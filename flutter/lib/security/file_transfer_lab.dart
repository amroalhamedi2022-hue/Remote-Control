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

String validateLabFileName(String name) {
  if (name.isEmpty || name.length > 180 || name == '.' || name == '..' ||
      name.endsWith('.') || name.endsWith(' ') ||
      RegExp(r'[\\/<>:"|?*\x00-\x1f\x7f-\x9f\uFFFD]').hasMatch(name) ||
      RegExp(r'[\u00ad\u034f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]').hasMatch(name) ||
      RegExp(r'[\u{E0000}-\u{E007F}]', unicode: true).hasMatch(name) ||
      RegExp(r'^\.(liquidremote|netkit)-', caseSensitive: false).hasMatch(name) ||
      RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(\.|$)',
          caseSensitive: false).hasMatch(name)) {
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

/// Hashes the stream without loading a large SAF document into memory.
Future<String> _hashFile(XFile file) async =>
    (await crypto.sha256.bind(file.openRead()).first).toString();

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
}) async {
  if (sendTimeout <= Duration.zero) {
    throw ArgumentError.value(sendTimeout, 'sendTimeout', 'must be positive');
  }
  if (responseTimeout <= Duration.zero) {
    throw ArgumentError.value(responseTimeout, 'responseTimeout', 'must be positive');
  }
  var sendTimedOut = false;
  Future<void> sendFrame(Map<String, dynamic> message) async {
    try {
      await channel.send(message).timeout(sendTimeout);
    } on TimeoutException {
      sendTimedOut = true;
      if (channel is AbortableFileTransferChannel) channel.abort();
      rethrow;
    }
  }
  Future<Map<String, dynamic>> receiveFrame() async {
    try {
      return await channel.receive().timeout(responseTimeout);
    } on TimeoutException {
      // A timed-out Future does not cancel the underlying receive. Revoke the
      // transport when possible so the peer cannot keep a stalled session alive.
      if (channel is AbortableFileTransferChannel) channel.abort();
      rethrow;
    }
  }
  void requireActiveSession() {
    if (isSessionActive?.call() == false) {
      throw StateError('File transfer session revoked');
    }
  }
  requireActiveSession();
  final name = validateLabFileName(selectedName ?? file.name);
  final size = await file.length();
  if (size < 0 || size > maxLabFileBytes) {
    throw const FormatException('Selected file exceeds 64 MiB lab limit');
  }
  final digest = await _hashFile(file);
  requireActiveSession();
  if (await file.length() != size) {
    throw StateError('Selected file changed while hashing');
  }

  await sendFrame({
    'type': 'FILE_OFFER', 'name': name, 'bytes': size, 'sha256': digest,
  });
  final approval = await receiveFrame();
  if (approval['type'] == 'FILE_DENIED') {
    throw StateError('Receiver denied file transfer');
  }
  if (approval['type'] != 'FILE_READY') {
    throw StateError('Invalid file receiver approval');
  }

  var sent = 0;
  var seq = 0;
  var finalFrameAttempted = false;
  try {
  requireActiveSession();
  await for (final chunk in _fixedChunks(file.openRead(), labFileChunkBytes)) {
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
  if (sent != size || await file.length() != size ||
      await _hashFile(file) != digest) {
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
  if (sendTimeout <= Duration.zero) {
    throw ArgumentError.value(sendTimeout, 'sendTimeout', 'must be positive');
  }
  if (responseTimeout <= Duration.zero) {
    throw ArgumentError.value(responseTimeout, 'responseTimeout', 'must be positive');
  }
  if (consentTimeout <= Duration.zero) {
    throw ArgumentError.value(consentTimeout, 'consentTimeout', 'must be positive');
  }
  if (stagingTimeout <= Duration.zero) {
    throw ArgumentError.value(stagingTimeout, 'stagingTimeout', 'must be positive');
  }
  Future<void> sendFrame(Map<String, dynamic> message) async {
    try {
      await channel.send(message).timeout(sendTimeout);
    } on TimeoutException {
      if (channel is AbortableFileTransferChannel) channel.abort();
      rethrow;
    }
  }
  Future<Map<String, dynamic>> receiveFrame() async {
    try {
      return await channel.receive().timeout(responseTimeout);
    } on TimeoutException {
      // Revoke the channel on a stalled peer response; staging is rolled back
      // by receiveLabFile's error path below.
      if (channel is AbortableFileTransferChannel) channel.abort();
      rethrow;
    }
  }
  void requireActiveSession() {
    if (isSessionActive?.call() == false) {
      throw StateError('File transfer session revoked');
    }
  }
  requireActiveSession();
  if (offer['type'] != 'FILE_OFFER' ||
      offer['name'] is! String ||
      offer['bytes'] is! int ||
      offer['sha256'] is! String) {
    throw const FormatException('Invalid incoming file offer');
  }
  final name = validateLabFileName(offer['name'] as String);
  final size = offer['bytes'] as int;
  final expected = offer['sha256'] as String;
  if (size < 0 || size > maxLabFileBytes ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
    throw const FormatException('Invalid incoming file size or digest');
  }
  final request = LabIncomingOffer(name, size, expected);
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
    await sendFrame({'type': 'FILE_DENIED'});
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
    try { await sendFrame({'type': 'FILE_DENIED'}); } catch (_) {}
    rethrow;
  }
  var committed = false;
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
  } finally {
    if (!committed) await staging.abort();
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
