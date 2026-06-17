import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('benchmark manifest launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_manifest_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('prints the checked-in comparative benchmark manifest', () async {
      final result = await _runTool(['benchmark', 'manifest', '--json']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final manifest = _jsonObject(result.stdout);
      expect(manifest['kind'], 'fleuryComparativeBenchmarkManifest');
      expect(manifest['schemaVersion'], 1);
      final scenarios = manifest['scenarios'];
      expect(scenarios, isA<List<Object?>>());
      expect(scenarios as List<Object?>, hasLength(greaterThanOrEqualTo(12)));

      final byId = <String, Map<String, Object?>>{
        for (final scenario in scenarios)
          (scenario as Map<String, Object?>)['id'].toString(): scenario,
      };
      expect(byId, contains('SB.1'));
      expect(byId, contains('SB.10'));
      expect(
        (byId['SB.10']!['local'] as Map<String, Object?>)['workingDirectory'],
        'packages/fleury_example_console',
      );
      expect(byId['SB.10']!['peerRuns'], isEmpty);
    });

    test('rejects malformed benchmark manifests', () async {
      final path = '${tempDir.path}/bad-manifest.json';
      File(path).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryComparativeBenchmarkManifest',
          'peers': [
            {'id': 'known', 'name': 'Known'},
          ],
          'scenarios': [
            {
              'id': 'SB.bad',
              'name': 'Bad Scenario',
              'local': {
                'workingDirectory': 'packages/fleury',
                'command': ['dart'],
              },
              'peerTargets': ['missing-peer'],
              'contract': ['do work'],
              'requiredMetrics': ['workUs'],
              'claimGates': ['correct'],
            },
          ],
        }),
      );

      final result = await _runTool(['benchmark', 'manifest', '--input=$path']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('unknown peer'));
    });
  });

  group('benchmark result launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_result_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'accepts and merges a peer benchmark run into a manifest copy',
      () async {
        final inputPath = '${tempDir.path}/bubbletea-sb1.json';
        final outputPath = '${tempDir.path}/manifest-with-peer.json';
        _writeEntry(tempDir, 'bubbletea-sb1.json', _peerRun());

        final result = await _runTool([
          'benchmark',
          'result',
          '--input=$inputPath',
          '--output=$outputPath',
          '--json',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final summary = _jsonObject(result.stdout);
        expect(summary['accepted'], isTrue);
        expect(summary['peerId'], 'bubbletea');
        expect(summary['scenarioId'], 'SB.1');
        expect(summary['requiredMetricCount'], 6);
        expect(summary['claimGateCount'], 3);
        expect(summary['outputPath'], contains('manifest-with-peer.json'));

        final manifest = _jsonObject(File(outputPath).readAsStringSync());
        final scenarios = manifest['scenarios'] as List<Object?>;
        final scenario = scenarios.cast<Map<String, Object?>>().singleWhere(
          (scenario) => scenario['id'] == 'SB.1',
        );
        final peerRuns = scenario['peerRuns'] as List<Object?>;
        expect(peerRuns, hasLength(1));
        expect(
          peerRuns.single as Map<String, Object?>,
          containsPair('runId', 'bubbletea-sb1-local-fixture'),
        );
      },
    );

    test('rejects a peer run missing required metrics', () async {
      final inputPath = '${tempDir.path}/bad-bubbletea-sb1.json';
      final run = _peerRun();
      final metrics = run['metrics'] as Map<String, Object?>;
      metrics.remove('commandToFrameUs');
      _writeEntry(tempDir, 'bad-bubbletea-sb1.json', run);

      final result = await _runTool([
        'benchmark',
        'result',
        '--input=$inputPath',
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('missing required metric'));
      expect(result.stderr, contains('commandToFrameUs'));
    });
  });

  group('benchmark variance launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_variance_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('summarizes repeated comparable peer runs', () async {
      final runsDir = Directory('${tempDir.path}/runs')..createSync();
      _writeEntry(
        runsDir,
        'run-a.json',
        _peerRun(
          runId: 'bubbletea-sb1-run-a',
          firstFrameUsP95: 900,
          commandToFrameUsP95: 1100,
          semanticOrTestQueryUsP95: 700,
        ),
      );
      _writeEntry(
        runsDir,
        'run-b.json',
        _peerRun(
          runId: 'bubbletea-sb1-run-b',
          firstFrameUsP95: 1000,
          commandToFrameUsP95: 1200,
          semanticOrTestQueryUsP95: 800,
        ),
      );
      _writeEntry(
        runsDir,
        'run-c.json',
        _peerRun(
          runId: 'bubbletea-sb1-run-c',
          firstFrameUsP95: 1100,
          commandToFrameUsP95: 1300,
          semanticOrTestQueryUsP95: 900,
        ),
      );
      final outputPath = '${tempDir.path}/variance.json';

      final result = await _runTool([
        'benchmark',
        'variance',
        '--input=${runsDir.path}',
        '--min-runs=3',
        '--strict',
        '--output=$outputPath',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final summary = _jsonObject(result.stdout);
      expect(summary['kind'], 'fleuryBenchmarkVariance');
      expect(summary['peerId'], 'bubbletea');
      expect(summary['scenarioId'], 'SB.1');
      expect(summary['runCount'], 3);
      expect(summary['sufficientRunCount'], isTrue);
      expect(summary['comparable'], isTrue);
      expect(summary['strictPass'], isTrue);

      final metrics = summary['metrics'] as Map<String, Object?>;
      final commandToFrame =
          metrics['commandToFrameUs'] as Map<String, Object?>;
      expect(commandToFrame['primaryValue'], 'p95');
      expect(commandToFrame['samples'], 3);
      expect(commandToFrame['median'], 1200);
      expect(commandToFrame['min'], 1100);
      expect(commandToFrame['max'], 1300);

      final persisted = _jsonObject(File(outputPath).readAsStringSync());
      expect(persisted['kind'], 'fleuryBenchmarkVariance');
      expect(persisted['strictPass'], isTrue);
    });

    test('strict mode fails when repeated evidence is insufficient', () async {
      final inputPath = '${tempDir.path}/single-run.json';
      _writeEntry(
        tempDir,
        'single-run.json',
        _peerRun(runId: 'bubbletea-sb1-single-run'),
      );

      final result = await _runTool([
        'benchmark',
        'variance',
        '--input=$inputPath',
        '--min-runs=2',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final summary = _jsonObject(result.stdout);
      expect(summary['strictPass'], isFalse);
      expect(summary['sufficientRunCount'], isFalse);
      expect(
        summary['errors'] as List<Object?>,
        contains('runCount 1 is below minRuns 2'),
      );
    });
  });

  group('benchmark web-report launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_report_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('summarizes retained DOM web frame captures', () async {
      final inputPath = '${tempDir.path}/web-frames.json';
      final outputPath = '${tempDir.path}/web-frames.md';
      File(inputPath).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameCapture',
          'browserMetrics': {
            'layoutDurationMs': 1.5,
            'recalcStyleDurationMs': 2.25,
            'scriptDurationMs': 3.75,
            'taskDurationMs': 7.5,
            'jsHeapUsedBytes': 1048576,
            'jsHeapTotalBytes': 2097152,
            'domDocumentCount': 1,
            'domNodeCount': 128,
            'jsEventListenerCount': 9,
          },
          'frames': [
            _webFrame(
              totalFrameMicros: 10000,
              dirtyRowDiffMicros: 800,
              domApplyMicros: 3000,
            ),
            _webFrame(
              totalFrameMicros: 22000,
              dirtyRowDiffMicros: 1500,
              domApplyMicros: 12000,
            ),
          ],
        }),
      );

      final jsonResult = await _runTool([
        'benchmark',
        'web-report',
        '--input=$inputPath',
        '--budget-ms=16.67',
        '--json',
      ]);

      expect(jsonResult.exitCode, 0, reason: jsonResult.stderr.toString());
      final summary = _jsonObject(jsonResult.stdout);
      expect(summary['kind'], 'fleuryWebFrameSummary');
      expect(summary['frameCount'], 2);
      expect(summary['overBudgetFrameCount'], 1);
      expect(summary['dominantP95Slice'], 'domApplyMs');
      final timings = summary['timings'] as Map<String, Object?>;
      final dirtyRowDiff = timings['dirtyRowDiffMs'] as Map<String, Object?>;
      expect(dirtyRowDiff['p95'], 1.5);
      final browserMetrics = summary['browserMetrics'] as Map<String, Object?>;
      expect(browserMetrics['domNodeCount'], 128);

      final passingGate = await _runTool([
        'benchmark',
        'web-report',
        '--input=$inputPath',
        '--max-total-frame-p95-ms=25',
        '--max-dom-apply-p95-ms=15',
        '--max-semantic-apply-p95-ms=2',
        '--max-semantic-uncovered-cells=0',
        '--strict',
        '--json',
      ]);

      expect(passingGate.exitCode, 0, reason: passingGate.stderr.toString());
      final passingSummary = _jsonObject(passingGate.stdout);
      expect(passingSummary['strictPass'], isTrue);
      expect(passingSummary['gates'] as List<Object?>, hasLength(4));

      final failingGate = await _runTool([
        'benchmark',
        'web-report',
        '--input=$inputPath',
        '--max-total-frame-p95-ms=15',
        '--strict',
        '--json',
      ]);

      expect(failingGate.exitCode, 1);
      final failingSummary = _jsonObject(failingGate.stdout);
      expect(failingSummary['strictPass'], isFalse);
      expect(
        failingSummary['gates'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>()
              .having((gate) => gate['id'], 'id', 'totalFrameP95Ms')
              .having((gate) => gate['passed'], 'passed', isFalse),
        ),
      );

      final markdownResult = await _runTool([
        'benchmark',
        'web-report',
        '--input=$inputPath',
        '--output=$outputPath',
        '--max-total-frame-p95-ms=25',
      ]);

      expect(
        markdownResult.exitCode,
        0,
        reason: markdownResult.stderr.toString(),
      );
      final markdown = File(outputPath).readAsStringSync();
      expect(markdown, contains('Fleury Web Frame'));
      expect(markdown, contains('dirtyRowDiffMs'));
      expect(markdown, contains('domApplyMs'));
      expect(markdown, contains('## Browser Metrics'));
      expect(markdown, contains('DOM nodes'));
      expect(markdown, contains('## Gates'));
    });
  });

  group('benchmark web-capture launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_capture_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('forwards retained DOM browser capture options', () async {
      final outputPath = '${tempDir.path}/capture.json';
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-capture',
        '--scenario=single-dirty-cell-160x50',
        '--frames=3',
        '--warmup=0',
        '--budget-ms=8',
        '--output=$outputPath',
        '--chrome=/tmp/chrome',
        '--timeout=5',
        '--headful',
        '--keep-temp',
        '--compile-only',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('(packages/fleury_web) dart run'));
      expect(result.stdout, contains('tool/web_frame_capture.dart'));
      expect(result.stdout, contains('--scenario=single-dirty-cell-160x50'));
      expect(result.stdout, contains('--frames=3'));
      expect(result.stdout, contains('--warmup=0'));
      expect(result.stdout, contains('--budget-ms=8.0'));
      expect(result.stdout, contains('--output=$outputPath'));
      expect(result.stdout, contains('--chrome=/tmp/chrome'));
      expect(result.stdout, contains('--timeout=5'));
      expect(result.stdout, contains('--headful'));
      expect(result.stdout, contains('--keep-temp'));
      expect(result.stdout, contains('--compile-only'));
      expect(result.stdout, contains('--json'));
    });

    test(
      'uses ignored generated bucket for default web capture output',
      () async {
        final result = await _runTool([
          '--dry-run',
          'benchmark',
          'web-capture',
          '--scenario=normal-80x24',
          '--compile-only',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          result.stdout.toString().replaceAll(Platform.pathSeparator, '/'),
          contains('/profiling/web/runs/normal-80x24-'),
        );
      },
    );
  });

  group('benchmark web-suite launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_suite_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('forwards retained DOM browser suite options', () async {
      final outputDir = '${tempDir.path}/suite';
      final scoreboardPath = '${tempDir.path}/scoreboard.md';
      final scoreboardJsonPath = '${tempDir.path}/scoreboard.json';
      final thresholdsPath = '${tempDir.path}/thresholds.json';
      final candidateThresholdsPath =
          '${tempDir.path}/candidate-thresholds.json';
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-suite',
        '--scenarios=normal-80x24,single-dirty-cell-160x50',
        '--runs=2',
        '--frames=3',
        '--warmup=0',
        '--budget-ms=8',
        '--output-dir=$outputDir',
        '--scoreboard=$scoreboardPath',
        '--scoreboard-json=$scoreboardJsonPath',
        '--min-runs=2',
        '--max-total-frame-p95-ms=25',
        '--max-dom-apply-p95-ms=12',
        '--max-semantic-apply-p95-ms=8',
        '--max-over-budget-percent=10',
        '--max-semantic-uncovered-cells=0',
        '--thresholds=$thresholdsPath',
        '--write-thresholds=$candidateThresholdsPath',
        '--threshold-headroom-percent=10',
        '--threshold-min-headroom-ms=0.5',
        '--threshold-min-headroom-percent=0.5',
        '--chrome=/tmp/chrome',
        '--timeout=5',
        '--no-strict',
        '--no-require-comparable-environment',
        '--no-compile-once',
        '--headful',
        '--keep-temp',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('(packages/fleury_web) dart run'));
      expect(result.stdout, contains('tool/web_frame_suite.dart'));
      expect(
        result.stdout,
        contains('--scenarios=normal-80x24,single-dirty-cell-160x50'),
      );
      expect(result.stdout, contains('--runs=2'));
      expect(result.stdout, contains('--frames=3'));
      expect(result.stdout, contains('--warmup=0'));
      expect(result.stdout, contains('--budget-ms=8.0'));
      expect(result.stdout, contains('--output-dir=$outputDir'));
      expect(result.stdout, contains('--scoreboard=$scoreboardPath'));
      expect(result.stdout, contains('--scoreboard-json=$scoreboardJsonPath'));
      expect(result.stdout, contains('--min-runs=2'));
      expect(result.stdout, contains('--max-total-frame-p95-ms=25.0'));
      expect(result.stdout, contains('--max-dom-apply-p95-ms=12.0'));
      expect(result.stdout, contains('--max-semantic-apply-p95-ms=8.0'));
      expect(result.stdout, contains('--max-over-budget-percent=10.0'));
      expect(result.stdout, contains('--max-semantic-uncovered-cells=0.0'));
      expect(result.stdout, contains('--thresholds=$thresholdsPath'));
      expect(
        result.stdout,
        contains('--write-thresholds=$candidateThresholdsPath'),
      );
      expect(result.stdout, contains('--threshold-headroom-percent=10.0'));
      expect(result.stdout, contains('--threshold-min-headroom-ms=0.5'));
      expect(result.stdout, contains('--threshold-min-headroom-percent=0.5'));
      expect(result.stdout, contains('--chrome=/tmp/chrome'));
      expect(result.stdout, contains('--timeout=5'));
      expect(result.stdout, contains('--no-strict'));
      expect(result.stdout, contains('--no-require-comparable-environment'));
      expect(result.stdout, contains('--no-compile-once'));
      expect(result.stdout, contains('--headful'));
      expect(result.stdout, contains('--keep-temp'));
      expect(result.stdout, contains('--json'));
    });

    test(
      'uses ignored generated bucket for default web suite output',
      () async {
        final result = await _runTool([
          '--dry-run',
          'benchmark',
          'web-suite',
          '--scenarios=normal-80x24',
          '--runs=1',
          '--frames=1',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final stdout = result.stdout.toString().replaceAll(
          Platform.pathSeparator,
          '/',
        );
        expect(stdout, contains('/profiling/web/runs/'));
        expect(stdout, contains('-suite'));
        expect(stdout, contains('/scoreboard.md'));
        expect(stdout, contains('/scoreboard.json'));
      },
    );
  });

  group('benchmark web-scoreboard launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_scoreboard_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('aggregates retained DOM web frame capture directories', () async {
      final outputPath = '${tempDir.path}/scoreboard.md';
      final jsonOutputPath = '${tempDir.path}/scoreboard.json';
      final thresholdsPath = '${tempDir.path}/thresholds.json';
      final candidateThresholdsPath =
          '${tempDir.path}/candidate-thresholds.json';
      File(thresholdsPath).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameThresholds',
          'defaults': {'maxTotalFrameP95Ms': 25},
        }),
      );
      File('${tempDir.path}/normal-80x24-a.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameCapture',
          'capturedAt': '2026-06-08T01:00:00.000000Z',
          'scenario': {'id': 'normal-80x24'},
          'frames': [
            _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
            _webFrame(totalFrameMicros: 20000, domApplyMicros: 5000),
          ],
        }),
      );

      final jsonResult = await _runTool([
        'benchmark',
        'web-scoreboard',
        '--input=${tempDir.path}',
        '--json-output=$jsonOutputPath',
        '--thresholds=$thresholdsPath',
        '--write-thresholds=$candidateThresholdsPath',
        '--threshold-headroom-percent=10',
        '--threshold-min-headroom-ms=0.5',
        '--threshold-min-headroom-percent=0.5',
        '--max-dom-apply-p95-ms=6',
        '--strict',
        '--json',
      ]);

      expect(jsonResult.exitCode, 0, reason: jsonResult.stderr.toString());
      final scoreboard = _jsonObject(jsonResult.stdout);
      expect(scoreboard['kind'], 'fleuryWebFrameScoreboard');
      expect(scoreboard['thresholdPolicyPath'], thresholdsPath);
      expect(scoreboard['runCount'], 1);
      final persistedScoreboard =
          jsonDecode(File(jsonOutputPath).readAsStringSync())
              as Map<String, Object?>;
      expect(persistedScoreboard['kind'], 'fleuryWebFrameScoreboard');
      expect(persistedScoreboard['runCount'], 1);
      final candidateThresholds =
          jsonDecode(File(candidateThresholdsPath).readAsStringSync())
              as Map<String, Object?>;
      expect(candidateThresholds['kind'], 'fleuryWebFrameThresholds');
      final generatedFrom =
          candidateThresholds['generatedFrom'] as Map<String, Object?>;
      expect(generatedFrom['thresholdHeadroomPercent'], 10.0);
      final scenarios = scoreboard['scenarios'] as List<Object?>;
      final scenario = scenarios.single as Map<String, Object?>;
      expect(scenario['id'], 'normal-80x24');
      expect(scenario['frameCount'], 2);
      expect(
        scenario['gates'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>()
              .having((gate) => gate['id'], 'id', 'totalFrameP95MedianMs')
              .having((gate) => gate['passed'], 'passed', isTrue),
        ),
      );

      final markdownResult = await _runTool([
        'benchmark',
        'web-scoreboard',
        '--input=${tempDir.path}',
        '--output=$outputPath',
        '--thresholds=$thresholdsPath',
      ]);

      expect(
        markdownResult.exitCode,
        0,
        reason: markdownResult.stderr.toString(),
      );
      final markdown = File(outputPath).readAsStringSync();
      expect(markdown, contains('Fleury Web Frame Scoreboard'));
      expect(markdown, contains('normal-80x24'));
      expect(markdown, contains('Gates'));
    });

    test('forwards comparable environment scoreboard gate', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-scoreboard',
        '--input=${tempDir.path}',
        '--require-comparable-environment',
        '--strict',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_frame_scoreboard.dart'));
      expect(result.stdout, contains('--require-comparable-environment'));
      expect(result.stdout, contains('--strict'));
    });
  });

  group('benchmark web-threshold-review launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_threshold_review_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('promotes candidate thresholds with root-relative paths', () async {
      final inputPath = '${tempDir.path}/thresholds.candidate.json';
      final outputPath = '${tempDir.path}/thresholds.json';
      final jsonOutputPath = '${tempDir.path}/threshold-review.json';
      File(inputPath).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameThresholds',
          'generatedAt': '2026-06-08T12:00:00.000Z',
          'reviewState': 'candidate',
          'defaults': <String, Object?>{},
          'scenarios': {
            'normal-80x24': {
              'maxTotalFrameP95Ms': 20,
              'maxDomApplyP95Ms': 4,
              'maxSemanticApplyP95Ms': 8,
              'maxOverBudgetPercent': 0,
              'maxSemanticUncoveredCells': 0,
            },
          },
        }),
      );

      final result = await _runTool([
        'benchmark',
        'web-threshold-review',
        '--input=$inputPath',
        '--output=$outputPath',
        '--json-output=$jsonOutputPath',
        '--reviewed-by=tool reviewer',
        '--reviewed-at=2026-06-08T12:00:00Z',
        '--review-context=Chrome 127 macOS launcher test context',
        '--review-note=Accepted for launcher test.',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final summary = _jsonObject(result.stdout);
      expect(summary['kind'], 'fleuryWebThresholdReview');
      expect(summary['reviewState'], 'reviewed');
      expect(summary['reviewedBy'], 'tool reviewer');
      expect(summary['reviewedAt'], '2026-06-08T12:00:00.000Z');
      expect(
        summary['reviewContext'],
        'Chrome 127 macOS launcher test context',
      );
      expect(summary['scenarioCount'], 1);
      expect(
        _jsonObject(File(jsonOutputPath).readAsStringSync())['reviewState'],
        'reviewed',
      );

      final reviewed = _jsonObject(File(outputPath).readAsStringSync());
      expect(reviewed['kind'], 'fleuryWebFrameThresholds');
      expect(reviewed['reviewState'], 'reviewed');
      expect(reviewed['reviewedBy'], 'tool reviewer');
      expect(
        reviewed['reviewContext'],
        'Chrome 127 macOS launcher test context',
      );
      expect(reviewed['reviewNote'], 'Accepted for launcher test.');
    });

    test('writes threshold review plan without promotion provenance', () async {
      final inputPath = '${tempDir.path}/thresholds.candidate.json';
      final planPath = '${tempDir.path}/threshold-review-plan.md';
      final outputPath = '${tempDir.path}/thresholds.json';
      File(inputPath).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameThresholds',
          'generatedAt': '2026-06-08T12:00:00.000Z',
          'reviewState': 'candidate',
          'defaults': <String, Object?>{},
          'scenarios': {
            'normal-80x24': {
              'maxTotalFrameP95Ms': 20,
              'maxDomApplyP95Ms': 4,
              'maxSemanticApplyP95Ms': 8,
              'maxOverBudgetPercent': 0,
              'maxSemanticUncoveredCells': 0,
            },
          },
        }),
      );

      final result = await _runTool([
        'benchmark',
        'web-threshold-review',
        '--input=$inputPath',
        '--write-plan=$planPath',
        '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(outputPath).existsSync(), isFalse);
      final plan = File(planPath).readAsStringSync();
      expect(plan, contains('Fleury Web Threshold Review Plan'));
      expect(plan, contains('normal-80x24'));
      expect(plan, contains('--reviewed-by=<reviewer>'));
      expect(plan, contains('intentionally not runnable as written'));
      expect(
        plan,
        contains(
          'Review context hint: `Browser Chrome/127, OS macos, retained DOM product baseline`',
        ),
      );
    });

    test('writes threshold review plan with JSON summary path only', () async {
      final inputPath = '${tempDir.path}/thresholds.candidate.json';
      final planPath = '${tempDir.path}/threshold-review-plan.md';
      final outputPath = '${tempDir.path}/thresholds.json';
      final jsonOutputPath = '${tempDir.path}/threshold-review.json';
      File(inputPath).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameThresholds',
          'generatedAt': '2026-06-08T12:00:00.000Z',
          'reviewState': 'candidate',
          'defaults': <String, Object?>{},
          'scenarios': {
            'normal-80x24': {
              'maxTotalFrameP95Ms': 20,
              'maxDomApplyP95Ms': 4,
              'maxSemanticApplyP95Ms': 8,
              'maxOverBudgetPercent': 0,
              'maxSemanticUncoveredCells': 0,
            },
          },
        }),
      );

      final result = await _runTool([
        'benchmark',
        'web-threshold-review',
        '--input=$inputPath',
        '--write-plan=$planPath',
        '--json-output=$jsonOutputPath',
        '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(outputPath).existsSync(), isFalse);
      expect(File(jsonOutputPath).existsSync(), isFalse);
      final plan = File(planPath).readAsStringSync();
      expect(plan, contains('--json-output=$jsonOutputPath'));
      expect(plan, contains('--reviewed-by=<reviewer>'));
      expect(plan, contains('intentionally not runnable as written'));
    });

    test('forwards threshold review options in dry-run mode', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-threshold-review',
        '--input=${tempDir.path}/thresholds.candidate.json',
        '--write-plan=${tempDir.path}/threshold-review-plan.md',
        '--output=${tempDir.path}/thresholds.json',
        '--json-output=${tempDir.path}/threshold-review.json',
        '--reviewed-by=tool reviewer',
        '--reviewed-at=2026-06-08T12:00:00Z',
        '--review-context=Chrome 127 macOS dry-run context',
        '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
        '--expect-input-fingerprint=fnv1a64:1111111111111111',
        '--allow-over-budget-thresholds',
        '--review-note=Accepted.',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_threshold_review.dart'));
      expect(
        result.stdout,
        contains('--input=${tempDir.path}/thresholds.candidate.json'),
      );
      expect(
        result.stdout,
        contains('--output=${tempDir.path}/thresholds.json'),
      );
      expect(
        result.stdout,
        contains('--write-plan=${tempDir.path}/threshold-review-plan.md'),
      );
      expect(
        result.stdout,
        contains('--json-output=${tempDir.path}/threshold-review.json'),
      );
      expect(result.stdout, contains('--reviewed-by=tool reviewer'));
      expect(result.stdout, contains('--reviewed-at=2026-06-08T12:00:00Z'));
      expect(
        result.stdout,
        contains('--review-context=Chrome 127 macOS dry-run context'),
      );
      expect(
        result.stdout,
        contains(
          '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
        ),
      );
      expect(result.stdout, contains('--review-note=Accepted.'));
      expect(
        result.stdout,
        contains('--expect-input-fingerprint=fnv1a64:1111111111111111'),
      );
      expect(result.stdout, contains('--allow-over-budget-thresholds'));
      expect(result.stdout, contains('--json'));
    });

    test('rejects empty threshold review JSON output path', () async {
      final result = await _runTool([
        'benchmark',
        'web-threshold-review',
        '--input=${tempDir.path}/thresholds.candidate.json',
        '--output=${tempDir.path}/thresholds.json',
        '--json-output=',
        '--reviewed-by=tool reviewer',
        '--review-context=Chrome 127 macOS invalid JSON output path',
      ]);

      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains(
          'benchmark web-threshold-review --json-output requires a non-empty path.',
        ),
      );
    });

    test('rejects empty threshold review plan path', () async {
      final result = await _runTool([
        'benchmark',
        'web-threshold-review',
        '--input=${tempDir.path}/thresholds.candidate.json',
        '--write-plan=',
      ]);

      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains(
          'benchmark web-threshold-review --write-plan requires a non-empty path.',
        ),
      );
    });
  });

  group('benchmark web-semantic-audit launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_semantic_audit_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('summarizes retained DOM semantic fallback coverage', () async {
      final outputPath = '${tempDir.path}/semantic-coverage.md';
      File('${tempDir.path}/normal-80x24-a.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'fleuryWebFrameCapture',
          'capturedAt': '2026-06-08T01:00:00.000000Z',
          'scenario': {'id': 'normal-80x24'},
          'frames': [
            _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
            _webFrame(
              totalFrameMicros: 20000,
              domApplyMicros: 5000,
              semanticFallbackNodeCount: 1,
              semanticUncoveredCellCount: 4,
            ),
          ],
        }),
      );

      final jsonResult = await _runTool([
        'benchmark',
        'web-semantic-audit',
        '--input=${tempDir.path}',
        '--max-fallback-cells=4',
        '--json',
      ]);

      expect(jsonResult.exitCode, 0, reason: jsonResult.stderr.toString());
      final audit = _jsonObject(jsonResult.stdout);
      expect(audit['kind'], 'fleuryWebSemanticCoverageAudit');
      expect(audit['captureCount'], 1);
      expect(audit['frameCount'], 2);
      expect(audit['fallbackCellCount'], 4);
      final scenarios = audit['scenarios'] as List<Object?>;
      final scenario = scenarios.single as Map<String, Object?>;
      expect(scenario['id'], 'normal-80x24');
      expect(scenario['fallbackNodeCount'], 1);

      final markdownResult = await _runTool([
        'benchmark',
        'web-semantic-audit',
        '--input=${tempDir.path}',
        '--output=$outputPath',
        '--max-fallback-cells=4',
      ]);

      expect(
        markdownResult.exitCode,
        0,
        reason: markdownResult.stderr.toString(),
      );
      final markdown = File(outputPath).readAsStringSync();
      expect(markdown, contains('Fleury Web Semantic Coverage Audit'));
      expect(markdown, contains('normal-80x24'));
      expect(markdown, contains('Fallback Cells'));
    });

    test('forwards semantic fallback audit gate options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-semantic-audit',
        '--input=${tempDir.path}',
        '--max-fallback-cells=0',
        '--max-fallback-frame-percent=0',
        '--max-fallback-viewport-percent=0.5',
        '--json-output=${tempDir.path}/semantic-coverage.json',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_semantic_coverage_audit.dart'));
      expect(result.stdout, contains('--max-fallback-cells=0'));
      expect(result.stdout, contains('--max-fallback-frame-percent=0.0'));
      expect(result.stdout, contains('--max-fallback-viewport-percent=0.5'));
      expect(
        result.stdout,
        contains('--json-output=${tempDir.path}/semantic-coverage.json'),
      );
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });
  });

  group('benchmark web-manual-validation launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_manual_validation_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'generates retained DOM manual validation plan and template',
      () async {
        final planPath = '${tempDir.path}/plan.md';
        final templatePath = '${tempDir.path}/chrome-ime-macos.json';
        final templatesDir = '${tempDir.path}/templates';

        final result = await _runTool([
          'benchmark',
          'web-manual-validation',
          '--target=chrome-ime-macos',
          '--write-plan=$planPath',
          '--write-template=$templatePath',
          '--write-templates=$templatesDir',
          '--template-target=chrome-ime-macos',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final plan = File(planPath).readAsStringSync();
        expect(plan, contains('Fleury Web Manual Validation Plan'));
        expect(plan, contains('manual_validation.html'));
        final template = _jsonObject(File(templatePath).readAsStringSync());
        expect(template['kind'], 'fleuryWebManualValidationEntry');
        expect(template['targetId'], 'chrome-ime-macos');
        final batchTemplate = _jsonObject(
          File(
            '$templatesDir/chrome-ime-macos.template.json',
          ).readAsStringSync(),
        );
        expect(batchTemplate['kind'], 'fleuryWebManualValidationEntry');
        expect(batchTemplate['targetId'], 'chrome-ime-macos');
      },
    );

    test('forwards manual validation audit options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-manual-validation',
        '--input=${tempDir.path}',
        '--output=${tempDir.path}/review.md',
        '--write-plan=${tempDir.path}/plan.md',
        '--write-template=${tempDir.path}/template.json',
        '--write-starter=${tempDir.path}/starter.json',
        '--starter-template=${tempDir.path}/template.json',
        '--update-provenance=${tempDir.path}/starter.json',
        '--update-page-signal=${tempDir.path}/starter.json',
        '--update-check=${tempDir.path}/starter.json',
        '--reviewed-by=manual-reviewer',
        '--captured-at=now',
        '--browser-version=Chrome/148.0.7778.217',
        '--signal-id=retained-dom-ready',
        '--signal-status=pass',
        '--observed-value=ready',
        '--signal-notes=Observed retained DOM ready signal.',
        '--check-id=composition-end-commits-once',
        '--check-status=pass',
        '--check-notes=Observed composition commit once.',
        '--entry-status=needsReview',
        '--write-templates=${tempDir.path}/templates',
        '--template-target=chrome-voiceover-macos',
        '--json-output=${tempDir.path}/manual-validation-audit.json',
        '--target-preset=primary',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_manual_validation.dart'));
      expect(result.stdout, contains('--input=${tempDir.path}'));
      expect(result.stdout, contains('--output=${tempDir.path}/review.md'));
      expect(result.stdout, contains('--write-plan=${tempDir.path}/plan.md'));
      expect(
        result.stdout,
        contains('--write-template=${tempDir.path}/template.json'),
      );
      expect(
        result.stdout,
        contains('--write-starter=${tempDir.path}/starter.json'),
      );
      expect(
        result.stdout,
        contains('--starter-template=${tempDir.path}/template.json'),
      );
      expect(
        result.stdout,
        contains('--update-provenance=${tempDir.path}/starter.json'),
      );
      expect(
        result.stdout,
        contains('--update-page-signal=${tempDir.path}/starter.json'),
      );
      expect(
        result.stdout,
        contains('--update-check=${tempDir.path}/starter.json'),
      );
      expect(result.stdout, contains('--reviewed-by=manual-reviewer'));
      expect(result.stdout, contains('--captured-at=now'));
      expect(
        result.stdout,
        contains('--browser-version=Chrome/148.0.7778.217'),
      );
      expect(result.stdout, contains('--signal-id=retained-dom-ready'));
      expect(result.stdout, contains('--signal-status=pass'));
      expect(result.stdout, contains('--observed-value=ready'));
      expect(
        result.stdout,
        contains('--signal-notes=Observed retained DOM ready signal.'),
      );
      expect(
        result.stdout,
        contains('--check-id=composition-end-commits-once'),
      );
      expect(result.stdout, contains('--check-status=pass'));
      expect(
        result.stdout,
        contains('--check-notes=Observed composition commit once.'),
      );
      expect(result.stdout, contains('--entry-status=needsReview'));
      expect(
        result.stdout,
        contains('--write-templates=${tempDir.path}/templates'),
      );
      expect(
        result.stdout,
        contains('--template-target=chrome-voiceover-macos'),
      );
      expect(
        result.stdout,
        contains('--json-output=${tempDir.path}/manual-validation-audit.json'),
      );
      expect(result.stdout, contains('--target-preset=primary'));
      expect(result.stdout, contains('--target=chrome-ime-macos'));
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });
  });

  group('benchmark web-readiness launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_benchmark_web_readiness_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('appears in benchmark catalog', () async {
      final result = await _runTool(['benchmark', 'list', '--json']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final catalog = _jsonObject(result.stdout);
      expect(catalog, contains('webReadiness'));
      final readiness = catalog['webReadiness'] as Map<String, Object?>;
      expect(readiness['purpose'], contains('Phase 6 web readiness gate'));
      expect(catalog, contains('webReadinessBundle'));
      final bundle = catalog['webReadinessBundle'] as Map<String, Object?>;
      expect(bundle['purpose'], contains('JSON artifact manifest'));
      final bundleArtifacts = bundle['artifacts'] as List<Object?>;
      expect(bundleArtifacts, contains('web-readiness-bundle.json'));
      expect(
        bundleArtifacts,
        contains('web-default-preflight-make-dom-default.json'),
      );
      expect(
        bundleArtifacts,
        contains('web-default-preflight-retire-temporary-paths.json'),
      );
      expect(catalog, contains('webAutomatedValidation'));
      final automatedValidation =
          catalog['webAutomatedValidation'] as Map<String, Object?>;
      expect(
        automatedValidation['purpose'],
        contains(
          'durable evidence consumed by bundle-bound default preflights',
        ),
      );
      final automatedValidationCommand =
          automatedValidation['command'] as List<Object?>;
      expect(
        automatedValidationCommand,
        contains(
          '--json-output=profiling/web/baselines/web-readiness-bundle/web-automated-validation.json',
        ),
      );
      expect(catalog, contains('webDefaultPreflight'));
      final preflight = catalog['webDefaultPreflight'] as Map<String, Object?>;
      expect(preflight['purpose'], contains('temporary-path retirement'));
      final preflightCommand = preflight['command'] as List<Object?>;
      expect(
        preflightCommand,
        contains(
          '--bundle=profiling/web/baselines/web-readiness-bundle/web-readiness-bundle.json',
        ),
      );
      expect(
        preflightCommand,
        contains(
          '--automated-validation=profiling/web/baselines/web-readiness-bundle/web-automated-validation.json',
        ),
      );
      expect(catalog, contains('webThresholdReview'));
      final thresholdReview =
          catalog['webThresholdReview'] as Map<String, Object?>;
      expect(thresholdReview['purpose'], contains('promote candidate'));
      final thresholdReviewCommand =
          thresholdReview['command'] as List<Object?>;
      expect(thresholdReviewCommand, contains('--reviewed-by=REVIEWER'));
      expect(
        thresholdReviewCommand,
        contains('--expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN'),
      );
      expect(
        thresholdReviewCommand,
        contains('--allow-over-budget-thresholds'),
      );
      expect(
        thresholdReviewCommand,
        contains('--review-note=Explain any accepted over-budget thresholds.'),
      );
      expect(
        thresholdReviewCommand,
        contains(
          '--review-context=Chrome VERSION on PLATFORM, retained DOM product baseline',
        ),
      );
      expect(
        thresholdReviewCommand,
        isNot(contains('--reviewed-by=<reviewer>')),
      );
      final thresholdReviewPlanCommand =
          thresholdReview['planCommand'] as List<Object?>;
      expect(
        thresholdReviewPlanCommand,
        isNot(contains(startsWith('--review-context-hint='))),
      );
      final thresholdReviewArtifacts =
          thresholdReview['artifacts'] as List<Object?>;
      expect(thresholdReviewArtifacts, contains('threshold-review.json'));
    });

    test('prints release-grade benchmark help examples', () async {
      final result = await _runTool(['benchmark', '--help']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('--reviewed-by=REVIEWER'));
      expect(result.stdout, contains('--allow-over-budget-thresholds'));
      expect(result.stdout, contains('Chrome VERSION on PLATFORM'));
      expect(result.stdout, isNot(contains('--reviewed-by=<reviewer>')));
      expect(
        result.stdout,
        contains(
          '--thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json',
        ),
      );
      expect(
        result.stdout,
        contains(
          '--threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json',
        ),
      );
      expect(
        result.stdout,
        contains(
          '--bundle=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json',
        ),
      );
      expect(
        result.stdout,
        contains(
          '--json-output=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-automated-validation.json',
        ),
      );
      expect(
        result.stdout,
        contains(
          '--automated-validation=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-automated-validation.json',
        ),
      );
    });

    test('forwards readiness audit artifact options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-readiness',
        '--scoreboard=${tempDir.path}/scoreboard.json',
        '--semantic-audit=${tempDir.path}/semantic.json',
        '--manual-audit=${tempDir.path}/manual.json',
        '--threshold-review=${tempDir.path}/threshold-review.json',
        '--output=${tempDir.path}/readiness.md',
        '--json-output=${tempDir.path}/readiness.json',
        '--min-scoreboard-runs=5',
        '--no-require-comparable-environment',
        '--no-require-scoreboard-gates',
        '--no-require-total-frame-gate',
        '--no-require-semantic-gates',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_readiness.dart'));
      expect(
        result.stdout,
        contains('--scoreboard=${tempDir.path}/scoreboard.json'),
      );
      expect(
        result.stdout,
        contains('--semantic-audit=${tempDir.path}/semantic.json'),
      );
      expect(
        result.stdout,
        contains('--manual-audit=${tempDir.path}/manual.json'),
      );
      expect(
        result.stdout,
        contains('--threshold-review=${tempDir.path}/threshold-review.json'),
      );
      expect(result.stdout, contains('--output=${tempDir.path}/readiness.md'));
      expect(
        result.stdout,
        contains('--json-output=${tempDir.path}/readiness.json'),
      );
      expect(result.stdout, contains('--min-scoreboard-runs=5'));
      expect(result.stdout, contains('--no-require-comparable-environment'));
      expect(result.stdout, contains('--no-require-scoreboard-gates'));
      expect(result.stdout, contains('--no-require-total-frame-gate'));
      expect(result.stdout, contains('--no-require-semantic-gates'));
      expect(result.stdout, contains('--no-require-reviewed-threshold-policy'));
      expect(result.stdout, contains('--no-require-threshold-review-summary'));
      expect(result.stdout, contains('--no-require-scenario-thresholds'));
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });

    test('forwards readiness bundle options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-readiness-bundle',
        '--captures=${tempDir.path}/captures',
        '--manual=${tempDir.path}/manual',
        '--output-dir=${tempDir.path}/bundle',
        '--min-runs=5',
        '--max-total-frame-p95-ms=16.67',
        '--max-dom-apply-p95-ms=8',
        '--max-semantic-apply-p95-ms=4',
        '--max-over-budget-percent=1',
        '--max-semantic-uncovered-cells=0',
        '--thresholds=${tempDir.path}/thresholds.json',
        '--threshold-review=${tempDir.path}/threshold-review.json',
        '--no-require-comparable-environment',
        '--max-fallback-cells=0',
        '--max-fallback-frame-percent=0',
        '--max-fallback-viewport-percent=0',
        '--target-preset=v1',
        '--target=chrome-ime-macos',
        '--no-require-scoreboard-gates',
        '--no-require-total-frame-gate',
        '--no-require-semantic-gates',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--write-default-preflights',
        '--completion-audit=${tempDir.path}/completion-audit.json',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_readiness_bundle.dart'));
      expect(result.stdout, contains('--captures=${tempDir.path}/captures'));
      expect(result.stdout, contains('--manual=${tempDir.path}/manual'));
      expect(result.stdout, contains('--output-dir=${tempDir.path}/bundle'));
      expect(result.stdout, contains('--min-runs=5'));
      expect(result.stdout, contains('--max-total-frame-p95-ms=16.67'));
      expect(result.stdout, contains('--max-dom-apply-p95-ms=8.0'));
      expect(result.stdout, contains('--max-semantic-apply-p95-ms=4.0'));
      expect(result.stdout, contains('--max-over-budget-percent=1.0'));
      expect(result.stdout, contains('--max-semantic-uncovered-cells=0.0'));
      expect(
        result.stdout,
        contains('--thresholds=${tempDir.path}/thresholds.json'),
      );
      expect(
        result.stdout,
        contains('--threshold-review=${tempDir.path}/threshold-review.json'),
      );
      expect(result.stdout, contains('--no-require-comparable-environment'));
      expect(result.stdout, contains('--max-fallback-cells=0'));
      expect(result.stdout, contains('--max-fallback-frame-percent=0.0'));
      expect(result.stdout, contains('--max-fallback-viewport-percent=0.0'));
      expect(result.stdout, contains('--target-preset=v1'));
      expect(result.stdout, contains('--target=chrome-ime-macos'));
      expect(result.stdout, contains('--no-require-scoreboard-gates'));
      expect(result.stdout, contains('--no-require-total-frame-gate'));
      expect(result.stdout, contains('--no-require-semantic-gates'));
      expect(result.stdout, contains('--no-require-reviewed-threshold-policy'));
      expect(result.stdout, contains('--no-require-threshold-review-summary'));
      expect(result.stdout, contains('--no-require-scenario-thresholds'));
      expect(result.stdout, contains('--write-default-preflights'));
      expect(
        result.stdout,
        contains('--completion-audit=${tempDir.path}/completion-audit.json'),
      );
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });

    test('forwards readiness bundle verification options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-readiness-bundle',
        '--verify=${tempDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_readiness_bundle.dart'));
      expect(
        result.stdout,
        contains('--verify=${tempDir.path}/web-readiness-bundle.json'),
      );
      expect(result.stdout, isNot(contains('--captures=')));
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });

    test('forwards automated validation options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-automated-validation',
        '--json-output=${tempDir.path}/web-automated-validation.json',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_automated_validation.dart'));
      expect(
        result.stdout,
        contains('--json-output=${tempDir.path}/web-automated-validation.json'),
      );
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });

    test('forwards default preflight options', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-default-preflight',
        '--readiness=${tempDir.path}/web-readiness.json',
        '--bundle=${tempDir.path}/web-readiness-bundle.json',
        '--automated-validation=${tempDir.path}/web-automated-validation.json',
        '--target=retire-temporary-paths',
        '--output=${tempDir.path}/preflight.md',
        '--json-output=${tempDir.path}/preflight.json',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_default_preflight.dart'));
      expect(
        result.stdout,
        contains('--readiness=${tempDir.path}/web-readiness.json'),
      );
      expect(
        result.stdout,
        contains('--bundle=${tempDir.path}/web-readiness-bundle.json'),
      );
      expect(
        result.stdout,
        contains(
          '--automated-validation=${tempDir.path}/web-automated-validation.json',
        ),
      );
      expect(result.stdout, contains('--target=retire-temporary-paths'));
      expect(result.stdout, contains('--output=${tempDir.path}/preflight.md'));
      expect(
        result.stdout,
        contains('--json-output=${tempDir.path}/preflight.json'),
      );
      expect(result.stdout, contains('--strict'));
      expect(result.stdout, contains('--json'));
    });

    test('forwards default preflight diagnostics mode', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-default-preflight',
        '--readiness=${tempDir.path}/web-readiness.json',
        '--allow-unbundled',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_default_preflight.dart'));
      expect(
        result.stdout,
        contains('--readiness=${tempDir.path}/web-readiness.json'),
      );
      expect(result.stdout, contains('--allow-unbundled'));
      expect(result.stdout, isNot(contains('--bundle=')));
      expect(result.stdout, isNot(contains('--automated-validation=')));
      expect(result.stdout, contains('--json'));
    });

    test('infers sibling default preflight bundle', () async {
      final result = await _runTool([
        '--dry-run',
        'benchmark',
        'web-default-preflight',
        '--readiness=${tempDir.path}/web-readiness.json',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('tool/web_default_preflight.dart'));
      expect(
        result.stdout,
        contains('--readiness=${tempDir.path}/web-readiness.json'),
      );
      expect(
        result.stdout,
        contains('--bundle=${tempDir.path}/web-readiness-bundle.json'),
      );
      expect(
        result.stdout,
        contains(
          '--automated-validation=${tempDir.path}/web-automated-validation.json',
        ),
      );
      expect(result.stdout, contains('--json'));
    });
  });

  group('terminal-matrix-audit launcher', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'fleury_terminal_matrix_tool_test_',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'matches clean target labels without context-label bleedthrough',
      () async {
        _writeEntry(tempDir, 'iterm2.json', _matrixEntry(label: 'iterm2-3-5'));
        _writeEntry(
          tempDir,
          'tmux-kitty.json',
          _matrixEntry(label: 'tmux-kitty'),
        );

        final result = await _runTool([
          'terminal-matrix-audit',
          '--input=${tempDir.path}',
          '--target=iterm2',
          '--target=kitty',
          '--target=tmux',
          '--json',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final audit = _jsonObject(result.stdout);
        expect(audit['kind'], 'fleuryTerminalMatrixAudit');
        expect(audit['targetCount'], 3);
        expect(audit['readyTargetCount'], 2);
        expect(audit['missingTargets'], ['kitty']);
        expect(audit['strictPass'], isFalse);

        final targets = _targetReports(audit);
        expect(targets['iterm2']!['covered'], isTrue);
        expect(targets['iterm2']!['readyEntryCount'], 1);
        expect(targets['iterm2']!['nonReadyEntryCount'], 0);
        expect(targets['iterm2']!['nextAction'], 'complete');
        expect(
          _matchedLabels(targets['iterm2']!),
          containsPair('iterm2-3-5', 'targetPrefix'),
        );
        expect(targets['tmux']!['covered'], isTrue);
        expect(targets['tmux']!['nextAction'], 'complete');
        expect(
          _matchedLabels(targets['tmux']!),
          containsPair('tmux-kitty', 'contextToken'),
        );
        expect(targets['kitty']!['covered'], isFalse);
        expect(targets['kitty']!['readyEntryCount'], 0);
        expect(targets['kitty']!['nonReadyEntryCount'], 0);
        expect(targets['kitty']!['nextAction'], 'capture');
        expect(_matchedLabels(targets['kitty']!), isEmpty);
        expect(targets['kitty']!['suggestedCaptureCommand'], [
          'dart',
          'tool/fleury_dev.dart',
          'terminal-matrix',
          '--label=kitty',
        ]);
      },
    );

    test('strict mode fails for invalid entries and missing targets', () async {
      _writeEntry(
        tempDir,
        'wezterm.json',
        _matrixEntry(
          label: 'wezterm-nightly',
          reviewStatus: 'needsAttention',
          reviewIssues: ['kittyGraphics passive support was not confirmed'],
        ),
      );
      File('${tempDir.path}/broken.json').writeAsStringSync('{not-json');

      final result = await _runTool([
        'terminal-matrix-audit',
        '--input=${tempDir.path}',
        '--target=wezterm',
        '--target=ghostty',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final audit = _jsonObject(result.stdout);
      expect(audit['entryCount'], 1);
      expect(audit['invalidEntryCount'], 1);
      expect(audit['missingTargets'], ['wezterm', 'ghostty']);
      expect(audit['targetsNeedingReview'], ['wezterm']);
      expect(audit['nonReadyTargetCount'], 1);
      expect(audit['strictPass'], isFalse);

      final targets = _targetReports(audit);
      expect(targets['wezterm']!['covered'], isFalse);
      expect(targets['wezterm']!['readyEntryCount'], 0);
      expect(targets['wezterm']!['nonReadyEntryCount'], 1);
      expect(targets['wezterm']!['nonReadyReviewStatuses'], ['needsAttention']);
      expect(targets['wezterm']!['nextAction'], 'review-or-recapture');
      expect(targets['ghostty']!['nextAction'], 'capture');

      final invalidEntries = audit['invalidEntries'];
      expect(invalidEntries, isA<List<Object?>>());
      expect(invalidEntries as List<Object?>, hasLength(1));
      expect(
        invalidEntries.single as Map<String, Object?>,
        containsPair('path', contains('broken.json')),
      );
    });

    test('accepted reviewed entries satisfy strict target coverage', () async {
      _writeEntry(
        tempDir,
        'wezterm.json',
        _matrixEntry(
          label: 'wezterm-nightly',
          reviewStatus: 'needsAttention',
          reviewIssues: ['kittyGraphics passive support was not confirmed'],
        ),
      );

      final before = await _runTool([
        'terminal-matrix-audit',
        '--input=${tempDir.path}',
        '--target=wezterm',
        '--strict',
        '--json',
      ]);
      expect(before.exitCode, 1);

      final accept = await _runTool([
        'terminal-matrix-accept',
        '--input=${tempDir.path}',
        '--label=wezterm-nightly',
        '--accepted-by=QA',
        '--note=Reviewed passive mismatch against probe behavior',
      ]);
      expect(accept.exitCode, 0, reason: accept.stderr.toString());
      expect(accept.stdout, contains('Accepted wezterm-nightly'));

      final entry = _jsonObject(
        File('${tempDir.path}/wezterm.json').readAsStringSync(),
      );
      final review = entry['review'] as Map<String, Object?>;
      expect(review['status'], 'acceptedForLaunch');
      expect(review['previousStatus'], 'needsAttention');
      expect(review['acceptedBy'], 'QA');
      expect(
        review['acceptanceNotes'] as List<Object?>,
        contains('Reviewed passive mismatch against probe behavior'),
      );
      expect(
        review['issues'] as List<Object?>,
        contains('kittyGraphics passive support was not confirmed'),
      );

      final after = await _runTool([
        'terminal-matrix-audit',
        '--input=${tempDir.path}',
        '--target=wezterm',
        '--strict',
        '--json',
      ]);
      expect(after.exitCode, 0, reason: after.stderr.toString());
      final audit = _jsonObject(after.stdout);
      expect(audit['readyTargetCount'], 1);
      expect(audit['strictPass'], isTrue);
      final targets = _targetReports(audit);
      expect(targets['wezterm']!['covered'], isTrue);
      expect(targets['wezterm']!['readyEntryCount'], 1);
      expect(targets['wezterm']!['nonReadyEntryCount'], 0);
    });

    test(
      'accept command refuses nonInteractive entries without override',
      () async {
        _writeEntry(
          tempDir,
          'pipe.json',
          _matrixEntry(
            label: 'ci-pipe-control',
            reviewStatus: 'nonInteractive',
            reviewIssues: ['stdin/stdout are not both terminals'],
          ),
        );

        final result = await _runTool([
          'terminal-matrix-accept',
          '--input=${tempDir.path}',
          '--label=ci-pipe-control',
          '--note=Control evidence only',
        ]);

        expect(result.exitCode, 2);
        expect(
          result.stderr,
          contains('Refusing to accept nonInteractive entry'),
        );
      },
    );

    test('writes markdown collection plan from audit state', () async {
      _writeEntry(tempDir, 'iterm2.json', _matrixEntry(label: 'iterm2-3-5'));
      _writeEntry(
        tempDir,
        'wezterm.json',
        _matrixEntry(
          label: 'wezterm-nightly',
          reviewStatus: 'needsAttention',
          reviewIssues: ['kittyGraphics passive support was not confirmed'],
        ),
      );
      final planPath = '${tempDir.path}/collection-plan.md';

      final result = await _runTool([
        'terminal-matrix-audit',
        '--input=${tempDir.path}',
        '--target=iterm2',
        '--target=wezterm',
        '--target=ghostty',
        '--write-plan=$planPath',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit = _jsonObject(result.stdout);
      expect(audit['readyTargetCount'], 1);
      expect(audit['targetsNeedingReview'], ['wezterm']);

      final plan = File(planPath).readAsStringSync();
      expect(plan, contains('# Terminal Matrix Collection Plan'));
      expect(plan, contains('**Targets ready:** 1/3'));
      expect(plan, contains('### iterm2'));
      expect(plan, contains('- Next action: complete'));
      expect(plan, contains('### wezterm'));
      expect(plan, contains('- Next action: review-or-recapture'));
      expect(
        plan,
        contains('dart tool/fleury_dev.dart terminal-matrix --label=wezterm'),
      );
      expect(plan, contains('### ghostty'));
      expect(plan, contains('- Next action: capture'));
      expect(
        plan,
        contains('dart tool/fleury_dev.dart terminal-matrix --label=ghostty'),
      );
    });

    test('writes markdown review packet from audit state', () async {
      _writeEntry(tempDir, 'iterm2.json', _matrixEntry(label: 'iterm2-3-5'));
      _writeEntry(
        tempDir,
        'wezterm.json',
        _matrixEntry(
          label: 'wezterm-nightly',
          reviewStatus: 'needsAttention',
          reviewIssues: ['kittyGraphics passive support was not confirmed'],
          reviewNotes: ['Captured with default profile'],
        ),
      );
      _writeEntry(
        tempDir,
        'ci-pipe-control.json',
        _matrixEntry(
          label: 'ci-pipe-control',
          reviewStatus: 'nonInteractive',
          reviewIssues: ['stdin/stdout are not both terminals'],
        ),
      );
      final reviewPath = '${tempDir.path}/review-packet.md';

      final result = await _runTool([
        'terminal-matrix-audit',
        '--input=${tempDir.path}',
        '--target=iterm2',
        '--target=wezterm',
        '--target=ghostty',
        '--write-review=$reviewPath',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit = _jsonObject(result.stdout);
      expect(audit['readyTargetCount'], 1);
      expect(audit['targetsNeedingReview'], ['wezterm']);

      final review = File(reviewPath).readAsStringSync();
      expect(review, contains('# Terminal Matrix Review Packet'));
      expect(review, contains('**Targets ready:** 1/3'));
      expect(review, contains('### iterm2'));
      expect(
        review,
        contains('- [ ] `iterm2-3-5` (`readyForReview`, targetPrefix)'),
      );
      expect(review, contains('### wezterm'));
      expect(review, contains('- Next action: review-or-recapture'));
      expect(
        review,
        contains('- [ ] `wezterm-nightly` (`needsAttention`, targetPrefix)'),
      );
      expect(
        review,
        contains('- kittyGraphics passive support was not confirmed'),
      );
      expect(review, contains('- Captured with default profile'));
      expect(review, contains('### ghostty'));
      expect(
        review,
        contains(
          'Capture: `dart tool/fleury_dev.dart terminal-matrix --label=ghostty`',
        ),
      );
      expect(review, contains('## Unmatched Entries'));
      expect(review, contains('- [ ] `ci-pipe-control` (`nonInteractive`)'));
    });

    test('windows target preset expands validation targets', () async {
      final planPath = '${tempDir.path}/windows-plan.md';
      final reviewPath = '${tempDir.path}/windows-review.md';

      final result = await _runTool([
        'terminal-matrix-audit',
        '--input=${tempDir.path}',
        '--target-preset=windows',
        '--write-plan=$planPath',
        '--write-review=$reviewPath',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit = _jsonObject(result.stdout);
      expect(audit['targetCount'], 4);
      expect(audit['readyTargetCount'], 0);
      expect(audit['missingTargets'], [
        'windows-terminal',
        'windows-conhost',
        'windows-powershell',
        'windows-ide',
      ]);

      final targets = _targetReports(audit);
      expect(
        targets['windows-terminal']!['collectionNote'],
        contains('real Windows host inside Windows Terminal'),
      );
      expect(
        targets['windows-conhost']!['collectionNote'],
        contains('classic Windows Console Host'),
      );
      expect(
        targets['windows-powershell']!['collectionNote'],
        contains('PowerShell host on Windows'),
      );
      expect(
        targets['windows-ide']!['collectionNote'],
        contains('Windows IDE integrated terminal'),
      );

      final plan = File(planPath).readAsStringSync();
      expect(plan, contains('### windows-conhost'));
      expect(plan, contains('### windows-powershell'));
      expect(plan, contains('### windows-ide'));
      expect(
        plan,
        contains(
          'dart tool/fleury_dev.dart terminal-matrix --label=windows-conhost',
        ),
      );

      final review = File(reviewPath).readAsStringSync();
      expect(review, contains('# Terminal Matrix Review Packet'));
      expect(review, contains('### windows-terminal'));
      expect(review, contains('### windows-conhost'));
      expect(review, contains('### windows-powershell'));
      expect(review, contains('### windows-ide'));
    });

    test('capture command preserves reviewer notes', () async {
      final outputPath = '${tempDir.path}/noted-entry.json';

      final result = await _runTool([
        'terminal-matrix',
        '--label=ci-pipe-control',
        '--output=$outputPath',
        '--no-probe',
        '--review-note=Captured from CI pipe as a control entry',
        '--review-note=Use only for non-interactive degradation review',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final entry = _jsonObject(File(outputPath).readAsStringSync());
      expect(entry['label'], 'ci-pipe-control');
      final review = entry['review'] as Map<String, Object?>;
      expect(review['status'], 'nonInteractive');
      expect(review['notes'], [
        'Captured from CI pipe as a control entry',
        'Use only for non-interactive degradation review',
      ]);
      expect(
        review['issues'] as List<Object?>,
        contains('stdin/stdout are not both terminals'),
      );
    });

    test(
      'mvp-readiness strict mode fails until external evidence is ready',
      () async {
        final reportPath = '${tempDir.path}/mvp-readiness.md';

        final result = await _runTool([
          'mvp-readiness',
          '--input=${tempDir.path}',
          '--write-report=$reportPath',
          '--strict',
          '--json',
        ]);

        expect(result.exitCode, 1);
        final readiness = _jsonObject(result.stdout);
        expect(readiness['kind'], 'fleuryMvpReadinessAudit');
        expect(readiness['strictPass'], isFalse);
        expect(
          readiness['remainingBlockers'] as List<Object?>,
          contains(contains('M2.10 reviewed real-terminal matrix coverage')),
        );
        expect(
          readiness['remainingBlockers'] as List<Object?>,
          isNot(contains(contains('M2.9 reviewed real Windows validation'))),
        );

        final report = File(reportPath).readAsStringSync();
        expect(report, contains('# Fleury MVP Readiness Audit'));
        expect(report, contains('**Strict pass:** false'));
        expect(report, contains('Launch terminal strict gate'));
        expect(report, contains('Windows validation MVP status:** deferred'));
        expect(report, contains('Post-MVP Windows Validation'));
      },
    );

    test(
      'mvp-readiness strict mode passes when MVP launch targets pass',
      () async {
        const launchTargets = <String>['macos-terminal', 'tmux-terminal'];
        var index = 0;
        for (final target in launchTargets) {
          _writeEntry(
            tempDir,
            'entry-${index++}-$target.json',
            _matrixEntry(label: target),
          );
        }
        final reportPath = '${tempDir.path}/mvp-readiness-pass.md';

        final result = await _runTool([
          'mvp-readiness',
          '--input=${tempDir.path}',
          '--write-report=$reportPath',
          '--strict',
          '--json',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final readiness = _jsonObject(result.stdout);
        expect(readiness['strictPass'], isTrue);
        expect(readiness['remainingBlockers'], isEmpty);
        expect(
          (readiness['launchTerminalEvidence']
              as Map<String, Object?>)['readyTargetCount'],
          2,
        );
        final windows =
            readiness['windowsValidationEvidence'] as Map<String, Object?>;
        expect(windows['readyTargetCount'], 0);
        expect(windows['requiredForMvp'], isFalse);
        expect(windows['mvpStatus'], 'deferred');
        expect(
          readiness['deferredOutOfMvp'] as List<Object?>,
          contains(contains('real Windows validation across Windows Terminal')),
        );
        expect(
          readiness['deferredOutOfMvp'] as List<Object?>,
          contains(contains('extended terminal matrix coverage')),
        );

        final report = File(reportPath).readAsStringSync();
        expect(report, contains('**Strict pass:** true'));
        expect(report, contains('- None.'));
        expect(report, contains('Local RC gate'));
      },
    );

    test('mvp-final-gate dry-run shows local and external gates', () async {
      final result = await _runTool([
        '--dry-run',
        'mvp-final-gate',
        '--quick',
        '--write-report=${tempDir.path}/mvp-readiness.md',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout,
        contains('run local RC gate: dart tool/fleury_dev.dart check --quick'),
      );
      expect(
        result.stdout,
        contains('scan docs/implementation/terminal-matrix'),
      );
      expect(result.stdout, contains('write '));
      expect(result.stdout, contains('enforce MVP external evidence'));
    });

    test(
      'mvp-final-gate fails external evidence after skipped local gate',
      () async {
        final reportPath = '${tempDir.path}/final-gate-fail.md';

        final result = await _runTool([
          'mvp-final-gate',
          '--skip-local',
          '--input=${tempDir.path}',
          '--write-report=$reportPath',
        ]);

        expect(result.exitCode, 1);
        expect(
          result.stdout,
          contains('Skipping local RC gate (--skip-local).'),
        );
        expect(result.stdout, contains('Fleury MVP readiness: not ready'));
        expect(result.stdout, contains('M2.10 reviewed real-terminal matrix'));
        expect(
          File(reportPath).readAsStringSync(),
          contains('**Strict pass:** false'),
        );
      },
    );

    test(
      'mvp-final-gate passes with skipped local and complete fixture evidence',
      () async {
        const launchTargets = <String>['macos-terminal', 'tmux-terminal'];
        var index = 0;
        for (final target in launchTargets) {
          _writeEntry(
            tempDir,
            'entry-${index++}-$target.json',
            _matrixEntry(label: target),
          );
        }
        final reportPath = '${tempDir.path}/final-gate-pass.md';

        final result = await _runTool([
          'mvp-final-gate',
          '--skip-local',
          '--input=${tempDir.path}',
          '--write-report=$reportPath',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          result.stdout,
          contains('Skipping local RC gate (--skip-local).'),
        );
        expect(result.stdout, contains('Fleury MVP readiness: ready'));
        expect(result.stdout, contains('MVP final gate passed.'));
        expect(
          File(reportPath).readAsStringSync(),
          contains('**Strict pass:** true'),
        );
        expect(
          File(reportPath).readAsStringSync(),
          contains('Windows validation MVP status:** deferred'),
        );
      },
    );

    test(
      'mvp-evidence-refresh writes all generated evidence artifacts',
      () async {
        final outputDir = Directory('${tempDir.path}/generated');

        final result = await _runTool([
          'mvp-evidence-refresh',
          '--input=${tempDir.path}',
          '--output-dir=${outputDir.path}',
        ]);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          result.stdout,
          contains(
            'MVP evidence: launch 0/2 ready, post-MVP windows 0/4 ready.',
          ),
        );
        for (final name in [
          'terminal-matrix-collection-plan.md',
          'terminal-matrix-review-packet.md',
          'windows-validation-plan.md',
          'windows-validation-review-packet.md',
          'mvp-readiness-report.md',
        ]) {
          expect(File('${outputDir.path}/$name').existsSync(), isTrue);
        }
        expect(
          File('${outputDir.path}/mvp-readiness-report.md').readAsStringSync(),
          contains('**Strict pass:** false'),
        );
        expect(
          File(
            '${outputDir.path}/windows-validation-plan.md',
          ).readAsStringSync(),
          contains('### windows-conhost'),
        );
      },
    );

    test(
      'mvp-evidence-refresh strict mode fails when evidence is missing',
      () async {
        final outputDir = Directory('${tempDir.path}/strict-generated');

        final result = await _runTool([
          'mvp-evidence-refresh',
          '--input=${tempDir.path}',
          '--output-dir=${outputDir.path}',
          '--strict',
        ]);

        expect(result.exitCode, 1);
        expect(
          File('${outputDir.path}/mvp-readiness-report.md').existsSync(),
          isTrue,
        );
      },
    );
  });
}

Future<ProcessResult> _runTool(List<String> args) {
  return Process.run(Platform.resolvedExecutable, <String>[
    '../../tool/fleury_dev.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

Map<String, Object?> _jsonObject(Object? source) {
  final decoded = jsonDecode(source.toString());
  expect(decoded, isA<Map<String, Object?>>());
  return decoded as Map<String, Object?>;
}

void _writeEntry(Directory directory, String name, Map<String, Object?> entry) {
  const encoder = JsonEncoder.withIndent('  ');
  File(
    '${directory.path}/$name',
  ).writeAsStringSync('${encoder.convert(entry)}\n');
}

Map<String, Object?> _webFrame({
  required int totalFrameMicros,
  required int domApplyMicros,
  int dirtyRowDiffMicros = 0,
  int semanticFallbackNodeCount = 0,
  int semanticUncoveredCellCount = 0,
}) {
  return <String, Object?>{
    'reason': 'benchmark',
    'coalescedReasons': ['benchmark'],
    'viewport': {'cols': 120, 'rows': 32},
    'damageSource': 'paintDamage',
    'fullRepaint': false,
    'metricsChanged': false,
    'dirtyRowCount': 4,
    'dirtyCellEstimate': 480,
    'spanCount': 20,
    'domNodesCreated': 24,
    'rowsReplaced': 4,
    'styleCacheHits': 10,
    'styleCacheMisses': 2,
    'widthCacheHits': 0,
    'widthCacheMisses': 0,
    'metricsReadCount': 1,
    'semanticNodeCount': 8,
    'semanticAddedNodeCount': 1,
    'semanticRemovedNodeCount': 0,
    'semanticUpdatedNodeCount': 2,
    'semanticFallbackNodeCount': semanticFallbackNodeCount,
    'semanticUncoveredCellCount': semanticUncoveredCellCount,
    'runtimeRenderMicros': 3000,
    'dirtyRowDiffMicros': dirtyRowDiffMicros,
    'spanBuildMicros': 1000,
    'domApplyMicros': domApplyMicros,
    'semanticApplyMicros': 1000,
    'totalFrameMicros': totalFrameMicros,
  };
}

Map<String, Object?> _matrixEntry({
  required String label,
  String reviewStatus = 'readyForReview',
  List<String> reviewIssues = const <String>[],
  List<String> reviewNotes = const <String>[],
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryTerminalMatrixEntry',
    'label': label,
    'capturedAt': '2026-06-01T00:00:00.000000Z',
    'command': <String>[
      'dart',
      'run',
      'bin/fleury.dart',
      'diagnose',
      '--json-output=<matrix-diagnosis-json>',
      '--probe',
    ],
    'summary': <String, Object?>{
      'platform': <String, Object?>{
        'operatingSystem': 'macos',
        'operatingSystemVersion': '15.5',
        'dartVersion': Platform.version,
      },
      'terminal': <String, Object?>{
        'term': 'xterm-256color',
        'termProgram': 'fixture',
        'termProgramVersion': '1.0',
        'columns': 100,
        'rows': 40,
        'isInteractive': true,
        'stdinIsTerminal': true,
        'stdoutIsTerminal': true,
        'tmux': label.startsWith('tmux-'),
        'ssh': label.startsWith('ssh-'),
      },
      'diagnostics': <String, Object?>{
        'fallbackCount': 0,
        'warningCount': 0,
        'unsupportedFeatureCount': 0,
        'fallbackCodes': <Object?>[],
        'warningCodes': <Object?>[],
        'unsupportedFeatures': <Object?>[],
      },
      'activeProbes': <String, Object?>{
        'summary': <String, Object?>{
          'confirmed': 3,
          'unsupported': 0,
          'skipped': 0,
          'timeout': 0,
          'error': 0,
        },
        'probeStatuses': <String, Object?>{
          'primaryDeviceAttributes': 'confirmed',
          'kittyKeyboardStatus': 'confirmed',
          'kittyGraphicsQuery': 'confirmed',
        },
      },
      'compatibility': <String, Object?>{
        'summary': <String, Object?>{
          'confirmed': 2,
          'activeConfirmed': 0,
          'passiveUnverified': 0,
          'unsupported': 0,
          'inconclusive': 0,
        },
      },
    },
    'review': <String, Object?>{
      'status': reviewStatus,
      'issues': reviewIssues,
      'notes': reviewNotes,
    },
    'diagnosis': <String, Object?>{},
  };
}

Map<String, Object?> _peerRun({
  String runId = 'bubbletea-sb1-local-fixture',
  int firstFrameUsP95 = 1000,
  int commandToFrameUsP95 = 1500,
  int semanticOrTestQueryUsP95 = 900,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryPeerBenchmarkRun',
    'runId': runId,
    'peerId': 'bubbletea',
    'scenarioId': 'SB.1',
    'capturedAt': '2026-06-01T00:00:00.000000Z',
    'source': <String, Object?>{
      'name': 'Bubble Tea',
      'version': '1.3.6',
      'url': 'https://github.com/charmbracelet/bubbletea',
    },
    'environment': <String, Object?>{
      'machine': 'local-test-fixture',
      'operatingSystem': 'macos',
      'runtime': Platform.version,
      'terminalMode': 'test-harness',
      'terminalSize': <String, Object?>{'columns': 80, 'rows': 24},
    },
    'fixture': <String, Object?>{
      'workingDirectory': 'peer-fixtures/bubbletea/sb1_counter',
      'command': <String>['go', 'test', './...'],
      'warmupIterations': 2,
      'measuredIterations': 20,
    },
    'metrics': <String, Object?>{
      'firstFrameUs': <String, Object?>{'p95': firstFrameUsP95, 'samples': 20},
      'commandToFrameUs': <String, Object?>{
        'p95': commandToFrameUsP95,
        'samples': 20,
      },
      'semanticOrTestQueryUs': <String, Object?>{
        'p95': semanticOrTestQueryUsP95,
        'samples': 20,
      },
      'rssDeltaBytes': 4096,
      'lineOfCodeCount': 42,
      'testLineOfCodeCount': 24,
    },
    'correctness': <Object?>[
      <String, Object?>{'gate': 'counter text updates correctly', 'pass': true},
      <String, Object?>{
        'gate': 'input/action path matches normal app use',
        'pass': true,
      },
      <String, Object?>{'gate': 'test shape is documented', 'pass': true},
    ],
    'ergonomics': <String, Object?>{
      'lineOfCodeCount': 42,
      'testLineOfCodeCount': 24,
      'notes': <String>['fixture only; not real peer evidence'],
    },
    'notes': <String>['fixture generated by launcher test'],
  };
}

Map<String, Map<String, Object?>> _targetReports(Map<String, Object?> audit) {
  final reports = <String, Map<String, Object?>>{};
  for (final target in audit['targets'] as List<Object?>) {
    final targetMap = target as Map<String, Object?>;
    reports[targetMap['target']! as String] = targetMap;
  }
  return reports;
}

Map<String, String> _matchedLabels(Map<String, Object?> target) {
  return <String, String>{
    for (final match in target['matchedEntries'] as List<Object?>)
      (match as Map<String, Object?>)['label']! as String:
          match['matchKind']! as String,
  };
}
