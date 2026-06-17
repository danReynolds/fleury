import 'package:fleury/fleury.dart';

import 'bar_chart.dart';

/// A frequency-distribution chart: bins continuous [values] into equal-width
/// buckets and renders the counts as a [BarChart]. Useful for benchmark
/// distributions, latency percentiles, request-size histograms.
///
/// ```dart
/// Histogram(values: latenciesMs, bins: 12)
/// ```
///
/// Range defaults to autoscaled `[min(values), max(values)]`. Bin labels
/// are the midpoint of each bucket; turn them off with `showLabels: false`
/// when packing many bins into a narrow space.
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
class Histogram extends StatelessWidget {
  const Histogram({
    super.key,
    required this.values,
    this.bins = 10,
    this.range,
    this.showLabels = true,
    this.showValues = false,
    this.barWidth = 2,
    this.gap = 0,
    this.color,
    this.semanticLabel = 'Histogram',
  });

  /// Raw observations to bin.
  final List<num> values;

  /// Number of equal-width bins (≥ 1).
  final int bins;

  /// Explicit `(low, high)` range. `null` autoscales to `[min, max]` of
  /// [values]. Values outside the range are dropped.
  final (num, num)? range;

  final bool showLabels;
  final bool showValues;
  final int barWidth;
  final int gap;

  /// Bar color override; defaults to the theme's primary.
  final Color? color;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final distribution = _histogramDistribution(
      values,
      bins: bins,
      range: range,
      color: color,
    );
    if (distribution == null) {
      return Semantics(
        role: SemanticRole.chart,
        label: semanticLabel,
        state: const SemanticState({
          'chartType': 'histogram',
          'chartBarCount': 0,
          'chartPointCount': 0,
          'chartRecordedPointCount': 0,
        }),
        child: const EmptyBox(),
      );
    }

    return Semantics(
      role: SemanticRole.chart,
      label: semanticLabel,
      includeChildren: false,
      state: SemanticState({
        'chartType': 'histogram',
        'chartBarCount': distribution.bars.length,
        'chartPointCount': values.length,
        'chartRecordedPointCount': distribution.includedValueCount,
        'chartMinValue': distribution.low,
        'chartMaxValue': distribution.high,
      }),
      child: BarChart(
        bars: distribution.bars,
        barWidth: barWidth,
        gap: gap,
        showLabels: showLabels,
        showValues: showValues,
      ),
    );
  }

  static String _format(double v) {
    if (v == v.truncateToDouble() && v.abs() < 1e6) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(1);
  }
}

({List<Bar> bars, int includedValueCount, num low, num high})?
_histogramDistribution(
  List<num> values, {
  required int bins,
  required (num, num)? range,
  required Color? color,
}) {
  if (values.isEmpty || bins < 1) return null;

  var lo = range?.$1.toDouble();
  var hi = range?.$2.toDouble();
  if (lo == null || hi == null) {
    var autoLo = values.first.toDouble();
    var autoHi = values.first.toDouble();
    for (final v in values) {
      final d = v.toDouble();
      if (d < autoLo) autoLo = d;
      if (d > autoHi) autoHi = d;
    }
    lo ??= autoLo;
    hi ??= autoHi;
  }
  if (hi == lo) hi = lo + 1;

  final binWidth = (hi - lo) / bins;
  final counts = List<int>.filled(bins, 0);
  var included = 0;
  for (final v in values) {
    final d = v.toDouble();
    if (d < lo || d > hi) continue;
    var idx = ((d - lo) / binWidth).floor();
    if (idx >= bins) idx = bins - 1;
    if (idx < 0) idx = 0;
    counts[idx]++;
    included += 1;
  }

  final bars = <Bar>[
    for (var i = 0; i < bins; i++)
      Bar(
        Histogram._format(lo + (i + 0.5) * binWidth),
        counts[i],
        color: color,
      ),
  ];
  return (bars: bars, includedValueCount: included, low: lo, high: hi);
}
