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
  if (isSanitizedForDisplay(input)) return input;

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

/// Whether [input] is already free of unsafe runes, i.e. whether
/// [sanitizeForDisplay] would return it unchanged.
///
/// Scans code units rather than runes: every unsafe rune is below U+00A0, and
/// no surrogate half falls in that range, so a code-unit scan is exactly
/// equivalent to a rune scan — and allocates neither an iterable nor an
/// iterator, which matters because this runs on every keystroke.
bool isSanitizedForDisplay(String input) =>
    !_hasUnsafeCodeUnit(input, allowLineFeed: false);

/// Whether [input] is already in the canonical multiline form, i.e. whether
/// [sanitizeMultiline] would return it unchanged.
bool isSanitizedMultiline(String input) =>
    !_hasUnsafeCodeUnit(input, allowLineFeed: true);

/// [sanitizeForDisplay] applied per LINE: every unsafe rune is replaced as
/// usual, but `\n` survives as a line separator.
///
/// This is the canonical form for text held by a multiline editing model. The
/// widget-level split into rows happens on `\n`, so the separator must not be
/// rewritten; everything else — including `\r` and `\t` — is still collapsed to
/// [replacementCharacter], and escape-led sequences are still collapsed as a
/// unit.
///
/// Returns [input] itself when it is already canonical, so the common
/// no-controls case allocates nothing.
String sanitizeMultiline(String input) {
  if (isSanitizedMultiline(input)) return input;
  return input.split('\n').map(sanitizeForDisplay).join('\n');
}

/// True when [input] holds a code unit that [sanitizeForDisplay] would rewrite.
///
/// With [allowLineFeed], `\n` is treated as safe — the multiline variant.
bool _hasUnsafeCodeUnit(String input, {required bool allowLineFeed}) {
  for (var index = 0; index < input.length; index++) {
    final unit = input.codeUnitAt(index);
    // Printable ASCII, and everything from U+00A0 up (surrogate halves
    // included, so astral runes never trip this).
    if (unit >= 0x20 && unit < 0x7F) continue;
    if (unit > 0x9F) continue;
    if (allowLineFeed && unit == 0x0A) continue;
    return true;
  }
  return false;
}

final _singleLineBreaks = RegExp(r'[\r\n\t]');

/// [sanitizeForDisplay] for a ONE-LINE label: newlines, carriage returns, and
/// tabs collapse to a single space FIRST, then the usual unsafe-rune sanitizing
/// runs. Order matters — `sanitizeForDisplay` treats `\r\n\t` as C0 controls and
/// rewrites them to [replacementCharacter], so a caller that sanitizes *then*
/// strips breaks gets `�` where a space belonged (the break is already gone).
/// Use this for single-line labels — table/tree rows, tool cards, log lines,
/// menu options — instead of hand-rolling the order per widget.
String sanitizeSingleLine(String input) =>
    sanitizeForDisplay(input.replaceAll(_singleLineBreaks, ' '));

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
