import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:liquid_remote_control/security/android_saf_staging.dart';
import 'package:liquid_remote_control/security/file_transfer_lab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidSafLabReceiveStaging.channelName);
  final calls = <MethodCall>[];
  String? selected;
  bool failCommit = false;

  setUp(() {
    calls.clear();
    selected = 'content://test/tree/123';
    failCommit = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'pickTree':
          return selected;
        case 'begin':
          return 'stage-1';
        case 'write':
        case 'abort':
        case 'rollbackCommitted':
        case 'finalizeCommitted':
          return null;
        case 'commit':
          if (failCommit) throw PlatformException(code: 'SHA_MISMATCH');
          return 'content://test/document/received';
      }
      throw MissingPluginException();
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  LabIncomingOffer offer([String name = 'تقرير.txt']) =>
      LabIncomingOffer(name, 3, crypto.sha256.convert([1, 2, 3]).toString());

  test('fresh picker, bounded chunks, verified commit and no post-commit write', () async {
    final tree = await AndroidSafLabReceiveStaging.pickTree(channel: channel);
    final stage = await AndroidSafLabReceiveStaging.create(
        tree!, offer(), channel: channel);
    await stage.write([1, 2, 3]);
    final data = calls.singleWhere((call) => call.method == 'write')
        .arguments['data'] as Uint8List;
    expect(data, [1, 2, 3]);
    await stage.commit(name: offer().name, bytes: 3, sha256: offer().sha256);
    expect(calls.map((c) => c.method),
        ['pickTree', 'begin', 'write', 'commit']);
    await expectLater(stage.write([4]), throwsStateError);
    await stage.abort();
    expect(calls.where((c) => c.method == 'abort'), isEmpty);
  });

  test('cancelled Android folder picker never begins staging', () async {
    selected = null;
    expect(await AndroidSafLabReceiveStaging.pickTree(channel: channel), isNull);
    expect(calls.map((c) => c.method), ['pickTree']);
  });

  test('invalid names and oversized files fail before native staging', () async {
    await expectLater(AndroidSafLabReceiveStaging.create(
        'content://test', offer('../evil'), channel: channel),
        throwsFormatException);
    final huge = LabIncomingOffer('ok.txt', maxLabFileBytes + 1,
        '0' * 64);
    await expectLater(AndroidSafLabReceiveStaging.create(
        'content://test', huge, channel: channel), throwsFormatException);
    expect(calls, isEmpty);
  });

  test('post-commit revocation rolls back just-published document by staging id', () async {
    final stage = await AndroidSafLabReceiveStaging.create(
        'content://test', offer(), channel: channel);
    await stage.write([1, 2, 3]);
    await stage.commit(name: offer().name, bytes: 3, sha256: offer().sha256);
    await stage.rollbackCommitted();
    final rollback = calls.singleWhere((call) => call.method == 'rollbackCommitted');
    expect(rollback.arguments, {'id': 'stage-1'});
    expect(calls.map((call) => call.method),
        ['begin', 'write', 'commit', 'rollbackCommitted']);
  });

  test('successful publication finalizes rollback handle after FILE_OK', () async {
    final stage = await AndroidSafLabReceiveStaging.create(
        'content://test', offer(), channel: channel);
    await stage.write([1, 2, 3]);
    await stage.commit(name: offer().name, bytes: 3, sha256: offer().sha256);
    await stage.finalizeCommitted();
    await stage.rollbackCommitted();
    expect(calls.map((call) => call.method),
        ['begin', 'write', 'commit', 'finalizeCommitted']);
  });

  test('commit error can still abort private staging', () async {
    final stage = await AndroidSafLabReceiveStaging.create(
        'content://test', offer(), channel: channel);
    await stage.write([1, 2, 3]);
    failCommit = true;
    await expectLater(stage.commit(
        name: offer().name, bytes: 3, sha256: offer().sha256),
        throwsA(isA<PlatformException>()));
    await stage.abort();
    expect(calls.map((c) => c.method), ['begin', 'write', 'commit', 'abort']);
  });

  test('invalid chunk and duplicate abort are rejected or idempotent', () async {
    final stage = await AndroidSafLabReceiveStaging.create(
        'content://test', offer(), channel: channel);
    await expectLater(stage.write([]), throwsStateError);
    await expectLater(stage.write(List.filled(labFileChunkBytes + 1, 1)),
        throwsStateError);
    await stage.abort();
    await stage.abort();
    expect(calls.map((c) => c.method), ['begin', 'abort']);
  });
}
