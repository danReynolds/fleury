@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_frame_suite_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'web frame suite dry-run plans repeated captures and scoreboard',
    () async {
      final scoreboardPath = '${tempDir.path}/scoreboard.md';
      final scoreboardJsonPath = '${tempDir.path}/scoreboard.json';
      final thresholdsPath = '${tempDir.path}/thresholds.json';
      final candidateThresholdsPath =
          '${tempDir.path}/candidate-thresholds.json';
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_suite.dart',
        '--scenarios=normal-80x24,single-dirty-cell-160x50',
        '--runs=2',
        '--frames=3',
        '--warmup=0',
        '--budget-ms=8',
        '--output-dir=${tempDir.path}',
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
        '--headful',
        '--keep-temp',
        '--dry-run',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final plan = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(plan['kind'], 'fleuryWebFrameSuitePlan');
      expect(plan['scenarioCount'], 2);
      expect(plan['plannedCaptureCount'], 4);
      expect(plan['runsPerScenario'], 2);
      expect(plan['minRuns'], 2);
      expect(plan['strictScoreboard'], isTrue);
      expect(plan['compileOnce'], isTrue);
      expect(
        _portablePath(plan['compiledPageDir'].toString()),
        '${_portablePath(tempDir.path)}/.fleury-web-frame-page',
      );
      expect(plan['requireComparableRunEnvironment'], isTrue);
      expect(plan['thresholdPolicyPath'], thresholdsPath);
      expect(plan['candidateThresholdPolicyPath'], candidateThresholdsPath);
      expect(plan['scoreboardJsonPath'], scoreboardJsonPath);
      expect(plan['thresholdHeadroomPercent'], 10.0);
      expect(plan['thresholdMinHeadroomMs'], 0.5);
      expect(plan['thresholdMinHeadroomPercent'], 0.5);
      expect(plan['gates'], {
        'maxTotalFrameP95Ms': 25.0,
        'maxDomApplyP95Ms': 12.0,
        'maxSemanticApplyP95Ms': 8.0,
        'maxOverBudgetPercent': 10.0,
        'maxSemanticUncoveredCells': 0.0,
      });

      final commands = (plan['commands'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(commands, hasLength(6));
      expect(
        commands.first['args'] as List<Object?>,
        contains('--compile-only'),
      );
      expect(
        _portableArgs(commands.first),
        contains(
          '--page-dir=${_portablePath(tempDir.path)}/.fleury-web-frame-page',
        ),
      );
      final firstCapture = commands[1];
      expect(
        firstCapture['args'] as List<Object?>,
        contains('--scenario=normal-80x24'),
      );
      expect(firstCapture['args'] as List<Object?>, contains('--frames=3'));
      expect(
        firstCapture['args'] as List<Object?>,
        contains('--chrome=/tmp/chrome'),
      );
      expect(firstCapture['args'] as List<Object?>, contains('--headful'));
      expect(firstCapture['args'] as List<Object?>, contains('--keep-temp'));
      expect(
        _portableArgs(firstCapture),
        contains(
          '--page-dir=${_portablePath(tempDir.path)}/.fleury-web-frame-page',
        ),
      );
      expect(
        firstCapture['args'] as List<Object?>,
        contains('--output=${tempDir.path}/normal-80x24-run-1.json'),
      );
      final scoreboard = commands.last;
      expect(scoreboard['display'], contains('tool/web_frame_scoreboard.dart'));
      expect(scoreboard['args'] as List<Object?>, contains('--min-runs=2'));
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--max-total-frame-p95-ms=25.0'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--max-dom-apply-p95-ms=12.0'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--max-semantic-apply-p95-ms=8.0'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--max-over-budget-percent=10.0'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--max-semantic-uncovered-cells=0.0'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--thresholds=$thresholdsPath'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--write-thresholds=$candidateThresholdsPath'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--threshold-headroom-percent=10.0'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--threshold-min-headroom-ms=0.5'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--threshold-min-headroom-percent=0.5'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--require-comparable-environment'),
      );
      expect(scoreboard['args'] as List<Object?>, contains('--strict'));
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--output=$scoreboardPath'),
      );
      expect(
        scoreboard['args'] as List<Object?>,
        contains('--json-output=$scoreboardJsonPath'),
      );
    },
  );

  test(
    'web frame suite default output uses ignored generated runs bucket',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_frame_suite.dart',
        '--scenarios=normal-80x24',
        '--runs=1',
        '--frames=1',
        '--warmup=0',
        '--dry-run',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final plan = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final outputDir = _portablePath(plan['outputDir'].toString());
      final scoreboardPath = _portablePath(plan['scoreboardPath'].toString());
      final scoreboardJsonPath = _portablePath(
        plan['scoreboardJsonPath'].toString(),
      );
      expect(outputDir, contains('/profiling/web/runs/'));
      expect(outputDir, endsWith('-suite'));
      expect(scoreboardPath, '$outputDir/scoreboard.md');
      expect(scoreboardJsonPath, '$outputDir/scoreboard.json');

      final commands = (plan['commands'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        _portableArgs(commands.first),
        contains('--page-dir=$outputDir/.fleury-web-frame-page'),
      );
      final captureArgs = commands[1]['args'] as List<Object?>;
      expect(
        _portableArgs(commands[1]),
        contains('--page-dir=$outputDir/.fleury-web-frame-page'),
      );
      expect(
        _portablePath(
          captureArgs.cast<String>().singleWhere(
            (arg) => arg.startsWith('--output='),
          ),
        ),
        startsWith('--output=$outputDir/normal-80x24-run-1.json'),
      );
    },
  );

  test('web frame suite rejects unknown scenario ids', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_suite.dart',
      '--scenarios=missing',
      '--dry-run',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('Unknown web benchmark scenario: missing'));
  });

  test('web frame suite rejects empty scoreboard JSON path', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_suite.dart',
      '--scoreboard-json=',
      '--dry-run',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr,
      contains('--scoreboard-json requires a non-empty path.'),
    );
  });

  test('web frame suite can opt out of comparable environment gate', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_suite.dart',
      '--scenarios=normal-80x24',
      '--runs=1',
      '--no-require-comparable-environment',
      '--dry-run',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final plan = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(plan['requireComparableRunEnvironment'], isFalse);
    final commands = (plan['commands'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      commands.last['args'] as List<Object?>,
      isNot(contains('--require-comparable-environment')),
    );
  });

  test('web frame suite can opt out of compile-once reuse', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_frame_suite.dart',
      '--scenarios=normal-80x24',
      '--runs=1',
      '--no-compile-once',
      '--dry-run',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final plan = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(plan['compileOnce'], isFalse);
    expect(plan, isNot(contains('compiledPageDir')));
    final commands = (plan['commands'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(commands, hasLength(2));
    expect(commands.first['display'], contains('tool/web_frame_capture.dart'));
    expect(
      commands.first['args'] as List<Object?>,
      isNot(contains(startsWith('--page-dir='))),
    );
  });
}

String _portablePath(String path) =>
    path.replaceAll(Platform.pathSeparator, '/');

List<String> _portableArgs(Map<String, Object?> command) {
  return [
    for (final arg in (command['args'] as List<Object?>).cast<String>())
      _portablePath(arg),
  ];
}
