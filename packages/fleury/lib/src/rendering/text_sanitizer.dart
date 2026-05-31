/// Replacement character emitted in place of unsafe input bytes.
///
/// U+FFFD (the Unicode replacement character) renders as a single visible
/// glyph in every modern terminal. Using it preserves cell alignment and
/// makes corruption visible rather than invisible.
const String replacementCharacter = '�';

/// Returns true if [rune] is an unsafe terminal control code that must
/// never reach stdout as raw bytes.
///
/// Unsafe runes:
///   - C0 controls (0x00..0x1F), including ESC (0x1B)
///   - DEL (0x7F)
///   - C1 controls (0x80..0x9F)
///
/// LF/CR/TAB are also unsafe at the cell level: they have legitimate uses
/// at the *Text widget* level, where the widget splits them out before
/// handing safe content to the buffer. The renderer never sees them.
bool isUnsafeRune(int rune) {
  if (rune < 0x20) return true; // C0 controls including ESC
  if (rune == 0x7F) return true; // DEL
  if (rune >= 0x80 && rune <= 0x9F) return true; // C1 controls
  return false;
}

/// Returns a copy of [input] with every unsafe rune (see [isUnsafeRune])
/// replaced by [replacementCharacter].
///
/// This is the single safety boundary between strings produced by widget
/// code (which may contain arbitrary, possibly hostile content) and the
/// renderer's cell buffer. Application code should never bypass it.
String sanitizeForDisplay(String input) {
  // Fast path: scan once for any unsafe rune; if none, return the input
  // unchanged. Common case for app strings is "no controls at all."
  var unsafeAt = -1;
  var i = 0;
  for (final rune in input.runes) {
    if (isUnsafeRune(rune)) {
      unsafeAt = i;
      break;
    }
    i++;
  }
  if (unsafeAt == -1) return input;

  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (isUnsafeRune(rune)) {
      buffer.write(replacementCharacter);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
