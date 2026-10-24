import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/pair_session_ledger.dart';

void main() {
  test('pairing indicator expires at the exact deadline', () {
    var now = DateTime.utc(2026, 10, 23, 10);
    final ledger = PairSessionLedger(
      lifetime: const Duration(minutes: 2), clock: () => now);
    ledger.remember('192.168.1.10', 'trusted-a');
    expect(ledger.contains('192.168.1.10'), isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(ledger.contains('192.168.1.10'), isFalse);
  });

  test('re-pairing refreshes only that peer and revoke removes all addresses', () {
    var now = DateTime.utc(2026, 10, 23, 10);
    final ledger = PairSessionLedger(
      lifetime: const Duration(minutes: 2), clock: () => now);
    ledger.remember('192.168.1.10', 'fingerprint-a');
    ledger.remember('192.168.1.11', 'fingerprint-a');
    now = now.add(const Duration(minutes: 1));
    ledger.remember('192.168.1.10', 'fingerprint-a');
    now = now.add(const Duration(minutes: 1, seconds: 1));
    expect(ledger.contains('192.168.1.10'), isTrue);
    expect(ledger.contains('192.168.1.11'), isFalse);
    ledger.remember('192.168.1.12', 'fingerprint-a');
    ledger.revokeFingerprint('fingerprint-a');
    expect(ledger.contains('192.168.1.10'), isFalse);
    expect(ledger.contains('192.168.1.12'), isFalse);
  });

  test('capacity evicts oldest lease and never extends on reads', () {
    var now = DateTime.utc(2026, 10, 23, 10);
    final ledger = PairSessionLedger(maxEntries: 2,
      lifetime: const Duration(seconds: 5), clock: () => now);
    ledger.remember('a', 'fp-a');
    ledger.remember('b', 'fp-b');
    expect(ledger.contains('a'), isTrue);
    ledger.remember('c', 'fp-c');
    expect(ledger.contains('a'), isFalse);
    expect(ledger.contains('b'), isTrue);
    now = now.add(const Duration(seconds: 5));
    expect(ledger.contains('b'), isFalse);
    expect(ledger.contains('c'), isFalse);
  });

  test('fingerprint lookup expires and never treats an IP as identity', () {
    var now = DateTime.utc(2026, 10, 24, 8);
    final ledger = PairSessionLedger(
      lifetime: const Duration(seconds: 30), clock: () => now);
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
    now = now.add(const Duration(seconds: 30));
    expect(ledger.fingerprintFor('192.168.1.5'), isNull);
    ledger.remember('192.168.1.5', 'device-c');
    ledger.clear();
    expect(ledger.fingerprintFor('192.168.1.5'), isNull);
  });

  test('rejects invalid limits and empty identity', () {
    expect(() => PairSessionLedger(lifetime: Duration.zero), throwsArgumentError);
    expect(() => PairSessionLedger(maxEntries: 0), throwsArgumentError);
    final ledger = PairSessionLedger();
    expect(() => ledger.remember('', 'fingerprint'), throwsArgumentError);
    expect(() => ledger.remember('192.168.1.1', ''), throwsArgumentError);
    ledger.remember('192.168.1.1', 'fingerprint');
    ledger.clear();
    expect(ledger.contains('192.168.1.1'), isFalse);
  });
}
