import 'dart:convert';

/// Explicit text-only clipboard transfer, never automatic clipboard reading.
class ClipboardPolicy {
  static const maxBytes = 2048;

  static int validate(String text) {
    if (text.isEmpty) { throw const FormatException('Clipboard text is empty'); }
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c == 0xfffd || c <= 8 || c == 11 || c == 12 ||
          (c >= 14 && c <= 31) || c == 127 || (c >= 0x80 && c <= 0x9f)) {
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
    // Refuse invisible bidi/format controls that can visually disguise
    // commands or identities in the receiver's explicit approval dialog.
    // Ordinary Arabic letters/diacritics, emoji, tabs and newlines remain valid.
    for (final cp in text.runes) {
      if (cp == 0x00ad || cp == 0x034f || cp == 0x061c ||
          cp == 0x180e || cp >= 0x200b && cp <= 0x200f ||
          cp >= 0x202a && cp <= 0x202e ||
          cp >= 0x2060 && cp <= 0x206f ||
          cp == 0xfeff || cp >= 0xfff9 && cp <= 0xfffb ||
          cp >= 0xe0000 && cp <= 0xe007f) {
        throw const FormatException('Clipboard contains invisible direction controls');
      }
    }
    final bytes = utf8.encode(text).length;
    if (bytes > maxBytes) { throw const FormatException('Clipboard exceeds 2048 UTF-8 bytes'); }
    return bytes;
  }
}
