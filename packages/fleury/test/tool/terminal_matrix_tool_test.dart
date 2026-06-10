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
