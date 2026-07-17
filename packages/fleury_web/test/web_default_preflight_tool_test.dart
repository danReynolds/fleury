@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/readiness_bundle_verifier.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_default_preflight_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('web default preflight can run unbundled diagnostics', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final outputPath = '${tempDir.path}/preflight.md';
    final jsonOutputPath = '${tempDir.path}/preflight.json';
    _writeJson(readinessPath, _readiness());

    final result = await _run([
      '--readiness=$readinessPath',
      '--target=make-dom-default',
      '--output=$outputPath',
      '--json-output=$jsonOutputPath',
      '--strict',
      '--allow-unbundled',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = _jsonObject(result.stdout);
    expect(audit['kind'], 'fleuryWebDefaultPreflight');
    expect(audit['target'], 'make-dom-default');
    expect(audit['diagnosticOnly'], isTrue);
    expect(audit['diagnosticReason'], contains('Unbundled readiness-only'));
    expect(audit['finalGateRequiresBundle'], isTrue);
    expect(audit['finalGateRequiresAutomatedValidation'], isTrue);
    expect(
      audit['finalGateBundlePath'],
      '${tempDir.path}/web-readiness-bundle.json',
    );
    expect(
      audit['finalGateAutomatedValidationPath'],
      '${tempDir.path}/web-automated-validation.json',
    );
    expect(audit['bundleRequired'], isFalse);
    expect(audit['bundleBound'], isFalse);
    expect(audit['automatedValidationRequired'], isFalse);
    expect(audit['automatedValidationBound'], isFalse);
    expect(audit['strictPass'], isTrue);
    final checks = audit['checks'] as List<Object?>;
    expect(checks, hasLength(1));
    expect(
      checks.single,
      isA<Map<String, Object?>>().having(
        (check) => check['id'],
        'id',
        'phase6Readiness',
      ),
    );

    final markdown = File(outputPath).readAsStringSync();
    expect(markdown, contains('Fleury Web Default Preflight'));
    expect(markdown, contains('make-dom-default'));
    expect(markdown, contains('Diagnostic only: `true`'));
    expect(markdown, contains('Final gate requires bundle: `true`'));
    expect(markdown, contains('Strict pass: `true`'));

    final persisted = _jsonObject(File(jsonOutputPath).readAsStringSync());
    expect(persisted['kind'], 'fleuryWebDefaultPreflight');
    expect(persisted['target'], 'make-dom-default');
    expect(persisted['diagnosticOnly'], isTrue);
    expect(persisted['finalGateRequiresBundle'], isTrue);
    expect(persisted['finalGateRequiresAutomatedValidation'], isTrue);
    expect(persisted['bundleRequired'], isFalse);
    expect(persisted['bundleBound'], isFalse);
    expect(persisted['automatedValidationRequired'], isFalse);
    expect(persisted['automatedValidationBound'], isFalse);
    expect(persisted['strictPass'], isTrue);
  });

  test('web default preflight uses sibling bundle by default', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());
    _writeJson(bundlePath, _bundle(readinessPath: readinessPath));

    final result = await _run([
      '--readiness=$readinessPath',
      '--target=make-dom-default',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = _jsonObject(result.stdout);
    expect(audit['diagnosticOnly'], isFalse);
    expect(audit['finalGateRequiresBundle'], isTrue);
    expect(audit['finalGateRequiresAutomatedValidation'], isTrue);
    expect(audit['bundleRequired'], isTrue);
    expect(audit['bundleBound'], isTrue);
    expect(audit['automatedValidationRequired'], isTrue);
    expect(audit['automatedValidationBound'], isTrue);
    expect(audit['bundlePath'], bundlePath);
    expect(audit['strictPass'], isTrue);
    final checks = audit['checks'] as List<Object?>;
    expect(checks, hasLength(3));
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(bundleCheck['strictPass'], isTrue);
  });

  test('web default preflight rejects missing inferred bundle', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());

    final result = await _run([
      '--readiness=$readinessPath',
      '--target=make-dom-default',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['diagnosticOnly'], isFalse);
    expect(audit['finalGateRequiresBundle'], isTrue);
    expect(audit['finalGateRequiresAutomatedValidation'], isTrue);
    expect(audit['bundleRequired'], isTrue);
    expect(audit['bundleBound'], isTrue);
    expect(audit['automatedValidationRequired'], isTrue);
    expect(audit['automatedValidationBound'], isTrue);
    expect(audit['bundlePath'], bundlePath);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    expect(checks, hasLength(3));
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(bundleCheck['strictPass'], isFalse);
    expect(
      bundleCheck['blockers'] as List<Object?>,
      contains('missing readiness bundle: $bundlePath'),
    );
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['bundlePath'], File(bundlePath).absolute.path);
  });

  test('web default preflight verifies readiness bundle artifacts', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());
    _writeJson(bundlePath, _bundle(readinessPath: readinessPath));

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isTrue);
    expect(audit['bundlePath'], bundlePath);
    final checks = audit['checks'] as List<Object?>;
    expect(checks, hasLength(3));
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(bundleCheck['strictPass'], isTrue);
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['checkedArtifactCount'], 2);
    expect(details['mismatchCount'], 0);
    expect(details['checkedSourceInputCount'], greaterThan(100));
    expect(details['sourceMismatchCount'], 0);
    expect(details['missingSourceInputCount'], 0);
    expect(details['checkedMetadataCount'], 1);
    expect(details['metadataMismatchCount'], 0);
    expect(details['missingMetadataCount'], 0);
    expect(details['bundleReadinessPath'], File(readinessPath).absolute.path);
    final automatedCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'automatedValidation',
    );
    expect(automatedCheck['strictPass'], isTrue);
    final automatedDetails = automatedCheck['details'] as Map<String, Object?>;
    expect(automatedDetails['checkedSourceInputCount'], greaterThan(10));
    expect(automatedDetails['sourceMismatchCount'], 0);
    expect(automatedDetails['checkedMetadataCount'], 1);
    expect(automatedDetails['manifestMismatchCount'], 0);
  });

  test('web default preflight rejects stale automated validation', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    final automatedValidationPath =
        '${tempDir.path}/$webAutomatedValidationFileName';
    _writeJson(readinessPath, _readiness());
    _writeJson(bundlePath, _bundle(readinessPath: readinessPath));
    final validation =
        jsonDecode(File(automatedValidationPath).readAsStringSync())
            as Map<String, Object?>;
    final checks = (validation['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final browser = checks.singleWhere((check) => check['id'] == 'browser');
    final command = (browser['command'] as List<Object?>).toList();
    command[4] = 'test/stale_browser_test.dart';
    browser['command'] = command;
    _writeJson(automatedValidationPath, validation);

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final preflightChecks = audit['checks'] as List<Object?>;
    final automatedCheck = preflightChecks
        .cast<Map<String, Object?>>()
        .singleWhere((check) => check['id'] == 'automatedValidation');
    expect(automatedCheck['strictPass'], isFalse);
    expect(
      automatedCheck['blockers'] as List<Object?>,
      contains('automated validation has 1 manifest mismatch'),
    );
    final details = automatedCheck['details'] as Map<String, Object?>;
    expect(details['manifestMismatchCount'], 1);
    final mismatches = details['manifestMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>().having(
        (mismatch) => mismatch['id'],
        'id',
        'webAutomatedValidation.checks.browser.command',
      ),
    );
  });

  test('web default preflight rejects stale bundle manifest summary', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());
    final bundle = _bundle(readinessPath: readinessPath)
      ..['strictPass'] = false;
    _writeJson(bundlePath, bundle);

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(
      bundleCheck['blockers'] as List<Object?>,
      contains('readiness bundle has 1 manifest mismatch'),
    );
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['manifestMismatchCount'], 1);
    final mismatches = details['manifestMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>().having(
        (mismatch) => mismatch['id'],
        'id',
        'strictPass',
      ),
    );
  });

  test('web default preflight rejects stale readiness bundle', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());
    _writeJson(bundlePath, _bundle(readinessPath: readinessPath));
    File(readinessPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(_readiness())}\n\n',
    );

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(bundleCheck['strictPass'], isFalse);
    expect(
      bundleCheck['blockers'] as List<Object?>,
      contains('readiness bundle has 1 artifact fingerprint mismatch'),
    );
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['mismatchCount'], 1);
    final mismatches = details['mismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>().having(
        (mismatch) => mismatch['id'],
        'id',
        'readinessJson',
      ),
    );
  });

  test('web default preflight rejects stale bundle source input', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    final sourcePath = '${tempDir.path}/source-capture.json';
    _writeJson(readinessPath, _readiness());
    _writeJson(sourcePath, {
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameCapture',
      'frames': <Object?>[],
    });
    _writeJson(
      bundlePath,
      _bundle(readinessPath: readinessPath, sourcePath: sourcePath),
    );
    File(
      sourcePath,
    ).writeAsStringSync('${File(sourcePath).readAsStringSync()}\n');

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(
      bundleCheck['blockers'] as List<Object?>,
      contains('readiness bundle has 1 source input fingerprint mismatch'),
    );
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['sourceMismatchCount'], 1);
    final mismatches = details['sourceMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>().having(
        (mismatch) => mismatch['id'],
        'id',
        'captureFiles[0]',
      ),
    );
  });

  test(
    'web default preflight rejects stale manual validation page source input',
    () async {
      final readinessPath = '${tempDir.path}/web-readiness.json';
      final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
      final manualPagePath = File('web/manual_validation.dart').absolute.path;
      _writeJson(readinessPath, _readiness());
      final bundle = _bundle(readinessPath: readinessPath);
      final sourceInputFingerprints =
          bundle['sourceInputFingerprints'] as Map<String, Object?>;
      final manualPageFiles =
          sourceInputFingerprints['manualValidationPageFiles'] as List<Object?>;
      final manualPageIndex = manualPageFiles.indexWhere((entry) {
        return (entry as Map<String, Object?>)['path'] == manualPagePath;
      });
      expect(manualPageIndex, isNot(-1));
      final manualPageFingerprint = Map<String, Object?>.from(
        manualPageFiles[manualPageIndex] as Map<String, Object?>,
      );
      manualPageFingerprint['fingerprint'] = 'fnv1a64:0000000000000000';
      manualPageFiles[manualPageIndex] = manualPageFingerprint;
      _writeJson(bundlePath, bundle);

      final result = await _run([
        '--readiness=$readinessPath',
        '--bundle=$bundlePath',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final audit = _jsonObject(result.stdout);
      expect(audit['strictPass'], isFalse);
      final checks = audit['checks'] as List<Object?>;
      final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'readinessBundle',
      );
      expect(
        bundleCheck['blockers'] as List<Object?>,
        contains('readiness bundle has 1 source input fingerprint mismatch'),
      );
      final details = bundleCheck['details'] as Map<String, Object?>;
      expect(details['sourceMismatchCount'], 1);
      final mismatches = details['sourceMismatches'] as List<Object?>;
      expect(
        mismatches.single,
        isA<Map<String, Object?>>()
            .having(
              (mismatch) => mismatch['id'],
              'id',
              startsWith('manualValidationPageFiles['),
            )
            .having(
              (mismatch) => mismatch['path'],
              'path',
              File(manualPagePath).absolute.path,
            ),
      );
    },
  );

  test('web default preflight rejects omitted expected source input', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());
    final bundle = _bundle(readinessPath: readinessPath);
    final sourceInputFingerprints =
        bundle['sourceInputFingerprints'] as Map<String, Object?>;
    final webImplementationFiles =
        sourceInputFingerprints['webImplementationFiles'] as List<Object?>;
    final omittedPath = File('lib/src/run_tui_surface.dart').absolute.path;
    webImplementationFiles.removeWhere((entry) {
      return (entry as Map<String, Object?>)['path'] == omittedPath;
    });
    _writeJson(bundlePath, bundle);

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(
      bundleCheck['blockers'] as List<Object?>,
      contains('readiness bundle is missing 1 source input'),
    );
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['missingSourceInputCount'], 1);
    final missingSourceInputs = details['missingSourceInputs'] as List<Object?>;
    expect(
      missingSourceInputs.single,
      isA<Map<String, Object?>>()
          .having((missing) => missing['id'], 'id', 'webImplementationFiles')
          .having((missing) => missing['path'], 'path', omittedPath),
    );
  });

  test(
    'web default preflight rejects missing source input fingerprints',
    () async {
      final readinessPath = '${tempDir.path}/web-readiness.json';
      final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
      _writeJson(readinessPath, _readiness());
      final bundle = _bundle(readinessPath: readinessPath)
        ..remove('sourceInputFingerprints');
      _writeJson(bundlePath, bundle);

      final result = await _run([
        '--readiness=$readinessPath',
        '--bundle=$bundlePath',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, 1);
      final audit = _jsonObject(result.stdout);
      expect(audit['strictPass'], isFalse);
      final checks = audit['checks'] as List<Object?>;
      final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
        (check) => check['id'] == 'readinessBundle',
      );
      expect(
        bundleCheck['blockers'] as List<Object?>,
        contains(
          'readiness bundle sourceInputFingerprints must be a JSON object',
        ),
      );
      expect(
        bundleCheck['blockers'] as List<Object?>,
        contains('readiness bundle is missing 1 source input fingerprint'),
      );
      final details = bundleCheck['details'] as Map<String, Object?>;
      expect(details['missingSourceFingerprintCount'], 1);
      expect(details['missingSourceFingerprints'], ['sourceInputFingerprints']);
    },
  );

  test('web default preflight rejects stale bundle command cwd', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final bundlePath = '${tempDir.path}/web-readiness-bundle.json';
    _writeJson(readinessPath, _readiness());
    _writeJson(
      bundlePath,
      _bundle(
        readinessPath: readinessPath,
        commandWorkingDirectory: tempDir.path,
      ),
    );

    final result = await _run([
      '--readiness=$readinessPath',
      '--bundle=$bundlePath',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final bundleCheck = checks.cast<Map<String, Object?>>().singleWhere(
      (check) => check['id'] == 'readinessBundle',
    );
    expect(
      bundleCheck['blockers'] as List<Object?>,
      contains('readiness bundle has 1 metadata mismatch'),
    );
    final details = bundleCheck['details'] as Map<String, Object?>;
    expect(details['checkedMetadataCount'], 1);
    expect(details['metadataMismatchCount'], 1);
    expect(details['missingMetadataCount'], 0);
    final mismatches = details['metadataMismatches'] as List<Object?>;
    expect(
      mismatches.single,
      isA<Map<String, Object?>>()
          .having(
            (mismatch) => mismatch['id'],
            'id',
            'input.commandWorkingDirectory',
          )
          .having((mismatch) => mismatch['actual'], 'actual', tempDir.path),
    );
  });

  test('web default preflight fails when readiness is blocked', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    final outputPath = '${tempDir.path}/preflight.md';
    final jsonOutputPath = '${tempDir.path}/preflight.json';
    _writeJson(
      readinessPath,
      _readiness(
        strictPass: false,
        checks: const [
          {
            'id': 'frameScoreboard',
            'label': 'Frame performance scoreboard',
            'strictPass': false,
            'blockers': [
              'frame scoreboard threshold policy reviewState is candidate; expected reviewed',
            ],
            'details': <String, Object?>{},
          },
          {
            'id': 'manualValidation',
            'label': 'Manual browser validation',
            'strictPass': false,
            'blockers': [
              'missingTargets: chrome-ime-macos, chrome-voiceover-macos',
            ],
            'details': {
              'failingTargetDetails': [
                {
                  'id': 'chrome-ime-macos',
                  'status': 'missing',
                  'requiredCheckCount': 6,
                  'passedRequiredCheckCount': 0,
                  'missingCheckIds': [
                    'manual-page-loads-dom-host',
                    'candidate-window-near-caret',
                  ],
                },
                {
                  'id': 'chrome-voiceover-macos',
                  'status': 'missing',
                  'requiredCheckCount': 7,
                  'passedRequiredCheckCount': 0,
                  'missingCheckIds': [
                    'manual-page-ready-semantic-host',
                    'visual-grid-hidden',
                  ],
                },
              ],
            },
          },
        ],
      ),
    );

    final result = await _run([
      '--readiness=$readinessPath',
      '--target=retire-temporary-paths',
      '--output=$outputPath',
      '--json-output=$jsonOutputPath',
      '--strict',
      '--allow-unbundled',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['target'], 'retire-temporary-paths');
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final check = checks.single as Map<String, Object?>;
    expect(check['strictPass'], isFalse);
    expect(
      check['blockers'] as List<Object?>,
      contains(
        'Frame performance scoreboard: frame scoreboard threshold policy reviewState is candidate; expected reviewed',
      ),
    );
    expect(
      check['blockers'] as List<Object?>,
      contains(
        'Manual browser validation: missingTargets: chrome-ime-macos, chrome-voiceover-macos',
      ),
    );
    final details = check['details'] as Map<String, Object?>;
    expect(details['failedChecks'], hasLength(2));
    final failedChecks = details['failedChecks'] as List<Object?>;
    final manualFailure = failedChecks.cast<Map<String, Object?>>().singleWhere(
      (failed) => failed['id'] == 'manualValidation',
    );
    final manualDetails = manualFailure['details'] as Map<String, Object?>;
    final failingTargetDetails =
        manualDetails['failingTargetDetails'] as List<Object?>;
    final voiceOver = failingTargetDetails
        .cast<Map<String, Object?>>()
        .singleWhere((target) => target['id'] == 'chrome-voiceover-macos');
    expect(voiceOver['requiredCheckCount'], 7);
    expect(voiceOver['missingCheckIds'], [
      'manual-page-ready-semantic-host',
      'visual-grid-hidden',
    ]);

    final markdown = File(outputPath).readAsStringSync();
    expect(markdown, contains('Manual Target Diagnostics'));
    expect(markdown, contains('chrome-ime-macos'));
    expect(markdown, contains('0/6'));
    expect(markdown, contains('chrome-voiceover-macos'));
    expect(markdown, contains('0/7'));
    expect(markdown, contains('manual-page-ready-semantic-host'));

    final persisted = _jsonObject(File(jsonOutputPath).readAsStringSync());
    expect(persisted['target'], 'retire-temporary-paths');
    expect(persisted['strictPass'], isFalse);
    final persistedChecks = persisted['checks'] as List<Object?>;
    final persistedCheck = persistedChecks.single as Map<String, Object?>;
    final persistedDetails = persistedCheck['details'] as Map<String, Object?>;
    expect(persistedDetails['failedChecks'], hasLength(2));
    final persistedFailedChecks =
        persistedDetails['failedChecks'] as List<Object?>;
    final persistedManualFailure = persistedFailedChecks
        .cast<Map<String, Object?>>()
        .singleWhere((failed) => failed['id'] == 'manualValidation');
    final persistedManualDetails =
        persistedManualFailure['details'] as Map<String, Object?>;
    final persistedTargetDetails =
        persistedManualDetails['failingTargetDetails'] as List<Object?>;
    final persistedVoiceOver = persistedTargetDetails
        .cast<Map<String, Object?>>()
        .singleWhere((target) => target['id'] == 'chrome-voiceover-macos');
    expect(persistedVoiceOver['requiredCheckCount'], 7);
    expect(
      persistedVoiceOver['missingCheckIds'] as List<Object?>,
      contains('manual-page-ready-semantic-host'),
    );
  });

  test('web default preflight rejects missing readiness artifact', () async {
    final readinessPath = '${tempDir.path}/missing.json';

    final result = await _run([
      '--readiness=$readinessPath',
      '--strict',
      '--allow-unbundled',
      '--json',
    ]);

    expect(result.exitCode, 1);
    final audit = _jsonObject(result.stdout);
    expect(audit['strictPass'], isFalse);
    final checks = audit['checks'] as List<Object?>;
    final check = checks.single as Map<String, Object?>;
    expect(check['id'], 'readinessArtifact');
    expect(
      check['blockers'] as List<Object?>,
      contains('missing readiness artifact: $readinessPath'),
    );
  });

  test('web default preflight rejects empty json output path', () async {
    final readinessPath = '${tempDir.path}/web-readiness.json';
    _writeJson(readinessPath, _readiness());

    final result = await _run(['--readiness=$readinessPath', '--json-output=']);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--json-output requires a non-empty path.'),
    );
  });
}

Future<ProcessResult> _run(List<String> args) {
  return Process.run(Platform.resolvedExecutable, [
    'run',
    'tool/web_default_preflight.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

void _writeJson(String path, Map<String, Object?> json) {
  File(
    path,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
}

Map<String, Object?> _readiness({
  bool strictPass = true,
  List<Map<String, Object?>> checks = const [
    {
      'id': 'frameScoreboard',
      'label': 'Frame performance scoreboard',
      'strictPass': true,
      'blockers': <String>[],
      'details': <String, Object?>{},
    },
    {
      'id': 'semanticCoverage',
      'label': 'Semantic coverage audit',
      'strictPass': true,
      'blockers': <String>[],
      'details': <String, Object?>{},
    },
    {
      'id': 'manualValidation',
      'label': 'Manual browser validation',
      'strictPass': true,
      'blockers': <String>[],
      'details': <String, Object?>{},
    },
  ],
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebReadinessAudit',
    'generatedAt': '2026-06-08T12:00:00.000000Z',
    'strictPass': strictPass,
    'checks': checks,
  };
}

Map<String, Object?> _bundle({
  required String readinessPath,
  String? sourcePath,
  String? commandWorkingDirectory,
}) {
  final manualPlanPath =
      '${File(readinessPath).parent.path}/manual-validation-plan.md';
  File(
    manualPlanPath,
  ).writeAsStringSync('# Fleury Web Manual Validation Plan\n');
  final rootDir = File(readinessPath).parent.path;
  final captureDir = sourcePath == null
      ? rootDir
      : File(sourcePath).parent.path;
  final manualDir = '$rootDir/manual';
  Directory(manualDir).createSync(recursive: true);
  _writeAutomatedValidation(
    rootDir: rootDir,
    commandWorkingDirectory:
        commandWorkingDirectory ?? Directory.current.absolute.path,
  );
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebReadinessBundle',
    'strictPass': true,
    'input': <String, Object?>{
      'targetPreset': 'v1',
      'captureDir': captureDir,
      'manualDir': manualDir,
      'commandWorkingDirectory':
          commandWorkingDirectory ?? Directory.current.absolute.path,
    },
    'artifacts': <String, Object?>{
      'bundleJson':
          '${File(readinessPath).parent.path}/web-readiness-bundle.json',
      'manualPlan': manualPlanPath,
      'readinessJson': readinessPath,
    },
    'artifactFingerprints': <String, Object?>{
      'manualPlan': _fingerprint(manualPlanPath),
      'readinessJson': _fingerprint(readinessPath),
    },
    'sourceInputFingerprints': readinessBundleSourceInputFingerprints(
      captureDir: captureDir,
      manualDir: manualDir,
      manualTemplateTargetIds: const <String>[],
      manualEvidenceTargetIds: const <String>[],
      thresholdPolicyPath: null,
      thresholdReviewPath: null,
      thresholdReviewPlanPath: null,
    ),
    'checks': <String, Object?>{'readinessStrictPass': true},
  };
}

void _writeAutomatedValidation({
  required String rootDir,
  required String commandWorkingDirectory,
}) {
  _writeJson('$rootDir/$webAutomatedValidationFileName', {
    'schemaVersion': 1,
    'kind': 'fleuryWebAutomatedValidation',
    'generatedAt': '2026-06-08T12:00:00.000000Z',
    'commandWorkingDirectory': commandWorkingDirectory,
    'strictPass': true,
    'sourceInputGroup': 'webAutomatedTestFiles',
    'browserTestFiles': webAutomatedBrowserTestPaths,
    'vmTestFiles': webAutomatedVmTestPaths,
    'fixtureFiles': webAutomatedFixturePaths,
    'sourceInputFingerprints': <String, Object?>{
      'webAutomatedTestFiles': webAutomatedTestSourceInputFingerprints(),
    },
    'checks': <Map<String, Object?>>[
      {
        'id': 'browser',
        'label': 'Retained DOM browser tests',
        'command': webAutomatedBrowserTestCommand(),
        'testFiles': webAutomatedBrowserTestPaths,
        'testFileCount': webAutomatedBrowserTestPaths.length,
        'durationMs': 1,
        'exitCode': 0,
        'strictPass': true,
        'stdoutTail': '',
        'stderrTail': '',
      },
      {
        'id': 'vm',
        'label': 'Retained DOM VM tests',
        'command': webAutomatedVmTestCommand(),
        'testFiles': webAutomatedVmTestPaths,
        'testFileCount': webAutomatedVmTestPaths.length,
        'durationMs': 1,
        'exitCode': 0,
        'strictPass': true,
        'stdoutTail': '',
        'stderrTail': '',
      },
    ],
  });
}

String _fingerprint(String path) {
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in File(path).readAsBytesSync()) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
}

Map<String, Object?> _jsonObject(Object? stdout) {
  return jsonDecode(stdout.toString()) as Map<String, Object?>;
}
