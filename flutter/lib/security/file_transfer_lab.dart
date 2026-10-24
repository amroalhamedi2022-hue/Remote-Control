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
      RegExp(r'^\.(liquidremote|netkit)-', caseSensitive: false).hasMatch(name) ||
      RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
          caseSensitive: false).hasMatch(name)) {
    throw const FormatException('Unsafe selected filename');
  }
  return name;
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
}) async {
  final name = validateLabFileName(selectedName ?? file.name);
  final size = await file.length();
  if (size < 0 || size > maxLabFileBytes) {
    throw const FormatException('Selected file exceeds 64 MiB lab limit');
  }
  final digest = await _hashFile(file);
  if (await file.length() != size) {
    throw StateError('Selected file changed while hashing');
  }

  await channel.send({
    'type': 'FILE_OFFER', 'name': name, 'bytes': size, 'sha256': digest,
  });
  final approval = await channel.receive().timeout(fileResponseTimeout);
  if (approval['type'] == 'FILE_DENIED') {
    throw StateError('Receiver denied file transfer');
  }
  if (approval['type'] != 'FILE_READY') {
    throw StateError('Invalid file receiver approval');
  }

  var sent = 0;
  var seq = 0;
  await for (final block in file.openRead()) {
    var offset = 0;
    while (offset < block.length) {
      final count = block.length - offset > labFileChunkBytes
          ? labFileChunkBytes : block.length - offset;
      if (sent + count > size) {
        throw StateError('Selected file grew during transfer');
      }
      final chunk = block.sublist(offset, offset + count);
      await channel.send({
        'type': 'FILE_CHUNK', 'seq': seq, 'data': base64.encode(chunk),
      });
      final ack = await channel.receive().timeout(fileResponseTimeout);
      if (ack['type'] != 'FILE_ACK' || ack['seq'] != seq) {
        throw StateError('Invalid file chunk acknowledgement');
      }
      sent += count;
      offset += count;
      seq++;
      onProgress?.call(sent, size, false);
    }
  }
  if (sent != size || await file.length() != size ||
      await _hashFile(file) != digest) {
    throw StateError('Selected file changed during transfer');
  }
  await channel.send({'type': 'FILE_END', 'bytes': sent, 'sha256': digest});
  final done = await channel.receive().timeout(fileResponseTimeout);
  if (done['type'] != 'FILE_OK' ||
      done['bytes'] != sent || done['sha256'] != digest) {
    throw StateError('Receiver did not verify complete file');
  }
  onProgress?.call(sent, size, true);
  return FileSendResult(sent, digest);
}
