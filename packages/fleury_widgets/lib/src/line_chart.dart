import 'package:fleury/fleury_core.dart';

import 'canvas.dart';
import 'glyphs.dart';
import 'sub_cell_buffer.dart';

// =====================================================================
// Palettes
// =====================================================================

/// Pre-built color palettes for the viz catalog.
///
/// [LineChart] and `BarChart` cycle their `palette` across series / stacked
/// segments. The default is the theme-derived "semantic" palette
/// (primary/info/warning/success/error) — useful when each series has
/// inherent meaning. For arbitrary categorical data where colors are
/// just labels, prefer [categorical], a hue-distinct ANSI 16 sequence
/// chosen for distinguishability without the warning/error connotation.
final class Palettes {
  Palettes._();

  /// Six hue-distinct ANSI colors with no semantic baggage — the right
  /// default for stacked bars and multi-series charts where segments
  /// are just categories. Patterned after ColorBrewer's Set2 /
  /// Tableau10 — qualitative, not sequential.
  static const List<Color> categorical = [
    AnsiColor(6), // cyan
    AnsiColor(3), // yellow
    AnsiColor(2), // green
    AnsiColor(5), // magenta
    AnsiColor(4), // blue
    AnsiColor(1), // red
  ];
}

// =====================================================================
// Tick formatting
// =====================================================================

/// Formats a numeric axis tick value to a label string. Pass one to
/// [LineChart.xTickFormat] / [LineChart.yTickFormat] to control axis
/// labels (and the crosshair tooltip readout) — defaults to
/// [TickFormat.number].
typedef TickFormatter = String Function(num value);

/// Pre-built [TickFormatter]s for common axis label styles.
final class TickFormat {
  TickFormat._();

  /// Integer when the value is whole and within 6 digits, otherwise one
  /// decimal place. The default for both axes.
  static String number(num v) {
    final d = v.toDouble();
    if (d == d.truncateToDouble() && d.abs() < 1e6) {
      return d.toInt().toString();
    }
    return d.toStringAsFixed(1);
  }

  /// '50%'-style. Expects 0..1 values — `0.5` → `'50%'`.
  static String percent(num v) => '${(v.toDouble() * 100).round()}%';

  /// Compact K/M/B/T notation for large magnitudes.
  /// `1500` → `'1.5K'`, `2_400_000` → `'2.4M'`.
  static String compact(num v) {
    final d = v.toDouble();
    final abs = d.abs();
    final sign = d < 0 ? '-' : '';
    if (abs >= 1e12) return '$sign${(abs / 1e12).toStringAsFixed(1)}T';
    if (abs >= 1e9) return '$sign${(abs / 1e9).toStringAsFixed(1)}B';
    if (abs >= 1e6) return '$sign${(abs / 1e6).toStringAsFixed(1)}M';
    if (abs >= 1e3) return '$sign${(abs / 1e3).toStringAsFixed(1)}K';
    return number(v);
  }

  /// Currency with a symbol prefix. Large magnitudes use [compact].
  static TickFormatter currency(String symbol) =>
      (num v) => '$symbol${compact(v)}';

  /// Date label from epoch milliseconds. [pattern] supports tokens
  /// `yyyy`, `MM`, `dd`, `HH`, `mm`, and `MMM` (Jan/Feb/...). Useful
  /// when the x-axis is a timestamp.
  static TickFormatter epochMs([String pattern = 'MMM dd']) =>
      (num v) =>
          _formatDate(DateTime.fromMillisecondsSinceEpoch(v.toInt()), pattern);
}

String _formatDate(DateTime dt, String pattern) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return pattern
      .replaceAll('yyyy', dt.year.toString().padLeft(4, '0'))
      .replaceAll('MMM', months[dt.month - 1])
      .replaceAll('MM', dt.month.toString().padLeft(2, '0'))
      .replaceAll('dd', dt.day.toString().padLeft(2, '0'))
      .replaceAll('HH', dt.hour.toString().padLeft(2, '0'))
      .replaceAll('mm', dt.minute.toString().padLeft(2, '0'));
}

// =====================================================================
// Reference lines
// =====================================================================

/// Visual style for a [ReferenceLine].
enum ReferenceStyle { solid, dashed, dotted }

/// A horizontal or vertical marker line — a target, limit, or threshold
/// painted under the data so it doesn't obscure the series.
///
/// ```dart
/// LineChart(
///   series: [...],
///   references: const [
///     ReferenceLine.horizontal(80, color: AnsiColor(1), label: 'SLA'),
///     ReferenceLine.vertical(15, style: ReferenceStyle.dotted),
///   ],
/// )
/// ```
class ReferenceLine {
  /// A horizontal line at `y = value`.
  const ReferenceLine.horizontal(
    num this.y, {
    this.color,
    this.label,
    this.style = ReferenceStyle.dashed,
  }) : x = null;

  /// A vertical line at `x = value`.
  const ReferenceLine.vertical(
    num this.x, {
    this.color,
    this.label,
    this.style = ReferenceStyle.dashed,
  }) : y = null;

  final num? x;
  final num? y;
  final Color? color;
  final String? label;
  final ReferenceStyle style;
}

// =====================================================================
// Series
// =====================================================================

/// How a [LineSeries] is rendered into the chart's plot area.
///
/// - [line] (default) draws connecting segments between adjacent points,
///   giving a smooth braille curve.
/// - [scatter] draws each point as a single dot, no connecting line.
///   The classic scatter plot.
/// - [area] draws the line and fills every pixel below it down to the
///   visible y-min — a filled "shadow" under the curve.
enum LineType { line, scatter, area }

/// One named series of `(x, y)` points for [LineChart] to plot.
///
/// **Missing data**: use `double.nan` for a y (or x) to break the line.
/// Segments touching a non-finite endpoint are skipped, so a single NaN
/// cleanly splits a series into two visual pieces with a gap.
class LineSeries {
  const LineSeries(
    this.points, {
    this.color,
    this.label,
    this.type = LineType.line,
    this.thresholdY,
    this.belowColor,
    this.gradient,
  });

  /// Points in logical (data) space. For [LineType.line] and [LineType.area]
  /// order matters — adjacent points are joined with a segment.
  final List<(num x, num y)> points;
  final Color? color;
  final String? label;
  final LineType type;

  /// If non-null, segments are drawn in [color] when above [thresholdY]
  /// and in [belowColor] when below — for "alarm" plots that flip color
  /// at a limit. Segments straddling the threshold are split at the
  /// crossing point. [belowColor] falls back to [color] if null.
  final num? thresholdY;
  final Color? belowColor;

  /// Optional vertical color gradient for a [LineType.area] series, given as
  /// stops ordered **bottom → top** of the plot. When set, the area is
  /// painted as a *solid, gradient-shaded* fill — the "premium" filled-graph
  /// look (à la btop) — using block-element columns rather than a stippled
  /// braille wash, so it reads as a continuous region on every surface.
  ///
  /// A single-stop list is a flat solid fill. When a gradient is set, [color]
  /// and [thresholdY] are ignored for that series (the gradient owns the
  /// coloring). Ignored entirely for [LineType.line] and [LineType.scatter].
  final List<Color>? gradient;
}

// =====================================================================
// LineChart
// =====================================================================

/// A multi-series line chart with sub-cell-resolution braille rendering.
/// Axes (optional) display labels at the min, midpoint, and max of each
/// dimension's visible range.
///
/// ```dart
/// LineChart(series: [
///   LineSeries(cpuSamples, label: 'cpu'),
///   LineSeries(memSamples, label: 'mem'),
/// ])
/// ```
///
/// When [interactive] is true, the chart becomes focusable: arrow chords
/// move a vertical crosshair through the data points and a small tooltip
/// box shows the y value of each series at the cursor's x.
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.series,
    this.xRange,
    this.yRange,
    this.padding = 0.0,
    this.showAxes = true,
    this.showGrid = false,
    this.showLegend = false,
    this.yTickCount = 3,
    this.palette,
    this.marker = CanvasMarker.braille,
    this.xTickFormat,
    this.yTickFormat,
    this.references = const [],
    this.interactive = false,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel = 'Line chart',
  });

  /// One or more series to plot.
  final List<LineSeries> series;

  /// Visible x range. `null` autoscales to the data.
  final (num min, num max)? xRange;

  /// Visible y range. `null` autoscales to the data.
  final (num min, num max)? yRange;

  /// Extra space around the data along each axis, as a fraction of the
  /// range — `0.05` adds 5% of breathing room on every side. Only applied
  /// to autoscaled axes; ignored when [xRange]/[yRange] is set
  /// explicitly. Default `0.0` (literal extents — matches D3/Recharts
  /// behavior). Try `0.05` for dashboards where you don't want data
  /// touching the plot edges.
  final double padding;

  /// Draw min/mid/max labels for both axes.
  final bool showAxes;

  /// Draw faint mid-axis crosshair lines through the plot area.
  final bool showGrid;

  /// Draw a one-row legend at the top-right with a colored bullet and the
  /// label for each labeled series.
  final bool showLegend;

  /// Number of evenly-spaced y-axis tick labels, including both ends.
  /// Defaults to 3 (min / mid / max). Raise it for finer vertical reading
  /// (e.g. 5 gives quarter ticks); values below 2 are treated as 2. Only
  /// the two endpoints are drawn when the plot is shorter than 3 rows.
  final int yTickCount;

  /// Colors to cycle through for series that don't set [LineSeries.color]
  /// explicitly. Defaults to a palette derived from the theme's color
  /// scheme (primary, info, warning, success, error).
  final List<Color>? palette;

  /// Sub-cell rendering tier for the plotted line/scatter (not the gradient
  /// area fill, which always uses solid block columns). Defaults to
  /// [CanvasMarker.braille] — highest resolution and universal font support,
  /// but stippled. For a solid, gap-free line prefer [CanvasMarker.octant]
  /// (crispest, needs a Unicode-16 font or a kitty/Ghostty terminal),
  /// [CanvasMarker.sextant] (widely supported solid), or
  /// [CanvasMarker.quadrant]/[CanvasMarker.halfBlock] (universal, coarser).
  final CanvasMarker marker;

  /// Formatter for x-axis tick labels and the crosshair tooltip x value.
  /// Defaults to [TickFormat.number].
  final TickFormatter? xTickFormat;

  /// Formatter for y-axis tick labels and the crosshair tooltip y values.
  /// Defaults to [TickFormat.number].
  final TickFormatter? yTickFormat;

  /// Reference lines drawn under the data — useful for target / SLA /
  /// threshold markers.
  final List<ReferenceLine> references;

  /// When true, the chart is focusable. Arrow chords move a vertical
  /// crosshair through the union of data x values; Home/End jump to the
  /// ends. A floating tooltip shows the x value and each series' y at
  /// the cursor.
  final bool interactive;

  /// Auto-focus on first mount when [interactive] is true.
  final bool autofocus;

  /// Optional caller-provided node for [interactive] mode.
  final FocusNode? focusNode;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  FocusNode? _internalNode;
  FocusNode get _node =>
      widget.focusNode ??
      (_internalNode ??= FocusNode(debugLabel: 'LineChart'));

  int _cursorIdx = 0;
  List<num> _cursorXs = const [];
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _rebuildCursorXs();
  }

  @override
  void didUpdateWidget(covariant LineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.series, oldWidget.series)) {
      _rebuildCursorXs();
    }
  }

  @override
  void dispose() {
    _internalNode?.dispose();
    super.dispose();
  }

  void _rebuildCursorXs() {
    final s = <num>{};
    for (final ser in widget.series) {
      for (final (x, _) in ser.points) {
        if (x.toDouble().isFinite) s.add(x);
      }
    }
    final list = s.toList()..sort((a, b) => a.compareTo(b));
    _cursorXs = list;
    if (_cursorIdx >= list.length) {
      _cursorIdx = list.isEmpty ? 0 : list.length - 1;
    }
  }

  KeyEventResult _onKey(KeyEvent e) {
    if (_cursorXs.isEmpty) return KeyEventResult.ignored;
    final last = _cursorXs.length - 1;
    switch (e.code) {
      case KeyCode.arrowLeft:
        if (_cursorIdx == 0) return KeyEventResult.ignored;
        setState(() => _cursorIdx -= 1);
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        if (_cursorIdx == last) return KeyEventResult.ignored;
        setState(() => _cursorIdx += 1);
        return KeyEventResult.handled;
      case KeyCode.home:
        setState(() => _cursorIdx = 0);
        return KeyEventResult.handled;
      case KeyCode.end:
        setState(() => _cursorIdx = last);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _handleSemanticAction(SemanticAction action) async {
    final last = _cursorXs.length - 1;
    switch (action) {
      case SemanticAction.focus:
        if (widget.interactive) {
          _node.requestFocus();
          setState(() => _focused = true);
        }
        return;
      case SemanticAction.increment:
        if (widget.interactive && _cursorIdx < last) {
          setState(() => _cursorIdx += 1);
        }
        return;
      case SemanticAction.decrement:
        if (widget.interactive && _cursorIdx > 0) {
          setState(() => _cursorIdx -= 1);
        }
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final palette =
        widget.palette ??
        [cs.primary, cs.info, cs.warning, cs.success, cs.error];

    final showCursor = widget.interactive && _focused && _cursorXs.isNotEmpty;
    final cursorX = showCursor ? _cursorXs[_cursorIdx] : null;

    final raw = _RawLineChart(
      series: widget.series,
      xRange: widget.xRange,
      yRange: widget.yRange,
      padding: widget.padding,
      showAxes: widget.showAxes,
      showGrid: widget.showGrid,
      showLegend: widget.showLegend,
      yTickCount: widget.yTickCount,
      palette: palette,
      defaultColor: palette.isNotEmpty ? palette.first : cs.primary,
      axisStyle: theme.mutedStyle,
      xTickFormat: widget.xTickFormat ?? TickFormat.number,
      yTickFormat: widget.yTickFormat ?? TickFormat.number,
      references: widget.references,
      cursorX: cursorX,
      marker: widget.marker,
      glyphTier: MediaQuery.glyphTierOf(context),
    );

    final semantic = Semantics(
      role: SemanticRole.chart,
      label: widget.semanticLabel,
      value: cursorX == null ? null : 'x: $cursorX',
      focused: widget.interactive && _focused,
      actions: {
        if (widget.interactive) SemanticAction.focus,
        if (widget.interactive && _cursorIdx < _cursorXs.length - 1)
          SemanticAction.increment,
        if (widget.interactive && _cursorIdx > 0) SemanticAction.decrement,
      },
      onAction: _handleSemanticAction,
      state: _lineChartSemanticState(
        series: widget.series,
        xRange: widget.xRange,
        yRange: widget.yRange,
        padding: widget.padding,
        references: widget.references,
        interactive: widget.interactive,
        cursorXs: _cursorXs,
        cursorIndex: _cursorIdx,
      ),
      child: raw,
    );

    if (!widget.interactive) return semantic;
    return FocusWithin(
      onFocusChange: (has) {
        if (!mounted) return;
        setState(() => _focused = has);
      },
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKey: _onKey,
        child: semantic,
      ),
    );
  }
}

SemanticState _lineChartSemanticState({
  required List<LineSeries> series,
  required (num min, num max)? xRange,
  required (num min, num max)? yRange,
  required double padding,
  required List<ReferenceLine> references,
  required bool interactive,
  required List<num> cursorXs,
  required int cursorIndex,
}) {
  var pointCount = 0;
  for (final item in series) {
    pointCount += item.points.length;
  }
  var (xMin, xMax) = _effectiveChartRange(
    xRange,
    _lineChartExtents(series, x: true),
    padding,
  );
  var (yMin, yMax) = _effectiveChartRange(
    yRange,
    _lineChartExtents(series, x: false),
    padding,
  );
  if (xMin == xMax) xMax = xMin + 1;
  if (yMin == yMax) yMax = yMin + 1;
  final safeCursorIndex = cursorXs.isEmpty
      ? 0
      : cursorIndex.clamp(0, cursorXs.length - 1);
  return SemanticState({
    'chartType': 'line',
    'chartSeriesCount': series.length,
    'chartPointCount': pointCount,
    'chartXMin': xMin,
    'chartXMax': xMax,
    'chartYMin': yMin,
    'chartYMax': yMax,
    'chartReferenceCount': references.length,
    'chartInteractive': interactive,
    if (interactive) 'chartCursorCount': cursorXs.length,
    if (interactive && cursorXs.isNotEmpty) ...{
      'chartCursorIndex': safeCursorIndex,
      'chartCursorX': cursorXs[safeCursorIndex],
    },
  });
}

(double, double) _lineChartExtents(List<LineSeries> series, {required bool x}) {
  double? lo;
  double? hi;
  for (final item in series) {
    for (final point in item.points) {
      final value = (x ? point.$1 : point.$2).toDouble();
      if (!value.isFinite) continue;
      if (lo == null || value < lo) lo = value;
      if (hi == null || value > hi) hi = value;
    }
  }
  return (lo ?? 0, hi ?? 1);
}

(double, double) _effectiveChartRange(
  (num min, num max)? explicit,
  (double, double) auto,
  double padding,
) {
  if (explicit != null) {
    return (explicit.$1.toDouble(), explicit.$2.toDouble());
  }
  if (padding <= 0) return auto;
  final (lo, hi) = auto;
  final span = hi - lo;
  if (span <= 0) return auto;
  final pad = span * padding;
  return (lo - pad, hi + pad);
}

class _RawLineChart extends LeafRenderObjectWidget {
  const _RawLineChart({
    required this.series,
    required this.xRange,
    required this.yRange,
    required this.padding,
    required this.showAxes,
    required this.showGrid,
    required this.showLegend,
    required this.yTickCount,
    required this.palette,
    required this.defaultColor,
    required this.axisStyle,
    required this.xTickFormat,
    required this.yTickFormat,
    required this.references,
    required this.cursorX,
    required this.marker,
    required this.glyphTier,
  });

  final List<LineSeries> series;
  final (num min, num max)? xRange;
  final (num min, num max)? yRange;
  final double padding;
  final bool showAxes;
  final bool showGrid;
  final bool showLegend;
  final int yTickCount;
  final List<Color> palette;
  final Color defaultColor;
  final CellStyle axisStyle;
  final TickFormatter xTickFormat;
  final TickFormatter yTickFormat;
  final List<ReferenceLine> references;
  final num? cursorX;
  final CanvasMarker marker;
  final GlyphTier glyphTier;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLineChart(
    series: series,
    xRange: xRange,
    yRange: yRange,
    padding: padding,
    showAxes: showAxes,
    showGrid: showGrid,
    showLegend: showLegend,
    yTickCount: yTickCount,
    palette: palette,
    defaultColor: defaultColor,
    axisStyle: axisStyle,
    xTickFormat: xTickFormat,
    yTickFormat: yTickFormat,
    references: references,
    cursorX: cursorX,
    marker: marker,
    glyphTier: glyphTier,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderLineChart renderObject,
  ) {
    renderObject
      ..series = series
      ..xRange = xRange
      ..yRange = yRange
      ..padding = padding
      ..showAxes = showAxes
      ..showGrid = showGrid
      ..showLegend = showLegend
      ..yTickCount = yTickCount
      ..palette = palette
      ..defaultColor = defaultColor
      ..axisStyle = axisStyle
      ..xTickFormat = xTickFormat
      ..yTickFormat = yTickFormat
      ..references = references
      ..cursorX = cursorX
      ..marker = marker
      ..glyphTier = glyphTier;
  }
}

/// Render object behind [LineChart]. See its docs.
class RenderLineChart extends RenderObject {
  RenderLineChart({
    required List<LineSeries> series,
    required (num min, num max)? xRange,
    required (num min, num max)? yRange,
    required double padding,
    required bool showAxes,
    required bool showGrid,
    required bool showLegend,
    required int yTickCount,
    required List<Color> palette,
    required Color defaultColor,
    required CellStyle axisStyle,
    required TickFormatter xTickFormat,
    required TickFormatter yTickFormat,
    required List<ReferenceLine> references,
    required num? cursorX,
    required CanvasMarker marker,
    required GlyphTier glyphTier,
  }) : _series = series,
       _xRange = xRange,
       _yRange = yRange,
       _padding = padding,
       _showAxes = showAxes,
       _showGrid = showGrid,
       _showLegend = showLegend,
       _yTickCount = yTickCount,
       _palette = palette,
       _defaultColor = defaultColor,
       _axisStyle = axisStyle,
       _xTickFormat = xTickFormat,
       _yTickFormat = yTickFormat,
       _references = references,
       _cursorX = cursorX,
       _marker = marker,
       _glyphTier = glyphTier;

  List<LineSeries> _series;
  set series(List<LineSeries> v) {
    if (identical(_series, v)) return;
    _series = v;
    markNeedsPaintOnly();
  }

  (num min, num max)? _xRange;
  set xRange((num min, num max)? v) {
    if (_xRange == v) return;
    _xRange = v;
    markNeedsPaintOnly();
  }

  (num min, num max)? _yRange;
  set yRange((num min, num max)? v) {
    if (_yRange == v) return;
    _yRange = v;
    markNeedsPaintOnly();
  }

  double _padding;
  set padding(double v) {
    if (_padding == v) return;
    _padding = v;
    markNeedsPaintOnly();
  }

  bool _showAxes;
  set showAxes(bool v) {
    if (_showAxes == v) return;
    _showAxes = v;
    markNeedsPaintOnly();
  }

  bool _showGrid;
  set showGrid(bool v) {
    if (_showGrid == v) return;
    _showGrid = v;
    markNeedsPaintOnly();
  }

  bool _showLegend;
  set showLegend(bool v) {
    if (_showLegend == v) return;
    _showLegend = v;
    markNeedsPaintOnly();
  }

  int _yTickCount;
  set yTickCount(int v) {
    if (_yTickCount == v) return;
    _yTickCount = v;
    markNeedsPaintOnly();
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

  CellStyle _axisStyle;
  set axisStyle(CellStyle v) {
    if (_axisStyle == v) return;
    _axisStyle = v;
    markNeedsPaintOnly();
  }

  TickFormatter _xTickFormat;
  set xTickFormat(TickFormatter v) {
    if (identical(_xTickFormat, v)) return;
    _xTickFormat = v;
    markNeedsPaintOnly();
  }

  TickFormatter _yTickFormat;
  set yTickFormat(TickFormatter v) {
    if (identical(_yTickFormat, v)) return;
    _yTickFormat = v;
    markNeedsPaintOnly();
  }

  List<ReferenceLine> _references;
  set references(List<ReferenceLine> v) {
    if (identical(_references, v)) return;
    _references = v;
    markNeedsPaintOnly();
  }

  num? _cursorX;
  set cursorX(num? v) {
    if (_cursorX == v) return;
    _cursorX = v;
    markNeedsPaintOnly();
  }

  CanvasMarker _marker;
  set marker(CanvasMarker v) {
    if (_marker == v) return;
    _marker = v;
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
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 40;
    final rows = constraints.hasBoundedHeight ? constraints.maxRows! : 12;
    return constraints.constrain(CellSize(cols, rows));
  }

  // --------------------------------------------------------------------
  // Painting
  // --------------------------------------------------------------------

  static const _leftGutter = 6; // y-axis labels
  static const _bottomGutter = 1; // x-axis labels

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    final h = size.rows;
    if (w == 0 || h == 0 || _series.isEmpty) return;

    final useAxes = _showAxes && w > _leftGutter + 2 && h > _bottomGutter + 1;
    final plotLeft = useAxes ? _leftGutter : 0;
    final plotBottom = useAxes ? _bottomGutter : 0;
    final plotCols = w - plotLeft;
    final plotRows = h - plotBottom;
    if (plotCols <= 0 || plotRows <= 0) return;

    // Effective ranges. Padding only applies to autoscaled axes — an
    // explicit range is taken literally.
    var (xmin, xmax) = _effectiveRange(_xRange, _xExtents, _padding);
    var (ymin, ymax) = _effectiveRange(_yRange, _yExtents, _padding);
    // Degenerate single-value ranges: pad so the line has something to draw.
    if (xmax == xmin) {
      xmax = xmin + 1;
    }
    if (ymax == ymin) {
      ymax = ymin + 1;
    }

    // Grid first, so braille paints over it where they overlap.
    if (_showGrid) {
      _paintGrid(buffer, offset, plotLeft, plotCols, plotRows);
    }

    // Gradient-filled area series render as solid, gradient-shaded block
    // columns behind the reference lines, cursor, and other series — the
    // "filled graph" look. Painted just after the grid so everything else
    // draws on top.
    for (final s in _series) {
      final grad = s.gradient;
      if (grad != null && grad.isNotEmpty && s.type == LineType.area) {
        _paintGradientArea(
          buffer,
          offset,
          s,
          grad,
          plotLeft,
          plotCols,
          plotRows,
          xmin,
          xmax,
          ymin,
          ymax,
        );
      }
    }

    final plot = subCellBufferFor(_marker, plotCols, plotRows);
    final pxW = plot.pixelWidth;
    final pxH = plot.pixelHeight;

    // Convert logical coordinates to pixel space. Non-finite inputs are
    // clipped to a sentinel the buffer ignores (out-of-bounds).
    int toPx(num x) {
      final d = x.toDouble();
      if (!d.isFinite) return -1;
      final t = (d - xmin) / (xmax - xmin);
      return (t * (pxW - 1)).round();
    }

    int toPy(num y) {
      final d = y.toDouble();
      if (!d.isFinite) return -1;
      final t = (d - ymin) / (ymax - ymin);
      return ((1 - t) * (pxH - 1)).round();
    }

    // Clips a data-space segment to the visible [xmin,xmax]×[ymin,ymax] rect,
    // returning null when it falls entirely outside. Rasterizing the clipped
    // span keeps a finite out-of-range point drawing up to the boundary
    // instead of vanishing, and keeps the mapped pixels inside the buffer so
    // the Bresenham walk can't spin on a far-off overshoot.
    _ClippedSegment? clip(double x0, double y0, double x1, double y1) =>
        _clipSegmentToRect(x0, y0, x1, y1, xmin, xmax, ymin, ymax);

    final baselinePy = pxH - 1; // y-min row in pixel space — area fills to here

    // Reference *lines* go under the data so the series stays on top —
    // the line is just a faint guide. Reference *labels* paint after
    // the data (below) so they remain readable.
    for (final ref in _references) {
      _paintReferenceLine(
        buffer,
        offset,
        ref,
        plotLeft,
        plotCols,
        plotRows,
        xmin,
        xmax,
        ymin,
        ymax,
      );
    }

    // Cursor: also under the data. Paint as a faint vertical column of
    // dashed glyphs; the braille on top will overdraw at intersections.
    if (_cursorX != null) {
      _paintCursor(
        buffer,
        offset,
        _cursorX!,
        plotLeft,
        plotCols,
        plotRows,
        xmin,
        xmax,
      );
    }

    // Resolve a final color per series — explicit color wins, otherwise
    // cycle the palette.
    final resolvedColors = <Color>[];
    var autoIdx = 0;
    for (final s in _series) {
      final grad = s.gradient;
      if (grad != null && grad.isNotEmpty) {
        // A gradient owns the series color; the legend bullet uses its top
        // stop and it doesn't consume a palette slot.
        resolvedColors.add(grad.last);
      } else if (s.color != null) {
        resolvedColors.add(s.color!);
      } else if (_palette.isEmpty) {
        resolvedColors.add(_defaultColor);
      } else {
        resolvedColors.add(_palette[autoIdx++ % _palette.length]);
      }
    }

    for (var sIdx = 0; sIdx < _series.length; sIdx++) {
      final s = _series[sIdx];
      // Gradient area series are already painted as solid block columns.
      if (s.gradient != null &&
          s.gradient!.isNotEmpty &&
          s.type == LineType.area) {
        continue;
      }
      final above = resolvedColors[sIdx];
      final below = s.belowColor ?? above;
      final ty = s.thresholdY;

      // Scatter: each point is a single dot, no connection.
      if (s.type == LineType.scatter) {
        for (final (x, y) in s.points) {
          final color = (ty != null && y.toDouble() < ty.toDouble())
              ? below
              : above;
          plot.setPixel(toPx(x), toPy(y), color);
        }
        continue;
      }

      if (s.points.length == 1) {
        final (x, y) = s.points.first;
        final color = (ty != null && y.toDouble() < ty.toDouble())
            ? below
            : above;
        plot.setPixel(toPx(x), toPy(y), color);
        continue;
      }

      for (var i = 1; i < s.points.length; i++) {
        final (x0, y0) = s.points[i - 1];
        final (x1, y1) = s.points[i];
        _drawSegment(
          plot,
          toPx,
          toPy,
          clip,
          baselinePy,
          x0,
          y0,
          x1,
          y1,
          above,
          below,
          ty,
          s.type == LineType.area,
        );
      }
    }

    plot.writeTo(
      buffer,
      CellOffset(offset.col + plotLeft, offset.row),
      CellStyle(foreground: _defaultColor),
      glyphTier: _glyphTier,
    );

    // Reference labels paint on top of the data so they stay readable
    // when the series crosses their row/column.
    if (_references.isNotEmpty) {
      _paintReferenceLabels(
        buffer,
        offset,
        plotLeft,
        plotCols,
        plotRows,
        xmin,
        xmax,
        ymin,
        ymax,
      );
    }

    if (useAxes) {
      _paintAxes(buffer, offset, plotCols, plotRows, xmin, xmax, ymin, ymax);
    }

    // Tooltip last so it sits above everything else.
    if (_cursorX != null) {
      _paintTooltip(
        buffer,
        offset,
        _cursorX!,
        plotLeft,
        plotCols,
        plotRows,
        xmin,
        xmax,
        resolvedColors,
      );
    }

    // Legend last so it overlays everything else.
    if (_showLegend) {
      _paintLegend(buffer, offset, plotLeft, plotCols, resolvedColors);
    }
  }

  /// Draws a single segment, splitting it at the threshold when one is set
  /// and the endpoints straddle it. Area fill is performed per sub-segment
  /// using the same color logic.
  void _drawSegment(
    SubCellBuffer plot,
    int Function(num) toPx,
    int Function(num) toPy,
    _SegmentClip clip,
    int baselinePy,
    num x0n,
    num y0n,
    num x1n,
    num y1n,
    Color above,
    Color below,
    num? threshold,
    bool fillArea,
  ) {
    final y0 = y0n.toDouble();
    final y1 = y1n.toDouble();
    final ty = threshold?.toDouble();
    if (ty == null || (y0 - ty) * (y1 - ty) >= 0) {
      // No threshold, or both endpoints on the same side of it.
      final color = (ty != null && y0 < ty) ? below : above;
      _drawSegmentSolid(
        plot,
        toPx,
        toPy,
        clip,
        baselinePy,
        x0n,
        y0n,
        x1n,
        y1n,
        color,
        fillArea,
      );
      return;
    }
    // Straddles the threshold — split.
    final x0 = x0n.toDouble();
    final x1 = x1n.toDouble();
    final f = (ty - y0) / (y1 - y0);
    final xc = x0 + f * (x1 - x0);
    final c0 = y0 < ty ? below : above;
    final c1 = y1 < ty ? below : above;
    _drawSegmentSolid(
      plot,
      toPx,
      toPy,
      clip,
      baselinePy,
      x0n,
      y0n,
      xc,
      ty,
      c0,
      fillArea,
    );
    _drawSegmentSolid(
      plot,
      toPx,
      toPy,
      clip,
      baselinePy,
      xc,
      ty,
      x1n,
      y1n,
      c1,
      fillArea,
    );
  }

  void _drawSegmentSolid(
    SubCellBuffer plot,
    int Function(num) toPx,
    int Function(num) toPy,
    _SegmentClip clip,
    int baselinePy,
    num x0,
    num y0,
    num x1,
    num y1,
    Color color,
    bool fillArea,
  ) {
    // A non-finite endpoint is the missing-data sentinel (NaN/Infinity); skip
    // the segment so the line breaks into a gap, as documented.
    final dx0 = x0.toDouble(), dy0 = y0.toDouble();
    final dx1 = x1.toDouble(), dy1 = y1.toDouble();
    if (!dx0.isFinite || !dy0.isFinite || !dx1.isFinite || !dy1.isFinite) {
      return;
    }
    // Clip to the visible rect before mapping to pixels: a finite out-of-range
    // endpoint is drawn up to the boundary (not dropped), and the pixels stay
    // in-buffer so the Bresenham walk below stays bounded.
    final clipped = clip(dx0, dy0, dx1, dy1);
    if (clipped == null) return; // segment lies entirely outside the plot
    final (cx0, cy0, cx1, cy1) = clipped;
    final px0 = toPx(cx0), py0 = toPy(cy0);
    final px1 = toPx(cx1), py1 = toPy(cy1);
    plot.drawLine(px0, py0, px1, py1, color);
    // A stippled tier (braille) reads as a thin dotted trail; draw a second
    // pass offset 1px perpendicular to the segment's dominant axis so the
    // line fills its cells and reads as a continuous band. Solid tiers
    // (block/quadrant/sextant/octant) are already gap-free, so skip it.
    if (plot.isStippled) {
      if ((py1 - py0).abs() > (px1 - px0).abs()) {
        plot.drawLine(px0 + 1, py0, px1 + 1, py1, color);
      } else {
        plot.drawLine(px0, py0 + 1, px1, py1 + 1, color);
      }
    }

    if (!fillArea) return;
    final (a, b) = px0 <= px1
        ? ((px0, py0), (px1, py1))
        : ((px1, py1), (px0, py0));
    final dx = b.$1 - a.$1;
    if (dx == 0) {
      final top = py0 < py1 ? py0 : py1;
      for (var py = top; py <= baselinePy; py++) {
        plot.setPixel(a.$1, py, color);
      }
    } else {
      for (var px = a.$1; px <= b.$1; px++) {
        final t = (px - a.$1) / dx;
        final py = (a.$2 + t * (b.$2 - a.$2)).round();
        for (var fillPy = py; fillPy <= baselinePy; fillPy++) {
          plot.setPixel(px, fillPy, color);
        }
      }
    }
  }

  /// Paints a [LineType.area] series that has a [gradient] as solid, gradient-
  /// shaded block columns. For each plot column the series value is sampled at
  /// the column center, the column is filled from the y-min baseline up to
  /// that height using the `▁▂▃▄▅▆▇█` ramp (a smooth top edge), and every cell
  /// is colored by its vertical position through [gradient] — stop 0 at the
  /// baseline, the last stop at the top. Reads as a continuous filled region
  /// on every surface, with no braille stipple.
  void _paintGradientArea(
    CellBuffer buffer,
    CellOffset offset,
    LineSeries s,
    List<Color> gradient,
    int plotLeft,
    int plotCols,
    int plotRows,
    double xmin,
    double xmax,
    double ymin,
    double ymax,
  ) {
    if (plotCols <= 0 || plotRows <= 0) return;
    final span = ymax - ymin;
    if (span <= 0) return;
    final xspan = xmax - xmin;
    final totalEighths = plotRows * 8;
    for (var c = 0; c < plotCols; c++) {
      // Sample the series at the horizontal center of this column.
      final xAt = xmin + (plotCols == 1 ? 0.5 : (c + 0.5) / plotCols) * xspan;
      final y = _sampleSeriesY(s.points, xAt);
      if (y == null || !y.isFinite) continue;
      final hEighths = (((y - ymin) / span).clamp(0.0, 1.0) * totalEighths)
          .round();
      if (hEighths <= 0) continue;
      for (var r = 0; r < plotRows; r++) {
        final rowFromBottom = plotRows - 1 - r;
        final cellEighths = (hEighths - rowFromBottom * 8).clamp(0, 8);
        if (cellEighths <= 0) continue;
        final glyph = verticalLevelGlyph(_glyphTier, cellEighths);
        if (glyph.isEmpty) continue;
        final vpos = plotRows == 1 ? 0.0 : rowFromBottom / (plotRows - 1);
        buffer.writeGrapheme(
          CellOffset(offset.col + plotLeft + c, offset.row + r),
          glyph,
          style: CellStyle(foreground: _gradientAt(gradient, vpos)),
        );
      }
    }
  }

  /// Linear interpolation of a series' y at logical [x], scanning segments in
  /// point order. Returns null when [x] lies outside every segment, or the
  /// containing segment touches missing data (a non-finite endpoint) — so the
  /// gradient fill breaks at the same gaps the line does.
  static double? _sampleSeriesY(List<(num, num)> pts, double x) {
    for (var i = 1; i < pts.length; i++) {
      final x0 = pts[i - 1].$1.toDouble();
      final x1 = pts[i].$1.toDouble();
      final lo = x0 < x1 ? x0 : x1;
      final hi = x0 < x1 ? x1 : x0;
      if (x < lo || x > hi) continue;
      final y0 = pts[i - 1].$2.toDouble();
      final y1 = pts[i].$2.toDouble();
      if (!x0.isFinite || !x1.isFinite || !y0.isFinite || !y1.isFinite) {
        return null;
      }
      if (x1 == x0) return y1;
      return y0 + (x - x0) / (x1 - x0) * (y1 - y0);
    }
    return null;
  }

  /// Samples [stops] (ordered) at [t] in `0..1` with linear RGB interpolation.
  static Color _gradientAt(List<Color> stops, double t) {
    if (stops.length == 1) return stops.first;
    final n = stops.length - 1;
    final scaled = t.clamp(0.0, 1.0) * n;
    final i = scaled.floor().clamp(0, n - 1);
    return stops[i].toRgb().mix(stops[i + 1].toRgb(), scaled - i);
  }

  /// Faint dotted gridlines at the min/mid/max ticks on each axis — so
  /// the grid actually aligns with the axis labels (peer convention,
  /// not a single mid-axis crosshair).
  void _paintGrid(
    CellBuffer buffer,
    CellOffset offset,
    int plotLeft,
    int plotCols,
    int plotRows,
  ) {
    if (plotCols < 2 || plotRows < 2) return;
    const dot = '·';
    // Horizontal gridlines at y-min (bottom), y-mid, y-max (top).
    final rows = <int>{
      offset.row, // top → y-max
      offset.row + plotRows ~/ 2, // mid
      offset.row + plotRows - 1, // bottom → y-min
    };
    for (final r in rows) {
      for (var c = 0; c < plotCols; c++) {
        buffer.writeGrapheme(
          CellOffset(offset.col + plotLeft + c, r),
          dot,
          style: _axisStyle,
        );
      }
    }
    // Vertical gridlines at x-min (left), x-mid, x-max (right).
    final cols = <int>{
      offset.col + plotLeft, // left → x-min
      offset.col + plotLeft + plotCols ~/ 2, // mid
      offset.col + plotLeft + plotCols - 1, // right → x-max
    };
    for (final c in cols) {
      for (var r = 0; r < plotRows; r++) {
        buffer.writeGrapheme(
          CellOffset(c, offset.row + r),
          dot,
          style: _axisStyle,
        );
      }
    }
  }

  /// Paints a [ReferenceLine] as a horizontal or vertical row of glyphs
  /// across/through the plot. Drawn before the series so the data stays
  /// readable on top.
  void _paintReferenceLine(
    CellBuffer buffer,
    CellOffset offset,
    ReferenceLine ref,
    int plotLeft,
    int plotCols,
    int plotRows,
    double xmin,
    double xmax,
    double ymin,
    double ymax,
  ) {
    final color = ref.color;
    final style = color == null
        ? _axisStyle
        : _axisStyle.merge(CellStyle(foreground: color));
    if (ref.y != null) {
      final y = ref.y!.toDouble();
      if (!y.isFinite || y < ymin || y > ymax) return;
      final t = (y - ymin) / (ymax - ymin);
      final row = offset.row + ((1 - t) * (plotRows - 1)).round();
      final glyph = switch (ref.style) {
        ReferenceStyle.solid => '─',
        ReferenceStyle.dashed => '╌',
        ReferenceStyle.dotted => '·',
      };
      for (var c = 0; c < plotCols; c++) {
        buffer.writeGrapheme(
          CellOffset(offset.col + plotLeft + c, row),
          glyph,
          style: style,
        );
      }
    } else if (ref.x != null) {
      final x = ref.x!.toDouble();
      if (!x.isFinite || x < xmin || x > xmax) return;
      final t = (x - xmin) / (xmax - xmin);
      final col = offset.col + plotLeft + (t * (plotCols - 1)).round();
      final glyph = switch (ref.style) {
        ReferenceStyle.solid => '│',
        ReferenceStyle.dashed => '╎',
        ReferenceStyle.dotted => '·',
      };
      for (var r = 0; r < plotRows; r++) {
        buffer.writeGrapheme(
          CellOffset(col, offset.row + r),
          glyph,
          style: style,
        );
      }
    }
  }

  /// Paints reference-line *labels* on top of the data so they remain
  /// readable when the series crosses their row/column. Horizontal-ref
  /// labels go on the row adjacent to the line (above when possible,
  /// below near the top edge); vertical-ref labels paint horizontally
  /// at the top of the plot, anchored to the right of the line (flipped
  /// left when they'd overflow the right edge).
  void _paintReferenceLabels(
    CellBuffer buffer,
    CellOffset offset,
    int plotLeft,
    int plotCols,
    int plotRows,
    double xmin,
    double xmax,
    double ymin,
    double ymax,
  ) {
    for (final ref in _references) {
      final label = ref.label;
      if (label == null || label.isEmpty) continue;
      final color = ref.color;
      final style = color == null
          ? _axisStyle
          : _axisStyle.merge(CellStyle(foreground: color));
      if (ref.y != null) {
        final y = ref.y!.toDouble();
        if (!y.isFinite || y < ymin || y > ymax) continue;
        if (label.length > plotCols) continue;
        final t = (y - ymin) / (ymax - ymin);
        final row = offset.row + ((1 - t) * (plotRows - 1)).round();
        final labelRow = row > offset.row ? row - 1 : row + 1;
        if (labelRow < offset.row || labelRow >= offset.row + plotRows) {
          continue;
        }
        final col = offset.col + plotLeft + plotCols - label.length;
        for (var i = 0; i < label.length; i++) {
          buffer.writeGrapheme(
            CellOffset(col + i, labelRow),
            label[i],
            style: style,
          );
        }
      } else if (ref.x != null) {
        final x = ref.x!.toDouble();
        if (!x.isFinite || x < xmin || x > xmax) continue;
        if (label.length >= plotCols) continue;
        final t = (x - xmin) / (xmax - xmin);
        final col = offset.col + plotLeft + (t * (plotCols - 1)).round();
        final plotRightAbs = offset.col + plotLeft + plotCols;
        var labelLeft = col + 1;
        if (labelLeft + label.length > plotRightAbs) {
          labelLeft = col - label.length - 1;
        }
        if (labelLeft < offset.col + plotLeft) continue;
        for (var i = 0; i < label.length; i++) {
          buffer.writeGrapheme(
            CellOffset(labelLeft + i, offset.row),
            label[i],
            style: style,
          );
        }
      }
    }
  }

  /// Paints the vertical crosshair column at the cursor's x.
  void _paintCursor(
    CellBuffer buffer,
    CellOffset offset,
    num cursorX,
    int plotLeft,
    int plotCols,
    int plotRows,
    double xmin,
    double xmax,
  ) {
    final x = cursorX.toDouble();
    if (!x.isFinite) return;
    final t = (x - xmin) / (xmax - xmin);
    final col = offset.col + plotLeft + (t * (plotCols - 1)).round();
    for (var r = 0; r < plotRows; r++) {
      buffer.writeGrapheme(
        CellOffset(col, offset.row + r),
        '╎',
        style: _axisStyle,
      );
    }
  }

  /// Paints a small floating tooltip with x and per-series y readouts.
  /// Positioned in whichever top corner is opposite the cursor; skipped
  /// silently when it doesn't fit.
  void _paintTooltip(
    CellBuffer buffer,
    CellOffset offset,
    num cursorX,
    int plotLeft,
    int plotCols,
    int plotRows,
    double xmin,
    double xmax,
    List<Color> resolvedColors,
  ) {
    final x = cursorX.toDouble();
    if (!x.isFinite) return;
    // Resolve each series' y at the cursor, then sort descending by
    // value so the topmost line in the tooltip is the highest series —
    // ECharts / Highcharts shared-tooltip convention, more useful when
    // ranking series at a glance. Missing values (`null`) sort last.
    final rows = <(String, Color?, double?)>[];
    for (var i = 0; i < _series.length; i++) {
      final s = _series[i];
      final y = _valueAt(s, cursorX);
      final yStr = y == null ? '—' : _yTickFormat(y);
      final label = s.label ?? 's${i + 1}';
      rows.add(('● $label: $yStr', resolvedColors[i], y?.toDouble()));
    }
    rows.sort((a, b) {
      final av = a.$3;
      final bv = b.$3;
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      return bv.compareTo(av); // descending
    });

    final lines = <(String, Color?)>[
      ('x: ${_xTickFormat(cursorX)}', null),
      for (final r in rows) (r.$1, r.$2),
    ];
    var maxW = 0;
    for (final (text, _) in lines) {
      if (text.length > maxW) maxW = text.length;
    }
    final boxW = maxW + 2; // +2 for left/right border
    final boxH = lines.length + 2;
    if (boxW > plotCols || boxH > plotRows) return; // too tight, skip

    // Follow the cursor: prefer 2 cols to its right; flip to the left
    // when that would overflow, then clamp to the plot edges as a last
    // resort.
    final t = (x - xmin) / (xmax - xmin);
    final cursorCol = offset.col + plotLeft + (t * (plotCols - 1)).round();
    final plotLeftAbs = offset.col + plotLeft;
    final plotRightAbs = plotLeftAbs + plotCols;
    var boxCol = cursorCol + 2;
    if (boxCol + boxW > plotRightAbs) {
      boxCol = cursorCol - boxW - 1;
      if (boxCol < plotLeftAbs) {
        // Neither side has room — pin to the right edge.
        boxCol = plotRightAbs - boxW;
      }
    }
    final boxRow = offset.row;

    final top = '┌${'─' * (boxW - 2)}┐';
    final bot = '└${'─' * (boxW - 2)}┘';
    _writeAt(buffer, boxCol, boxRow, top, _axisStyle);
    _writeAt(buffer, boxCol, boxRow + boxH - 1, bot, _axisStyle);
    for (var i = 0; i < lines.length; i++) {
      final r = boxRow + 1 + i;
      final (text, color) = lines[i];
      _writeAt(buffer, boxCol, r, '│', _axisStyle);
      _writeAt(buffer, boxCol + boxW - 1, r, '│', _axisStyle);
      // Clear the interior so we don't show whatever was beneath.
      for (var k = 0; k < boxW - 2; k++) {
        buffer.writeGrapheme(
          CellOffset(boxCol + 1 + k, r),
          ' ',
          style: _axisStyle,
        );
      }
      if (color != null && text.startsWith('● ')) {
        // Colored bullet, rest in the muted text style.
        buffer.writeGrapheme(
          CellOffset(boxCol + 1, r),
          '●',
          style: CellStyle(foreground: color),
        );
        _writeAt(buffer, boxCol + 2, r, text.substring(1), _axisStyle);
      } else {
        _writeAt(buffer, boxCol + 1, r, text, _axisStyle);
      }
    }
  }

  /// Value of a series at the given cursor x. For [LineType.scatter],
  /// returns the nearest data point's y; for connected series, linearly
  /// interpolates between the two points whose x's span [cursorX]. Falls
  /// back to the nearest endpoint when the cursor sits outside the data.
  num? _valueAt(LineSeries s, num cursorX) {
    if (s.points.isEmpty) return null;
    if (s.type == LineType.scatter) return _nearestY(s, cursorX);
    final cx = cursorX.toDouble();
    // Walk pairs in series order — respects user-supplied ordering for
    // non-monotonic x's (e.g. cyclic curves).
    for (var i = 1; i < s.points.length; i++) {
      final (x0n, y0n) = s.points[i - 1];
      final (x1n, y1n) = s.points[i];
      final x0 = x0n.toDouble();
      final x1 = x1n.toDouble();
      final y0 = y0n.toDouble();
      final y1 = y1n.toDouble();
      if (!x0.isFinite || !x1.isFinite || !y0.isFinite || !y1.isFinite) {
        continue;
      }
      final lo = x0 < x1 ? x0 : x1;
      final hi = x0 < x1 ? x1 : x0;
      if (cx < lo || cx > hi) continue;
      if (x0 == x1) return y0n;
      final t = (cx - x0) / (x1 - x0);
      return y0 + t * (y1 - y0);
    }
    // Outside every segment — fall back to nearest data point.
    return _nearestY(s, cursorX);
  }

  num? _nearestY(LineSeries s, num cursorX) {
    if (s.points.isEmpty) return null;
    final cx = cursorX.toDouble();
    num? bestY;
    var bestDx = double.infinity;
    for (final (x, y) in s.points) {
      final xd = x.toDouble();
      final yd = y.toDouble();
      if (!xd.isFinite || !yd.isFinite) continue;
      final dx = (xd - cx).abs();
      if (dx < bestDx) {
        bestDx = dx;
        bestY = y;
      }
    }
    return bestY;
  }

  /// One-row right-aligned legend at the top of the plot: a colored bullet
  /// (`●`) plus the label, per labeled series. Skipped if it doesn't fit.
  void _paintLegend(
    CellBuffer buffer,
    CellOffset offset,
    int plotLeft,
    int plotCols,
    List<Color> resolvedColors,
  ) {
    final entries = <(LineSeries, Color)>[
      for (var i = 0; i < _series.length; i++)
        if (_series[i].label != null) (_series[i], resolvedColors[i]),
    ];
    if (entries.isEmpty) return;
    var totalWidth = 0;
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) totalWidth += 2; // gap between entries
      totalWidth += 2 + entries[i].$1.label!.length; // bullet + space + label
    }
    if (totalWidth > plotCols) return; // no room — skip
    var col = offset.col + plotLeft + plotCols - totalWidth;
    final row = offset.row;
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) col += 2;
      final (s, color) = entries[i];
      buffer.writeGrapheme(
        CellOffset(col, row),
        '●',
        style: CellStyle(foreground: color),
      );
      col += 2; // bullet + space
      final label = s.label!;
      for (var j = 0; j < label.length; j++) {
        buffer.writeGrapheme(
          CellOffset(col + j, row),
          label[j],
          style: _axisStyle,
        );
      }
      col += label.length;
    }
  }

  void _paintAxes(
    CellBuffer buffer,
    CellOffset offset,
    int plotCols,
    int plotRows,
    double xmin,
    double xmax,
    double ymin,
    double ymax,
  ) {
    // Y-axis: `yTickCount` evenly-spaced labels from ymax (top) down to
    // ymin (bottom). Right-align inside the left gutter (minus 1 col of
    // breathing room). Interior ticks are dropped on plots shorter than
    // 3 rows, where they'd collide with the endpoints. The (plotRows-1)
    // mapping with round() reproduces the old min/mid/max layout exactly
    // for the default count of 3.
    final yLabelWidth = _leftGutter - 1;
    final ticks = _yTickCount < 2 ? 2 : _yTickCount;
    for (var i = 0; i < ticks; i++) {
      final isEnd = i == 0 || i == ticks - 1;
      if (!isEnd && plotRows < 3) continue;
      final frac = i / (ticks - 1);
      final value = ymax - (ymax - ymin) * frac;
      final row = offset.row + ((plotRows - 1) * frac).round();
      _writeRightAligned(
        buffer,
        offset.col,
        row,
        yLabelWidth,
        _yTickFormat(value),
        _axisStyle,
      );
    }

    // X-axis: min at left of plot, max at right, mid centered (if room).
    final xRow = offset.row + plotRows;
    _writeAt(
      buffer,
      offset.col + _leftGutter,
      xRow,
      _xTickFormat(xmin),
      _axisStyle,
    );
    final maxLabel = _xTickFormat(xmax);
    final right = offset.col + _leftGutter + plotCols - maxLabel.length;
    _writeAt(buffer, right, xRow, maxLabel, _axisStyle);
    if (plotCols >= 16) {
      final midLabel = _xTickFormat((xmin + xmax) / 2);
      final mid =
          offset.col + _leftGutter + plotCols ~/ 2 - midLabel.length ~/ 2;
      _writeAt(buffer, mid, xRow, midLabel, _axisStyle);
    }
  }

  (double, double) get _xExtents {
    double? lo, hi;
    for (final s in _series) {
      for (final (x, _) in s.points) {
        final v = x.toDouble();
        if (!v.isFinite) continue;
        if (lo == null || v < lo) lo = v;
        if (hi == null || v > hi) hi = v;
      }
    }
    return (lo ?? 0, hi ?? 1);
  }

  (double, double) get _yExtents {
    double? lo, hi;
    for (final s in _series) {
      for (final (_, y) in s.points) {
        final v = y.toDouble();
        if (!v.isFinite) continue;
        if (lo == null || v < lo) lo = v;
        if (hi == null || v > hi) hi = v;
      }
    }
    return (lo ?? 0, hi ?? 1);
  }

  static (double, double) _effectiveRange(
    (num min, num max)? explicit,
    (double, double) auto,
    double padding,
  ) {
    if (explicit != null) {
      return (explicit.$1.toDouble(), explicit.$2.toDouble());
    }
    if (padding <= 0) return auto;
    final (lo, hi) = auto;
    final span = hi - lo;
    if (span <= 0) return auto; // degenerate — clamp logic handles it.
    final pad = span * padding;
    return (lo - pad, hi + pad);
  }

  static void _writeAt(
    CellBuffer buffer,
    int col,
    int row,
    String text,
    CellStyle style,
  ) {
    for (var i = 0; i < text.length; i++) {
      final c = col + i;
      if (c < 0 || c >= buffer.size.cols) continue;
      if (row < 0 || row >= buffer.size.rows) continue;
      buffer.writeGrapheme(CellOffset(c, row), text[i], style: style);
    }
  }

  static void _writeRightAligned(
    CellBuffer buffer,
    int leftCol,
    int row,
    int width,
    String text,
    CellStyle style,
  ) {
    final clipped = text.length > width ? text.substring(0, width) : text;
    _writeAt(buffer, leftCol + width - clipped.length, row, clipped, style);
  }
}

/// A segment clipped to the plot rect: (x0, y0, x1, y1) in data space.
typedef _ClippedSegment = (double, double, double, double);

/// Clips a data-space segment to the plot rect, returning null when the whole
/// segment lies outside it.
typedef _SegmentClip =
    _ClippedSegment? Function(double x0, double y0, double x1, double y1);

/// Cohen–Sutherland clip of the segment `(x0,y0)-(x1,y1)` to the axis-aligned
/// rect `[xmin,xmax] × [ymin,ymax]`, all in data space. Returns the clipped
/// endpoints, or null when the segment does not intersect the rect. Endpoints
/// are assumed finite (the caller filters out NaN/Infinity first).
_ClippedSegment? _clipSegmentToRect(
  double x0,
  double y0,
  double x1,
  double y1,
  double xmin,
  double xmax,
  double ymin,
  double ymax,
) {
  const inside = 0;
  const left = 1;
  const right = 2;
  const below = 4;
  const above = 8;

  int codeFor(double x, double y) {
    var code = inside;
    if (x < xmin) {
      code |= left;
    } else if (x > xmax) {
      code |= right;
    }
    if (y < ymin) {
      code |= below;
    } else if (y > ymax) {
      code |= above;
    }
    return code;
  }

  var code0 = codeFor(x0, y0);
  var code1 = codeFor(x1, y1);

  while (true) {
    if ((code0 | code1) == 0) {
      // Both endpoints inside the rect.
      return (x0, y0, x1, y1);
    }
    if ((code0 & code1) != 0) {
      // Both endpoints share an outside half-plane — no intersection. (The
      // trivial-reject also guarantees the divisors below are non-zero: a
      // segment parallel to the edge it is being clipped against would share
      // that edge's bit and be rejected here.)
      return null;
    }
    final outCode = code0 != 0 ? code0 : code1;
    double x;
    double y;
    if ((outCode & above) != 0) {
      x = x0 + (x1 - x0) * (ymax - y0) / (y1 - y0);
      y = ymax;
    } else if ((outCode & below) != 0) {
      x = x0 + (x1 - x0) * (ymin - y0) / (y1 - y0);
      y = ymin;
    } else if ((outCode & right) != 0) {
      y = y0 + (y1 - y0) * (xmax - x0) / (x1 - x0);
      x = xmax;
    } else {
      y = y0 + (y1 - y0) * (xmin - x0) / (x1 - x0);
      x = xmin;
    }
    if (outCode == code0) {
      x0 = x;
      y0 = y;
      code0 = codeFor(x0, y0);
    } else {
      x1 = x;
      y1 = y;
      code1 = codeFor(x1, y1);
    }
  }
}
