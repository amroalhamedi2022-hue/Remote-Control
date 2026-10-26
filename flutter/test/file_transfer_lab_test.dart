import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/file_transfer_lab.dart';

class _NodeReceiverFixture implements AbortableFileTransferChannel {
  bool aborted = false;
  @override
  void abort() { aborted = true; }
  final bool deny;
  final bool wrongAck;
  final void Function()? onAck;
  final String? stallOnSendType;
  final List<Map<String, dynamic>> sent = [];
  _NodeReceiverFixture({this.deny = false, this.wrongAck = false,
    this.onAck, this.stallOnSendType});

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (message['type'] == stallOnSendType) {
      await Completer<void>().future;
    }
    sent.add(message);
  }

  @override
  Future<Map<String, dynamic>> receive() async {
    final last = sent.last;
    switch (last['type']) {
      case 'FILE_OFFER':
        return {'type': deny ? 'FILE_DENIED' : 'FILE_READY'};
      case 'FILE_CHUNK':
        onAck?.call();
        return {'type':'FILE_ACK', 'seq': wrongAck ? -1 : last['seq']};
      case 'FILE_END':
        return {'type':'FILE_OK', 'bytes':last['bytes'],
          'sha256':last['sha256']};
      default:
        throw StateError('Unexpected fixture frame');
    }
  }
}


class _IncomingFixture implements AbortableFileTransferChannel {
  bool aborted = false;
  @override
  void abort() { aborted = true; }
  final List<Map<String, dynamic>> incoming;
  final String? stallOnSendType;
  final sent = <Map<String, dynamic>>[];
  _IncomingFixture(this.incoming, {this.stallOnSendType});
  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (message['type'] == stallOnSendType) {
      await Completer<void>().future;
    }
    sent.add(message);
  }
  @override
  Future<Map<String, dynamic>> receive() async => incoming.removeAt(0);
}

class _StagingFixture implements LabReceiveStaging {
  final bytes = <int>[];
  bool published = false;
  bool aborted = false;
  bool rejectCommit = false;
  bool rejectRollback = false;
  bool finalized = false;
  @override
  Future<void> write(List<int> data) async { bytes.addAll(data); }
  @override
  Future<void> commit({required String name, required int bytes,
      required String sha256}) async {
    if (rejectCommit) throw StateError('Disk full');
    if (this.bytes.length != bytes) throw StateError('Incorrect staging size');
    published = true;
  }
  @override
  Future<void> rollbackCommitted() async {
    if (rejectRollback) throw StateError('simulated published-file rollback failure');
    if (published) {
      published = false;
      aborted = true;
      bytes.clear();
    }
  }
  @override
  Future<void> finalizeCommitted() async { finalized = true; }
  @override
  Future<void> abort() async {
    if (published) return;
    aborted = true;
    bytes.clear();
  }
}

Future<void> _verifyReceive(
  List<Map<String, dynamic>> frames, {
  bool accept = true,
  bool failCommit = false,
  bool shouldSucceed = true,
}) async {
  final data = <int>[1, 2, 3, 4, 5];
  final hash = '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';
  final channel = _IncomingFixture(frames);
  final staging = _StagingFixture()..rejectCommit = failCommit;
  final offer = {
    'type': 'FILE_OFFER', 'name': 'ملف.txt',
    'bytes': data.length, 'sha256': hash,
  };
  var created = 0;
  Future<LabReceiveStaging> create(LabIncomingOffer _) async {
    created++;
    return staging;
  }
  Future<FileSendResult?> receive() => receiveLabFile(channel, offer,
    approve: (_) async => accept, createStaging: create);
  if (!accept) {
    expect(await receive(), isNull);
    expect(created, 0);
    expect(channel.sent.single['type'], 'FILE_DENIED');
  } else if (shouldSucceed) {
    final result = await receive();
    expect(result?.bytes, 5);
    expect(staging.bytes, data);
    expect(staging.published, isTrue);
    expect(staging.aborted, isFalse);
    expect(staging.finalized, isTrue);
    expect(channel.sent.map((e) => e['type']),
      ['FILE_READY', 'FILE_ACK', 'FILE_OK']);
  } else {
    await expectLater(receive(), throwsA(anyOf(isA<Exception>(), isA<Error>())));
    expect(staging.published, isFalse);
    expect(staging.aborted, isTrue);
    expect(channel.sent.where((e) => e['type'] == 'FILE_OK'), isEmpty);
  }
}

class _BlockingStaging extends _StagingFixture {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  @override
  Future<void> write(List<int> data) async {
    entered.complete();
    await release.future;
    await super.write(data);
  }
}

class _BlockingCommitStaging extends _StagingFixture {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  @override
  Future<void> commit({required String name, required int bytes,
      required String sha256}) async {
    entered.complete();
    await release.future;
    await super.commit(name: name, bytes: bytes, sha256: sha256);
  }
}

void main() {
  test('validates cross-platform filename safety before sending', () {
    for (final name in [
      '../secret', 'CON.txt', 'nul', 'bad?.pdf', 'name.', 'name ',
      '.liquidremote-123', 'a\\b', 'a\u202eexe', 'COM¹.txt', 'LPT².log', 'tag\u{E0001}.txt',
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

  test('sender aborts a stalled chunk transport instead of racing FILE_CANCEL', () async {
    final channel = _NodeReceiverFixture(stallOnSendType: 'FILE_CHUNK');
    final file = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'stall.bin');
    await expectLater(
      sendLabFile(channel, file, selectedName: 'stall.bin',
        sendTimeout: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    expect(channel.aborted, isTrue);
    expect(channel.sent.map((message) => message['type']), ['FILE_OFFER']);
  });

  test('sender never cancels after a timed-out FILE_END attempt', () async {
    final channel = _NodeReceiverFixture(stallOnSendType: 'FILE_END');
    final file = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'final-timeout.bin');
    await expectLater(
      sendLabFile(channel, file, selectedName: 'final-timeout.bin',
        sendTimeout: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    expect(channel.aborted, isTrue);
    expect(channel.sent.map((message) => message['type']),
      ['FILE_OFFER', 'FILE_CHUNK']);
  });

  test('canonical chunk boundary keeps a one-byte final chunk', () async {
    final bytes = Uint8List.fromList(
        List<int>.generate(labFileChunkBytes + 1, (i) => i % 251));
    final channel = _NodeReceiverFixture();
    final result = await sendLabFile(channel,
        XFile.fromData(bytes, name: 'boundary.bin'),
        selectedName: 'boundary.bin');
    final chunks = channel.sent
        .where((message) => message['type'] == 'FILE_CHUNK').toList();
    expect(result.bytes, labFileChunkBytes + 1);
    expect(chunks.map((message) =>
        base64.decode(message['data'] as String).length), [labFileChunkBytes, 1]);
    expect(chunks.map((message) => message['seq']), [0, 1]);
    expect(channel.sent.last['type'], 'FILE_END');
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
    expect(channel.sent.map((m) => m['type']),
      ['FILE_OFFER','FILE_CHUNK','FILE_CANCEL']);
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

  test('Dart receiver commits only after Node-compatible SHA-256 final frame', () async {
    const digest = '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1,2,3,4,5])},
      {'type': 'FILE_END', 'bytes': 5, 'sha256': digest},
    ]);
  });

  test('incoming transfer denial creates no destination', () async {
    await _verifyReceive([], accept: false);
  });

  test('wrong incoming sequence aborts staged bytes', () async {
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 1, 'data': base64.encode([1,2,3,4,5])},
    ], shouldSucceed: false);
  });

  test('non-canonical short chunk is rejected before acknowledgement', () async {
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1,2])},
    ], shouldSucceed: false);
  });

  test('incoming size overflow aborts before writing', () async {
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1,2,3,4,5,6])},
    ], shouldSucceed: false);
  });

  test('invalid incoming base64 aborts staging', () async {
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': '!!!='},
    ], shouldSucceed: false);
  });

  test('wrong final digest never publishes partial file', () async {
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1,2,3,4,5])},
      {'type': 'FILE_END', 'bytes': 5, 'sha256': '0' * 64},
    ], shouldSucceed: false);
  });

  test('failed destination commit never acknowledges success', () async {
    const digest = '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';
    await _verifyReceive([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1,2,3,4,5])},
      {'type': 'FILE_END', 'bytes': 5, 'sha256': digest},
    ], failCommit: true, shouldSucceed: false);
  });

  test('receiver bounds a stalled ACK send and aborts private staging', () async {
    const digest = '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';
    final channel = _IncomingFixture([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1, 2, 3, 4, 5])},
    ], stallOnSendType: 'FILE_ACK');
    final stage = _StagingFixture();
    await expectLater(
      receiveLabFile(channel, {
        'type': 'FILE_OFFER', 'name': 'stalled-ack.bin',
        'bytes': 5, 'sha256': digest,
      }, approve: (_) async => true,
        createStaging: (_) async => stage,
        sendTimeout: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    expect(stage.aborted, isTrue);
    expect(stage.published, isFalse);
    expect(channel.aborted, isTrue);
    expect(channel.sent.map((message) => message['type']), ['FILE_READY']);
  });

  test('SAF staging failure denies sender before FILE_READY', () async {
    final channel = _IncomingFixture([]);
    final offer = {
      'type': 'FILE_OFFER', 'name': 'ok.txt', 'bytes': 1,
      'sha256': '0' * 64,
    };
    await expectLater(receiveLabFile(channel, offer,
      approve: (_) async => true,
      createStaging: (_) async => throw StateError('SAF provider refused write')),
      throwsStateError);
    expect(channel.sent.map((m) => m['type']), ['FILE_DENIED']);
  });

  test('cancelled or failed approval denies sender without creating staging', () async {
    final channel = _IncomingFixture([]);
    var staged = false;
    await expectLater(receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'ok.txt', 'bytes': 1,
      'sha256': '0' * 64,
    }, approve: (_) async => throw StateError('Picker closed'),
      createStaging: (_) async { staged = true; return _StagingFixture(); }),
      throwsStateError);
    expect(staged, isFalse);
    expect(channel.sent.map((m) => m['type']), ['FILE_DENIED']);
  });

  test('malformed incoming offer is rejected before consent', () async {
    final channel = _IncomingFixture([]);
    var asked = false;
    await expectLater(receiveLabFile(channel, {
      'type':'FILE_OFFER','name':'CON.txt','bytes':2,'sha256':'0' * 64,
    }, approve: (_) async { asked = true; return true; },
       createStaging: (_) async => _StagingFixture()), throwsFormatException);
    expect(asked, isFalse);
    expect(channel.sent, isEmpty);
  });


  test('explicit sender cancellation aborts staged bytes without FILE_OK', () async {
    final firstChunk = List<int>.generate(labFileChunkBytes, (i) => i % 251);
    final channel = _IncomingFixture([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode(firstChunk)},
      {'type': 'FILE_CANCEL'},
    ]);
    final stage = _StagingFixture();
    await expectLater(receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'partial.bin',
      'bytes': labFileChunkBytes + 1, 'sha256': '0' * 64,
    }, approve: (_) async => true, createStaging: (_) async => stage),
      throwsStateError);
    expect(stage.aborted, isTrue);
    expect(stage.published, isFalse);
    expect(channel.sent.map((m) => m['type']), ['FILE_READY', 'FILE_ACK']);
  });

  test('late native staging completion after deadline is aborted', () async {
    final pending = Completer<LabReceiveStaging>();
    final channel = _IncomingFixture([]);
    final stage = _StagingFixture();
    final receiving = receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'late.bin', 'bytes': 1,
      'sha256': '0' * 64,
    }, approve: (_) async => true,
      createStaging: (_) => pending.future,
      stagingTimeout: const Duration(milliseconds: 5));
    await expectLater(receiving, throwsA(isA<TimeoutException>()));
    expect(channel.sent.map((m) => m['type']), ['FILE_DENIED']);
    pending.complete(stage);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(stage.aborted, isTrue);
    expect(stage.published, isFalse);
    expect(channel.sent.where((m) => m['type'] == 'FILE_READY'), isEmpty);
  });

  test('revoked sender cancels before publishing FILE_END', () async {
    var active = true;
    final channel = _NodeReceiverFixture(onAck: () { active = false; });
    final file = XFile.fromData(Uint8List.fromList([1, 2, 3]),
        name: 'revoked.bin');
    await expectLater(sendLabFile(channel, file,
      selectedName: 'revoked.bin', isSessionActive: () => active),
      throwsStateError);
    expect(channel.sent.map((m) => m['type']),
      ['FILE_OFFER', 'FILE_CHUNK', 'FILE_CANCEL']);
  });

  test('revocation during native staging aborts before FILE_READY', () async {
    var active = true;
    final pending = Completer<LabReceiveStaging>();
    final stage = _StagingFixture();
    final channel = _IncomingFixture([]);
    final receiving = receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'late.bin',
      'bytes': 1, 'sha256': '0' * 64,
    }, approve: (_) async => true, createStaging: (_) => pending.future,
      isSessionActive: () => active);
    await Future<void>.delayed(Duration.zero);
    active = false;
    pending.complete(stage);
    await expectLater(receiving, throwsStateError);
    expect(stage.aborted, isTrue);
    expect(stage.published, isFalse);
    expect(channel.sent.where((m) => m['type'] == 'FILE_READY'), isEmpty);
  });

  test('revocation during slow write aborts without ACK or publication', () async {
    var active = true;
    final stage = _BlockingStaging();
    final channel = _IncomingFixture([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1, 2])},
      {'type': 'FILE_END', 'bytes': 2, 'sha256': '0' * 64},
    ]);
    final receiving = receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'pending.bin',
      'bytes': 2, 'sha256': '0' * 64,
    }, approve: (_) async => true, createStaging: (_) async => stage,
      isSessionActive: () => active);
    await stage.entered.future;
    active = false;
    stage.release.complete();
    await expectLater(receiving, throwsStateError);
    expect(stage.aborted, isTrue);
    expect(stage.published, isFalse);
    expect(channel.sent.map((m) => m['type']), ['FILE_READY']);
  });

  test('revoke during native commit suppresses FILE_OK (SAF publish may already exist)', () async {
    const digest = '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';
    final stage = _BlockingCommitStaging();
    final channel = _IncomingFixture([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1, 2, 3, 4, 5])},
      {'type': 'FILE_END', 'bytes': 5, 'sha256': digest},
    ]);
    var active = true;
    final receiving = receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'late-publish.bin',
      'bytes': 5, 'sha256': digest,
    }, approve: (_) async => true, createStaging: (_) async => stage,
      isSessionActive: () => active);
    await stage.entered.future;
    active = false;
    stage.release.complete();
    await expectLater(receiving, throwsStateError);
    expect(stage.published, isFalse);
    expect(stage.aborted, isTrue);
    expect(stage.finalized, isFalse);
    expect(channel.sent.where((frame) => frame['type'] == 'FILE_OK'), isEmpty);
  });

  test('rollback failure after post-commit revocation is explicit and never ACKed', () async {
    const digest = '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';
    final stage = _BlockingCommitStaging()..rejectRollback = true;
    final channel = _IncomingFixture([
      {'type': 'FILE_CHUNK', 'seq': 0, 'data': base64.encode([1, 2, 3, 4, 5])},
      {'type': 'FILE_END', 'bytes': 5, 'sha256': digest},
    ]);
    var active = true;
    final receiving = receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'rollback-failure.bin',
      'bytes': 5, 'sha256': digest,
    }, approve: (_) async => true, createStaging: (_) async => stage,
      isSessionActive: () => active);
    await stage.entered.future;
    active = false;
    stage.release.complete();
    await expectLater(
      receiving,
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('rollback failed'),
      )),
    );
    expect(stage.published, isTrue); // Explicitly reported: provider refused rollback.
    expect(channel.sent.where((frame) => frame['type'] == 'FILE_OK'), isEmpty);
  });

  test('revoked session never asks for approval or opens staging', () async {
    var asked = false;
    final channel = _IncomingFixture([]);
    await expectLater(receiveLabFile(channel, {
      'type': 'FILE_OFFER', 'name': 'not-allowed.bin',
      'bytes': 1, 'sha256': '0' * 64,
    }, isSessionActive: () => false,
      approve: (_) async { asked = true; return true; },
      createStaging: (_) async => _StagingFixture()), throwsStateError);
    expect(asked, isFalse);
    expect(channel.sent, isEmpty);
  });

}
