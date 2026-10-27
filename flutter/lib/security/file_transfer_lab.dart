// Android/Windows one-shot FILE_OFFER interoperability with the Node LAN lab.
// Uses a user-picked XFile stream; never requests broad storage permissions.
// The enclosing channel MUST be the SAS-confirmed, signed 'file' intent AEAD
// channel. This fixture is not an audited production remote-access transport.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';

const maxLabFileBytes = 64 * 1024 * 1024;
const labFileChunkBytes = 3072; // keeps encrypted JSON lines under 8192 bytes
const fileResponseTimeout = Duration(seconds: 60);

// Per-frame deadlines must remain bounded even when supplied by a caller.
// A timeout does not cancel arbitrary Futures; abortable transports are closed
// on timeout and staging is rolled back by the receive error path.
const maxLabOperationTimeout = Duration(minutes: 2);

void _validateLabTimeout(Duration value, String name) {
  if (value <= Duration.zero || value > maxLabOperationTimeout) {
    throw ArgumentError.value(
      value, name, 'must be positive and no greater than 2 minutes');
  }
}

abstract class FileTransferChannel {
  Future<void> send(Map<String, dynamic> message);
  Future<Map<String, dynamic>> receive();
}

/// Optional hard-abort capability for channels whose underlying transport can
/// be closed synchronously. A timeout alone does not cancel channel.send().
abstract class AbortableFileTransferChannel implements FileTransferChannel {
  void abort();
}

class FileSendResult {
  final int bytes;
  final String sha256;
  const FileSendResult(this.bytes, this.sha256);
}

bool _isWindowsReservedDeviceName(String name) {
  // Win32 strips trailing ASCII spaces/dots from the device stem before the
  // extension (for example, "CON .txt"). Test the normalized stem, and include
  // the two console device aliases as well as the usual DOS device names.
  final stem = name.split('.').first.replaceFirst(RegExp(r'[ .]+$'), '');
  return RegExp(
    r'^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9¹²³]|LPT[1-9¹²³])$',
    caseSensitive: false,
  ).hasMatch(stem);
}

String validateLabFileName(String name) {
  if (name.isEmpty || name.length > 180 || name == '.' || name == '..' ||
      name.endsWith('.') || name.endsWith(' ') ||
      RegExp(r'[\\/<>:"|?*\x00-\x1f\x7f-\x9f\uFFFD]').hasMatch(name) ||
      RegExp(r'[\u00ad\u034f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]').hasMatch(name) ||
      RegExp(r'[\u{E0000}-\u{E007F}]', unicode: true).hasMatch(name) ||
      RegExp(r'^\.(liquidremote|netkit)-', caseSensitive: false).hasMatch(name) ||
      _isWindowsReservedDeviceName(name)) {
    throw const FormatException('Unsafe selected filename');
  }
  return name;
}

/// Re-chunk arbitrary picker/provider stream blocks into canonical protocol chunks.
/// This keeps the receiver's frame count and per-chunk work bounded even when a
/// content provider yields unusually small stream blocks.
Stream<List<int>> _fixedChunks(Stream<List<int>> source, int chunkSize) async* {
  final pending = <int>[];
  await for (final block in source) {
    var offset = 0;
    while (offset < block.length) {
      final remaining = chunkSize - pending.length;
      final available = block.length - offset;
      final take = remaining < available ? remaining : available;
      pending.addAll(block.sublist(offset, offset + take));
      offset += take;
      if (pending.length == chunkSize) {
        yield List<int>.from(pending);
        pending.clear();
      }
    }
  }
  if (pending.isNotEmpty) yield List<int>.from(pending);
}

/// Hashes a selected file incrementally without loading it into memory.
///
/// The idle timer is owned by this function rather than a StreamTransformer:
/// some provider/transformer combinations can pause upstream delivery while
/// waiting for the final digest, which can suppress a stream's own idle timer.
/// On timeout, cancel the provider subscription and fail before FILE_OFFER.
class _DigestValueSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest digest) {
    if (value != null) throw StateError('SHA-256 emitted more than one digest');
    value = digest;
  }

  @override
  void close() {}
}

Future<String> _hashFile(XFile file, Duration sourceReadTimeout) {
  final digestSink = _DigestValueSink();
  final digestInput = crypto.sha256.startChunkedConversion(digestSink);
  final result = Completer<String>();
  StreamSubscription<List<int>>? subscription;
  Timer? idleTimer;
  var settled = false;

  void cancelTimer() {
    idleTimer?.cancel();
    idleTimer = null;
  }

  void fail(Object error, StackTrace stack) {
    if (settled) return;
    settled = true;
    cancelTimer();
    final activeSubscription = subscription;
    if (activeSubscription != null) unawaited(activeSubscription.cancel());
    result.completeError(error, stack);
  }

  void armIdleTimer() {
    cancelTimer();
    idleTimer = Timer(sourceReadTimeout, () {
      fail(
        TimeoutException('Selected file stream stalled while hashing',
            sourceReadTimeout),
        StackTrace.current,
      );
    });
  }

  armIdleTimer();
  try {
    subscription = file.openRead().listen(
      (chunk) {
        if (settled) return;
        armIdleTimer();
        try {
          digestInput.add(chunk);
        } catch (error, stack) {
          fail(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) => fail(error, stack),
      onDone: () {
        if (settled) return;
        settled = true;
        cancelTimer();
        try {
          digestInput.close();
          final digest = digestSink.value;
          if (digest == null) throw StateError('SHA-256 produced no digest');
          result.complete(digest.toString());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      },
      cancelOnError: true,
    );
    // A synchronous stream may finish or fail before listen() returns.
    if (settled) unawaited(subscription.cancel());
  } catch (error, stack) {
    fail(error, stack);
  }
  return result.future;
}

/// The Node receiver must explicitly approve the signed file intent after
/// the six-digit pairing check. Each chunk is acknowledged before the next.
Future<FileSendResult> sendLabFile(
  FileTransferChannel channel,
  XFile file, {
  void Function(int bytes, int total, bool verified)? onProgress,
  // CrossFile.fromData ignores its 'name' argument on Dart IO; this override
  // lets in-memory protocol tests provide the original picker filename.
  String? selectedName,
  bool Function()? isSessionActive,
  Duration sendTimeout = fileResponseTimeout,
  Duration responseTimeout = fileResponseTimeout,
  Duration sourceReadTimeout = fileResponseTimeout,
}) async {
  _validateLabTimeout(sendTimeout, 'sendTimeout');
  _validateLabTimeout(responseTimeout, 'responseTimeout');
  _validateLabTimeout(sourceReadTimeout, 'sourceReadTimeout');
  var sendTimedOut = false;
  var channelAborted = false;
  void abortChannel() {
    if (channelAborted) return;
    channelAborted = true;
    final current = channel;
    if (current is AbortableFileTransferChannel) {
      try {
        current.abort();
      } catch (_) {
        // Preserve the original transfer failure if transport cleanup itself fails.
      }
    }
  }

  Future<void> sendFrame(Map<String, dynamic> message) async {
    try {
      await channel.send(message).timeout(sendTimeout);
    } on TimeoutException {
      sendTimedOut = true;
      abortChannel();
      rethrow;
    }
  }
  Future<Map<String, dynamic>> receiveFrame() async {
    try {
      return await channel.receive().timeout(responseTimeout);
    } on TimeoutException {
      // A timed-out Future does not cancel the underlying receive. Revoke the
      // transport when possible so the peer cannot keep a stalled session alive.
      abortChannel();
      rethrow;
    }
  }
  void requireActiveSession() {
    if (isSessionActive?.call() == false) {
      throw StateError('File transfer session revoked');
    }
  }
  late final String name;
  late final int size;
  late final String digest;
  try {
    requireActiveSession();
    name = validateLabFileName(selectedName ?? file.name);
    size = await file.length().timeout(sourceReadTimeout);
    if (size < 0 || size > maxLabFileBytes) {
      throw const FormatException('Selected file exceeds 64 MiB lab limit');
    }
    digest = await _hashFile(file, sourceReadTimeout);
    requireActiveSession();
    if (await file.length().timeout(sourceReadTimeout) != size) {
      throw StateError('Selected file changed while hashing');
    }
  } catch (_) {
    // Preflight may fail before FILE_OFFER (for example, a stalled SAF provider).
    // This file-intent channel is one-shot; never leave it open after failed preflight.
    abortChannel();
    rethrow;
  }

  late final Map<String, dynamic> approval;
  try {
    await sendFrame({
      'type': 'FILE_OFFER', 'name': name, 'bytes': size, 'sha256': digest,
    });
    approval = await receiveFrame();
  } catch (_) {
    // The initial offer/approval exchange is part of the one-shot intent too.
    // Non-timeout write/read errors must not leave a half-open channel waiting
    // for a peer that can no longer complete the handshake.
    abortChannel();
    rethrow;
  }
  if (approval['type'] == 'FILE_DENIED') {
    abortChannel();
    throw StateError('Receiver denied file transfer');
  }
  if (approval['type'] != 'FILE_READY') {
    abortChannel();
    throw StateError('Invalid file receiver approval');
  }

  var sent = 0;
  var seq = 0;
  var finalFrameAttempted = false;
  try {
  requireActiveSession();
  await for (final chunk in _fixedChunks(file.openRead().timeout(sourceReadTimeout), labFileChunkBytes)) {
    requireActiveSession();
    if (sent + chunk.length > size) {
      throw StateError('Selected file grew during transfer');
    }
    await sendFrame({
      'type': 'FILE_CHUNK', 'seq': seq, 'data': base64.encode(chunk),
    });
    final ack = await receiveFrame();
    if (ack['type'] != 'FILE_ACK' || ack['seq'] != seq) {
      throw StateError('Invalid file chunk acknowledgement');
    }
    requireActiveSession();
    sent += chunk.length;
    seq++;
    onProgress?.call(sent, size, false);
  }
  if (sent != size || await file.length().timeout(sourceReadTimeout) != size ||
      await _hashFile(file, sourceReadTimeout) != digest) {
    throw StateError('Selected file changed during transfer');
  }
  requireActiveSession();
  // Once FILE_END send starts, a timeout cannot prove the peer did not receive it.
  // Suppress FILE_CANCEL after this point because the receiver may already publish.
  finalFrameAttempted = true;
  await sendFrame({'type': 'FILE_END', 'bytes': sent, 'sha256': digest});
  final done = await receiveFrame();
  if (done['type'] != 'FILE_OK' ||
      done['bytes'] != sent || done['sha256'] != digest) {
    throw StateError('Receiver did not verify complete file');
  }
  onProgress?.call(sent, size, true);
  return FileSendResult(sent, digest);
  } catch (_) {
    // A sender that stops after FILE_READY must release the receiver's
    // private staging promptly, rather than waiting for the idle timeout.
    // A send timeout aborts an abortable transport: sending FILE_CANCEL on the
    // same stalled channel is not reliable and can race the original write.
    // Never cancel after FILE_END was attempted: the peer may have received it.
    if (!finalFrameAttempted && !sendTimedOut) {
      try { await sendFrame({'type': 'FILE_CANCEL'}); } catch (_) {}
    }
    // This is a one-shot file-intent channel. Revoke it after every failed
    // send path, including non-timeout errors while trying to send FILE_CANCEL
    // and errors after FILE_END where sending a cancel would be ambiguous.
    abortChannel();
    rethrow;
  }
}


/// One explicitly approved incoming file. The platform adapter MUST stage
/// privately and publish atomically only from commit(), never from write().
/// Android SAF and Windows destination adapters are separate acceptance work.
abstract class LabReceiveStaging {
  Future<void> write(List<int> bytes);
  Future<void> commit({required String name, required int bytes,
    required String sha256});
  Future<void> abort();

  /// Removes a just-published file if the session is revoked before FILE_OK.
  /// Platform providers may refuse deletion; callers must surface that failure.
  Future<void> rollbackCommitted() async {}

  /// Drops any rollback handle after the publication boundary is accepted.
  Future<void> finalizeCommitted() async {}
}

class LabIncomingOffer {
  final String name;
  final int bytes;
  final String sha256;
  const LabIncomingOffer(this.name, this.bytes, this.sha256);
}

/// Reports both the transfer failure and a failed attempt to remove private staging.
/// Cleanup failure must never silently replace the original receive-side error.
class FileTransferCleanupException implements Exception {
  final Object transferError;
  final Object cleanupError;

  const FileTransferCleanupException(this.transferError, this.cleanupError);

  @override
  String toString() =>
      'FileTransferCleanupException: transfer failed ($transferError); '
      'staging cleanup also failed ($cleanupError)';
}

/// Dart/Node FILE_OFFER interoperability. Caller must supply a paired,
/// signed-file-intent AEAD channel and a platform-specific transactional sink.
/// No file is published on denial, truncation, bad framing or hash mismatch.
Future<FileSendResult?> receiveLabFile(
  FileTransferChannel channel,
  Map<String, dynamic> offer, {
  required Future<bool> Function(LabIncomingOffer) approve,
  required Future<LabReceiveStaging> Function(LabIncomingOffer) createStaging,
  void Function(int bytes, int total, bool verified)? onProgress,
  Duration stagingTimeout = fileResponseTimeout,
  Duration consentTimeout = fileResponseTimeout,
  bool Function()? isSessionActive,
  Duration sendTimeout = fileResponseTimeout,
  Duration responseTimeout = fileResponseTimeout,
}) async {
  _validateLabTimeout(sendTimeout, 'sendTimeout');
  _validateLabTimeout(responseTimeout, 'responseTimeout');
  _validateLabTimeout(consentTimeout, 'consentTimeout');
  _validateLabTimeout(stagingTimeout, 'stagingTimeout');
  void abortChannel() {
    final current = channel;
    if (current is AbortableFileTransferChannel) {
      try {
        current.abort();
      } catch (_) {
        // Preserve the transfer/timeout failure if transport cleanup itself fails.
      }
    }
  }
  Future<void> sendFrame(Map<String, dynamic> message) async {
    try {
      await channel.send(message).timeout(sendTimeout);
    } on TimeoutException {
      abortChannel();
      rethrow;
    }
  }
  Future<Map<String, dynamic>> receiveFrame() async {
    try {
      return await channel.receive().timeout(responseTimeout);
    } on TimeoutException {
      // Revoke the channel on a stalled peer response; staging is rolled back
      // by receiveLabFile's error path below. A faulty abort implementation
      // must not replace the TimeoutException that triggered cleanup.
      abortChannel();
      rethrow;
    }
  }
  void requireActiveSession() {
    if (isSessionActive?.call() == false) {
      throw StateError('File transfer session revoked');
    }
  }
  Future<void> denyAndAbort() async {
    try {
      await sendFrame({'type': 'FILE_DENIED'});
    } catch (_) {
      // Malformed input must still close the one-shot channel if notification fails.
    } finally {
      abortChannel();
    }
  }

  try {
    requireActiveSession();
  } catch (_) {
    abortChannel();
    rethrow;
  }

  late final String name;
  late final int size;
  late final String expected;
  late final LabIncomingOffer request;
  try {
    if (offer['type'] != 'FILE_OFFER' ||
        offer['name'] is! String ||
        offer['bytes'] is! int ||
        offer['sha256'] is! String) {
      throw const FormatException('Invalid incoming file offer');
    }
    name = validateLabFileName(offer['name'] as String);
    size = offer['bytes'] as int;
    expected = offer['sha256'] as String;
    final digestIsLowerHex = expected.length == 64 && expected.codeUnits.every((unit) =>
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66));
    if (size < 0 || size > maxLabFileBytes || !digestIsLowerHex) {
      throw const FormatException('Invalid incoming file size or digest');
    }
    request = LabIncomingOffer(name, size, expected);
  } catch (_) {
    // A malformed offer is terminal for this one-shot intent channel; don't
    // leave the transport alive while the caller tears down the failed request.
    await denyAndAbort();
    rethrow;
  }
  bool accepted;
  try {
    accepted = await approve(request).timeout(consentTimeout);
    requireActiveSession();
  } catch (_) {
    // A cancelled picker, failed prompt, or revoked session must not strand
    // the sender waiting for FILE_READY. Deny first when possible, then close
    // this one-shot file-intent channel so a late UI completion cannot revive it.
    try { await sendFrame({'type': 'FILE_DENIED'}); } catch (_) {}
    if (channel is AbortableFileTransferChannel) channel.abort();
    rethrow;
  }
  if (!accepted) {
    // Explicit denial is terminal for this one-shot file-intent channel too.
    // Always revoke it, even if notifying the peer fails for a non-timeout reason.
    try {
      await sendFrame({'type': 'FILE_DENIED'});
    } finally {
      if (channel is AbortableFileTransferChannel) channel.abort();
    }
    return null;
  }

  // A failed SAF provider/open must be denied BEFORE FILE_READY. No staging
  // exists yet, so there is nothing to publish or abort.
  late final LabReceiveStaging staging;
  // Future.timeout does not cancel the underlying async native/desktop
  // allocation. A late completion MUST abort its staging to avoid orphaned
  // private files or SAF sessions after FILE_DENIED was sent.
  final pendingStaging =
      Future<LabReceiveStaging>.sync(() => createStaging(request));
  try {
    staging = await pendingStaging.timeout(stagingTimeout);
  } catch (_) {
    unawaited(pendingStaging.then((lateStage) async {
      try { await lateStage.abort(); } catch (_) { /* best effort cleanup */ }
    }, onError: (Object _, StackTrace __) {}));
    // A failed or timed-out SAF/desktop staging allocation is terminal for this
    // one-shot intent. Deny best-effort and revoke the channel even if sending
    // FILE_DENIED itself fails, matching malformed-offer and consent failures.
    await denyAndAbort();
    rethrow;
  }
  var committed = false;
  Object? transferFailure;
  StackTrace? transferFailureStack;
  final sink = _LabDigestSink();
  final hasher = crypto.sha256.startChunkedConversion(sink);
  var count = 0;
  var sequence = 0;
  try {
    // Native staging may finish after Stop; abort before FILE_READY.
    requireActiveSession();
    await sendFrame({'type': 'FILE_READY'});
    while (true) {
      final frame = await receiveFrame();
      requireActiveSession();
      if (frame['type'] == 'FILE_CANCEL') {
        throw StateError('Sender cancelled incoming file');
      }
      if (frame['type'] == 'FILE_END') {
        hasher.close();
        final actual = sink.value?.toString();
        if (count != size || frame['bytes'] != count ||
            frame['sha256'] != expected || actual != expected) {
          throw StateError('Incoming file size or SHA-256 mismatch');
        }
        // Native commit itself cannot be interrupted on all SAF providers.
        requireActiveSession();
        await staging.commit(name: name, bytes: count, sha256: expected);
        // SAF/desktop commit can be non-cancellable. If Stop/revoke wins while
        // commit is awaiting, remove the just-published output before reporting
        // failure. If rollback fails, surface that explicitly: the file may remain.
        try {
          requireActiveSession();
        } catch (failure, stackTrace) {
          try {
            await staging.rollbackCommitted();
          } catch (rollbackFailure) {
            Error.throwWithStackTrace(
              StateError('File session was revoked after publication and rollback failed: $rollbackFailure'),
              stackTrace,
            );
          }
          Error.throwWithStackTrace(failure, stackTrace);
        }
        // Once the active-session check passes, publication is accepted. A lost
        // FILE_OK must not delete a file the sender may already believe is saved.
        committed = true;
        try {
          await sendFrame({
            'type': 'FILE_OK', 'bytes': count, 'sha256': expected,
          });
        } finally {
          // This only drops a rollback handle; it does not touch the saved file.
          try { await staging.finalizeCommitted(); } catch (_) { /* best-effort handle cleanup */ }
        }
        onProgress?.call(count, size, true);
        return FileSendResult(count, expected);
      }
      final encoded = frame['data'];
      if (frame['type'] != 'FILE_CHUNK' ||
          frame['seq'] is! int || frame['seq'] != sequence ||
          encoded is! String || encoded.isEmpty ||
          encoded.length > ((labFileChunkBytes + 2) ~/ 3) * 4 ||
          !_canonicalLabBase64.hasMatch(encoded)) {
        throw const FormatException('Invalid incoming file chunk');
      }
      final bytes = base64.decode(encoded);
      final remaining = size - count;
      final canonicalLength =
          remaining < labFileChunkBytes ? remaining : labFileChunkBytes;
      if (bytes.isEmpty || bytes.length != canonicalLength) {
        throw StateError('Incoming file chunk has non-canonical size');
      }
      requireActiveSession();
      await staging.write(bytes);
      requireActiveSession();
      hasher.add(bytes);
      count += bytes.length;
      await sendFrame({'type': 'FILE_ACK', 'seq': sequence});
      sequence++;
      onProgress?.call(count, size, false);
    }
  } catch (error, stackTrace) {
    transferFailure = error;
    transferFailureStack = stackTrace;
    // Any failed receive-side operation makes this one-shot intent terminal.
    // In particular, non-timeout socket/provider errors must not leave the
    // peer's channel alive while private staging is being rolled back.
    abortChannel();
    rethrow;
  } finally {
    if (!committed) {
      try {
        await staging.abort();
      } catch (cleanupError, cleanupStack) {
        final originalError = transferFailure;
        final originalStack = transferFailureStack;
        if (originalError != null && originalStack != null) {
          Error.throwWithStackTrace(
            FileTransferCleanupException(originalError, cleanupError),
            originalStack,
          );
        }
        Error.throwWithStackTrace(cleanupError, cleanupStack);
      }
    }
  }
}

final RegExp _canonicalLabBase64 = RegExp(
  r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
);

class _LabDigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) { value = data; }
  @override
  void close() {}
}
