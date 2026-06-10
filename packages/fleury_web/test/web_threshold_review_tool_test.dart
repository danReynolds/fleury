@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_threshold_review_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('promotes candidate thresholds to a reviewed policy', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    final jsonOutputPath = '${tempDir.path}/threshold-review.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--json-output=$jsonOutputPath',
      '--reviewed-by=principal reviewer',
      '--reviewed-at=2026-06-08T12:00:00-04:00',
      '--review-context=Chrome 127 on macOS local retained DOM Phase 1 refresh',
      '--review-note=Accepted for local retained DOM Phase 1 evidence.',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final summary = jsonDecode(result.stdout.toString());
    expect(
      (summary as Map<String, Object?>)['kind'],
      'fleuryWebThresholdReview',
    );
    expect(summary['reviewState'], 'reviewed');
    expect(summary['reviewedBy'], 'principal reviewer');
    expect(summary['reviewedAt'], '2026-06-08T16:00:00.000Z');
    expect(
      summary['reviewContext'],
      'Chrome 127 on macOS local retained DOM Phase 1 refresh',
    );
    expect(summary['scenarioCount'], 1);
    expect(summary['inputPolicyFingerprint'], isA<String>());
    expect(summary['outputPolicyFingerprint'], isA<String>());
    expect(
      summary['outputPolicyFingerprint'],
      isNot(summary['inputPolicyFingerprint']),
    );
    expect(summary['generatedFrom'], isA<Map<String, Object?>>());
    expect(summary['scenarioIds'], ['normal-80x24']);
    expect(
      _jsonObject(File(jsonOutputPath).readAsStringSync()),
      containsPair('reviewState', 'reviewed'),
    );

    final policy = jsonDecode(File(outputPath).readAsStringSync());
    expect(
      (policy as Map<String, Object?>)['kind'],
      'fleuryWebFrameThresholds',
    );
    expect(policy['reviewState'], 'reviewed');
    expect(policy['reviewedBy'], 'principal reviewer');
    expect(policy['reviewedAt'], '2026-06-08T16:00:00.000Z');
    expect(
      policy['reviewContext'],
      'Chrome 127 on macOS local retained DOM Phase 1 refresh',
    );
    expect(
      policy['reviewNote'],
      'Accepted for local retained DOM Phase 1 evidence.',
    );
    expect(policy['generatedFrom'], isA<Map<String, Object?>>());
    final scenarios = policy['scenarios'] as Map<String, Object?>;
    expect(scenarios, contains('normal-80x24'));
  });

  test('requires explicit acknowledgement for over-budget thresholds', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath, maxOverBudgetPercent: 100);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=principal reviewer',
      '--review-context=Chrome 127 on macOS local retained DOM Phase 1 refresh',
      '--review-note=The current product baseline intentionally accepts slow frames.',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('rerun with --allow-over-budget-thresholds'),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('requires review note for over-budget acknowledgement', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath, maxOverBudgetPercent: 100);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=principal reviewer',
      '--review-context=Chrome 127 on macOS local retained DOM Phase 1 refresh',
      '--allow-over-budget-thresholds',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains(
        'requires --review-note=TEXT to justify --allow-over-budget-thresholds',
      ),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('promotes over-budget thresholds with explicit acknowledgement', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    final jsonOutputPath = '${tempDir.path}/threshold-review.json';
    _writeCandidatePolicy(inputPath, maxOverBudgetPercent: 100);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--json-output=$jsonOutputPath',
      '--reviewed-by=principal reviewer',
      '--reviewed-at=2026-06-08T12:00:00-04:00',
      '--review-context=Chrome 127 on macOS local retained DOM Phase 1 refresh',
      '--allow-over-budget-thresholds',
      '--review-note=Accepted as a local retained DOM baseline while render-bound work remains tracked.',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final summary = _jsonObject(result.stdout.toString());
    expect(summary['overBudgetThresholdScenarioCount'], 1);
    expect(summary['overBudgetThresholdScenarioIds'], ['normal-80x24']);
    expect(summary['overBudgetThresholdsAcknowledged'], isTrue);

    final policy = _jsonObject(File(outputPath).readAsStringSync());
    expect(policy['overBudgetThresholdsAcknowledged'], isTrue);
    expect(policy['overBudgetThresholdScenarioIds'], ['normal-80x24']);
    expect(
      _jsonObject(
        File(jsonOutputPath).readAsStringSync(),
      )['overBudgetThresholdsAcknowledged'],
      isTrue,
    );
  });

  test('writes a non-promoting threshold review plan', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final planPath = '${tempDir.path}/threshold-review-plan.md';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--write-plan=$planPath',
      '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('wrote $planPath'));
    expect(File(outputPath).existsSync(), isFalse);
    final plan = File(planPath).readAsStringSync();
    expect(plan, contains('Fleury Web Threshold Review Plan'));
    expect(plan, contains('normal-80x24'));
    expect(plan, contains('Frames / steps'));
    expect(plan, contains('| normal-80x24 | 4 / 2 | 2 | 2 |'));
    expect(plan, contains('Runtime Subphase Timing Availability'));
    expect(
      plan,
      contains(
        'should not be used to decide whether Dart work is build-, layout-, or paint-bound',
      ),
    );
    expect(plan, contains('| normal-80x24 | missing | missing | missing |'));
    expect(plan, contains('fnv1a64:'));
    expect(plan, contains('--output=$outputPath'));
    expect(
      plan,
      contains('--json-output=${tempDir.path}/threshold-review.json'),
    );
    expect(plan, contains('--reviewed-by=<reviewer>'));
    expect(plan, contains("'--reviewed-by=<reviewer>'"));
    expect(plan, contains('--expect-input-fingerprint=fnv1a64:'));
    expect(plan, contains('intentionally not runnable as written'));
    expect(
      plan,
      contains(
        "'--review-context=Browser Chrome/127, OS macos, retained DOM product baseline'",
      ),
    );
    expect(
      plan,
      contains(
        'Review context hint: `Browser Chrome/127, OS macos, retained DOM product baseline`',
      ),
    );
  });

  test('threshold review plan calls out over-budget acknowledgement', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final planPath = '${tempDir.path}/threshold-review-plan.md';
    _writeCandidatePolicy(inputPath, maxOverBudgetPercent: 100);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--write-plan=$planPath',
      '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final plan = File(planPath).readAsStringSync();
    expect(plan, contains('## Over-Budget Thresholds'));
    expect(plan, contains('normal-80x24'));
    expect(plan, contains('--allow-over-budget-thresholds'));
    expect(
      plan,
      contains(
        '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
      ),
    );
  });

  test('threshold review plan uses generated capture context hint', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final planPath = '${tempDir.path}/threshold-review-plan.md';
    _writeCandidatePolicy(
      inputPath,
      generatedReviewContextHint:
          'Browser Chrome/149, OS macos, retained DOM product baseline',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--write-plan=$planPath',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final plan = File(planPath).readAsStringSync();
    expect(
      plan,
      contains(
        'Review context hint: `Browser Chrome/149, OS macos, retained DOM product baseline`',
      ),
    );
    expect(
      plan,
      contains(
        "'--review-context=Browser Chrome/149, OS macos, retained DOM product baseline'",
      ),
    );
  });

  test(
    'threshold review plan omits subphase warning when metrics exist',
    () async {
      final inputPath = '${tempDir.path}/thresholds.candidate.json';
      final planPath = '${tempDir.path}/threshold-review-plan.md';
      _writeCandidatePolicy(inputPath, includeRuntimeSubphaseMetrics: true);

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_threshold_review.dart',
        '--input=$inputPath',
        '--write-plan=$planPath',
        '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final plan = File(planPath).readAsStringSync();
      expect(plan, isNot(contains('Runtime Subphase Timing Availability')));
      expect(plan, isNot(contains('build-, layout-, or paint-bound')));
    },
  );

  test(
    'threshold review plan reports partial runtime subphase metrics',
    () async {
      final inputPath = '${tempDir.path}/thresholds.candidate.json';
      final planPath = '${tempDir.path}/threshold-review-plan.md';
      _writeCandidatePolicy(
        inputPath,
        observedMaxRuntimeBuildP95Ms: 1.2,
        observedMaxRuntimeLayoutP95Ms: null,
        observedMaxRuntimePaintP95Ms: 3.4,
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_threshold_review.dart',
        '--input=$inputPath',
        '--write-plan=$planPath',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final plan = File(planPath).readAsStringSync();
      expect(plan, contains('Runtime Subphase Timing Availability'));
      expect(plan, contains('| normal-80x24 | present | missing | present |'));
    },
  );

  test('write-plan can embed JSON summary output without promotion', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final planPath = '${tempDir.path}/threshold-review-plan.md';
    final outputPath = '${tempDir.path}/thresholds.json';
    final jsonOutputPath = '${tempDir.path}/threshold-review.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--write-plan=$planPath',
      '--json-output=$jsonOutputPath',
      '--review-context-hint=Browser Chrome/127, OS macos, retained DOM product baseline',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(File(outputPath).existsSync(), isFalse);
    expect(File(jsonOutputPath).existsSync(), isFalse);
    final plan = File(planPath).readAsStringSync();
    expect(plan, contains('--json-output=$jsonOutputPath'));
    expect(plan, contains('--expect-input-fingerprint=fnv1a64:'));
    expect(plan, contains('--reviewed-by=<reviewer>'));
    expect(plan, contains('intentionally not runnable as written'));
  });

  test('rejects stale expected input fingerprint during promotion', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--expect-input-fingerprint=fnv1a64:0000000000000000',
      '--reviewed-by=principal reviewer',
      '--review-context=Chrome 127 macOS threshold review context',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('does not match expected fnv1a64:0000000000000000'),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('requires reviewer provenance', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('requires --reviewed-by=NAME'));
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('requires review context', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=principal reviewer',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('requires --review-context=TEXT'),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('rejects reviewer placeholder during promotion', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=<reviewer>',
      '--review-context=Chrome 127 on macOS local retained DOM Phase 1 refresh',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('replace the reviewer placeholder'),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('rejects generic browser context placeholder during promotion', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=principal reviewer',
      '--review-context=Chrome VERSION on PLATFORM, retained DOM product baseline',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('replace placeholder browser/platform values'),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('rejects already reviewed input', () async {
    final inputPath = '${tempDir.path}/thresholds.json';
    final outputPath = '${tempDir.path}/thresholds-reviewed-again.json';
    _writeCandidatePolicy(
      inputPath,
      reviewState: 'reviewed',
      reviewedBy: 'first reviewer',
      reviewedAt: '2026-06-08T12:00:00.000Z',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=second reviewer',
      '--review-context=Chrome 127 macOS already-reviewed test context',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('already reviewed'));
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('rejects empty JSON output path', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    final outputPath = '${tempDir.path}/thresholds.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--output=$outputPath',
      '--reviewed-by=principal reviewer',
      '--review-context=Chrome 127 macOS threshold review context',
      '--json-output=',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--json-output requires a non-empty path.'),
    );
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('rejects empty review plan path', () async {
    final inputPath = '${tempDir.path}/thresholds.candidate.json';
    _writeCandidatePolicy(inputPath);

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_threshold_review.dart',
      '--input=$inputPath',
      '--write-plan=',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--write-plan requires a non-empty path.'),
    );
  });
}

Map<String, Object?> _jsonObject(String source) =>
    (jsonDecode(source) as Map).cast<String, Object?>();

void _writeCandidatePolicy(
  String path, {
  String reviewState = 'candidate',
  String? reviewedBy,
  String? reviewedAt,
  num maxOverBudgetPercent = 0,
  bool includeRuntimeSubphaseMetrics = false,
  String? generatedReviewContextHint,
  num? observedMaxRuntimeBuildP95Ms,
  num? observedMaxRuntimeLayoutP95Ms,
  num? observedMaxRuntimePaintP95Ms,
}) {
  final runtimeSubphaseMetrics = includeRuntimeSubphaseMetrics
      ? <String, Object?>{
          'observedMaxRuntimeBuildP95Ms': observedMaxRuntimeBuildP95Ms ?? 1,
          'observedMaxRuntimeLayoutP95Ms': observedMaxRuntimeLayoutP95Ms ?? 2,
          'observedMaxRuntimePaintP95Ms': observedMaxRuntimePaintP95Ms ?? 3,
        }
      : <String, Object?>{
          if (observedMaxRuntimeBuildP95Ms != null)
            'observedMaxRuntimeBuildP95Ms': observedMaxRuntimeBuildP95Ms,
          if (observedMaxRuntimeLayoutP95Ms != null)
            'observedMaxRuntimeLayoutP95Ms': observedMaxRuntimeLayoutP95Ms,
          if (observedMaxRuntimePaintP95Ms != null)
            'observedMaxRuntimePaintP95Ms': observedMaxRuntimePaintP95Ms,
        };
  final policy = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebFrameThresholds',
    'generatedAt': '2026-06-08T12:00:00.000Z',
    'reviewState': reviewState,
    if (reviewedBy != null) 'reviewedBy': reviewedBy,
    if (reviewedAt != null) 'reviewedAt': reviewedAt,
    'reviewNote':
        'Generated from observed retained DOM web frame captures; review before using as a release gate.',
    'generatedFrom': <String, Object?>{
      'kind': 'fleuryWebFrameScoreboard',
      'runCount': 3,
      'scenarioCount': 1,
      if (generatedReviewContextHint != null)
        'captureEnvironment': <String, Object?>{
          'scenarioCount': 1,
          'scenarioWithEnvironmentCount': 1,
          'comparableScenarioCount': 1,
          'allScenariosComparable': true,
          'reviewContextHint': generatedReviewContextHint,
        },
    },
    'defaults': const <String, Object?>{},
    'scenarios': <String, Object?>{
      'normal-80x24': <String, Object?>{
        'maxTotalFrameP95Ms': 20,
        'maxDomApplyP95Ms': 4,
        'maxSemanticApplyP95Ms': 8,
        'maxOverBudgetPercent': maxOverBudgetPercent,
        'maxSemanticUncoveredCells': 0,
        'observedFrameCount': 4,
        'observedRequestedStepCount': 2,
        'observedExtraFrameCount': 2,
        'observedMaxFramesPerStep': 2,
        ...runtimeSubphaseMetrics,
      },
    },
  };
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(policy)}\n',
  );
}
