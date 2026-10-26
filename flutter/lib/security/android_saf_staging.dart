// Android-only, user-selected SAF tree receiver for signed FILE_OFFER sessions.
// No broad storage permission, persisted tree grant, or unattended writes.
// Native Kotlin keeps bytes in app-private cache until SHA-256 is verified.
import 'package:flutter/services.dart';

import 'file_transfer_lab.dart';

class AndroidSafLabReceiveStaging implements LabReceiveStaging {
  static const channelName = 'liquidremote/android_saf_receiver';
  static const MethodChannel _defaultChannel = MethodChannel(channelName);
  final MethodChannel _channel;
  final String _id;
  bool _closed = false;
  String? _committedUri;

  AndroidSafLabReceiveStaging._(this._channel, this._id);

  /// Every incoming file requires a fresh Android ACTION_OPEN_DOCUMENT_TREE
  /// selection. The returned URI is not persisted or exposed to the sender.
  static Future<String?> pickTree({MethodChannel? channel}) async {
    final selected = await (channel ?? _defaultChannel)
        .invokeMethod<String>('pickTree');
    return selected == null || selected.isEmpty ? null : selected;
  }

  static Future<AndroidSafLabReceiveStaging> create(
    String selectedTree, LabIncomingOffer offer, {
    MethodChannel? channel,
  }) async {
    validateLabFileName(offer.name);
    if (offer.bytes < 0 || offer.bytes > maxLabFileBytes ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(offer.sha256)) {
      throw const FormatException('Invalid incoming SAF offer');
    }
    final native = channel ?? _defaultChannel;
    final id = await native.invokeMethod<String>('begin', {
      'tree': selectedTree,
      'name': offer.name,
      'bytes': offer.bytes,
      'sha256': offer.sha256,
    });
    if (id == null || id.isEmpty) {
      throw StateError('Android SAF staging did not open');
    }
    return AndroidSafLabReceiveStaging._(native, id);
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (_closed) throw StateError('Android SAF staging already closed');
    if (bytes.isEmpty || bytes.length > labFileChunkBytes) {
      throw StateError('Invalid SAF transfer chunk');
    }
    await _channel.invokeMethod<void>('write', {
      'id': _id,
      'data': Uint8List.fromList(bytes),
    });
  }

  @override
  Future<void> commit({
    required String name,
    required int bytes,
    required String sha256,
  }) async {
    if (_closed) throw StateError('Android SAF staging already closed');
    // The native implementation rehashes the private file and reads back the
    // SAF temp document before renaming to a unique final name.
    final publishedUri = await _channel.invokeMethod<String>('commit', {
      'id': _id,
      'name': validateLabFileName(name),
      'bytes': bytes,
      'sha256': sha256,
    });
    if (publishedUri == null || publishedUri.isEmpty) {
      throw StateError('Android SAF commit did not return the published document URI');
    }
    _committedUri = publishedUri;
    _closed = true;
  }

  @override
  Future<void> rollbackCommitted() async {
    if (_committedUri == null) return;
    await _channel.invokeMethod<void>('rollbackCommitted', {'id': _id});
    _committedUri = null;
  }

  @override
  Future<void> finalizeCommitted() async {
    if (_committedUri == null) return;
    await _channel.invokeMethod<void>('finalizeCommitted', {'id': _id});
    _committedUri = null;
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    await _channel.invokeMethod<void>('abort', {'id': _id});
  }
}
