// KeyHintBar: a one-line widget that auto-discovers the currently
// active key bindings by walking the focus chain and renders them as
// "[label] description · [label] description" along the available width.

import 'package:fleury/fleury_core.dart';

/// Walks the active focus chain and renders each visible binding as
/// "`[label] description`". Updates automatically when focus moves (because it
/// depends on the [FocusManager] via [Focus.of]).
///
/// Under width pressure it degrades **honestly**: it fits as many whole
/// bindings as the width allows and collapses the rest into a trailing `+N`,
/// rather than clipping a label mid-word or silently dropping the trailing
/// hints. Priority is chain order — the deepest / most local bindings are kept
/// first, and [globalBindings] (appended last) collapse into the `+N` first;
/// the marker is the affordance that a narrow terminal is hiding more (the
/// missing "no affordance" the plain-`Text` bar lacked). Pinning ubiquitous
/// globals like quit/help ahead of locals is a deliberate non-goal for now —
/// it would break the contiguous prefix + single trailing marker. A binding
/// bound to several aliases (`KeyBinding.any([↑, ↓], …)`) renders a
/// **combined** label — `[↑↓] move`, not just `[↑] move`.
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
    final hints = resolveActiveKeyBindings(
      manager,
      globalBindings: globalBindings,
    );
    if (hints.isEmpty) return const EmptyBox();
    // Highest-priority (deepest / most local) bindings come first; the hard
    // [maxBindings] cap bounds the candidate set before width fitting. `total`
    // (every visible hint, cap included) drives the "+N" count so bindings the
    // cap dropped are never silently lost.
    final total = hints.length;
    final segments = [
      for (final h in hints.take(maxBindings))
        '[${h.sequenceLabel}] ${h.binding.displayLabel}',
    ];
    // Fit whole bindings to the width the bar is actually given, degrading
    // with a trailing "+N" instead of clipping a label mid-word. Under an
    // unbounded width (maxCols == null) everything shows — the Text sizes to
    // content, so LayoutBuilder doesn't collapse.
    // styled component, not selectable text
    return SelectionArea.disabled(
      child: LayoutBuilder(
        builder: (context, constraints) => Text(
          _fit(segments, total, constraints.maxCols),
          style: style,
          softWrap: false,
        ),
      ),
    );
  }

  /// Renders the largest prefix of whole bindings (highest-priority first) that
  /// fits [maxCols], plus a trailing `+N` for every binding not shown — [total]
  /// counts ALL visible hints, so bindings the [maxBindings] cap dropped are
  /// counted too. Never clips a label mid-word. Under an unbounded width
  /// ([maxCols] null) it shows everything, with a `+N` only if the cap dropped
  /// some.
  String _fit(List<String> segments, int total, int? maxCols) {
    if (total == 0) return '';
    const resolver = DefaultWidthResolver();
    int width(String s) => resolver.widthOfText(s, TerminalProfile.standard);
    String withMarker(int k) {
      final hidden = total - k;
      final shown = segments.take(k).join(separator);
      return hidden == 0 ? shown : '$shown$separator+$hidden';
    }

    if (maxCols == null) return withMarker(segments.length);
    for (var k = segments.length; k >= 1; k--) {
      final s = withMarker(k);
      if (width(s) <= maxCols) return s;
    }
    // Not even one binding fits: the widest count marker that fits, then a bare
    // "+" (there is more), else nothing — never a wrong number clipped to fit.
    final marker = '+$total';
    if (width(marker) <= maxCols) return marker;
    return maxCols >= 1 ? '+' : '';
  }
}
