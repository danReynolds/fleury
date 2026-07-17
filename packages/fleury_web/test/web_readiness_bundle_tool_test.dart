@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/manual_validation/manual_validation_targets.dart';
import 'package:test/test.dart';

import '../tool/readiness_bundle_verifier.dart';

void main() {
  late Directory tempDir;
  late Directory capturesDir;
  late Directory manualDir;
  late Directory outputDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_readiness_bundle_test_',
    );
    capturesDir = Directory('${tempDir.path}/captures')..createSync();
    manualDir = Directory('${tempDir.path}/manual')..createSync();
    outputDir = Directory('${tempDir.path}/bundle');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('readiness verifier rejects the removed primary preset', () {
    final state = ReadinessBundleVerificationState();

    verifyReadinessBundleManifestConsistency(<String, Object?>{
      'input': <String, Object?>{'targetPreset': 'primary'},
      'artifacts': <String, Object?>{},
      'checks': <String, Object?>{},
    }, state: state);

    expect(
      state.manifestMismatches,
      contains(
        isA<Map<String, Object?>>()
            .having((mismatch) => mismatch['id'], 'id', 'input.targetPreset')
            .having(
              (mismatch) => mismatch['expected'],
              'expected',
              const <String>['v1', 'all'],
            )
            .having((mismatch) => mismatch['actual'], 'actual', 'primary'),
      ),
    );
  });

  test('web readiness bundle writes passing reviewed artifacts', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);
    final thresholdsPath = '${tempDir.path}/thresholds.json';
    final thresholdReviewPath = '${tempDir.path}/threshold-review.json';
    final completionAuditPath = '${tempDir.path}/completion-audit.json';
    final thresholdPolicy = {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameThresholds',
      'reviewState': 'reviewed',
      'reviewedBy': 'test reviewer',
      'reviewedAt': '2026-06-08T12:00:00.000000Z',
      'reviewContext': 'Chrome 127 macOS retained DOM bundle test',
      'defaults': {'maxTotalFrameP95Ms': 16.67, 'maxSemanticUncoveredCells': 0},
      'scenarios': {
        'normal-80x24': {
          'maxTotalFrameP95Ms': 16.67,
          'maxOverBudgetPercent': 100,
          'maxSemanticUncoveredCells': 0,
        },
      },
    };
    _writeJson(thresholdsPath, thresholdPolicy);
    _writeThresholdReview(
      path: thresholdReviewPath,
      outputPath: thresholdsPath,
      reviewedBy: 'test reviewer',
      reviewedAt: '2026-06-08T12:00:00.000000Z',
      reviewContext: 'Chrome 127 macOS retained DOM bundle test',
      scenarioCount: 1,
      outputPolicyFingerprint: _jsonFingerprint(thresholdPolicy),
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--thresholds=$thresholdsPath',
      '--threshold-review=$thresholdReviewPath',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--completion-audit=$completionAuditPath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(bundle['kind'], 'fleuryWebReadinessBundle');
    expect(bundle['strictPass'], isTrue);
    final completionAudit =
        jsonDecode(File(completionAuditPath).readAsStringSync())
            as Map<String, Object?>;
    expect(completionAudit['kind'], 'fleuryWebRfcCompletionAudit');
    expect(
      completionAudit['readinessBundlePath'],
      '${outputDir.path}/web-readiness-bundle.json',
    );
    expect(completionAudit['architectureReviewReady'], isTrue);
    expect(completionAudit['releaseReady'], isFalse);
    expect(completionAudit['defaultFlipReady'], isFalse);
    expect(completionAudit['temporaryPathRetirementReady'], isFalse);
    expect(completionAudit['goalCompletionClaim'], 'not-complete');
    final completionScopes =
        completionAudit['completionScopes'] as Map<String, Object?>;
    final architectureScope =
        completionScopes['architectureReview'] as Map<String, Object?>;
    expect(architectureScope['ready'], isTrue);
    expect(architectureScope['status'], 'ready-for-re-review');
    expect(architectureScope['claim'], 'implementation-review-ready');
    expect(architectureScope['releaseScope'], isFalse);
    expect(architectureScope['deferredReleaseGateIds'], [
      'release-evidence',
      'make-dom-default',
      'retire-temporary-paths',
    ]);
    final releaseEvidenceScope =
        completionScopes['releaseEvidence'] as Map<String, Object?>;
    expect(releaseEvidenceScope['ready'], isFalse);
    expect(releaseEvidenceScope['status'], 'blocked');
    expect(releaseEvidenceScope['remainingReleaseActionIds'], [
      'run-automated-web-host-tests',
    ]);
    expect(releaseEvidenceScope['satisfiedCurrentEvidenceActionIds'], [
      'verify-readiness-bundle',
    ]);
    expect(
      releaseEvidenceScope['remainingReleaseActionIds'],
      isNot(contains('run-default-preflight:make-dom-default')),
    );
    final releaseDefaultScope =
        completionScopes['releaseDefault'] as Map<String, Object?>;
    expect(releaseDefaultScope['ready'], isFalse);
    expect(releaseDefaultScope['status'], 'blocked');
    expect(releaseDefaultScope['remainingGateIds'], [
      'release-evidence',
      'run-default-preflight:make-dom-default',
      'run-default-preflight:retire-temporary-paths',
    ]);
    expect(
      completionAudit['completionBlockers'],
      contains('automated retained-host validation artifact must pass'),
    );
    final completionManualEvidence =
        completionAudit['manualEvidence'] as Map<String, Object?>;
    expect(completionManualEvidence['needsReviewTargets'], isEmpty);
    final completionAutomatedEvidence =
        (completionAudit['automatedEvidence']
                as Map<String, Object?>)['automatedWebHostValidation']
            as Map<String, Object?>;
    expect(completionAutomatedEvidence['status'], 'missing');
    final completionPhases = (completionAudit['phaseStatus'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final phase5 = completionPhases.singleWhere(
      (phase) => phase['phase'] == 'Phase 5',
    );
    expect(phase5['releaseBlocking'], isFalse);
    expect(phase5['evidence'], contains(thresholdsPath));
    final phase6 = completionPhases.singleWhere(
      (phase) => phase['phase'] == 'Phase 6',
    );
    expect(phase6['releaseBlocking'], isTrue);
    expect(
      phase6['evidence'],
      contains('${outputDir.path}/web-default-preflight-make-dom-default.json'),
    );
    final completionReleaseActions =
        (completionAudit['releaseActions'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      completionReleaseActions.singleWhere(
        (action) => action['id'] == 'run-automated-web-host-tests',
      )['status'],
      'required',
    );
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      [for (final action in actions) action['id']],
      [
        'verify-readiness-bundle',
        'run-automated-web-host-tests',
        'run-default-preflight:make-dom-default',
        'run-default-preflight:retire-temporary-paths',
      ],
    );
    final input = bundle['input'] as Map<String, Object?>;
    expect(input['commandWorkingDirectory'], Directory.current.absolute.path);
    expect(input['thresholdPolicyPath'], thresholdsPath);
    expect(input['thresholdReviewPath'], thresholdReviewPath);
    expect(input['requireScenarioThresholds'], isTrue);
    final artifacts = bundle['artifacts'] as Map<String, Object?>;
    final releaseActionsPath = artifacts['releaseActionsMarkdown'] as String;
    final releaseActionsMarkdown = File(releaseActionsPath).readAsStringSync();
    expect(releaseActionsMarkdown, contains('verify-readiness-bundle'));
    expect(
      releaseActionsMarkdown,
      contains('run-default-preflight:make-dom-default'),
    );
    expect(releaseActionsMarkdown, contains('run-automated-web-host-tests'));
    expect(releaseActionsMarkdown, contains('**Root command**'));
    expect(releaseActionsMarkdown, contains('tool/fleury_dev.dart'));
    expect(releaseActionsMarkdown, contains('**Browser test command**'));
    expect(
      releaseActionsMarkdown,
      contains(
        'dart test -p chrome test/browser_frame_flush_scheduler_test.dart',
      ),
    );
    expect(releaseActionsMarkdown, contains('**VM test command**'));
    expect(
      releaseActionsMarkdown,
      contains('dart test test/frame_presentation_test.dart'),
    );
    final verifyAction = actions.singleWhere(
      (action) => action['id'] == 'verify-readiness-bundle',
    );
    expect(verifyAction.containsKey('dependsOn'), isFalse);
    expect(
      verifyAction['rootCommandTemplate'] as List<Object?>,
      containsAll(<String>[
        'tool/fleury_dev.dart',
        'web-readiness-bundle',
        '--verify=${outputDir.path}/web-readiness-bundle.json',
      ]),
    );
    final automatedTestsAction = actions.singleWhere(
      (action) => action['id'] == 'run-automated-web-host-tests',
    );
    expect(automatedTestsAction['dependsOn'], ['verify-readiness-bundle']);
    final automatedTestsDetails =
        automatedTestsAction['details'] as Map<String, Object?>;
    expect(automatedTestsDetails['sourceInputGroup'], 'webAutomatedTestFiles');
    expect(
      automatedTestsDetails['automatedValidationJsonPath'],
      '${outputDir.path}/web-automated-validation.json',
    );
    expect(automatedTestsDetails['browserTestFileCount'], 9);
    expect(automatedTestsDetails['vmTestFileCount'], 4);
    expect(automatedTestsDetails['fixtureFileCount'], 1);
    expect(
      automatedTestsAction['commandTemplate'] as List<Object?>,
      contains('tool/web_automated_validation.dart'),
    );
    expect(
      automatedTestsAction['commandTemplate'] as List<Object?>,
      contains('--json-output=${outputDir.path}/web-automated-validation.json'),
    );
    expect(
      automatedTestsAction['rootCommandTemplate'] as List<Object?>,
      containsAll(<String>[
        'tool/fleury_dev.dart',
        'web-automated-validation',
        '--json-output=${outputDir.path}/web-automated-validation.json',
      ]),
    );
    expect(
      automatedTestsAction['browserTestCommand'] as List<Object?>,
      contains('test/mount_app_test.dart'),
    );
    expect(
      automatedTestsAction['vmTestCommand'] as List<Object?>,
      contains('test/web_public_api_boundary_test.dart'),
    );
    final preflightAction = actions.singleWhere(
      (action) => action['id'] == 'run-default-preflight:make-dom-default',
    );
    expect(preflightAction['dependsOn'], [
      'verify-readiness-bundle',
      'run-automated-web-host-tests',
    ]);
    final preflightDetails = preflightAction['details'] as Map<String, Object?>;
    expect(preflightDetails['generatedPreviewStrictPass'], isTrue);
    expect(preflightDetails['generatedPreviewBundleBound'], isFalse);
    expect(preflightDetails['generatedPreviewDiagnosticOnly'], isTrue);
    expect(preflightDetails['requiresBundleBinding'], isTrue);
    expect(
      preflightDetails['automatedValidationJsonPath'],
      '${outputDir.path}/web-automated-validation.json',
    );
    expect(
      preflightAction['rootCommandTemplate'] as List<Object?>,
      containsAll(<String>[
        'tool/fleury_dev.dart',
        'web-default-preflight',
        '--automated-validation=${outputDir.path}/web-automated-validation.json',
      ]),
    );
    final artifactFingerprints =
        bundle['artifactFingerprints'] as Map<String, Object?>;
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    for (final path
        in artifacts.entries
            .where((entry) => entry.value is String)
            .map((entry) => entry.value as String)) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(
      artifactFingerprints['scoreboard'],
      _fileFingerprint('${outputDir.path}/scoreboard.json'),
    );
    expect(
      artifactFingerprints['semanticAudit'],
      _fileFingerprint('${outputDir.path}/semantic-coverage.json'),
    );
    expect(
      artifactFingerprints['manualPlan'],
      _fileFingerprint('${outputDir.path}/manual-validation-plan.md'),
    );
    expect(
      File('${outputDir.path}/manual-validation-plan.md').readAsStringSync(),
      contains('dart test -p chrome test/manual_validation_page_test.dart'),
    );
    expect(
      artifactFingerprints['manualAudit'],
      _fileFingerprint('${outputDir.path}/manual-validation-audit.json'),
    );
    expect(
      artifactFingerprints['readinessJson'],
      _fileFingerprint('${outputDir.path}/web-readiness.json'),
    );
    expect(
      artifactFingerprints['readinessMarkdown'],
      _fileFingerprint('${outputDir.path}/web-readiness.md'),
    );
    final captureFingerprints =
        sourceInputFingerprints['captureFiles'] as List<Object?>;
    expect(captureFingerprints, hasLength(3));
    final firstCaptureFingerprint = captureFingerprints
        .cast<Map<String, Object?>>()
        .first;
    expect(firstCaptureFingerprint['path'], endsWith('normal-0.json'));
    expect(
      firstCaptureFingerprint['fingerprint'],
      _fileFingerprint('${capturesDir.path}/normal-0.json'),
    );
    final manualFingerprints =
        sourceInputFingerprints['manualEvidenceFiles'] as List<Object?>;
    expect(manualFingerprints, hasLength(2));
    final manualPageFingerprints =
        sourceInputFingerprints['manualValidationPageFiles'] as List<Object?>;
    final manualPageFingerprintPaths = manualPageFingerprints
        .cast<Map<String, Object?>>()
        .map((entry) => entry['path'])
        .toList();
    expect(
      manualPageFingerprintPaths,
      contains(File('web/manual_validation.dart').absolute.path),
    );
    expect(
      manualPageFingerprintPaths,
      contains(File('web/manual_validation.html').absolute.path),
    );
    expect(
      manualPageFingerprintPaths,
      contains(File('test/manual_validation_page_test.dart').absolute.path),
    );
    final manualValidationScript = File('web/manual_validation.dart.js');
    if (manualValidationScript.existsSync()) {
      expect(
        manualPageFingerprintPaths,
        contains(manualValidationScript.absolute.path),
      );
    }
    final webImplementationFingerprints =
        sourceInputFingerprints['webImplementationFiles'] as List<Object?>;
    final webImplementationFingerprintPaths = webImplementationFingerprints
        .cast<Map<String, Object?>>()
        .map((entry) => entry['path'])
        .toList();
    expect(
      webImplementationFingerprintPaths,
      contains(File('lib/fleury_web.dart').absolute.path),
    );
    expect(
      webImplementationFingerprintPaths,
      contains(File('lib/src/run_tui_surface.dart').absolute.path),
    );
    expect(
      webImplementationFingerprintPaths,
      contains(File('lib/src/dom_grid/dom_grid_surface.dart').absolute.path),
    );
    final automatedTestFingerprints =
        sourceInputFingerprints['webAutomatedTestFiles'] as List<Object?>;
    final automatedTestFingerprintPaths = automatedTestFingerprints
        .cast<Map<String, Object?>>()
        .map((entry) => entry['path'])
        .toList();
    expect(
      automatedTestFingerprintPaths,
      contains(File('test/mount_app_test.dart').absolute.path),
    );
    expect(
      automatedTestFingerprintPaths,
      contains(File('test/dom_input_source_test.dart').absolute.path),
    );
    expect(
      automatedTestFingerprintPaths,
      contains(File('test/semantic_dom_presenter_test.dart').absolute.path),
    );
    final fleuryCoreImplementationFingerprints =
        sourceInputFingerprints['fleuryCoreImplementationFiles']
            as List<Object?>;
    final fleuryCoreImplementationFingerprintPaths =
        fleuryCoreImplementationFingerprints
            .cast<Map<String, Object?>>()
            .map((entry) => entry['path'])
            .toList();
    expect(
      fleuryCoreImplementationFingerprintPaths,
      contains(_fleuryPackagePath('lib/fleury_core.dart')),
    );
    expect(
      fleuryCoreImplementationFingerprintPaths,
      contains(_fleuryPackagePath('lib/src/runtime/tui_runtime.dart')),
    );
    expect(
      fleuryCoreImplementationFingerprintPaths,
      contains(_fleuryPackagePath('lib/src/runtime/tui_frame_loop.dart')),
    );
    final readinessToolFingerprints =
        sourceInputFingerprints['readinessToolFiles'] as List<Object?>;
    final readinessToolFingerprintPaths = readinessToolFingerprints
        .cast<Map<String, Object?>>()
        .map((entry) => entry['path'])
        .toList();
    expect(
      readinessToolFingerprintPaths,
      contains(File('tool/web_readiness_bundle.dart').absolute.path),
    );
    expect(
      readinessToolFingerprintPaths,
      contains(File('tool/readiness_bundle_verifier.dart').absolute.path),
    );
    expect(
      readinessToolFingerprintPaths,
      contains(File('tool/web_default_preflight.dart').absolute.path),
    );
    final rootReleaseLauncherFingerprints =
        sourceInputFingerprints['rootReleaseLauncherFiles'] as List<Object?>;
    final rootReleaseLauncherFingerprintPaths = rootReleaseLauncherFingerprints
        .cast<Map<String, Object?>>()
        .map((entry) => entry['path'])
        .toList();
    final rootLauncherPath = _workspaceRootPath('tool/fleury_dev.dart');
    expect(rootReleaseLauncherFingerprintPaths, contains(rootLauncherPath));
    final rootLauncherFingerprint = rootReleaseLauncherFingerprints
        .cast<Map<String, Object?>>()
        .singleWhere((entry) => entry['path'] == rootLauncherPath);
    expect(
      rootLauncherFingerprint['fingerprint'],
      _fileFingerprint(rootLauncherPath),
    );
    final packageConfigurationFingerprints =
        sourceInputFingerprints['packageConfigurationFiles'] as List<Object?>;
    final packageConfigurationFingerprintPaths =
        packageConfigurationFingerprints
            .cast<Map<String, Object?>>()
            .map((entry) => entry['path'])
            .toList();
    expect(
      packageConfigurationFingerprintPaths,
      contains(File('pubspec.yaml').absolute.path),
    );
    expect(
      packageConfigurationFingerprintPaths,
      contains(File('pubspec.lock').absolute.path),
    );
    expect(
      packageConfigurationFingerprintPaths,
      contains(File('.dart_tool/package_config.json').absolute.path),
    );
    expect(
      packageConfigurationFingerprintPaths,
      contains(_fleuryPackagePath('pubspec.yaml')),
    );
    expect(
      packageConfigurationFingerprintPaths,
      contains(_fleuryPackagePath('pubspec.lock')),
    );
    expect(
      (sourceInputFingerprints['thresholdPolicy']
          as Map<String, Object?>)['fingerprint'],
      _fileFingerprint(thresholdsPath),
    );
    expect(
      (sourceInputFingerprints['thresholdReview']
          as Map<String, Object?>)['fingerprint'],
      _fileFingerprint(thresholdReviewPath),
    );
    final manifest =
        jsonDecode(
              File(
                '${outputDir.path}/web-readiness-bundle.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(manifest['kind'], 'fleuryWebReadinessBundle');
    expect(manifest['strictPass'], isTrue);
    final manifestArtifacts = manifest['artifacts'] as Map<String, Object?>;
    expect(
      manifestArtifacts['bundleJson'],
      '${outputDir.path}/web-readiness-bundle.json',
    );
    final manifestFingerprints =
        manifest['artifactFingerprints'] as Map<String, Object?>;
    expect(
      manifestFingerprints['scoreboard'],
      artifactFingerprints['scoreboard'],
    );
    final defaultPreflights =
        artifacts['defaultPreflights'] as Map<String, Object?>;
    final defaultPreflightFingerprints =
        artifactFingerprints['defaultPreflights'] as Map<String, Object?>;
    for (final targetId in ['make-dom-default', 'retire-temporary-paths']) {
      final targetArtifacts =
          defaultPreflights[targetId] as Map<String, Object?>;
      final targetFingerprints =
          defaultPreflightFingerprints[targetId] as Map<String, Object?>;
      final jsonPath = targetArtifacts['json'] as String;
      final markdownPath = targetArtifacts['markdown'] as String;
      expect(File(jsonPath).existsSync(), isTrue, reason: jsonPath);
      expect(File(markdownPath).existsSync(), isTrue, reason: markdownPath);
      expect(targetFingerprints['json'], _fileFingerprint(jsonPath));
      expect(targetFingerprints['markdown'], _fileFingerprint(markdownPath));
      final preflight =
          jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, Object?>;
      expect(preflight['kind'], 'fleuryWebDefaultPreflight');
      expect(preflight['target'], targetId);
      expect(preflight['bundleRequired'], isFalse);
      expect(preflight['bundleBound'], isFalse);
      expect(preflight['strictPass'], isTrue);
    }
    final checks = bundle['checks'] as Map<String, Object?>;
    expect(checks['defaultPreflightStrictPass'], {
      'make-dom-default': true,
      'retire-temporary-paths': true,
    });
    expect(checks['defaultPreflightBundleBound'], {
      'make-dom-default': false,
      'retire-temporary-paths': false,
    });
    expect(checks['defaultPreflightFinalGateRequiresBundle'], isTrue);
    final scoreboard =
        jsonDecode(File('${outputDir.path}/scoreboard.json').readAsStringSync())
            as Map<String, Object?>;
    expect(scoreboard['thresholdPolicyPath'], thresholdsPath);

    final readiness =
        jsonDecode(
              File('${outputDir.path}/web-readiness.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(readiness['kind'], 'fleuryWebReadinessAudit');
    expect(readiness['strictPass'], isTrue);
    expect(
      File('${outputDir.path}/web-readiness.md').readAsStringSync(),
      contains('Fleury Web Readiness Audit'),
    );

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);
    expect(verifyResult.exitCode, 0, reason: verifyResult.stderr.toString());
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['kind'], 'fleuryWebReadinessBundleVerification');
    expect(verification['strictPass'], isTrue);
    expect(verification['checkedArtifactCount'], 11);
    expect(
      verification['checkedSourceInputCount'],
      7 +
          manualPageFingerprints.length +
          webImplementationFingerprints.length +
          automatedTestFingerprints.length +
          fleuryCoreImplementationFingerprints.length +
          readinessToolFingerprints.length +
          rootReleaseLauncherFingerprints.length +
          packageConfigurationFingerprints.length,
    );
    expect(verification['sourceMismatchCount'], 0);
    expect(verification['checkedMetadataCount'], 1);
    expect(verification['metadataMismatchCount'], 0);
    expect(verification['missingMetadataCount'], 0);
  });

  test('completion audit keeps release blocked before final preflights', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);
    outputDir.createSync(recursive: true);
    final automatedValidationPath =
        '${outputDir.path}/web-automated-validation.json';
    _writeJson(automatedValidationPath, {
      'schemaVersion': 1,
      'kind': 'fleuryWebAutomatedValidation',
      'strictPass': true,
      'checks': [
        {'id': 'browser', 'strictPass': true, 'blockers': <String>[]},
        {'id': 'vm', 'strictPass': true, 'blockers': <String>[]},
      ],
    });
    final thresholdsPath = '${tempDir.path}/thresholds.json';
    final thresholdReviewPath = '${tempDir.path}/threshold-review.json';
    final completionAuditPath = '${tempDir.path}/completion-audit.json';
    final thresholdPolicy = {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameThresholds',
      'reviewState': 'reviewed',
      'reviewedBy': 'test reviewer',
      'reviewedAt': '2026-06-08T12:00:00.000000Z',
      'reviewContext': 'Chrome 127 macOS retained DOM completion audit test',
      'defaults': {'maxTotalFrameP95Ms': 16.67, 'maxSemanticUncoveredCells': 0},
      'scenarios': {
        'normal-80x24': {
          'maxTotalFrameP95Ms': 16.67,
          'maxOverBudgetPercent': 100,
          'maxSemanticUncoveredCells': 0,
        },
      },
    };
    _writeJson(thresholdsPath, thresholdPolicy);
    _writeThresholdReview(
      path: thresholdReviewPath,
      outputPath: thresholdsPath,
      reviewedBy: 'test reviewer',
      reviewedAt: '2026-06-08T12:00:00.000000Z',
      reviewContext: 'Chrome 127 macOS retained DOM completion audit test',
      scenarioCount: 1,
      outputPolicyFingerprint: _jsonFingerprint(thresholdPolicy),
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--thresholds=$thresholdsPath',
      '--threshold-review=$thresholdReviewPath',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--completion-audit=$completionAuditPath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final completionAudit =
        jsonDecode(File(completionAuditPath).readAsStringSync())
            as Map<String, Object?>;
    expect(completionAudit['releaseEvidenceReady'], isTrue);
    expect(completionAudit['releaseReady'], isFalse);
    expect(completionAudit['defaultFlipReady'], isFalse);
    expect(completionAudit['temporaryPathRetirementReady'], isFalse);
    expect(
      completionAudit['overallStatus'],
      'release-evidence-ready-default-actions-pending',
    );
    final completionScopes =
        completionAudit['completionScopes'] as Map<String, Object?>;
    final architectureScope =
        completionScopes['architectureReview'] as Map<String, Object?>;
    expect(architectureScope['ready'], isTrue);
    expect(architectureScope['deferredReleaseGateIds'], [
      'make-dom-default',
      'retire-temporary-paths',
    ]);
    final releaseEvidenceScope =
        completionScopes['releaseEvidence'] as Map<String, Object?>;
    expect(releaseEvidenceScope['ready'], isTrue);
    expect(releaseEvidenceScope['remainingReleaseActionIds'], isEmpty);
    expect(
      releaseEvidenceScope['satisfiedCurrentEvidenceActionIds'],
      containsAll(['verify-readiness-bundle', 'run-automated-web-host-tests']),
    );
    final releaseDefaultScope =
        completionScopes['releaseDefault'] as Map<String, Object?>;
    expect(releaseDefaultScope['ready'], isFalse);
    expect(releaseDefaultScope['remainingGateIds'], [
      'run-default-preflight:make-dom-default',
      'run-default-preflight:retire-temporary-paths',
    ]);
    expect(
      completionAudit['completionBlockers'],
      isNot(contains('automated retained-host validation artifact must pass')),
    );
    expect(
      completionAudit['completionBlockers'],
      isNot(
        contains(
          'strict Phase 6 readiness must pass after reviewed threshold and manual evidence',
        ),
      ),
    );
    expect(
      completionAudit['completionBlockers'],
      contains(
        'bundle-bound make-dom-default preflight must pass before changing the package default',
      ),
    );
    final releaseGateEvidence =
        completionAudit['releaseGateEvidence'] as Map<String, Object?>;
    final defaultPreflights =
        releaseGateEvidence['defaultPreflights'] as Map<String, Object?>;
    final makeDomDefault =
        defaultPreflights['make-dom-default'] as Map<String, Object?>;
    expect(makeDomDefault['ready'], isFalse);
    expect(makeDomDefault['status'], 'diagnostic-only');
    expect(makeDomDefault['diagnosticOnly'], isTrue);
    expect(makeDomDefault['bundleBound'], isFalse);
    expect(makeDomDefault['bundleRequired'], isFalse);
    expect(makeDomDefault['automatedValidationBound'], isTrue);
    expect(makeDomDefault['automatedValidationRequired'], isFalse);
    final phase6 = (completionAudit['phaseStatus'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((phase) => phase['phase'] == 'Phase 6');
    expect(phase6['status'], 'release-evidence-ready-default-actions-pending');
    expect(phase6['releaseBlocking'], isTrue);
  });

  test('web readiness bundle verification fails stale artifacts', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final scoreboardFile = File('${outputDir.path}/scoreboard.json');
    scoreboardFile.writeAsStringSync('${scoreboardFile.readAsStringSync()}\n');

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);

    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['mismatchCount'], 1);
    final mismatches = verification['mismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>().having(
        (mismatch) => mismatch['id'],
        'id',
        'scoreboard',
      ),
    );
  });

  test('web readiness bundle verification fails stale source inputs', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final captureFile = File('${capturesDir.path}/normal-0.json');
    captureFile.writeAsStringSync('${captureFile.readAsStringSync()}\n');

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);

    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['sourceMismatchCount'], 1);
    expect(verification['mismatchCount'], 0);
    final mismatches = verification['sourceMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>()
          .having((mismatch) => mismatch['id'], 'id', 'captureFiles[0]')
          .having(
            (mismatch) => mismatch['path'],
            'path',
            File('${capturesDir.path}/normal-0.json').absolute.path,
          ),
    );
  });

  test(
    'web readiness bundle verification fails stale embedded manual evidence fingerprints',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--target=chrome-ime-macos',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final artifacts = (bundle['artifacts'] as Map).cast<String, Object?>();
      final artifactFingerprints = (bundle['artifactFingerprints'] as Map)
          .cast<String, Object?>();
      final manualAuditPath = artifacts['manualAudit'] as String;
      final readinessPath = artifacts['readinessJson'] as String;

      final manualAuditFile = File(manualAuditPath);
      final manualAudit =
          jsonDecode(manualAuditFile.readAsStringSync())
              as Map<String, Object?>;
      final manualTargets = (manualAudit['targets'] as List<Object?>)
          .cast<Map<String, Object?>>();
      manualTargets.first['latestEntryFingerprint'] =
          'fnv1a64:0000000000000000';
      _writeJson(manualAuditPath, manualAudit);

      final readinessFile = File(readinessPath);
      final readiness =
          jsonDecode(readinessFile.readAsStringSync()) as Map<String, Object?>;
      final manualCheck = (readiness['checks'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((check) => check['id'] == 'manualValidation');
      final manualDetails = (manualCheck['details'] as Map)
          .cast<String, Object?>();
      final manualEvidence = (manualDetails['manualEvidence'] as List<Object?>)
          .cast<Map<String, Object?>>();
      manualEvidence.first['latestEntryFingerprint'] =
          'fnv1a64:0000000000000000';
      _writeJson(readinessPath, readiness);

      artifactFingerprints['manualAudit'] = readinessFileFingerprint(
        manualAuditPath,
      );
      artifactFingerprints['readinessJson'] = readinessFileFingerprint(
        readinessPath,
      );
      _writeJson(bundleFile.path, bundle);

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['mismatchCount'], 0);
      expect(verification['sourceMismatchCount'], 0);
      expect(verification['manifestMismatchCount'], 2);
      final manifestMismatches =
          verification['manifestMismatches'] as List<Object?>;
      expect(
        manifestMismatches,
        contains(
          isA<Map<String, Object?>>().having(
            (mismatch) => mismatch['id'],
            'id',
            'artifacts.manualAudit.targets.chrome-ime-macos.latestEntryFingerprint',
          ),
        ),
      );
      expect(
        manifestMismatches,
        contains(
          isA<Map<String, Object?>>().having(
            (mismatch) => mismatch['id'],
            'id',
            'artifacts.readiness.manualValidation.manualEvidence.chrome-ime-macos.latestEntryFingerprint',
          ),
        ),
      );
    },
  );

  test(
    'web readiness bundle verification fails stale generated preflight diagnostics',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final artifacts = (bundle['artifacts'] as Map).cast<String, Object?>();
      final defaultPreflights = (artifacts['defaultPreflights'] as Map)
          .cast<String, Object?>();
      final makeDomPreflight = (defaultPreflights['make-dom-default'] as Map)
          .cast<String, Object?>();
      final preflightJsonPath = makeDomPreflight['json'] as String;
      final preflight =
          jsonDecode(File(preflightJsonPath).readAsStringSync())
              as Map<String, Object?>;
      preflight['diagnosticOnly'] = false;
      _writeJson(preflightJsonPath, preflight);

      final artifactFingerprints = (bundle['artifactFingerprints'] as Map)
          .cast<String, Object?>();
      final preflightFingerprints =
          (artifactFingerprints['defaultPreflights'] as Map)
              .cast<String, Object?>();
      final makeDomFingerprints =
          (preflightFingerprints['make-dom-default'] as Map)
              .cast<String, Object?>();
      makeDomFingerprints['json'] = _fileFingerprint(preflightJsonPath);
      _writeJson(bundleFile.path, bundle);

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['mismatchCount'], 0);
      expect(verification['sourceMismatchCount'], 0);
      expect(verification['manifestMismatchCount'], 2);
      final manifestMismatches =
          verification['manifestMismatches'] as List<Object?>;
      expect(
        manifestMismatches,
        contains(
          isA<Map<String, Object?>>().having(
            (mismatch) => mismatch['id'],
            'id',
            'artifacts.defaultPreflights.make-dom-default.json.diagnosticOnly',
          ),
        ),
      );
      expect(
        manifestMismatches,
        contains(
          isA<Map<String, Object?>>().having(
            (mismatch) => mismatch['id'],
            'id',
            'remainingReleaseActions.run-default-preflight:make-dom-default.details.generatedPreviewDiagnosticOnly',
          ),
        ),
      );
    },
  );

  test(
    'web readiness bundle verification fails omitted implementation source',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final webImplementationFiles =
          sourceInputFingerprints['webImplementationFiles'] as List<Object?>;
      final omittedPath = File('lib/src/run_tui_surface.dart').absolute.path;
      webImplementationFiles.removeWhere((entry) {
        return (entry as Map<String, Object?>)['path'] == omittedPath;
      });
      bundleFile.writeAsStringSync(jsonEncode(bundle));

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['missingSourceInputCount'], 1);
      final missingSourceInputs =
          verification['missingSourceInputs'] as List<Object?>;
      expect(
        missingSourceInputs.single,
        isA<Map<String, Object?>>()
            .having((missing) => missing['id'], 'id', 'webImplementationFiles')
            .having((missing) => missing['path'], 'path', omittedPath),
      );
    },
  );

  test(
    'web readiness bundle verification fails stale implementation source',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final webImplementationFiles =
          sourceInputFingerprints['webImplementationFiles'] as List<Object?>;
      final runTuiSurfaceIndex = webImplementationFiles.indexWhere((entry) {
        return (entry as Map<String, Object?>)['path'] ==
            File('lib/src/run_tui_surface.dart').absolute.path;
      });
      expect(runTuiSurfaceIndex, isNot(-1));
      final runTuiSurfaceFingerprint = Map<String, Object?>.from(
        webImplementationFiles[runTuiSurfaceIndex] as Map<String, Object?>,
      );
      runTuiSurfaceFingerprint['fingerprint'] = 'fnv1a64:0000000000000000';
      webImplementationFiles[runTuiSurfaceIndex] = runTuiSurfaceFingerprint;
      bundleFile.writeAsStringSync(jsonEncode(bundle));

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['sourceMismatchCount'], 1);
      final mismatches = verification['sourceMismatches'] as List<Object?>;
      expect(
        mismatches.single,
        isA<Map<String, Object?>>()
            .having(
              (mismatch) => mismatch['id'],
              'id',
              startsWith('webImplementationFiles['),
            )
            .having(
              (mismatch) => mismatch['path'],
              'path',
              File('lib/src/run_tui_surface.dart').absolute.path,
            ),
      );
    },
  );

  test('web readiness bundle verification fails stale core source', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
    final bundle =
        jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    final coreImplementationFiles =
        sourceInputFingerprints['fleuryCoreImplementationFiles']
            as List<Object?>;
    final frameLoopIndex = coreImplementationFiles.indexWhere((entry) {
      return (entry as Map<String, Object?>)['path'] ==
          _fleuryPackagePath('lib/src/runtime/tui_frame_loop.dart');
    });
    expect(frameLoopIndex, isNot(-1));
    final frameLoopFingerprint = Map<String, Object?>.from(
      coreImplementationFiles[frameLoopIndex] as Map<String, Object?>,
    );
    frameLoopFingerprint['fingerprint'] = 'fnv1a64:0000000000000000';
    coreImplementationFiles[frameLoopIndex] = frameLoopFingerprint;
    bundleFile.writeAsStringSync(jsonEncode(bundle));

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);

    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['sourceMismatchCount'], 1);
    final mismatches = verification['sourceMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>()
          .having(
            (mismatch) => mismatch['id'],
            'id',
            startsWith('fleuryCoreImplementationFiles['),
          )
          .having(
            (mismatch) => mismatch['path'],
            'path',
            _fleuryPackagePath('lib/src/runtime/tui_frame_loop.dart'),
          ),
    );
  });

  test('web readiness bundle verification fails stale tool source', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
    final bundle =
        jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    final readinessToolFiles =
        sourceInputFingerprints['readinessToolFiles'] as List<Object?>;
    final bundleToolIndex = readinessToolFiles.indexWhere((entry) {
      return (entry as Map<String, Object?>)['path'] ==
          File('tool/web_readiness_bundle.dart').absolute.path;
    });
    expect(bundleToolIndex, isNot(-1));
    final bundleToolFingerprint = Map<String, Object?>.from(
      readinessToolFiles[bundleToolIndex] as Map<String, Object?>,
    );
    bundleToolFingerprint['fingerprint'] = 'fnv1a64:0000000000000000';
    readinessToolFiles[bundleToolIndex] = bundleToolFingerprint;
    bundleFile.writeAsStringSync(jsonEncode(bundle));

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);

    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['sourceMismatchCount'], 1);
    final mismatches = verification['sourceMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>()
          .having(
            (mismatch) => mismatch['id'],
            'id',
            startsWith('readinessToolFiles['),
          )
          .having(
            (mismatch) => mismatch['path'],
            'path',
            File('tool/web_readiness_bundle.dart').absolute.path,
          ),
    );
  });

  test(
    'web readiness bundle verification fails stale root release launcher',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final rootReleaseLauncherFiles =
          sourceInputFingerprints['rootReleaseLauncherFiles'] as List<Object?>;
      final launcherPath = _workspaceRootPath('tool/fleury_dev.dart');
      final launcherIndex = rootReleaseLauncherFiles.indexWhere((entry) {
        return (entry as Map<String, Object?>)['path'] == launcherPath;
      });
      expect(launcherIndex, isNot(-1));
      final launcherFingerprint = Map<String, Object?>.from(
        rootReleaseLauncherFiles[launcherIndex] as Map<String, Object?>,
      );
      launcherFingerprint['fingerprint'] = 'fnv1a64:0000000000000000';
      rootReleaseLauncherFiles[launcherIndex] = launcherFingerprint;
      bundleFile.writeAsStringSync(jsonEncode(bundle));

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['sourceMismatchCount'], 1);
      final mismatches = verification['sourceMismatches'] as List<Object?>;
      expect(
        mismatches.single,
        isA<Map<String, Object?>>()
            .having(
              (mismatch) => mismatch['id'],
              'id',
              startsWith('rootReleaseLauncherFiles['),
            )
            .having((mismatch) => mismatch['path'], 'path', launcherPath),
      );
    },
  );

  test(
    'web readiness bundle verification fails stale package configuration',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final packageConfigurationFiles =
          sourceInputFingerprints['packageConfigurationFiles'] as List<Object?>;
      final pubspecIndex = packageConfigurationFiles.indexWhere((entry) {
        return (entry as Map<String, Object?>)['path'] ==
            File('pubspec.yaml').absolute.path;
      });
      expect(pubspecIndex, isNot(-1));
      final pubspecFingerprint = Map<String, Object?>.from(
        packageConfigurationFiles[pubspecIndex] as Map<String, Object?>,
      );
      pubspecFingerprint['fingerprint'] = 'fnv1a64:0000000000000000';
      packageConfigurationFiles[pubspecIndex] = pubspecFingerprint;
      bundleFile.writeAsStringSync(jsonEncode(bundle));

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['sourceMismatchCount'], 1);
      final mismatches = verification['sourceMismatches'] as List<Object?>;
      expect(
        mismatches.single,
        isA<Map<String, Object?>>()
            .having(
              (mismatch) => mismatch['id'],
              'id',
              startsWith('packageConfigurationFiles['),
            )
            .having(
              (mismatch) => mismatch['path'],
              'path',
              File('pubspec.yaml').absolute.path,
            ),
      );
    },
  );

  test('web readiness bundle verification requires source groups', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
    final bundle =
        jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    sourceInputFingerprints.remove('webImplementationFiles');
    sourceInputFingerprints.remove('fleuryCoreImplementationFiles');
    sourceInputFingerprints.remove('readinessToolFiles');
    sourceInputFingerprints.remove('rootReleaseLauncherFiles');
    sourceInputFingerprints.remove('packageConfigurationFiles');
    sourceInputFingerprints.remove('webAutomatedTestFiles');
    bundleFile.writeAsStringSync(jsonEncode(bundle));

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);

    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['missingSourceFingerprintCount'], 6);
    expect(
      verification['missingSourceFingerprints'],
      containsAll([
        'fleuryCoreImplementationFiles',
        'packageConfigurationFiles',
        'readinessToolFiles',
        'rootReleaseLauncherFiles',
        'webAutomatedTestFiles',
        'webImplementationFiles',
      ]),
    );
  });

  test('web readiness bundle verification requires manual plan', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
    final bundle =
        jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
    final artifacts = bundle['artifacts'] as Map<String, Object?>;
    final artifactFingerprints =
        bundle['artifactFingerprints'] as Map<String, Object?>;
    artifacts.remove('manualPlan');
    artifactFingerprints.remove('manualPlan');
    bundleFile.writeAsStringSync(jsonEncode(bundle));

    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);

    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['missingManifestFieldCount'], 1);
    expect(
      verification['missingManifestFields'] as List<Object?>,
      contains('artifacts.manualPlan'),
    );
  });

  test(
    'web readiness bundle verification fails stale command working directory',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final input = bundle['input'] as Map<String, Object?>;
      input['commandWorkingDirectory'] = tempDir.path;
      bundleFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(bundle)}\n',
      );

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['metadataMismatchCount'], 1);
      expect(verification['missingMetadataCount'], 0);
      expect(verification['mismatchCount'], 0);
      expect(verification['sourceMismatchCount'], 0);
      final mismatches = verification['metadataMismatches'] as List<Object?>;
      expect(
        mismatches.single,
        isA<Map<String, Object?>>()
            .having(
              (mismatch) => mismatch['id'],
              'id',
              'input.commandWorkingDirectory',
            )
            .having(
              (mismatch) => mismatch['expected'],
              'expected',
              Directory.current.absolute.path,
            )
            .having((mismatch) => mismatch['actual'], 'actual', tempDir.path),
      );
    },
  );

  test('web readiness bundle verification fails stale release actions', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);
    final thresholdsPath = '${tempDir.path}/thresholds.json';
    final thresholdReviewPath = '${tempDir.path}/threshold-review.json';
    final thresholdPolicy = {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameThresholds',
      'reviewState': 'reviewed',
      'reviewedBy': 'test reviewer',
      'reviewedAt': '2026-06-08T12:00:00.000000Z',
      'reviewContext': 'Chrome 127 macOS retained DOM bundle test',
      'defaults': {'maxTotalFrameP95Ms': 16.67, 'maxSemanticUncoveredCells': 0},
      'scenarios': {
        'normal-80x24': {
          'maxTotalFrameP95Ms': 16.67,
          'maxSemanticUncoveredCells': 0,
        },
      },
    };
    _writeJson(thresholdsPath, thresholdPolicy);
    _writeThresholdReview(
      path: thresholdReviewPath,
      outputPath: thresholdsPath,
      reviewedBy: 'test reviewer',
      reviewedAt: '2026-06-08T12:00:00.000000Z',
      reviewContext: 'Chrome 127 macOS retained DOM bundle test',
      scenarioCount: 1,
      outputPolicyFingerprint: _jsonFingerprint(thresholdPolicy),
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--thresholds=$thresholdsPath',
      '--threshold-review=$thresholdReviewPath',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--strict',
      '--json',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final bundlePath = '${outputDir.path}/web-readiness-bundle.json';
    final bundle =
        jsonDecode(File(bundlePath).readAsStringSync()) as Map<String, Object?>;
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final automatedTestAction = actions.singleWhere(
      (action) => action['id'] == 'run-automated-web-host-tests',
    );
    final automatedTestDetails =
        automatedTestAction['details'] as Map<String, Object?>;
    final browserTestFiles =
        (automatedTestDetails['browserTestFiles'] as List<Object?>).toList();
    browserTestFiles[0] = 'test/stale_browser_test.dart';
    automatedTestDetails['browserTestFiles'] = browserTestFiles;
    final browserTestCommand =
        (automatedTestAction['browserTestCommand'] as List<Object?>).toList();
    browserTestCommand[4] = 'test/stale_browser_test.dart';
    automatedTestAction['browserTestCommand'] = browserTestCommand;
    final retirePreflightAction = actions.singleWhere(
      (action) =>
          action['id'] == 'run-default-preflight:retire-temporary-paths',
    );
    final retirePreflightDetails =
        retirePreflightAction['details'] as Map<String, Object?>;
    retirePreflightDetails['automatedValidationJsonPath'] =
        '${outputDir.path}/stale-web-automated-validation.json';
    actions.removeWhere(
      (action) => action['id'] == 'run-default-preflight:make-dom-default',
    );
    _writeJson(bundlePath, bundle);

    final verifyResult = await _run([
      '--verify=$bundlePath',
      '--strict',
      '--json',
    ]);
    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['strictPass'], isFalse);
    expect(verification['mismatchCount'], 0);
    expect(verification['manifestMismatchCount'], 6);
    expect(verification['missingManifestFieldCount'], 1);
    final manifestMismatches =
        verification['manifestMismatches'] as List<Object?>;
    expect(
      manifestMismatches,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.run-automated-web-host-tests.details.browserTestFiles',
        ),
      ),
    );
    expect(
      manifestMismatches,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.run-default-preflight:retire-temporary-paths.rootCommandTemplate',
        ),
      ),
    );
    expect(
      manifestMismatches,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.run-default-preflight:retire-temporary-paths.details.automatedValidationJsonPath',
        ),
      ),
    );
    expect(
      manifestMismatches,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.run-automated-web-host-tests.browserTestCommand',
        ),
      ),
    );
    expect(
      manifestMismatches,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.run-default-preflight:retire-temporary-paths.commandTemplate',
        ),
      ),
    );
    expect(
      manifestMismatches,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'artifacts.defaultPreflights.retire-temporary-paths.json.finalGateAutomatedValidationPath',
        ),
      ),
    );
    expect(
      verification['missingManifestFields'] as List<Object?>,
      contains(
        'remainingReleaseActions.run-default-preflight:make-dom-default',
      ),
    );
  });

  test('web readiness bundle reports manual evidence actions', () async {
    _writeCaptureSet(capturesDir);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-total-frame-p95-ms=20',
      '--max-fallback-cells=0',
      '--target=chrome-ime-macos',
      '--no-require-reviewed-threshold-policy',
      '--no-require-threshold-review-summary',
      '--no-require-scenario-thresholds',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final input = bundle['input'] as Map<String, Object?>;
    expect(input['targetPreset'], 'v1');
    expect(input['targetIds'], ['chrome-ime-macos']);
    expect(bundle['strictPass'], isFalse);
    final artifacts = bundle['artifacts'] as Map<String, Object?>;
    final releaseActionsPath = artifacts['releaseActionsMarkdown'] as String;
    expect(File(releaseActionsPath).existsSync(), isTrue);
    final releaseActionsMarkdown = File(releaseActionsPath).readAsStringSync();
    expect(releaseActionsMarkdown, contains('Fleury Web Release Actions'));
    expect(
      releaseActionsMarkdown,
      contains('collect-manual-evidence:chrome-ime-macos'),
    );
    expect(
      releaseActionsMarkdown,
      contains(
        '- Command working directory: `${Directory.current.absolute.path}`',
      ),
    );
    expect(
      releaseActionsMarkdown,
      contains('Run from: `${Directory.current.absolute.path}`'),
    );
    expect(releaseActionsMarkdown, contains('candidate-window-near-caret'));
    expect(releaseActionsMarkdown, contains('```sh'));
    expect(releaseActionsMarkdown, contains('**Manual page build command**'));
    expect(
      releaseActionsMarkdown,
      contains('**Manual page serve setup command**'),
    );
    expect(releaseActionsMarkdown, contains('**Manual page serve command**'));
    expect(
      releaseActionsMarkdown,
      contains(
        'dart compile js web/manual_validation.dart -o web/manual_validation.dart.js',
      ),
    );
    expect(releaseActionsMarkdown, contains('dart pub global activate dhttpd'));
    expect(
      releaseActionsMarkdown,
      contains('dart pub global run dhttpd --path web'),
    );
    expect(releaseActionsMarkdown, contains('**Starter command**'));
    expect(releaseActionsMarkdown, contains('**Root starter command**'));
    expect(releaseActionsMarkdown, contains('**Provenance command**'));
    expect(releaseActionsMarkdown, contains('**Page signal update command**'));
    expect(releaseActionsMarkdown, contains('**Check update command**'));
    expect(releaseActionsMarkdown, contains('**Root provenance command**'));
    expect(
      releaseActionsMarkdown,
      contains('**Root page signal update command**'),
    );
    expect(releaseActionsMarkdown, contains('**Root check update command**'));
    expect(releaseActionsMarkdown, contains('**Audit command**'));
    expect(releaseActionsMarkdown, contains('**Root audit command**'));
    expect(
      releaseActionsMarkdown,
      contains(
        '--update-provenance=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(
      releaseActionsMarkdown,
      contains(
        '--update-page-signal=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(
      releaseActionsMarkdown,
      contains(
        '--update-check=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(releaseActionsMarkdown, contains('tool/fleury_dev.dart'));
    expect(releaseActionsMarkdown, contains('web-manual-validation'));
    final fingerprints = bundle['artifactFingerprints'] as Map<String, Object?>;
    expect(
      fingerprints['releaseActionsMarkdown'],
      _fileFingerprint(releaseActionsPath),
    );
    final actions = bundle['remainingReleaseActions'] as List<Object?>;
    final actionIds = [
      for (final action in actions.cast<Map<String, Object?>>()) action['id'],
    ];
    expect(actionIds, contains('prepare-manual-evidence-templates'));
    expect(actionIds, contains('collect-manual-evidence:chrome-ime-macos'));
    expect(
      actionIds,
      isNot(contains('collect-manual-evidence:chrome-voiceover-macos')),
    );
    final prepareAction = actions.cast<Map<String, Object?>>().singleWhere(
      (action) => action['id'] == 'prepare-manual-evidence-templates',
    );
    expect(prepareAction['kind'], 'artifact-prep');
    final prepareDetails = prepareAction['details'] as Map<String, Object?>;
    expect(prepareDetails['templateStatus'], 'missing');
    final targetTemplates = prepareDetails['targetTemplates'] as List<Object?>;
    expect(
      targetTemplates,
      contains(
        isA<Map<String, Object?>>()
            .having(
              (template) => template['targetId'],
              'targetId',
              'chrome-ime-macos',
            )
            .having((template) => template['status'], 'status', 'missing'),
      ),
    );
    expect(
      prepareAction['commandTemplate'] as List<Object?>,
      contains('--write-templates=${manualDir.path}/templates'),
    );
    expect(
      prepareAction['commandTemplate'] as List<Object?>,
      contains('--target=chrome-ime-macos'),
    );
    expect(
      prepareAction['commandTemplate'] as List<Object?>,
      isNot(contains('--target=chrome-voiceover-macos')),
    );
    final rootPrepareCommand =
        prepareAction['rootCommandTemplate'] as List<Object?>;
    expect(rootPrepareCommand, contains('tool/fleury_dev.dart'));
    expect(rootPrepareCommand, contains('benchmark'));
    expect(rootPrepareCommand, contains('web-manual-validation'));
    expect(
      rootPrepareCommand,
      contains('--write-templates=${manualDir.path}/templates'),
    );
    expect(rootPrepareCommand, contains('--target=chrome-ime-macos'));
    expect(
      rootPrepareCommand,
      isNot(contains('--target=chrome-voiceover-macos')),
    );
    final imeAction = actions.cast<Map<String, Object?>>().singleWhere(
      (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
    );
    expect(imeAction['kind'], 'manual-validation');
    expect(
      imeAction['dependsOn'] as List<Object?>,
      contains('prepare-manual-evidence-templates'),
    );
    final details = imeAction['details'] as Map<String, Object?>;
    expect(details['requiredCheckCount'], 6);
    expect(
      details['missingCheckIds'] as List<Object?>,
      contains('candidate-window-near-caret'),
    );
    expect(details['manualValidationPage'], 'web/manual_validation.html');
    expect(details['requiredEvidencePage'], 'manual_validation.html');
    expect(details['manualPageCommandWorkingDirectory'], 'packages/fleury_web');
    expect(
      details['manualValidationReadySignal'],
      'document.body data-fleury-manual-validation="ready"',
    );
    expect(details['manualPageSmokeCommand'] as List<Object?>, [
      'dart',
      'test',
      '-p',
      'chrome',
      'test/manual_validation_page_test.dart',
    ]);
    expect(
      details['manualPageLocalUrl'],
      'http://localhost:8080/manual_validation.html',
    );
    expect(
      details['manualPageServeNote'],
      contains('http://localhost:8080/manual_validation.html'),
    );
    expect(
      details['manualPageServeNote'],
      contains('manualPageServeSetupCommand'),
    );
    expect(details['manualPageProvenanceAttributes'] as List<Object?>, [
      'data-fleury-manual-browser-version',
      'data-fleury-manual-platform',
      'data-fleury-manual-user-agent',
      'data-fleury-manual-page',
    ]);
    final pageSignals = details['requiredPageSignals'] as List<Object?>;
    expect(
      pageSignals,
      contains(
        isA<Map<String, Object?>>()
            .having((signal) => signal['id'], 'id', 'retained-dom-ready')
            .having(
              (signal) => signal['attribute'],
              'attribute',
              'data-fleury-manual-validation',
            )
            .having(
              (signal) => signal['expectedValue'],
              'expectedValue',
              'ready',
            ),
      ),
    );
    expect(
      pageSignals,
      contains(
        isA<Map<String, Object?>>()
            .having((signal) => signal['id'], 'id', 'ime-caret-positioned')
            .having(
              (signal) => signal['attribute'],
              'attribute',
              'data-fleury-caret-state',
            )
            .having(
              (signal) => signal['expectedValue'],
              'expectedValue',
              'positioned',
            ),
      ),
    );
    expect(
      details['starterEvidencePath'],
      '${manualDir.path}/evidence/chrome-ime-macos.review.json',
    );
    expect(
      details['suggestedEvidencePath'],
      '${manualDir.path}/evidence/chrome-ime-macos-YYYY-MM-DD.json',
    );
    expect(details['starterOverwritePolicy'], 'fail-if-destination-exists');
    expect(details['provenanceCommandRunnable'], isFalse);
    expect(details['checkCommandRunnable'], isFalse);
    expect(
      details['provenanceCommandPlaceholders'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((placeholder) => placeholder['name'], 'name', 'reviewer')
            .having(
              (placeholder) => placeholder['argument'],
              'argument',
              '--reviewed-by',
            ),
      ),
    );
    expect(
      details['checkCommandPlaceholders'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((placeholder) => placeholder['name'], 'name', 'checkId')
            .having(
              (placeholder) => placeholder['argument'],
              'argument',
              '--check-id',
            ),
      ),
    );
    expect(
      details['pageSignalCommandPlaceholders'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((placeholder) => placeholder['name'], 'name', 'signalId')
            .having(
              (placeholder) => placeholder['argument'],
              'argument',
              '--signal-id',
            ),
      ),
    );
    expect(details['reviewerNextStep'], contains('run starterCommand'));
    expect(
      details['reviewerNextStep'],
      contains('replace provenanceCommandTemplate placeholders'),
    );
    expect(
      details['reviewerNextStep'],
      contains('use pageSignalCommandTemplate for each required page signal'),
    );
    expect(
      details['reviewerNextStep'],
      contains('use checkCommandTemplate for each observed required check'),
    );
    expect(imeAction['manualPageBuildCommand'] as List<Object?>, [
      'dart',
      'compile',
      'js',
      'web/manual_validation.dart',
      '-o',
      'web/manual_validation.dart.js',
    ]);
    expect(imeAction['manualPageSmokeCommand'] as List<Object?>, [
      'dart',
      'test',
      '-p',
      'chrome',
      'test/manual_validation_page_test.dart',
    ]);
    expect(imeAction['manualPageServeCommand'] as List<Object?>, [
      'dart',
      'pub',
      'global',
      'run',
      'dhttpd',
      '--path',
      'web',
    ]);
    expect(imeAction['manualPageServeSetupCommand'] as List<Object?>, [
      'dart',
      'pub',
      'global',
      'activate',
      'dhttpd',
    ]);
    final starterCommand = imeAction['starterCommand'] as List<Object?>;
    expect(starterCommand, contains('dart'));
    expect(starterCommand, contains('run'));
    expect(starterCommand, contains('tool/web_manual_validation.dart'));
    expect(
      starterCommand,
      contains(
        '--write-starter=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(
      starterCommand,
      contains(
        '--starter-template=${manualDir.path}/templates/chrome-ime-macos.template.json',
      ),
    );
    expect(starterCommand, contains('--template-target=chrome-ime-macos'));
    final rootStarterCommand = imeAction['rootStarterCommand'] as List<Object?>;
    expect(rootStarterCommand, contains('tool/fleury_dev.dart'));
    expect(rootStarterCommand, contains('benchmark'));
    expect(rootStarterCommand, contains('web-manual-validation'));
    expect(
      rootStarterCommand,
      contains(
        '--write-starter=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(
      rootStarterCommand,
      contains(
        '--starter-template=${manualDir.path}/templates/chrome-ime-macos.template.json',
      ),
    );
    expect(rootStarterCommand, contains('--template-target=chrome-ime-macos'));
    final provenanceCommand =
        imeAction['provenanceCommandTemplate'] as List<Object?>;
    expect(provenanceCommand, contains('dart'));
    expect(provenanceCommand, contains('run'));
    expect(provenanceCommand, contains('tool/web_manual_validation.dart'));
    expect(
      provenanceCommand,
      contains(
        '--update-provenance=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(provenanceCommand, contains('--template-target=chrome-ime-macos'));
    expect(provenanceCommand, contains('--reviewed-by=<reviewer>'));
    expect(provenanceCommand, contains('--captured-at=now'));
    expect(
      provenanceCommand,
      contains('--browser-version=<Chrome version used for manual validation>'),
    );
    final pageSignalCommand =
        imeAction['pageSignalCommandTemplate'] as List<Object?>;
    expect(pageSignalCommand, contains('dart'));
    expect(pageSignalCommand, contains('run'));
    expect(pageSignalCommand, contains('tool/web_manual_validation.dart'));
    expect(
      pageSignalCommand,
      contains(
        '--update-page-signal=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(pageSignalCommand, contains('--template-target=chrome-ime-macos'));
    expect(
      pageSignalCommand,
      contains('--signal-id=<required-page-signal-id>'),
    );
    expect(pageSignalCommand, contains('--signal-status=pass'));
    expect(pageSignalCommand, contains('--observed-value=<expected-value>'));
    expect(
      pageSignalCommand,
      contains('--signal-notes=<reviewer observation>'),
    );
    final checkCommand = imeAction['checkCommandTemplate'] as List<Object?>;
    expect(checkCommand, contains('dart'));
    expect(checkCommand, contains('run'));
    expect(checkCommand, contains('tool/web_manual_validation.dart'));
    expect(
      checkCommand,
      contains(
        '--update-check=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(checkCommand, contains('--template-target=chrome-ime-macos'));
    expect(checkCommand, contains('--check-id=<required-check-id>'));
    expect(checkCommand, contains('--check-status=pass'));
    expect(checkCommand, contains('--check-notes=<reviewer observation>'));
    final rootProvenanceCommand =
        imeAction['rootProvenanceCommandTemplate'] as List<Object?>;
    expect(rootProvenanceCommand, contains('tool/fleury_dev.dart'));
    expect(rootProvenanceCommand, contains('benchmark'));
    expect(rootProvenanceCommand, contains('web-manual-validation'));
    expect(
      rootProvenanceCommand,
      contains(
        '--update-provenance=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(
      rootProvenanceCommand,
      contains('--template-target=chrome-ime-macos'),
    );
    expect(rootProvenanceCommand, contains('--reviewed-by=<reviewer>'));
    expect(rootProvenanceCommand, contains('--captured-at=now'));
    expect(
      rootProvenanceCommand,
      contains('--browser-version=<Chrome version used for manual validation>'),
    );
    final rootPageSignalCommand =
        imeAction['rootPageSignalCommandTemplate'] as List<Object?>;
    expect(rootPageSignalCommand, contains('tool/fleury_dev.dart'));
    expect(rootPageSignalCommand, contains('benchmark'));
    expect(rootPageSignalCommand, contains('web-manual-validation'));
    expect(
      rootPageSignalCommand,
      contains(
        '--update-page-signal=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(
      rootPageSignalCommand,
      contains('--template-target=chrome-ime-macos'),
    );
    expect(
      rootPageSignalCommand,
      contains('--signal-id=<required-page-signal-id>'),
    );
    expect(rootPageSignalCommand, contains('--signal-status=pass'));
    expect(
      rootPageSignalCommand,
      contains('--observed-value=<expected-value>'),
    );
    expect(
      rootPageSignalCommand,
      contains('--signal-notes=<reviewer observation>'),
    );
    final rootCheckCommand =
        imeAction['rootCheckCommandTemplate'] as List<Object?>;
    expect(rootCheckCommand, contains('tool/fleury_dev.dart'));
    expect(rootCheckCommand, contains('benchmark'));
    expect(rootCheckCommand, contains('web-manual-validation'));
    expect(
      rootCheckCommand,
      contains(
        '--update-check=${manualDir.path}/evidence/chrome-ime-macos.review.json',
      ),
    );
    expect(rootCheckCommand, contains('--template-target=chrome-ime-macos'));
    expect(rootCheckCommand, contains('--check-id=<required-check-id>'));
    expect(rootCheckCommand, contains('--check-status=pass'));
    expect(rootCheckCommand, contains('--check-notes=<reviewer observation>'));
    expect(
      imeAction['commandTemplate'] as List<Object?>,
      contains('--template-target=chrome-ime-macos'),
    );
    final rootTemplateCommand =
        imeAction['rootCommandTemplate'] as List<Object?>;
    expect(rootTemplateCommand, contains('tool/fleury_dev.dart'));
    expect(rootTemplateCommand, contains('benchmark'));
    expect(rootTemplateCommand, contains('web-manual-validation'));
    expect(
      rootTemplateCommand,
      contains(
        '--write-template=${manualDir.path}/templates/chrome-ime-macos.template.json',
      ),
    );
    expect(rootTemplateCommand, contains('--template-target=chrome-ime-macos'));
    final auditCommand = imeAction['auditCommand'] as List<Object?>;
    expect(auditCommand, contains('tool/web_manual_validation.dart'));
    expect(auditCommand, contains('--input=${manualDir.path}'));
    expect(auditCommand, contains('--target=chrome-ime-macos'));
    expect(
      auditCommand,
      contains('--json-output=${manualDir.path}/manual-validation-audit.json'),
    );
    expect(auditCommand, contains('--strict'));
    final rootAuditCommand = imeAction['rootAuditCommand'] as List<Object?>;
    expect(rootAuditCommand, contains('tool/fleury_dev.dart'));
    expect(rootAuditCommand, contains('benchmark'));
    expect(rootAuditCommand, contains('web-manual-validation'));
    expect(rootAuditCommand, contains('--input=${manualDir.path}'));
    expect(rootAuditCommand, contains('--target=chrome-ime-macos'));
    expect(
      rootAuditCommand,
      contains('--json-output=${manualDir.path}/manual-validation-audit.json'),
    );
    expect(rootAuditCommand, contains('--strict'));

    final staleRootTemplateCommand = rootTemplateCommand.toList();
    staleRootTemplateCommand[4] = 'web-manual-validation-stale';
    imeAction['rootCommandTemplate'] = staleRootTemplateCommand;
    final staleRootProvenanceCommand = rootProvenanceCommand.toList();
    staleRootProvenanceCommand[4] = 'web-manual-validation-stale';
    imeAction['rootProvenanceCommandTemplate'] = staleRootProvenanceCommand;
    final staleRootPageSignalCommand = rootPageSignalCommand.toList();
    staleRootPageSignalCommand[4] = 'web-manual-validation-stale';
    imeAction['rootPageSignalCommandTemplate'] = staleRootPageSignalCommand;
    final staleRootCheckCommand = rootCheckCommand.toList();
    staleRootCheckCommand[4] = 'web-manual-validation-stale';
    imeAction['rootCheckCommandTemplate'] = staleRootCheckCommand;
    final staleRootAuditCommand = rootAuditCommand.toList();
    staleRootAuditCommand[4] = 'web-manual-validation-stale';
    imeAction['rootAuditCommand'] = staleRootAuditCommand;
    _writeJson('${outputDir.path}/web-readiness-bundle.json', bundle);
    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);
    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['manifestMismatchCount'], 5);
    expect(
      verification['manifestMismatches'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.collect-manual-evidence:chrome-ime-macos.rootCommandTemplate',
        ),
      ),
    );
    expect(
      verification['manifestMismatches'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.collect-manual-evidence:chrome-ime-macos.rootCheckCommandTemplate',
        ),
      ),
    );
    expect(
      verification['manifestMismatches'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.collect-manual-evidence:chrome-ime-macos.rootPageSignalCommandTemplate',
        ),
      ),
    );
    expect(
      verification['manifestMismatches'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.collect-manual-evidence:chrome-ime-macos.rootProvenanceCommandTemplate',
        ),
      ),
    );
    expect(
      verification['manifestMismatches'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.collect-manual-evidence:chrome-ime-macos.rootAuditCommand',
        ),
      ),
    );
  });

  test(
    'web readiness bundle skips template prep action when templates exist',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
      );
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-voiceover-macos',
        checkIds: _chromeVoiceOverChecks,
      );

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-total-frame-p95-ms=20',
        '--max-fallback-cells=0',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--target=chrome-ime-macos',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundle =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(bundle['strictPass'], isFalse);
      final actions = (bundle['remainingReleaseActions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final actionIds = [for (final action in actions) action['id']];
      expect(actionIds, isNot(contains('prepare-manual-evidence-templates')));
      final imeAction = actions.singleWhere(
        (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
      );
      expect(imeAction.containsKey('dependsOn'), isFalse);
      expect(imeAction.containsKey('commandTemplate'), isFalse);
      final details = imeAction['details'] as Map<String, Object?>;
      expect(details['templateStatus'], 'current');
      expect(details['templateFingerprint'], startsWith('fnv1a64:'));
      expect(details, isNot(contains('templateBlockers')));
      expect(details['manualValidationPage'], 'web/manual_validation.html');
      expect(details['requiredEvidencePage'], 'manual_validation.html');
      expect(
        details['manualPageCommandWorkingDirectory'],
        'packages/fleury_web',
      );
      expect(
        details['manualValidationReadySignal'],
        'document.body data-fleury-manual-validation="ready"',
      );
      expect(details['manualPageSmokeCommand'] as List<Object?>, [
        'dart',
        'test',
        '-p',
        'chrome',
        'test/manual_validation_page_test.dart',
      ]);
      expect(
        details['manualPageLocalUrl'],
        'http://localhost:8080/manual_validation.html',
      );
      expect(
        details['manualPageServeNote'],
        contains('start checks only after the ready signal'),
      );
      expect(
        details['manualPageServeNote'],
        contains('manualPageServeSetupCommand'),
      );
      expect(details['manualPageProvenanceAttributes'] as List<Object?>, [
        'data-fleury-manual-browser-version',
        'data-fleury-manual-platform',
        'data-fleury-manual-user-agent',
        'data-fleury-manual-page',
      ]);
      final pageSignals = details['requiredPageSignals'] as List<Object?>;
      expect(
        pageSignals,
        contains(
          isA<Map<String, Object?>>()
              .having((signal) => signal['id'], 'id', 'retained-dom-ready')
              .having(
                (signal) => signal['attribute'],
                'attribute',
                'data-fleury-manual-validation',
              )
              .having(
                (signal) => signal['expectedValue'],
                'expectedValue',
                'ready',
              ),
        ),
      );
      expect(
        pageSignals,
        contains(
          isA<Map<String, Object?>>()
              .having((signal) => signal['id'], 'id', 'ime-caret-positioned')
              .having(
                (signal) => signal['attribute'],
                'attribute',
                'data-fleury-caret-state',
              )
              .having(
                (signal) => signal['expectedValue'],
                'expectedValue',
                'positioned',
              ),
        ),
      );
      expect(
        details['suggestedEvidencePath'],
        '${manualDir.path}/evidence/chrome-ime-macos-YYYY-MM-DD.json',
      );
      expect(
        details['starterEvidencePath'],
        '${manualDir.path}/evidence/chrome-ime-macos.review.json',
      );
      expect(details['starterOverwritePolicy'], 'fail-if-destination-exists');
      expect(details['reviewerNextStep'], contains('run starterCommand'));
      expect(imeAction['manualPageBuildCommand'] as List<Object?>, [
        'dart',
        'compile',
        'js',
        'web/manual_validation.dart',
        '-o',
        'web/manual_validation.dart.js',
      ]);
      expect(imeAction['manualPageSmokeCommand'] as List<Object?>, [
        'dart',
        'test',
        '-p',
        'chrome',
        'test/manual_validation_page_test.dart',
      ]);
      expect(imeAction['manualPageServeCommand'] as List<Object?>, [
        'dart',
        'pub',
        'global',
        'run',
        'dhttpd',
        '--path',
        'web',
      ]);
      expect(imeAction['manualPageServeSetupCommand'] as List<Object?>, [
        'dart',
        'pub',
        'global',
        'activate',
        'dhttpd',
      ]);
      final starterCommand = imeAction['starterCommand'] as List<Object?>;
      expect(starterCommand, contains('dart'));
      expect(starterCommand, contains('run'));
      expect(starterCommand, contains('tool/web_manual_validation.dart'));
      expect(
        starterCommand,
        contains(
          '--write-starter=${manualDir.path}/evidence/chrome-ime-macos.review.json',
        ),
      );
      expect(
        starterCommand,
        contains(
          '--starter-template=${manualDir.path}/templates/chrome-ime-macos.template.json',
        ),
      );
      expect(starterCommand, contains('--template-target=chrome-ime-macos'));
      final starterResult = await Process.run(Platform.resolvedExecutable, [
        for (final arg in starterCommand.skip(1)) arg.toString(),
      ], workingDirectory: Directory.current.path);
      expect(
        starterResult.exitCode,
        0,
        reason: starterResult.stderr.toString(),
      );
      final starterFile = File(
        '${manualDir.path}/evidence/chrome-ime-macos.review.json',
      );
      expect(starterFile.existsSync(), isTrue);
      final starterContents = starterFile.readAsStringSync();
      final starterJson = jsonDecode(starterContents) as Map<String, Object?>;
      expect(starterJson['targetId'], 'chrome-ime-macos');
      expect(starterJson['status'], 'needsReview');
      expect(starterJson['target'], isA<Map<String, Object?>>());
      final starterInstructions =
          starterJson['reviewInstructions'] as Map<String, Object?>;
      expect(starterInstructions['manualPageBuildCommand'], [
        'dart',
        'compile',
        'js',
        'web/manual_validation.dart',
        '-o',
        'web/manual_validation.dart.js',
      ]);
      expect(starterInstructions['manualPageSmokeCommand'], [
        'dart',
        'test',
        '-p',
        'chrome',
        'test/manual_validation_page_test.dart',
      ]);
      expect(starterInstructions['manualPageServeCommand'], [
        'dart',
        'pub',
        'global',
        'run',
        'dhttpd',
        '--path',
        'web',
      ]);
      starterFile.writeAsStringSync('review in progress\n');
      final overwriteResult = await Process.run(Platform.resolvedExecutable, [
        for (final arg in starterCommand.skip(1)) arg.toString(),
      ], workingDirectory: Directory.current.path);
      expect(overwriteResult.exitCode, 1);
      expect(
        overwriteResult.stderr.toString(),
        contains('starter evidence already exists:'),
      );
      expect(starterFile.readAsStringSync(), 'review in progress\n');
      starterFile.writeAsStringSync(starterContents);
      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final manualTemplateFiles =
          sourceInputFingerprints['manualTemplateFiles'] as List<Object?>;
      expect(manualTemplateFiles, hasLength(1));
      expect(
        manualTemplateFiles,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (template) => template['path'],
                'path',
                File(
                  '${manualDir.path}/templates/chrome-ime-macos.template.json',
                ).absolute.path,
              )
              .having(
                (template) => template['fingerprint'],
                'fingerprint',
                startsWith('fnv1a64:'),
              ),
        ),
      );
      final releaseActionsPath =
          (bundle['artifacts']
                  as Map<String, Object?>)['releaseActionsMarkdown']
              as String;
      final releaseActionsMarkdown = File(
        releaseActionsPath,
      ).readAsStringSync();
      expect(
        releaseActionsMarkdown,
        isNot(contains('prepare-manual-evidence-templates')),
      );
      expect(releaseActionsMarkdown, isNot(contains('--write-template=')));

      final templateFile = File(
        '${manualDir.path}/templates/chrome-ime-macos.template.json',
      );
      templateFile.writeAsStringSync('${templateFile.readAsStringSync()}\n');

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);
      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['sourceMismatchCount'], 1);
      final sourceMismatches =
          verification['sourceMismatches'] as List<Object?>;
      expect(
        sourceMismatches.single,
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          startsWith('manualTemplateFiles['),
        ),
      );
    },
  );

  test(
    'web readiness bundle treats existing starter evidence as edit target',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
      );
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-voiceover-macos',
        checkIds: _chromeVoiceOverChecks,
      );
      final evidenceDir = Directory('${manualDir.path}/evidence')..createSync();
      File(
        '${manualDir.path}/templates/chrome-ime-macos.template.json',
      ).copySync('${evidenceDir.path}/chrome-ime-macos.review.json');
      File(
        '${manualDir.path}/templates/chrome-voiceover-macos.template.json',
      ).copySync('${evidenceDir.path}/chrome-voiceover-macos.review.json');

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-total-frame-p95-ms=20',
        '--max-fallback-cells=0',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--target=chrome-ime-macos',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundle =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(bundle['strictPass'], isFalse);
      final actions = (bundle['remainingReleaseActions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect([
        for (final action in actions) action['id'],
      ], isNot(contains('prepare-manual-evidence-templates')));
      final imeAction = actions.singleWhere(
        (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
      );
      expect(imeAction.containsKey('starterCommand'), isFalse);
      expect(imeAction.containsKey('rootStarterCommand'), isFalse);
      final details = imeAction['details'] as Map<String, Object?>;
      expect(details['starterEvidenceStatus'], 'exists');
      expect(details['starterEvidenceFingerprint'], startsWith('fnv1a64:'));
      expect(
        details['reviewerNextStep'],
        contains('replace provenanceCommandTemplate placeholders'),
      );
      expect(
        details['reviewerNextStep'],
        isNot(contains('run starterCommand')),
      );
      expect(
        imeAction['provenanceCommandTemplate'] as List<Object?>,
        contains(
          '--update-provenance=${manualDir.path}/evidence/chrome-ime-macos.review.json',
        ),
      );
      expect(
        imeAction['rootProvenanceCommandTemplate'] as List<Object?>,
        contains('web-manual-validation'),
      );
      expect(
        imeAction['rootProvenanceCommandTemplate'] as List<Object?>,
        contains(
          '--update-provenance=${manualDir.path}/evidence/chrome-ime-macos.review.json',
        ),
      );
      expect(
        imeAction['rootAuditCommand'] as List<Object?>,
        contains('web-manual-validation'),
      );
      expect(
        imeAction['rootAuditCommand'] as List<Object?>,
        contains('--input=${manualDir.path}'),
      );
      expect(
        imeAction['rootAuditCommand'] as List<Object?>,
        contains(
          '--json-output=${manualDir.path}/manual-validation-audit.json',
        ),
      );

      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final manualEvidenceFiles =
          sourceInputFingerprints['manualEvidenceFiles'] as List<Object?>;
      expect(manualEvidenceFiles, hasLength(1));
      expect(
        manualEvidenceFiles,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (evidence) => evidence['path'],
                'path',
                File(
                  '${manualDir.path}/evidence/chrome-ime-macos.review.json',
                ).absolute.path,
              )
              .having(
                (evidence) => evidence['fingerprint'],
                'fingerprint',
                details['starterEvidenceFingerprint'],
              ),
        ),
      );
      final releaseActionsPath =
          (bundle['artifacts']
                  as Map<String, Object?>)['releaseActionsMarkdown']
              as String;
      final releaseActionsMarkdown = File(
        releaseActionsPath,
      ).readAsStringSync();
      expect(releaseActionsMarkdown, isNot(contains('**Starter command**')));
      expect(
        releaseActionsMarkdown,
        isNot(contains('**Root starter command**')),
      );
      expect(releaseActionsMarkdown, contains('**Provenance command**'));
      expect(releaseActionsMarkdown, contains('**Root provenance command**'));
      expect(releaseActionsMarkdown, contains('**Root audit command**'));
      expect(releaseActionsMarkdown, contains('starterEvidenceStatus'));
      expect(
        releaseActionsMarkdown,
        contains('replace provenanceCommandTemplate placeholders'),
      );
    },
  );

  test('web readiness bundle flags templates missing review metadata', () async {
    _writeCaptureSet(capturesDir);
    _writeLegacyManualTemplate(
      manualDir,
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-voiceover-macos',
      checkIds: _chromeVoiceOverChecks,
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-total-frame-p95-ms=20',
      '--max-fallback-cells=0',
      '--no-require-reviewed-threshold-policy',
      '--no-require-threshold-review-summary',
      '--no-require-scenario-thresholds',
      '--target=chrome-ime-macos',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final prepareAction = actions.singleWhere(
      (action) => action['id'] == 'prepare-manual-evidence-templates',
    );
    final details = prepareAction['details'] as Map<String, Object?>;
    expect(details['templateStatus'], 'stale');
    final targetTemplates = details['targetTemplates'] as List<Object?>;
    final imeTemplate = targetTemplates
        .cast<Map<String, Object?>>()
        .singleWhere((template) => template['targetId'] == 'chrome-ime-macos');
    expect(imeTemplate['status'], 'stale');
    expect(
      imeTemplate['blockers'] as List<Object?>,
      contains('template target.id must be chrome-ime-macos'),
    );
    expect(
      imeTemplate['blockers'] as List<Object?>,
      contains(
        'template reviewInstructions.manualValidationPage must be manual_validation.html',
      ),
    );
    expect(
      prepareAction['commandTemplate'] as List<Object?>,
      contains('--write-templates=${manualDir.path}/templates'),
    );
    final imeAction = actions.singleWhere(
      (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
    );
    expect(
      imeAction['dependsOn'] as List<Object?>,
      contains('prepare-manual-evidence-templates'),
    );
    final imeDetails = imeAction['details'] as Map<String, Object?>;
    expect(imeDetails['templateStatus'], 'stale');
    expect(
      imeDetails['templateBlockers'] as List<Object?>,
      contains('template target.id must be chrome-ime-macos'),
    );
  });

  test(
    'web readiness bundle flags templates that fail starter freshness',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
      );
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-voiceover-macos',
        checkIds: _chromeVoiceOverChecks,
      );
      final imeTemplatePath =
          '${manualDir.path}/templates/chrome-ime-macos.template.json';
      final imeTemplate =
          jsonDecode(File(imeTemplatePath).readAsStringSync())
              as Map<String, Object?>;
      final target = (imeTemplate['target'] as Map).cast<String, Object?>();
      target['inputMethod'] = 'Japanese Romaji test fixture';
      final environment = (imeTemplate['environment'] as Map)
          .cast<String, Object?>();
      environment['inputMethod'] = 'Japanese Romaji test fixture';
      final checks = (imeTemplate['checks'] as List<Object?>);
      checks.removeWhere(
        (check) => check is Map && check['id'] == 'candidate-window-near-caret',
      );
      _writeJson(imeTemplatePath, imeTemplate);

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-total-frame-p95-ms=20',
        '--max-fallback-cells=0',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--target=chrome-ime-macos',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundle =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final actions = (bundle['remainingReleaseActions'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final prepareAction = actions.singleWhere(
        (action) => action['id'] == 'prepare-manual-evidence-templates',
      );
      final details = prepareAction['details'] as Map<String, Object?>;
      expect(details['templateStatus'], 'stale');
      final targetTemplates = details['targetTemplates'] as List<Object?>;
      final imeTemplateStatus = targetTemplates
          .cast<Map<String, Object?>>()
          .singleWhere(
            (template) => template['targetId'] == 'chrome-ime-macos',
          );
      expect(imeTemplateStatus['status'], 'stale');
      expect(
        imeTemplateStatus['blockers'] as List<Object?>,
        contains(
          'template target.inputMethod must be Any real composing IME, such as Japanese Romaji',
        ),
      );
      expect(
        imeTemplateStatus['blockers'] as List<Object?>,
        contains(
          'template environment.inputMethod must be Any real composing IME, such as Japanese Romaji',
        ),
      );
      expect(
        imeTemplateStatus['blockers'] as List<Object?>,
        contains('template checks must include candidate-window-near-caret'),
      );
      final imeAction = actions.singleWhere(
        (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
      );
      expect(
        imeAction['dependsOn'] as List<Object?>,
        contains('prepare-manual-evidence-templates'),
      );
      final imeDetails = imeAction['details'] as Map<String, Object?>;
      expect(imeDetails['templateStatus'], 'stale');
      expect(
        imeDetails['templateBlockers'] as List<Object?>,
        contains('template checks must include candidate-window-near-caret'),
      );
    },
  );

  test('web readiness bundle flags stale manual check instructions', () async {
    _writeCaptureSet(capturesDir);
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-voiceover-macos',
      checkIds: _chromeVoiceOverChecks,
    );
    final imeTemplatePath =
        '${manualDir.path}/templates/chrome-ime-macos.template.json';
    final imeTemplate =
        jsonDecode(File(imeTemplatePath).readAsStringSync())
            as Map<String, Object?>;
    final checks = (imeTemplate['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final candidateCheck = checks.singleWhere(
      (check) => check['id'] == 'candidate-window-near-caret',
    );
    candidateCheck['notes'] = 'The browser IME candidate window is near caret.';
    _writeJson(imeTemplatePath, imeTemplate);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-total-frame-p95-ms=20',
      '--max-fallback-cells=0',
      '--no-require-reviewed-threshold-policy',
      '--no-require-threshold-review-summary',
      '--no-require-scenario-thresholds',
      '--target=chrome-ime-macos',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final prepareAction = actions.singleWhere(
      (action) => action['id'] == 'prepare-manual-evidence-templates',
    );
    final details = prepareAction['details'] as Map<String, Object?>;
    expect(details['templateStatus'], 'stale');
    final targetTemplates = details['targetTemplates'] as List<Object?>;
    final imeTemplateStatus = targetTemplates
        .cast<Map<String, Object?>>()
        .singleWhere((template) => template['targetId'] == 'chrome-ime-macos');
    expect(
      imeTemplateStatus['blockers'] as List<Object?>,
      contains(
        startsWith('template check candidate-window-near-caret notes must be'),
      ),
    );
    final imeAction = actions.singleWhere(
      (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
    );
    final imeDetails = imeAction['details'] as Map<String, Object?>;
    expect(
      imeDetails['templateBlockers'] as List<Object?>,
      contains(
        startsWith('template check candidate-window-near-caret notes must be'),
      ),
    );
  });

  test('web readiness bundle flags stale manual page signals', () async {
    _writeCaptureSet(capturesDir);
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-voiceover-macos',
      checkIds: _chromeVoiceOverChecks,
    );
    final imeTemplatePath =
        '${manualDir.path}/templates/chrome-ime-macos.template.json';
    final imeTemplate =
        jsonDecode(File(imeTemplatePath).readAsStringSync())
            as Map<String, Object?>;
    final reviewInstructions = (imeTemplate['reviewInstructions'] as Map)
        .cast<String, Object?>();
    final pageSignals =
        (reviewInstructions['requiredPageSignals'] as List<Object?>)
            .cast<Map<String, Object?>>();
    pageSignals.removeWhere((signal) => signal['id'] == 'ime-caret-positioned');
    _writeJson(imeTemplatePath, imeTemplate);

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-total-frame-p95-ms=20',
      '--max-fallback-cells=0',
      '--no-require-reviewed-threshold-policy',
      '--no-require-threshold-review-summary',
      '--no-require-scenario-thresholds',
      '--target=chrome-ime-macos',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final prepareAction = actions.singleWhere(
      (action) => action['id'] == 'prepare-manual-evidence-templates',
    );
    final details = prepareAction['details'] as Map<String, Object?>;
    expect(details['templateStatus'], 'stale');
    final targetTemplates = details['targetTemplates'] as List<Object?>;
    final imeTemplateStatus = targetTemplates
        .cast<Map<String, Object?>>()
        .singleWhere((template) => template['targetId'] == 'chrome-ime-macos');
    expect(
      imeTemplateStatus['blockers'] as List<Object?>,
      contains(
        'template reviewInstructions.requiredPageSignals must include retained-dom-ready ime-caret-positioned',
      ),
    );
    final imeAction = actions.singleWhere(
      (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
    );
    final imeDetails = imeAction['details'] as Map<String, Object?>;
    expect(
      imeDetails['templateBlockers'] as List<Object?>,
      contains(
        'template reviewInstructions.requiredPageSignals must include retained-dom-ready ime-caret-positioned',
      ),
    );
  });

  test('web readiness bundle flags stale manual page serve notes', () async {
    _writeCaptureSet(capturesDir);
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
      manualPageServeNote:
          'Run manualPageServeSetupCommand if dhttpd is not active, keep manualPageServeCommand running, open manualPageLocalUrl from that local server, and start checks only after the ready signal.',
    );
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-voiceover-macos',
      checkIds: _chromeVoiceOverChecks,
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-total-frame-p95-ms=20',
      '--max-fallback-cells=0',
      '--no-require-reviewed-threshold-policy',
      '--no-require-threshold-review-summary',
      '--no-require-scenario-thresholds',
      '--target=chrome-ime-macos',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final prepareAction = actions.singleWhere(
      (action) => action['id'] == 'prepare-manual-evidence-templates',
    );
    final details = prepareAction['details'] as Map<String, Object?>;
    expect(details['templateStatus'], 'stale');
    final targetTemplates = details['targetTemplates'] as List<Object?>;
    final imeTemplateStatus = targetTemplates
        .cast<Map<String, Object?>>()
        .singleWhere((template) => template['targetId'] == 'chrome-ime-macos');
    expect(imeTemplateStatus['status'], 'stale');
    expect(
      imeTemplateStatus['blockers'] as List<Object?>,
      contains(
        contains('template reviewInstructions.manualPageServeNote must be '),
      ),
    );
    expect(
      imeTemplateStatus['blockers'] as List<Object?>,
      contains(contains('open http://localhost:8080/manual_validation.html')),
    );
    final imeAction = actions.singleWhere(
      (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
    );
    expect(
      imeAction['dependsOn'] as List<Object?>,
      contains('prepare-manual-evidence-templates'),
    );
    final imeDetails = imeAction['details'] as Map<String, Object?>;
    expect(imeDetails['templateStatus'], 'stale');
    expect(
      imeDetails['templateBlockers'] as List<Object?>,
      contains(
        contains('template reviewInstructions.manualPageServeNote must be '),
      ),
    );
  });

  test('web readiness bundle actions preserve explicit manual targets', () async {
    _writeCaptureSet(capturesDir);
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    _writeManualTemplate(
      manualDir,
      targetId: 'chrome-voiceover-macos',
      checkIds: _chromeVoiceOverChecks,
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--max-total-frame-p95-ms=20',
      '--max-fallback-cells=0',
      '--no-require-reviewed-threshold-policy',
      '--no-require-threshold-review-summary',
      '--no-require-scenario-thresholds',
      '--target=chrome-ime-macos',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final input = bundle['input'] as Map<String, Object?>;
    expect(input['targetPreset'], 'v1');
    expect(input['targetIds'], ['chrome-ime-macos']);
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    final manualTemplateFiles =
        sourceInputFingerprints['manualTemplateFiles'] as List<Object?>;
    expect(manualTemplateFiles, hasLength(1));
    expect(
      manualTemplateFiles.single,
      isA<Map<String, Object?>>()
          .having(
            (template) => template['path'],
            'path',
            File(
              '${manualDir.path}/templates/chrome-ime-macos.template.json',
            ).absolute.path,
          )
          .having(
            (template) => template['path'],
            'path',
            isNot(
              File(
                '${manualDir.path}/templates/chrome-voiceover-macos.template.json',
              ).absolute.path,
            ),
          ),
    );

    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final actionIds = [for (final action in actions) action['id']];
    expect(actionIds, isNot(contains('prepare-manual-evidence-templates')));
    final imeAction = actions.singleWhere(
      (action) => action['id'] == 'collect-manual-evidence:chrome-ime-macos',
    );
    expect(imeAction.containsKey('dependsOn'), isFalse);
    expect(imeAction.containsKey('commandTemplate'), isFalse);
    expect(
      imeAction['auditCommand'] as List<Object?>,
      contains('--target=chrome-ime-macos'),
    );
    expect(
      imeAction['auditCommand'] as List<Object?>,
      isNot(contains('--target-preset=v1')),
    );
    final regenerateAction = actions.singleWhere(
      (action) => action['id'] == 'regenerate-readiness-bundle',
    );
    expect(
      regenerateAction['commandTemplate'] as List<Object?>,
      contains('--target=chrome-ime-macos'),
    );
    expect(
      regenerateAction['commandTemplate'] as List<Object?>,
      isNot(contains('--target-preset=v1')),
    );
  });

  test(
    'web readiness bundle verification rejects stale manual target scope',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
      );
      _writeManualTemplate(
        manualDir,
        targetId: 'chrome-voiceover-macos',
        checkIds: _chromeVoiceOverChecks,
      );

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-total-frame-p95-ms=20',
        '--max-fallback-cells=0',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--target=chrome-ime-macos',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundleFile = File('${outputDir.path}/web-readiness-bundle.json');
      final bundle =
          jsonDecode(bundleFile.readAsStringSync()) as Map<String, Object?>;
      final input = bundle['input'] as Map<String, Object?>;
      input.remove('targetIds');
      input['targetPreset'] = 'all';
      bundleFile.writeAsStringSync(jsonEncode(bundle));

      final verifyResult = await _run([
        '--verify=${outputDir.path}/web-readiness-bundle.json',
        '--strict',
        '--json',
      ]);

      expect(verifyResult.exitCode, 1);
      final verification =
          jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
      expect(verification['strictPass'], isFalse);
      expect(verification['missingSourceInputCount'], greaterThanOrEqualTo(1));
      expect(
        verification['missingSourceInputs'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>()
              .having((missing) => missing['id'], 'id', 'manualTemplateFiles')
              .having(
                (missing) => missing['path'],
                'path',
                File(
                  '${manualDir.path}/templates/chrome-voiceover-macos.template.json',
                ).absolute.path,
              ),
        ),
      );
      expect(verification['manifestMismatchCount'], greaterThanOrEqualTo(1));
      expect(
        verification['manifestMismatches'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>().having(
            (mismatch) => mismatch['id'],
            'id',
            'artifacts.manualAudit.targets',
          ),
        ),
      );
    },
  );

  test('web readiness bundle actions promote candidate thresholds', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);
    final thresholdsPath = '${tempDir.path}/thresholds.candidate.json';
    final thresholdPolicy = {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameThresholds',
      'reviewState': 'candidate',
      'generatedFrom': {
        'captureEnvironment': {
          'reviewContextHint':
              'Browser Chrome/127, OS ${Platform.operatingSystem}, retained DOM product baseline',
        },
      },
      'defaults': {'maxTotalFrameP95Ms': 16.67, 'maxSemanticUncoveredCells': 0},
      'scenarios': {
        'normal-80x24': {
          'maxTotalFrameP95Ms': 16.67,
          'maxOverBudgetPercent': 100,
          'maxSemanticUncoveredCells': 0,
        },
      },
    };
    _writeJson(thresholdsPath, thresholdPolicy);
    final planPath = '${tempDir.path}/threshold-review-plan.md';
    File(planPath).writeAsStringSync(
      '# Fleury Web Threshold Review Plan\n\n'
      '- Input fingerprint: `${_jsonFingerprint(thresholdPolicy)}`\n',
    );

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--thresholds=$thresholdsPath',
      '--max-fallback-cells=0',
      '--write-default-preflights',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(bundle['strictPass'], isFalse);
    final actions = (bundle['remainingReleaseActions'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final thresholdAction = actions.singleWhere(
      (action) => action['id'] == 'review-threshold-policy',
    );
    expect(
      thresholdAction['planCommand'] as List<Object?>,
      contains('--write-plan=${tempDir.path}/threshold-review-plan.md'),
    );
    expect(
      thresholdAction['planCommand'] as List<Object?>,
      isNot(contains(startsWith('--review-context-hint='))),
    );
    final details = thresholdAction['details'] as Map<String, Object?>;
    expect(details['commandTemplateRunnable'], isFalse);
    expect(details['planCommandUsesCandidateCapturedContext'], isTrue);
    expect(
      details['candidateReviewContextHint'],
      contains('Browser Chrome/127'),
    );
    expect(
      details['reviewerNextStep'],
      contains('verify suggestedReviewContext'),
    );
    expect(details['overBudgetThresholdScenarioCount'], 1);
    expect(details['overBudgetAcknowledgementRequired'], isTrue);
    expect(
      details['overBudgetThresholdScenarios'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>()
            .having((scenario) => scenario['id'], 'id', 'normal-80x24')
            .having(
              (scenario) => scenario['maxOverBudgetPercent'],
              'maxOverBudgetPercent',
              100,
            ),
      ),
    );
    expect(details['suggestedReviewContext'], contains('Browser Chrome/127'));
    final placeholders =
        (details['commandTemplatePlaceholders'] as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(
      placeholders,
      contains(
        isA<Map<String, Object?>>()
            .having((placeholder) => placeholder['name'], 'name', 'reviewer')
            .having(
              (placeholder) => placeholder['argument'],
              'argument',
              '--reviewed-by',
            )
            .having(
              (placeholder) => placeholder['placeholder'],
              'placeholder',
              '<reviewer>',
            ),
      ),
    );
    expect(
      placeholders,
      contains(
        isA<Map<String, Object?>>()
            .having((placeholder) => placeholder['name'], 'name', 'reviewNote')
            .having(
              (placeholder) => placeholder['argument'],
              'argument',
              '--review-note',
            ),
      ),
    );
    expect(
      placeholders,
      isNot(
        contains(
          isA<Map<String, Object?>>().having(
            (placeholder) => placeholder['name'],
            'name',
            'reviewContext',
          ),
        ),
      ),
    );
    expect(details['thresholdReviewPlanStatus'], 'current');
    expect(
      details['thresholdReviewPlanInputFingerprint'],
      _jsonFingerprint(thresholdPolicy),
    );
    expect(
      details['expectedInputFingerprint'],
      _jsonFingerprint(thresholdPolicy),
    );
    expect(
      thresholdAction['planCommand'] as List<Object?>,
      isNot(contains('--output=${tempDir.path}/thresholds.json')),
    );
    expect(
      thresholdAction['rootPlanCommand'] as List<Object?>,
      contains('tool/fleury_dev.dart'),
    );
    expect(
      thresholdAction['rootPlanCommand'] as List<Object?>,
      contains('benchmark'),
    );
    expect(
      thresholdAction['rootPlanCommand'] as List<Object?>,
      contains('web-threshold-review'),
    );
    expect(
      thresholdAction['rootPlanCommand'] as List<Object?>,
      contains('--write-plan=${tempDir.path}/threshold-review-plan.md'),
    );
    final releaseActionsMarkdown = File(
      (bundle['artifacts'] as Map<String, Object?>)['releaseActionsMarkdown']
          as String,
    ).readAsStringSync();
    expect(releaseActionsMarkdown, contains('**Root plan command**'));
    expect(releaseActionsMarkdown, contains('web-threshold-review'));
    expect(
      thresholdAction['commandTemplate'] as List<Object?>,
      contains('--output=${tempDir.path}/thresholds.json'),
    );
    expect(
      thresholdAction['commandTemplate'] as List<Object?>,
      contains(
        '--expect-input-fingerprint=${_jsonFingerprint(thresholdPolicy)}',
      ),
    );
    expect(
      thresholdAction['commandTemplate'] as List<Object?>,
      contains(startsWith('--review-context=Browser Chrome/127')),
    );
    expect(
      thresholdAction['commandTemplate'] as List<Object?>,
      contains('--allow-over-budget-thresholds'),
    );
    expect(
      thresholdAction['commandTemplate'] as List<Object?>,
      contains(
        '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
      ),
    );
    final rootCommandTemplate =
        thresholdAction['rootCommandTemplate'] as List<Object?>;
    expect(rootCommandTemplate, contains('tool/fleury_dev.dart'));
    expect(rootCommandTemplate, contains('benchmark'));
    expect(rootCommandTemplate, contains('web-threshold-review'));
    expect(
      rootCommandTemplate,
      contains('--output=${tempDir.path}/thresholds.json'),
    );
    expect(
      rootCommandTemplate,
      contains(
        '--expect-input-fingerprint=${_jsonFingerprint(thresholdPolicy)}',
      ),
    );
    expect(rootCommandTemplate, contains('--reviewed-by=<reviewer>'));
    expect(
      rootCommandTemplate,
      contains(startsWith('--review-context=Browser Chrome/127')),
    );
    expect(rootCommandTemplate, contains('--allow-over-budget-thresholds'));
    expect(
      rootCommandTemplate,
      contains(
        '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
      ),
    );
    final regenerateAction = actions.singleWhere(
      (action) => action['id'] == 'regenerate-readiness-bundle',
    );
    expect(
      regenerateAction['commandTemplate'] as List<Object?>,
      contains('--thresholds=${tempDir.path}/thresholds.json'),
    );
    final regenerateDetails =
        regenerateAction['details'] as Map<String, Object?>;
    expect(regenerateDetails['captureDir'], capturesDir.path);
    expect(regenerateDetails['manualDir'], manualDir.path);
    expect(regenerateDetails['outputDir'], outputDir.path);
    expect(
      regenerateDetails['bundleJsonPath'],
      '${outputDir.path}/web-readiness-bundle.json',
    );
    expect(
      regenerateDetails['readinessJsonPath'],
      '${outputDir.path}/web-readiness.json',
    );
    expect(
      regenerateDetails['thresholdPolicyPath'],
      '${tempDir.path}/thresholds.json',
    );
    expect(regenerateDetails['strictRequired'], isTrue);
    expect(regenerateDetails['writeDefaultPreflights'], isTrue);
    expect(
      regenerateDetails['reviewerNextStep'],
      contains('manual-validation dependencies pass'),
    );
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    final thresholdReviewPlan =
        sourceInputFingerprints['thresholdReviewPlan'] as Map<String, Object?>;
    expect(thresholdReviewPlan['path'], File(planPath).absolute.path);
    expect(thresholdReviewPlan['fingerprint'], _fileFingerprint(planPath));

    final staleRootCommand = rootCommandTemplate.toList();
    staleRootCommand[4] = 'web-threshold-review-stale';
    thresholdAction['rootCommandTemplate'] = staleRootCommand;
    _writeJson('${outputDir.path}/web-readiness-bundle.json', bundle);
    final verifyResult = await _run([
      '--verify=${outputDir.path}/web-readiness-bundle.json',
      '--strict',
      '--json',
    ]);
    expect(verifyResult.exitCode, 1);
    final verification =
        jsonDecode(verifyResult.stdout.toString()) as Map<String, Object?>;
    expect(verification['manifestMismatchCount'], 1);
    expect(
      verification['manifestMismatches'] as List<Object?>,
      contains(
        isA<Map<String, Object?>>().having(
          (mismatch) => mismatch['id'],
          'id',
          'remainingReleaseActions.review-threshold-policy.rootCommandTemplate',
        ),
      ),
    );
  });

  test('web readiness bundle can relax scenario thresholds', () async {
    _writeCaptureSet(capturesDir);
    _writeManualEvidence(manualDir);
    final thresholdsPath = '${tempDir.path}/thresholds.json';
    _writeJson(thresholdsPath, {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameThresholds',
      'reviewState': 'reviewed',
      'reviewedBy': 'test reviewer',
      'reviewedAt': '2026-06-08T12:00:00.000000Z',
      'reviewContext': 'Chrome 127 macOS relaxed scenario bundle test',
      'defaults': {'maxTotalFrameP95Ms': 16.67, 'maxSemanticUncoveredCells': 0},
    });

    final result = await _run([
      '--captures=${capturesDir.path}',
      '--manual=${manualDir.path}',
      '--output-dir=${outputDir.path}',
      '--thresholds=$thresholdsPath',
      '--max-fallback-cells=0',
      '--no-require-scenario-thresholds',
      '--no-require-threshold-review-summary',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final bundle = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(bundle['strictPass'], isTrue);
    final input = bundle['input'] as Map<String, Object?>;
    expect(input['requireScenarioThresholds'], isFalse);
    expect(input['requireThresholdReviewSummary'], isFalse);
  });

  test(
    'web readiness bundle keeps artifacts when strict readiness fails',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);
      final completionAuditPath = '${tempDir.path}/completion-audit.json';

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--completion-audit=$completionAuditPath',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final bundle =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(bundle['strictPass'], isFalse);
      expect(File('${outputDir.path}/scoreboard.json').existsSync(), isTrue);
      expect(
        File('${outputDir.path}/semantic-coverage.json').existsSync(),
        isTrue,
      );
      expect(
        File('${outputDir.path}/manual-validation-audit.json').existsSync(),
        isTrue,
      );
      expect(
        File('${outputDir.path}/manual-validation-plan.md').existsSync(),
        isTrue,
      );
      expect(File(completionAuditPath).existsSync(), isTrue);
      final fingerprints =
          bundle['artifactFingerprints'] as Map<String, Object?>;
      expect(fingerprints['scoreboard'], startsWith('fnv1a64:'));
      expect(fingerprints['manualPlan'], startsWith('fnv1a64:'));
      expect(fingerprints['readinessJson'], startsWith('fnv1a64:'));
      final preflightFingerprints =
          fingerprints['defaultPreflights'] as Map<String, Object?>;
      expect(
        (preflightFingerprints['make-dom-default']
            as Map<String, Object?>)['json'],
        startsWith('fnv1a64:'),
      );
      final manifestPath = '${outputDir.path}/web-readiness-bundle.json';
      expect(File(manifestPath).existsSync(), isTrue);
      final manifest =
          jsonDecode(File(manifestPath).readAsStringSync())
              as Map<String, Object?>;
      expect(manifest['strictPass'], isFalse);
      final manifestChecks = manifest['checks'] as Map<String, Object?>;
      expect(manifestChecks['defaultPreflightStrictPass'], {
        'make-dom-default': false,
        'retire-temporary-paths': false,
      });
      expect(manifestChecks['defaultPreflightBundleBound'], {
        'make-dom-default': false,
        'retire-temporary-paths': false,
      });
      expect(manifestChecks['defaultPreflightFinalGateRequiresBundle'], isTrue);
      for (final targetId in ['make-dom-default', 'retire-temporary-paths']) {
        final jsonPath =
            '${outputDir.path}/web-default-preflight-$targetId.json';
        final markdownPath =
            '${outputDir.path}/web-default-preflight-$targetId.md';
        expect(File(jsonPath).existsSync(), isTrue, reason: jsonPath);
        expect(File(markdownPath).existsSync(), isTrue, reason: markdownPath);
        final preflight =
            jsonDecode(File(jsonPath).readAsStringSync())
                as Map<String, Object?>;
        expect(preflight['target'], targetId);
        expect(preflight['diagnosticOnly'], isTrue);
        expect(preflight['diagnosticReason'], contains('Unbundled'));
        expect(preflight['finalGateRequiresBundle'], isTrue);
        expect(preflight['finalGateRequiresAutomatedValidation'], isTrue);
        expect(
          preflight['finalGateBundlePath'],
          '${outputDir.path}/web-readiness-bundle.json',
        );
        expect(
          preflight['finalGateAutomatedValidationPath'],
          '${outputDir.path}/web-automated-validation.json',
        );
        expect(preflight['bundleRequired'], isFalse);
        expect(preflight['bundleBound'], isFalse);
        expect(preflight['strictPass'], isFalse);
      }
      final actions = bundle['remainingReleaseActions'] as List<Object?>;
      final actionIds = [
        for (final action in actions.cast<Map<String, Object?>>()) action['id'],
      ];
      expect(actionIds, contains('review-threshold-policy'));
      expect(actionIds, contains('regenerate-readiness-bundle'));
      expect(actionIds, contains('verify-readiness-bundle'));
      expect(actionIds, contains('run-automated-web-host-tests'));
      expect(actionIds, contains('run-default-preflight:make-dom-default'));
      expect(
        actionIds,
        contains('run-default-preflight:retire-temporary-paths'),
      );
      final thresholdAction = actions.cast<Map<String, Object?>>().singleWhere(
        (action) => action['id'] == 'review-threshold-policy',
      );
      expect(thresholdAction['kind'], 'human-review');
      final thresholdDetails =
          thresholdAction['details'] as Map<String, Object?>;
      expect(thresholdDetails['commandTemplateRunnable'], isFalse);
      final captureEnvironment =
          thresholdDetails['captureEnvironment'] as Map<String, Object?>;
      expect(captureEnvironment['scenarioCount'], 1);
      expect(captureEnvironment['scenarioWithEnvironmentCount'], 1);
      expect(captureEnvironment['comparableScenarioCount'], 1);
      expect(captureEnvironment['allScenariosComparable'], isTrue);
      expect(captureEnvironment['chromeBrowser'], 'Chrome/127');
      expect(captureEnvironment['operatingSystem'], Platform.operatingSystem);
      expect(captureEnvironment['frameBudgetMs'], 16.67);
      expect(captureEnvironment['requestedFrames'], 2);
      expect(
        captureEnvironment['reviewContextHint'],
        contains('Browser Chrome/127'),
      );
      expect(
        thresholdDetails['commandTemplatePlaceholders'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>().having(
            (placeholder) => placeholder['placeholder'],
            'placeholder',
            '<reviewer>',
          ),
        ),
      );
      expect(
        thresholdDetails['suggestedReviewContext'],
        contains('Browser Chrome/127'),
      );
      expect(
        thresholdAction['commandTemplate'] as List<Object?>,
        contains('--reviewed-by=<reviewer>'),
      );
      expect(
        thresholdAction['commandTemplate'] as List<Object?>,
        contains(startsWith('--review-context=Browser Chrome/127')),
      );
      final regenerateAction = actions.cast<Map<String, Object?>>().singleWhere(
        (action) => action['id'] == 'regenerate-readiness-bundle',
      );
      final regenerateDetails =
          regenerateAction['details'] as Map<String, Object?>;
      expect(regenerateDetails['captureDir'], capturesDir.path);
      expect(regenerateDetails['manualDir'], manualDir.path);
      expect(regenerateDetails['outputDir'], outputDir.path);
      expect(regenerateDetails['maxFallbackCells'], 0);
      expect(regenerateDetails['strictRequired'], isTrue);
      expect(regenerateDetails['jsonOutput'], isTrue);
      expect(regenerateDetails['targetPreset'], 'v1');
      expect(regenerateDetails['completionAuditPath'], completionAuditPath);
      expect(
        regenerateAction['commandTemplate'] as List<Object?>,
        contains('--completion-audit=$completionAuditPath'),
      );
      expect(
        regenerateAction['rootCommandTemplate'] as List<Object?>,
        contains('--completion-audit=$completionAuditPath'),
      );
      final verifyAction = actions.cast<Map<String, Object?>>().singleWhere(
        (action) => action['id'] == 'verify-readiness-bundle',
      );
      final verifyDetails = verifyAction['details'] as Map<String, Object?>;
      expect(
        verifyDetails['bundleJsonPath'],
        '${outputDir.path}/web-readiness-bundle.json',
      );
      expect(verifyDetails['strictRequired'], isTrue);
      expect(
        verifyDetails['verificationScope'] as List<Object?>,
        containsAll(<String>[
          'generated-artifact-fingerprints',
          'source-input-fingerprints',
          'expected-source-input-path-coverage',
          'command-working-directory-metadata',
          'manual-evidence-latest-entry-fingerprints',
          'threshold-review-release-action',
          'manual-evidence-release-actions',
          'generated-default-preflight-diagnostics',
          'release-action-command-templates',
        ]),
      );
      final automatedTestsAction = actions
          .cast<Map<String, Object?>>()
          .singleWhere(
            (action) => action['id'] == 'run-automated-web-host-tests',
          );
      expect(automatedTestsAction['kind'], 'automated-validation');
      expect(automatedTestsAction['dependsOn'], ['verify-readiness-bundle']);
      final automatedTestsDetails =
          automatedTestsAction['details'] as Map<String, Object?>;
      expect(
        automatedTestsDetails['sourceInputGroup'],
        'webAutomatedTestFiles',
      );
      expect(
        automatedTestsDetails['automatedValidationJsonPath'],
        '${outputDir.path}/web-automated-validation.json',
      );
      expect(automatedTestsDetails['requiredPass'], isTrue);
      expect(
        automatedTestsAction['commandTemplate'] as List<Object?>,
        containsAll(<String>[
          'tool/web_automated_validation.dart',
          '--json-output=${outputDir.path}/web-automated-validation.json',
          '--strict',
        ]),
      );
      expect(
        automatedTestsAction['browserTestCommand'] as List<Object?>,
        containsAll(<String>[
          '-p',
          'chrome',
          'test/dom_input_trace_fixture_test.dart',
          'test/mount_app_test.dart',
        ]),
      );
      expect(
        automatedTestsAction['vmTestCommand'] as List<Object?>,
        containsAll(<String>[
          'test/frame_presentation_test.dart',
          'test/web_public_api_boundary_test.dart',
        ]),
      );
      final preflightAction = actions.cast<Map<String, Object?>>().singleWhere(
        (action) => action['id'] == 'run-default-preflight:make-dom-default',
      );
      expect(
        preflightAction['dependsOn'] as List<Object?>,
        contains('run-automated-web-host-tests'),
      );
      final preflightDetails =
          preflightAction['details'] as Map<String, Object?>;
      expect(preflightDetails['targetId'], 'make-dom-default');
      expect(
        preflightDetails['readinessJsonPath'],
        '${outputDir.path}/web-readiness.json',
      );
      expect(
        preflightDetails['bundleJsonPath'],
        '${outputDir.path}/web-readiness-bundle.json',
      );
      expect(
        preflightDetails['automatedValidationJsonPath'],
        '${outputDir.path}/web-automated-validation.json',
      );
      expect(preflightDetails['requiresBundleBinding'], isTrue);
      expect(preflightDetails['strictRequired'], isTrue);
      expect(
        preflightDetails['verificationScope'] as List<Object?>,
        containsAll(<String>[
          'generated-artifact-fingerprints',
          'source-input-fingerprints',
          'expected-source-input-path-coverage',
          'command-working-directory-metadata',
          'readiness-json-path-binding',
        ]),
      );
      final artifacts = bundle['artifacts'] as Map<String, Object?>;
      final releaseActionsPath = artifacts['releaseActionsMarkdown'] as String;
      final releaseActions = File(releaseActionsPath).readAsStringSync();
      expect(releaseActions, contains("'--reviewed-by=<reviewer>'"));
      expect(releaseActions, contains("'--review-context=Browser Chrome/127"));
      final readiness = bundle['readiness'] as Map<String, Object?>;
      final checks = readiness['checks'] as List<Object?>;
      final frameCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'frameScoreboard',
      );
      expect(
        frameCheck['blockers'] as List<Object?>,
        contains('frame scenarios missing total-frame p95 gate: normal-80x24'),
      );
      expect(
        frameCheck['blockers'] as List<Object?>,
        contains('frame scoreboard did not use a threshold policy'),
      );
    },
  );

  test(
    'web readiness bundle binds preview preflights to existing automated validation',
    () async {
      _writeCaptureSet(capturesDir);
      _writeManualEvidence(manualDir);
      _writeAutomatedValidationArtifact(
        '${outputDir.path}/web-automated-validation.json',
      );

      final result = await _run([
        '--captures=${capturesDir.path}',
        '--manual=${manualDir.path}',
        '--output-dir=${outputDir.path}',
        '--max-total-frame-p95-ms=20',
        '--max-fallback-cells=0',
        '--no-require-reviewed-threshold-policy',
        '--no-require-threshold-review-summary',
        '--no-require-scenario-thresholds',
        '--write-default-preflights',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      for (final targetId in ['make-dom-default', 'retire-temporary-paths']) {
        final preflight =
            jsonDecode(
                  File(
                    '${outputDir.path}/web-default-preflight-$targetId.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(preflight['automatedValidationRequired'], isFalse);
        expect(preflight['automatedValidationBound'], isTrue);
        expect(
          preflight['automatedValidationPath'],
          '${outputDir.path}/web-automated-validation.json',
        );
        final checks = (preflight['checks'] as List<Object?>)
            .cast<Map<String, Object?>>();
        final automatedCheck = checks.singleWhere(
          (check) => check['id'] == 'automatedValidation',
        );
        expect(automatedCheck['strictPass'], isTrue);
        final details = automatedCheck['details'] as Map<String, Object?>;
        expect(details['sourceMismatchCount'], 0);
      }
    },
  );
}

Future<ProcessResult> _run(List<String> args) {
  return Process.run(Platform.resolvedExecutable, [
    'run',
    'tool/web_readiness_bundle.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

void _writeCaptureSet(Directory directory) {
  for (var i = 0; i < 3; i += 1) {
    _writeJson('${directory.path}/normal-$i.json', {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameCapture',
      'capturedAt': '2026-06-08T12:0$i:00.000000Z',
      'frameBudgetMs': 16.67,
      'scenario': {'id': 'normal-80x24'},
      'runEnvironment': _runEnvironment(),
      'frames': [
        _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
        _webFrame(totalFrameMicros: 12000, domApplyMicros: 4000),
      ],
    });
  }
}

void _writeAutomatedValidationArtifact(String path) {
  File(path).parent.createSync(recursive: true);
  _writeJson(path, {
    'schemaVersion': 1,
    'kind': 'fleuryWebAutomatedValidation',
    'generatedAt': '2026-06-09T12:00:00.000000Z',
    'commandWorkingDirectory': Directory.current.absolute.path,
    'strictPass': true,
    'sourceInputGroup': 'webAutomatedTestFiles',
    'browserTestFiles': webAutomatedBrowserTestPaths,
    'vmTestFiles': webAutomatedVmTestPaths,
    'fixtureFiles': webAutomatedFixturePaths,
    'sourceInputFingerprints': {
      'webAutomatedTestFiles': [
        for (final path in webAutomatedTestSourceInputPaths)
          if (File(path).existsSync())
            {
              'path': File(path).absolute.path,
              'fingerprint': _fileFingerprint(path),
            },
      ],
    },
    'checks': [
      {
        'id': 'browser',
        'label': 'Retained DOM browser tests',
        'command': webAutomatedBrowserTestCommand(),
        'testFiles': webAutomatedBrowserTestPaths,
        'testFileCount': webAutomatedBrowserTestPaths.length,
        'exitCode': 0,
        'strictPass': true,
      },
      {
        'id': 'vm',
        'label': 'Retained DOM VM tests',
        'command': webAutomatedVmTestCommand(),
        'testFiles': webAutomatedVmTestPaths,
        'testFileCount': webAutomatedVmTestPaths.length,
        'exitCode': 0,
        'strictPass': true,
      },
    ],
  });
}

Map<String, Object?> _runEnvironment() {
  return <String, Object?>{
    'chromeBrowser': 'Chrome/127',
    'chromeUserAgent': 'Mozilla/5.0 test Chrome/127',
    'devtoolsProtocolVersion': '1.3',
    'dartVersion': Platform.version,
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'headless': true,
    'requestedFrames': 2,
    'warmupFrames': 0,
    'frameBudgetMs': 16.67,
  };
}

Map<String, Object?> _webFrame({
  required int totalFrameMicros,
  required int domApplyMicros,
}) {
  return <String, Object?>{
    'reason': 'benchmark',
    'coalescedReasons': ['benchmark'],
    'viewport': {'cols': 80, 'rows': 24},
    'damageSource': 'paintDamage',
    'fullRepaint': false,
    'metricsChanged': false,
    'dirtyRowCount': 2,
    'dirtyCellEstimate': 160,
    'spanCount': 8,
    'domNodesCreated': 10,
    'rowsReplaced': 2,
    'styleCacheHits': 4,
    'styleCacheMisses': 1,
    'widthCacheHits': 0,
    'widthCacheMisses': 0,
    'metricsReadCount': 1,
    'semanticNodeCount': 3,
    'semanticAddedNodeCount': 1,
    'semanticRemovedNodeCount': 0,
    'semanticUpdatedNodeCount': 1,
    'semanticFallbackNodeCount': 0,
    'semanticUncoveredCellCount': 0,
    'runtimeRenderMicros': 3000,
    'spanBuildMicros': 1000,
    'domApplyMicros': domApplyMicros,
    'semanticApplyMicros': 1000,
    'totalFrameMicros': totalFrameMicros,
  };
}

void _writeManualEvidence(Directory directory) {
  _writeManualEntry(
    '${directory.path}/chrome-ime-macos.json',
    targetId: 'chrome-ime-macos',
    checkIds: _chromeImeChecks,
  );
  _writeManualEntry(
    '${directory.path}/chrome-voiceover-macos.json',
    targetId: 'chrome-voiceover-macos',
    checkIds: _chromeVoiceOverChecks,
  );
}

void _writeManualTemplate(
  Directory directory, {
  required String targetId,
  required Iterable<String> checkIds,
  String? manualPageServeNote,
}) {
  final templatesDir = Directory('${directory.path}/templates')..createSync();
  final target = manualValidationTargetById(targetId);
  if (target == null) {
    throw ArgumentError.value(targetId, 'targetId', 'unknown target');
  }
  final template = manualValidationTemplateFor(target);
  if (manualPageServeNote != null) {
    final reviewInstructions = (template['reviewInstructions'] as Map)
        .cast<String, Object?>();
    reviewInstructions['manualPageServeNote'] = manualPageServeNote;
  }
  template['checks'] = [
    for (final id in checkIds)
      {
        'id': id,
        'status': 'needsReview',
        'notes': _manualCheckInstruction(targetId, id),
      },
  ];
  _writeJson('${templatesDir.path}/$targetId.template.json', template);
}

String _manualCheckInstruction(String targetId, String checkId) {
  final target = manualValidationTargetById(targetId);
  if (target == null) return 'unknown target check';
  for (final check in target.requiredChecks) {
    if (check.id == checkId) return check.instruction;
  }
  return 'unknown target check';
}

void _writeLegacyManualTemplate(
  Directory directory, {
  required String targetId,
  required Iterable<String> checkIds,
}) {
  final templatesDir = Directory('${directory.path}/templates')..createSync();
  _writeJson('${templatesDir.path}/$targetId.template.json', {
    'schemaVersion': 1,
    'kind': 'fleuryWebManualValidationEntry',
    'targetId': targetId,
    'capturedAt': '',
    'status': 'needsReview',
    'reviewedBy': '',
    'environment': {
      'browser': 'Chrome',
      'browserVersion': '',
      'platform': 'macOS',
      'fleuryWebPage': 'manual_validation.html',
    },
    'checks': [
      for (final id in checkIds)
        {'id': id, 'status': 'needsReview', 'notes': 'legacy template'},
    ],
    'notes': <String>[],
  });
}

void _writeManualEntry(
  String path, {
  required String targetId,
  required Iterable<String> checkIds,
}) {
  final target = manualValidationTargetById(targetId);
  if (target == null) {
    throw ArgumentError.value(targetId, 'targetId', 'unknown target');
  }
  final entry = manualValidationTemplateFor(target)
    ..['capturedAt'] = '2026-06-08T12:00:00.000000Z'
    ..['status'] = 'pass'
    ..['reviewedBy'] = 'tester'
    ..['environment'] = {
      'browser': 'Chrome',
      'browserVersion': '127',
      'platform': 'macOS',
      'fleuryWebPage': 'manual_validation.html',
      if (targetId == 'chrome-ime-macos')
        'inputMethod': 'Japanese Romaji test fixture',
      if (targetId == 'chrome-voiceover-macos')
        'assistiveTechnology': 'VoiceOver',
    }
    ..['observedPageSignals'] = [
      for (final signal in target.requiredPageSignals)
        {
          ...signal.toJson(),
          'observedValue': signal.expectedValue,
          'status': 'pass',
          'notes': 'Observed ${signal.attribute}=${signal.expectedValue}.',
        },
    ]
    ..['checks'] = [
      for (final id in checkIds)
        {'id': id, 'status': 'pass', 'notes': 'Observed pass for $id.'},
    ]
    ..['notes'] = ['test fixture'];
  _writeJson(path, entry);
}

void _writeThresholdReview({
  required String path,
  required String outputPath,
  required String reviewedBy,
  required String reviewedAt,
  required String reviewContext,
  required int scenarioCount,
  required String outputPolicyFingerprint,
}) {
  final inputPath = '${File(outputPath).parent.path}/thresholds.candidate.json';
  final inputPolicy = _candidateThresholdPolicyForReviewedOutput(outputPath);
  _writeJson(inputPath, inputPolicy);
  _writeJson(path, {
    'schemaVersion': 1,
    'kind': 'fleuryWebThresholdReview',
    'inputPath': inputPath,
    'outputPath': outputPath,
    'reviewState': 'reviewed',
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt,
    'reviewContext': reviewContext,
    'scenarioCount': scenarioCount,
    'inputPolicyFingerprint': _jsonFingerprint(inputPolicy),
    'outputPolicyFingerprint': outputPolicyFingerprint,
  });
}

Map<String, Object?> _candidateThresholdPolicyForReviewedOutput(
  String outputPath,
) {
  final raw = jsonDecode(File(outputPath).readAsStringSync());
  final reviewed = (raw as Map).cast<String, Object?>();
  return <String, Object?>{...reviewed, 'reviewState': 'candidate'}
    ..remove('reviewedBy')
    ..remove('reviewedAt')
    ..remove('reviewContext')
    ..remove('overBudgetThresholdsAcknowledged')
    ..remove('overBudgetThresholdScenarioIds');
}

void _writeJson(String path, Map<String, Object?> json) {
  File(
    path,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
}

String _jsonFingerprint(Map<String, Object?> json) {
  final canonicalJson = jsonEncode(_canonicalizeJson(json));
  return _fnv1a64(utf8.encode(canonicalJson));
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

String _fileFingerprint(String path) => _fnv1a64(File(path).readAsBytesSync());

String _fleuryPackagePath(String packageRelativePath) {
  return Directory.current.absolute.parent.uri
      .resolve('fleury/$packageRelativePath')
      .toFilePath();
}

String _workspaceRootPath(String workspaceRelativePath) {
  return Directory.current.absolute.uri
      .resolve('../../$workspaceRelativePath')
      .toFilePath();
}

String _fnv1a64(List<int> bytes) {
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in bytes) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
}

const _chromeImeChecks = <String>[
  'manual-page-loads-dom-host',
  'keyboard-capture-focused',
  'composition-start-update-visible',
  'composition-end-commits-once',
  'candidate-window-near-caret',
  'typing-continues-after-composition',
];

const _chromeVoiceOverChecks = <String>[
  'manual-page-ready-semantic-host',
  'visual-grid-hidden',
  'semantic-root-exposed',
  'focused-textbox-announced',
  'semantic-action-works',
  'keyboard-capture-restored',
  'safe-link-announced',
];
