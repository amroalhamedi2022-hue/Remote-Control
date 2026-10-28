import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/desktop_file_staging.dart';
import 'package:liquid_remote_control/security/file_transfer_lab.dart';

class _Frames implements AbortableFileTransferChannel {
  final List<Map<String, dynamic>> frames;
  final sent = <Map<String, dynamic>>[];
  bool aborted = false;
  _Frames(this.frames);

  @override
  void abort() { aborted = true; }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (aborted) throw StateError('Channel aborted');
    sent.add(message);
  }

  @override
  Future<Map<String, dynamic>> receive() async {
    if (aborted) throw StateError('Channel aborted');
    return frames.removeAt(0);
  }
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

  test('invalid offer metadata is rejected before creating desktop staging', () async {
    final validDigest = crypto.sha256.convert([1]).toString();
    final invalidOffers = [
      LabIncomingOffer('bad.txt', -1, validDigest),
      LabIncomingOffer('bad.txt', maxLabFileBytes + 1, validDigest),
      LabIncomingOffer('bad.txt', 1, List.filled(64, 'G').join()),
      LabIncomingOffer('bad.txt', 1, List.filled(63, '0').join()),
    ];
    for (final invalid in invalidOffers) {
      await expectLater(
        DesktopLabReceiveStaging.create(destination, invalid),
        throwsFormatException,
      );
    }
    expect(await destination.list().toList(), isEmpty);
  });

  test('desktop staging rejects bytes beyond the approved offer before writing', () async {
    final stage = await DesktopLabReceiveStaging.create(
      destination, _offer('bounded.txt', [1, 2, 3]));
    await expectLater(stage.write([1, 2, 3, 4]), throwsStateError);
    await stage.abort();
    expect(await destination.list().toList(), isEmpty);
  });

  test('desktop commit cannot substitute approved byte count or digest', () async {
    final data = [1, 2, 3];
    final offer = _offer('bound.txt', data);
    final stage = await DesktopLabReceiveStaging.create(
      destination, LabIncomingOffer(
        offer['name'] as String, offer['bytes'] as int, offer['sha256'] as String));
    await stage.write(data);
    await expectLater(stage.commit(
      name: 'bound.txt',
      bytes: data.length,
      sha256: crypto.sha256.convert([9, 8, 7]).toString(),
    ), throwsStateError);
    await expectLater(stage.commit(
      name: 'bound.txt',
      bytes: data.length - 1,
      sha256: offer['sha256'] as String,
    ), throwsStateError);
    await stage.abort();
    expect(await destination.list().toList(), isEmpty);
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

  test('revocation after commit rolls back only the transferred file', () async {
    final data = utf8.encode('rollback-safe');
    final offer = _offer('rollback.txt', data);
    final staging = await DesktopLabReceiveStaging.create(destination, LabIncomingOffer(
      offer['name'] as String, offer['bytes'] as int, offer['sha256'] as String));
    await staging.write(data);
    await staging.commit(name: offer['name'] as String,
      bytes: offer['bytes'] as int, sha256: offer['sha256'] as String);
    final publishedPath = staging.publishedPath!;
    final folderPath = publishedPath.substring(
      0, publishedPath.lastIndexOf(Platform.pathSeparator));
    final extra = File('$folderPath${Platform.pathSeparator}user-added.txt');
    await extra.writeAsString('keep this unrelated file');

    await staging.rollbackCommitted();

    expect(await File(publishedPath).exists(), isFalse);
    expect(await extra.readAsString(), 'keep this unrelated file');
    expect(await Directory(folderPath).exists(), isTrue);
    expect(staging.publishedPath, isNull);
  });

  test('commit refuses publication after receiver folder is replaced by a symlink', () async {
    final data = utf8.encode('must stay in the originally selected folder');
    final offer = _offer('staged.txt', data);
    final staging = await DesktopLabReceiveStaging.create(destination,
      LabIncomingOffer(offer['name'] as String, offer['bytes'] as int,
        offer['sha256'] as String));
    await staging.write(data);

    final moved = Directory('${destination.path}-original');
    final outside = Directory('${destination.path}-outside');
    await destination.rename(moved.path);
    await outside.create();
    final replacement = Link(destination.path);
    try {
      await replacement.create(outside.path);
      await expectLater(staging.commit(name: offer['name'] as String,
        bytes: offer['bytes'] as int, sha256: offer['sha256'] as String),
        throwsStateError);
      expect(await outside.list().toList(), isEmpty);
      expect(await FileSystemEntity.type(destination.path, followLinks: false),
        FileSystemEntityType.link);
    } finally {
      if (await FileSystemEntity.type(destination.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await replacement.delete();
      }
      if (await moved.exists() && !await destination.exists()) {
        await moved.rename(destination.path);
      }
      await staging.abort();
      if (await outside.exists()) await outside.delete(recursive: true);
    }
  }, skip: Platform.isWindows ? 'Directory replacement with an open staging handle is not portable on Windows' : false);

  test('rollback refuses a published folder replaced by a symlink', () async {
    final data = utf8.encode('must not delete outside target');
    final offer = _offer('victim.txt', data);
    final staging = await DesktopLabReceiveStaging.create(destination,
      LabIncomingOffer(offer['name'] as String, offer['bytes'] as int,
        offer['sha256'] as String));
    await staging.write(data);
    await staging.commit(name: offer['name'] as String,
      bytes: offer['bytes'] as int, sha256: offer['sha256'] as String);
    final publishedPath = staging.publishedPath!;
    final folderPath = publishedPath.substring(
      0, publishedPath.lastIndexOf(Platform.pathSeparator));
    final moved = Directory('$folderPath-original');
    final outside = Directory('${destination.path}${Platform.pathSeparator}outside');
    await outside.create();
    final outsideFile = File('${outside.path}${Platform.pathSeparator}victim.txt');
    await outsideFile.writeAsString('preserve this file');
    await Directory(folderPath).rename(moved.path);

    final replacement = Link(folderPath);
    try {
      await replacement.create(outside.path);
    } on FileSystemException {
      // Some Windows runners do not grant symlink creation. Restore the original
      // directory and leave cleanup to tearDown rather than testing an unsupported primitive.
      await moved.rename(folderPath);
      return;
    }

    await expectLater(staging.rollbackCommitted(), throwsStateError);
    expect(await outsideFile.readAsString(), 'preserve this file');
    expect(await FileSystemEntity.type(folderPath, followLinks: false),
      FileSystemEntityType.link);
  });

  test('finalized desktop publication cannot be rolled back', () async {
    final data = utf8.encode('accepted');
    final offer = _offer('accepted.txt', data);
    final staging = await DesktopLabReceiveStaging.create(destination, LabIncomingOffer(
      offer['name'] as String, offer['bytes'] as int, offer['sha256'] as String));
    await staging.write(data);
    await staging.commit(name: offer['name'] as String,
      bytes: offer['bytes'] as int, sha256: offer['sha256'] as String);
    final publishedPath = staging.publishedPath!;
    await staging.finalizeCommitted();

    await expectLater(staging.rollbackCommitted(), throwsStateError);
    expect(await File(publishedPath).readAsBytes(), data);
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
