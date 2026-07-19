import 'package:fleury/fleury_core.dart';

import 'glyphs.dart';

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
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
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
    this.showYAxis = false,
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
  /// meaning), prefer overriding with `Palettes.categorical` to avoid
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

  /// Reserve a left gutter and draw a value axis (max at the top, 0 at
  /// the baseline, the midpoint between). Off by default — many compact
  /// bar charts rely on per-bar value labels ([showValues]) instead — but
  /// a shared axis is easier to read across many bars. Quietly degrades
  /// to no gutter when the chart is too narrow.
  final bool showYAxis;

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
        showYAxis: showYAxis,
        segmentLabels: segmentLabels,
        palette: p,
        defaultColor: p.isNotEmpty ? p.first : cs.primary,
        labelStyle: theme.mutedStyle,
        glyphTier: MediaQuery.glyphTierOf(context),
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
    required this.showYAxis,
    required this.segmentLabels,
    required this.palette,
    required this.defaultColor,
    required this.labelStyle,
    required this.glyphTier,
  });

  final List<Bar> bars;
  final num? max;
  final int barWidth;
  final int gap;
  final bool showLabels;
  final bool showValues;
  final bool showLegend;
  final bool showYAxis;
  final List<String>? segmentLabels;
  final List<Color> palette;
  final Color defaultColor;
  final CellStyle labelStyle;
  final GlyphTier glyphTier;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBarChart(
    bars: bars,
    max: max,
    barWidth: barWidth,
    gap: gap,
    showLabels: showLabels,
    showValues: showValues,
    showLegend: showLegend,
    showYAxis: showYAxis,
    segmentLabels: segmentLabels,
    palette: palette,
    defaultColor: defaultColor,
    labelStyle: labelStyle,
    glyphTier: glyphTier,
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
      ..showYAxis = showYAxis
      ..segmentLabels = segmentLabels
      ..palette = palette
      ..defaultColor = defaultColor
      ..labelStyle = labelStyle
      ..glyphTier = glyphTier;
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
    required bool showYAxis,
    required List<String>? segmentLabels,
    required List<Color> palette,
    required Color defaultColor,
    required CellStyle labelStyle,
    required GlyphTier glyphTier,
  }) : _bars = bars,
       _max = max,
       _barWidth = barWidth < 1 ? 1 : barWidth,
       _gap = gap < 0 ? 0 : gap,
       _showLabels = showLabels,
       _showValues = showValues,
       _showLegend = showLegend,
       _showYAxis = showYAxis,
       _segmentLabels = segmentLabels,
       _palette = palette,
       _defaultColor = defaultColor,
       _labelStyle = labelStyle,
       _glyphTier = glyphTier;

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

  bool _showYAxis;
  set showYAxis(bool v) {
    if (_showYAxis == v) return;
    _showYAxis = v;
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

  GlyphTier _glyphTier;
  set glyphTier(GlyphTier v) {
    if (_glyphTier == v) return;
    _glyphTier = v;
    markNeedsPaintOnly();
  }

  /// Width reserved on the left for value-axis labels when [showYAxis].
  static const _yAxisGutter = 6;

  bool get _legendActive {
    if (!_showLegend) return false;
    final labels = _segmentLabels;
    return labels != null && labels.isNotEmpty;
  }

  int get _chromeRows =>
      (_showLabels ? 1 : 0) + (_showValues ? 1 : 0) + (_legendActive ? 1 : 0);

  int get _naturalWidth {
    if (_bars.isEmpty) return 0;
    final bars = _bars.length * _barWidth + (_bars.length - 1) * _gap;
    return bars + (_showYAxis ? _yAxisGutter : 0);
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
      // Autoscale over the finite totals only — one NaN/±Infinity bar must
      // not poison the scale for the rest.
      var hi = 0.0;
      for (final b in _bars) {
        final v = b.total.toDouble();
        if (!v.isFinite) continue;
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

    // Reserve a value-axis gutter on the left when there's room for it;
    // degrade to no gutter (bars flush-left) when the box is too narrow.
    final gutter = (_showYAxis && w > _yAxisGutter + 1) ? _yAxisGutter : 0;
    if (gutter > 0) {
      _paintYAxis(buffer, offset, chartTopRow, chartRows, topVal);
    }

    // Clip bars that start past the buffer's right edge — at tight
    // widths the natural width exceeds the box, and we silently drop
    // overflowing bars rather than crashing on out-of-bounds writes.
    final rightEdge = offset.col + w;
    var col = offset.col + gutter;
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

      col += _barWidth;
    }

    // Category labels get their own pass so each can use the horizontal span up
    // to the midpoint toward its nearest labelled neighbour — letting a label
    // wider than one bar spill into the empty gaps a thinned axis leaves,
    // instead of clipping to the bar. Labels stay clear of one another.
    if (labelRow != null) {
      _writeCategoryLabels(buffer, offset.col + gutter, rightEdge, labelRow);
    }
  }

  /// Draws category labels under the bars. Each labelled bar centres its label
  /// on the bar but may spread into the space up to the midpoint toward the
  /// nearest *labelled* neighbour (or the chart edge), so a wide label reclaims
  /// the room a blank (thinned) neighbour leaves without overlapping the next.
  void _writeCategoryLabels(
    CellBuffer buffer,
    int firstCol,
    int rightEdge,
    int row,
  ) {
    if (row < 0 || row >= buffer.size.rows) return;
    final stride = _barWidth + _gap;
    final centers = <int>[];
    final texts = <String>[];
    // Right edge of the last drawn bar. Labels spread only within the bar band
    // [firstCol, lastBarRight) — never into the chart box's trailing padding —
    // so a fully-labelled chart renders identically and only blank (thinned)
    // neighbours donate their room.
    var lastBarRight = firstCol;
    for (var i = 0; i < _bars.length; i++) {
      final start = firstCol + i * stride;
      if (start >= rightEdge) break;
      final barRight = start + _barWidth;
      lastBarRight = barRight < rightEdge ? barRight : rightEdge;
      if (_bars[i].label.isEmpty) continue;
      centers.add(start + _barWidth ~/ 2);
      texts.add(_bars[i].label);
    }
    for (var k = 0; k < centers.length; k++) {
      final center = centers[k];
      // A one-cell gap between adjacent spans (prev.right = midpoint,
      // this.left = midpoint + 1) guarantees labels never touch.
      final left = k == 0 ? firstCol : (centers[k - 1] + center) ~/ 2 + 1;
      final right = k == centers.length - 1
          ? lastBarRight
          : (center + centers[k + 1]) ~/ 2;
      if (right - left <= 0) continue;
      final text = texts[k];
      final shown = text.length > right - left
          ? text.substring(0, right - left)
          : text;
      var start = center - shown.length ~/ 2;
      if (start < left) start = left;
      if (start + shown.length > right) start = right - shown.length;
      for (var j = 0; j < shown.length; j++) {
        final col = start + j;
        if (col < 0 || col >= buffer.size.cols) continue;
        buffer.writeGrapheme(CellOffset(col, row), shown[j], style: _labelStyle);
      }
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
    // A non-finite value (or scale) renders as an empty column — round()
    // on NaN/±Infinity would throw.
    final rawTicks = (bar.value!.toDouble() / topVal) * chartRows * 8;
    final ticks = rawTicks.isFinite ? rawTicks.round() : 0;
    final fullRows = ticks ~/ 8;
    final partial = ticks % 8;
    final hasPartial = partial > 0 && fullRows < chartRows;
    final paintedRows = fullRows + (hasPartial ? 1 : 0);
    final firstFilledRow = chartRows - paintedRows;

    for (var r = 0; r < chartRows; r++) {
      if (r < firstFilledRow) continue;
      final isTop = r == firstFilledRow;
      final glyph = (isTop && hasPartial)
          ? verticalLevelGlyph(_glyphTier, partial)
          : verticalLevelGlyph(_glyphTier, 8);
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
    final segTicks = List<int>.filled(n, 0);
    var runningTicks = 0;
    var totalAssigned = 0;
    for (var i = 0; i < n; i++) {
      // A non-finite segment contributes no height (rendered as a gap) —
      // round() on NaN/±Infinity would throw.
      final raw = (bar.segments[i].toDouble() / topVal) * chartRows * 8;
      runningTicks += raw.isFinite ? raw.round() : 0;
      // Each segment ends at `runningTicks` ticks from the baseline.
      segTicks[i] = runningTicks - totalAssigned;
      totalAssigned = runningTicks;
    }
    // Soak any rounding drift into the top segment. A non-finite total
    // (one bad segment poisons the sum) keeps the per-segment answer.
    final rawTotal = (bar.total.toDouble() / topVal) * chartRows * 8;
    final totalTicks = rawTotal.isFinite ? rawTotal.round() : totalAssigned;
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
          buffer.writeGrapheme(
            CellOffset(tgt, cursorRow),
            verticalLevelGlyph(_glyphTier, 8),
            style: style,
          );
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
            verticalLevelGlyph(_glyphTier, partial),
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
          _glyphTier == GlyphTier.ascii ? '*' : '●',
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

  /// Value axis in the left gutter: max at the chart top, 0 at the
  /// baseline, and the midpoint between (when there's room). Bars grow
  /// from 0, so the axis is always zero-based. Labels right-align inside
  /// the gutter with one column of breathing room before the bars.
  void _paintYAxis(
    CellBuffer buffer,
    CellOffset offset,
    int chartTopRow,
    int chartRows,
    double topVal,
  ) {
    final labelWidth = _yAxisGutter - 1;
    _writeRightAligned(
      buffer,
      offset.col,
      chartTopRow,
      labelWidth,
      _formatValue(topVal),
      _labelStyle,
    );
    if (chartRows >= 3) {
      _writeRightAligned(
        buffer,
        offset.col,
        chartTopRow + chartRows ~/ 2,
        labelWidth,
        _formatValue(topVal / 2),
        _labelStyle,
      );
    }
    _writeRightAligned(
      buffer,
      offset.col,
      chartTopRow + chartRows - 1,
      labelWidth,
      _formatValue(0),
      _labelStyle,
    );
  }

  static void _writeRightAligned(
    CellBuffer buffer,
    int leftCol,
    int row,
    int width,
    String text,
    CellStyle style,
  ) {
    if (row < 0 || row >= buffer.size.rows) return;
    final clipped = text.length > width ? text.substring(0, width) : text;
    final startCol = leftCol + width - clipped.length;
    for (var i = 0; i < clipped.length; i++) {
      final col = startCol + i;
      if (col < 0 || col >= buffer.size.cols) continue;
      buffer.writeGrapheme(CellOffset(col, row), clipped[i], style: style);
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
    if (!v.isFinite) return v.toString(); // 'NaN' / 'Infinity' — toInt throws
    if (v == v.truncate()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
