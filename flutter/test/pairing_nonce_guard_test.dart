import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/pairing_nonce_guard.dart';

void main() {
  test('accepts a fresh nonce and rejects a signed hello replay', () {
    final guard = PairingNonceGuard();
    expect(guard.remember('peerPublicKey', 'freshNonce'), isTrue);
    expect(guard.remember('peerPublicKey', 'freshNonce'), isFalse);
    expect(guard.length, 1);
  });

  test('nonce identity is scoped to the public identity', () {
    final guard = PairingNonceGuard();
    expect(guard.remember('peerA', 'sameNonce'), isTrue);
    expect(guard.remember('peerB', 'sameNonce'), isTrue);
  });

  test('capacity fails closed and never evicts an unexpired nonce', () {
    var now = 0;
    final guard = PairingNonceGuard(
      lifetime: const Duration(microseconds: 100),
      maxEntries: 2,
      monotonicMicros: () => now,
    );
    expect(guard.remember('peerA', 'nonce1'), isTrue);
    expect(guard.remember('peerA', 'nonce2'), isTrue);
    expect(guard.remember('peerB', 'nonce3'), isFalse);
    expect(guard.remember('peerA', 'nonce1'), isFalse);

    now = 100;
    expect(guard.remember('peerA', 'nonce1'), isTrue);
    expect(guard.length, 1);
  });

  test('malformed identity and nonce encodings are rejected', () {
    final guard = PairingNonceGuard();
    expect(() => guard.remember('', 'nonce'), throwsFormatException);
    expect(() => guard.remember('peer:injected', 'nonce'), throwsFormatException);
    expect(() => guard.remember('peer', 'nonce with spaces'), throwsFormatException);
  });

  test('monotonic clock rollback clears nonce cache and fails closed until restart', () {
    var now = 1000;
    final guard = PairingNonceGuard(
      lifetime: const Duration(microseconds: 500),
      monotonicMicros: () => now,
    );
    expect(guard.remember('peerA', 'nonce1'), isTrue);
    expect(guard.length, 1);

    now = 999; // A broken injected/platform clock must not extend nonce lifetime.
    expect(guard.remember('peerA', 'freshNonce'), isFalse);
    expect(guard.length, 0);

    now = 1200;
    expect(guard.remember('peerA', 'nonce1'), isFalse,
        reason: 'the same nonce must not become reusable after a clock rollback');
    expect(guard.remember('peerB', 'nonce2'), isFalse,
        reason: 'recreate the pairing guard/session after clock health is lost');
    expect(guard.length, 0);
  });

  test('clock source failure clears replay state and permanently fails closed', () {
    var broken = false;
    var now = 1000;
    final guard = PairingNonceGuard(monotonicMicros: () {
      if (broken) throw StateError('clock unavailable');
      return now;
    });
    expect(guard.remember('peerA', 'nonce1'), isTrue);
    broken = true;
    expect(guard.remember('peerA', 'nonce2'), isFalse);
    expect(guard.length, 0);
    broken = false;
    now = 2000;
    expect(guard.remember('peerA', 'nonce1'), isFalse,
        reason: 'clock recovery must not reactivate stale nonce state');
    expect(guard.remember('peerB', 'nonce3'), isFalse);
  });

  test('invalid cache bounds are rejected', () {
    expect(() => PairingNonceGuard(maxEntries: 0), throwsArgumentError);
    expect(() => PairingNonceGuard(lifetime: Duration.zero), throwsArgumentError);
    expect(() => PairingNonceGuard(maxEntries: 4097), throwsArgumentError);
    expect(() => PairingNonceGuard(lifetime: Duration(days: 2)), throwsArgumentError);
  });

  test('expiry arithmetic overflow permanently fails closed for this guard', () {
    var now = 0x7fffffffffffffff - 100;
    final guard = PairingNonceGuard(
      lifetime: const Duration(microseconds: 500),
      monotonicMicros: () => now,
    );
    expect(guard.remember('peerA', 'nonce1'), isFalse);
    expect(guard.length, 0);
    now = 1;
    expect(guard.remember('peerA', 'nonce1'), isFalse,
        reason: 'a clock recovery must not reactivate the broken guard');
  });
}
