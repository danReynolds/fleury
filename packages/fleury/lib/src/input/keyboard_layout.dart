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
/// 2. **A supplied table.** The constructor accepts a position→cap map for
///    an embedder that knows the layout out of band. Fleury bundles no
///    tables: a curated layout set is real data with a real maintenance
///    cost, and it ships when something consumes it (the sessions the
///    framework runs always learn instead).
///
/// Anything unknown stays unknown. There is deliberately no third tier that
/// invents a plausible label.
final class KeyboardLayout {
  KeyboardLayout({Map<KeyPosition, String>? table, this.tableName})
    : _table = table ?? const {};

  /// A layout with no table: only what the terminal teaches us.
  factory KeyboardLayout.learning() => KeyboardLayout();

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
  ///
  /// Returns true only when this taught something NEW, so the one caller that
  /// republishes on a change does it once per physical key rather than once
  /// per keystroke.
  bool observe(KeyEvent event) {
    final position = event.position;
    if (position == null) return false;
    final character = event.code.character;
    if (character == null || character.trim().isEmpty) return false;
    if (event.modifiers.isNotEmpty) return false;
    if (_learned[position] == character) return false;
    _learned[position] = character;
    return true;
  }

  /// The cap for [selector], or null when nothing is known.
  ///
  /// Rendered as the key actually produces it — unshifted and uncased. A
  /// caller that renders a chord uppercases the atom itself, matching how a
  /// logical step is labelled ([KeySequence.hintLabel]); doing it here would
  /// make `[q] Quit` and `[W] Thrust` sit side by side in one hint bar.
  ///
  /// A [KeyCode] is already the label — it IS what the cap says — so it
  /// resolves without any layout knowledge.
  KeyLabel? labelFor(KeySelector selector) {
    if (selector is KeyCode) {
      final character = selector.character;
      if (character == null) return null; // special: the caller's own label
      return KeyLabel(_render(character), KeyLabelSource.learned);
    }
    if (selector is! KeyPosition) return null;
    final learned = _learned[selector];
    if (learned != null) {
      return KeyLabel(_render(learned), KeyLabelSource.learned);
    }
    final tabled = _table[selector];
    if (tabled != null) return KeyLabel(_render(tabled), KeyLabelSource.table);
    return null;
  }

  static String _render(String character) =>
      character == ' ' ? 'Space' : character;

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
      // Replace only the atom, preserving any modifier prefix the step's own
      // label rendered (`Ctrl+W` → `Ctrl+Z`) — and matching its casing rule:
      // a chord uppercases its atom, a bare key does not.
      final original = steps[entry.key];
      final plus = original.lastIndexOf('+');
      steps[entry.key] = plus < 0
          ? label.text
          : '${original.substring(0, plus + 1)}${label.text.toUpperCase()}';
      substituted = true;
    }
    return substituted ? steps.join(' ') : sequence.hintLabel;
  }
}
