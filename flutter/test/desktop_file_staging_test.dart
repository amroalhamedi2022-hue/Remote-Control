import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/desktop_file_staging.dart';
import 'package:liquid_remote_control/security/file_transfer_lab.dart';

class _Frames implements FileTransferChannel {
  final List<Map<String, dynamic>> frames;
  final sent = <Map<String, dynamic>>[];
  _Frames(this.frames);
  @override
  Future<void> send(Map<String, dynamic> message) async => sent.add(message);
  @override
  Future<Map<String, dynamic>> receive() async => frames.removeAt(0);
}

Map<String, dynamic> _offer(String name, List<int> data) => {
  'type': 'FILE_OFFER',
  'name': name,
  'bytes': data.length,
  'sha256': crypto.sha256.convert(data).toString(),
};

_Frames _validFrames(List<int> bytes) => _Frames([
  if (bytes.isNotEmpty) {
    'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode(bytes),
  },
  {
    'type': 'FILE_END',
    'bytes': bytes.length,
    'sha256': crypto.sha256.convert(bytes).toString(),
  },
]);

void main() {
  late Directory destination;
  setUp(() async {
    destination = await Directory.systemTemp.createTemp('remote-desktop-test-');
  });
  tearDown(() async {
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
  });

  test('verified transfer publishes exactly one complete received folder', () async {
    final original = File('${destination.path}${Platform.pathSeparator}تقرير.txt');
    await original.writeAsString('do not overwrite');
    final data = utf8.encode('secure file contents');
    final channel = _validFrames(data);
    final offer = _offer('تقرير.txt', data);
    var approvals = 0;
    final result = await receiveLabFileToDesktopFolder(channel, offer,
      destination: destination,
      approve: (_) async { approvals++; return true; });
    expect(result?.bytes, data.length);
    expect(approvals, 1);
    expect(await original.readAsString(), 'do not overwrite');
    final children = await destination.list().toList();
    final folders = children.whereType<Directory>().toList();
    expect(folders.length, 1);
    expect(folders.single.uri.pathSegments.where((e) => e.isNotEmpty).last,
      startsWith('Received-'));
    expect(await File('${folders.single.path}${Platform.pathSeparator}تقرير.txt')
      .readAsBytes(), data);
    expect(children.where((e) => e.path.contains('.liquidremote-stage-')), isEmpty);
    expect(channel.sent.map((e) => e['type']),
      ['FILE_READY', 'FILE_ACK', 'FILE_OK']);
  });

  test('receiver denial leaves destination entirely unchanged', () async {
    final channel = _Frames([]);
    final result = await receiveLabFileToDesktopFolder(channel,
      _offer('no.txt', [1]), destination: destination,
      approve: (_) async => false);
    expect(result, isNull);
    expect(await destination.list().toList(), isEmpty);
    expect(channel.sent.single['type'], 'FILE_DENIED');
  });

  test('bad final digest removes staging and never sends FILE_OK', () async {
    final data = [1, 2, 3];
    final channel = _Frames([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode(data)},
      {'type': 'FILE_END', 'bytes': data.length, 'sha256': '0' * 64},
    ]);
    await expectLater(receiveLabFileToDesktopFolder(channel,
      _offer('x.bin', data), destination: destination,
      approve: (_) async => true), throwsStateError);
    expect(await destination.list().toList(), isEmpty);
    expect(channel.sent.where((e) => e['type'] == 'FILE_OK'), isEmpty);
  });

  test('empty file is committed only after final SHA confirmation', () async {
    final channel = _validFrames([]);
    final result = await receiveLabFileToDesktopFolder(channel,
      _offer('empty.bin', []), destination: destination,
      approve: (_) async => true);
    expect(result?.bytes, 0);
    final folder = (await destination.list().toList()).single as Directory;
    expect(await File('${folder.path}${Platform.pathSeparator}empty.bin')
      .length(), 0);
    expect(channel.sent.map((e) => e['type']), ['FILE_READY', 'FILE_OK']);
  });

  test('two transfers with identical names never overwrite each other', () async {
    for (final data in <List<int>>[[1, 2], [3, 4, 5]]) {
      await receiveLabFileToDesktopFolder(_validFrames(data),
        _offer('same.txt', data), destination: destination,
        approve: (_) async => true);
    }
    final folders = (await destination.list().toList()).whereType<Directory>().toList();
    expect(folders.length, 2);
    final contents = <String>[];
    for (final folder in folders) {
      contents.add((await File('${folder.path}${Platform.pathSeparator}same.txt')
        .readAsBytes()).join(','));
    }
    expect(contents, containsAll(['1,2', '3,4,5']));
  });

  test('modified staging bytes fail second SHA verification and are removed', () async {
    final offer = LabIncomingOffer('clean.txt', 3,
      crypto.sha256.convert([1, 2, 3]).toString());
    final staging = await DesktopLabReceiveStaging.create(destination, offer);
    await staging.write([1, 2, 3]);
    final stageDir = (await destination.list().toList()).single as Directory;
    final payload = File('${stageDir.path}${Platform.pathSeparator}payload.part');
    // Simulate external modification between receipt and publish.
    await payload.writeAsBytes([4, 5, 6], flush: true);
    await expectLater(staging.commit(name: offer.name, bytes: offer.bytes,
      sha256: offer.sha256), throwsStateError);
    await staging.abort();
    expect(await destination.list().toList(), isEmpty);
  });

  test('unsafe filename and missing destination are rejected before write', () async {
    final bad = LabIncomingOffer('../outside.txt', 1, '0' * 64);
    await expectLater(DesktopLabReceiveStaging.create(destination, bad),
      throwsFormatException);
    expect(await destination.list().toList(), isEmpty);
    final missing = Directory('${destination.path}${Platform.pathSeparator}missing');
    final good = LabIncomingOffer('safe.txt', 1, '0' * 64);
    await expectLater(DesktopLabReceiveStaging.create(missing, good),
      throwsStateError);
  });

  test('symlink destination is rejected (where symlinks are supported)', () async {
    final link = Link('${destination.path}${Platform.pathSeparator}shortcut');
    try {
      await link.create(destination.path);
    } on FileSystemException {
      return; // Windows accounts without symlink permission.
    }
    final offer = LabIncomingOffer('safe.txt', 0,
      crypto.sha256.convert([]).toString());
    await expectLater(DesktopLabReceiveStaging.create(
      Directory(link.path), offer), throwsStateError);
  });
}
