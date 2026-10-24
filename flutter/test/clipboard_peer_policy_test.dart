import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/clipboard_peer_policy.dart';

void main() {
  test('one-shot clipboard may target either Android or Windows', () {
    expect(ClipboardPeerPolicy.canSendTo('Android'), isTrue);
    expect(ClipboardPeerPolicy.canSendTo('Windows'), isTrue);
  });

  test('untrusted discovery cannot route clipboard to arbitrary platform', () {
    for (final platform in ['', 'Linux', 'Web', 'android', 'Windows ',
      'Android\u202E', 'Windows/Android']) {
      expect(ClipboardPeerPolicy.canSendTo(platform), isFalse);
    }
  });
}
