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

  test('invalid cache bounds are rejected', () {
    expect(() => PairingNonceGuard(maxEntries: 0), throwsArgumentError);
    expect(() => PairingNonceGuard(lifetime: Duration.zero), throwsArgumentError);
  });
}
