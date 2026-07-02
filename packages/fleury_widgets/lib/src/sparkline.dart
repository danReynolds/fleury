import 'package:fleury/fleury_core.dart';

import 'glyphs.dart';

/// A compact, single-row history graph of recent numeric values, rendered
/// with the eight vertical block elements (`▁▂▃▄▅▆▇█`).
///
/// Right-aligned (newest value on the right, like `htop`/`bashtop`); values
/// older than the available width are dropped from the left. Sized by the
/// parent — a row that fills its width by default, or wrap in `SizedBox`
/// for an explicit width.
///
/// ```dart
/// SizedBox(width: 20, child: Sparkline(data: cpuHistory));
/// ```
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.data,
    this.max,
    this.min = 0,
    this.color,
    this.style,
    this.showValue = false,
    this.semanticLabel = 'Sparkline',
  });

  /// The series of values to plot. The newest value goes on the right.
  final List<num> data;

  /// When true, append the latest value as muted text to the right of the
  /// sparkline — a shape alone doesn't convey magnitude (btop/bashtop show it).
  final bool showValue;

  /// Top of the visible range. `null` autoscales to the data window.
  final num? max;

  /// Baseline value. Defaults to 0.
  final num min;

  /// Foreground color override; defaults to the theme's primary.
  final Color? color;

  /// Full style override; takes precedence over [color].
  final CellStyle? style;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved =
        style ?? CellStyle(foreground: color ?? theme.colorScheme.primary);
    final latest = data.isEmpty ? null : data.last;
    final resolvedMax = max ?? _maxFinite(data);
    return Semantics(
      role: SemanticRole.chart,
      label: semanticLabel,
      value: latest?.toString(),
      state: SemanticState({
        'chartType': 'sparkline',
        'chartPointCount': data.length,
        'chartMinValue': min,
        'chartMaxValue': ?resolvedMax,
        'chartLatestValue': ?latest,
      }),
      child: showValue && latest != null
          ? Row(
              children: <Widget>[
                Expanded(
                  child: _RawSparkline(
                    data: data,
                    max: max,
                    min: min,
                    style: resolved,
                    glyphTier: MediaQuery.glyphTierOf(context),
                  ),
                ),
                Text(' ${_formatSparkValue(latest)}', style: theme.mutedStyle),
              ],
            )
          : _RawSparkline(
              data: data,
              max: max,
              min: min,
              style: resolved,
              glyphTier: MediaQuery.glyphTierOf(context),
            ),
    );
  }
}

String _formatSparkValue(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

num? _maxFinite(Iterable<num> values) {
  num? result;
  for (final value in values) {
    if (!value.toDouble().isFinite) continue;
    if (result == null || value > result) result = value;
  }
  return result;
}

class _RawSparkline extends LeafRenderObjectWidget {
  const _RawSparkline({
    required this.data,
    required this.max,
    required this.min,
    required this.style,
    required this.glyphTier,
  });

  final List<num> data;
  final num? max;
  final num min;
  final CellStyle style;
  final GlyphTier glyphTier;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSparkline(
    data: data,
    max: max,
    min: min,
    style: style,
    glyphTier: glyphTier,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSparkline renderObject,
  ) {
    renderObject
      ..data = data
      ..max = max
      ..min = min
      ..style = style
      ..glyphTier = glyphTier;
  }
}

/// Render object behind [Sparkline]. See its docs.
class RenderSparkline extends RenderObject {
  RenderSparkline({
    required List<num> data,
    required num? max,
    required num min,
    required CellStyle style,
    required GlyphTier glyphTier,
  }) : _data = data,
       _max = max,
       _min = min,
       _style = style,
       _glyphTier = glyphTier;

  List<num> _data;
  set data(List<num> v) {
    if (identical(_data, v)) return;
    final layoutChanged = _data.length != v.length;
    _data = v;
    if (layoutChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaintOnly();
    }
  }

  num? _max;
  set max(num? v) {
    if (_max == v) return;
    _max = v;
    markNeedsPaintOnly();
  }

  num _min;
  set min(num v) {
    if (_min == v) return;
    _min = v;
    markNeedsPaintOnly();
  }

  CellStyle _style;
  set style(CellStyle v) {
    if (_style == v) return;
    _style = v;
    markNeedsPaintOnly();
  }

  GlyphTier _glyphTier;
  set glyphTier(GlyphTier v) {
    if (_glyphTier == v) return;
    _glyphTier = v;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 10;
    return constraints.constrain(CellSize(cols, 1));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) => _data.length;
  @override
  int computeMaxIntrinsicHeight(int? width) => 1;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    if (w == 0 || size.rows == 0 || _data.isEmpty) return;

    // Take only the last `w` points so the newest value sits on the right.
    final start = _data.length > w ? _data.length - w : 0;
    final window = _data.sublist(start);
    // Left-pad the row so the window stays right-aligned in `w` columns.
    final leftPad = w - window.length;

    final minD = _min.toDouble();
    var maxD = _max?.toDouble();
    if (maxD == null) {
      var hi = window.first.toDouble();
      for (final v in window) {
        if (v > hi) hi = v.toDouble();
      }
      maxD = hi;
    }
    final range = maxD - minD;

    for (var i = 0; i < window.length; i++) {
      final col = offset.col + leftPad + i;
      final v = window[i].toDouble();
      int level;
      if (range <= 0) {
        // Degenerate range: render baseline cells when at-or-above min,
        // empty otherwise.
        level = v >= minD ? 1 : 0;
      } else {
        var t = (v - minD) / range;
        if (t <= 0) {
          level = 0;
        } else if (t >= 1) {
          level = 8;
        } else {
          // 1..8 — at least one block once we cross the baseline.
          level = (t * 8).ceil();
        }
      }
      if (level == 0) continue;
      buffer.writeGrapheme(
        CellOffset(col, offset.row),
        verticalLevelGlyph(_glyphTier, level),
        style: _style,
      );
    }
  }
}
