import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/pair_consent_policy.dart';

void main() {
  test('approved consent is preserved', () async {
    expect(await PairConsentPolicy.awaitApproval(() async => true), isTrue);
  });

  test('explicit rejection stays rejected', () async {
    expect(await PairConsentPolicy.awaitApproval(() async => false), isFalse);
  });

  test('unanswered consent expires closed', () async {
    final never = Completer<bool>();
    expect(await PairConsentPolicy.awaitApproval(() => never.future,
      timeout: const Duration(milliseconds: 15)), isFalse);
  });

  test('failed consent UI never authorizes a peer', () async {
    expect(await PairConsentPolicy.awaitApproval(
      () async => throw StateError('dialog dismissed')), isFalse);
  });

  test('invalid deadline is rejected', () async {
    await expectLater(
      PairConsentPolicy.awaitApproval(() async => true, timeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
