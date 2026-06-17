@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_frame_report_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('web frame report exposes dirty row diff timing', () async {
    final capturePath = '${tempDir.path}/capture.json';
    _writeCapture(
      capturePath,
      frames: [
        _webFrame(
          totalFrameMicros: 10000,
          dirtyRowDiffMicros: 800,
          domApplyMicros: 500,
        ),
        _webFrame(
          totalFrameMicros: 14000,
          dirtyRowDiffMicros: 5000,
          domApplyMicros: 900,
        ),
      ],
    );

    final jsonResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_report.dart',
      '--input=$capturePath',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(jsonResult.exitCode, 0, reason: jsonResult.stderr.toString());
    final json =
        jsonDecode(jsonResult.stdout.toString()) as Map<String, Object?>;
    expect(json['kind'], 'fleuryWebFrameSummary');
    expect(json['dominantP95Slice'], 'dirtyRowDiffMs');
    final timings = json['timings'] as Map<String, Object?>;
    final dirtyRowDiff = timings['dirtyRowDiffMs'] as Map<String, Object?>;
    expect(dirtyRowDiff['p95'], 5.0);
    expect(dirtyRowDiff['max'], 5.0);

    final markdownPath = '${tempDir.path}/report.md';
    final markdownResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_report.dart',
      '--input=$capturePath',
      '--output=$markdownPath',
    ], workingDirectory: Directory.current.path);

    expect(
      markdownResult.exitCode,
      0,
      reason: markdownResult.stderr.toString(),
    );
    final markdown = File(markdownPath).readAsStringSync();
    expect(markdown, contains('dirtyRowDiffMs'));
    expect(markdown, contains('dirtyRowDiffMs | 5.80 ms | 0.80 ms | 5.00 ms'));
  });

  test(
    'web frame report accepts old captures without row diff timing',
    () async {
      final capturePath = '${tempDir.path}/old-capture.json';
      _writeCapture(
        capturePath,
        frames: [
          _webFrame(totalFrameMicros: 10000, domApplyMicros: 500),
        ].map((frame) => frame..remove('dirtyRowDiffMicros')).toList(),
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_report.dart',
        '--input=$capturePath',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final json = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final timings = json['timings'] as Map<String, Object?>;
      final dirtyRowDiff = timings['dirtyRowDiffMs'] as Map<String, Object?>;
      expect(dirtyRowDiff['p95'], 0.0);
      final runtimeBuild = timings['runtimeBuildMs'] as Map<String, Object?>;
      expect(runtimeBuild['sampleCount'], 0);

      final markdownPath = '${tempDir.path}/old-report.md';
      final markdownResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_report.dart',
        '--input=$capturePath',
        '--output=$markdownPath',
      ], workingDirectory: Directory.current.path);

      expect(
        markdownResult.exitCode,
        0,
        reason: markdownResult.stderr.toString(),
      );
      final markdown = File(markdownPath).readAsStringSync();
      expect(markdown, contains('| runtimeBufferPrepareMs | - | - | - | - |'));
      expect(markdown, contains('| runtimeBuildMs | - | - | - | - |'));
    },
  );

  test('web frame report gates semantic apply p95 independently', () async {
    final capturePath = '${tempDir.path}/semantic-apply-capture.json';
    _writeCapture(
      capturePath,
      frames: [
        _webFrame(totalFrameMicros: 10000, domApplyMicros: 500),
        _webFrame(totalFrameMicros: 11000, domApplyMicros: 600),
      ],
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_report.dart',
      '--input=$capturePath',
      '--max-semantic-apply-p95-ms=0.5',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final json = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(json['strictPass'], isFalse);
    expect(
      json['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'semanticApplyP95Ms')
            .having((gate) => gate['actual'], 'actual', 0.6)
            .having((gate) => gate['maximum'], 'maximum', 0.5)
            .having((gate) => gate['passed'], 'passed', isFalse),
      ),
    );
  });

  test('web frame report exposes and gates steady-state window', () async {
    final capturePath = '${tempDir.path}/steady-capture.json';
    _writeCapture(
      capturePath,
      frames: [
        _webFrame(totalFrameMicros: 30000, domApplyMicros: 500),
        _webFrame(totalFrameMicros: 10000, domApplyMicros: 500),
        _webFrame(totalFrameMicros: 12000, domApplyMicros: 500),
      ],
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_report.dart',
      '--input=$capturePath',
      '--steady-skip-frames=1',
      '--max-over-budget-percent=0',
      '--max-steady-over-budget-percent=0',
      '--max-steady-total-frame-p95-ms=12',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final json = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final steadyState = json['steadyState'] as Map<String, Object?>;
    expect(steadyState['skipInitialFrames'], 1);
    expect(steadyState['frameCount'], 2);
    expect(steadyState['overBudgetFrameCount'], 0);
    expect(
      json['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'overBudgetPercent')
            .having((gate) => gate['actual'], 'actual', closeTo(33.333, 0.01))
            .having((gate) => gate['passed'], 'passed', isFalse),
      ),
    );
    expect(
      json['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'steadyOverBudgetPercent')
            .having((gate) => gate['actual'], 'actual', 0.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );
    expect(
      json['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'steadyTotalFrameP95Ms')
            .having((gate) => gate['actual'], 'actual', 12.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );

    final markdownResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_report.dart',
      '--input=$capturePath',
      '--steady-skip-frames=1',
    ], workingDirectory: Directory.current.path);

    expect(
      markdownResult.exitCode,
      0,
      reason: markdownResult.stderr.toString(),
    );
    expect(markdownResult.stdout, contains('## Steady State'));
    expect(
      markdownResult.stdout,
      contains('Skips the first `1` captured frame(s).'),
    );
  });
}

void _writeCapture(String path, {required List<Map<String, Object?>> frames}) {
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'kind': 'fleuryWebFrameCapture', 'frameBudgetMs': 16.67, 'frames': frames})}\n',
  );
}

Map<String, Object?> _webFrame({
  required int totalFrameMicros,
  required int domApplyMicros,
  int dirtyRowDiffMicros = 0,
  int semanticApplyMicros = 600,
}) {
  return <String, Object?>{
    'reason': 'benchmark',
    'coalescedReasons': ['benchmark'],
    'viewport': {'cols': 80, 'rows': 24},
    'damageSource': 'paintDamage',
    'fullRepaint': false,
    'metricsChanged': false,
    'dirtyRowCount': 1,
    'dirtyCellEstimate': 80,
    'spanCount': 4,
    'domNodesCreated': 4,
    'rowsReplaced': 1,
    'styleCacheHits': 4,
    'styleCacheMisses': 0,
    'widthCacheHits': 0,
    'widthCacheMisses': 0,
    'metricsReadCount': 1,
    'semanticNodeCount': 2,
    'semanticAddedNodeCount': 0,
    'semanticRemovedNodeCount': 0,
    'semanticUpdatedNodeCount': 1,
    'semanticFallbackNodeCount': 0,
    'semanticUncoveredCellCount': 0,
    'runtimeRenderMicros': 1000,
    'dirtyRowDiffMicros': dirtyRowDiffMicros,
    'spanBuildMicros': 700,
    'domApplyMicros': domApplyMicros,
    'semanticApplyMicros': semanticApplyMicros,
    'totalFrameMicros': totalFrameMicros,
  };
}
