// Transactional desktop receiver for the explicitly approved FILE_OFFER lab.
// This is for dart:io desktop folders (Windows first), NOT Android SAF.
// Files are staged in a random sibling directory and made visible under a
// unique "Received-..." folder only after protocol SHA-256 verification.
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'file_transfer_lab.dart';

class DesktopLabReceiveStaging implements LabReceiveStaging {
  final Directory _destination;
  final Directory _staging;
  final File _payload;
  final String _expectedName;
  RandomAccessFile? _writer;
  bool _committed = false;
  bool _aborted = false;
  int _written = 0;
  String? publishedPath;

  DesktopLabReceiveStaging._(
    this._destination, this._staging, this._payload,
    this._expectedName, this._writer,
  );

  /// The folder must be chosen by the local receiver, never by the peer.
  /// Staging stays on the same filesystem to avoid cross-device copy/publish.
  static Future<DesktopLabReceiveStaging> create(
      Directory destination, LabIncomingOffer offer) async {
    final name = validateLabFileName(offer.name);
    if (!await destination.exists() ||
        await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw StateError('Receiver must choose an existing non-link folder');
    }
    final staging = await destination.createTemp('.liquidremote-stage-');
    try {
      final payload = File('${staging.path}${Platform.pathSeparator}payload.part');
      await payload.create(exclusive: true);
      final writer = await payload.open(mode: FileMode.writeOnly);
      return DesktopLabReceiveStaging._(
          destination, staging, payload, name, writer);
    } catch (_) {
      await staging.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (_committed || _aborted || _writer == null) {
      throw StateError('Receiver staging is closed');
    }
    if (bytes.isEmpty || bytes.length > labFileChunkBytes ||
        _written + bytes.length > maxLabFileBytes) {
      throw StateError('Invalid desktop staging chunk');
    }
    await _writer!.writeFrom(bytes);
    _written += bytes.length;
  }

  @override
  Future<void> commit({
    required String name, required int bytes, required String sha256,
  }) async {
    if (_committed || _aborted || _writer == null) {
      throw StateError('Receiver staging is closed');
    }
    if (validateLabFileName(name) != _expectedName ||
        bytes != _written || bytes < 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw StateError('Desktop staging metadata mismatch');
    }
    await _writer!.flush();
    await _writer!.close();
    _writer = null;
    if (await _payload.length() != bytes ||
        (await crypto.sha256.bind(_payload.openRead()).first).toString() !=
            sha256) {
      throw StateError('Desktop staged payload changed before publication');
    }
    // No existing user file is overwritten. A random unique destination
    // *folder* also avoids case-insensitive Windows filename collisions.
    // Dart cannot guarantee no hostile cross-process filesystem races.
    final stageSuffix = _staging.uri.pathSegments
        .where((segment) => segment.isNotEmpty).last
        .replaceFirst('.liquidremote-stage-', '');
    final folder = 'Received-${DateTime.now().toUtc().microsecondsSinceEpoch}-$stageSuffix';
    final finalFolder = Directory(
        '${_destination.path}${Platform.pathSeparator}$folder');
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    final finalName = '${_staging.path}${Platform.pathSeparator}$name';
    await _payload.rename(finalName);
    // Directory rename is same-volume; a failed rename is handled by abort().
    await _staging.rename(finalFolder.path);
    _committed = true;
    publishedPath = '${finalFolder.path}${Platform.pathSeparator}$name';
  }

  @override
  Future<void> abort() async {
    if (_committed || _aborted) return;
    _aborted = true;
    final writer = _writer;
    _writer = null;
    if (writer != null) {
      try { await writer.close(); } catch (_) { /* continue cleanup */ }
    }
    if (await _staging.exists()) {
      await _staging.delete(recursive: true);
    }
  }
}

/// Wires the existing consent + authenticated-channel receiver to real
/// desktop storage. The caller MUST pass an already paired AEAD file channel.
Future<FileSendResult?> receiveLabFileToDesktopFolder(
  FileTransferChannel channel,
  Map<String, dynamic> offer, {
  required Directory destination,
  required Future<bool> Function(LabIncomingOffer) approve,
  void Function(int bytes, int total, bool verified)? onProgress,
}) => receiveLabFile(
  channel, offer,
  approve: approve,
  createStaging: (request) =>
      DesktopLabReceiveStaging.create(destination, request),
  onProgress: onProgress,
);
