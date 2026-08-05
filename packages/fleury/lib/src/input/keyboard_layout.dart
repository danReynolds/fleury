// RFC 0020 §9 — naming a physical key the way the user's keyboard does.
//
// A KeyPosition names a SPOT ("where W sits on QWERTY"). Rendering that spot
// as "W" to someone on AZERTY is a lie: the key under that finger is capped
// Z, and on Dvorak it is comma. Since the framework's own hint bar exists to
// tell people what to press, it must not be the thing that misleads them.

import 'events.dart';

/// Where a label came from — how much to trust it.
enum KeyLabelSource {
  /// Observed from this terminal's own reports (Kitty flag 4 pairs a
  /// physical position with the character it produced). Authoritative: it
  /// is this keyboard, right now.
  learned,

  /// A bundled per-layout table, selected by configuration or environment.
  /// Right for the named layout, but an assumption about which one is in
  /// use.
  table,

  /// Nothing known. Callers render the position honestly rather than
  /// guessing — "the key at QWERTY-W", not "W".
  unknown,
}

/// A label plus its provenance.
final class KeyLabel {
  const KeyLabel(this.text, this.source);

  final String text;
  final KeyLabelSource source;

  @override
  String toString() => '$text (${source.name})';
}

/// Maps physical key positions to the caps the user actually has.
///
/// Populated two ways, most trustworthy first:
///
/// 1. **Learned.** Where the terminal reports alternate keys (Kitty flag 4),
///    every press carries both its logical code and its physical position —
///    which IS the mapping, observed rather than assumed. Fills in one key
///    per first press, so it is a slow-filling cache and never the
///    first-paint story.
/// 2. **A named table.** Bundled layouts for the common non-US keyboards.
///    Selected explicitly; a guess about which layout is in use, but a
///    correct one for that layout.
///
/// Anything unknown stays unknown. There is deliberately no third tier that
/// invents a plausible label.
final class KeyboardLayout {
  KeyboardLayout({Map<KeyPosition, String>? table, this.tableName})
    : _table = table ?? const {};

  /// A layout with no table: only what the terminal teaches us.
  factory KeyboardLayout.learning() => KeyboardLayout();

  /// One of the bundled layouts by name (`fr-azerty`, `de-qwertz`,
  /// `tr-q`, `dvorak`), or a learning-only layout when the name is unknown.
  factory KeyboardLayout.named(String name) {
    final table = bundledKeyboardLayouts[name.toLowerCase()];
    if (table == null) return KeyboardLayout.learning();
    return KeyboardLayout(table: table, tableName: name.toLowerCase());
  }

  final Map<KeyPosition, String> _table;
  final Map<KeyPosition, String> _learned = {};

  /// The bundled table in use, if any.
  final String? tableName;

  /// Records what the terminal just told us: this position produced this
  /// key. Framework-internal; fed from the regularized event stream.
  ///
  /// Only unmodified, printable reports teach anything — a chord reports
  /// the base key, and a functional key's identity is layout-independent
  /// already.
  void observe(KeyEvent event) {
    final position = event.position;
    if (position == null) return;
    final character = event.code.character;
    if (character == null || character.trim().isEmpty) return;
    if (event.modifiers.isNotEmpty) return;
    _learned[position] = character;
  }

  /// The cap for [selector], or null when nothing is known.
  ///
  /// A [KeyCode] is already the label — it IS what the cap says — so it
  /// resolves without any layout knowledge.
  KeyLabel? labelFor(KeySelector selector) {
    if (selector is KeyCode) {
      final character = selector.character;
      if (character != null) {
        return KeyLabel(
          character == ' ' ? 'Space' : character.toUpperCase(),
          KeyLabelSource.learned,
        );
      }
      return null; // a special key: the caller's own label applies
    }
    if (selector is! KeyPosition) return null;
    final learned = _learned[selector];
    if (learned != null) {
      return KeyLabel(
        learned == ' ' ? 'Space' : learned.toUpperCase(),
        KeyLabelSource.learned,
      );
    }
    final tabled = _table[selector];
    if (tabled != null) {
      return KeyLabel(
        tabled == ' ' ? 'Space' : tabled.toUpperCase(),
        KeyLabelSource.table,
      );
    }
    return null;
  }

  /// A hint-bar-ready label for [sequence], substituting real caps for any
  /// positional step.
  ///
  /// Falls back to the sequence's own [KeySequence.hintLabel] when nothing
  /// positional is involved, so the common case is unchanged.
  String labelForSequence(KeySequence sequence) {
    final steps = <String>[];
    var substituted = false;
    for (var i = 0; i < sequence.stepCount; i++) {
      final step = sequence.stepLabelAt(i);
      if (step == null) return sequence.hintLabel;
      steps.add(step);
    }
    final positions = sequence.positionalSteps;
    if (positions.isEmpty) return sequence.hintLabel;
    for (final entry in positions.entries) {
      final label = labelFor(entry.value);
      if (label == null) continue;
      // Replace only the atom, preserving any modifier prefix the step's
      // own label rendered (`Ctrl+W` → `Ctrl+Z`).
      final original = steps[entry.key];
      final plus = original.lastIndexOf('+');
      steps[entry.key] = plus < 0
          ? label.text
          : '${original.substring(0, plus + 1)}${label.text}';
      substituted = true;
    }
    return substituted ? steps.join(' ') : sequence.hintLabel;
  }
}

/// Bundled cap tables for the layouts whose letter/digit block differs most
/// from US-QWERTY. Keyed by position; the value is the unmodified cap.
///
/// Deliberately partial: only the keys that actually move. A position absent
/// from a table produces the same character it does on US-QWERTY, which is
/// what [KeyPosition.usTwin] already reports.
const Map<String, Map<KeyPosition, String>> bundledKeyboardLayouts = {
  // French AZERTY: A↔Q, Z↔W swap, M moves off the home row, and the digit
  // row is shifted (its unmodified caps are punctuation).
  'fr-azerty': {
    KeyPosition.q: 'a',
    KeyPosition.a: 'q',
    KeyPosition.w: 'z',
    KeyPosition.z: 'w',
    KeyPosition.semicolon: 'm',
    KeyPosition.m: ',',
    KeyPosition.comma: ';',
    KeyPosition.period: ':',
    KeyPosition.slash: '!',
  },
  // German QWERTZ: Y↔Z, plus the umlaut keys on the punctuation cluster.
  'de-qwertz': {
    KeyPosition.y: 'z',
    KeyPosition.z: 'y',
    KeyPosition.semicolon: 'ö',
    KeyPosition.quote: 'ä',
    KeyPosition.bracketLeft: 'ü',
    KeyPosition.minus: 'ß',
  },
  // Turkish-Q: the letters stay put; the punctuation cluster carries the
  // dotted/dotless i and friends.
  'tr-q': {
    KeyPosition.bracketLeft: 'ğ',
    KeyPosition.bracketRight: 'ü',
    KeyPosition.semicolon: 'ş',
    KeyPosition.quote: 'i',
    KeyPosition.comma: 'ö',
    KeyPosition.period: 'ç',
  },
  // Dvorak: almost nothing is where QWERTY puts it — the layout that makes
  // "just render the US name" most obviously wrong.
  'dvorak': {
    KeyPosition.q: "'",
    KeyPosition.w: ',',
    KeyPosition.e: '.',
    KeyPosition.r: 'p',
    KeyPosition.t: 'y',
    KeyPosition.y: 'f',
    KeyPosition.u: 'g',
    KeyPosition.i: 'c',
    KeyPosition.o: 'r',
    KeyPosition.p: 'l',
    KeyPosition.a: 'a',
    KeyPosition.s: 'o',
    KeyPosition.d: 'e',
    KeyPosition.f: 'u',
    KeyPosition.g: 'i',
    KeyPosition.h: 'd',
    KeyPosition.j: 'h',
    KeyPosition.k: 't',
    KeyPosition.l: 'n',
    KeyPosition.semicolon: 's',
    KeyPosition.z: ';',
    KeyPosition.x: 'q',
    KeyPosition.c: 'j',
    KeyPosition.v: 'k',
    KeyPosition.b: 'x',
    KeyPosition.n: 'b',
    KeyPosition.m: 'm',
    KeyPosition.comma: 'w',
    KeyPosition.period: 'v',
    KeyPosition.slash: 'z',
  },
};
