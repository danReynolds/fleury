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
/// Escape-led terminal control sequences are collapsed as a unit rather than
/// replacing only the ESC byte. That prevents active payloads such as OSC 52
/// clipboard writes, OSC 8 hyperlinks, Sixel/DCS data, or Kitty/APC image data
/// from leaking into displayed text after the leading control byte is removed.
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
  var index = 0;
  while (index < input.length) {
    final unit = input.codeUnitAt(index);
    if (unit == _esc) {
      buffer.write(replacementCharacter);
      index = _escapeSequenceEnd(input, index);
      continue;
    }
    if (unit == _csi) {
      buffer.write(replacementCharacter);
      index = _csiSequenceEnd(input, index + 1);
      continue;
    }
    if (unit == _osc) {
      buffer.write(replacementCharacter);
      index = _terminatedControlStringEnd(input, index + 1, allowBel: true);
      continue;
    }
    if (_isC1StringControl(unit)) {
      buffer.write(replacementCharacter);
      index = _terminatedControlStringEnd(input, index + 1);
      continue;
    }
    if (isUnsafeRune(unit)) {
      buffer.write(replacementCharacter);
      index += 1;
      continue;
    }
    if (_isHighSurrogate(unit) && index + 1 < input.length) {
      buffer.write(input.substring(index, index + 2));
      index += 2;
    } else {
      buffer.writeCharCode(unit);
      index += 1;
    }
  }
  return buffer.toString();
}

const _esc = 0x1B;
const _bel = 0x07;
const _st = 0x9C;
const _csi = 0x9B;
const _osc = 0x9D;
const _dcs = 0x90;
const _sos = 0x98;
const _pm = 0x9E;
const _apc = 0x9F;

int _escapeSequenceEnd(String input, int escIndex) {
  final nextIndex = escIndex + 1;
  if (nextIndex >= input.length) return nextIndex;

  final next = input.codeUnitAt(nextIndex);
  return switch (next) {
    0x5B => _csiSequenceEnd(input, nextIndex + 1), // ESC [
    0x5D => _terminatedControlStringEnd(
      input,
      nextIndex + 1,
      allowBel: true,
    ), // ESC ]
    0x50 ||
    0x58 ||
    0x5E ||
    0x5F => _terminatedControlStringEnd(input, nextIndex + 1), // ESC P/X/^/_
    >= 0x20 && <= 0x2F => _intermediateEscapeEnd(input, nextIndex + 1),
    >= 0x40 && <= 0x5F => nextIndex + 1,
    _ => nextIndex,
  };
}

int _csiSequenceEnd(String input, int start) {
  var index = start;
  while (index < input.length) {
    final unit = input.codeUnitAt(index);
    if (unit >= 0x40 && unit <= 0x7E) return index + 1;
    index += 1;
  }
  return input.length;
}

int _intermediateEscapeEnd(String input, int start) {
  var index = start;
  while (index < input.length) {
    final unit = input.codeUnitAt(index);
    if (unit >= 0x30 && unit <= 0x7E) return index + 1;
    index += 1;
  }
  return input.length;
}

int _terminatedControlStringEnd(
  String input,
  int start, {
  bool allowBel = false,
}) {
  var index = start;
  while (index < input.length) {
    final unit = input.codeUnitAt(index);
    if (allowBel && unit == _bel) return index + 1;
    if (unit == _st) return index + 1;
    if (unit == _esc &&
        index + 1 < input.length &&
        input.codeUnitAt(index + 1) == 0x5C) {
      return index + 2;
    }
    index += 1;
  }
  return input.length;
}

bool _isC1StringControl(int unit) {
  return unit == _dcs || unit == _sos || unit == _pm || unit == _apc;
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
