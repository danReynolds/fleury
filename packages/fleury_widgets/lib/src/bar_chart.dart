import 'package:fleury/fleury.dart';

/// One column in a [BarChart].
///
/// A single-value bar uses [Bar.new] with one [value]. For stacked bars,
/// pass multiple values to [Bar.stacked] — segments paint bottom→top and
/// each takes the next color from the chart's palette (or [colors] when
/// explicitly provided).
class Bar {
  /// A single-value bar.
  const Bar(this.label, num this.value, {this.color})
    : segments = const [],
      colors = const [];

  /// A stacked bar of [segments] (rendered bottom→top). Segment heights
  /// sum to determine the bar's total height. [colors] (optional) pairs
  /// each segment with an explicit color — by index, falling back to the
  /// chart's palette for any unspecified index.
  const Bar.stacked(this.label, this.segments, {this.colors = const []})
    : value = null,
      color = null;

  /// Bar label drawn below the column (when `showLabels: true`).
  final String label;

  /// The bar's single value, or null when [segments] is non-empty.
  final num? value;

  /// Stacked segment values (bottom→top). Empty for single-value bars.
  final List<num> segments;

  /// Fill color for a single-value bar.
  final Color? color;

  /// Optional per-segment colors for stacked bars. Padded by the chart
  /// palette when shorter than [segments].
  final List<Color> colors;

  /// The bar's total magnitude — `value` for single bars, segment sum for
  /// stacked bars. Used for autoscale and the value label.
  num get total {
    if (segments.isNotEmpty) {
      num s = 0;
      for (final v in segments) {
        s += v;
      }
      return s;
    }
    return value ?? 0;
  }
}

/// A vertical bar chart with optional category labels (below) and value
/// labels (above). Bar heights are rendered with the eight vertical block
/// elements (`▁▂▃▄▅▆▇█`), so partial cells render proportionally.
///
/// Supports both single-value bars ([Bar.new]) and stacked bars
/// ([Bar.stacked]) — stacked segments cycle through the chart [palette]
/// for distinct colors.
///
/// The widget sizes itself to its bars by default (`barWidth × N + gaps`
/// wide, plus a row of labels and/or values). Bound the height with a
/// parent and it fills the available rows; bound the width and it clips
/// the visible bars.
///
/// ```dart
/// BarChart(bars: const [
///   Bar('a', 12), Bar('b', 8), Bar('c', 5),
/// ]);
///
/// // Stacked: cpu/mem/disk per host
/// BarChart(bars: const [
///   Bar.stacked('host-a', [40, 30, 10]),
///   Bar.stacked('host-b', [55, 25,  5]),
/// ]);
/// ```
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.bars,
    this.max,
    this.barWidth = 2,
    this.gap = 1,
    this.palette,
    this.segmentLabels,
    this.showLabels = true,
    this.showValues = false,
    this.showLegend = false,
    this.semanticLabel = 'Bar chart',
  });

  /// The bars, left to right.
  final List<Bar> bars;

  /// Top of the visible range. `null` autoscales to the data.
  final num? max;

  /// Cells per bar (must be ≥ 1).
  final int barWidth;

  /// Cells between bars.
  final int gap;

  /// Colors used for stacked-bar segments and as the default for
  /// single-value bars that don't set [Bar.color] explicitly. Defaults to
  /// a palette derived from the theme's color scheme (primary, info,
  /// warning, success, error).
  ///
  /// For stacked bars where segments are categorical (no semantic
  /// meaning), prefer overriding with [Palettes.categorical] to avoid
  /// implying that a yellow segment is a "warning" or red is "error".
  final List<Color>? palette;

  /// Labels for stacked-bar segments, parallel to each [Bar.stacked]'s
  /// `segments` list. Required for the legend to render — without it,
  /// stacked bars are unreadable, so peer libs all auto-emit one.
  final List<String>? segmentLabels;

  /// Whether to draw a row of category labels under the chart.
  final bool showLabels;

  /// Whether to draw a row of value labels above each bar.
  final bool showValues;

  /// Draw a one-row legend at the top-right mapping the palette colors
  /// to [segmentLabels]. Quietly skipped if [segmentLabels] is null/
  /// empty or the chart is too narrow to fit it.
  final bool showLegend;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p =
        palette ?? [cs.primary, cs.info, cs.warning, cs.success, cs.error];
    return Semantics(
      role: SemanticRole.chart,
      label: semanticLabel,
      state: _barChartSemanticState(bars, max),
      child: _RawBarChart(
        bars: bars,
        max: max,
        barWidth: barWidth,
        gap: gap,
        showLabels: showLabels,
        showValues: showValues,
        showLegend: showLegend,
        segmentLabels: segmentLabels,
        palette: p,
        defaultColor: p.isNotEmpty ? p.first : cs.primary,
        labelStyle: theme.mutedStyle,
      ),
    );
  }
}

SemanticState _barChartSemanticState(List<Bar> bars, num? explicitMax) {
  num? minValue;
  num? maxValue = explicitMax;
  var segmentCount = 0;
  for (final bar in bars) {
    final total = bar.total;
    if (total.toDouble().isFinite) {
      if (minValue == null || total < minValue) minValue = total;
      if (maxValue == null || total > maxValue) maxValue = total;
    }
    segmentCount += bar.segments.isEmpty ? 1 : bar.segments.length;
  }
  return SemanticState({
    'chartType': 'bar',
    'chartBarCount': bars.length,
    'chartSegmentCount': segmentCount,
    'chartMinValue': ?minValue,
    'chartMaxValue': ?maxValue,
  });
}

class _RawBarChart extends LeafRenderObjectWidget {
  const _RawBarChart({
    required this.bars,
    required this.max,
    required this.barWidth,
    required this.gap,
    required this.showLabels,
    required this.showValues,
    required this.showLegend,
    required this.segmentLabels,
    required this.palette,
    required this.defaultColor,
    required this.labelStyle,
  });

  final List<Bar> bars;
  final num? max;
  final int barWidth;
  final int gap;
  final bool showLabels;
  final bool showValues;
  final bool showLegend;
  final List<String>? segmentLabels;
  final List<Color> palette;
  final Color defaultColor;
  final CellStyle labelStyle;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBarChart(
    bars: bars,
    max: max,
    barWidth: barWidth,
    gap: gap,
    showLabels: showLabels,
    showValues: showValues,
    showLegend: showLegend,
    segmentLabels: segmentLabels,
    palette: palette,
    defaultColor: defaultColor,
    labelStyle: labelStyle,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBarChart renderObject,
  ) {
    renderObject
      ..bars = bars
      ..max = max
      ..barWidth = barWidth
      ..gap = gap
      ..showLabels = showLabels
      ..showValues = showValues
      ..showLegend = showLegend
      ..segmentLabels = segmentLabels
      ..palette = palette
      ..defaultColor = defaultColor
      ..labelStyle = labelStyle;
  }
}

/// Render object behind [BarChart]. See its docs.
class RenderBarChart extends RenderObject {
  RenderBarChart({
    required List<Bar> bars,
    required num? max,
    required int barWidth,
    required int gap,
    required bool showLabels,
    required bool showValues,
    required bool showLegend,
    required List<String>? segmentLabels,
    required List<Color> palette,
    required Color defaultColor,
    required CellStyle labelStyle,
  }) : _bars = bars,
       _max = max,
       _barWidth = barWidth < 1 ? 1 : barWidth,
       _gap = gap < 0 ? 0 : gap,
       _showLabels = showLabels,
       _showValues = showValues,
       _showLegend = showLegend,
       _segmentLabels = segmentLabels,
       _palette = palette,
       _defaultColor = defaultColor,
       _labelStyle = labelStyle;

  List<Bar> _bars;
  set bars(List<Bar> v) {
    if (identical(_bars, v)) return;
    final layoutChanged = _bars.length != v.length;
    _bars = v;
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

  int _barWidth;
  set barWidth(int v) {
    final clamped = v < 1 ? 1 : v;
    if (_barWidth == clamped) return;
    _barWidth = clamped;
    markNeedsLayout();
  }

  int _gap;
  set gap(int v) {
    final clamped = v < 0 ? 0 : v;
    if (_gap == clamped) return;
    _gap = clamped;
    markNeedsLayout();
  }

  bool _showLabels;
  set showLabels(bool v) {
    if (_showLabels == v) return;
    _showLabels = v;
    markNeedsLayout();
  }

  bool _showValues;
  set showValues(bool v) {
    if (_showValues == v) return;
    _showValues = v;
    markNeedsLayout();
  }

  bool _showLegend;
  set showLegend(bool v) {
    if (_showLegend == v) return;
    _showLegend = v;
    markNeedsLayout();
  }

  List<String>? _segmentLabels;
  set segmentLabels(List<String>? v) {
    if (identical(_segmentLabels, v)) return;
    _segmentLabels = v;
    markNeedsLayout();
  }

  List<Color> _palette;
  set palette(List<Color> v) {
    if (identical(_palette, v)) return;
    _palette = v;
    markNeedsPaintOnly();
  }

  Color _defaultColor;
  set defaultColor(Color v) {
    if (_defaultColor == v) return;
    _defaultColor = v;
    markNeedsPaintOnly();
  }

  CellStyle _labelStyle;
  set labelStyle(CellStyle v) {
    if (_labelStyle == v) return;
    _labelStyle = v;
    markNeedsPaintOnly();
  }

  static const _partials = ['', '▁', '▂', '▃', '▄', '▅', '▆', '▇'];
  static const _full = '█';

  bool get _legendActive {
    if (!_showLegend) return false;
    final labels = _segmentLabels;
    return labels != null && labels.isNotEmpty;
  }

  int get _chromeRows =>
      (_showLabels ? 1 : 0) + (_showValues ? 1 : 0) + (_legendActive ? 1 : 0);

  int get _naturalWidth {
    if (_bars.isEmpty) return 0;
    return _bars.length * _barWidth + (_bars.length - 1) * _gap;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final desiredWidth = _naturalWidth;
    final cols = constraints.hasBoundedWidth
        ? (desiredWidth < constraints.maxCols!
              ? desiredWidth
              : constraints.maxCols!)
        : desiredWidth;
    final rows = constraints.hasBoundedHeight
        ? constraints.maxRows!
        : (8 + _chromeRows); // sensible default for unbounded
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) => _naturalWidth;
  @override
  int computeMinIntrinsicWidth(int? height) => _naturalWidth;
  @override
  int computeMaxIntrinsicHeight(int? width) => 8 + _chromeRows;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    final h = size.rows;
    if (w == 0 || h == 0 || _bars.isEmpty) return;

    final chartRows = h - _chromeRows;
    if (chartRows < 1) return;

    var topVal = _max?.toDouble();
    if (topVal == null) {
      var hi = _bars.first.total.toDouble();
      for (final b in _bars) {
        final v = b.total.toDouble();
        if (v > hi) hi = v;
      }
      topVal = hi;
    }
    if (topVal <= 0) topVal = 1; // avoid /0; degenerate input still renders.

    // Top-to-bottom row layout: optional legend → optional value labels
    // → chart body → optional category labels. The legend sits above
    // value labels so it doesn't break their visual association with
    // the bar tops.
    final legendRow = _legendActive ? offset.row : null;
    final valueRow = _showValues ? offset.row + (_legendActive ? 1 : 0) : null;
    final chartTopRow =
        offset.row + (_legendActive ? 1 : 0) + (_showValues ? 1 : 0);
    final labelRow = _showLabels ? chartTopRow + chartRows : null;

    if (legendRow != null) {
      _paintLegend(buffer, legendRow, offset.col, w);
    }

    // Clip bars that start past the buffer's right edge — at tight
    // widths the natural width exceeds the box, and we silently drop
    // overflowing bars rather than crashing on out-of-bounds writes.
    final rightEdge = offset.col + w;
    var col = offset.col;
    for (var i = 0; i < _bars.length; i++) {
      if (i > 0) col += _gap;
      if (col >= rightEdge) break;
      final b = _bars[i];

      if (b.segments.isNotEmpty) {
        _paintStackedBar(buffer, b, col, chartTopRow, chartRows, topVal);
      } else {
        _paintSingleBar(buffer, b, col, chartTopRow, chartRows, topVal);
      }

      // Value label above the bar — totals for stacked.
      if (valueRow != null) {
        final text = _formatValue(b.total);
        _writeCentered(buffer, col, valueRow, _barWidth, text, _labelStyle);
      }

      // Category label below.
      if (labelRow != null) {
        _writeCentered(buffer, col, labelRow, _barWidth, b.label, _labelStyle);
      }

      col += _barWidth;
    }
  }

  /// Paints a single-value [bar] starting at column [col]. Top of bar
  /// uses a partial 1/8 glyph; full cells below use `█`.
  void _paintSingleBar(
    CellBuffer buffer,
    Bar bar,
    int col,
    int chartTopRow,
    int chartRows,
    double topVal,
  ) {
    final style = CellStyle(foreground: bar.color ?? _defaultColor);
    final ticks = ((bar.value!.toDouble() / topVal) * chartRows * 8).round();
    final fullRows = ticks ~/ 8;
    final partial = ticks % 8;
    final hasPartial = partial > 0 && fullRows < chartRows;
    final paintedRows = fullRows + (hasPartial ? 1 : 0);
    final firstFilledRow = chartRows - paintedRows;

    for (var r = 0; r < chartRows; r++) {
      if (r < firstFilledRow) continue;
      final isTop = r == firstFilledRow;
      final glyph = (isTop && hasPartial) ? _partials[partial] : _full;
      for (var x = 0; x < _barWidth; x++) {
        final tgt = col + x;
        if (tgt < 0 || tgt >= buffer.size.cols) continue;
        final row = chartTopRow + r;
        if (row < 0 || row >= buffer.size.rows) continue;
        buffer.writeGrapheme(CellOffset(tgt, row), glyph, style: style);
      }
    }
  }

  /// Paints a stacked bar — segments bottom→top, each in its own color.
  /// Only the top of the topmost non-zero segment uses a partial glyph;
  /// intermediate segment boundaries always land on full cells. (Trying
  /// to draw a partial mid-stack would alpha-blend two colors into one
  /// cell, which the terminal can't represent.)
  void _paintStackedBar(
    CellBuffer buffer,
    Bar bar,
    int col,
    int chartTopRow,
    int chartRows,
    double topVal,
  ) {
    // Compute each segment's pixel-eighths height. Carry rounding error
    // forward so cumulative tops match the bar's overall total.
    final n = bar.segments.length;
    final totalTicks = ((bar.total.toDouble() / topVal) * chartRows * 8)
        .round();
    final segTicks = List<int>.filled(n, 0);
    var runningTicks = 0;
    var totalAssigned = 0;
    for (var i = 0; i < n; i++) {
      runningTicks += ((bar.segments[i].toDouble() / topVal) * chartRows * 8)
          .round();
      // Each segment ends at `runningTicks` ticks from the baseline.
      segTicks[i] = runningTicks - totalAssigned;
      totalAssigned = runningTicks;
    }
    // Soak any rounding drift into the top segment.
    if (totalAssigned != totalTicks && n > 0) {
      segTicks[n - 1] += totalTicks - totalAssigned;
    }

    // Render bottom-up. `cursorRow` is the next row to paint (from chart
    // bottom, working up).
    var cursorRow = chartTopRow + chartRows - 1;
    for (var i = 0; i < n; i++) {
      final t = segTicks[i];
      if (t <= 0) continue;
      final fullRows = t ~/ 8;
      final partial = t % 8;
      final color = i < bar.colors.length
          ? bar.colors[i]
          : (_palette.isEmpty ? _defaultColor : _palette[i % _palette.length]);
      final style = CellStyle(foreground: color);

      for (var r = 0; r < fullRows; r++) {
        if (cursorRow < chartTopRow) return;
        for (var x = 0; x < _barWidth; x++) {
          final tgt = col + x;
          if (tgt < 0 || tgt >= buffer.size.cols) continue;
          if (cursorRow < 0 || cursorRow >= buffer.size.rows) continue;
          buffer.writeGrapheme(CellOffset(tgt, cursorRow), _full, style: style);
        }
        cursorRow -= 1;
      }
      // Partial only on the topmost segment to avoid two-color blending.
      final isTopSegment = i == n - 1;
      if (partial > 0 && isTopSegment && cursorRow >= chartTopRow) {
        for (var x = 0; x < _barWidth; x++) {
          final tgt = col + x;
          if (tgt < 0 || tgt >= buffer.size.cols) continue;
          if (cursorRow < 0 || cursorRow >= buffer.size.rows) continue;
          buffer.writeGrapheme(
            CellOffset(tgt, cursorRow),
            _partials[partial],
            style: style,
          );
        }
      }
    }
  }

  /// One-row right-aligned legend mapping palette colors to segment
  /// labels: `● cpu  ● mem  ● disk`. Quietly skipped if the chart is
  /// too narrow to fit the full text.
  void _paintLegend(CellBuffer buffer, int row, int leftCol, int totalWidth) {
    final labels = _segmentLabels;
    if (labels == null || labels.isEmpty) return;
    var totalW = 0;
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) totalW += 2; // inter-entry gap
      totalW += 2 + labels[i].length; // bullet + space + label
    }
    if (totalW > totalWidth) return;
    if (row < 0 || row >= buffer.size.rows) return;
    var col = leftCol + totalWidth - totalW;
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) col += 2;
      final color = _palette.isEmpty
          ? _defaultColor
          : _palette[i % _palette.length];
      if (col >= 0 && col < buffer.size.cols) {
        buffer.writeGrapheme(
          CellOffset(col, row),
          '●',
          style: CellStyle(foreground: color),
        );
      }
      col += 2;
      final label = labels[i];
      for (var j = 0; j < label.length; j++) {
        final c = col + j;
        if (c < 0 || c >= buffer.size.cols) continue;
        buffer.writeGrapheme(CellOffset(c, row), label[j], style: _labelStyle);
      }
      col += label.length;
    }
  }

  static void _writeCentered(
    CellBuffer buffer,
    int leftCol,
    int row,
    int width,
    String text,
    CellStyle style,
  ) {
    if (row < 0 || row >= buffer.size.rows) return;
    final clipped = text.length > width ? text.substring(0, width) : text;
    final padLeft = (width - clipped.length) ~/ 2;
    for (var i = 0; i < clipped.length; i++) {
      final col = leftCol + padLeft + i;
      if (col < 0 || col >= buffer.size.cols) continue;
      buffer.writeGrapheme(CellOffset(col, row), clipped[i], style: style);
    }
  }

  static String _formatValue(num v) {
    if (v == v.truncate()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
