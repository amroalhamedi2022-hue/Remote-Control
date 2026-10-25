import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/pairing_lifecycle.dart';

void main() {
  test('stop invalidates all pending pairing operations', () {
    final lifecycle = PairingLifecycle();
    final initial = lifecycle.ticket;
    lifecycle.requireCurrent(initial);
    lifecycle.invalidate();
    expect(lifecycle.isCurrent(initial), isFalse);
    expect(() => lifecycle.requireCurrent(initial), throwsStateError);
  });

  test('restart cannot revive a stale pairing operation', () {
    final lifecycle = PairingLifecycle();
    final stale = lifecycle.ticket;
    lifecycle.invalidate();
    final fresh = lifecycle.ticket;
    expect(fresh, isNot(stale));
    lifecycle.requireCurrent(fresh);
    lifecycle.invalidate();
    expect(() => lifecycle.requireCurrent(fresh), throwsStateError);
    expect(() => lifecycle.requireCurrent(stale), throwsStateError);
  });
}
