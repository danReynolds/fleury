@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fleury_web_readiness_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('web readiness passes reviewed gate artifacts', () async {
    final paths = _writeArtifacts(tempDir);
    final outputPath = '${tempDir.path}/readiness.md';
    final jsonOutputPath = '${tempDir.path}/readiness.json';

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--json-output=$jsonOutputPath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['kind'], 'fleuryWebReadinessAudit');
    expect(audit['strictPass'], isTrue);
    final checks = audit['checks'] as List<Object?>;
    expect(checks, hasLength(3));
    expect(
      checks,
      everyElement(
        isA<Map<String, Object?>>().having(
          (check) => check['strictPass'],
          'strictPass',
          isTrue,
        ),
      ),
    );
    final persisted =
        jsonDecode(File(jsonOutputPath).readAsStringSync())
            as Map<String, Object?>;
    expect(persisted['kind'], 'fleuryWebReadinessAudit');
    expect(persisted['strictPass'], isTrue);
    final manualCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'manualValidation',
    );
    final manualDetails = manualCheck['details'] as Map<String, Object?>;
    final manualEvidence = manualDetails['manualEvidence'] as List<Object?>;
    expect(manualEvidence, hasLength(2));
    expect(
      manualEvidence,
      contains(
        isA<Map<String, Object?>>()
            .having((entry) => entry['id'], 'id', 'chrome-ime-macos')
            .having(
              (entry) => entry['latestEntryFingerprint'],
              'latestEntryFingerprint',
              startsWith('fnv1a64:'),
            ),
      ),
    );

    final markdownResult = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--output=$outputPath',
    ]);
    expect(
      markdownResult.exitCode,
      0,
      reason: markdownResult.stderr.toString(),
    );

    final markdown = File(outputPath).readAsStringSync();
    expect(markdown, contains('Fleury Web Readiness Audit'));
    expect(markdown, contains('Frame performance scoreboard'));
    expect(markdown, contains('Semantic coverage audit'));
    expect(markdown, contains('Manual browser validation'));
  });

  test('web readiness fails smoke scoreboard artifacts', () async {
    final jsonOutputPath = '${tempDir.path}/readiness.json';
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: _scoreboard(minRuns: 1, gates: const []),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--json-output=$jsonOutputPath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('frame scoreboard minRuns 1 is below required 3'),
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('frame scenarios missing threshold gates: normal-80x24'),
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('frame scenarios missing total-frame p95 gate: normal-80x24'),
    );
    final persisted =
        jsonDecode(File(jsonOutputPath).readAsStringSync())
            as Map<String, Object?>;
    expect(persisted['strictPass'], isFalse);
  });

  test('web readiness rejects empty json output path', () async {
    final paths = _writeArtifacts(tempDir);

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--json-output=',
    ]);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--json-output requires a non-empty path.'),
    );
  });

  test('web readiness requires reviewed threshold policy by default', () async {
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: _scoreboard(thresholdPolicyReviewState: 'candidate'),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains(
        'frame scoreboard threshold policy reviewState is candidate; expected reviewed',
      ),
    );
  });

  test('web readiness requires reviewed threshold provenance', () async {
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: _scoreboard(
        thresholdPolicyReviewedBy: null,
        thresholdPolicyReviewedAt: null,
      ),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('frame scoreboard threshold policy reviewedBy is missing'),
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('frame scoreboard threshold policy reviewedAt is missing'),
    );
  });

  test('web readiness requires reviewed threshold context', () async {
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: _scoreboard(thresholdPolicyReviewContext: null),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('frame scoreboard threshold policy reviewContext is missing'),
    );
  });

  test('web readiness requires threshold review summary by default', () async {
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: _scoreboard(
        thresholdPolicyPath: '${tempDir.path}/thresholds.json',
      ),
      writeThresholdReview: false,
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains('threshold review summary: missing artifact'),
    );
  });

  test('web readiness rejects mismatched threshold review summary', () async {
    final scoreboard = _scoreboard(
      thresholdPolicyPath: '${tempDir.path}/thresholds.json',
    );
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: scoreboard,
      thresholdReview: {
        ..._thresholdReview(scoreboard),
        'outputPath': '${tempDir.path}/other-thresholds.json',
        'reviewContext': 'different review context',
        'scenarioCount': 2,
      },
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    final blockers = frameCheck['blockers'] as List<Object?>;
    expect(
      blockers,
      contains(
        'threshold review summary outputPath does not match threshold policy path',
      ),
    );
    expect(
      blockers,
      contains(
        'threshold review summary reviewContext does not match frame scoreboard threshold policy',
      ),
    );
    expect(
      blockers,
      contains(
        'threshold review summary scenarioCount 2 does not match frame scoreboard scenarioCount 1',
      ),
    );
  });

  test(
    'web readiness rejects stale threshold review summary fingerprint',
    () async {
      final scoreboard = _scoreboard(
        thresholdPolicyPath: '${tempDir.path}/thresholds.json',
      );
      final paths = _writeArtifacts(
        tempDir,
        scoreboard: scoreboard,
        thresholdReview: {
          ..._thresholdReview(scoreboard),
          'outputPolicyFingerprint': 'fnv1a64:0000000000000000',
        },
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final checks = audit['checks'] as List<Object?>;
      final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'frameScoreboard',
      );
      expect(
        frameCheck['blockers'] as List<Object?>,
        contains(
          'threshold review summary outputPolicyFingerprint does not match frame scoreboard threshold policy',
        ),
      );
    },
  );

  test(
    'web readiness rejects missing threshold review input provenance',
    () async {
      final scoreboard = _scoreboard(
        thresholdPolicyPath: '${tempDir.path}/thresholds.json',
      );
      final review = _thresholdReview(scoreboard)..remove('inputPath');
      final paths = _writeArtifacts(
        tempDir,
        scoreboard: scoreboard,
        thresholdReview: review,
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final checks = audit['checks'] as List<Object?>;
      final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'frameScoreboard',
      );
      expect(
        frameCheck['blockers'] as List<Object?>,
        contains('threshold review summary inputPath is missing'),
      );
    },
  );

  test(
    'web readiness rejects stale threshold review input fingerprint',
    () async {
      final scoreboard = _scoreboard(
        thresholdPolicyPath: '${tempDir.path}/thresholds.json',
      );
      final paths = _writeArtifacts(
        tempDir,
        scoreboard: scoreboard,
        thresholdReview: {
          ..._thresholdReview(scoreboard),
          'inputPolicyFingerprint': 'fnv1a64:0000000000000000',
        },
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final checks = audit['checks'] as List<Object?>;
      final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'frameScoreboard',
      );
      expect(
        frameCheck['blockers'] as List<Object?>,
        contains(
          'threshold review summary inputPolicyFingerprint does not match inputPath policy',
        ),
      );
    },
  );

  test(
    'web readiness can relax threshold review summary requirement',
    () async {
      final paths = _writeArtifacts(
        tempDir,
        scoreboard: _scoreboard(
          thresholdPolicyPath: '${tempDir.path}/thresholds.json',
        ),
        writeThresholdReview: false,
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--no-require-threshold-review-summary',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isTrue);
    },
  );

  test('web readiness rejects empty threshold review path', () async {
    final paths = _writeArtifacts(tempDir);

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--threshold-review=',
    ]);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--threshold-review requires a non-empty path.'),
    );
  });

  test(
    'web readiness can relax reviewed threshold policy requirement',
    () async {
      final paths = _writeArtifacts(
        tempDir,
        scoreboard: _scoreboard(thresholdPolicyReviewState: 'candidate'),
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--no-require-reviewed-threshold-policy',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isTrue);
    },
  );

  test('web readiness requires scenario threshold policy by default', () async {
    final paths = _writeArtifacts(
      tempDir,
      scoreboard: _scoreboard(thresholdPolicyMatchedScenario: false),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'frameScoreboard',
    );
    expect(
      frameCheck['blockers'] as List<Object?>,
      contains(
        'frame scenarios missing scenario-specific threshold policy: normal-80x24',
      ),
    );
    final details = frameCheck['details'] as Map<String, Object?>;
    expect(details['missingScenarioThresholdPolicy'], ['normal-80x24']);
  });

  test(
    'web readiness can relax scenario threshold policy requirement',
    () async {
      final paths = _writeArtifacts(
        tempDir,
        scoreboard: _scoreboard(thresholdPolicyMatchedScenario: false),
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--no-require-scenario-thresholds',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isTrue);
    },
  );

  test('web readiness reports missing manual evidence artifact', () async {
    final paths = _writeArtifacts(tempDir);
    File(paths.manualAudit).deleteSync();

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final manualCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'manualValidation',
    );
    expect(manualCheck['strictPass'], isFalse);
    expect(manualCheck['blockers'], ['missing artifact']);
  });

  test('web readiness allows empty scoped manual validation audit', () async {
    final paths = _writeArtifacts(
      tempDir,
      manualAudit: _manualAudit(targetIds: const <String>[]),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['strictPass'], isTrue);
    final manualCheck = (audit['checks'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((check) => check['id'] == 'manualValidation');
    expect(manualCheck['strictPass'], isTrue);
    final details = manualCheck['details'] as Map<String, Object?>;
    expect(details['targetCount'], 0);
    expect(details['passedTargetCount'], 0);
    expect(details, isNot(contains('manualEvidence')));
  });

  test('web readiness reports manual provenance blockers', () async {
    final paths = _writeArtifacts(
      tempDir,
      manualAudit: _manualAudit(
        strictPass: false,
        passedTargetCount: 1,
        needsReviewTargets: const ['chrome-ime-macos'],
        targetOverrides: const {
          'chrome-ime-macos': {
            'status': 'needsReview',
            'strictPass': false,
            'provenanceBlockers': ['reviewedBy', 'environment.browserVersion'],
          },
        },
      ),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final manualCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'manualValidation',
    );
    expect(
      manualCheck['blockers'] as List<Object?>,
      contains('needsReviewTargets: chrome-ime-macos'),
    );
    expect(
      manualCheck['blockers'] as List<Object?>,
      contains(
        'manual evidence provenance blockers: chrome-ime-macos: reviewedBy, environment.browserVersion',
      ),
    );
    final details = manualCheck['details'] as Map<String, Object?>;
    expect(details['needsReviewTargets'], ['chrome-ime-macos']);
    final provenanceBlockers =
        details['provenanceBlockers'] as Map<String, Object?>;
    expect(provenanceBlockers['chrome-ime-macos'], [
      'reviewedBy',
      'environment.browserVersion',
    ]);
  });

  test('web readiness reports invalid manual evidence files', () async {
    final paths = _writeArtifacts(
      tempDir,
      manualAudit: _manualAudit(
        strictPass: false,
        invalidEntries: const [
          {
            'path': '/tmp/fleury-web-manual/broken.json',
            'file': 'broken.json',
            'reason': 'invalid JSON: Unexpected character',
          },
        ],
      ),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final manualCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'manualValidation',
    );
    expect(
      manualCheck['blockers'] as List<Object?>,
      contains('manual validation audit has 1 invalid evidence file(s)'),
    );
    final details = manualCheck['details'] as Map<String, Object?>;
    expect(details['invalidEntryCount'], 1);
    final invalidEntries = details['invalidEntries'] as List<Object?>;
    expect(
      invalidEntries.single,
      isA<Map<String, Object?>>()
          .having((issue) => issue['file'], 'file', 'broken.json')
          .having(
            (issue) => issue['reason'],
            'reason',
            contains('invalid JSON'),
          ),
    );
  });

  test('web readiness surfaces manual target check diagnostics', () async {
    final outputPath = '${tempDir.path}/readiness.md';
    final paths = _writeArtifacts(
      tempDir,
      manualAudit: _manualAudit(
        strictPass: false,
        passedTargetCount: 0,
        missingTargets: const ['chrome-ime-macos', 'chrome-voiceover-macos'],
        targetOverrides: const {
          'chrome-ime-macos': {
            'status': 'missing',
            'strictPass': false,
            'passedRequiredCheckCount': 0,
            'missingCheckIds': [
              'manual-page-loads-dom-host',
              'candidate-window-near-caret',
            ],
          },
          'chrome-voiceover-macos': {
            'status': 'missing',
            'strictPass': false,
            'passedRequiredCheckCount': 0,
            'missingCheckIds': [
              'manual-page-ready-semantic-host',
              'visual-grid-hidden',
            ],
          },
        },
      ),
    );

    final result = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final checks = audit['checks'] as List<Object?>;
    final manualCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'manualValidation',
    );
    final details = manualCheck['details'] as Map<String, Object?>;
    final failingTargetDetails =
        details['failingTargetDetails'] as List<Object?>;
    final voiceOver = failingTargetDetails
        .cast<Map<String, Object?>>()
        .singleWhere((target) => target['id'] == 'chrome-voiceover-macos');

    expect(voiceOver['requiredCheckCount'], 7);
    expect(voiceOver['passedRequiredCheckCount'], 0);
    expect(voiceOver['missingCheckIds'], [
      'manual-page-ready-semantic-host',
      'visual-grid-hidden',
    ]);

    final markdownResult = await _run([
      '--scoreboard=${paths.scoreboard}',
      '--semantic-audit=${paths.semanticAudit}',
      '--manual-audit=${paths.manualAudit}',
      '--output=$outputPath',
    ]);

    expect(
      markdownResult.exitCode,
      0,
      reason: markdownResult.stderr.toString(),
    );
    final markdown = File(outputPath).readAsStringSync();
    expect(markdown, contains('Manual Target Diagnostics'));
    expect(markdown, contains('chrome-ime-macos'));
    expect(markdown, contains('0/6'));
    expect(markdown, contains('chrome-voiceover-macos'));
    expect(markdown, contains('0/7'));
    expect(markdown, contains('manual-page-ready-semantic-host'));
  });

  test(
    'web readiness surfaces semantic fallback capture diagnostics',
    () async {
      final paths = _writeArtifacts(
        tempDir,
        semanticAudit: _semanticAudit(
          topFallbackCaptures: const [
            {
              'path': '/tmp/normal-a.json',
              'file': 'normal-a.json',
              'scenarioId': 'normal-80x24',
              'capturedAt': '2026-06-08T12:00:00.000000Z',
              'frameCount': 2,
              'viewportCellCount': 3840,
              'fallbackFrameCount': 1,
              'fallbackCellCount': 6,
              'fallbackNodeCount': 2,
              'fallbackFramePercent': 50.0,
              'fallbackViewportCellPercent': 0.15625,
              'maxFallbackCellsInFrame': 6,
              'maxFallbackNodesInFrame': 2,
            },
          ],
        ),
      );

      final result = await _run([
        '--scoreboard=${paths.scoreboard}',
        '--semantic-audit=${paths.semanticAudit}',
        '--manual-audit=${paths.manualAudit}',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final checks = audit['checks'] as List<Object?>;
      final semanticCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'semanticCoverage',
      );
      final details = semanticCheck['details'] as Map<String, Object?>;
      expect(details['topFallbackCaptures'], hasLength(1));
      expect(
        (details['topFallbackCaptures'] as List<Object?>).single,
        isA<Map<String, Object?>>().having(
          (capture) => capture['file'],
          'file',
          'normal-a.json',
        ),
      );
    },
  );
}

Future<ProcessResult> _run(List<String> args) {
  return Process.run(Platform.resolvedExecutable, [
    'run',
    'tool/web_readiness.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

_ArtifactPaths _writeArtifacts(
  Directory directory, {
  Map<String, Object?>? scoreboard,
  Map<String, Object?>? semanticAudit,
  Map<String, Object?>? manualAudit,
  Map<String, Object?>? thresholdReview,
  bool writeThresholdReview = true,
}) {
  final scoreboardJson =
      scoreboard ??
      _scoreboard(thresholdPolicyPath: '${directory.path}/thresholds.json');
  final thresholdReviewPath =
      _defaultThresholdReviewPath(scoreboardJson['thresholdPolicyPath']) ??
      '${directory.path}/threshold-review.json';
  final paths = _ArtifactPaths(
    scoreboard: '${directory.path}/scoreboard.json',
    semanticAudit: '${directory.path}/semantic.json',
    manualAudit: '${directory.path}/manual.json',
    thresholdReview: thresholdReviewPath,
  );
  _writeJson(paths.scoreboard, scoreboardJson);
  _writeJson(paths.semanticAudit, semanticAudit ?? _semanticAudit());
  _writeJson(paths.manualAudit, manualAudit ?? _manualAudit());
  if (writeThresholdReview &&
      scoreboardJson['thresholdPolicyReviewState'] == 'reviewed') {
    final thresholdReviewJson =
        thresholdReview ?? _thresholdReview(scoreboardJson);
    _writeThresholdReviewInputPolicy(thresholdReviewJson);
    _writeJson(paths.thresholdReview, thresholdReviewJson);
  }
  return paths;
}

String? _defaultThresholdReviewPath(Object? thresholdPolicyPath) {
  final path = thresholdPolicyPath?.toString().trim();
  if (path == null || path.isEmpty) return null;
  return '${File(path).parent.path}${Platform.pathSeparator}threshold-review.json';
}

void _writeJson(String path, Map<String, Object?> json) {
  File(
    path,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
}

Map<String, Object?> _scoreboard({
  int minRuns = 3,
  String? thresholdPolicyPath = '/tmp/fleury-reviewed-thresholds.json',
  String? thresholdPolicyReviewState = 'reviewed',
  String? thresholdPolicyReviewedBy = 'test reviewer',
  String? thresholdPolicyReviewedAt = '2026-06-08T12:00:00.000000Z',
  String? thresholdPolicyReviewContext =
      'Chrome 127 macOS retained DOM readiness test',
  String? thresholdPolicyFingerprint = 'fnv1a64:1111111111111111',
  bool thresholdPolicyMatchedScenario = true,
  List<Map<String, Object?>> gates = const [
    {
      'id': 'totalFrameP95MedianMs',
      'actual': 14.2,
      'maximum': 16.67,
      'unit': 'ms',
      'passed': true,
    },
  ],
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebFrameScoreboard',
    'generatedAt': '2026-06-08T12:00:00.000000Z',
    'minRuns': minRuns,
    if (thresholdPolicyPath != null) 'thresholdPolicyPath': thresholdPolicyPath,
    if (thresholdPolicyReviewState != null)
      'thresholdPolicyReviewState': thresholdPolicyReviewState,
    if (thresholdPolicyReviewedBy != null)
      'thresholdPolicyReviewedBy': thresholdPolicyReviewedBy,
    if (thresholdPolicyReviewedAt != null)
      'thresholdPolicyReviewedAt': thresholdPolicyReviewedAt,
    if (thresholdPolicyReviewContext != null)
      'thresholdPolicyReviewContext': thresholdPolicyReviewContext,
    if (thresholdPolicyFingerprint != null)
      'thresholdPolicyFingerprint': thresholdPolicyFingerprint,
    if (thresholdPolicyPath != null) 'thresholdPolicyScenarioCount': 1,
    'requireComparableRunEnvironment': true,
    'scenarioCount': 1,
    'runCount': 3,
    'strictPass': true,
    'scenarios': [
      {
        'id': 'normal-80x24',
        'runCount': 3,
        'sufficientRunCount': true,
        'requireComparableRunEnvironment': true,
        'runEnvironmentComparable': true,
        if (thresholdPolicyPath != null)
          'thresholdPolicyMatchedScenario': thresholdPolicyMatchedScenario,
        'gates': gates,
        'strictPass': true,
      },
    ],
  };
}

Map<String, Object?> _thresholdReview(Map<String, Object?> scoreboard) {
  final outputPath =
      scoreboard['thresholdPolicyPath']?.toString() ??
      '/tmp/fleury-reviewed-thresholds.json';
  final inputPath =
      '${File(outputPath).parent.path}${Platform.pathSeparator}thresholds.candidate.json';
  final inputPolicy = _candidateThresholdPolicy();
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebThresholdReview',
    'inputPath': inputPath,
    'outputPath': scoreboard['thresholdPolicyPath'],
    'reviewState': scoreboard['thresholdPolicyReviewState'],
    'reviewedBy': scoreboard['thresholdPolicyReviewedBy'],
    'reviewedAt': scoreboard['thresholdPolicyReviewedAt'],
    'reviewContext': scoreboard['thresholdPolicyReviewContext'],
    'scenarioCount': scoreboard['scenarioCount'],
    'inputPolicyFingerprint': _jsonFingerprint(inputPolicy),
    'outputPolicyFingerprint': scoreboard['thresholdPolicyFingerprint'],
  };
}

void _writeThresholdReviewInputPolicy(Map<String, Object?> review) {
  final inputPath = review['inputPath']?.toString().trim();
  if (inputPath == null || inputPath.isEmpty) return;
  _writeJson(inputPath, _candidateThresholdPolicy());
}

Map<String, Object?> _candidateThresholdPolicy({
  String reviewState = 'candidate',
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebFrameThresholds',
    'reviewState': reviewState,
    'defaults': const <String, Object?>{
      'maxTotalFrameP95Ms': 16.67,
      'maxSemanticUncoveredCells': 0,
    },
    'scenarios': const <String, Object?>{
      'normal-80x24': <String, Object?>{
        'maxTotalFrameP95Ms': 16.67,
        'maxOverBudgetPercent': 0,
        'maxSemanticUncoveredCells': 0,
      },
    },
  };
}

Map<String, Object?> _semanticAudit({
  List<Map<String, Object?>> topFallbackCaptures =
      const <Map<String, Object?>>[],
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebSemanticCoverageAudit',
    'inputDir': '/tmp/fleury-web',
    'generatedAt': '2026-06-08T12:00:00.000000Z',
    'scenarioCount': 1,
    'captureCount': 3,
    'frameCount': 90,
    'fallbackFrameCount': 0,
    'fallbackCellCount': 0,
    'fallbackNodeCount': 0,
    'topFallbackCaptures': topFallbackCaptures,
    'gates': [
      {
        'id': 'maxFallbackCellsInFrame',
        'actual': 0,
        'maximum': 0,
        'unit': 'count',
        'passed': true,
      },
    ],
    'strictPass': true,
    'scenarios': [
      {
        'id': 'normal-80x24',
        'captureCount': 3,
        'frameCount': 90,
        'gates': [
          {
            'id': 'maxFallbackCellsInFrame',
            'actual': 0,
            'maximum': 0,
            'unit': 'count',
            'passed': true,
          },
        ],
        'strictPass': true,
      },
    ],
  };
}

Map<String, Object?> _manualAudit({
  bool strictPass = true,
  int? passedTargetCount,
  List<String> missingTargets = const <String>[],
  List<String> failedTargets = const <String>[],
  List<String> blockedTargets = const <String>[],
  List<String> needsReviewTargets = const <String>[],
  List<Map<String, Object?>> invalidEntries = const <Map<String, Object?>>[],
  List<String> targetIds = const <String>[
    'chrome-ime-macos',
    'chrome-voiceover-macos',
  ],
  Map<String, Map<String, Object?>> targetOverrides =
      const <String, Map<String, Object?>>{},
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebManualValidationAudit',
    'generatedAt': '2026-06-08T12:00:00.000000Z',
    'targetCount': targetIds.length,
    'entryCount': targetIds.length,
    'invalidEntryCount': invalidEntries.length,
    if (invalidEntries.isNotEmpty) 'invalidEntries': invalidEntries,
    'passedTargetCount': passedTargetCount ?? targetIds.length,
    'missingTargets': missingTargets,
    'failedTargets': failedTargets,
    'blockedTargets': blockedTargets,
    'needsReviewTargets': needsReviewTargets,
    'strictPass': strictPass,
    'targets': [
      for (final targetId in targetIds)
        _manualTarget(targetId, targetOverrides),
    ],
  };
}

Map<String, Object?> _manualTarget(
  String targetId,
  Map<String, Map<String, Object?>> overrides,
) {
  final requiredCheckCount = switch (targetId) {
    'chrome-voiceover-macos' => 7,
    _ => 6,
  };
  final override = overrides[targetId];
  final status = override?['status']?.toString() ?? 'pass';
  return <String, Object?>{
    'id': targetId,
    'status': 'pass',
    'strictPass': true,
    'requiredCheckCount': requiredCheckCount,
    'passedRequiredCheckCount': requiredCheckCount,
    if (status != 'missing') ...{
      'latestEntryPath': '/tmp/fleury-web-manual/$targetId.json',
      'latestEntryFile': '$targetId.json',
      'latestEntryFingerprint': _manualFingerprint(targetId),
      'latestCapturedAt': '2026-06-08T12:00:00.000000Z',
      'reviewedBy': 'test reviewer',
    },
    'missingCheckIds': <String>[],
    'failedCheckIds': <String>[],
    'blockedCheckIds': <String>[],
    'provenanceBlockers': <String>[],
    ...?override,
  };
}

String _manualFingerprint(String targetId) {
  return switch (targetId) {
    'chrome-voiceover-macos' => 'fnv1a64:bbbbbbbbbbbbbbbb',
    _ => 'fnv1a64:aaaaaaaaaaaaaaaa',
  };
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
  if (value is List) {
    return [for (final item in value) _canonicalizeJson(item)];
  }
  return value;
}

final class _ArtifactPaths {
  const _ArtifactPaths({
    required this.scoreboard,
    required this.semanticAudit,
    required this.manualAudit,
    required this.thresholdReview,
  });

  final String scoreboard;
  final String semanticAudit;
  final String manualAudit;
  final String thresholdReview;
}
