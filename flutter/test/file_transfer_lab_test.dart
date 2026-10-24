import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/file_transfer_lab.dart';

class _NodeReceiverFixture implements FileTransferChannel {
  final bool deny;
  final bool wrongAck;
  final List<Map<String, dynamic>> sent = [];
  _NodeReceiverFixture({this.deny = false, this.wrongAck = false});

  @override
  Future<void> send(Map<String, dynamic> message) async {
    sent.add(message);
  }

  @override
  Future<Map<String, dynamic>> receive() async {
    final last = sent.last;
    switch (last['type']) {
      case 'FILE_OFFER':
        return {'type': deny ? 'FILE_DENIED' : 'FILE_READY'};
      case 'FILE_CHUNK':
        return {'type':'FILE_ACK', 'seq': wrongAck ? -1 : last['seq']};
      case 'FILE_END':
        return {'type':'FILE_OK', 'bytes':last['bytes'],
          'sha256':last['sha256']};
      default:
        throw StateError('Unexpected fixture frame');
    }
  }
}

void main() {
  test('validates cross-platform filename safety before sending', () {
    for (final name in [
      '../secret', 'CON.txt', 'nul', 'bad?.pdf', 'name.', 'name ',
      '.liquidremote-123', 'a\\b', 'a\u202eexe',
    ]) {
      expect(() => validateLabFileName(name), throwsFormatException,
          reason:name);
    }
    expect(validateLabFileName('تقرير 2026.pdf'), 'تقرير 2026.pdf');
  });

  test('sends bounded chunks with SHA-256 and verified final ACK', () async {
    final bytes = Uint8List.fromList(List<int>.generate(8000, (i) => i % 251));
    final file = XFile.fromData(bytes, name:'ملف.bin');
    final channel = _NodeReceiverFixture();
    final updates = <(int,int,bool)>[];
    final result = await sendLabFile(channel, file, selectedName:'ملف.bin',
      onProgress:(sent,total,verified) => updates.add((sent,total,verified)));
    expect(result.bytes, 8000);
    expect(result.sha256, hasLength(64));
    expect(channel.sent.first['type'], 'FILE_OFFER');
    expect(channel.sent.first['sha256'], result.sha256);
    final chunks = channel.sent.where((m) => m['type'] == 'FILE_CHUNK').toList();
    expect(chunks.length, 3);
    expect(chunks.map((m) => base64.decode(m['data'] as String).length),
      [3072, 3072, 1856]);
    expect(chunks.map((m) => m['seq']), [0, 1, 2]);
    expect(channel.sent.last['type'], 'FILE_END');
    expect(updates.last, (8000,8000,true));
  });

  test('receiver refusal never emits file bytes', () async {
    final channel = _NodeReceiverFixture(deny:true);
    final file = XFile.fromData(Uint8List.fromList([1,2,3]),name:'x.bin');
    await expectLater(sendLabFile(channel,file,selectedName:'x.bin'), throwsStateError);
    expect(channel.sent.map((m) => m['type']), ['FILE_OFFER']);
  });

  test('incorrect chunk ACK fails closed before sending completion', () async {
    final channel = _NodeReceiverFixture(wrongAck:true);
    final file = XFile.fromData(Uint8List.fromList([1,2,3]),name:'x.bin');
    await expectLater(sendLabFile(channel,file,selectedName:'x.bin'), throwsStateError);
    expect(channel.sent.map((m) => m['type']), ['FILE_OFFER','FILE_CHUNK']);
  });

  test('empty file still receives a SHA-256 verified completion', () async {
    final channel = _NodeReceiverFixture();
    final file = XFile.fromData(Uint8List(0),name:'empty.txt');
    final result = await sendLabFile(channel,file,selectedName:'empty.txt');
    expect(result.bytes,0);
    expect(result.sha256,
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(channel.sent.map((m) => m['type']), ['FILE_OFFER','FILE_END']);
  });
}
