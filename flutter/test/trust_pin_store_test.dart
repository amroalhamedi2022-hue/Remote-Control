import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/trust_pin_store.dart';

void main() {
  test('stop during delayed pin persistence restores the prior durable snapshot', () async {
    var active = true;
    var firstWrite = true;
    final entered = Completer<void>();
    final release = Completer<void>();
    final writes = <Map<String, String>>[];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      writes.add(Map<String, String>.of(snapshot));
      if (firstWrite) {
        firstWrite = false;
        entered.complete();
        await release.future;
      }
    });

    final pending = store.pinIfCurrent('peer-a', 'public-key-a',
        isCurrent: () => active);
    await entered.future;
    active = false;
    // Mirrors PairingLab.stop(): queue the current snapshot while the stale
    // candidate write is still pending, then let storage finish.
    final stopFlush = store.persistCurrent();
    release.complete();
    await stopFlush;

    await expectLater(pending, throwsStateError);
    expect(store.values, isEmpty);
    expect(writes.last, isEmpty);
  });

  test('concurrent revoke wins over a pin write already in flight', () async {
    var firstWrite = true;
    final entered = Completer<void>();
    final release = Completer<void>();
    final writes = <Map<String, String>>[];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      writes.add(Map<String, String>.of(snapshot));
      if (firstWrite) {
        firstWrite = false;
        entered.complete();
        await release.future;
      }
    });
    store.load({'peer-old': 'public-key-old'});

    final pendingPin = store.pinIfCurrent('peer-new', 'public-key-new',
        isCurrent: () => true);
    await entered.future;
    final pendingRevoke = store.revoke('peer-old');
    expect(store.values, isEmpty);
    release.complete();

    await expectLater(pendingPin, throwsStateError);
    expect(await pendingRevoke, isTrue);
    expect(store.values, isEmpty);
    expect(writes.last, isEmpty);
  });

  test('successful pin is persisted before appearing in the in-memory trust set', () async {
    final writes = <Map<String, String>>[];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      writes.add(Map<String, String>.of(snapshot));
    });
    await store.pinIfCurrent('peer-a', 'public-key-a', isCurrent: () => true);
    expect(store['peer-a'], 'public-key-a');
    expect(writes.single, {'peer-a': 'public-key-a'});
    expect(await store.revoke('peer-a'), isTrue);
    expect(store.values, isEmpty);
    expect(writes.last, isEmpty);
  });

  test('revoke retries a transient secure-storage failure before succeeding', () async {
    var attempts = 0;
    final durable = <Map<String, String>>[
      {'peer-a': 'public-key-a'},
    ];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      attempts++;
      if (attempts == 1) {
        throw StateError('simulated transient secure-storage failure');
      }
      durable.add(Map<String, String>.of(snapshot));
    });
    store.load({'peer-a': 'public-key-a'});

    expect(await store.revoke('peer-a'), isTrue);
    expect(store.values, isEmpty);
    expect(attempts, 2);
    expect(durable.last, isEmpty);
  });

  test('revoke reports when both durable writes fail instead of claiming persistence', () async {
    var attempts = 0;
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      attempts++;
      throw StateError('simulated storage outage');
    });
    store.load({'peer-a': 'public-key-a'});

    await expectLater(
      store.revoke('peer-a'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('durable trust may survive restart'),
      )),
    );
    expect(store.values, isEmpty);
    expect(attempts, 2);
  });

  test('failed pin persistence leaves memory unchanged and reasserts current snapshot', () async {
    var firstWrite = true;
    final writes = <Map<String, String>>[];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      if (firstWrite) {
        firstWrite = false;
        throw StateError('simulated secure-storage failure');
      }
      writes.add(Map<String, String>.of(snapshot));
    });
    await expectLater(
      store.pinIfCurrent('peer-a', 'public-key-a', isCurrent: () => true),
      throwsStateError,
    );
    expect(store.values, isEmpty);
    expect(writes.last, isEmpty);
  });

  test('trust set refuses a 129th peer before any persistence write', () async {
    final writes = <Map<String, String>>[];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      writes.add(Map<String, String>.of(snapshot));
    });
    final full = <String, String>{
      for (var i = 0; i < TrustPinStore.maxTrustedPeers; i++)
        'peer-$i': 'public-key-$i',
    };
    store.load(full);

    await expectLater(
      store.pinIfCurrent(
        'peer-overflow', 'public-key-overflow', isCurrent: () => true),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('peer limit reached'),
      )),
    );
    expect(store.length, TrustPinStore.maxTrustedPeers);
    expect(store.containsKey('peer-overflow'), isFalse);
    expect(writes, isEmpty);
  });

  test('oversized persisted trust snapshot is rejected without partial loading', () {
    final store = TrustPinStore(writeSnapshot: (_) async {});
    final oversized = <String, String>{
      for (var i = 0; i <= TrustPinStore.maxTrustedPeers; i++)
        'peer-$i': 'public-key-$i',
    };
    expect(() => store.load(oversized), throwsFormatException);
    expect(store.values, isEmpty);
    expect(store.length, 0);
  });

  test('revoke retry never overwrites a newer concurrent pin snapshot', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var attempts = 0;
    final durable = <Map<String, String>>[];
    final store = TrustPinStore(writeSnapshot: (snapshot) async {
      attempts++;
      if (attempts == 1) {
        entered.complete();
        await release.future;
        throw StateError('simulated uncertain revoke write');
      }
      durable.add(Map<String, String>.of(snapshot));
    });
    store.load({'peer-old': 'public-key-old'});

    final revoking = store.revoke('peer-old');
    await entered.future;
    final pinning = store.pinIfCurrent(
      'peer-new', 'public-key-new', isCurrent: () => true);
    release.complete();

    await expectLater(
      revoking,
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('concurrent trust mutation'),
      )),
    );
    await pinning;
    expect(store.values, {'peer-new': 'public-key-new'});
    expect(durable, isNotEmpty);
    expect(durable.last, {'peer-new': 'public-key-new'});
    expect(durable.any((snapshot) => snapshot.containsKey('peer-old')), isFalse);
  });

}
