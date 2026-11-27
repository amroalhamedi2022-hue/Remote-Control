import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/file_peer_policy.dart';

void main() {
  test('routes files to both Android and Windows', () {
    expect(FilePeerPolicy.canSendTo('Android'), isTrue);
    expect(FilePeerPolicy.canSendTo('Windows'), isTrue);
  });
  test('rejects unknown and malformed discovery labels', () {
    for (final label in ['', 'iOS', 'Linux', 'android', 'Android ']) {
      expect(FilePeerPolicy.canSendTo(label), isFalse);
    }
  });
}
