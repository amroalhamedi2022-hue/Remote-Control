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
  final int _expectedBytes;
  final String _expectedSha256;
  RandomAccessFile? _writer;
  bool _committed = false;
  bool _aborted = false;
  bool _finalized = false;
  String? _publishedFolderPath;
  String? _publishedFilePath;
  int _written = 0;
  String? publishedPath;

  DesktopLabReceiveStaging._(
    this._destination, this._staging, this._payload,
    this._expectedName, this._expectedBytes, this._expectedSha256, this._writer,
  );

  /// Recheck the publication parent at commit time, not only when the user picks it.
  /// This catches a destination path replaced while the peer was still sending chunks.
  /// It narrows path-substitution risk; Dart does not expose an atomic no-follow rename.
  Future<void> _assertPublishLocationSafe() async {
    final destinationType = await FileSystemEntity.type(
        _destination.path, followLinks: false);
    if (destinationType != FileSystemEntityType.directory) {
      throw StateError('Receiver destination changed before publication');
    }
    if (_staging.parent.path != _destination.path) {
      throw StateError('Private staging folder escaped the receiver destination');
    }
    final stagingType = await FileSystemEntity.type(
        _staging.path, followLinks: false);
    if (stagingType != FileSystemEntityType.directory) {
      throw StateError('Private staging folder changed before publication');
    }
  }

  /// The folder must be chosen by the local receiver, never by the peer.
  /// Staging stays on the same filesystem to avoid cross-device copy/publish.
  static Future<DesktopLabReceiveStaging> create(
      Directory destination, LabIncomingOffer offer) async {
    final name = validateLabFileName(offer.name);
    if (offer.bytes < 0 || offer.bytes > maxLabFileBytes ||
        !RegExp(r'^[0-9a-f]{64}
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
          destination, staging, payload, name, offer.bytes, offer.sha256, writer);
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
    if (bytes.isEmpty || bytes.length > labFileChunkBytes) {
      throw StateError('Invalid desktop staging chunk');
    }
    if (_written + bytes.length > _expectedBytes) {
      throw StateError('Desktop staging exceeded offered byte count');
    }
    if (_written + bytes.length > maxLabFileBytes) {
      throw StateError('Desktop staging exceeded the global byte limit');
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
        bytes != _expectedBytes || bytes != _written || bytes < 0 ||
        sha256 != _expectedSha256 ||
        !RegExp(r'^[0-9a-f]{64}
      throw StateError('Desktop staging metadata mismatch');
    }
    await _assertPublishLocationSafe();
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
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    final finalName = '${_staging.path}${Platform.pathSeparator}$name';
    await _payload.rename(finalName);
    // Recheck after payload rename and immediately before the directory publication.
    // A hostile process can still race the final check; atomic no-follow rename is not
    // available through Dart's portable filesystem API.
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    await _staging.rename(finalFolder.path);
    _committed = true;
    _publishedFolderPath = finalFolder.path;
    _publishedFilePath = '${finalFolder.path}${Platform.pathSeparator}$name';
    publishedPath = _publishedFilePath;
  }

  @override
  Future<void> rollbackCommitted() async {
    if (_finalized) {
      throw StateError('Desktop publication already crossed the FILE_OK boundary');
    }
    if (!_committed) return;
    final folderPath = _publishedFolderPath;
    final filePath = _publishedFilePath;
    if (folderPath == null || filePath == null) {
      throw StateError('Published desktop output has no rollback path');
    }
    if (!filePath.startsWith('$folderPath${Platform.pathSeparator}')) {
      throw StateError('Published desktop rollback path escaped its private folder');
    }
    // Rollback is destructive, so re-check every parent before touching the child.
    // In particular, do not follow a published-folder path that was replaced by a symlink.
    // This narrows accidental/path-substitution risk; Dart does not provide an atomic
    // no-follow unlink-at API, so hostile cross-process TOCTOU races remain out of scope.
    final destinationType = await FileSystemEntity.type(
        _destination.path, followLinks: false);
    if (destinationType != FileSystemEntityType.directory) {
      throw StateError('Receiver destination changed before rollback');
    }
    final folderType = await FileSystemEntity.type(
        folderPath, followLinks: false);
    if (folderType != FileSystemEntityType.directory) {
      throw StateError('Published desktop folder was replaced or is no longer a directory');
    }
    if (Directory(folderPath).parent.path != _destination.path) {
      throw StateError('Published desktop folder is no longer a direct child of the receiver destination');
    }
    // Remove only the file created by this transfer. Never recursively delete
    // the folder: the user may have added another file while publication awaited.
    final type = await FileSystemEntity.type(filePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Published desktop file disappeared before rollback');
    }
    if (type == FileSystemEntityType.link) {
      await Link(filePath).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(filePath).delete();
    } else {
      throw StateError('Published desktop target is no longer a regular file');
    }
    // The generated folder is private to this transfer. Delete it only if still
    // empty; preserve unrelated files if the user added anything after commit.
    try { await Directory(folderPath).delete(); } on FileSystemException { /* non-empty or provider denied cleanup */ }
    _committed = false;
    _aborted = true;
    _publishedFolderPath = null;
    _publishedFilePath = null;
    publishedPath = null;
  }

  @override
  Future<void> finalizeCommitted() async {
    if (_committed) {
      _finalized = true;
      _publishedFolderPath = null;
      _publishedFilePath = null;
    }
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
).hasMatch(offer.sha256)) {
      throw const FormatException('Invalid desktop receive offer');
    }
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
    await _assertPublishLocationSafe();
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
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    final finalName = '${_staging.path}${Platform.pathSeparator}$name';
    await _payload.rename(finalName);
    // Recheck after payload rename and immediately before the directory publication.
    // A hostile process can still race the final check; atomic no-follow rename is not
    // available through Dart's portable filesystem API.
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    await _staging.rename(finalFolder.path);
    _committed = true;
    _publishedFolderPath = finalFolder.path;
    _publishedFilePath = '${finalFolder.path}${Platform.pathSeparator}$name';
    publishedPath = _publishedFilePath;
  }

  @override
  Future<void> rollbackCommitted() async {
    if (_finalized) {
      throw StateError('Desktop publication already crossed the FILE_OK boundary');
    }
    if (!_committed) return;
    final folderPath = _publishedFolderPath;
    final filePath = _publishedFilePath;
    if (folderPath == null || filePath == null) {
      throw StateError('Published desktop output has no rollback path');
    }
    if (!filePath.startsWith('$folderPath${Platform.pathSeparator}')) {
      throw StateError('Published desktop rollback path escaped its private folder');
    }
    // Rollback is destructive, so re-check every parent before touching the child.
    // In particular, do not follow a published-folder path that was replaced by a symlink.
    // This narrows accidental/path-substitution risk; Dart does not provide an atomic
    // no-follow unlink-at API, so hostile cross-process TOCTOU races remain out of scope.
    final destinationType = await FileSystemEntity.type(
        _destination.path, followLinks: false);
    if (destinationType != FileSystemEntityType.directory) {
      throw StateError('Receiver destination changed before rollback');
    }
    final folderType = await FileSystemEntity.type(
        folderPath, followLinks: false);
    if (folderType != FileSystemEntityType.directory) {
      throw StateError('Published desktop folder was replaced or is no longer a directory');
    }
    if (Directory(folderPath).parent.path != _destination.path) {
      throw StateError('Published desktop folder is no longer a direct child of the receiver destination');
    }
    // Remove only the file created by this transfer. Never recursively delete
    // the folder: the user may have added another file while publication awaited.
    final type = await FileSystemEntity.type(filePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Published desktop file disappeared before rollback');
    }
    if (type == FileSystemEntityType.link) {
      await Link(filePath).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(filePath).delete();
    } else {
      throw StateError('Published desktop target is no longer a regular file');
    }
    // The generated folder is private to this transfer. Delete it only if still
    // empty; preserve unrelated files if the user added anything after commit.
    try { await Directory(folderPath).delete(); } on FileSystemException { /* non-empty or provider denied cleanup */ }
    _committed = false;
    _aborted = true;
    _publishedFolderPath = null;
    _publishedFilePath = null;
    publishedPath = null;
  }

  @override
  Future<void> finalizeCommitted() async {
    if (_committed) {
      _finalized = true;
      _publishedFolderPath = null;
      _publishedFilePath = null;
    }
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
).hasMatch(sha256)) {
      throw StateError('Desktop staging metadata mismatch');
    }
    await _assertPublishLocationSafe();
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
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    final finalName = '${_staging.path}${Platform.pathSeparator}$name';
    await _payload.rename(finalName);
    // Recheck after payload rename and immediately before the directory publication.
    // A hostile process can still race the final check; atomic no-follow rename is not
    // available through Dart's portable filesystem API.
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    await _staging.rename(finalFolder.path);
    _committed = true;
    _publishedFolderPath = finalFolder.path;
    _publishedFilePath = '${finalFolder.path}${Platform.pathSeparator}$name';
    publishedPath = _publishedFilePath;
  }

  @override
  Future<void> rollbackCommitted() async {
    if (_finalized) {
      throw StateError('Desktop publication already crossed the FILE_OK boundary');
    }
    if (!_committed) return;
    final folderPath = _publishedFolderPath;
    final filePath = _publishedFilePath;
    if (folderPath == null || filePath == null) {
      throw StateError('Published desktop output has no rollback path');
    }
    if (!filePath.startsWith('$folderPath${Platform.pathSeparator}')) {
      throw StateError('Published desktop rollback path escaped its private folder');
    }
    // Rollback is destructive, so re-check every parent before touching the child.
    // In particular, do not follow a published-folder path that was replaced by a symlink.
    // This narrows accidental/path-substitution risk; Dart does not provide an atomic
    // no-follow unlink-at API, so hostile cross-process TOCTOU races remain out of scope.
    final destinationType = await FileSystemEntity.type(
        _destination.path, followLinks: false);
    if (destinationType != FileSystemEntityType.directory) {
      throw StateError('Receiver destination changed before rollback');
    }
    final folderType = await FileSystemEntity.type(
        folderPath, followLinks: false);
    if (folderType != FileSystemEntityType.directory) {
      throw StateError('Published desktop folder was replaced or is no longer a directory');
    }
    if (Directory(folderPath).parent.path != _destination.path) {
      throw StateError('Published desktop folder is no longer a direct child of the receiver destination');
    }
    // Remove only the file created by this transfer. Never recursively delete
    // the folder: the user may have added another file while publication awaited.
    final type = await FileSystemEntity.type(filePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Published desktop file disappeared before rollback');
    }
    if (type == FileSystemEntityType.link) {
      await Link(filePath).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(filePath).delete();
    } else {
      throw StateError('Published desktop target is no longer a regular file');
    }
    // The generated folder is private to this transfer. Delete it only if still
    // empty; preserve unrelated files if the user added anything after commit.
    try { await Directory(folderPath).delete(); } on FileSystemException { /* non-empty or provider denied cleanup */ }
    _committed = false;
    _aborted = true;
    _publishedFolderPath = null;
    _publishedFilePath = null;
    publishedPath = null;
  }

  @override
  Future<void> finalizeCommitted() async {
    if (_committed) {
      _finalized = true;
      _publishedFolderPath = null;
      _publishedFilePath = null;
    }
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
).hasMatch(offer.sha256)) {
      throw const FormatException('Invalid desktop receive offer');
    }
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
    await _assertPublishLocationSafe();
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
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    final finalName = '${_staging.path}${Platform.pathSeparator}$name';
    await _payload.rename(finalName);
    // Recheck after payload rename and immediately before the directory publication.
    // A hostile process can still race the final check; atomic no-follow rename is not
    // available through Dart's portable filesystem API.
    await _assertPublishLocationSafe();
    if (await FileSystemEntity.type(finalFolder.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Receiver destination collision');
    }
    await _staging.rename(finalFolder.path);
    _committed = true;
    _publishedFolderPath = finalFolder.path;
    _publishedFilePath = '${finalFolder.path}${Platform.pathSeparator}$name';
    publishedPath = _publishedFilePath;
  }

  @override
  Future<void> rollbackCommitted() async {
    if (_finalized) {
      throw StateError('Desktop publication already crossed the FILE_OK boundary');
    }
    if (!_committed) return;
    final folderPath = _publishedFolderPath;
    final filePath = _publishedFilePath;
    if (folderPath == null || filePath == null) {
      throw StateError('Published desktop output has no rollback path');
    }
    if (!filePath.startsWith('$folderPath${Platform.pathSeparator}')) {
      throw StateError('Published desktop rollback path escaped its private folder');
    }
    // Rollback is destructive, so re-check every parent before touching the child.
    // In particular, do not follow a published-folder path that was replaced by a symlink.
    // This narrows accidental/path-substitution risk; Dart does not provide an atomic
    // no-follow unlink-at API, so hostile cross-process TOCTOU races remain out of scope.
    final destinationType = await FileSystemEntity.type(
        _destination.path, followLinks: false);
    if (destinationType != FileSystemEntityType.directory) {
      throw StateError('Receiver destination changed before rollback');
    }
    final folderType = await FileSystemEntity.type(
        folderPath, followLinks: false);
    if (folderType != FileSystemEntityType.directory) {
      throw StateError('Published desktop folder was replaced or is no longer a directory');
    }
    if (Directory(folderPath).parent.path != _destination.path) {
      throw StateError('Published desktop folder is no longer a direct child of the receiver destination');
    }
    // Remove only the file created by this transfer. Never recursively delete
    // the folder: the user may have added another file while publication awaited.
    final type = await FileSystemEntity.type(filePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Published desktop file disappeared before rollback');
    }
    if (type == FileSystemEntityType.link) {
      await Link(filePath).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(filePath).delete();
    } else {
      throw StateError('Published desktop target is no longer a regular file');
    }
    // The generated folder is private to this transfer. Delete it only if still
    // empty; preserve unrelated files if the user added anything after commit.
    try { await Directory(folderPath).delete(); } on FileSystemException { /* non-empty or provider denied cleanup */ }
    _committed = false;
    _aborted = true;
    _publishedFolderPath = null;
    _publishedFilePath = null;
    publishedPath = null;
  }

  @override
  Future<void> finalizeCommitted() async {
    if (_committed) {
      _finalized = true;
      _publishedFolderPath = null;
      _publishedFilePath = null;
    }
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
