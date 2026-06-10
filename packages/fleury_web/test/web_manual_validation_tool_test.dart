@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/manual_validation/manual_validation_targets.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_manual_validation_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('web manual validation writes a plan and evidence template', () async {
    final planPath = '${tempDir.path}/plan.md';
    final templatePath = '${tempDir.path}/chrome-ime-macos.json';
    final voiceOverTemplatePath = '${tempDir.path}/chrome-voiceover-macos.json';

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-plan=$planPath',
      '--write-template=$templatePath',
      '--template-target=chrome-ime-macos',
      '--target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    final voiceOverResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-template=$voiceOverTemplatePath',
      '--template-target=chrome-voiceover-macos',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      voiceOverResult.exitCode,
      0,
      reason: voiceOverResult.stderr.toString(),
    );
    final plan = File(planPath).readAsStringSync();
    expect(plan, contains('Fleury Web Manual Validation Plan'));
    expect(plan, contains('manual_validation.html'));
    expect(
      plan,
      contains('dart test -p chrome test/manual_validation_page_test.dart'),
    );
    expect(plan, contains('does not replace real IME behavior'));
    expect(plan, contains('dart pub global activate dhttpd'));
    expect(plan, contains('dart pub global run dhttpd --path web'));
    expect(plan, contains('data-fleury-manual-validation="ready"'));
    expect(plan, contains('data-fleury-caret-state="positioned"'));
    expect(plan, contains('data-fleury-manual-browser-version'));
    expect(plan, contains('data-fleury-manual-platform'));
    expect(plan, contains('chrome-ime-macos'));
    expect(plan, contains('candidate-window-near-caret'));
    expect(plan, isNot(contains('manual-page-ready-semantic-host')));

    final template =
        jsonDecode(File(templatePath).readAsStringSync())
            as Map<String, Object?>;
    expect(template['kind'], 'fleuryWebManualValidationEntry');
    expect(template['targetId'], 'chrome-ime-macos');
    final target = template['target'] as Map<String, Object?>;
    expect(target['id'], 'chrome-ime-macos');
    expect(target['phase'], 'Phase 3');
    expect(target['category'], 'ime');
    expect(target['requiredCheckCount'], 6);
    final reviewInstructions =
        template['reviewInstructions'] as Map<String, Object?>;
    expect(
      reviewInstructions['manualValidationPage'],
      'manual_validation.html',
    );
    expect(
      reviewInstructions['manualPageCommandWorkingDirectory'],
      'packages/fleury_web',
    );
    expect(
      reviewInstructions['readySignal'],
      contains('data-fleury-manual-validation="ready"'),
    );
    expect(reviewInstructions['manualPageBuildCommand'] as List<Object?>, [
      'dart',
      'compile',
      'js',
      'web/manual_validation.dart',
      '-o',
      'web/manual_validation.dart.js',
    ]);
    expect(reviewInstructions['manualPageSmokeCommand'] as List<Object?>, [
      'dart',
      'test',
      '-p',
      'chrome',
      'test/manual_validation_page_test.dart',
    ]);
    expect(reviewInstructions['manualPageServeSetupCommand'] as List<Object?>, [
      'dart',
      'pub',
      'global',
      'activate',
      'dhttpd',
    ]);
    expect(reviewInstructions['manualPageServeCommand'] as List<Object?>, [
      'dart',
      'pub',
      'global',
      'run',
      'dhttpd',
      '--path',
      'web',
    ]);
    expect(
      reviewInstructions['manualPageLocalUrl'],
      'http://localhost:8080/manual_validation.html',
    );
    expect(
      reviewInstructions['manualPageServeNote'],
      contains('manualPageServeCommand'),
    );
    expect(
      reviewInstructions['manualPageServeNote'],
      contains('http://localhost:8080/manual_validation.html'),
    );
    expect(reviewInstructions['provenanceAttributes'] as List<Object?>, [
      'data-fleury-manual-browser-version',
      'data-fleury-manual-platform',
      'data-fleury-manual-user-agent',
      'data-fleury-manual-page',
    ]);
    final pageSignals =
        reviewInstructions['requiredPageSignals'] as List<Object?>;
    expect(
      pageSignals,
      contains(
        isA<Map<String, Object?>>()
            .having((signal) => signal['id'], 'id', 'retained-dom-ready')
            .having((signal) => signal['selector'], 'selector', 'body')
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
            .having((signal) => signal['selector'], 'selector', 'textarea')
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
      reviewInstructions['statusValues'] as List<Object?>,
      containsAll(['pass', 'fail', 'blocked', 'needsReview']),
    );
    expect(
      reviewInstructions['requiredEnvironmentKeys'] as List<Object?>,
      containsAll([
        'browser',
        'browserVersion',
        'platform',
        'fleuryWebPage',
        'inputMethod',
      ]),
    );
    expect(
      reviewInstructions['completionRule'],
      contains('every required check'),
    );
    expect(
      reviewInstructions['completionRule'],
      contains('required page signal'),
    );
    expect(
      reviewInstructions['completionRule'],
      contains('reviewer observation notes'),
    );
    final observedPageSignals =
        template['observedPageSignals'] as List<Object?>;
    expect(
      observedPageSignals,
      contains(
        isA<Map<String, Object?>>()
            .having((signal) => signal['id'], 'id', 'retained-dom-ready')
            .having((signal) => signal['status'], 'status', 'needsReview')
            .having((signal) => signal['observedValue'], 'observedValue', ''),
      ),
    );
    expect(
      observedPageSignals,
      contains(
        isA<Map<String, Object?>>().having(
          (signal) => signal['id'],
          'id',
          'ime-caret-positioned',
        ),
      ),
    );
    expect(template['status'], 'needsReview');
    expect(template['capturedAt'], isEmpty);
    final checks = template['checks'] as List<Object?>;
    expect(
      checks,
      contains(
        isA<Map<String, Object?>>().having(
          (check) => check['id'],
          'id',
          'composition-end-commits-once',
        ),
      ),
    );
    expect(
      checks,
      contains(
        isA<Map<String, Object?>>()
            .having((check) => check['id'], 'id', 'manual-page-loads-dom-host')
            .having(
              (check) => check['notes'],
              'notes',
              contains('data-fleury-manual-validation="ready"'),
            ),
      ),
    );
    expect(
      checks,
      contains(
        isA<Map<String, Object?>>()
            .having((check) => check['id'], 'id', 'candidate-window-near-caret')
            .having(
              (check) => check['notes'],
              'notes',
              contains('data-fleury-caret-state="positioned"'),
            ),
      ),
    );

    final voiceOverTemplate =
        jsonDecode(File(voiceOverTemplatePath).readAsStringSync())
            as Map<String, Object?>;
    expect(voiceOverTemplate['targetId'], 'chrome-voiceover-macos');
    final voiceOverTarget = voiceOverTemplate['target'] as Map<String, Object?>;
    expect(voiceOverTarget['phase'], 'Phase 4');
    expect(voiceOverTarget['category'], 'screenReader');
    final voiceOverInstructions =
        voiceOverTemplate['reviewInstructions'] as Map<String, Object?>;
    expect(
      voiceOverInstructions['requiredEnvironmentKeys'] as List<Object?>,
      contains('assistiveTechnology'),
    );
    expect(voiceOverTemplate['capturedAt'], isEmpty);
    final voiceOverChecks = voiceOverTemplate['checks'] as List<Object?>;
    expect(
      voiceOverChecks,
      contains(
        isA<Map<String, Object?>>()
            .having(
              (check) => check['id'],
              'id',
              'manual-page-ready-semantic-host',
            )
            .having(
              (check) => check['notes'],
              'notes',
              contains('data-fleury-manual-validation="ready"'),
            )
            .having((check) => check['notes'], 'notes', contains('xterm')),
      ),
    );
  });

  test(
    'web manual validation v1 preset has no blocking manual targets',
    () async {
      final planPath = '${tempDir.path}/plan.md';
      final jsonOutputPath = '${tempDir.path}/manual-validation-audit.json';

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}/evidence',
        '--target-preset=v1',
        '--write-plan=$planPath',
        '--json-output=$jsonOutputPath',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit =
          jsonDecode(File(jsonOutputPath).readAsStringSync())
              as Map<String, Object?>;
      expect(audit['kind'], 'fleuryWebManualValidationAudit');
      expect(audit['strictPass'], isTrue);
      expect(audit['targetCount'], 0);
      expect(audit['passedTargetCount'], 0);
      expect(audit['targets'], isEmpty);
      expect(audit['needsReviewTargets'], isEmpty);
      final persisted =
          jsonDecode(File(jsonOutputPath).readAsStringSync())
              as Map<String, Object?>;
      expect(persisted['strictPass'], isTrue);
      final plan = File(planPath).readAsStringSync();
      expect(plan, contains('Fleury Web Manual Validation Plan'));
      expect(plan, isNot(contains('chrome-ime-macos')));
      expect(plan, isNot(contains('chrome-voiceover-macos')));
    },
  );

  test('web manual validation writes selected target templates', () async {
    final templatesDir = '${tempDir.path}/templates';

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}/evidence',
      '--target-preset=all',
      '--write-templates=$templatesDir',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final imePath = '$templatesDir/chrome-ime-macos.template.json';
    final voiceOverPath = '$templatesDir/chrome-voiceover-macos.template.json';
    expect(result.stdout, contains('wrote $imePath'));
    expect(result.stdout, contains('wrote $voiceOverPath'));

    final imeTemplate =
        jsonDecode(File(imePath).readAsStringSync()) as Map<String, Object?>;
    expect(imeTemplate['kind'], 'fleuryWebManualValidationEntry');
    expect(imeTemplate['targetId'], 'chrome-ime-macos');
    expect(imeTemplate['target'], isA<Map<String, Object?>>());
    expect(imeTemplate['reviewInstructions'], isA<Map<String, Object?>>());
    expect(imeTemplate['capturedAt'], isEmpty);
    final voiceOverTemplate =
        jsonDecode(File(voiceOverPath).readAsStringSync())
            as Map<String, Object?>;
    expect(voiceOverTemplate['kind'], 'fleuryWebManualValidationEntry');
    expect(voiceOverTemplate['targetId'], 'chrome-voiceover-macos');
    expect(voiceOverTemplate['target'], isA<Map<String, Object?>>());
    expect(
      voiceOverTemplate['reviewInstructions'],
      isA<Map<String, Object?>>(),
    );
    expect(voiceOverTemplate['capturedAt'], isEmpty);
  });

  test(
    'web manual validation writes starter evidence without overwrite',
    () async {
      final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
      final starterPath =
          '${tempDir.path}/evidence/chrome-ime-macos.review.json';

      final templateResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        templateResult.exitCode,
        0,
        reason: templateResult.stderr.toString(),
      );

      final starterResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-starter=$starterPath',
        '--starter-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        starterResult.exitCode,
        0,
        reason: starterResult.stderr.toString(),
      );
      expect(starterResult.stdout, contains('wrote $starterPath'));

      final starter =
          jsonDecode(File(starterPath).readAsStringSync())
              as Map<String, Object?>;
      expect(starter['kind'], 'fleuryWebManualValidationEntry');
      expect(starter['targetId'], 'chrome-ime-macos');
      expect(starter['status'], 'needsReview');
      expect(starter['capturedAt'], isEmpty);
      expect(starter['reviewedBy'], isEmpty);
      expect(starter['target'], isA<Map<String, Object?>>());
      final starterInstructions =
          starter['reviewInstructions'] as Map<String, Object?>;
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

      File(starterPath).writeAsStringSync('review in progress\n');
      final overwriteResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-starter=$starterPath',
        '--starter-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(overwriteResult.exitCode, 1);
      expect(
        overwriteResult.stderr.toString(),
        contains('starter evidence already exists: $starterPath'),
      );
      expect(File(starterPath).readAsStringSync(), 'review in progress\n');
    },
  );

  test(
    'web manual validation updates starter provenance without passing checks',
    () async {
      final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
      final starterPath =
          '${tempDir.path}/evidence/chrome-ime-macos.review.json';

      final templateResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        templateResult.exitCode,
        0,
        reason: templateResult.stderr.toString(),
      );
      final starterResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-starter=$starterPath',
        '--starter-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        starterResult.exitCode,
        0,
        reason: starterResult.stderr.toString(),
      );

      final updateResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--update-provenance=$starterPath',
        '--template-target=chrome-ime-macos',
        '--reviewed-by=manual-reviewer',
        '--captured-at=2026-06-09T06:30:00Z',
        '--browser-version=Chrome/148.0.7778.217',
        '--target=chrome-ime-macos',
        '--json',
      ], workingDirectory: Directory.current.path);
      expect(updateResult.exitCode, 0, reason: updateResult.stderr.toString());
      expect(
        updateResult.stdout.toString(),
        contains('updated provenance $starterPath'),
      );

      final starter =
          jsonDecode(File(starterPath).readAsStringSync())
              as Map<String, Object?>;
      expect(starter['status'], 'needsReview');
      expect(starter['reviewedBy'], 'manual-reviewer');
      expect(starter['capturedAt'], '2026-06-09T06:30:00.000Z');
      final environment = starter['environment'] as Map<String, Object?>;
      expect(environment['browserVersion'], 'Chrome/148.0.7778.217');
      final checks = starter['checks'] as List<Object?>;
      expect(
        checks,
        everyElement(
          isA<Map<String, Object?>>().having(
            (check) => check['status'],
            'status',
            'needsReview',
          ),
        ),
      );

      final auditResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}/evidence',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);
      expect(auditResult.exitCode, 1);
      final audit =
          jsonDecode(auditResult.stdout.toString()) as Map<String, Object?>;
      final target =
          (audit['targets'] as List<Object?>).single as Map<String, Object?>;
      expect(target['strictPass'], isFalse);
      expect(target['status'], 'needsReview');
      expect(target['provenanceBlockers'], isEmpty);
      expect(
        target['missingCheckIds'] as List<Object?>,
        contains('composition-end-commits-once'),
      );
    },
  );

  test('web manual validation updates one evidence check safely', () async {
    final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
    final starterPath = '${tempDir.path}/evidence/chrome-ime-macos.review.json';

    final templateResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(
      templateResult.exitCode,
      0,
      reason: templateResult.stderr.toString(),
    );
    final starterResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-starter=$starterPath',
      '--starter-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(starterResult.exitCode, 0, reason: starterResult.stderr.toString());

    final updateResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--update-check=$starterPath',
      '--template-target=chrome-ime-macos',
      '--check-id=composition-end-commits-once',
      '--check-status=pass',
      '--check-notes=Observed Japanese Romaji commit inserted the selected candidate once.',
      '--target=chrome-ime-macos',
      '--json',
    ], workingDirectory: Directory.current.path);
    expect(updateResult.exitCode, 0, reason: updateResult.stderr.toString());
    expect(
      updateResult.stdout.toString(),
      contains('updated evidence $starterPath'),
    );

    final starter =
        jsonDecode(File(starterPath).readAsStringSync())
            as Map<String, Object?>;
    expect(starter['status'], 'needsReview');
    final checks = (starter['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final updatedCheck = checks.singleWhere(
      (check) => check['id'] == 'composition-end-commits-once',
    );
    expect(updatedCheck['status'], 'pass');
    expect(
      updatedCheck['notes'],
      'Observed Japanese Romaji commit inserted the selected candidate once.',
    );

    final auditResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}/evidence',
      '--target=chrome-ime-macos',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);
    expect(auditResult.exitCode, 1);
    final audit =
        jsonDecode(auditResult.stdout.toString()) as Map<String, Object?>;
    final target =
        (audit['targets'] as List<Object?>).single as Map<String, Object?>;
    expect(target['strictPass'], isFalse);
    expect(
      target['missingCheckIds'] as List<Object?>,
      isNot(contains('composition-end-commits-once')),
    );
  });

  test('web manual validation updates one page signal safely', () async {
    final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
    final starterPath = '${tempDir.path}/evidence/chrome-ime-macos.review.json';

    final templateResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(
      templateResult.exitCode,
      0,
      reason: templateResult.stderr.toString(),
    );
    final starterResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-starter=$starterPath',
      '--starter-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(starterResult.exitCode, 0, reason: starterResult.stderr.toString());

    final updateResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--update-page-signal=$starterPath',
      '--template-target=chrome-ime-macos',
      '--signal-id=retained-dom-ready',
      '--signal-status=pass',
      '--observed-value=ready',
      '--signal-notes=Observed body retained DOM ready attribute after the first rendered frame.',
      '--target=chrome-ime-macos',
      '--json',
    ], workingDirectory: Directory.current.path);
    expect(updateResult.exitCode, 0, reason: updateResult.stderr.toString());
    expect(
      updateResult.stdout.toString(),
      contains('updated evidence $starterPath'),
    );

    final starter =
        jsonDecode(File(starterPath).readAsStringSync())
            as Map<String, Object?>;
    expect(starter['status'], 'needsReview');
    final signals = (starter['observedPageSignals'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final updatedSignal = signals.singleWhere(
      (signal) => signal['id'] == 'retained-dom-ready',
    );
    expect(updatedSignal['status'], 'pass');
    expect(updatedSignal['observedValue'], 'ready');
    expect(
      updatedSignal['notes'],
      'Observed body retained DOM ready attribute after the first rendered frame.',
    );

    final auditResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}/evidence',
      '--target=chrome-ime-macos',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);
    expect(auditResult.exitCode, 1);
    final audit =
        jsonDecode(auditResult.stdout.toString()) as Map<String, Object?>;
    final target =
        (audit['targets'] as List<Object?>).single as Map<String, Object?>;
    expect(target['strictPass'], isFalse);
    expect(target['status'], 'needsReview');
  });

  test('web manual validation rejects copied page signal notes update', () async {
    final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
    final starterPath = '${tempDir.path}/evidence/chrome-ime-macos.review.json';

    final templateResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(
      templateResult.exitCode,
      0,
      reason: templateResult.stderr.toString(),
    );
    final starterResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-starter=$starterPath',
      '--starter-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(starterResult.exitCode, 0, reason: starterResult.stderr.toString());

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--update-page-signal=$starterPath',
      '--template-target=chrome-ime-macos',
      '--signal-id=retained-dom-ready',
      '--signal-status=pass',
      '--observed-value=ready',
      '--signal-notes=${_manualPageSignalDescription('chrome-ime-macos', 'retained-dom-ready')}',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains(
        '--signal-notes must describe reviewer observation, not repeat the template description.',
      ),
    );
  });

  test(
    'web manual validation rejects passing page signal with wrong value',
    () async {
      final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
      final starterPath =
          '${tempDir.path}/evidence/chrome-ime-macos.review.json';

      final templateResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        templateResult.exitCode,
        0,
        reason: templateResult.stderr.toString(),
      );
      final starterResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-starter=$starterPath',
        '--starter-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        starterResult.exitCode,
        0,
        reason: starterResult.stderr.toString(),
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--update-page-signal=$starterPath',
        '--template-target=chrome-ime-macos',
        '--signal-id=retained-dom-ready',
        '--signal-status=pass',
        '--observed-value=mounted',
        '--signal-notes=Observed stale mounted state before the retained DOM ready frame.',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 2);
      expect(
        result.stderr.toString(),
        contains(
          '--observed-value must equal ready for retained-dom-ready when --signal-status=pass.',
        ),
      );
    },
  );

  test('web manual validation rejects copied check notes update', () async {
    final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
    final starterPath = '${tempDir.path}/evidence/chrome-ime-macos.review.json';

    final templateResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(
      templateResult.exitCode,
      0,
      reason: templateResult.stderr.toString(),
    );
    final starterResult = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-starter=$starterPath',
      '--starter-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);
    expect(starterResult.exitCode, 0, reason: starterResult.stderr.toString());

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--update-check=$starterPath',
      '--template-target=chrome-ime-macos',
      '--check-id=composition-end-commits-once',
      '--check-status=pass',
      '--check-notes=${_manualCheckInstruction('chrome-ime-macos', 'composition-end-commits-once')}',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains(
        '--check-notes must describe reviewer observation, not repeat the template instruction.',
      ),
    );
  });

  test(
    'web manual validation rejects provenance update without values',
    () async {
      final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
      final starterPath =
          '${tempDir.path}/evidence/chrome-ime-macos.review.json';

      final templateResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        templateResult.exitCode,
        0,
        reason: templateResult.stderr.toString(),
      );
      final starterResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--write-starter=$starterPath',
        '--starter-template=$templatePath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);
      expect(
        starterResult.exitCode,
        0,
        reason: starterResult.stderr.toString(),
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--update-provenance=$starterPath',
        '--template-target=chrome-ime-macos',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 2);
      expect(
        result.stderr.toString(),
        contains(
          '--update-provenance requires at least one of --reviewed-by, --captured-at, or --browser-version.',
        ),
      );
    },
  );

  test('web manual validation rejects stale starter templates', () async {
    final templatePath = '${tempDir.path}/templates/chrome-ime-macos.json';
    final starterPath = '${tempDir.path}/evidence/chrome-ime-macos.review.json';
    File(templatePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'kind': 'fleuryWebManualValidationEntry',
          'targetId': 'chrome-ime-macos',
          'capturedAt': '2026-06-08T12:00:00.000000Z',
          'status': 'pass',
          'reviewedBy': 'old-reviewer',
          'environment': {'browser': 'Chrome', 'browserVersion': 'old', 'platform': 'macOS'},
          'checks': [
            {'id': 'manual-page-loads-dom-host', 'status': 'pass', 'notes': 'old template'},
          ],
        })}\n',
      );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--write-starter=$starterPath',
      '--starter-template=$templatePath',
      '--template-target=chrome-ime-macos',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('starter template is stale'));
    expect(
      result.stderr.toString(),
      contains('template target.id must be chrome-ime-macos'),
    );
    expect(
      result.stderr.toString(),
      contains(
        'template reviewInstructions.manualValidationPage must be manual_validation.html',
      ),
    );
    expect(
      result.stderr.toString(),
      contains(
        'template reviewInstructions.manualPageBuildCommand must be dart compile js web/manual_validation.dart -o web/manual_validation.dart.js',
      ),
    );
    expect(
      result.stderr.toString(),
      contains(
        'template reviewInstructions.manualPageSmokeCommand must be dart test -p chrome test/manual_validation_page_test.dart',
      ),
    );
    expect(
      result.stderr.toString(),
      contains('template reviewInstructions.manualPageServeNote must be '),
    );
    expect(
      result.stderr.toString(),
      contains(
        'template reviewInstructions.provenanceAttributes must be data-fleury-manual-browser-version data-fleury-manual-platform data-fleury-manual-user-agent data-fleury-manual-page',
      ),
    );
    expect(
      result.stderr.toString(),
      contains('template status must be needsReview'),
    );
    expect(File(starterPath).existsSync(), isFalse);
  });

  test('web manual validation strict mode fails missing targets', () async {
    final jsonOutputPath = '${tempDir.path}/manual-validation-audit.json';

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--target=chrome-ime-macos',
      '--json-output=$jsonOutputPath',
      '--target-preset=all',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final audit =
        jsonDecode(File(jsonOutputPath).readAsStringSync())
            as Map<String, Object?>;
    expect(audit['kind'], 'fleuryWebManualValidationAudit');
    expect(audit['strictPass'], isFalse);
    expect(audit['missingTargets'], ['chrome-ime-macos']);
    final persisted =
        jsonDecode(File(jsonOutputPath).readAsStringSync())
            as Map<String, Object?>;
    expect(persisted['kind'], 'fleuryWebManualValidationAudit');
    expect(persisted['strictPass'], isFalse);
    expect(persisted['missingTargets'], ['chrome-ime-macos']);
  });

  test('web manual validation strict mode passes complete evidence', () async {
    final jsonOutputPath = '${tempDir.path}/manual-validation-audit.json';
    _writeEntry(
      '${tempDir.path}/chrome-ime-macos.json',
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    _writeEntry(
      '${tempDir.path}/chrome-voiceover-macos.json',
      targetId: 'chrome-voiceover-macos',
      checkIds: _chromeVoiceOverChecks,
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--json-output=$jsonOutputPath',
      '--target-preset=all',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['strictPass'], isTrue);
    expect(audit['passedTargetCount'], 2);
    final targets = audit['targets'] as List<Object?>;
    expect(
      targets,
      everyElement(
        isA<Map<String, Object?>>()
            .having((target) => target['strictPass'], 'strictPass', isTrue)
            .having(
              (target) => target['latestEntryFingerprint'],
              'latestEntryFingerprint',
              isA<String>().having(
                (value) => value,
                'value',
                startsWith('fnv1a64:'),
              ),
            )
            .having(
              (target) => target['provenanceBlockers'],
              'provenanceBlockers',
              isEmpty,
            ),
      ),
    );
    final persisted =
        jsonDecode(File(jsonOutputPath).readAsStringSync())
            as Map<String, Object?>;
    expect(persisted['strictPass'], isTrue);
    expect(persisted['passedTargetCount'], 2);
  });

  test('web manual validation rejects empty json output path', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--json-output=',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--json-output requires a non-empty path.'),
    );
  });

  test('web manual validation rejects empty template directory', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--write-templates=',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--write-templates requires a non-empty path.'),
    );
  });

  test('web manual validation strict mode requires provenance', () async {
    _writeEntry(
      '${tempDir.path}/chrome-ime-macos.json',
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
      reviewedBy: '',
      browserVersion: '',
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--target=chrome-ime-macos',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['strictPass'], isFalse);
    expect(audit['needsReviewTargets'], ['chrome-ime-macos']);
    final targets = audit['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target['status'], 'needsReview');
    expect(target['strictPass'], isFalse);
    expect(
      target['provenanceBlockers'] as List<Object?>,
      containsAll(['reviewedBy', 'environment.browserVersion']),
    );
  });

  test(
    'web manual validation strict mode rejects placeholder provenance',
    () async {
      _writeEntry(
        '${tempDir.path}/chrome-ime-macos.json',
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
        reviewedBy: '<reviewer>',
        browserVersion: 'Chrome VERSION',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['needsReviewTargets'], ['chrome-ime-macos']);
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target['status'], 'needsReview');
      expect(target['strictPass'], isFalse);
      expect(
        target['provenanceBlockers'] as List<Object?>,
        containsAll([
          'reviewedBy placeholder',
          'environment.browserVersion placeholder',
        ]),
      );
    },
  );

  test(
    'web manual validation strict mode requires target environment',
    () async {
      _writeEntry(
        '${tempDir.path}/chrome-voiceover-macos.json',
        targetId: 'chrome-voiceover-macos',
        checkIds: _chromeVoiceOverChecks,
        browser: 'Safari',
        platform: 'iOS',
        assistiveTechnology: 'Narrator',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-voiceover-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['needsReviewTargets'], ['chrome-voiceover-macos']);
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(
        target['provenanceBlockers'] as List<Object?>,
        containsAll([
          'environment.browser expected Chrome',
          'environment.platform expected macOS',
          'environment.assistiveTechnology expected VoiceOver',
        ]),
      );
    },
  );

  test(
    'web manual validation requires parseable timestamp and manual page',
    () async {
      _writeEntry(
        '${tempDir.path}/chrome-ime-macos.json',
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
        capturedAt: 'not-a-timestamp',
        fleuryWebPage: 'dom_demo.html',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['needsReviewTargets'], ['chrome-ime-macos']);
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(
        target['provenanceBlockers'] as List<Object?>,
        containsAll([
          'capturedAt must be ISO-8601',
          'environment.fleuryWebPage expected manual_validation.html',
        ]),
      );
    },
  );

  test(
    'web manual validation strict mode requires current page signals in evidence',
    () async {
      final entryPath = '${tempDir.path}/chrome-ime-macos.json';
      _writeEntry(
        entryPath,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
      );
      final entryFile = File(entryPath);
      final entry =
          jsonDecode(entryFile.readAsStringSync()) as Map<String, Object?>;
      final reviewInstructions = (entry['reviewInstructions'] as Map)
          .cast<String, Object?>();
      reviewInstructions['requiredPageSignals'] = [
        manualValidationReadyPageSignal.toJson(),
      ];
      entryFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(entry)}\n',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['needsReviewTargets'], ['chrome-ime-macos']);
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target['status'], 'needsReview');
      expect(
        target['provenanceBlockers'] as List<Object?>,
        contains(
          'evidence reviewInstructions.requiredPageSignals must include retained-dom-ready ime-caret-positioned',
        ),
      );
    },
  );

  test(
    'web manual validation rejects copied template notes as pass evidence',
    () async {
      final entryPath = '${tempDir.path}/chrome-ime-macos.json';
      _writeEntry(
        entryPath,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
        useTemplateCheckNotes: true,
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['needsReviewTargets'], ['chrome-ime-macos']);
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target['status'], 'needsReview');
      expect(
        target['provenanceBlockers'] as List<Object?>,
        contains(
          'evidence check manual-page-loads-dom-host notes must be reviewer observation, not copied instruction',
        ),
      );
    },
  );

  test(
    'web manual validation requires observed page signals for pass evidence',
    () async {
      final entryPath = '${tempDir.path}/chrome-ime-macos.json';
      _writeEntry(
        entryPath,
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
        omitObservedPageSignals: true,
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['needsReviewTargets'], ['chrome-ime-macos']);
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target['status'], 'needsReview');
      expect(
        target['provenanceBlockers'] as List<Object?>,
        containsAll([
          'evidence observedPageSignals must include retained-dom-ready',
          'evidence observedPageSignals must include ime-caret-positioned',
        ]),
      );
    },
  );

  test(
    'web manual validation latest entry prefers parseable timestamps',
    () async {
      _writeEntry(
        '${tempDir.path}/chrome-ime-macos-valid.json',
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
        capturedAt: '2026-06-08T12:00:00.000000Z',
      );
      _writeEntry(
        '${tempDir.path}/chrome-ime-macos-invalid.json',
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks.where(
          (id) => id != 'candidate-window-near-caret',
        ),
        capturedAt: 'zz-not-a-timestamp',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      final targets = audit['targets'] as List<Object?>;
      final target = targets.single as Map<String, Object?>;
      expect(target['latestEntryFile'], 'chrome-ime-macos-valid.json');
      expect(target['latestEntryFingerprint'], startsWith('fnv1a64:'));
      expect(target['strictPass'], isTrue);
    },
  );

  test('web manual validation ignores template files during audit', () async {
    _writeEntry(
      '${tempDir.path}/evidence/chrome-ime-macos.json',
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    _writeTemplateEntry(
      '${tempDir.path}/templates/chrome-ime-macos.template.json',
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks,
    );
    File(
      '${tempDir.path}/manual-validation-audit.json',
    ).writeAsStringSync('{"kind":"fleuryWebManualValidationAudit"}\n');

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--target=chrome-ime-macos',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(audit['strictPass'], isTrue);
    expect(audit['entryCount'], 1);
    expect(audit['ignoredFileCount'], 2);
    final ignoredFiles = audit['ignoredFiles'] as List<Object?>;
    expect(
      ignoredFiles,
      contains(
        isA<Map<String, Object?>>().having(
          (issue) => issue['reason'],
          'reason',
          'template file',
        ),
      ),
    );
    expect(
      ignoredFiles,
      contains(
        isA<Map<String, Object?>>().having(
          (issue) => issue['reason'],
          'reason',
          'generated audit',
        ),
      ),
    );
    final targets = audit['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target['latestEntryFile'], 'chrome-ime-macos.json');
    expect(target['latestEntryFingerprint'], startsWith('fnv1a64:'));
  });

  test(
    'web manual validation strict mode reports invalid evidence json',
    () async {
      final outputPath = '${tempDir.path}/review.md';
      final jsonOutputPath = '${tempDir.path}/manual-validation-audit.json';
      _writeEntry(
        '${tempDir.path}/chrome-ime-macos.json',
        targetId: 'chrome-ime-macos',
        checkIds: _chromeImeChecks,
      );
      File('${tempDir.path}/broken.json').writeAsStringSync('{broken');

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--output=$outputPath',
        '--json-output=$jsonOutputPath',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(File(jsonOutputPath).readAsStringSync())
              as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      expect(audit['entryCount'], 1);
      expect(audit['invalidEntryCount'], 1);
      final invalidEntries = audit['invalidEntries'] as List<Object?>;
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
      final review = File(outputPath).readAsStringSync();
      expect(review, contains('fnv1a64:'));
      expect(review, contains('Invalid Evidence Files'));
    },
  );

  test(
    'web manual validation strict mode reports entries missing targetId',
    () async {
      File('${tempDir.path}/missing-target.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'kind': 'fleuryWebManualValidationEntry', 'capturedAt': '2026-06-08T12:00:00.000000Z', 'status': 'pass'})}\n',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_manual_validation.dart',
        '--input=${tempDir.path}',
        '--target=chrome-ime-macos',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['invalidEntryCount'], 1);
      final invalidEntries = audit['invalidEntries'] as List<Object?>;
      expect(
        invalidEntries.single,
        isA<Map<String, Object?>>()
            .having((issue) => issue['file'], 'file', 'missing-target.json')
            .having(
              (issue) => issue['reason'],
              'reason',
              'targetId is missing',
            ),
      );
    },
  );

  test('web manual validation strict mode fails incomplete checks', () async {
    _writeEntry(
      '${tempDir.path}/chrome-ime-macos.json',
      targetId: 'chrome-ime-macos',
      checkIds: _chromeImeChecks.where(
        (id) => id != 'candidate-window-near-caret',
      ),
    );

    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${tempDir.path}',
      '--target=chrome-ime-macos',
      '--strict',
      '--json',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 1);
    final audit = jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final targets = audit['targets'] as List<Object?>;
    final target = targets.single as Map<String, Object?>;
    expect(target['strictPass'], isFalse);
    expect(target['missingCheckIds'], ['candidate-window-near-caret']);
  });
}

void _writeEntry(
  String path, {
  required String targetId,
  required Iterable<String> checkIds,
  String capturedAt = '2026-06-08T12:00:00.000000Z',
  String reviewedBy = 'tester',
  String browser = 'Chrome',
  String browserVersion = 'test',
  String platform = 'macOS',
  String fleuryWebPage = 'manual_validation.html',
  String? inputMethod,
  String? assistiveTechnology,
  bool useTemplateCheckNotes = false,
  bool omitObservedPageSignals = false,
}) {
  final file = File(path)..parent.createSync(recursive: true);
  final target = manualValidationTargetById(targetId);
  if (target == null) {
    throw ArgumentError.value(targetId, 'targetId', 'unknown target');
  }
  final environment = <String, Object?>{
    'browser': browser,
    'browserVersion': browserVersion,
    'platform': platform,
    'fleuryWebPage': fleuryWebPage,
    if (targetId == 'chrome-ime-macos')
      'inputMethod': inputMethod ?? 'Japanese Romaji test fixture',
    if (targetId == 'chrome-voiceover-macos')
      'assistiveTechnology': assistiveTechnology ?? 'VoiceOver',
  };
  final entry = manualValidationTemplateFor(target)
    ..['capturedAt'] = capturedAt
    ..['status'] = 'pass'
    ..['reviewedBy'] = reviewedBy
    ..['environment'] = environment
    ..['observedPageSignals'] = omitObservedPageSignals
        ? const <Object?>[]
        : [
            for (final signal in target.requiredPageSignals)
              {
                ...signal.toJson(),
                'observedValue': signal.expectedValue,
                'status': 'pass',
                'notes':
                    'Observed ${signal.attribute}=${signal.expectedValue}.',
              },
          ]
    ..['checks'] = [
      for (final id in checkIds)
        {
          'id': id,
          'status': 'pass',
          'notes': useTemplateCheckNotes
              ? _manualCheckInstruction(targetId, id)
              : 'Observed pass for $id.',
        },
    ]
    ..['notes'] = ['test fixture'];
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(entry)}\n',
  );
}

String _manualCheckInstruction(String targetId, String checkId) {
  final target = manualValidationTargetById(targetId);
  if (target == null) {
    throw ArgumentError.value(targetId, 'targetId', 'unknown target');
  }
  for (final check in target.requiredChecks) {
    if (check.id == checkId) return check.instruction;
  }
  throw ArgumentError.value(checkId, 'checkId', 'unknown check');
}

String _manualPageSignalDescription(String targetId, String signalId) {
  final target = manualValidationTargetById(targetId);
  if (target == null) {
    throw ArgumentError.value(targetId, 'targetId', 'unknown target');
  }
  for (final signal in target.requiredPageSignals) {
    if (signal.id == signalId) return signal.description;
  }
  throw ArgumentError.value(signalId, 'signalId', 'unknown page signal');
}

void _writeTemplateEntry(
  String path, {
  required String targetId,
  required Iterable<String> checkIds,
}) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'kind': 'fleuryWebManualValidationEntry',
      'targetId': targetId,
      'capturedAt': '2026-06-08T13:00:00.000000Z',
      'status': 'needsReview',
      'reviewedBy': '',
      'environment': {'browser': 'Chrome', 'browserVersion': '', 'platform': 'macOS'},
      'checks': [
        for (final id in checkIds) {'id': id, 'status': 'needsReview', 'notes': 'template'},
      ],
      'notes': ['template fixture'],
    })}\n',
  );
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
