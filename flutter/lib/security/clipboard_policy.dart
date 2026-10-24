import 'dart:convert';

/// Explicit text-only clipboard transfer, never automatic clipboard reading.
class ClipboardPolicy {
  static const maxBytes = 2048;

  static int validate(String text) {
    if (text.isEmpty) throw const FormatException('Clipboard text is empty');
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c == 0xfffd || c <= 8 || c == 11 || c == 12 ||
          (c >= 14 && c <= 31) || c == 127) {
        throw const FormatException('Clipboard text contains invalid characters');
      }
      if (c >= 0xd800 && c <= 0xdbff) {
        if (i + 1 >= units.length || units[i + 1] < 0xdc00 || units[i + 1] > 0xdfff) {
          throw const FormatException('Invalid UTF-16 surrogate');
        }
        i++;
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        throw const FormatException('Invalid UTF-16 surrogate');
      }
    }
    final bytes = utf8.encode(text).length;
    if (bytes > maxBytes) throw const FormatException('Clipboard exceeds 2048 UTF-8 bytes');
    return bytes;
  }
}
