import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/clipboard_policy.dart';

void main() {
  test('Arabic and emoji count UTF-8 bytes', () {
    expect(ClipboardPolicy.validate('مرحبًا 👋'), greaterThan(9));
    expect(ClipboardPolicy.validate(List.filled(512, '😀').join()), 2048);
  });
  test('invalid text and control characters are rejected', () {
    for (final bad in ['', '\u0000', 'x\u0007', 'x\uFFFD',
      List.filled(2049, 'x').join(), '\uD800', '\uDC00', '\uD800x',
      'invoice\u202Egpj.exe', 'hidden\u2066text', 'x\u200by', 'a\u061cb']) {
      expect(() => ClipboardPolicy.validate(bad), throwsFormatException);
    }
  });
  test('tabs, newlines and exact byte limit are supported', () {
    expect(ClipboardPolicy.validate('a\tb\nc'), 5);
    expect(ClipboardPolicy.validate(List.filled(2048, 'x').join()), 2048);
    expect(() => ClipboardPolicy.validate(List.filled(513, '😀').join()), throwsFormatException);
  });
}
