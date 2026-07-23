import 'package:fleury/fleury_core.dart';

import 'line_chart.dart';

/// One filled series for [AreaChart]: the region from the y-min baseline up to
/// the curve is shaded with a solid block fill.
class AreaSeries {
  const AreaSeries(this.points, {this.color, this.label, this.gradient});

  /// Points in logical (data) space, ordered by x — the fill top follows them.
  final List<(num x, num y)> points;

  /// Flat fill color, used when [gradient] is null. Defaults to the theme's
  /// primary color.
  final Color? color;

  /// Optional series label for the legend.
  final String? label;

  /// Vertical fill gradient, stops ordered **bottom → top** of the plot. When
  /// set it owns the coloring and [color] is ignored. A single-stop list is a
  /// flat fill.
  final List<Color>? gradient;
}

/// A filled **area chart**: each series is drawn as a solid, gradient- (or
/// flat-) shaded region using block-element columns — the "premium" filled
/// look that reads as a continuous surface on every surface.
///
/// [AreaChart] shares [LineChart]'s cartesian engine — axes, legend, ranges,
/// grid, references, and the interactive crosshair all behave identically.
/// Reach for [LineChart] when you want a line or scatter plot instead of a
/// fill; reach for [AreaChart] when the shaded region is the point.
///
/// ```dart
/// AreaChart(series: [
///   AreaSeries(load, label: 'load', gradient: [cs.success, cs.warning, cs.error]),
/// ])
/// ```
class AreaChart extends StatelessWidget {
  const AreaChart({
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
    this.xTickFormat,
    this.yTickFormat,
    this.references = const [],
    this.interactive = false,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel = 'Area chart',
  });

  /// One or more filled series to plot.
  final List<AreaSeries> series;

  /// Visible x range. `null` autoscales to the data. See [LineChart.xRange].
  final (num min, num max)? xRange;

  /// Visible y range. `null` autoscales to the data. See [LineChart.yRange].
  final (num min, num max)? yRange;

  /// Extra space around autoscaled data, as a fraction of the range.
  final double padding;

  /// Draw min/mid/max labels for both axes.
  final bool showAxes;

  /// Draw faint mid-axis crosshair lines through the plot area.
  final bool showGrid;

  /// Draw a one-row legend with a colored bullet and label per series.
  final bool showLegend;

  /// Number of evenly-spaced y-axis tick labels, including both ends.
  final int yTickCount;

  /// Colors cycled for series that set neither [AreaSeries.color] nor
  /// [AreaSeries.gradient].
  final List<Color>? palette;

  /// Formatter for x-axis tick labels and the crosshair tooltip x value.
  final TickFormatter? xTickFormat;

  /// Formatter for y-axis tick labels and the crosshair tooltip y values.
  final TickFormatter? yTickFormat;

  /// Reference lines drawn under the data.
  final List<ReferenceLine> references;

  /// When true, the chart is focusable with an arrow-key crosshair.
  final bool interactive;

  /// Auto-focus on first mount when [interactive] is true.
  final bool autofocus;

  /// Optional caller-provided focus node for [interactive] mode.
  final FocusNode? focusNode;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fallback =
        palette ?? <Color>[Theme.of(context).colorScheme.primary];
    var autoIdx = 0;
    Color nextFallback() =>
        fallback[fallback.isEmpty ? 0 : autoIdx++ % fallback.length];
    return LineChart(
      series: <LineSeries>[
        for (final s in series)
          LineSeries(
            s.points,
            label: s.label,
            type: LineType.area,
            gradient: s.gradient ?? <Color>[s.color ?? nextFallback()],
          ),
      ],
      xRange: xRange,
      yRange: yRange,
      padding: padding,
      showAxes: showAxes,
      showGrid: showGrid,
      showLegend: showLegend,
      yTickCount: yTickCount,
      palette: palette,
      xTickFormat: xTickFormat,
      yTickFormat: yTickFormat,
      references: references,
      interactive: interactive,
      autofocus: autofocus,
      focusNode: focusNode,
      semanticLabel: semanticLabel,
    );
  }
}
