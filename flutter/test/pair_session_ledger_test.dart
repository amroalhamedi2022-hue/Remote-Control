import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/pair_session_ledger.dart';

void main() {
  test('pairing indicator expires at the exact monotonic deadline', () {
    var nowMicros = 0;
    final ledger = PairSessionLedger(
      lifetime: const Duration(minutes: 2),
      monotonicMicros: () => nowMicros,
    );
    ledger.remember('192.168.1.10', 'trusted-a');
    expect(ledger.contains('192.168.1.10'), isTrue);
    nowMicros += const Duration(minutes: 2).inMicroseconds;
    expect(ledger.contains('192.168.1.10'), isFalse);
  });

  test('re-pairing refreshes only that peer and revoke removes all addresses', () {
    var nowMicros = 0;
    final ledger = PairSessionLedger(
      lifetime: const Duration(minutes: 2),
      monotonicMicros: () => nowMicros,
    );
    ledger.remember('192.168.1.10', 'fingerprint-a');
    ledger.remember('192.168.1.11', 'fingerprint-a');
    nowMicros += const Duration(minutes: 1).inMicroseconds;
    ledger.remember('192.168.1.10', 'fingerprint-a');
    nowMicros += const Duration(minutes: 1, seconds: 1).inMicroseconds;
    expect(ledger.contains('192.168.1.10'), isTrue);
    expect(ledger.contains('192.168.1.11'), isFalse);
    ledger.remember('192.168.1.12', 'fingerprint-a');
    ledger.revokeFingerprint('fingerprint-a');
    expect(ledger.contains('192.168.1.10'), isFalse);
    expect(ledger.contains('192.168.1.12'), isFalse);
  });

  test('capacity evicts oldest lease and reads never extend its lifetime', () {
    var nowMicros = 0;
    final ledger = PairSessionLedger(
      maxEntries: 2,
      lifetime: const Duration(seconds: 5),
      monotonicMicros: () => nowMicros,
    );
    ledger.remember('a', 'fp-a');
    ledger.remember('b', 'fp-b');
    expect(ledger.contains('a'), isTrue);
    ledger.remember('c', 'fp-c');
    expect(ledger.contains('a'), isFalse);
    expect(ledger.contains('b'), isTrue);
    nowMicros += const Duration(seconds: 5).inMicroseconds;
    expect(ledger.contains('b'), isFalse);
    expect(ledger.contains('c'), isFalse);
  });

  test('fingerprint lookup expires and never treats an IP as identity', () {
    var nowMicros = 0;
    final ledger = PairSessionLedger(
      lifetime: const Duration(seconds: 30),
      monotonicMicros: () => nowMicros,
    );
    ledger.remember('192.168.1.5', 'device-a');
    expect(ledger.fingerprintFor('192.168.1.5'), 'device-a');
    expect(ledger.fingerprintFor('192.168.1.6'), isNull);
    // Re-pairing a reused DHCP address replaces the old identity.
    ledger.remember('192.168.1.5', 'device-b');
    expect(ledger.fingerprintFor('192.168.1.5'), 'device-b');
    ledger.revokeFingerprint('device-a');
    expect(ledger.fingerprintFor('192.168.1.5'), 'device-b');
    ledger.revokeFingerprint('device-b');
    expect(ledger.fingerprintFor('192.168.1.5'), isNull);
    ledger.remember('192.168.1.5', 'device-c');
    nowMicros += const Duration(seconds: 30).inMicroseconds;
    expect(ledger.fingerprintFor('192.168.1.5'), isNull);
    ledger.remember('192.168.1.5', 'device-c');
    ledger.clear();
    expect(ledger.fingerprintFor('192.168.1.5'), isNull);
  });

  test('bounds peer identifiers and rejects hidden control characters', () {
    final ledger = PairSessionLedger();
    final longAddress = List.filled(PairSessionLedger.maxAddressLength + 1, 'a').join();
    final longFingerprint = List.filled(PairSessionLedger.maxFingerprintLength + 1, 'f').join();
    expect(() => ledger.remember(longAddress, 'fingerprint'), throwsArgumentError);
    expect(() => ledger.remember('192.168.1.10', longFingerprint), throwsArgumentError);
    expect(() => ledger.remember('192.168.1.10\u202E', 'fingerprint'), throwsArgumentError);
    expect(() => ledger.remember('192.168.1.10', 'fingerprint\nspoof'), throwsArgumentError);
    expect(ledger.length, 0);

    const address = 'fe80::1%wlan0';
    final fingerprint = List.filled(64, 'a').join();
    ledger.remember(address, fingerprint);
    expect(ledger.fingerprintFor(address), fingerprint);
  });

  test('clock rollback permanently invalidates the ledger until session recreation', () {
    var nowMicros = 10_000;
    final ledger = PairSessionLedger(monotonicMicros: () => nowMicros);
    ledger.remember('192.168.1.7', 'device-seven');
    nowMicros = 9_000;
    expect(() => ledger.contains('192.168.1.7'), throwsStateError);

    nowMicros = 10_000; // source recovers, but this ledger must stay unusable
    expect(() => ledger.contains('192.168.1.7'), throwsStateError);
    expect(() => ledger.remember('192.168.1.8', 'device-eight'), throwsStateError);
    expect(() => ledger.length, throwsStateError);
    ledger.clear(); // clearing entries must not repair the clock-health latch
    expect(() => ledger.remember('192.168.1.9', 'device-nine'), throwsStateError);
  });

  test('fingerprint revocation detects rollback and keeps ledger disabled', () {
    var nowMicros = 10_000;
    final ledger = PairSessionLedger(monotonicMicros: () => nowMicros);
    ledger.remember('192.168.1.8', 'device-eight');
    ledger.remember('192.168.1.9', 'device-nine');

    nowMicros = 9_000;
    expect(() => ledger.revokeFingerprint('device-eight'), throwsStateError);
    nowMicros = 10_000;
    expect(() => ledger.length, throwsStateError);
    expect(() => ledger.fingerprintFor('192.168.1.9'), throwsStateError);
  });

  test('negative monotonic clock is rejected and permanently disables ledger', () {
    var nowMicros = 10;
    final ledger = PairSessionLedger(monotonicMicros: () => nowMicros);
    ledger.remember('peer-a', 'fingerprint-a');
    nowMicros = -1;
    expect(() => ledger.contains('peer-a'), throwsStateError);
    nowMicros = 10;
    expect(() => ledger.contains('peer-a'), throwsStateError);
    expect(() => ledger.remember('peer-b', 'fingerprint-b'), throwsStateError);
  });

  test('rejects invalid limits and empty identity', () {
    expect(() => PairSessionLedger(lifetime: Duration.zero), throwsArgumentError);
    expect(() => PairSessionLedger(maxEntries: 0), throwsArgumentError);
    expect(() => PairSessionLedger(maxEntries: PairSessionLedger.maxAllowedEntries + 1),
        throwsArgumentError);
    expect(() => PairSessionLedger(lifetime: const Duration(days: 2)),
        throwsArgumentError);
    final ledger = PairSessionLedger();
    expect(() => ledger.remember('', 'fingerprint'), throwsArgumentError);
    expect(() => ledger.remember('192.168.1.1', ''), throwsArgumentError);
    ledger.remember('192.168.1.1', 'fingerprint');
    ledger.clear();
    expect(ledger.contains('192.168.1.1'), isFalse);
  });
}
