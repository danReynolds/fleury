import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fleury_web/src/benchmark/web_benchmark_scenarios.dart';
import 'package:fleury_web/src/instrumentation/web_host_instrumentation.dart';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final runs = _loadRuns(
    options.inputDir,
    steadySkipFrames: options.steadySkipFrames,
  );
  final thresholdPolicy = _ThresholdPolicy.load(options.thresholdsPath);
  final scoreboard = _buildScoreboard(
    runs,
    inputDir: options.inputDir,
    minRuns: options.minRuns,
    steadySkipFrames: options.steadySkipFrames,
    gates: options.gates,
    thresholdPolicy: thresholdPolicy,
    thresholdsPath: options.thresholdsPath,
    requireComparableRunEnvironment: options.requireComparableRunEnvironment,
  );
  final scoreboardJson = const JsonEncoder.withIndent('  ').convert(scoreboard);
  if (options.jsonOutputPath != null) {
    final output = File(options.jsonOutputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$scoreboardJson\n');
  }
  if (options.json) {
    stdout.writeln(scoreboardJson);
  }
  if (options.writeThresholdsPath != null) {
    final policy = _buildCandidateThresholdPolicy(
      scoreboard,
      headroomPercent: options.thresholdHeadroomPercent,
      minHeadroomMs: options.thresholdMinHeadroomMs,
      minHeadroomPercent: options.thresholdMinHeadroomPercent,
    );
    final output = File(options.writeThresholdsPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(policy)}\n',
    );
    if (!options.json) stdout.writeln('wrote ${output.path}');
  }

  final outputPath = options.outputPath;
  final markdown = _markdown(scoreboard, inputDir: options.inputDir);
  if (outputPath == null) {
    if (!options.json) stdout.write(markdown);
  } else {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(markdown);
    stdout.writeln('wrote ${output.path}');
  }

  if (options.strict && scoreboard['strictPass'] != true) exit(1);
}

Map<String, Object?> _buildCandidateThresholdPolicy(
  Map<String, Object?> scoreboard, {
  required double headroomPercent,
  required double minHeadroomMs,
  required double minHeadroomPercent,
}) {
  final captureEnvironment = _captureEnvironmentSummary(scoreboard);
  final scenarios = <String, Object?>{};
  final rawScenarios = scoreboard['scenarios'];
  if (rawScenarios is List<Object?>) {
    for (final rawScenario in rawScenarios) {
      if (rawScenario is! Map<String, Object?>) continue;
      final id = rawScenario['id']?.toString();
      if (id == null || id.isEmpty) continue;
      scenarios[id] = <String, Object?>{
        'maxTotalFrameP95Ms': _msThreshold(
          _metricMax(rawScenario, 'totalFrameP95Ms'),
          headroomPercent: headroomPercent,
          minHeadroomMs: minHeadroomMs,
        ),
        'maxDomApplyP95Ms': _msThreshold(
          _metricMax(rawScenario, 'domApplyP95Ms'),
          headroomPercent: headroomPercent,
          minHeadroomMs: minHeadroomMs,
        ),
        'maxSemanticApplyP95Ms': _msThreshold(
          _metricMax(rawScenario, 'semanticApplyP95Ms'),
          headroomPercent: headroomPercent,
          minHeadroomMs: minHeadroomMs,
        ),
        'maxOverBudgetPercent': _percentThreshold(
          _metricMax(rawScenario, 'overBudgetPercent'),
          headroomPercent: headroomPercent,
          minHeadroomPercent: minHeadroomPercent,
        ),
        'maxSteadyTotalFrameP95Ms': _msThreshold(
          _metricMax(rawScenario, 'steadyTotalFrameP95Ms'),
          headroomPercent: headroomPercent,
          minHeadroomMs: minHeadroomMs,
        ),
        'maxSteadySemanticApplyP95Ms': _msThreshold(
          _metricMax(rawScenario, 'steadySemanticApplyP95Ms'),
          headroomPercent: headroomPercent,
          minHeadroomMs: minHeadroomMs,
        ),
        'maxSteadyOverBudgetPercent': _percentThreshold(
          _metricMax(rawScenario, 'steadyOverBudgetPercent'),
          headroomPercent: headroomPercent,
          minHeadroomPercent: minHeadroomPercent,
        ),
        'maxSemanticUncoveredCells': _metricMax(
          rawScenario,
          'semanticUncoveredCellsMax',
        ).ceil(),
        'observedFrameCount': rawScenario['frameCount'],
        'observedSteadyFrameCount': rawScenario['steadyFrameCount'],
        'observedRequestedStepCount': rawScenario['requestedStepCount'],
        'observedExtraFrameCount': rawScenario['extraFrameCount'],
        'observedMaxFramesPerStep': _metricMax(rawScenario, 'framesPerStep'),
        'observedMaxRuntimeBuildP95Ms': _optionalMetricMax(
          rawScenario,
          'runtimeBuildP95Ms',
        ),
        'observedMaxRuntimeLayoutP95Ms': _optionalMetricMax(
          rawScenario,
          'runtimeLayoutP95Ms',
        ),
        'observedMaxRuntimePaintP95Ms': _optionalMetricMax(
          rawScenario,
          'runtimePaintP95Ms',
        ),
      };
    }
  }
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebFrameThresholds',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'reviewState': 'candidate',
    'reviewNote':
        'Generated from observed retained DOM web frame captures; review before using as a release gate.',
    'generatedFrom': <String, Object?>{
      'kind': scoreboard['kind'],
      'inputDir': scoreboard['inputDir'],
      'scoreboardGeneratedAt': scoreboard['generatedAt'],
      'minRuns': scoreboard['minRuns'],
      'runCount': scoreboard['runCount'],
      'scenarioCount': scoreboard['scenarioCount'],
      'sourceMetric': 'maxCaptureP95PerScenario',
      'thresholdHeadroomPercent': headroomPercent,
      'thresholdMinHeadroomMs': minHeadroomMs,
      'thresholdMinHeadroomPercent': minHeadroomPercent,
      'steadySkipFrames': scoreboard['steadySkipFrames'],
      if (captureEnvironment.isNotEmpty)
        'captureEnvironment': captureEnvironment,
    },
    'defaults': const <String, Object?>{},
    'scenarios': scenarios,
  };
}

Map<String, Object?> _captureEnvironmentSummary(
  Map<String, Object?> scoreboard,
) {
  final rawScenarios = scoreboard['scenarios'];
  if (rawScenarios is! List<Object?> || rawScenarios.isEmpty) {
    return const <String, Object?>{};
  }
  final scenarios = [
    for (final rawScenario in rawScenarios)
      if (rawScenario is Map<String, Object?>) rawScenario,
  ];
  if (scenarios.isEmpty) return const <String, Object?>{};
  final environments = [
    for (final scenario in scenarios)
      if (_map(scenario['latestRunEnvironment']).isNotEmpty)
        _map(scenario['latestRunEnvironment']),
  ];
  if (environments.isEmpty) return const <String, Object?>{};

  final chromeBrowsers = _uniqueEnvironmentValues(
    environments,
    'chromeBrowser',
  );
  final operatingSystems = _uniqueEnvironmentValues(
    environments,
    'operatingSystem',
  );
  final operatingSystemVersions = _uniqueEnvironmentValues(
    environments,
    'operatingSystemVersion',
  );
  final dartVersions = _uniqueEnvironmentValues(environments, 'dartVersion');
  final headlessValues = _uniqueEnvironmentValues(environments, 'headless');
  final frameBudgetValues = _uniqueEnvironmentValues(
    environments,
    'frameBudgetMs',
  );
  final requestedFrameValues = _uniqueEnvironmentValues(
    environments,
    'requestedFrames',
  );
  final warmupFrameValues = _uniqueEnvironmentValues(
    environments,
    'warmupFrames',
  );
  final comparableScenarioCount = scenarios
      .where((scenario) => scenario['runEnvironmentComparable'] == true)
      .length;

  return <String, Object?>{
    'scenarioCount': scenarios.length,
    'scenarioWithEnvironmentCount': environments.length,
    'comparableScenarioCount': comparableScenarioCount,
    'allScenariosComparable':
        comparableScenarioCount == scenarios.length &&
        environments.length == scenarios.length,
    if (chromeBrowsers.isNotEmpty)
      'chromeBrowser': _singleOrList(chromeBrowsers),
    if (operatingSystems.isNotEmpty)
      'operatingSystem': _singleOrList(operatingSystems),
    if (operatingSystemVersions.isNotEmpty)
      'operatingSystemVersion': _singleOrList(operatingSystemVersions),
    if (dartVersions.isNotEmpty) 'dartVersion': _singleOrList(dartVersions),
    if (headlessValues.isNotEmpty) 'headless': _singleOrList(headlessValues),
    if (frameBudgetValues.isNotEmpty)
      'frameBudgetMs': _singleOrList(frameBudgetValues),
    if (requestedFrameValues.isNotEmpty)
      'requestedFrames': _singleOrList(requestedFrameValues),
    if (warmupFrameValues.isNotEmpty)
      'warmupFrames': _singleOrList(warmupFrameValues),
    if (chromeBrowsers.isNotEmpty && operatingSystems.isNotEmpty)
      'reviewContextHint': _reviewContextHint(
        chromeBrowsers: chromeBrowsers,
        operatingSystems: operatingSystems,
        operatingSystemVersions: operatingSystemVersions,
        dartVersions: dartVersions,
        headlessValues: headlessValues,
        frameBudgetValues: frameBudgetValues,
      ),
  };
}

Map<String, Object?> _map(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) return raw.cast<String, Object?>();
  return const <String, Object?>{};
}

List<Object?> _uniqueEnvironmentValues(
  List<Map<String, Object?>> environments,
  String key,
) {
  final values = <Object?>[];
  for (final environment in environments) {
    final value = environment[key];
    if (value == null || values.contains(value)) continue;
    values.add(value);
  }
  return values;
}

Object? _singleOrList(List<Object?> values) {
  if (values.length == 1) return values.single;
  return values;
}

String _reviewContextHint({
  required List<Object?> chromeBrowsers,
  required List<Object?> operatingSystems,
  required List<Object?> operatingSystemVersions,
  required List<Object?> dartVersions,
  required List<Object?> headlessValues,
  required List<Object?> frameBudgetValues,
}) {
  final parts = <String>[];
  parts.add(_contextValue(chromeBrowsers, label: 'Browser'));
  final platform = [
    _contextValue(operatingSystems, label: 'OS'),
    if (operatingSystemVersions.isNotEmpty)
      _contextValue(operatingSystemVersions, label: 'OS version'),
  ].join(' ');
  parts.add(platform);
  if (dartVersions.isNotEmpty) {
    parts.add(_contextValue(dartVersions, label: 'Dart'));
  }
  if (headlessValues.isNotEmpty) {
    parts.add('headless=${_contextValue(headlessValues)}');
  }
  if (frameBudgetValues.isNotEmpty) {
    parts.add('frameBudgetMs=${_contextValue(frameBudgetValues)}');
  }
  parts.add('retained DOM product baseline');
  return parts.where((part) => part.trim().isNotEmpty).join(', ');
}

String _contextValue(List<Object?> values, {String? label}) {
  if (values.isEmpty) return '';
  final value = values.length == 1 ? values.single : 'mixed ${values.length}';
  return label == null ? '$value' : '$label $value';
}

double _msThreshold(
  double observedMax, {
  required double headroomPercent,
  required double minHeadroomMs,
}) {
  if (observedMax <= 0) return 0;
  return _roundUp(
    math.max(
      observedMax * (1 + headroomPercent / 100),
      observedMax + minHeadroomMs,
    ),
  );
}

double _percentThreshold(
  double observedMax, {
  required double headroomPercent,
  required double minHeadroomPercent,
}) {
  if (observedMax <= 0) return 0;
  return math.min(
    100,
    _roundUp(
      math.max(
        observedMax * (1 + headroomPercent / 100),
        observedMax + minHeadroomPercent,
      ),
    ),
  );
}

double _roundUp(double value) {
  const precision = 100;
  return (math.max(0, value - 1e-9) * precision).ceilToDouble() / precision;
}

Map<String, Object?> _buildScoreboard(
  List<_WebFrameRun> runs, {
  required String inputDir,
  required int minRuns,
  required int steadySkipFrames,
  required _GateOptions gates,
  required _ThresholdPolicy thresholdPolicy,
  required String? thresholdsPath,
  required bool requireComparableRunEnvironment,
}) {
  final byScenario = <String, List<_WebFrameRun>>{};
  for (final run in runs) {
    (byScenario[run.scenarioId] ??= <_WebFrameRun>[]).add(run);
  }
  final summaries = [
    for (final entry in byScenario.entries)
      _ScenarioAggregate.from(
        entry.key,
        entry.value,
        minRuns: minRuns,
        steadySkipFrames: steadySkipFrames,
        gates: thresholdPolicy.gatesFor(entry.key, fallback: gates),
        thresholdPolicyPath: thresholdsPath,
        thresholdPolicyMatchedScenario: thresholdPolicy.hasScenario(entry.key),
        requireComparableRunEnvironment: requireComparableRunEnvironment,
      ).toJson(),
  ]..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
  final strictPass = summaries.every(
    (summary) => summary['strictPass'] == true,
  );
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebFrameScoreboard',
    'inputDir': inputDir,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'minRuns': minRuns,
    'steadySkipFrames': steadySkipFrames,
    if (thresholdsPath != null) 'thresholdPolicyPath': thresholdsPath,
    if (thresholdPolicy.reviewState != null)
      'thresholdPolicyReviewState': thresholdPolicy.reviewState,
    if (thresholdPolicy.reviewedBy != null)
      'thresholdPolicyReviewedBy': thresholdPolicy.reviewedBy,
    if (thresholdPolicy.reviewedAt != null)
      'thresholdPolicyReviewedAt': thresholdPolicy.reviewedAt,
    if (thresholdPolicy.reviewContext != null)
      'thresholdPolicyReviewContext': thresholdPolicy.reviewContext,
    if (thresholdPolicy.fingerprint != null)
      'thresholdPolicyFingerprint': thresholdPolicy.fingerprint,
    if (thresholdsPath != null)
      'thresholdPolicyScenarioCount': thresholdPolicy.scenarios.length,
    'requireComparableRunEnvironment': requireComparableRunEnvironment,
    'scenarioCount': summaries.length,
    'runCount': runs.length,
    'strictPass': strictPass,
    'scenarios': summaries,
  };
}

String _markdown(Map<String, Object?> scoreboard, {required String inputDir}) {
  final scenarios = (scoreboard['scenarios'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final steadySkipFrames =
      (scoreboard['steadySkipFrames'] as num?)?.toInt() ?? 0;
  const columns = [
    'Scenario',
    'Runs',
    'Run Env',
    'Frames / steps',
    'Total p95',
    'Runtime p95',
    'Build p95',
    'Layout p95',
    'Paint p95',
    'Row diff p95',
    'Span p95',
    'DOM p95',
    'Semantic p95',
    'Over budget',
    'Steady total p95',
    'Steady semantic p95',
    'Steady over budget',
    'Browser layout',
    'Browser style',
    'Browser task',
    'JS heap',
    'DOM nodes',
    'Uncovered cells',
    'Gates',
    'Dominant p95 slices',
    'Latest capture',
  ];
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Frame Scoreboard')
    ..writeln()
    ..writeln('Generated from `$inputDir` at `${scoreboard['generatedAt']}`.')
    ..writeln()
    ..writeln(
      'Values are medians across capture-level p95s unless noted. '
      'This scoreboard is for retained DOM browser captures, not PTY byte runs.',
    )
    ..writeln();

  if (steadySkipFrames > 0) {
    buffer
      ..writeln(
        'Steady-state columns skip the first `$steadySkipFrames` captured frame(s).',
      )
      ..writeln();
  }

  buffer
    ..writeln('| ${columns.join(' | ')} |')
    ..writeln('| ${List.filled(columns.length, '---').join(' | ')} |');

  if (scenarios.isEmpty) {
    final row = List<String>.filled(columns.length, '-');
    row[1] = '0';
    row[3] = '0';
    buffer.writeln('| ${row.join(' | ')} |');
    return buffer.toString();
  }

  for (final scenario in scenarios) {
    buffer.writeln(
      '| ${scenario['id']} | '
      '${scenario['runCount']} | '
      '${_runEnvironmentCell(scenario)} | '
      '${_frameAccountingCell(scenario)} | '
      '${_metricCell(scenario, 'totalFrameP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'runtimeRenderP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'runtimeBuildP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'runtimeLayoutP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'runtimePaintP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'dirtyRowDiffP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'spanBuildP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'domApplyP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'semanticApplyP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'overBudgetPercent', _fmtPercent)} | '
      '${_metricCell(scenario, 'steadyTotalFrameP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'steadySemanticApplyP95Ms', _fmtMs)} | '
      '${_metricCell(scenario, 'steadyOverBudgetPercent', _fmtPercent)} | '
      '${_metricCell(scenario, 'browserLayoutDurationMs', _fmtMs)} | '
      '${_metricCell(scenario, 'browserRecalcStyleDurationMs', _fmtMs)} | '
      '${_metricCell(scenario, 'browserTaskDurationMs', _fmtMs)} | '
      '${_metricCell(scenario, 'browserJsHeapUsedBytes', _fmtBytes)} | '
      '${_metricCell(scenario, 'browserDomNodeCount', _fmtNumber)} | '
      '${_metricCell(scenario, 'semanticUncoveredCellsMax', _fmtNumber)} | '
      '${_gateFailures(scenario)} | '
      '${_dominantSlices(scenario)} | '
      '${scenario['latestCapture']} |',
    );
  }

  return buffer.toString();
}

String _runEnvironmentCell(Map<String, Object?> scenario) {
  final comparable = scenario['runEnvironmentComparable'] == true;
  final required = scenario['requireComparableRunEnvironment'] == true;
  final missing =
      (scenario['missingRunEnvironmentCount'] as num?)?.toInt() ?? 0;
  final count =
      (scenario['runEnvironmentSignatureCount'] as num?)?.toInt() ?? 0;
  if (required) {
    if (comparable) return 'pass';
    if (missing > 0) return 'fail<br>$missing missing';
    return 'fail<br>$count signatures';
  }
  if (comparable) return '1 signature';
  if (missing > 0) return '$count signatures<br>$missing missing';
  return '$count signatures';
}

String _frameAccountingCell(Map<String, Object?> scenario) {
  final frameCount = (scenario['frameCount'] as num?)?.toInt();
  final requestedStepCount = (scenario['requestedStepCount'] as num?)?.toInt();
  final extraFrameCount = (scenario['extraFrameCount'] as num?)?.toInt();
  if (frameCount == null) return '-';
  if (requestedStepCount == null) return '$frameCount';
  final extra = extraFrameCount == null || extraFrameCount == 0
      ? ''
      : '<br>+$extraFrameCount extra';
  return '$frameCount / $requestedStepCount$extra';
}

String _gateFailures(Map<String, Object?> scenario) {
  final gates = scenario['gates'];
  if (gates is! List || gates.isEmpty) return '-';
  final failed = [
    for (final gate in gates.cast<Map<String, Object?>>())
      if (gate['passed'] != true)
        '${gate['id']}:${_fmtGateValue((gate['actual'] as num).toDouble(), gate['unit'].toString())}>${_fmtGateValue((gate['maximum'] as num).toDouble(), gate['unit'].toString())}',
  ];
  if (failed.isEmpty) return 'pass';
  return failed.join('<br>');
}

String _metricCell(
  Map<String, Object?> scenario,
  String key,
  String Function(double) format,
) {
  final metric = scenario[key];
  if (metric is! Map<String, Object?>) return '-';
  final median = (metric['median'] as num?)?.toDouble();
  final min = (metric['min'] as num?)?.toDouble();
  final max = (metric['max'] as num?)?.toDouble();
  if (median == null) return '-';
  final spread = min == null || max == null || min == max
      ? ''
      : '<br>${format(min)}-${format(max)}';
  return '${format(median)}$spread';
}

String _dominantSlices(Map<String, Object?> scenario) {
  final slices = scenario['dominantP95Slices'];
  if (slices is! Map<String, Object?> || slices.isEmpty) return '-';
  final entries = slices.entries.toList()
    ..sort((a, b) {
      final count = (b.value as num).compareTo(a.value as num);
      return count == 0 ? a.key.compareTo(b.key) : count;
    });
  return entries.map((entry) => '${entry.key}:${entry.value}').join('<br>');
}

List<_WebFrameRun> _loadRuns(String inputDir, {required int steadySkipFrames}) {
  final root = Directory(inputDir);
  if (!root.existsSync()) return const [];
  final runs = <_WebFrameRun>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final run = _tryLoadRun(entity, steadySkipFrames: steadySkipFrames);
    if (run != null) runs.add(run);
  }
  runs.sort((a, b) => a.path.compareTo(b.path));
  return runs;
}

_WebFrameRun? _tryLoadRun(File file, {required int steadySkipFrames}) {
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final capture = decoded.cast<String, Object?>();
  final frames = capture['frames'];
  if (capture['kind'] != 'fleuryWebFrameCapture' || frames is! List) {
    return null;
  }
  final scenarioId = _scenarioIdFor(capture, file.path);
  final frameBudgetMs =
      (capture['frameBudgetMs'] as num?)?.toDouble() ?? defaultWebFrameBudgetMs;
  final parsedFrames = [
    for (final rawFrame in frames)
      WebFrameInstrumentation.fromJson(
        (rawFrame as Map).cast<String, Object?>(),
      ),
  ];
  final summary = WebInstrumentationSummary.fromFrames(
    parsedFrames,
    frameBudgetMs: frameBudgetMs,
  );
  final steadySummary = WebInstrumentationSummary.fromFrames(
    parsedFrames.skip(steadySkipFrames),
    frameBudgetMs: frameBudgetMs,
  );
  return _WebFrameRun(
    path: file.path,
    scenarioId: scenarioId,
    capturedAt: capture['capturedAt']?.toString(),
    summary: summary,
    steadySummary: steadySummary,
    steadySkipFrames: steadySkipFrames,
    browserMetrics: _readBrowserMetrics(capture['browserMetrics']),
    runEnvironment: _readRunEnvironment(capture['runEnvironment']),
    requestedFrameCount: _readOptionalInt(capture['requestedFrames']),
    requestedStepCount: _readOptionalInt(capture['requestedSteps']),
  );
}

String _scenarioIdFor(Map<String, Object?> capture, String path) {
  final scenario = capture['scenario'];
  if (scenario is Map && scenario['id'] != null) {
    return scenario['id'].toString();
  }
  final name = path.split(Platform.pathSeparator).last;
  if (name.endsWith('.json')) return name.substring(0, name.length - 5);
  return name;
}

final class _WebFrameRun {
  const _WebFrameRun({
    required this.path,
    required this.scenarioId,
    required this.capturedAt,
    required this.summary,
    required this.steadySummary,
    required this.steadySkipFrames,
    required this.browserMetrics,
    required this.runEnvironment,
    required this.requestedFrameCount,
    required this.requestedStepCount,
  });

  final String path;
  final String scenarioId;
  final String? capturedAt;
  final WebInstrumentationSummary summary;
  final WebInstrumentationSummary steadySummary;
  final int steadySkipFrames;
  final WebBrowserPerformanceMetrics? browserMetrics;
  final Map<String, Object?>? runEnvironment;
  final int? requestedFrameCount;
  final int? requestedStepCount;

  int get frameCount => summary.frameCount;
  int get steadyFrameCount => steadySummary.frameCount;
  int get effectiveRequestedStepCount =>
      requestedStepCount ?? requestedFrameCount ?? frameCount;
  int get extraFrameCount => frameCount - effectiveRequestedStepCount;
  double get framesPerStep => effectiveRequestedStepCount <= 0
      ? 0
      : frameCount / effectiveRequestedStepCount;
  double get totalFrameP95Ms => _timingP95('totalFrameMs');
  double get steadyTotalFrameP95Ms => _steadyTimingP95('totalFrameMs');
  double get runtimeRenderP95Ms => _timingP95('runtimeRenderMs');
  double? get runtimeBuildP95Ms => _optionalTimingP95('runtimeBuildMs');
  double? get runtimeLayoutP95Ms => _optionalTimingP95('runtimeLayoutMs');
  double? get runtimePaintP95Ms => _optionalTimingP95('runtimePaintMs');
  double get dirtyRowDiffP95Ms => _timingP95('dirtyRowDiffMs');
  double get spanBuildP95Ms => _timingP95('spanBuildMs');
  double get domApplyP95Ms => _timingP95('domApplyMs');
  double get semanticApplyP95Ms => _timingP95('semanticApplyMs');
  double get overBudgetPercent => summary.overBudgetPercent;
  double get steadySemanticApplyP95Ms => _steadyTimingP95('semanticApplyMs');
  double get steadyOverBudgetPercent => steadySummary.overBudgetPercent;
  double get semanticUncoveredCellsMax =>
      summary.counts['semanticUncoveredCells']?.max ?? 0;
  String get dominantP95Slice => summary.dominantP95Slice;

  double _timingP95(String key) => summary.timings[key]?.p95 ?? 0;
  double _steadyTimingP95(String key) => steadySummary.timings[key]?.p95 ?? 0;
  double? _optionalTimingP95(String key) {
    final metric = summary.timings[key];
    if (metric == null || metric.sampleCount == 0) return null;
    return metric.p95;
  }
}

final class _ScenarioAggregate {
  _ScenarioAggregate({
    required this.id,
    required this.label,
    required this.runs,
    required this.minRuns,
    required this.steadySkipFrames,
    required this.gates,
    required this.thresholdPolicyPath,
    required this.thresholdPolicyMatchedScenario,
    required this.requireComparableRunEnvironment,
  });

  factory _ScenarioAggregate.from(
    String id,
    List<_WebFrameRun> runs, {
    required int minRuns,
    required int steadySkipFrames,
    required _GateOptions gates,
    required String? thresholdPolicyPath,
    required bool thresholdPolicyMatchedScenario,
    required bool requireComparableRunEnvironment,
  }) {
    final scenario = webBenchmarkScenarioById(id);
    return _ScenarioAggregate(
      id: id,
      label: scenario?.label ?? id,
      runs: List.unmodifiable(runs),
      minRuns: minRuns,
      steadySkipFrames: steadySkipFrames,
      gates: gates,
      thresholdPolicyPath: thresholdPolicyPath,
      thresholdPolicyMatchedScenario: thresholdPolicyMatchedScenario,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
    );
  }

  final String id;
  final String label;
  final List<_WebFrameRun> runs;
  final int minRuns;
  final int steadySkipFrames;
  final _GateOptions gates;
  final String? thresholdPolicyPath;
  final bool thresholdPolicyMatchedScenario;
  final bool requireComparableRunEnvironment;

  Map<String, Object?> toJson() {
    final latest = _latestRun;
    final runEnvironmentSignatures = _counts(
      runs.map((run) => _runEnvironmentSignature(run.runEnvironment)),
    );
    final missingRunEnvironmentCount = runs
        .where((run) => run.runEnvironment == null)
        .length;
    final runEnvironmentComparable =
        runs.isNotEmpty &&
        missingRunEnvironmentCount == 0 &&
        runEnvironmentSignatures.length == 1;
    final json = <String, Object?>{
      'id': id,
      'label': label,
      'runCount': runs.length,
      'sufficientRunCount': runs.length >= minRuns,
      if (thresholdPolicyPath != null)
        'thresholdPolicyPath': thresholdPolicyPath,
      if (thresholdPolicyPath != null)
        'thresholdPolicyMatchedScenario': thresholdPolicyMatchedScenario,
      'requireComparableRunEnvironment': requireComparableRunEnvironment,
      'runEnvironmentComparable': runEnvironmentComparable,
      'runEnvironmentSignatureCount': runEnvironmentSignatures.length,
      'missingRunEnvironmentCount': missingRunEnvironmentCount,
      'runEnvironmentSignatures': runEnvironmentSignatures,
      if (latest?.runEnvironment != null)
        'latestRunEnvironment': latest!.runEnvironment,
      'frameCount': runs.fold<int>(0, (sum, run) => sum + run.frameCount),
      'steadySkipFrames': steadySkipFrames,
      'steadyFrameCount': runs.fold<int>(
        0,
        (sum, run) => sum + run.steadyFrameCount,
      ),
      'requestedStepCount': runs.fold<int>(
        0,
        (sum, run) => sum + run.effectiveRequestedStepCount,
      ),
      'extraFrameCount': runs.fold<int>(
        0,
        (sum, run) => sum + run.extraFrameCount,
      ),
      'framesPerStep': _metric(runs.map((run) => run.framesPerStep)),
      'latestCapture': latest == null ? null : _fileName(latest.path),
      'latestCapturedAt': latest?.capturedAt,
      'totalFrameP95Ms': _metric(runs.map((run) => run.totalFrameP95Ms)),
      'runtimeRenderP95Ms': _metric(runs.map((run) => run.runtimeRenderP95Ms)),
      'runtimeBuildP95Ms': _metric(runs.map((run) => run.runtimeBuildP95Ms)),
      'runtimeLayoutP95Ms': _metric(runs.map((run) => run.runtimeLayoutP95Ms)),
      'runtimePaintP95Ms': _metric(runs.map((run) => run.runtimePaintP95Ms)),
      'dirtyRowDiffP95Ms': _metric(runs.map((run) => run.dirtyRowDiffP95Ms)),
      'spanBuildP95Ms': _metric(runs.map((run) => run.spanBuildP95Ms)),
      'domApplyP95Ms': _metric(runs.map((run) => run.domApplyP95Ms)),
      'semanticApplyP95Ms': _metric(runs.map((run) => run.semanticApplyP95Ms)),
      'overBudgetPercent': _metric(runs.map((run) => run.overBudgetPercent)),
      'steadyTotalFrameP95Ms': _metric(
        runs.map((run) => run.steadyTotalFrameP95Ms),
      ),
      'steadySemanticApplyP95Ms': _metric(
        runs.map((run) => run.steadySemanticApplyP95Ms),
      ),
      'steadyOverBudgetPercent': _metric(
        runs.map((run) => run.steadyOverBudgetPercent),
      ),
      'browserLayoutDurationMs': _browserDoubleMetric(
        (metrics) => metrics.layoutDurationMs,
      ),
      'browserRecalcStyleDurationMs': _browserDoubleMetric(
        (metrics) => metrics.recalcStyleDurationMs,
      ),
      'browserScriptDurationMs': _browserDoubleMetric(
        (metrics) => metrics.scriptDurationMs,
      ),
      'browserTaskDurationMs': _browserDoubleMetric(
        (metrics) => metrics.taskDurationMs,
      ),
      'browserJsHeapUsedBytes': _browserDoubleMetric(
        (metrics) => metrics.jsHeapUsedBytes,
      ),
      'browserJsHeapTotalBytes': _browserDoubleMetric(
        (metrics) => metrics.jsHeapTotalBytes,
      ),
      'browserDomDocumentCount': _browserIntMetric(
        (metrics) => metrics.domDocumentCount,
      ),
      'browserDomNodeCount': _browserIntMetric(
        (metrics) => metrics.domNodeCount,
      ),
      'browserJsEventListenerCount': _browserIntMetric(
        (metrics) => metrics.jsEventListenerCount,
      ),
      'semanticUncoveredCellsMax': _metric(
        runs.map((run) => run.semanticUncoveredCellsMax),
      ),
      'dominantP95Slices': _counts(runs.map((run) => run.dominantP95Slice)),
      'captures': [
        for (final run in runs)
          <String, Object?>{
            'path': run.path,
            'file': _fileName(run.path),
            'capturedAt': run.capturedAt,
            'frameCount': run.frameCount,
            'steadyFrameCount': run.steadyFrameCount,
            'requestedStepCount': run.effectiveRequestedStepCount,
            'extraFrameCount': run.extraFrameCount,
            'framesPerStep': run.framesPerStep,
            'totalFrameP95Ms': run.totalFrameP95Ms,
            'runtimeRenderP95Ms': run.runtimeRenderP95Ms,
            'runtimeBuildP95Ms': run.runtimeBuildP95Ms,
            'runtimeLayoutP95Ms': run.runtimeLayoutP95Ms,
            'runtimePaintP95Ms': run.runtimePaintP95Ms,
            'dirtyRowDiffP95Ms': run.dirtyRowDiffP95Ms,
            'spanBuildP95Ms': run.spanBuildP95Ms,
            'domApplyP95Ms': run.domApplyP95Ms,
            'semanticApplyP95Ms': run.semanticApplyP95Ms,
            'overBudgetPercent': run.overBudgetPercent,
            'steadyTotalFrameP95Ms': run.steadyTotalFrameP95Ms,
            'steadySemanticApplyP95Ms': run.steadySemanticApplyP95Ms,
            'steadyOverBudgetPercent': run.steadyOverBudgetPercent,
            'semanticUncoveredCellsMax': run.semanticUncoveredCellsMax,
            'dominantP95Slice': run.dominantP95Slice,
            if (run.browserMetrics != null)
              'browserMetrics': run.browserMetrics!.toJson(),
            if (run.runEnvironment != null)
              'runEnvironment': run.runEnvironment,
          },
      ],
    };
    final gateResults = _gateResults(json);
    json['gates'] = [for (final gate in gateResults) gate.toJson()];
    json['strictPass'] =
        runs.length >= minRuns &&
        gateResults.every((gate) => gate.passed) &&
        (!requireComparableRunEnvironment || runEnvironmentComparable);
    return json;
  }

  List<_GateResult> _gateResults(Map<String, Object?> json) {
    return [
      if (gates.maxTotalFrameP95Ms case final limit?)
        _GateResult(
          id: 'totalFrameP95MedianMs',
          actual: _metricMedian(json, 'totalFrameP95Ms'),
          maximum: limit,
          unit: 'ms',
        ),
      if (gates.maxDomApplyP95Ms case final limit?)
        _GateResult(
          id: 'domApplyP95MedianMs',
          actual: _metricMedian(json, 'domApplyP95Ms'),
          maximum: limit,
          unit: 'ms',
        ),
      if (gates.maxSemanticApplyP95Ms case final limit?)
        _GateResult(
          id: 'semanticApplyP95MedianMs',
          actual: _metricMedian(json, 'semanticApplyP95Ms'),
          maximum: limit,
          unit: 'ms',
        ),
      if (gates.maxOverBudgetPercent case final limit?)
        _GateResult(
          id: 'overBudgetPercentMedian',
          actual: _metricMedian(json, 'overBudgetPercent'),
          maximum: limit,
          unit: '%',
        ),
      if (gates.maxSteadyTotalFrameP95Ms case final limit?)
        _GateResult(
          id: 'steadyTotalFrameP95MedianMs',
          actual: _metricMedian(json, 'steadyTotalFrameP95Ms'),
          maximum: limit,
          unit: 'ms',
        ),
      if (gates.maxSteadySemanticApplyP95Ms case final limit?)
        _GateResult(
          id: 'steadySemanticApplyP95MedianMs',
          actual: _metricMedian(json, 'steadySemanticApplyP95Ms'),
          maximum: limit,
          unit: 'ms',
        ),
      if (gates.maxSteadyOverBudgetPercent case final limit?)
        _GateResult(
          id: 'steadyOverBudgetPercentMedian',
          actual: _metricMedian(json, 'steadyOverBudgetPercent'),
          maximum: limit,
          unit: '%',
        ),
      if (gates.maxSemanticUncoveredCells case final limit?)
        _GateResult(
          id: 'semanticUncoveredCellsMax',
          actual: _metricMax(json, 'semanticUncoveredCellsMax'),
          maximum: limit,
          unit: 'count',
        ),
    ];
  }

  _WebFrameRun? get _latestRun {
    if (runs.isEmpty) return null;
    return runs.reduce((a, b) {
      final aTime = a.capturedAt ?? '';
      final bTime = b.capturedAt ?? '';
      return aTime.compareTo(bTime) >= 0 ? a : b;
    });
  }

  Map<String, Object?> _browserDoubleMetric(
    double? Function(WebBrowserPerformanceMetrics metrics) read,
  ) {
    return _metric(_browserValues(read));
  }

  Map<String, Object?> _browserIntMetric(
    int? Function(WebBrowserPerformanceMetrics metrics) read,
  ) {
    return _metric(_browserValues((metrics) => read(metrics)?.toDouble()));
  }

  Iterable<double> _browserValues(
    double? Function(WebBrowserPerformanceMetrics metrics) read,
  ) sync* {
    for (final run in runs) {
      final metrics = run.browserMetrics;
      if (metrics == null) continue;
      final value = read(metrics);
      if (value != null) yield value;
    }
  }
}

Map<String, Object?> _metric(Iterable<double?> values) {
  final sorted = [
    for (final value in values)
      if (value != null && value.isFinite) value,
  ]..sort();
  if (sorted.isEmpty) {
    return const <String, Object?>{'median': null, 'min': null, 'max': null};
  }
  return <String, Object?>{
    'median': _median(sorted),
    'min': sorted.first,
    'max': sorted.last,
  };
}

double _median(List<double> sorted) {
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

Map<String, Object?> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}

String _fileName(String path) {
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

String _fmtMs(double value) => '${value.toStringAsFixed(2)} ms';
String _fmtPercent(double value) => '${value.toStringAsFixed(1)}%';

String _fmtNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _fmtBytes(double value) {
  const kib = 1024.0;
  const mib = kib * 1024;
  if (value.abs() >= mib) return '${(value / mib).toStringAsFixed(2)} MiB';
  if (value.abs() >= kib) return '${(value / kib).toStringAsFixed(2)} KiB';
  return '${value.toStringAsFixed(0)} B';
}

String _fmtGateValue(double value, String unit) {
  return switch (unit) {
    'ms' => _fmtMs(value),
    '%' => _fmtPercent(value),
    _ => _fmtNumber(value),
  };
}

double _metricMedian(Map<String, Object?> json, String key) {
  final metric = json[key];
  if (metric is! Map<String, Object?>) return 0;
  return (metric['median'] as num?)?.toDouble() ?? 0;
}

double _metricMax(Map<String, Object?> json, String key) {
  final metric = json[key];
  if (metric is! Map<String, Object?>) return 0;
  return (metric['max'] as num?)?.toDouble() ?? 0;
}

double? _optionalMetricMax(Map<String, Object?> json, String key) {
  final metric = json[key];
  if (metric is! Map<String, Object?>) return null;
  return (metric['max'] as num?)?.toDouble();
}

WebBrowserPerformanceMetrics? _readBrowserMetrics(Object? rawMetrics) {
  if (rawMetrics is Map<String, Object?>) {
    final metrics = WebBrowserPerformanceMetrics.fromJson(rawMetrics);
    return metrics.isEmpty ? null : metrics;
  }
  if (rawMetrics is Map) {
    final metrics = WebBrowserPerformanceMetrics.fromJson(
      rawMetrics.cast<String, Object?>(),
    );
    return metrics.isEmpty ? null : metrics;
  }
  return null;
}

Map<String, Object?>? _readRunEnvironment(Object? rawEnvironment) {
  if (rawEnvironment is Map<String, Object?>) return rawEnvironment;
  if (rawEnvironment is Map) return rawEnvironment.cast<String, Object?>();
  return null;
}

String _runEnvironmentSignature(Map<String, Object?>? environment) {
  if (environment == null) return 'missing-run-environment';
  final signature = <String, Object?>{
    for (final key in const [
      'chromeBrowser',
      'chromeUserAgent',
      'devtoolsProtocolVersion',
      'dartVersion',
      'operatingSystem',
      'operatingSystemVersion',
      'headless',
      'requestedFrames',
      'warmupFrames',
      'frameBudgetMs',
    ])
      key: environment[key],
    'requestedSteps':
        environment['requestedSteps'] ?? environment['requestedFrames'],
  };
  return jsonEncode(signature);
}

int? _readOptionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

final class _Options {
  const _Options({
    required this.help,
    required this.inputDir,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.minRuns,
    required this.steadySkipFrames,
    required this.gates,
    required this.thresholdsPath,
    required this.writeThresholdsPath,
    required this.thresholdHeadroomPercent,
    required this.thresholdMinHeadroomMs,
    required this.thresholdMinHeadroomPercent,
    required this.requireComparableRunEnvironment,
    required this.json,
    required this.strict,
  });

  final bool help;
  final String inputDir;
  final String? outputPath;
  final String? jsonOutputPath;
  final int minRuns;
  final int steadySkipFrames;
  final _GateOptions gates;
  final String? thresholdsPath;
  final String? writeThresholdsPath;
  final double thresholdHeadroomPercent;
  final double thresholdMinHeadroomMs;
  final double thresholdMinHeadroomPercent;
  final bool requireComparableRunEnvironment;
  final bool json;
  final bool strict;

  static _Options parse(List<String> args) {
    var help = false;
    var inputDir = '../../profiling/web';
    String? outputPath;
    String? jsonOutputPath;
    var minRuns = 1;
    var steadySkipFrames = 0;
    double? maxTotalFrameP95Ms;
    double? maxDomApplyP95Ms;
    double? maxSemanticApplyP95Ms;
    double? maxOverBudgetPercent;
    double? maxSteadyTotalFrameP95Ms;
    double? maxSteadySemanticApplyP95Ms;
    double? maxSteadyOverBudgetPercent;
    double? maxSemanticUncoveredCells;
    String? thresholdsPath;
    String? writeThresholdsPath;
    var thresholdHeadroomPercent = 20.0;
    var thresholdMinHeadroomMs = 1.0;
    var thresholdMinHeadroomPercent = 1.0;
    var requireComparableRunEnvironment = false;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--input=')) {
        inputDir = arg.substring('--input='.length);
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length).trim();
        if (jsonOutputPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--min-runs=')) {
        minRuns = _positiveInt(arg, '--min-runs=');
      } else if (arg.startsWith('--steady-skip-frames=')) {
        steadySkipFrames = _nonNegativeInt(arg, '--steady-skip-frames=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveDouble(arg, '--max-total-frame-p95-ms=');
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-steady-total-frame-p95-ms=')) {
        maxSteadyTotalFrameP95Ms = _positiveDouble(
          arg,
          '--max-steady-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-steady-semantic-apply-p95-ms=')) {
        maxSteadySemanticApplyP95Ms = _positiveDouble(
          arg,
          '--max-steady-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-steady-over-budget-percent=')) {
        maxSteadyOverBudgetPercent = _nonNegativeDouble(
          arg,
          '--max-steady-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--thresholds=')) {
        thresholdsPath = arg.substring('--thresholds='.length);
      } else if (arg.startsWith('--write-thresholds=')) {
        writeThresholdsPath = arg.substring('--write-thresholds='.length);
      } else if (arg.startsWith('--threshold-headroom-percent=')) {
        thresholdHeadroomPercent = _nonNegativeDouble(
          arg,
          '--threshold-headroom-percent=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-ms=')) {
        thresholdMinHeadroomMs = _nonNegativeDouble(
          arg,
          '--threshold-min-headroom-ms=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-percent=')) {
        thresholdMinHeadroomPercent = _nonNegativeDouble(
          arg,
          '--threshold-min-headroom-percent=',
        );
      } else if (arg == '--require-comparable-environment') {
        requireComparableRunEnvironment = true;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for web_frame_scoreboard: $arg');
        _printUsage();
        exit(2);
      }
    }

    return _Options(
      help: help,
      inputDir: inputDir,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      minRuns: minRuns,
      steadySkipFrames: steadySkipFrames,
      gates: _GateOptions(
        maxTotalFrameP95Ms: maxTotalFrameP95Ms,
        maxDomApplyP95Ms: maxDomApplyP95Ms,
        maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
        maxOverBudgetPercent: maxOverBudgetPercent,
        maxSteadyTotalFrameP95Ms: maxSteadyTotalFrameP95Ms,
        maxSteadySemanticApplyP95Ms: maxSteadySemanticApplyP95Ms,
        maxSteadyOverBudgetPercent: maxSteadyOverBudgetPercent,
        maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      ),
      thresholdsPath: thresholdsPath,
      writeThresholdsPath: writeThresholdsPath,
      thresholdHeadroomPercent: thresholdHeadroomPercent,
      thresholdMinHeadroomMs: thresholdMinHeadroomMs,
      thresholdMinHeadroomPercent: thresholdMinHeadroomPercent,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
      json: json,
      strict: strict,
    );
  }
}

final class _GateOptions {
  const _GateOptions({
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSteadyTotalFrameP95Ms,
    required this.maxSteadySemanticApplyP95Ms,
    required this.maxSteadyOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
  });

  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSteadyTotalFrameP95Ms;
  final double? maxSteadySemanticApplyP95Ms;
  final double? maxSteadyOverBudgetPercent;
  final double? maxSemanticUncoveredCells;

  bool get isEmpty =>
      maxTotalFrameP95Ms == null &&
      maxDomApplyP95Ms == null &&
      maxSemanticApplyP95Ms == null &&
      maxOverBudgetPercent == null &&
      maxSteadyTotalFrameP95Ms == null &&
      maxSteadySemanticApplyP95Ms == null &&
      maxSteadyOverBudgetPercent == null &&
      maxSemanticUncoveredCells == null;

  _GateOptions merge(_GateOptions override) {
    return _GateOptions(
      maxTotalFrameP95Ms: override.maxTotalFrameP95Ms ?? maxTotalFrameP95Ms,
      maxDomApplyP95Ms: override.maxDomApplyP95Ms ?? maxDomApplyP95Ms,
      maxSemanticApplyP95Ms:
          override.maxSemanticApplyP95Ms ?? maxSemanticApplyP95Ms,
      maxOverBudgetPercent:
          override.maxOverBudgetPercent ?? maxOverBudgetPercent,
      maxSteadyTotalFrameP95Ms:
          override.maxSteadyTotalFrameP95Ms ?? maxSteadyTotalFrameP95Ms,
      maxSteadySemanticApplyP95Ms:
          override.maxSteadySemanticApplyP95Ms ?? maxSteadySemanticApplyP95Ms,
      maxSteadyOverBudgetPercent:
          override.maxSteadyOverBudgetPercent ?? maxSteadyOverBudgetPercent,
      maxSemanticUncoveredCells:
          override.maxSemanticUncoveredCells ?? maxSemanticUncoveredCells,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (maxTotalFrameP95Ms != null) 'maxTotalFrameP95Ms': maxTotalFrameP95Ms,
    if (maxDomApplyP95Ms != null) 'maxDomApplyP95Ms': maxDomApplyP95Ms,
    if (maxSemanticApplyP95Ms != null)
      'maxSemanticApplyP95Ms': maxSemanticApplyP95Ms,
    if (maxOverBudgetPercent != null)
      'maxOverBudgetPercent': maxOverBudgetPercent,
    if (maxSteadyTotalFrameP95Ms != null)
      'maxSteadyTotalFrameP95Ms': maxSteadyTotalFrameP95Ms,
    if (maxSteadySemanticApplyP95Ms != null)
      'maxSteadySemanticApplyP95Ms': maxSteadySemanticApplyP95Ms,
    if (maxSteadyOverBudgetPercent != null)
      'maxSteadyOverBudgetPercent': maxSteadyOverBudgetPercent,
    if (maxSemanticUncoveredCells != null)
      'maxSemanticUncoveredCells': maxSemanticUncoveredCells,
  };

  static _GateOptions fromJson(Map<String, Object?> json, String context) {
    return _GateOptions(
      maxTotalFrameP95Ms: _optionalNonNegativeNumber(
        json,
        'maxTotalFrameP95Ms',
        context,
      ),
      maxDomApplyP95Ms: _optionalNonNegativeNumber(
        json,
        'maxDomApplyP95Ms',
        context,
      ),
      maxSemanticApplyP95Ms: _optionalNonNegativeNumber(
        json,
        'maxSemanticApplyP95Ms',
        context,
      ),
      maxOverBudgetPercent: _optionalNonNegativeNumber(
        json,
        'maxOverBudgetPercent',
        context,
      ),
      maxSteadyTotalFrameP95Ms: _optionalNonNegativeNumber(
        json,
        'maxSteadyTotalFrameP95Ms',
        context,
      ),
      maxSteadySemanticApplyP95Ms: _optionalNonNegativeNumber(
        json,
        'maxSteadySemanticApplyP95Ms',
        context,
      ),
      maxSteadyOverBudgetPercent: _optionalNonNegativeNumber(
        json,
        'maxSteadyOverBudgetPercent',
        context,
      ),
      maxSemanticUncoveredCells: _optionalNonNegativeNumber(
        json,
        'maxSemanticUncoveredCells',
        context,
      ),
    );
  }
}

final class _ThresholdPolicy {
  const _ThresholdPolicy({
    required this.defaults,
    required this.scenarios,
    required this.reviewState,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewContext,
    required this.fingerprint,
  });

  static const empty = _ThresholdPolicy(
    defaults: _GateOptions(
      maxTotalFrameP95Ms: null,
      maxDomApplyP95Ms: null,
      maxSemanticApplyP95Ms: null,
      maxOverBudgetPercent: null,
      maxSteadyTotalFrameP95Ms: null,
      maxSteadySemanticApplyP95Ms: null,
      maxSteadyOverBudgetPercent: null,
      maxSemanticUncoveredCells: null,
    ),
    scenarios: <String, _GateOptions>{},
    reviewState: null,
    reviewedBy: null,
    reviewedAt: null,
    reviewContext: null,
    fingerprint: null,
  );

  final _GateOptions defaults;
  final Map<String, _GateOptions> scenarios;
  final String? reviewState;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? reviewContext;
  final String? fingerprint;

  static _ThresholdPolicy load(String? path) {
    if (path == null) return empty;
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Threshold policy not found: $path');
      exit(2);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      stderr.writeln('Invalid threshold policy JSON: ${error.message}');
      exit(2);
    }
    if (decoded is! Map) {
      stderr.writeln('Threshold policy must be a JSON object.');
      exit(2);
    }
    final json = decoded.cast<String, Object?>();
    final kind = json['kind'];
    if (kind != null && kind != 'fleuryWebFrameThresholds') {
      stderr.writeln(
        'Threshold policy kind must be fleuryWebFrameThresholds, got `$kind`.',
      );
      exit(2);
    }
    final rawReviewState = json['reviewState'];
    final reviewState = rawReviewState == null
        ? null
        : rawReviewState.toString();
    final rawReviewedBy = json['reviewedBy'];
    final reviewedBy = rawReviewedBy == null ? null : rawReviewedBy.toString();
    final rawReviewedAt = json['reviewedAt'];
    final reviewedAt = rawReviewedAt == null ? null : rawReviewedAt.toString();
    final rawReviewContext = json['reviewContext'];
    final reviewContext = rawReviewContext == null
        ? null
        : rawReviewContext.toString();
    final defaults = _readGateOptions(json['defaults'], 'defaults');
    final scenarios = <String, _GateOptions>{};
    final rawScenarios = json['scenarios'];
    if (rawScenarios != null) {
      if (rawScenarios is! Map) {
        stderr.writeln('Threshold policy scenarios must be a JSON object.');
        exit(2);
      }
      for (final entry in rawScenarios.entries) {
        scenarios[entry.key.toString()] = _readGateOptions(
          entry.value,
          'scenarios.${entry.key}',
        );
      }
    }
    return _ThresholdPolicy(
      defaults: defaults,
      scenarios: Map.unmodifiable(scenarios),
      reviewState: reviewState,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt,
      reviewContext: reviewContext,
      fingerprint: _jsonFingerprint(json),
    );
  }

  _GateOptions gatesFor(String scenarioId, {required _GateOptions fallback}) {
    return fallback
        .merge(defaults)
        .merge(scenarios[scenarioId] ?? empty.defaults);
  }

  bool hasScenario(String scenarioId) => scenarios.containsKey(scenarioId);
}

String _jsonFingerprint(Map<String, Object?> json) {
  final canonicalJson = jsonEncode(_canonicalizeJson(json));
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(canonicalJson)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
}

Object? _canonicalizeJson(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final key in value.keys.toList()..sort())
        key: _canonicalizeJson(value[key]),
    };
  }
  if (value is Map) {
    final stringMap = {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
    return _canonicalizeJson(stringMap);
  }
  if (value is List) return [for (final item in value) _canonicalizeJson(item)];
  return value;
}

_GateOptions _readGateOptions(Object? raw, String context) {
  if (raw == null) return _ThresholdPolicy.empty.defaults;
  if (raw is Map<String, Object?>) return _GateOptions.fromJson(raw, context);
  if (raw is Map) {
    return _GateOptions.fromJson(raw.cast<String, Object?>(), context);
  }
  stderr.writeln('Threshold policy $context must be a JSON object.');
  exit(2);
}

final class _GateResult {
  const _GateResult({
    required this.id,
    required this.actual,
    required this.maximum,
    required this.unit,
  });

  final String id;
  final double actual;
  final double maximum;
  final String unit;

  bool get passed => actual <= maximum;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'actual': actual,
      'maximum': maximum,
      'unit': unit,
      'passed': passed,
    };
  }
}

int _positiveInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive integer.');
    exit(2);
  }
  return value;
}

int _nonNegativeInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative integer.');
    exit(2);
  }
  return value;
}

double _positiveDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive number.');
    exit(2);
  }
  return value;
}

double _nonNegativeDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative number.');
    exit(2);
  }
  return value;
}

double? _optionalNonNegativeNumber(
  Map<String, Object?> json,
  String key,
  String context,
) {
  final raw = json[key];
  if (raw == null) return null;
  if (raw is! num || raw < 0) {
    stderr.writeln('Threshold policy $context.$key must be non-negative.');
    exit(2);
  }
  return raw.toDouble();
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_frame_scoreboard.dart [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=DIR             Capture directory, default ../../profiling/web',
  );
  stdout.writeln('  --output=PATH           Markdown output path');
  stdout.writeln('  --json-output=PATH      JSON scoreboard output path');
  stdout.writeln(
    '  --min-runs=N            Required captures per scenario, default 1',
  );
  stdout.writeln(
    '  --steady-skip-frames=N  Skip first N captured frames for steady-state columns, default 0',
  );
  stdout.writeln('  --max-total-frame-p95-ms=N       Gate median total p95.');
  stdout.writeln(
    '  --max-dom-apply-p95-ms=N         Gate median DOM apply p95.',
  );
  stdout.writeln(
    '  --max-semantic-apply-p95-ms=N    Gate median semantic apply p95.',
  );
  stdout.writeln(
    '  --max-over-budget-percent=N      Gate median percent over budget.',
  );
  stdout.writeln(
    '  --max-steady-total-frame-p95-ms=N    Gate median steady-state total p95.',
  );
  stdout.writeln(
    '  --max-steady-semantic-apply-p95-ms=N Gate median steady-state semantic apply p95.',
  );
  stdout.writeln(
    '  --max-steady-over-budget-percent=N   Gate median steady-state percent over budget.',
  );
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N Gate max uncovered semantic cells.',
  );
  stdout.writeln(
    '  --thresholds=PATH       JSON threshold policy with defaults/scenarios.',
  );
  stdout.writeln(
    '  --write-thresholds=PATH Write a candidate JSON threshold policy from observed aggregates.',
  );
  stdout.writeln(
    '  --threshold-headroom-percent=N      Candidate threshold headroom, default 20.',
  );
  stdout.writeln(
    '  --threshold-min-headroom-ms=N       Candidate minimum timing headroom, default 1.',
  );
  stdout.writeln(
    '  --threshold-min-headroom-percent=N  Candidate minimum over-budget headroom, default 1.',
  );
  stdout.writeln(
    '  --require-comparable-environment Require one complete run environment signature per scenario.',
  );
  stdout.writeln(
    '  --strict                Exit non-zero if run count, gates, or required environment checks fail',
  );
  stdout.writeln(
    '  --json                  Print machine-readable scoreboard JSON',
  );
}
