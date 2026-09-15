import 'dart:math';

double percentile(Iterable<num> values, double p) {
  final sorted = values.map((n) => n.toDouble()).toList()..sort();
  if (sorted.isEmpty) throw ArgumentError('No samples');
  final index = (sorted.length - 1) * p;
  final lo = index.floor(), hi = index.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (index - lo);
}

/// Resamples fresh PROCESS PAIRS, never individual frames as independent runs.
/// The interval describes this machine/session, not a cross-machine guarantee.
Map<String, Object?> pairedEstimate(
    List<double> baseline, List<double> candidate,
    {double practicalPercent = 5, int seed = 251}) {
  if (baseline.isEmpty || baseline.length != candidate.length) {
    throw ArgumentError('Need matching nonempty process pairs');
  }
  final absolute = [
    for (var i = 0; i < baseline.length; i++) candidate[i] - baseline[i]
  ];
  final result = <String, Object?>{
    'pairs': baseline.length,
    'baseline': percentile(baseline, .5),
    'candidate': percentile(candidate, .5),
    'absoluteDelta': percentile(absolute, .5),
    'baselineRuns': baseline,
    'candidateRuns': candidate,
    'practicalPercent': practicalPercent,
  };
  if (baseline.any((n) => n <= 0) || candidate.any((n) => n <= 0)) {
    return {...result, 'verdict': 'below timer resolution'};
  }
  final differences = [
    for (var i = 0; i < baseline.length; i++)
      100 * (candidate[i] / baseline[i] - 1)
  ];
  final random = Random(seed);
  final boot = [
    for (var i = 0; i < 4000; i++)
      percentile([
        for (var j = 0; j < differences.length; j++)
          differences[random.nextInt(differences.length)]
      ], .5)
  ];
  final lower = percentile(boot, .025), upper = percentile(boot, .975);
  return {
    ...result,
    'deltaPercent': percentile(differences, .5),
    'interval95Percent': [lower, upper],
    'verdict': baseline.length < 5
        ? 'exploratory: fewer than 5 pairs'
        : lower > practicalPercent
            ? 'regression'
            : upper < -practicalPercent
                ? 'improvement'
                : 'no clear change',
  };
}
