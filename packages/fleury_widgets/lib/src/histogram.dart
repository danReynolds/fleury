import 'package:fleury/fleury_core.dart';

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

  /// Whether each bar shows its bin midpoint label.
  final bool showLabels;

  /// Whether each bar shows its observation count.
  final bool showValues;

  /// Width of each bar in terminal cells.
  final int barWidth;

  /// Horizontal gap between adjacent bars in terminal cells.
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
        bars: showLabels
            ? _thinLabels(distribution.bars, barWidth: barWidth, gap: gap)
            : distribution.bars,
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
    // Auto range over the finite values only — one NaN/±Infinity sample
    // must not poison the bin edges.
    double? autoLo, autoHi;
    for (final v in values) {
      final d = v.toDouble();
      if (!d.isFinite) continue;
      if (autoLo == null || d < autoLo) autoLo = d;
      if (autoHi == null || d > autoHi) autoHi = d;
    }
    lo ??= autoLo ?? 0;
    hi ??= autoHi ?? 1;
  }
  if (hi == lo) hi = lo + 1;

  final binWidth = (hi - lo) / bins;
  final counts = List<int>.filled(bins, 0);
  var included = 0;
  for (final v in values) {
    final d = v.toDouble();
    // Non-finite values fall outside every bin (NaN compares false against
    // the bounds, and floor() on it would throw).
    if (!d.isFinite || d < lo || d > hi) continue;
    final rel = (d - lo) / binWidth;
    if (!rel.isFinite) continue; // degenerate user-supplied range
    var idx = rel.floor();
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

/// Blanks bin labels that would collide, keeping an evenly-spaced subset
/// (endpoints included) so the axis stays readable when many bins pack into a
/// narrow space. Bars are fixed width, so a stride in bins maps straight to
/// cell spacing: keep one label per `stride` bins, where `stride` is the bins
/// needed to clear the widest label plus a gap.
List<Bar> _thinLabels(
  List<Bar> bars, {
  required int barWidth,
  required int gap,
}) {
  if (bars.length < 2) return bars;
  var maxLen = 0;
  for (final b in bars) {
    if (b.label.length > maxLen) maxLen = b.label.length;
  }
  if (maxLen == 0) return bars;
  final slot = (barWidth < 1 ? 1 : barWidth) + (gap < 0 ? 0 : gap);
  final stride = ((maxLen + 1) / slot).ceil();
  if (stride <= 1) return bars; // every label already fits
  final last = bars.length - 1;
  final fit = last ~/ stride + 1; // labels that fit with spacing >= stride
  final keep = <int>{};
  if (fit < 2) {
    // Not even two labels clear the widest one — a forced pair of endpoints
    // would still overlap, so keep just the first.
    keep.add(0);
  } else {
    for (var j = 0; j < fit; j++) {
      keep.add((j * last / (fit - 1)).round());
    }
  }
  return <Bar>[
    for (var i = 0; i < bars.length; i++)
      if (keep.contains(i) || bars[i].value == null)
        bars[i]
      else
        Bar('', bars[i].value!, color: bars[i].color),
  ];
}
