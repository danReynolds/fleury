import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/instrumentation/web_host_instrumentation.dart';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }
  final inputPath = options.inputPath;
  if (inputPath == null) {
    stderr.writeln('web_frame_report requires --input=<path>.');
    _printUsage();
    exit(2);
  }

  final capture = _loadCapture(inputPath);
  final summary = WebInstrumentationSummary.fromFrames(
    capture.frames,
    frameBudgetMs: options.frameBudgetMs,
  );
  final steadyFrames = options.steadySkipFrames == 0
      ? capture.frames
      : capture.frames.skip(options.steadySkipFrames);
  final steadySummary = WebInstrumentationSummary.fromFrames(
    steadyFrames,
    frameBudgetMs: options.frameBudgetMs,
  );
  final gateReport = _GateReport.fromSummaries(
    summary: summary,
    steadySummary: steadySummary,
    options: options.gates,
  );
  final summaryJson = summary.toJson();
  summaryJson['steadyState'] = <String, Object?>{
    'skipInitialFrames': options.steadySkipFrames,
    ...steadySummary.toJson(),
  };
  final browserMetrics = capture.browserMetrics;
  if (browserMetrics != null && !browserMetrics.isEmpty) {
    summaryJson['browserMetrics'] = browserMetrics.toJson();
  }
  if (gateReport.hasGates) {
    summaryJson['strictPass'] = gateReport.strictPass;
    summaryJson['gates'] = [for (final gate in gateReport.gates) gate.toJson()];
  }
  final outputPath = options.outputPath;
  if (outputPath != null) {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    final content = outputPath.endsWith('.json')
        ? const JsonEncoder.withIndent('  ').convert(summaryJson)
        : _markdown(
            summary,
            browserMetrics: browserMetrics,
            gateReport: gateReport,
            inputPath: inputPath,
            steadySummary: steadySummary,
            steadySkipFrames: options.steadySkipFrames,
          );
    output.writeAsStringSync(content);
    stdout.writeln('wrote ${output.path}');
  }

  if (options.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(summaryJson));
  } else if (outputPath == null) {
    stdout.write(
      _markdown(
        summary,
        browserMetrics: browserMetrics,
        gateReport: gateReport,
        inputPath: inputPath,
        steadySummary: steadySummary,
        steadySkipFrames: options.steadySkipFrames,
      ),
    );
  }

  if (options.strict && !gateReport.strictPass) {
    exit(1);
  }
}

_LoadedWebCapture _loadCapture(String inputPath) {
  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('No such input file: $inputPath');
    exit(2);
  }
  final decoded = jsonDecode(input.readAsStringSync());
  WebBrowserPerformanceMetrics? browserMetrics;
  final rawFrames = switch (decoded) {
    List<Object?> list => list,
    Map<String, Object?> map when map['frames'] is List<Object?> => () {
      browserMetrics = _readBrowserMetrics(map['browserMetrics']);
      return map['frames']! as List<Object?>;
    }(),
    Map map when map['frames'] is List => () {
      browserMetrics = _readBrowserMetrics(map['browserMetrics']);
      return (map['frames']! as List).cast<Object?>();
    }(),
    _ => throw const FormatException(
      'Expected a frame array or an object with a `frames` array.',
    ),
  };
  return _LoadedWebCapture(
    frames: [
      for (final rawFrame in rawFrames)
        WebFrameInstrumentation.fromJson(
          (rawFrame as Map).cast<String, Object?>(),
        ),
    ],
    browserMetrics: browserMetrics,
  );
}

String _markdown(
  WebInstrumentationSummary summary, {
  required WebBrowserPerformanceMetrics? browserMetrics,
  required _GateReport gateReport,
  required String inputPath,
  required WebInstrumentationSummary steadySummary,
  required int steadySkipFrames,
}) {
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Frame Report')
    ..writeln()
    ..writeln('Generated from `$inputPath`.')
    ..writeln()
    ..writeln('| Frames | Budget | Over Budget | Dominant p95 Slice |')
    ..writeln('| --- | --- | --- | --- |')
    ..writeln(
      '| ${summary.frameCount} | ${_fmtMs(summary.frameBudgetMs)} | '
      '${summary.overBudgetFrameCount} '
      '(${_fmtPercent(summary.overBudgetPercent)}) | '
      '${summary.dominantP95Slice} |',
    );

  if (steadySkipFrames > 0) {
    buffer
      ..writeln()
      ..writeln('## Steady State')
      ..writeln()
      ..writeln('Skips the first `$steadySkipFrames` captured frame(s).')
      ..writeln()
      ..writeln('| Frames | Budget | Over Budget | Dominant p95 Slice |')
      ..writeln('| --- | --- | --- | --- |')
      ..writeln(
        '| ${steadySummary.frameCount} | '
        '${_fmtMs(steadySummary.frameBudgetMs)} | '
        '${steadySummary.overBudgetFrameCount} '
        '(${_fmtPercent(steadySummary.overBudgetPercent)}) | '
        '${steadySummary.dominantP95Slice} |',
      );
  }

  if (browserMetrics != null && !browserMetrics.isEmpty) {
    buffer
      ..writeln()
      ..writeln('## Browser Metrics')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('| --- | --- |');
    _writeBrowserMetricRows(buffer, browserMetrics);
  }

  buffer
    ..writeln()
    ..writeln('## Timings')
    ..writeln()
    ..writeln('| Slice | Total | p50 | p95 | Max |')
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final key in _timingOrder) {
    final metric = summary.timings[key];
    if (metric == null) continue;
    buffer.writeln(
      '| $key | ${_fmtMetricMs(metric.total, metric.sampleCount)} | '
      '${_fmtMetricMs(metric.p50, metric.sampleCount)} | '
      '${_fmtMetricMs(metric.p95, metric.sampleCount)} | '
      '${_fmtMetricMs(metric.max, metric.sampleCount)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Counts')
    ..writeln()
    ..writeln('| Counter | Total | p50 | p95 | Max |')
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final key in _countOrder) {
    final metric = summary.counts[key];
    if (metric == null) continue;
    buffer.writeln(
      '| $key | ${_fmtNumber(metric.total)} | ${_fmtNumber(metric.p50)} | '
      '${_fmtNumber(metric.p95)} | ${_fmtNumber(metric.max)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Cache Rates')
    ..writeln()
    ..writeln('| Cache | Hit Rate |')
    ..writeln('| --- | --- |');
  for (final entry in summary.cacheHitRates.entries) {
    buffer.writeln('| ${entry.key} | ${_fmtPercent(entry.value * 100)} |');
  }
  if (gateReport.hasGates) {
    buffer
      ..writeln()
      ..writeln('## Gates')
      ..writeln()
      ..writeln('| Gate | Actual | Limit | Status |')
      ..writeln('| --- | --- | --- | --- |');
    for (final gate in gateReport.gates) {
      buffer.writeln(
        '| ${gate.id} | ${_fmtGateValue(gate.actual, gate.unit)} | '
        '<= ${_fmtGateValue(gate.maximum, gate.unit)} | '
        '${gate.passed ? 'pass' : 'FAIL'} |',
      );
    }
  }
  return buffer.toString();
}

final class _LoadedWebCapture {
  const _LoadedWebCapture({required this.frames, required this.browserMetrics});

  final List<WebFrameInstrumentation> frames;
  final WebBrowserPerformanceMetrics? browserMetrics;
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

void _writeBrowserMetricRows(
  StringBuffer buffer,
  WebBrowserPerformanceMetrics metrics,
) {
  void writeRow(String label, String? value) {
    if (value == null) return;
    buffer.writeln('| $label | $value |');
  }

  writeRow('Layout duration', _fmtOptionalMs(metrics.layoutDurationMs));
  writeRow(
    'Style recalculation duration',
    _fmtOptionalMs(metrics.recalcStyleDurationMs),
  );
  writeRow('Script duration', _fmtOptionalMs(metrics.scriptDurationMs));
  writeRow('Task duration', _fmtOptionalMs(metrics.taskDurationMs));
  writeRow('JS heap used', _fmtOptionalBytes(metrics.jsHeapUsedBytes));
  writeRow('JS heap total', _fmtOptionalBytes(metrics.jsHeapTotalBytes));
  writeRow('DOM documents', _fmtOptionalInt(metrics.domDocumentCount));
  writeRow('DOM nodes', _fmtOptionalInt(metrics.domNodeCount));
  writeRow('JS event listeners', _fmtOptionalInt(metrics.jsEventListenerCount));
}

String _fmtMs(double value) => '${value.toStringAsFixed(2)} ms';
String _fmtMetricMs(double value, int sampleCount) =>
    sampleCount == 0 ? '-' : _fmtMs(value);
String _fmtPercent(double value) => '${value.toStringAsFixed(1)}%';

String? _fmtOptionalMs(double? value) => value == null ? null : _fmtMs(value);
String? _fmtOptionalBytes(double? value) =>
    value == null ? null : _fmtBytes(value);
String? _fmtOptionalInt(int? value) => value?.toString();

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

const _timingOrder = <String>[
  'runtimeRenderMs',
  'runtimeBufferPrepareMs',
  'runtimeBuildMs',
  'runtimeLayoutMs',
  'runtimePaintMs',
  'dirtyRowDiffMs',
  'spanBuildMs',
  'domApplyMs',
  'semanticTreeBuildMs',
  'semanticCoverageMs',
  'semanticDiffMs',
  'semanticPresenterMs',
  'semanticFocusSyncMs',
  'semanticApplyMs',
  'totalFrameMs',
];

const _countOrder = <String>[
  'dirtyRows',
  'dirtyCells',
  'spans',
  'domNodesCreated',
  'rowsReplaced',
  'styleCacheHits',
  'styleCacheMisses',
  'widthCacheHits',
  'widthCacheMisses',
  'metricsReads',
  'semanticNodes',
  'semanticAddedNodes',
  'semanticRemovedNodes',
  'semanticUpdatedNodes',
  'semanticDomCreatedElements',
  'semanticDomReusedElements',
  'semanticDomReplacedElements',
  'semanticDomAttributesSet',
  'semanticDomAttributesRemoved',
  'semanticFallbackNodes',
  'semanticUncoveredCells',
];

final class _Options {
  const _Options({
    required this.inputPath,
    required this.outputPath,
    required this.frameBudgetMs,
    required this.steadySkipFrames,
    required this.gates,
    required this.json,
    required this.strict,
    required this.help,
  });

  final String? inputPath;
  final String? outputPath;
  final double frameBudgetMs;
  final int steadySkipFrames;
  final _GateOptions gates;
  final bool json;
  final bool strict;
  final bool help;

  static _Options parse(List<String> args) {
    String? inputPath;
    String? outputPath;
    var frameBudgetMs = defaultWebFrameBudgetMs;
    var steadySkipFrames = 0;
    double? maxTotalFrameP95Ms;
    double? maxDomApplyP95Ms;
    double? maxSemanticApplyP95Ms;
    double? maxOverBudgetPercent;
    double? maxSemanticUncoveredCells;
    double? maxSteadyTotalFrameP95Ms;
    double? maxSteadySemanticApplyP95Ms;
    double? maxSteadyOverBudgetPercent;
    var json = false;
    var strict = false;
    var help = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length);
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--budget-ms=')) {
        frameBudgetMs = _positiveDoubleOption(arg, '--budget-ms=');
      } else if (arg.startsWith('--steady-skip-frames=')) {
        steadySkipFrames = _nonNegativeIntOption(arg, '--steady-skip-frames=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveDoubleOption(
          arg,
          '--max-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveDoubleOption(
          arg,
          '--max-dom-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveDoubleOption(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeDoubleOption(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeDoubleOption(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--max-steady-total-frame-p95-ms=')) {
        maxSteadyTotalFrameP95Ms = _positiveDoubleOption(
          arg,
          '--max-steady-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-steady-semantic-apply-p95-ms=')) {
        maxSteadySemanticApplyP95Ms = _positiveDoubleOption(
          arg,
          '--max-steady-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-steady-over-budget-percent=')) {
        maxSteadyOverBudgetPercent = _nonNegativeDoubleOption(
          arg,
          '--max-steady-over-budget-percent=',
        );
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for web_frame_report: $arg');
        _printUsage();
        exit(2);
      }
    }

    return _Options(
      inputPath: inputPath,
      outputPath: outputPath,
      frameBudgetMs: frameBudgetMs,
      steadySkipFrames: steadySkipFrames,
      gates: _GateOptions(
        maxTotalFrameP95Ms: maxTotalFrameP95Ms,
        maxDomApplyP95Ms: maxDomApplyP95Ms,
        maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
        maxOverBudgetPercent: maxOverBudgetPercent,
        maxSemanticUncoveredCells: maxSemanticUncoveredCells,
        maxSteadyTotalFrameP95Ms: maxSteadyTotalFrameP95Ms,
        maxSteadySemanticApplyP95Ms: maxSteadySemanticApplyP95Ms,
        maxSteadyOverBudgetPercent: maxSteadyOverBudgetPercent,
      ),
      json: json,
      strict: strict,
      help: help,
    );
  }
}

final class _GateOptions {
  const _GateOptions({
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
    required this.maxSteadyTotalFrameP95Ms,
    required this.maxSteadySemanticApplyP95Ms,
    required this.maxSteadyOverBudgetPercent,
  });

  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;
  final double? maxSteadyTotalFrameP95Ms;
  final double? maxSteadySemanticApplyP95Ms;
  final double? maxSteadyOverBudgetPercent;
}

final class _GateReport {
  const _GateReport(this.gates);

  factory _GateReport.fromSummaries({
    required WebInstrumentationSummary summary,
    required WebInstrumentationSummary steadySummary,
    required _GateOptions options,
  }) {
    return _GateReport([
      if (options.maxTotalFrameP95Ms case final limit?)
        _GateResult(
          id: 'totalFrameP95Ms',
          actual: summary.timings['totalFrameMs']!.p95,
          maximum: limit,
          unit: 'ms',
        ),
      if (options.maxDomApplyP95Ms case final limit?)
        _GateResult(
          id: 'domApplyP95Ms',
          actual: summary.timings['domApplyMs']!.p95,
          maximum: limit,
          unit: 'ms',
        ),
      if (options.maxSemanticApplyP95Ms case final limit?)
        _GateResult(
          id: 'semanticApplyP95Ms',
          actual: summary.timings['semanticApplyMs']!.p95,
          maximum: limit,
          unit: 'ms',
        ),
      if (options.maxOverBudgetPercent case final limit?)
        _GateResult(
          id: 'overBudgetPercent',
          actual: summary.overBudgetPercent,
          maximum: limit,
          unit: '%',
        ),
      if (options.maxSemanticUncoveredCells case final limit?)
        _GateResult(
          id: 'semanticUncoveredCellsMax',
          actual: summary.counts['semanticUncoveredCells']!.max,
          maximum: limit,
          unit: 'count',
        ),
      if (options.maxSteadyTotalFrameP95Ms case final limit?)
        _GateResult(
          id: 'steadyTotalFrameP95Ms',
          actual: steadySummary.timings['totalFrameMs']!.p95,
          maximum: limit,
          unit: 'ms',
        ),
      if (options.maxSteadySemanticApplyP95Ms case final limit?)
        _GateResult(
          id: 'steadySemanticApplyP95Ms',
          actual: steadySummary.timings['semanticApplyMs']!.p95,
          maximum: limit,
          unit: 'ms',
        ),
      if (options.maxSteadyOverBudgetPercent case final limit?)
        _GateResult(
          id: 'steadyOverBudgetPercent',
          actual: steadySummary.overBudgetPercent,
          maximum: limit,
          unit: '%',
        ),
    ]);
  }

  final List<_GateResult> gates;

  bool get hasGates => gates.isNotEmpty;

  bool get strictPass => gates.every((gate) => gate.passed);
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

double _positiveDoubleOption(String arg, String prefix) {
  final parsed = double.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed <= 0) {
    stderr.writeln('$prefix requires a positive number.');
    exit(2);
  }
  return parsed;
}

int _nonNegativeIntOption(String arg, String prefix) {
  final parsed = int.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed < 0) {
    stderr.writeln('$prefix requires a non-negative integer.');
    exit(2);
  }
  return parsed;
}

double _nonNegativeDoubleOption(String arg, String prefix) {
  final parsed = double.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed < 0) {
    stderr.writeln('$prefix requires a non-negative number.');
    exit(2);
  }
  return parsed;
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/web_frame_report.dart --input=<frames.json> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --output=PATH           Write Markdown, or JSON for .json paths.',
  );
  stdout.writeln(
    '  --budget-ms=N          Total-frame budget, default $defaultWebFrameBudgetMs.',
  );
  stdout.writeln(
    '  --steady-skip-frames=N Skip first N captured frames for steady-state summary.',
  );
  stdout.writeln('  --max-total-frame-p95-ms=N       Gate total frame p95.');
  stdout.writeln('  --max-dom-apply-p95-ms=N         Gate DOM apply p95.');
  stdout.writeln('  --max-semantic-apply-p95-ms=N    Gate semantic apply p95.');
  stdout.writeln(
    '  --max-over-budget-percent=N      Gate percent of frames over budget.',
  );
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N Gate max uncovered semantic cells.',
  );
  stdout.writeln(
    '  --max-steady-total-frame-p95-ms=N    Gate steady-state total frame p95.',
  );
  stdout.writeln(
    '  --max-steady-semantic-apply-p95-ms=N Gate steady-state semantic apply p95.',
  );
  stdout.writeln(
    '  --max-steady-over-budget-percent=N   Gate steady-state over-budget percent.',
  );
  stdout.writeln('  --strict                Exit non-zero if any gate fails.');
  stdout.writeln(
    '  --json                  Print machine-readable summary JSON.',
  );
}
