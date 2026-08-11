import 'package:meta/meta.dart';

import '../input/events.dart';

/// One fixed legacy terminal byte sequence and its semantic key.
@immutable
final class LegacyKeySequence {
  const LegacyKeySequence(
    this.sequence,
    this.key, {
    this.modifiers = const <KeyModifier>{},
  });

  /// ASCII escape sequence as emitted by the terminal.
  final String sequence;
  final KeyCode key;
  final Set<KeyModifier> modifiers;
}

/// Small built-in compatibility table for sequences outside CSI/SS3 grammar.
///
/// Linux-console F1–F5 use an extra `[` (`ESC [[ A` through `ESC [[ E`).
/// Other widespread keys remain grammar-driven, avoiding a duplicate xterm
/// table that could drift from the parser's modifier handling.
const builtInLegacyKeySequences = <LegacyKeySequence>[
  LegacyKeySequence('\x1b[[A', KeyCode.f1),
  LegacyKeySequence('\x1b[[B', KeyCode.f2),
  LegacyKeySequence('\x1b[[C', KeyCode.f3),
  LegacyKeySequence('\x1b[[D', KeyCode.f4),
  LegacyKeySequence('\x1b[[E', KeyCode.f5),
];
