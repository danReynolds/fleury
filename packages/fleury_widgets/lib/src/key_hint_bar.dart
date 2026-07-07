// KeyHintBar: a one-line widget that auto-discovers the currently
// active key bindings by walking the focus chain and renders them as
// "[label] description · [label] description" along the available width.

import 'package:fleury/fleury_core.dart';

/// Walks the active focus chain and renders each visible binding as
/// "[label] description". Updates automatically when focus moves (because it
/// depends on the [FocusManager] via [Focus.of]).
///
/// Under width pressure it degrades **honestly**: it fits as many whole
/// bindings as the width allows (highest-priority first) and collapses the
/// rest into a trailing `+N`, rather than clipping a label mid-word or
/// silently dropping the trailing hints. A binding bound to several aliases
/// (`KeyBinding.list([↑, ↓], …)`) renders a **combined** label — `[↑↓] move`,
/// not just `[↑] move`.
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

  /// Hard cap on how many bindings are considered, applied before width
  /// fitting. Anything past the fitted width or this cap collapses into a
  /// trailing `+N` — so extra bindings degrade visibly rather than vanishing.
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
    // Highest-priority (deepest / most local) bindings come first; the hard
    // [maxBindings] cap bounds the candidate set before width fitting.
    final segments = [
      for (final h in hints.take(maxBindings))
        '[${_chordLabel(h)}] ${h.binding.displayLabel}',
    ];
    // Fit whole bindings to the width the bar is actually given, degrading
    // with a trailing "+N" instead of clipping a label mid-word. Under an
    // unbounded width (maxCols == null) everything shows — the Text sizes to
    // content, so LayoutBuilder doesn't collapse.
    return LayoutBuilder(
      builder: (context, constraints) => Text(
        _fit(segments, constraints.maxCols),
        style: style,
        softWrap: false,
      ),
    );
  }

  /// Combined chord label — `↑↓` for a multi-alias binding
  /// (`KeyBinding.list([↑, ↓], …)`), a single label otherwise.
  String _chordLabel(_Hint h) => h.chords.map((c) => c.hintLabel).join();

  /// Joins [segments] to fit [maxCols]: shows the largest prefix of whole
  /// bindings (they arrive highest-priority first) plus a trailing `+N` for
  /// the rest, and never clips a label mid-word. Shows everything when
  /// [maxCols] is null (unbounded width).
  String _fit(List<String> segments, int? maxCols) {
    if (segments.isEmpty) return '';
    final all = segments.join(separator);
    if (maxCols == null) return all;
    const resolver = DefaultWidthResolver();
    int width(String s) => resolver.widthOfText(s, TerminalProfile.standard);
    if (width(all) <= maxCols) return all;
    for (var k = segments.length - 1; k >= 1; k--) {
      final shown =
          '${segments.take(k).join(separator)}$separator+${segments.length - k}';
      if (width(shown) <= maxCols) return shown;
    }
    // Not even one binding plus the "+N" marker fits — show just the count.
    return '+${segments.length}';
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
      // The keys this binding can actually FIRE on right now: while a text
      // field holds focus, a bare-printable alias is swallowed as typed text,
      // so it neither fires nor claims a key. A binding with no firable alias
      // shows nothing and claims nothing (so it can't poison a shallower
      // binding that shares one of its dead aliases).
      final firable = [
        for (final c in binding.chords)
          if (!textFocused || !c.isShadowedByTextInput) c,
      ];
      if (firable.isEmpty) return;
      // The firable chords this binding OWNS: distinct, and not already claimed
      // by a DEEPER binding — dispatch is deepest-first, so a deeper binding
      // wins every key they share, and a shallower binding advertising a lost
      // key would lie. (Test only against what deeper bindings claimed, not
      // this binding's own earlier aliases — a repeated alias must not
      // self-suppress.) The bar combines the owned chords into one label.
      final owned = <KeyChord>[];
      final ownedLabels = <String>{};
      for (final c in firable) {
        if (seenChords.contains(c.hintLabel)) continue;
        if (ownedLabels.add(c.hintLabel)) owned.add(c);
      }
      if (owned.isEmpty) return; // every firable alias is claimed deeper
      // Now claim ALL of this binding's firable keys: it wins them for
      // dispatch, so a shallower binding bound to any of them is dead.
      for (final c in firable) {
        seenChords.add(c.hintLabel);
      }
      result.add(_Hint(binding, owned));
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

/// A binding paired with the firable chords the bar advertises for it — the
/// aliases that can actually fire in the current focus context, combined into
/// the rendered label.
class _Hint {
  const _Hint(this.binding, this.chords);
  final KeyBinding binding;
  final List<KeyChord> chords;
}
