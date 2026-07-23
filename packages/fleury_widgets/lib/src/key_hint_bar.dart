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
    this.keyStyle,
    this.globalBindings = const [],
  });

  /// Hard cap on how many bindings are considered, applied before width
  /// fitting. Anything past the fitted width or this cap collapses into a
  /// trailing `+N` — so extra bindings degrade visibly rather than vanishing.
  final int maxBindings;

  /// Separator between bindings. Default: `' · '`.
  final String separator;

  /// Style applied to the description text (and separators / `+N` marker).
  final CellStyle style;

  /// Style for the `[key chord]` portion of each hint, so the chord reads
  /// distinctly from its description (Terminal.Gui's "Hot" idea, for a
  /// keyboard-first bar). Defaults to the theme's focus colour, bold, layered
  /// on [style].
  final CellStyle? keyStyle;

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
    final resolvedKeyStyle =
        keyStyle ??
        style.merge(CellStyle(foreground: context.colors.focus, bold: true));
    return LayoutBuilder(
      builder: (context, constraints) => _styledBar(
        _fit(segments, total, constraints.maxCols),
        resolvedKeyStyle,
      ),
    );
  }

  /// Renders [text] with each `[chord]` run in [keyStyle] and everything else
  /// (descriptions, separators, the `+N` marker) in [style]. Splits on the
  /// literal brackets the segments were built with, so the fitted width is
  /// unchanged — only the colouring differs.
  Widget _styledBar(String text, CellStyle keyStyle) {
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final open = text.indexOf('[', cursor);
      if (open < 0) {
        spans.add(TextSpan(text: text.substring(cursor), style: style));
        break;
      }
      if (open > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, open), style: style));
      }
      final close = text.indexOf(']', open);
      if (close < 0) {
        spans.add(TextSpan(text: text.substring(open), style: style));
        break;
      }
      spans.add(
        TextSpan(text: text.substring(open, close + 1), style: keyStyle),
      );
      cursor = close + 1;
    }
    return RichText(text: TextSpan(children: spans), softWrap: false);
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
