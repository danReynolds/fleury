// KeyHintBar: a one-line widget that auto-discovers the currently
// active key bindings by walking the focus chain and renders them as
// "hint description · hint description" along the available width.

import '../rendering/cell.dart';
import 'basic.dart';
import 'focus.dart';
import 'framework.dart';
import 'key_bindings.dart';

/// Walks the active focus chain and renders each visible binding as
/// "[label]". Updates automatically when focus moves (because it
/// depends on the [FocusManager] via [Focus.of]).
///
/// Filtering rules:
///   1. Bindings with `label == null` are hidden (the chord's
///      auto-label alone isn't enough — a binding needs a written
///      label to qualify for the bar).
///   2. Bindings with `hideFromHintBar: true` are hidden.
///   3. Bindings with `enabled: false` are hidden.
///   4. Duplicate chords keep the nearest (deeper) binding.
///   5. Global bindings (passed via [globalBindings]) appear last.
class KeyHintBar extends StatelessWidget {
  const KeyHintBar({
    super.key,
    this.maxBindings = 12,
    this.separator = ' · ',
    this.style = CellStyle.empty,
    this.globalBindings = const [],
  });

  /// Maximum number of bindings to render. Bindings beyond this limit
  /// are silently dropped. Keep small to avoid wrapping issues.
  final int maxBindings;

  /// Separator between bindings. Default: `' · '`.
  final String separator;

  /// Style applied to the entire rendered text.
  final CellStyle style;

  /// Bindings from `runApp`'s `globalBindings` parameter. Pass these
  /// in explicitly so the hint bar can show them; the framework
  /// doesn't currently expose them via an InheritedWidget.
  final List<KeyBinding> globalBindings;

  @override
  Widget build(BuildContext context) {
    final manager = Focus.maybeOf(context);
    if (manager == null) return const EmptyBox();
    final hints = _collectVisibleHints(manager);
    if (hints.isEmpty) return const EmptyBox();
    final rendered = hints
        .take(maxBindings)
        .map((h) => '[${h.chord.hintLabel}] ${h.binding.displayLabel}')
        .join(separator);
    return Text(rendered, style: style, softWrap: false);
  }

  List<_Hint> _collectVisibleHints(FocusManager manager) {
    final result = <_Hint>[];
    final seenChords = <String>{};
    // Honesty filter: while a text field holds focus, bare-printable chords —
    // chain and global alike — are swallowed as typed text and can never
    // fire. Shadowing is a PER-CHORD property: a binding with several aliases
    // (`KeyBinding.list([j, ↓], …)`) stays visible through its first
    // non-shadowed chord (dispatch fires on any alias), and is hidden only
    // when every alias is shadowed. Modifier/function chords (Ctrl+S, F1,
    // Esc) bypass the text claimant and stay shown.
    final textFocused = manager.focusedNodeClaimsText;

    void consider(KeyBinding binding) {
      if (binding.label == null) return;
      if (binding.hideFromHintBar) return;
      if (!binding.enabled) return;
      // Dedup registers EVERY alias this binding would fire on (dispatch is
      // deepest-first over all chords), so a shallower binding can't surface
      // a label for a key a deeper binding actually claims. Advertise the
      // first alias that isn't text-shadowed.
      KeyChord? advertise;
      var alreadyClaimed = false;
      for (final c in binding.chords) {
        final key = c.hintLabel;
        if (seenChords.contains(key)) alreadyClaimed = true;
        seenChords.add(key);
        if (advertise == null && !(textFocused && c.isShadowedByTextInput)) {
          advertise = c;
        }
      }
      if (alreadyClaimed) return; // a deeper binding owns one of these keys
      if (advertise == null) return; // every alias is text-shadowed
      result.add(_Hint(binding, advertise));
    }

    for (final node in manager.activeChain()) {
      final source = node.bindingSource;
      if (source == null) continue;
      for (final binding in source.activeBindings) {
        consider(binding);
      }
    }
    if (!manager.suppressGlobals) {
      for (final binding in globalBindings) {
        consider(binding);
      }
    }
    return result;
  }
}

/// A binding paired with the chord the bar advertises for it — the first
/// alias that can actually fire in the current focus context.
class _Hint {
  const _Hint(this.binding, this.chord);
  final KeyBinding binding;
  final KeyChord chord;
}
