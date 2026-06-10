import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/benchmark/web_benchmark_scenarios.dart';
import 'package:fleury_web/src/instrumentation/web_host_instrumentation.dart';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final runs = _loadRuns(options.inputDir);
  final audit = _buildAudit(
    runs,
    inputDir: options.inputDir,
    gates: options.gates,
  );
  final auditJson = const JsonEncoder.withIndent('  ').convert(audit);
  if (options.jsonOutputPath != null) {
    final output = File(options.jsonOutputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$auditJson\n');
  }

  if (options.json) {
    stdout.writeln(auditJson);
  }

  final outputPath = options.outputPath;
  final markdown = _markdown(audit, inputDir: options.inputDir);
  if (outputPath == null) {
    if (!options.json) stdout.write(markdown);
  } else {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(markdown);
    stdout.writeln('wrote ${output.path}');
  }

  if (options.strict && audit['strictPass'] != true) exit(1);
}

Map<String, Object?> _buildAudit(
  List<_SemanticCoverageRun> runs, {
  required String inputDir,
  required _GateOptions gates,
}) {
  final byScenario = <String, List<_SemanticCoverageRun>>{};
  for (final run in runs) {
    (byScenario[run.scenarioId] ??= <_SemanticCoverageRun>[]).add(run);
  }
  final summaries = [
    for (final entry in byScenario.entries)
      _ScenarioCoverageAggregate.from(
        entry.key,
        entry.value,
        gates: gates,
      ).toJson(),
  ]..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
  final gateResults = _gateResults(
    fallbackFramePercent: _fallbackFramePercent(runs),
    fallbackViewportCellPercent: _fallbackViewportCellPercent(runs),
    maxFallbackCellsInFrame: _maxFallbackCellsInFrame(runs).toDouble(),
    gates: gates,
  );
  final strictPass =
      gateResults.every((gate) => gate.passed) &&
      summaries.every((scenario) => scenario['strictPass'] == true);

  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebSemanticCoverageAudit',
    'inputDir': inputDir,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'scenarioCount': summaries.length,
    'captureCount': runs.length,
    'frameCount': runs.fold<int>(0, (sum, run) => sum + run.frameCount),
    'fallbackFrameCount': runs.fold<int>(
      0,
      (sum, run) => sum + run.fallbackFrameCount,
    ),
    'fallbackCellCount': runs.fold<int>(
      0,
      (sum, run) => sum + run.fallbackCellCount,
    ),
    'fallbackNodeCount': runs.fold<int>(
      0,
      (sum, run) => sum + run.fallbackNodeCount,
    ),
    'fallbackFramePercent': _fallbackFramePercent(runs),
    'fallbackViewportCellPercent': _fallbackViewportCellPercent(runs),
    'maxFallbackCellsInFrame': _maxFallbackCellsInFrame(runs),
    'maxFallbackNodesInFrame': _maxFallbackNodesInFrame(runs),
    'topFallbackCaptures': _topFallbackRuns(runs),
    'gates': [for (final gate in gateResults) gate.toJson()],
    'strictPass': strictPass,
    'scenarios': summaries,
  };
}

String _markdown(Map<String, Object?> audit, {required String inputDir}) {
  final scenarios = (audit['scenarios'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Semantic Coverage Audit')
    ..writeln()
    ..writeln('Generated from `$inputDir` at `${audit['generatedAt']}`.')
    ..writeln()
    ..writeln(
      'Fallback cells are visible painted text cells that were not covered by '
      'richer geometry-bearing semantic nodes before the text fallback bridge '
      'added low-priority semantic text nodes. Zero fallback cells means the '
      'audited captures did not rely on fallback text for readable content.',
    )
    ..writeln()
    ..writeln(
      '| Scenario | Captures | Frames | Fallback Frames | Fallback Cells | Viewport % | Max Cells/Frame | Max Nodes/Frame | Gates | Latest Capture |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');

  if (scenarios.isEmpty) {
    buffer.writeln('| - | 0 | 0 | 0 | 0 | 0.0% | 0 | 0 | - | - |');
    return buffer.toString();
  }

  for (final scenario in scenarios) {
    buffer.writeln(
      '| ${scenario['id']} | '
      '${scenario['captureCount']} | '
      '${scenario['frameCount']} | '
      '${scenario['fallbackFrameCount']} '
      '(${_fmtPercent((scenario['fallbackFramePercent'] as num).toDouble())}) | '
      '${scenario['fallbackCellCount']} | '
      '${_fmtPercent((scenario['fallbackViewportCellPercent'] as num).toDouble())} | '
      '${scenario['maxFallbackCellsInFrame']} | '
      '${scenario['maxFallbackNodesInFrame']} | '
      '${_gateFailures(scenario)} | '
      '${scenario['latestCapture']} |',
    );
  }

  final topFallbackCaptures = (audit['topFallbackCaptures'] as List<Object?>)
      .cast<Map<String, Object?>>();
  buffer
    ..writeln()
    ..writeln('## Top Fallback Captures')
    ..writeln();
  if (topFallbackCaptures.isEmpty) {
    buffer.writeln('No fallback reliance was observed in these captures.');
  } else {
    buffer
      ..writeln(
        '| Scenario | Capture | Fallback Frames | Fallback Cells | Fallback Nodes | Viewport % | Max Cells/Frame |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final capture in topFallbackCaptures) {
      buffer.writeln(
        '| ${capture['scenarioId']} | '
        '${capture['file']} | '
        '${capture['fallbackFrameCount']} '
        '(${_fmtPercent((capture['fallbackFramePercent'] as num).toDouble())}) | '
        '${capture['fallbackCellCount']} | '
        '${capture['fallbackNodeCount']} | '
        '${_fmtPercent((capture['fallbackViewportCellPercent'] as num).toDouble())} | '
        '${capture['maxFallbackCellsInFrame']} |',
      );
    }
  }

  return buffer.toString();
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

List<_SemanticCoverageRun> _loadRuns(String inputDir) {
  final root = Directory(inputDir);
  if (!root.existsSync()) return const [];
  final runs = <_SemanticCoverageRun>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final run = _tryLoadRun(entity);
    if (run != null) runs.add(run);
  }
  runs.sort((a, b) => a.path.compareTo(b.path));
  return runs;
}

_SemanticCoverageRun? _tryLoadRun(File file) {
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

  final parsedFrames = [
    for (final rawFrame in frames)
      WebFrameInstrumentation.fromJson(
        (rawFrame as Map).cast<String, Object?>(),
      ),
  ];
  return _SemanticCoverageRun(
    path: file.path,
    scenarioId: _scenarioIdFor(capture, file.path),
    capturedAt: capture['capturedAt']?.toString(),
    frames: List.unmodifiable(parsedFrames),
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

final class _SemanticCoverageRun {
  const _SemanticCoverageRun({
    required this.path,
    required this.scenarioId,
    required this.capturedAt,
    required this.frames,
  });

  final String path;
  final String scenarioId;
  final String? capturedAt;
  final List<WebFrameInstrumentation> frames;

  int get frameCount => frames.length;
  int get viewportCellCount => frames.fold<int>(
    0,
    (sum, frame) => sum + frame.viewportSize.cols * frame.viewportSize.rows,
  );
  int get fallbackFrameCount => frames
      .where(
        (frame) =>
            frame.semanticUncoveredCellCount > 0 ||
            frame.semanticFallbackNodeCount > 0,
      )
      .length;
  int get fallbackCellCount => frames.fold<int>(
    0,
    (sum, frame) => sum + frame.semanticUncoveredCellCount,
  );
  int get fallbackNodeCount => frames.fold<int>(
    0,
    (sum, frame) => sum + frame.semanticFallbackNodeCount,
  );
  double get fallbackFramePercent => _percent(fallbackFrameCount, frameCount);
  double get fallbackViewportCellPercent =>
      _percent(fallbackCellCount, viewportCellCount);
  int get maxFallbackCellsInFrame => frames.fold<int>(
    0,
    (max, frame) => frame.semanticUncoveredCellCount > max
        ? frame.semanticUncoveredCellCount
        : max,
  );
  int get maxFallbackNodesInFrame => frames.fold<int>(
    0,
    (max, frame) => frame.semanticFallbackNodeCount > max
        ? frame.semanticFallbackNodeCount
        : max,
  );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'file': _fileName(path),
      'scenarioId': scenarioId,
      'capturedAt': capturedAt,
      'frameCount': frameCount,
      'viewportCellCount': viewportCellCount,
      'fallbackFrameCount': fallbackFrameCount,
      'fallbackCellCount': fallbackCellCount,
      'fallbackNodeCount': fallbackNodeCount,
      'fallbackFramePercent': fallbackFramePercent,
      'fallbackViewportCellPercent': fallbackViewportCellPercent,
      'maxFallbackCellsInFrame': maxFallbackCellsInFrame,
      'maxFallbackNodesInFrame': maxFallbackNodesInFrame,
    };
  }
}

final class _ScenarioCoverageAggregate {
  _ScenarioCoverageAggregate({
    required this.id,
    required this.label,
    required this.runs,
    required this.gates,
  });

  factory _ScenarioCoverageAggregate.from(
    String id,
    List<_SemanticCoverageRun> runs, {
    required _GateOptions gates,
  }) {
    final scenario = webBenchmarkScenarioById(id);
    return _ScenarioCoverageAggregate(
      id: id,
      label: scenario?.label ?? id,
      runs: List.unmodifiable(runs),
      gates: gates,
    );
  }

  final String id;
  final String label;
  final List<_SemanticCoverageRun> runs;
  final _GateOptions gates;

  Map<String, Object?> toJson() {
    final latest = _latestRun;
    final frameCount = runs.fold<int>(0, (sum, run) => sum + run.frameCount);
    final viewportCellCount = runs.fold<int>(
      0,
      (sum, run) => sum + run.viewportCellCount,
    );
    final fallbackFrameCount = runs.fold<int>(
      0,
      (sum, run) => sum + run.fallbackFrameCount,
    );
    final fallbackCellCount = runs.fold<int>(
      0,
      (sum, run) => sum + run.fallbackCellCount,
    );
    final fallbackNodeCount = runs.fold<int>(
      0,
      (sum, run) => sum + run.fallbackNodeCount,
    );
    final fallbackFramePercent = _percent(fallbackFrameCount, frameCount);
    final fallbackViewportCellPercent = _percent(
      fallbackCellCount,
      viewportCellCount,
    );
    final maxFallbackCellsInFrame = _maxFallbackCellsInFrame(runs);
    final maxFallbackNodesInFrame = _maxFallbackNodesInFrame(runs);
    final gateResults = _gateResults(
      fallbackFramePercent: fallbackFramePercent,
      fallbackViewportCellPercent: fallbackViewportCellPercent,
      maxFallbackCellsInFrame: maxFallbackCellsInFrame.toDouble(),
      gates: gates,
    );
    return <String, Object?>{
      'id': id,
      'label': label,
      'captureCount': runs.length,
      'frameCount': frameCount,
      'viewportCellCount': viewportCellCount,
      'fallbackFrameCount': fallbackFrameCount,
      'fallbackCellCount': fallbackCellCount,
      'fallbackNodeCount': fallbackNodeCount,
      'fallbackFramePercent': fallbackFramePercent,
      'fallbackViewportCellPercent': fallbackViewportCellPercent,
      'maxFallbackCellsInFrame': maxFallbackCellsInFrame,
      'maxFallbackNodesInFrame': maxFallbackNodesInFrame,
      'latestCapture': latest == null ? null : _fileName(latest.path),
      'latestCapturedAt': latest?.capturedAt,
      'topFallbackCaptures': _topFallbackRuns(runs),
      'gates': [for (final gate in gateResults) gate.toJson()],
      'strictPass': gateResults.every((gate) => gate.passed),
      'captures': [for (final run in runs) run.toJson()],
    };
  }

  _SemanticCoverageRun? get _latestRun {
    if (runs.isEmpty) return null;
    return runs.reduce((a, b) {
      final aTime = a.capturedAt ?? '';
      final bTime = b.capturedAt ?? '';
      return aTime.compareTo(bTime) >= 0 ? a : b;
    });
  }
}

List<_GateResult> _gateResults({
  required double fallbackFramePercent,
  required double fallbackViewportCellPercent,
  required double maxFallbackCellsInFrame,
  required _GateOptions gates,
}) {
  return [
    if (gates.maxFallbackCells case final limit?)
      _GateResult(
        id: 'maxFallbackCellsInFrame',
        actual: maxFallbackCellsInFrame,
        maximum: limit.toDouble(),
        unit: 'count',
      ),
    if (gates.maxFallbackFramePercent case final limit?)
      _GateResult(
        id: 'fallbackFramePercent',
        actual: fallbackFramePercent,
        maximum: limit,
        unit: '%',
      ),
    if (gates.maxFallbackViewportPercent case final limit?)
      _GateResult(
        id: 'fallbackViewportCellPercent',
        actual: fallbackViewportCellPercent,
        maximum: limit,
        unit: '%',
      ),
  ];
}

double _fallbackFramePercent(List<_SemanticCoverageRun> runs) {
  final frameCount = runs.fold<int>(0, (sum, run) => sum + run.frameCount);
  final fallbackFrameCount = runs.fold<int>(
    0,
    (sum, run) => sum + run.fallbackFrameCount,
  );
  return _percent(fallbackFrameCount, frameCount);
}

double _fallbackViewportCellPercent(List<_SemanticCoverageRun> runs) {
  final viewportCellCount = runs.fold<int>(
    0,
    (sum, run) => sum + run.viewportCellCount,
  );
  final fallbackCellCount = runs.fold<int>(
    0,
    (sum, run) => sum + run.fallbackCellCount,
  );
  return _percent(fallbackCellCount, viewportCellCount);
}

int _maxFallbackCellsInFrame(List<_SemanticCoverageRun> runs) {
  return runs.fold<int>(
    0,
    (max, run) =>
        run.maxFallbackCellsInFrame > max ? run.maxFallbackCellsInFrame : max,
  );
}

int _maxFallbackNodesInFrame(List<_SemanticCoverageRun> runs) {
  return runs.fold<int>(
    0,
    (max, run) =>
        run.maxFallbackNodesInFrame > max ? run.maxFallbackNodesInFrame : max,
  );
}

List<Map<String, Object?>> _topFallbackRuns(
  List<_SemanticCoverageRun> runs, {
  int limit = 5,
}) {
  final top =
      runs
          .where(
            (run) =>
                run.fallbackFrameCount > 0 ||
                run.fallbackCellCount > 0 ||
                run.fallbackNodeCount > 0,
          )
          .toList()
        ..sort((a, b) {
          final byCells = b.fallbackCellCount.compareTo(a.fallbackCellCount);
          if (byCells != 0) return byCells;
          final byNodes = b.fallbackNodeCount.compareTo(a.fallbackNodeCount);
          if (byNodes != 0) return byNodes;
          final byFrames = b.fallbackFrameCount.compareTo(a.fallbackFrameCount);
          if (byFrames != 0) return byFrames;
          final byViewport = b.fallbackViewportCellPercent.compareTo(
            a.fallbackViewportCellPercent,
          );
          if (byViewport != 0) return byViewport;
          return a.path.compareTo(b.path);
        });
  return [for (final run in top.take(limit)) run.toJson()];
}

double _percent(int numerator, int denominator) {
  if (denominator == 0) return 0;
  return numerator * 100 / denominator;
}

String _fileName(String path) {
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

String _fmtPercent(double value) => '${value.toStringAsFixed(1)}%';

String _fmtGateValue(double value, String unit) {
  return switch (unit) {
    '%' => _fmtPercent(value),
    _ =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1),
  };
}

final class _Options {
  const _Options({
    required this.help,
    required this.inputDir,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.gates,
    required this.json,
    required this.strict,
  });

  final bool help;
  final String inputDir;
  final String? outputPath;
  final String? jsonOutputPath;
  final _GateOptions gates;
  final bool json;
  final bool strict;

  static _Options parse(List<String> args) {
    var help = false;
    var inputDir = '../../profiling/web';
    String? outputPath;
    String? jsonOutputPath;
    int? maxFallbackCells;
    double? maxFallbackFramePercent;
    double? maxFallbackViewportPercent;
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
      } else if (arg.startsWith('--max-fallback-cells=')) {
        maxFallbackCells = _nonNegativeInt(arg, '--max-fallback-cells=');
      } else if (arg.startsWith('--max-fallback-frame-percent=')) {
        maxFallbackFramePercent = _nonNegativeDouble(
          arg,
          '--max-fallback-frame-percent=',
        );
      } else if (arg.startsWith('--max-fallback-viewport-percent=')) {
        maxFallbackViewportPercent = _nonNegativeDouble(
          arg,
          '--max-fallback-viewport-percent=',
        );
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for web_semantic_coverage_audit: $arg');
        _printUsage();
        exit(2);
      }
    }

    return _Options(
      help: help,
      inputDir: inputDir,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      gates: _GateOptions(
        maxFallbackCells: maxFallbackCells,
        maxFallbackFramePercent: maxFallbackFramePercent,
        maxFallbackViewportPercent: maxFallbackViewportPercent,
      ),
      json: json,
      strict: strict,
    );
  }
}

final class _GateOptions {
  const _GateOptions({
    required this.maxFallbackCells,
    required this.maxFallbackFramePercent,
    required this.maxFallbackViewportPercent,
  });

  final int? maxFallbackCells;
  final double? maxFallbackFramePercent;
  final double? maxFallbackViewportPercent;
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

int _nonNegativeInt(String arg, String prefix) {
  final parsed = int.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed < 0) {
    stderr.writeln('$prefix requires a non-negative integer.');
    exit(2);
  }
  return parsed;
}

double _nonNegativeDouble(String arg, String prefix) {
  final parsed = double.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed < 0) {
    stderr.writeln('$prefix requires a non-negative number.');
    exit(2);
  }
  return parsed;
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/web_semantic_coverage_audit.dart [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=DIR                         Capture directory, default ../../profiling/web.',
  );
  stdout.writeln('  --output=PATH                       Markdown output path.');
  stdout.writeln(
    '  --json-output=PATH                  JSON audit output path.',
  );
  stdout.writeln(
    '  --max-fallback-cells=N              Gate max fallback cells in any frame.',
  );
  stdout.writeln(
    '  --max-fallback-frame-percent=N      Gate percent of frames needing fallback.',
  );
  stdout.writeln(
    '  --max-fallback-viewport-percent=N   Gate fallback cells as percent of viewport cells.',
  );
  stdout.writeln(
    '  --strict                            Exit non-zero if any gate fails.',
  );
  stdout.writeln(
    '  --json                              Print machine-readable audit JSON.',
  );
}
