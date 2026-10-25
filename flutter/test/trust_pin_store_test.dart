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
    release.complete();

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
}
