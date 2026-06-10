@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_frame_scoreboard_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('web frame scoreboard aggregates capture files', () async {
    _writeCapture(
      '${tempDir.path}/normal-a.json',
      scenarioId: 'normal-80x24',
      capturedAt: '2026-06-08T01:00:00.000000Z',
      requestedSteps: 1,
      browserMetrics: {
        'layoutDurationMs': 1.0,
        'recalcStyleDurationMs': 2.0,
        'scriptDurationMs': 5.0,
        'taskDurationMs': 8.0,
        'jsHeapUsedBytes': 1048576,
        'jsHeapTotalBytes': 2097152,
        'domDocumentCount': 1,
        'domNodeCount': 100,
        'jsEventListenerCount': 12,
      },
      runEnvironment: _runEnvironment(),
      frames: [
        _webFrame(
          totalFrameMicros: 10000,
          dirtyRowDiffMicros: 400,
          domApplyMicros: 3000,
        ),
        _webFrame(
          totalFrameMicros: 20000,
          dirtyRowDiffMicros: 800,
          domApplyMicros: 5000,
        ),
      ],
    );
    _writeCapture(
      '${tempDir.path}/normal-b.json',
      scenarioId: 'normal-80x24',
      capturedAt: '2026-06-08T01:05:00.000000Z',
      requestedSteps: 1,
      browserMetrics: {
        'layoutDurationMs': 3.0,
        'recalcStyleDurationMs': 4.0,
        'scriptDurationMs': 7.0,
        'taskDurationMs': 10.0,
        'jsHeapUsedBytes': 2097152,
        'jsHeapTotalBytes': 4194304,
        'domDocumentCount': 1,
        'domNodeCount': 140,
        'jsEventListenerCount': 18,
      },
      runEnvironment: _runEnvironment(),
      frames: [
        _webFrame(
          totalFrameMicros: 14000,
          dirtyRowDiffMicros: 600,
          domApplyMicros: 4000,
        ),
        _webFrame(
          totalFrameMicros: 18000,
          dirtyRowDiffMicros: 1200,
          domApplyMicros: 6000,
        ),
      ],
    );
    File('${tempDir.path}/not-a-capture.json').writeAsStringSync('{}');

    final jsonOutputPath = '${tempDir.path}/scoreboard.json';
    final jsonResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--min-runs=2',
      '--json-output=$jsonOutputPath',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(jsonResult.exitCode, 0, reason: jsonResult.stderr.toString());
    final scoreboard = jsonDecode(jsonResult.stdout.toString());
    expect(scoreboard, isA<Map<String, Object?>>());
    expect(
      (scoreboard as Map<String, Object?>)['kind'],
      'fleuryWebFrameScoreboard',
    );
    expect(scoreboard['strictPass'], isTrue);
    expect(scoreboard['runCount'], 2);
    expect(scoreboard['steadySkipFrames'], 0);
    final persisted =
        jsonDecode(File(jsonOutputPath).readAsStringSync())
            as Map<String, Object?>;
    expect(persisted['kind'], 'fleuryWebFrameScoreboard');
    expect(persisted['strictPass'], isTrue);
    expect(persisted['runCount'], 2);
    final scenarios = scoreboard['scenarios'] as List<Object?>;
    expect(scenarios, hasLength(1));
    final scenario = scenarios.single as Map<String, Object?>;
    expect(scenario['id'], 'normal-80x24');
    expect(scenario['runCount'], 2);
    expect(scenario['runEnvironmentComparable'], isTrue);
    expect(scenario['runEnvironmentSignatureCount'], 1);
    expect(scenario['missingRunEnvironmentCount'], 0);
    expect(scenario['frameCount'], 4);
    expect(scenario['steadyFrameCount'], 4);
    expect(scenario['requestedStepCount'], 2);
    expect(scenario['extraFrameCount'], 2);
    final framesPerStep = scenario['framesPerStep'] as Map<String, Object?>;
    expect(framesPerStep['median'], 2.0);
    expect(scenario['latestCapture'], 'normal-b.json');
    final totalFrame = scenario['totalFrameP95Ms'] as Map<String, Object?>;
    expect(totalFrame['median'], 19.0);
    final steadyTotalFrame =
        scenario['steadyTotalFrameP95Ms'] as Map<String, Object?>;
    expect(steadyTotalFrame['median'], 19.0);
    final dirtyRowDiff = scenario['dirtyRowDiffP95Ms'] as Map<String, Object?>;
    expect(dirtyRowDiff['median'], 1.0);
    final browserDomNodes =
        scenario['browserDomNodeCount'] as Map<String, Object?>;
    expect(browserDomNodes['median'], 120.0);

    final markdownPath = '${tempDir.path}/scoreboard.md';
    final markdownResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--output=$markdownPath',
    ], workingDirectory: Directory.current.path);

    expect(
      markdownResult.exitCode,
      0,
      reason: markdownResult.stderr.toString(),
    );
    final markdown = File(markdownPath).readAsStringSync();
    expect(markdown, contains('Fleury Web Frame Scoreboard'));
    expect(markdown, contains('normal-80x24'));
    expect(markdown, contains('Total p95'));
    expect(markdown, contains('Steady total p95'));
    expect(markdown, contains('Steady semantic p95'));
    expect(markdown, contains('Steady over budget'));
    expect(markdown, contains('Frames / steps'));
    expect(markdown, contains('Build p95'));
    expect(markdown, contains('Layout p95'));
    expect(markdown, contains('Paint p95'));
    expect(markdown, contains('4 / 2<br>+2 extra'));
    expect(markdown, contains('Row diff p95'));
    expect(markdown, contains('Run Env'));
    expect(markdown, contains('1 signature'));
    expect(markdown, contains('DOM nodes'));
    expect(markdown, contains('1.50 MiB'));
  });

  test(
    'web frame scoreboard strict mode fails when run count is low',
    () async {
      _writeCapture(
        '${tempDir.path}/normal-a.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:00:00.000000Z',
        frames: [_webFrame(totalFrameMicros: 10000, domApplyMicros: 3000)],
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_scoreboard.dart',
        '--input=${tempDir.path}',
        '--min-runs=2',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final scoreboard = jsonDecode(result.stdout.toString());
      expect((scoreboard as Map<String, Object?>)['strictPass'], isFalse);
    },
  );

  test(
    'web frame scoreboard marks old runtime subphases unavailable',
    () async {
      final oldFrame = _webFrame(totalFrameMicros: 10000, domApplyMicros: 500)
        ..remove('runtimePhaseTimingAvailable')
        ..remove('runtimeBuildMicros')
        ..remove('runtimeLayoutMicros')
        ..remove('runtimePaintMicros');
      _writeCapture(
        '${tempDir.path}/old-normal.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:00:00.000000Z',
        frames: [oldFrame],
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_scoreboard.dart',
        '--input=${tempDir.path}',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final scoreboard =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final scenario =
          (scoreboard['scenarios'] as List<Object?>).single
              as Map<String, Object?>;
      expect(
        scenario['runtimeBuildP95Ms'],
        isA<Map<String, Object?>>().having(
          (metric) => metric['median'],
          'median',
          isNull,
        ),
      );
      expect(
        scenario['runtimeLayoutP95Ms'],
        isA<Map<String, Object?>>().having(
          (metric) => metric['median'],
          'median',
          isNull,
        ),
      );
      expect(
        scenario['runtimePaintP95Ms'],
        isA<Map<String, Object?>>().having(
          (metric) => metric['median'],
          'median',
          isNull,
        ),
      );
      expect(
        scenario['dominantP95Slices'],
        isA<Map<String, Object?>>().having(
          (slices) => slices['runtimeRenderMs'],
          'runtimeRenderMs',
          1,
        ),
      );
      final captures = scenario['captures'] as List<Object?>;
      final capture = captures.single as Map<String, Object?>;
      expect(capture['runtimeBuildP95Ms'], isNull);

      final markdownPath = '${tempDir.path}/scoreboard.md';
      final markdownResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_scoreboard.dart',
        '--input=${tempDir.path}',
        '--output=$markdownPath',
      ], workingDirectory: Directory.current.path);

      expect(
        markdownResult.exitCode,
        0,
        reason: markdownResult.stderr.toString(),
      );
      final markdown = File(markdownPath).readAsStringSync();
      expect(markdown, contains('10.00 ms | 3.00 ms | - | - | - |'));
    },
  );

  test('web frame scoreboard rejects empty json output path', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--json-output=',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--json-output requires a non-empty path.'),
    );
  });

  test('web frame scoreboard exposes and gates steady-state metrics', () async {
    _writeCapture(
      '${tempDir.path}/dirty-row.json',
      scenarioId: 'dirty-row-160x50',
      capturedAt: '2026-06-09T21:30:00.000000Z',
      frames: [
        _webFrame(
          totalFrameMicros: 30000,
          domApplyMicros: 6000,
          semanticApplyMicros: 9000,
        ),
        _webFrame(
          totalFrameMicros: 10000,
          domApplyMicros: 3000,
          semanticApplyMicros: 2000,
        ),
        _webFrame(
          totalFrameMicros: 12000,
          domApplyMicros: 3000,
          semanticApplyMicros: 2000,
        ),
      ],
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--steady-skip-frames=1',
      '--max-over-budget-percent=0',
      '--max-steady-over-budget-percent=0',
      '--max-steady-total-frame-p95-ms=12',
      '--max-steady-semantic-apply-p95-ms=2',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final scoreboard =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(scoreboard['strictPass'], isFalse);
    expect(scoreboard['steadySkipFrames'], 1);
    final scenario =
        (scoreboard['scenarios'] as List<Object?>).single
            as Map<String, Object?>;
    expect(scenario['steadySkipFrames'], 1);
    expect(scenario['frameCount'], 3);
    expect(scenario['steadyFrameCount'], 2);
    expect(
      scenario['steadyTotalFrameP95Ms'],
      isA<Map<String, Object?>>().having(
        (metric) => metric['median'],
        'median',
        12.0,
      ),
    );
    expect(
      scenario['steadySemanticApplyP95Ms'],
      isA<Map<String, Object?>>().having(
        (metric) => metric['median'],
        'median',
        2.0,
      ),
    );
    expect(
      scenario['steadyOverBudgetPercent'],
      isA<Map<String, Object?>>().having(
        (metric) => metric['median'],
        'median',
        0.0,
      ),
    );
    final gates = scenario['gates'] as List<Object?>;
    expect(
      gates,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'overBudgetPercentMedian')
            .having((gate) => gate['maximum'], 'maximum', 0.0)
            .having((gate) => gate['passed'], 'passed', isFalse),
      ),
    );
    expect(
      gates,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'steadyTotalFrameP95MedianMs')
            .having((gate) => gate['actual'], 'actual', 12.0)
            .having((gate) => gate['maximum'], 'maximum', 12.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );
    expect(
      gates,
      contains(
        isA<Map<String, Object?>>()
            .having(
              (gate) => gate['id'],
              'id',
              'steadySemanticApplyP95MedianMs',
            )
            .having((gate) => gate['actual'], 'actual', 2.0)
            .having((gate) => gate['maximum'], 'maximum', 2.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );
    expect(
      gates,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'steadyOverBudgetPercentMedian')
            .having((gate) => gate['actual'], 'actual', 0.0)
            .having((gate) => gate['maximum'], 'maximum', 0.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );
  });

  test('web frame scoreboard strict mode fails supplied gates', () async {
    _writeCapture(
      '${tempDir.path}/normal-a.json',
      scenarioId: 'normal-80x24',
      capturedAt: '2026-06-08T01:00:00.000000Z',
      runEnvironment: _runEnvironment(chromeBrowser: 'Chrome/127'),
      requestedSteps: 1,
      frames: [
        _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
        _webFrame(totalFrameMicros: 20000, domApplyMicros: 5000),
      ],
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--max-total-frame-p95-ms=15',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final scoreboard = jsonDecode(result.stdout.toString());
    expect((scoreboard as Map<String, Object?>)['strictPass'], isFalse);
    final scenarios = scoreboard['scenarios'] as List<Object?>;
    final scenario = scenarios.single as Map<String, Object?>;
    expect(scenario['strictPass'], isFalse);
    expect(
      scenario['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'totalFrameP95MedianMs')
            .having((gate) => gate['actual'], 'actual', 20.0)
            .having((gate) => gate['maximum'], 'maximum', 15.0)
            .having((gate) => gate['passed'], 'passed', isFalse),
      ),
    );

    final markdownPath = '${tempDir.path}/scoreboard.md';
    final markdownResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--output=$markdownPath',
      '--max-total-frame-p95-ms=15',
    ], workingDirectory: Directory.current.path);

    expect(
      markdownResult.exitCode,
      0,
      reason: markdownResult.stderr.toString(),
    );
    final markdown = File(markdownPath).readAsStringSync();
    expect(markdown, contains('Gates'));
    expect(markdown, contains('totalFrameP95MedianMs'));
  });

  test(
    'web frame scoreboard can require comparable run environments',
    () async {
      _writeCapture(
        '${tempDir.path}/normal-a.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:00:00.000000Z',
        runEnvironment: _runEnvironment(),
        frames: [_webFrame(totalFrameMicros: 10000, domApplyMicros: 3000)],
      );
      _writeCapture(
        '${tempDir.path}/normal-b.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:05:00.000000Z',
        runEnvironment: _runEnvironment(),
        frames: [_webFrame(totalFrameMicros: 12000, domApplyMicros: 4000)],
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_scoreboard.dart',
        '--input=${tempDir.path}',
        '--min-runs=2',
        '--require-comparable-environment',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final scoreboard =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(scoreboard['requireComparableRunEnvironment'], isTrue);
      expect(scoreboard['strictPass'], isTrue);
      final scenario =
          (scoreboard['scenarios'] as List<Object?>).single
              as Map<String, Object?>;
      expect(scenario['runEnvironmentComparable'], isTrue);
      expect(scenario['strictPass'], isTrue);
    },
  );

  test(
    'web frame scoreboard strict mode fails incomparable environments',
    () async {
      _writeCapture(
        '${tempDir.path}/normal-a.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:00:00.000000Z',
        runEnvironment: _runEnvironment(chromeBrowser: 'Chrome/126'),
        frames: [_webFrame(totalFrameMicros: 10000, domApplyMicros: 3000)],
      );
      _writeCapture(
        '${tempDir.path}/normal-b.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:05:00.000000Z',
        runEnvironment: _runEnvironment(chromeBrowser: 'Chrome/127'),
        frames: [_webFrame(totalFrameMicros: 12000, domApplyMicros: 4000)],
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_scoreboard.dart',
        '--input=${tempDir.path}',
        '--min-runs=2',
        '--require-comparable-environment',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final scoreboard =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(scoreboard['strictPass'], isFalse);
      final scenario =
          (scoreboard['scenarios'] as List<Object?>).single
              as Map<String, Object?>;
      expect(scenario['runEnvironmentComparable'], isFalse);
      expect(scenario['runEnvironmentSignatureCount'], 2);
      expect(scenario['strictPass'], isFalse);
    },
  );

  test('web frame scoreboard applies per-scenario threshold policy', () async {
    _writeCapture(
      '${tempDir.path}/normal-a.json',
      scenarioId: 'normal-80x24',
      capturedAt: '2026-06-08T01:00:00.000000Z',
      requestedSteps: 1,
      frames: [
        _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
        _webFrame(totalFrameMicros: 20000, domApplyMicros: 5000),
      ],
    );
    _writeCapture(
      '${tempDir.path}/stress-a.json',
      scenarioId: 'stress-300x100',
      capturedAt: '2026-06-08T01:05:00.000000Z',
      frames: [_webFrame(totalFrameMicros: 12000, domApplyMicros: 3000)],
    );
    final thresholdsPath = '${tempDir.path}/thresholds.json';
    File(thresholdsPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'kind': 'fleuryWebFrameThresholds',
        'reviewState': 'reviewed',
        'reviewedBy': 'test reviewer',
        'reviewedAt': '2026-06-08T12:00:00.000000Z',
        'reviewContext': 'Chrome 127 macOS retained DOM scoreboard test',
        'defaults': {'maxTotalFrameP95Ms': 11, 'maxSteadyTotalFrameP95Ms': 11, 'maxSteadyOverBudgetPercent': 0, 'maxSemanticUncoveredCells': 0},
        'scenarios': {
          'normal-80x24': {'maxTotalFrameP95Ms': 25, 'maxSteadyTotalFrameP95Ms': 25, 'maxSteadyOverBudgetPercent': 100},
        },
      })}\n',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--thresholds=$thresholdsPath',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final scoreboard =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(scoreboard['thresholdPolicyPath'], thresholdsPath);
    expect(scoreboard['thresholdPolicyReviewState'], 'reviewed');
    expect(scoreboard['thresholdPolicyReviewedBy'], 'test reviewer');
    expect(
      scoreboard['thresholdPolicyReviewedAt'],
      '2026-06-08T12:00:00.000000Z',
    );
    expect(
      scoreboard['thresholdPolicyReviewContext'],
      'Chrome 127 macOS retained DOM scoreboard test',
    );
    expect(scoreboard['thresholdPolicyFingerprint'], isA<String>());
    expect(scoreboard['thresholdPolicyScenarioCount'], 1);
    expect(scoreboard['strictPass'], isFalse);
    final scenarios = {
      for (final raw in scoreboard['scenarios'] as List<Object?>)
        (raw as Map<String, Object?>)['id']: raw,
    };
    final normal = scenarios['normal-80x24']!;
    expect(normal['thresholdPolicyMatchedScenario'], isTrue);
    expect(normal['strictPass'], isTrue);
    expect(
      normal['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'totalFrameP95MedianMs')
            .having((gate) => gate['maximum'], 'maximum', 25.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );
    expect(
      normal['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'steadyTotalFrameP95MedianMs')
            .having((gate) => gate['maximum'], 'maximum', 25.0)
            .having((gate) => gate['passed'], 'passed', isTrue),
      ),
    );

    final stress = scenarios['stress-300x100']!;
    expect(stress['thresholdPolicyMatchedScenario'], isFalse);
    expect(stress['strictPass'], isFalse);
    expect(
      stress['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'totalFrameP95MedianMs')
            .having((gate) => gate['actual'], 'actual', 12.0)
            .having((gate) => gate['maximum'], 'maximum', 11.0)
            .having((gate) => gate['passed'], 'passed', isFalse),
      ),
    );
    expect(
      stress['gates'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((gate) => gate['id'], 'id', 'steadyTotalFrameP95MedianMs')
            .having((gate) => gate['actual'], 'actual', 12.0)
            .having((gate) => gate['maximum'], 'maximum', 11.0)
            .having((gate) => gate['passed'], 'passed', isFalse),
      ),
    );
  });

  test('web frame scoreboard writes candidate threshold policy', () async {
    _writeCapture(
      '${tempDir.path}/normal-a.json',
      scenarioId: 'normal-80x24',
      capturedAt: '2026-06-08T01:00:00.000000Z',
      requestedSteps: 1,
      frames: [
        _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
        _webFrame(totalFrameMicros: 20000, domApplyMicros: 5000),
      ],
    );
    _writeCapture(
      '${tempDir.path}/noop-a.json',
      scenarioId: 'noop-160x50',
      capturedAt: '2026-06-08T01:00:00.000000Z',
      runEnvironment: _runEnvironment(chromeBrowser: 'Chrome/127'),
      frames: [
        _webFrame(totalFrameMicros: 20000, domApplyMicros: 0),
        _webFrame(totalFrameMicros: 20000, domApplyMicros: 0),
      ],
    );
    final thresholdsPath = '${tempDir.path}/candidate-thresholds.json';

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${tempDir.path}',
      '--write-thresholds=$thresholdsPath',
      '--steady-skip-frames=1',
      '--threshold-headroom-percent=10',
      '--threshold-min-headroom-ms=0.5',
      '--threshold-min-headroom-percent=0.5',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final scoreboard =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(scoreboard['kind'], 'fleuryWebFrameScoreboard');

    final policy =
        jsonDecode(File(thresholdsPath).readAsStringSync())
            as Map<String, Object?>;
    expect(policy['kind'], 'fleuryWebFrameThresholds');
    expect(policy['reviewState'], 'candidate');
    final generatedFrom = policy['generatedFrom'] as Map<String, Object?>;
    expect(generatedFrom['sourceMetric'], 'maxCaptureP95PerScenario');
    expect(generatedFrom['thresholdHeadroomPercent'], 10.0);
    expect(generatedFrom['thresholdMinHeadroomMs'], 0.5);
    expect(generatedFrom['thresholdMinHeadroomPercent'], 0.5);
    expect(generatedFrom['steadySkipFrames'], 1);
    final captureEnvironment =
        generatedFrom['captureEnvironment'] as Map<String, Object?>;
    expect(captureEnvironment['scenarioCount'], 2);
    expect(captureEnvironment['scenarioWithEnvironmentCount'], greaterThan(0));
    expect(captureEnvironment['chromeBrowser'], 'Chrome/127');
    expect(
      captureEnvironment['reviewContextHint'],
      'Browser Chrome/127, OS macos OS version test-os, Dart Dart test, headless=true, frameBudgetMs=16.67, retained DOM product baseline',
    );

    final scenarios = policy['scenarios'] as Map<String, Object?>;
    final normal = scenarios['normal-80x24'] as Map<String, Object?>;
    expect(normal['maxTotalFrameP95Ms'], 22.0);
    expect(normal['maxDomApplyP95Ms'], 5.5);
    expect(normal['maxSemanticApplyP95Ms'], 1.5);
    expect(normal['maxOverBudgetPercent'], 55.0);
    expect(normal['maxSteadyTotalFrameP95Ms'], 22.0);
    expect(normal['maxSteadySemanticApplyP95Ms'], 1.5);
    expect(normal['maxSteadyOverBudgetPercent'], 100.0);
    expect(normal['maxSemanticUncoveredCells'], 0);
    expect(normal['observedFrameCount'], 2);
    expect(normal['observedSteadyFrameCount'], 1);
    expect(normal['observedRequestedStepCount'], 1);
    expect(normal['observedExtraFrameCount'], 1);
    expect(normal['observedMaxFramesPerStep'], 2.0);
    expect(normal['observedMaxRuntimeBuildP95Ms'], 0.5);
    expect(normal['observedMaxRuntimeLayoutP95Ms'], 0.75);
    expect(normal['observedMaxRuntimePaintP95Ms'], 1.75);

    final noop = scenarios['noop-160x50'] as Map<String, Object?>;
    expect(noop['maxOverBudgetPercent'], 100.0);
  });
}

void _writeCapture(
  String path, {
  required String scenarioId,
  required String capturedAt,
  Map<String, Object?>? browserMetrics,
  Map<String, Object?>? runEnvironment,
  int? requestedFrames,
  int? requestedSteps,
  required List<Map<String, Object?>> frames,
}) {
  final effectiveRequestedFrames = requestedFrames ?? frames.length;
  final effectiveRequestedSteps = requestedSteps ?? effectiveRequestedFrames;
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameCapture',
      'capturedAt': capturedAt,
      'scenario': {'id': scenarioId},
      'frameBudgetMs': 16.67,
      'requestedFrames': effectiveRequestedFrames,
      'requestedSteps': effectiveRequestedSteps,
      'capturedFrameCount': frames.length,
      'extraFrameCount': frames.length - effectiveRequestedSteps,
      'framesPerStep': frames.length / effectiveRequestedSteps,
      if (browserMetrics != null) 'browserMetrics': browserMetrics,
      if (runEnvironment != null) 'runEnvironment': runEnvironment,
      'frames': frames,
    })}\n',
  );
}

Map<String, Object?> _runEnvironment({String chromeBrowser = 'Chrome/126'}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'chromeExecutable': '/tmp/chrome',
    'chromeBrowser': chromeBrowser,
    'chromeUserAgent': 'Mozilla/5.0 test',
    'devtoolsProtocolVersion': '1.3',
    'dartVersion': 'Dart test',
    'operatingSystem': 'macos',
    'operatingSystemVersion': 'test-os',
    'headless': true,
    'requestedFrames': 24,
    'requestedSteps': 24,
    'warmupFrames': 2,
    'frameBudgetMs': 16.67,
  };
}

Map<String, Object?> _webFrame({
  required int totalFrameMicros,
  required int domApplyMicros,
  int dirtyRowDiffMicros = 0,
  int semanticApplyMicros = 1000,
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
    'runtimeRenderMicros': 3000,
    'runtimeBuildMicros': 500,
    'runtimeLayoutMicros': 750,
    'runtimePaintMicros': 1750,
    'dirtyRowDiffMicros': dirtyRowDiffMicros,
    'spanBuildMicros': 1000,
    'domApplyMicros': domApplyMicros,
    'semanticApplyMicros': semanticApplyMicros,
    'totalFrameMicros': totalFrameMicros,
  };
}
