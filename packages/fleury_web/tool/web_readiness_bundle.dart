import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/manual_validation/manual_validation_targets.dart';

import 'readiness_bundle_verifier.dart';

void main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }
  if (options.verifyPath != null) {
    final verification = _verifyBundle(options.verifyPath!);
    final verificationJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(verification);
    if (options.json) {
      stdout.writeln(verificationJson);
    } else {
      stdout
        ..writeln('Fleury web readiness bundle verification')
        ..writeln('  bundle: ${options.verifyPath}')
        ..writeln('  strictPass: ${verification['strictPass']}')
        ..writeln(
          '  checkedArtifactCount: ${verification['checkedArtifactCount']}',
        )
        ..writeln('  mismatchCount: ${verification['mismatchCount']}')
        ..writeln(
          '  missingArtifactCount: ${verification['missingArtifactCount']}',
        )
        ..writeln(
          '  missingFingerprintCount: ${verification['missingFingerprintCount']}',
        )
        ..writeln(
          '  checkedSourceInputCount: ${verification['checkedSourceInputCount']}',
        )
        ..writeln(
          '  sourceMismatchCount: ${verification['sourceMismatchCount']}',
        )
        ..writeln(
          '  missingSourceInputCount: ${verification['missingSourceInputCount']}',
        )
        ..writeln(
          '  missingSourceFingerprintCount: ${verification['missingSourceFingerprintCount']}',
        )
        ..writeln(
          '  checkedMetadataCount: ${verification['checkedMetadataCount']}',
        )
        ..writeln(
          '  metadataMismatchCount: ${verification['metadataMismatchCount']}',
        )
        ..writeln(
          '  missingMetadataCount: ${verification['missingMetadataCount']}',
        )
        ..writeln(
          '  checkedManifestFieldCount: ${verification['checkedManifestFieldCount']}',
        )
        ..writeln(
          '  manifestMismatchCount: ${verification['manifestMismatchCount']}',
        )
        ..writeln(
          '  missingManifestFieldCount: ${verification['missingManifestFieldCount']}',
        );
    }
    if (options.strict && verification['strictPass'] != true) exit(1);
    return;
  }

  final outputDir = Directory(options.outputDir)..createSync(recursive: true);
  final scoreboardPath = '${outputDir.path}/scoreboard.json';
  final semanticAuditPath = '${outputDir.path}/semantic-coverage.json';
  final manualPlanPath = '${outputDir.path}/manual-validation-plan.md';
  final manualAuditPath = '${outputDir.path}/manual-validation-audit.json';
  final readinessJsonPath = '${outputDir.path}/web-readiness.json';
  final readinessMarkdownPath = '${outputDir.path}/web-readiness.md';
  final bundleJsonPath = '${outputDir.path}/web-readiness-bundle.json';
  final automatedValidationJsonPath =
      '${outputDir.path}/$webAutomatedValidationFileName';
  final generatedAt = DateTime.now().toUtc().toIso8601String();
  final commandWorkingDirectory = Directory.current.absolute.path;
  final thresholdReviewPath =
      options.thresholdReviewPath ??
      _defaultThresholdReviewPath(options.thresholdsPath);
  final thresholdReviewPlanPath = _thresholdReviewPlanPath(
    _reviewedThresholdOutputPath(options.thresholdsPath),
  );
  final preflightArtifacts = <String, Map<String, String>>{};
  final preflightChecks = <String, bool>{};

  final scoreboard = await _runJsonOutputTool(
    [
      'tool/web_frame_scoreboard.dart',
      '--input=${options.captureDir}',
      '--json-output=$scoreboardPath',
      '--min-runs=${options.minRuns}',
      if (options.maxTotalFrameP95Ms != null)
        '--max-total-frame-p95-ms=${options.maxTotalFrameP95Ms}',
      if (options.maxDomApplyP95Ms != null)
        '--max-dom-apply-p95-ms=${options.maxDomApplyP95Ms}',
      if (options.maxSemanticApplyP95Ms != null)
        '--max-semantic-apply-p95-ms=${options.maxSemanticApplyP95Ms}',
      if (options.maxOverBudgetPercent != null)
        '--max-over-budget-percent=${options.maxOverBudgetPercent}',
      if (options.maxSemanticUncoveredCells != null)
        '--max-semantic-uncovered-cells=${options.maxSemanticUncoveredCells}',
      if (options.thresholdsPath != null)
        '--thresholds=${options.thresholdsPath}',
      if (options.requireComparableRunEnvironment)
        '--require-comparable-environment',
    ],
    outputPath: scoreboardPath,
    expectedKind: 'fleuryWebFrameScoreboard',
  );

  final semanticAudit = await _runJsonOutputTool(
    [
      'tool/web_semantic_coverage_audit.dart',
      '--input=${options.captureDir}',
      '--json-output=$semanticAuditPath',
      if (options.maxFallbackCells != null)
        '--max-fallback-cells=${options.maxFallbackCells}',
      if (options.maxFallbackFramePercent != null)
        '--max-fallback-frame-percent=${options.maxFallbackFramePercent}',
      if (options.maxFallbackViewportPercent != null)
        '--max-fallback-viewport-percent=${options.maxFallbackViewportPercent}',
    ],
    outputPath: semanticAuditPath,
    expectedKind: 'fleuryWebSemanticCoverageAudit',
  );

  final manualAudit = await _runJsonOutputTool(
    [
      'tool/web_manual_validation.dart',
      '--input=${options.manualDir}',
      '--write-plan=$manualPlanPath',
      '--json-output=$manualAuditPath',
      '--target-preset=${options.targetPreset}',
      for (final targetId in options.targetIds) '--target=$targetId',
    ],
    outputPath: manualAuditPath,
    expectedKind: 'fleuryWebManualValidationAudit',
  );

  final readiness = await _runJsonOutputTool(
    [
      'tool/web_readiness.dart',
      '--scoreboard=$scoreboardPath',
      '--semantic-audit=$semanticAuditPath',
      '--manual-audit=$manualAuditPath',
      if (thresholdReviewPath != null)
        '--threshold-review=$thresholdReviewPath',
      '--output=$readinessMarkdownPath',
      '--json-output=$readinessJsonPath',
      '--min-scoreboard-runs=${options.minRuns}',
      if (!options.requireComparableRunEnvironment)
        '--no-require-comparable-environment',
      if (!options.requireScoreboardGates) '--no-require-scoreboard-gates',
      if (!options.requireTotalFrameGate) '--no-require-total-frame-gate',
      if (!options.requireReviewedThresholdPolicy)
        '--no-require-reviewed-threshold-policy',
      if (!options.requireThresholdReviewSummary)
        '--no-require-threshold-review-summary',
      if (!options.requireScenarioThresholds)
        '--no-require-scenario-thresholds',
      if (!options.requireSemanticGates) '--no-require-semantic-gates',
    ],
    outputPath: readinessJsonPath,
    expectedKind: 'fleuryWebReadinessAudit',
  );

  if (options.writeDefaultPreflights) {
    for (final target in _DefaultPreflightTarget.values) {
      final jsonPath =
          '${outputDir.path}/web-default-preflight-${target.id}.json';
      final markdownPath =
          '${outputDir.path}/web-default-preflight-${target.id}.md';
      final hasAutomatedValidationArtifact = File(
        automatedValidationJsonPath,
      ).existsSync();
      final preflight = await _runJsonOutputTool(
        [
          'tool/web_default_preflight.dart',
          '--readiness=$readinessJsonPath',
          '--target=${target.id}',
          '--output=$markdownPath',
          '--json-output=$jsonPath',
          if (hasAutomatedValidationArtifact)
            '--automated-validation=$automatedValidationJsonPath',
          '--allow-unbundled',
        ],
        outputPath: jsonPath,
        expectedKind: 'fleuryWebDefaultPreflight',
      );
      preflightArtifacts[target.id] = <String, String>{
        'json': jsonPath,
        'markdown': markdownPath,
      };
      preflightChecks[target.id] = preflight['strictPass'] == true;
    }
  }

  final artifacts = <String, Object?>{
    'bundleJson': bundleJsonPath,
    'scoreboard': scoreboardPath,
    'semanticAudit': semanticAuditPath,
    'manualPlan': manualPlanPath,
    'manualAudit': manualAuditPath,
    'readinessJson': readinessJsonPath,
    'readinessMarkdown': readinessMarkdownPath,
    if (preflightArtifacts.isNotEmpty) 'defaultPreflights': preflightArtifacts,
  };
  final remainingReleaseActions = _remainingReleaseActions(
    readiness: readiness,
    scoreboard: scoreboard,
    defaultPreflightChecks: preflightChecks,
    captureDir: options.captureDir,
    manualDir: options.manualDir,
    outputDir: outputDir.path,
    thresholdPolicyPath: options.thresholdsPath,
    thresholdReviewPath: thresholdReviewPath,
    readinessJsonPath: readinessJsonPath,
    bundleJsonPath: bundleJsonPath,
    automatedValidationJsonPath: automatedValidationJsonPath,
    completionAuditPath: options.completionAuditPath,
    requireComparableRunEnvironment: options.requireComparableRunEnvironment,
    requireScenarioThresholds: options.requireScenarioThresholds,
    requireThresholdReviewSummary: options.requireThresholdReviewSummary,
    targetPreset: options.targetPreset,
    targetIds: options.targetIds,
  );
  if (remainingReleaseActions.isNotEmpty) {
    final releaseActionsMarkdownPath =
        '${outputDir.path}/web-release-actions.md';
    File(releaseActionsMarkdownPath).writeAsStringSync(
      _releaseActionsMarkdown(
        actions: remainingReleaseActions,
        bundleJsonPath: bundleJsonPath,
        commandWorkingDirectory: commandWorkingDirectory,
        readinessJsonPath: readinessJsonPath,
        generatedAt: generatedAt,
      ),
    );
    artifacts['releaseActionsMarkdown'] = releaseActionsMarkdownPath;
  }
  final sourceInputFingerprints = readinessBundleSourceInputFingerprints(
    captureDir: options.captureDir,
    manualDir: options.manualDir,
    manualTemplateTargetIds: _manualTargetIdsFromAudit(
      manualAudit,
      fallbackTargetIds: options.targetIds,
    ),
    manualEvidenceTargetIds: _manualTargetIdsFromAudit(
      manualAudit,
      fallbackTargetIds: options.targetIds,
    ),
    thresholdPolicyPath: options.thresholdsPath,
    thresholdReviewPath: thresholdReviewPath,
    thresholdReviewPlanPath: thresholdReviewPlanPath,
  );
  final bundle = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebReadinessBundle',
    'generatedAt': generatedAt,
    'strictPass': readiness['strictPass'] == true,
    'input': <String, Object?>{
      'captureDir': options.captureDir,
      'manualDir': options.manualDir,
      'commandWorkingDirectory': commandWorkingDirectory,
      'minRuns': options.minRuns,
      if (options.thresholdsPath != null)
        'thresholdPolicyPath': options.thresholdsPath,
      if (thresholdReviewPath != null)
        'thresholdReviewPath': thresholdReviewPath,
      'targetPreset': options.targetPreset,
      if (options.targetIds.isNotEmpty) 'targetIds': options.targetIds,
      'requireComparableRunEnvironment':
          options.requireComparableRunEnvironment,
      'requireThresholdReviewSummary': options.requireThresholdReviewSummary,
      'requireScenarioThresholds': options.requireScenarioThresholds,
    },
    'artifacts': artifacts,
    'artifactFingerprints': _artifactFingerprints(artifacts),
    'sourceInputFingerprints': sourceInputFingerprints,
    'remainingReleaseActions': remainingReleaseActions,
    'checks': <String, Object?>{
      'scoreboardStrictPass': scoreboard['strictPass'] == true,
      'semanticAuditStrictPass': semanticAudit['strictPass'] == true,
      'manualAuditStrictPass': manualAudit['strictPass'] == true,
      'readinessStrictPass': readiness['strictPass'] == true,
      if (preflightChecks.isNotEmpty)
        'defaultPreflightStrictPass': preflightChecks,
      if (preflightChecks.isNotEmpty)
        'defaultPreflightBundleBound': {
          for (final targetId in preflightChecks.keys) targetId: false,
        },
      if (preflightChecks.isNotEmpty)
        'defaultPreflightFinalGateRequiresBundle': true,
    },
    'readiness': readiness,
  };
  final bundleJson = const JsonEncoder.withIndent('  ').convert(bundle);
  File(bundleJsonPath).writeAsStringSync('$bundleJson\n');

  if (options.completionAuditPath != null) {
    final completionAudit = _buildCompletionAudit(
      bundle: bundle,
      verification: _verifyBundle(bundleJsonPath),
      generatedAt: generatedAt,
    );
    final output = File(options.completionAuditPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(completionAudit)}\n',
    );
  }

  if (options.json) {
    stdout.writeln(bundleJson);
  } else {
    stdout
      ..writeln('Fleury web readiness bundle')
      ..writeln('  output: ${outputDir.path}')
      ..writeln('  strictPass: ${bundle['strictPass']}')
      ..writeln('  manifest: $bundleJsonPath')
      ..writeln('  readiness: $readinessMarkdownPath');
    if (remainingReleaseActions.isNotEmpty) {
      stdout.writeln(
        '  release actions: ${artifacts['releaseActionsMarkdown']}',
      );
    }
    if (options.completionAuditPath != null) {
      stdout.writeln('  completion audit: ${options.completionAuditPath}');
    }
    for (final entry in preflightArtifacts.entries) {
      stdout.writeln('  preflight ${entry.key}: ${entry.value['markdown']}');
    }
  }

  if (options.strict && bundle['strictPass'] != true) exit(1);
}

Future<Map<String, Object?>> _runJsonOutputTool(
  List<String> args, {
  required String outputPath,
  required String expectedKind,
}) async {
  await _runTool(args);
  final output = File(outputPath);
  if (!output.existsSync()) {
    stderr.writeln(
      'Tool `${_display(args)}` did not write expected JSON output `$outputPath`.',
    );
    exit(2);
  }
  final outputText = output.readAsStringSync();
  Object? decoded;
  try {
    decoded = jsonDecode(outputText);
  } on FormatException catch (error) {
    stderr
      ..writeln(
        'Failed to decode JSON output `$outputPath` from `${_display(args)}`.',
      )
      ..writeln(error.message)
      ..writeln(outputText);
    exit(2);
  }
  if (decoded is! Map) {
    stderr.writeln(
      'Tool `${_display(args)}` wrote `$outputPath`, but it was not a JSON object.',
    );
    exit(2);
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != expectedKind) {
    stderr.writeln(
      'Tool `${_display(args)}` returned kind `${json['kind']}`, expected `$expectedKind`.',
    );
    exit(2);
  }
  return json;
}

Future<ProcessResult> _runTool(List<String> args) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'run',
    ...args,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    stderr
      ..writeln('Command failed with exit code ${result.exitCode}:')
      ..writeln('  dart run ${_display(args)}')
      ..writeln(result.stderr);
    exit(result.exitCode);
  }
  return result;
}

String _display(List<String> args) => args.map(_shellArg).join(' ');

String _shellArg(String arg) {
  if (arg.isEmpty) return "''";
  final safe = RegExp(r'^[A-Za-z0-9_./:=+,-]+$');
  if (safe.hasMatch(arg)) return arg;
  return "'${arg.replaceAll("'", "'\\''")}'";
}

List<Map<String, Object?>> _maps(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return [
    for (final item in raw)
      if (item is Map<String, Object?>)
        item
      else if (item is Map)
        item.cast<String, Object?>(),
  ];
}

Map<String, Object?> _map(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) return raw.cast<String, Object?>();
  return const <String, Object?>{};
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final item in raw) item.toString()];
}

String? _string(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

List<String> _manualTargetIdsFromAudit(
  Map<String, Object?> manualAudit, {
  required List<String> fallbackTargetIds,
}) {
  final ids = <String>[];
  for (final target in _maps(manualAudit['targets'])) {
    final id = target['id']?.toString().trim() ?? '';
    if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  if (ids.isNotEmpty) return ids;
  return [
    for (final id in fallbackTargetIds)
      if (id.trim().isNotEmpty) id.trim(),
  ];
}

List<Map<String, Object?>> _remainingReleaseActions({
  required Map<String, Object?> readiness,
  required Map<String, Object?> scoreboard,
  required Map<String, bool> defaultPreflightChecks,
  required String captureDir,
  required String manualDir,
  required String outputDir,
  required String? thresholdPolicyPath,
  required String? thresholdReviewPath,
  required String readinessJsonPath,
  required String bundleJsonPath,
  required String automatedValidationJsonPath,
  required String? completionAuditPath,
  required bool requireComparableRunEnvironment,
  required bool requireScenarioThresholds,
  required bool requireThresholdReviewSummary,
  required String targetPreset,
  required List<String> targetIds,
}) {
  final actions = <Map<String, Object?>>[];
  final dependencyIds = <String>[];
  var bundleThresholdPolicyPath = thresholdPolicyPath;

  final frameCheck = _readinessCheck(readiness, 'frameScoreboard');
  if (frameCheck != null && frameCheck['strictPass'] != true) {
    final blockers = _strings(frameCheck['blockers']);
    final details = _map(frameCheck['details']);
    final actionThresholdPolicyPath =
        thresholdPolicyPath ?? details['thresholdPolicyPath']?.toString();
    final reviewedThresholdPath = _reviewedThresholdOutputPath(
      actionThresholdPolicyPath,
    );
    if (reviewedThresholdPath != null) {
      bundleThresholdPolicyPath = reviewedThresholdPath;
    }
    actions.add(
      _thresholdReviewAction(
        thresholdPolicyPath: actionThresholdPolicyPath,
        thresholdReviewPath:
            thresholdReviewPath ?? details['thresholdReviewPath']?.toString(),
        reviewState: details['thresholdPolicyReviewState']?.toString(),
        fingerprint: details['thresholdPolicyFingerprint']?.toString(),
        captureEnvironment: _captureEnvironmentSummary(scoreboard),
        blockers: blockers,
      ),
    );
    dependencyIds.add('review-threshold-policy');
  }

  final manualCheck = _readinessCheck(readiness, 'manualValidation');
  if (manualCheck != null && manualCheck['strictPass'] != true) {
    final details = _map(manualCheck['details']);
    final targets = _maps(details['failingTargetDetails']);
    final knownTargetIds = [
      for (final target in targets)
        if ((target['id']?.toString() ?? '').trim().isNotEmpty)
          target['id'].toString(),
    ];
    final preparationTargetIds = knownTargetIds.isEmpty
        ? targetIds
        : knownTargetIds;
    const prepareManualTemplatesId = 'prepare-manual-evidence-templates';
    final templateStatuses = _manualTemplateStatuses(
      manualDir: manualDir,
      targetIds: preparationTargetIds,
    );
    final templateStatusById = <String, Map<String, Object?>>{
      for (final status in templateStatuses)
        status['targetId'].toString(): status,
    };
    final templatesNeedPreparation = templateStatuses.any(
      (status) => status['status'] != 'current',
    );
    final evidenceDependsOn = templatesNeedPreparation
        ? const [prepareManualTemplatesId]
        : const <String>[];
    if (templatesNeedPreparation) {
      actions.add(
        _manualTemplatePreparationAction(
          manualDir: manualDir,
          targetPreset: targetPreset,
          targetIds: preparationTargetIds,
          templateStatuses: templateStatuses,
        ),
      );
    }
    if (targets.isEmpty) {
      actions.add(
        _manualEvidenceAction(
          manualDir: manualDir,
          target: const <String, Object?>{'id': '<target>'},
          blockers: _strings(manualCheck['blockers']),
          targetPreset: targetPreset,
          targetIds: targetIds,
          dependsOn: evidenceDependsOn,
          templateStatus: null,
        ),
      );
      dependencyIds.add('collect-manual-evidence:<target>');
    } else {
      for (final target in targets) {
        final id = target['id']?.toString() ?? '<target>';
        final templateStatus = templateStatusById[id];
        actions.add(
          _manualEvidenceAction(
            manualDir: manualDir,
            target: target,
            blockers: _strings(manualCheck['blockers']),
            targetPreset: targetPreset,
            targetIds: targetIds,
            dependsOn: evidenceDependsOn,
            templateStatus: templateStatus,
          ),
        );
        dependencyIds.add('collect-manual-evidence:$id');
      }
    }
  }

  final needsRegeneration =
      actions.isNotEmpty || readiness['strictPass'] != true;
  final needsFinalDefaultPreflights = defaultPreflightChecks.isNotEmpty;
  if (needsRegeneration) {
    actions.add(
      _regenerateBundleAction(
        captureDir: captureDir,
        manualDir: manualDir,
        outputDir: outputDir,
        thresholdPolicyPath: bundleThresholdPolicyPath,
        thresholdReviewPath: thresholdReviewPath,
        requireComparableRunEnvironment: requireComparableRunEnvironment,
        requireScenarioThresholds: requireScenarioThresholds,
        requireThresholdReviewSummary: requireThresholdReviewSummary,
        targetPreset: targetPreset,
        targetIds: targetIds,
        dependsOn: dependencyIds,
        completionAuditPath: completionAuditPath,
      ),
    );
  }

  if (needsRegeneration || needsFinalDefaultPreflights) {
    actions.add(
      _verifyBundleAction(
        bundleJsonPath: bundleJsonPath,
        dependsOn: needsRegeneration
            ? const ['regenerate-readiness-bundle']
            : const <String>[],
      ),
    );
    actions.add(
      _automatedWebHostTestsAction(
        automatedValidationJsonPath: automatedValidationJsonPath,
        dependsOn: const ['verify-readiness-bundle'],
      ),
    );
  }

  for (final entry in defaultPreflightChecks.entries) {
    actions.add(
      _defaultPreflightAction(
        targetId: entry.key,
        readinessJsonPath: readinessJsonPath,
        bundleJsonPath: bundleJsonPath,
        automatedValidationJsonPath: automatedValidationJsonPath,
        previewStrictPass: entry.value,
        dependsOn: [
          if (needsRegeneration) 'regenerate-readiness-bundle',
          'verify-readiness-bundle',
          'run-automated-web-host-tests',
        ],
      ),
    );
  }

  return actions;
}

String _releaseActionsMarkdown({
  required List<Map<String, Object?>> actions,
  required String bundleJsonPath,
  required String commandWorkingDirectory,
  required String readinessJsonPath,
  required String generatedAt,
}) {
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Release Actions')
    ..writeln()
    ..writeln('- Generated at: `$generatedAt`')
    ..writeln('- Bundle manifest: `$bundleJsonPath`')
    ..writeln('- Readiness artifact: `$readinessJsonPath`')
    ..writeln('- Command working directory: `$commandWorkingDirectory`')
    ..writeln('- Remaining action count: `${actions.length}`')
    ..writeln()
    ..writeln(
      'These actions are generated from the readiness bundle. Complete them in dependency order, then require strict bundle verification and bundle-bound default preflights before changing web defaults.',
    )
    ..writeln();
  final rootCommandWorkingDirectory = _rootCommandWorkingDirectory(
    commandWorkingDirectory,
  );

  for (var index = 0; index < actions.length; index += 1) {
    final action = actions[index];
    buffer
      ..writeln('## ${index + 1}. ${action['id']}')
      ..writeln()
      ..writeln('- Kind: `${action['kind'] ?? 'unknown'}`');
    final label = action['label']?.toString();
    if (label != null && label.trim().isNotEmpty) {
      buffer.writeln('- Label: $label');
    }
    _writeActionList(buffer, 'Depends on', action['dependsOn']);
    _writeActionList(buffer, 'Blocking checks', action['blockingChecks']);
    _writeActionList(buffer, 'Blockers', action['blockers']);
    final targetId = action['targetId']?.toString();
    if (targetId != null && targetId.trim().isNotEmpty) {
      buffer.writeln('- Target: `$targetId`');
    }
    final status = action['status']?.toString();
    if (status != null && status.trim().isNotEmpty) {
      buffer.writeln('- Status: `$status`');
    }
    buffer.writeln();
    _writeActionDetails(buffer, action['details']);
    _writeActionCommand(
      buffer,
      'Plan command',
      action['planCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root plan command',
      action['rootPlanCommand'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Command',
      action['commandTemplate'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root command',
      action['rootCommandTemplate'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Browser test command',
      action['browserTestCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'VM test command',
      action['vmTestCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Manual page build command',
      action['manualPageBuildCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Manual page smoke command',
      action['manualPageSmokeCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Manual page serve setup command',
      action['manualPageServeSetupCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Manual page serve command',
      action['manualPageServeCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Starter command',
      action['starterCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root starter command',
      action['rootStarterCommand'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Provenance command',
      action['provenanceCommandTemplate'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Page signal update command',
      action['pageSignalCommandTemplate'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Check update command',
      action['checkCommandTemplate'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root provenance command',
      action['rootProvenanceCommandTemplate'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root page signal update command',
      action['rootPageSignalCommandTemplate'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root check update command',
      action['rootCheckCommandTemplate'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Audit command',
      action['auditCommand'],
      commandWorkingDirectory: commandWorkingDirectory,
    );
    _writeActionCommand(
      buffer,
      'Root audit command',
      action['rootAuditCommand'],
      commandWorkingDirectory: rootCommandWorkingDirectory,
    );
  }

  return buffer.toString();
}

String _rootCommandWorkingDirectory(String commandWorkingDirectory) {
  final packageDir = Directory(commandWorkingDirectory);
  final parent = packageDir.parent;
  if (_pathBasename(parent.path) == 'packages') return parent.parent.path;
  return packageDir.path;
}

String _pathBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash == -1 ? normalized : normalized.substring(slash + 1);
}

void _writeActionList(StringBuffer buffer, String label, Object? raw) {
  final values = _strings(raw);
  if (values.isEmpty) return;
  buffer.writeln('- $label: ${values.map((value) => '`$value`').join(', ')}');
}

void _writeActionDetails(StringBuffer buffer, Object? raw) {
  final details = _map(raw);
  if (details.isEmpty) return;
  buffer
    ..writeln('| Detail | Value |')
    ..writeln('| --- | --- |');
  for (final entry in details.entries) {
    buffer.writeln(
      '| `${_markdownTableCell(entry.key)}` | ${_markdownTableCell(_markdownValue(entry.value))} |',
    );
  }
  buffer.writeln();
}

void _writeActionCommand(
  StringBuffer buffer,
  String label,
  Object? raw, {
  required String commandWorkingDirectory,
}) {
  final command = _strings(raw);
  if (command.isEmpty) return;
  buffer
    ..writeln('**$label**')
    ..writeln()
    ..writeln('Run from: `$commandWorkingDirectory`')
    ..writeln()
    ..writeln('```sh')
    ..writeln(_display(command))
    ..writeln('```')
    ..writeln();
}

String _markdownValue(Object? value) {
  if (value == null) return '';
  if (value is List) {
    if (value.every((item) => item is String || item is num || item is bool)) {
      return value.join(', ');
    }
    return jsonEncode(value);
  }
  if (value is Map) return jsonEncode(value);
  return value.toString();
}

String _markdownTableCell(String value) =>
    value.replaceAll('|', r'\|').replaceAll('\n', '<br>');

Map<String, Object?> _thresholdReviewAction({
  required String? thresholdPolicyPath,
  required String? thresholdReviewPath,
  required String? reviewState,
  required String? fingerprint,
  required Map<String, Object?> captureEnvironment,
  required List<String> blockers,
}) {
  final outputPath = _reviewedThresholdOutputPath(thresholdPolicyPath);
  final jsonOutput =
      thresholdReviewPath ?? _defaultThresholdReviewPath(outputPath);
  final planOutput = _thresholdReviewPlanPath(outputPath);
  final captureReviewContextHint = captureEnvironment['reviewContextHint']
      ?.toString()
      .trim();
  final candidateReviewContextHint = _thresholdPolicyReviewContextHint(
    thresholdPolicyPath,
  );
  final reviewContextHint =
      candidateReviewContextHint ?? captureReviewContextHint;
  final hasReviewContextHint =
      reviewContextHint != null && reviewContextHint.isNotEmpty;
  final planCommandReviewContextHint = candidateReviewContextHint == null
      ? reviewContextHint
      : null;
  final planDetails = _thresholdReviewPlanDetails(
    planOutput,
    expectedInputFingerprint: fingerprint,
  );
  final overBudgetScenarios = _thresholdPolicyOverBudgetScenarios(
    thresholdPolicyPath,
  );
  final hasOverBudgetThresholds = overBudgetScenarios.isNotEmpty;
  final placeholders = <Map<String, Object?>>[
    <String, Object?>{
      'name': 'reviewer',
      'argument': '--reviewed-by',
      'placeholder': '<reviewer>',
      'description': 'human reviewer name or handle',
    },
    if (!hasReviewContextHint)
      <String, Object?>{
        'name': 'reviewContext',
        'argument': '--review-context',
        'placeholder':
            '<Chrome version, platform, retained DOM product baseline>',
        'description':
            'browser version, platform, and retained DOM baseline reviewed',
      },
    if (hasOverBudgetThresholds)
      <String, Object?>{
        'name': 'reviewNote',
        'argument': '--review-note',
        'placeholder':
            '<why these over-budget thresholds are acceptable for this reviewed baseline>',
        'description':
            'explicit justification for accepting thresholds that allow over-budget frames',
      },
  ];
  final actionBlockers = [
    ...blockers,
    ..._thresholdReviewPlanBlockers(planDetails),
  ];
  return <String, Object?>{
    'id': 'review-threshold-policy',
    'kind': 'human-review',
    'label': 'Review and promote per-scenario web thresholds',
    'blockingChecks': const ['frameScoreboard'],
    'blockers': actionBlockers,
    'details': <String, Object?>{
      if (thresholdPolicyPath != null)
        'candidateThresholdPolicyPath': thresholdPolicyPath,
      if (outputPath != null) 'reviewedThresholdPolicyPath': outputPath,
      if (jsonOutput != null) 'thresholdReviewPath': jsonOutput,
      if (planOutput != null) 'thresholdReviewPlanPath': planOutput,
      if (reviewState != null) 'currentReviewState': reviewState,
      if (fingerprint != null) 'currentThresholdPolicyFingerprint': fingerprint,
      if (fingerprint != null) 'expectedInputFingerprint': fingerprint,
      if (captureEnvironment.isNotEmpty)
        'captureEnvironment': captureEnvironment,
      if (candidateReviewContextHint != null)
        'candidateReviewContextHint': candidateReviewContextHint,
      if (candidateReviewContextHint != null)
        'planCommandUsesCandidateCapturedContext': true,
      if (hasReviewContextHint) 'suggestedReviewContext': reviewContextHint,
      if (hasOverBudgetThresholds) ...<String, Object?>{
        'overBudgetThresholdScenarioCount': overBudgetScenarios.length,
        'overBudgetThresholdScenarios': overBudgetScenarios,
        'overBudgetAcknowledgementRequired': true,
      },
      'commandTemplateRunnable': false,
      'commandTemplatePlaceholders': placeholders,
      'reviewerNextStep': hasOverBudgetThresholds
          ? 'replace commandTemplate placeholders, verify suggestedReviewContext if present, and keep --allow-over-budget-thresholds only after explicitly accepting the over-budget scenarios in --review-note'
          : hasReviewContextHint
          ? 'replace the reviewer placeholder and verify suggestedReviewContext before running threshold review promotion'
          : 'replace commandTemplate placeholders before running threshold review promotion',
      ...planDetails,
    },
    if (thresholdPolicyPath != null && planOutput != null)
      'planCommand': [
        'dart',
        'run',
        'tool/web_threshold_review.dart',
        '--input=$thresholdPolicyPath',
        '--write-plan=$planOutput',
        if (planCommandReviewContextHint != null)
          '--review-context-hint=$planCommandReviewContextHint',
      ],
    if (thresholdPolicyPath != null && planOutput != null)
      'rootPlanCommand': [
        'dart',
        'run',
        'tool/fleury_dev.dart',
        'benchmark',
        'web-threshold-review',
        '--input=$thresholdPolicyPath',
        '--write-plan=$planOutput',
        if (planCommandReviewContextHint != null)
          '--review-context-hint=$planCommandReviewContextHint',
      ],
    'commandTemplate': [
      'dart',
      'run',
      'tool/web_threshold_review.dart',
      if (thresholdPolicyPath != null) '--input=$thresholdPolicyPath',
      if (outputPath != null) '--output=$outputPath',
      if (jsonOutput != null) '--json-output=$jsonOutput',
      if (fingerprint != null) '--expect-input-fingerprint=$fingerprint',
      '--reviewed-by=<reviewer>',
      if (hasReviewContextHint)
        '--review-context=$reviewContextHint'
      else
        '--review-context=<Chrome version, platform, retained DOM product baseline>',
      if (hasOverBudgetThresholds) '--allow-over-budget-thresholds',
      if (hasOverBudgetThresholds)
        '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
    ],
    'rootCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-threshold-review',
      if (thresholdPolicyPath != null) '--input=$thresholdPolicyPath',
      if (outputPath != null) '--output=$outputPath',
      if (jsonOutput != null) '--json-output=$jsonOutput',
      if (fingerprint != null) '--expect-input-fingerprint=$fingerprint',
      '--reviewed-by=<reviewer>',
      if (hasReviewContextHint)
        '--review-context=$reviewContextHint'
      else
        '--review-context=<Chrome version, platform, retained DOM product baseline>',
      if (hasOverBudgetThresholds) '--allow-over-budget-thresholds',
      if (hasOverBudgetThresholds)
        '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
    ],
  };
}

String? _thresholdPolicyReviewContextHint(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final generatedFrom = decoded['generatedFrom'];
  if (generatedFrom is! Map<String, Object?>) return null;
  final captureEnvironment = generatedFrom['captureEnvironment'];
  if (captureEnvironment is! Map<String, Object?>) return null;
  final reviewContextHint = captureEnvironment['reviewContextHint']
      ?.toString()
      .trim();
  if (reviewContextHint == null || reviewContextHint.isEmpty) return null;
  return reviewContextHint;
}

List<Map<String, Object?>> _thresholdPolicyOverBudgetScenarios(String? path) {
  if (path == null || path.trim().isEmpty)
    return const <Map<String, Object?>>[];
  final file = File(path);
  if (!file.existsSync()) return const <Map<String, Object?>>[];
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return const <Map<String, Object?>>[];
  }
  final scenarios = _map(_map(decoded)['scenarios']);
  if (scenarios.isEmpty) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  for (final entry in scenarios.entries) {
    final scenario = _map(entry.value);
    final maxOverBudgetPercent = _number(scenario['maxOverBudgetPercent']);
    if (maxOverBudgetPercent == null || maxOverBudgetPercent <= 0) continue;
    result.add(<String, Object?>{
      'id': entry.key,
      if (scenario['maxTotalFrameP95Ms'] != null)
        'maxTotalFrameP95Ms': scenario['maxTotalFrameP95Ms'],
      'maxOverBudgetPercent': scenario['maxOverBudgetPercent'],
    });
  }
  return result;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

Map<String, Object?> _captureEnvironmentSummary(
  Map<String, Object?> scoreboard,
) {
  final scenarios = _maps(scoreboard['scenarios']);
  if (scenarios.isEmpty) return const <String, Object?>{};
  final environments = [
    for (final scenario in scenarios)
      if (_map(scenario['latestRunEnvironment']).isNotEmpty)
        _map(scenario['latestRunEnvironment']),
  ];
  if (environments.isEmpty) return const <String, Object?>{};

  final chromeBrowsers = _uniqueEnvironmentValues(
    environments,
    'chromeBrowser',
  );
  final operatingSystems = _uniqueEnvironmentValues(
    environments,
    'operatingSystem',
  );
  final operatingSystemVersions = _uniqueEnvironmentValues(
    environments,
    'operatingSystemVersion',
  );
  final dartVersions = _uniqueEnvironmentValues(environments, 'dartVersion');
  final headlessValues = _uniqueEnvironmentValues(environments, 'headless');
  final frameBudgetValues = _uniqueEnvironmentValues(
    environments,
    'frameBudgetMs',
  );
  final requestedFrameValues = _uniqueEnvironmentValues(
    environments,
    'requestedFrames',
  );
  final warmupFrameValues = _uniqueEnvironmentValues(
    environments,
    'warmupFrames',
  );
  final comparableScenarioCount = scenarios
      .where((scenario) => scenario['runEnvironmentComparable'] == true)
      .length;
  return <String, Object?>{
    'scenarioCount': scenarios.length,
    'scenarioWithEnvironmentCount': environments.length,
    'comparableScenarioCount': comparableScenarioCount,
    'allScenariosComparable':
        comparableScenarioCount == scenarios.length &&
        environments.length == scenarios.length,
    if (chromeBrowsers.isNotEmpty)
      'chromeBrowser': _singleOrList(chromeBrowsers),
    if (operatingSystems.isNotEmpty)
      'operatingSystem': _singleOrList(operatingSystems),
    if (operatingSystemVersions.isNotEmpty)
      'operatingSystemVersion': _singleOrList(operatingSystemVersions),
    if (dartVersions.isNotEmpty) 'dartVersion': _singleOrList(dartVersions),
    if (headlessValues.isNotEmpty) 'headless': _singleOrList(headlessValues),
    if (frameBudgetValues.isNotEmpty)
      'frameBudgetMs': _singleOrList(frameBudgetValues),
    if (requestedFrameValues.isNotEmpty)
      'requestedFrames': _singleOrList(requestedFrameValues),
    if (warmupFrameValues.isNotEmpty)
      'warmupFrames': _singleOrList(warmupFrameValues),
    if (chromeBrowsers.isNotEmpty && operatingSystems.isNotEmpty)
      'reviewContextHint': _reviewContextHint(
        chromeBrowsers: chromeBrowsers,
        operatingSystems: operatingSystems,
        operatingSystemVersions: operatingSystemVersions,
        dartVersions: dartVersions,
        headlessValues: headlessValues,
        frameBudgetValues: frameBudgetValues,
      ),
  };
}

List<Object?> _uniqueEnvironmentValues(
  List<Map<String, Object?>> environments,
  String key,
) {
  final values = <Object?>[];
  for (final environment in environments) {
    final value = environment[key];
    if (value == null || values.contains(value)) continue;
    values.add(value);
  }
  return values;
}

Object? _singleOrList(List<Object?> values) {
  if (values.length == 1) return values.single;
  return values;
}

String _reviewContextHint({
  required List<Object?> chromeBrowsers,
  required List<Object?> operatingSystems,
  required List<Object?> operatingSystemVersions,
  required List<Object?> dartVersions,
  required List<Object?> headlessValues,
  required List<Object?> frameBudgetValues,
}) {
  final parts = <String>[];
  parts.add(_contextValue(chromeBrowsers, label: 'Browser'));
  final platform = [
    _contextValue(operatingSystems, label: 'OS'),
    if (operatingSystemVersions.isNotEmpty)
      _contextValue(operatingSystemVersions, label: 'OS version'),
  ].join(' ');
  parts.add(platform);
  if (dartVersions.isNotEmpty) {
    parts.add(_contextValue(dartVersions, label: 'Dart'));
  }
  if (headlessValues.isNotEmpty) {
    parts.add('headless=${_contextValue(headlessValues)}');
  }
  if (frameBudgetValues.isNotEmpty) {
    parts.add('frameBudgetMs=${_contextValue(frameBudgetValues)}');
  }
  parts.add('retained DOM product baseline');
  return parts.where((part) => part.trim().isNotEmpty).join(', ');
}

String _contextValue(List<Object?> values, {String? label}) {
  if (values.isEmpty) return '';
  final value = values.length == 1 ? values.single : 'mixed ${values.length}';
  return label == null ? '$value' : '$label $value';
}

Map<String, Object?> _thresholdReviewPlanDetails(
  String? path, {
  required String? expectedInputFingerprint,
}) {
  if (path == null || path.trim().isEmpty) {
    return const <String, Object?>{};
  }
  final file = File(path);
  if (!file.existsSync()) {
    return const <String, Object?>{'thresholdReviewPlanStatus': 'missing'};
  }
  final inputFingerprint = _thresholdReviewPlanInputFingerprint(file);
  final expected = expectedInputFingerprint?.trim();
  final status = inputFingerprint == null
      ? 'missing-input-fingerprint'
      : expected == null || expected.isEmpty
      ? 'present'
      : inputFingerprint == expected
      ? 'current'
      : 'stale';
  return <String, Object?>{
    'thresholdReviewPlanStatus': status,
    if (inputFingerprint != null)
      'thresholdReviewPlanInputFingerprint': inputFingerprint,
  };
}

String? _thresholdReviewPlanInputFingerprint(File file) {
  final pattern = RegExp(r'^\- Input fingerprint: `([^`]+)`$');
  for (final line in file.readAsLinesSync()) {
    final match = pattern.firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

List<String> _thresholdReviewPlanBlockers(Map<String, Object?> details) {
  final status = details['thresholdReviewPlanStatus'];
  if (status == null || status == 'current' || status == 'present') {
    return const <String>[];
  }
  return switch (status) {
    'missing' => const [
      'threshold review plan is missing; run planCommand before review',
    ],
    'stale' => const [
      'threshold review plan input fingerprint does not match current threshold policy fingerprint',
    ],
    'missing-input-fingerprint' => const [
      'threshold review plan is missing its input fingerprint',
    ],
    _ => ['threshold review plan status is $status'],
  };
}

Map<String, Object?> _manualTemplatePreparationAction({
  required String manualDir,
  required String targetPreset,
  required List<String> targetIds,
  required List<Map<String, Object?>> templateStatuses,
}) {
  final templatesDir = _joinPath(manualDir, 'templates');
  return <String, Object?>{
    'id': 'prepare-manual-evidence-templates',
    'kind': 'artifact-prep',
    'label': 'Prepare manual web evidence templates',
    'blockingChecks': const ['manualValidation'],
    'details': <String, Object?>{
      'templatesDirectory': templatesDir,
      if (targetIds.isEmpty) 'targetPreset': targetPreset,
      if (targetIds.isNotEmpty) 'targetIds': targetIds,
      'templateStatus': _aggregateManualTemplateStatus(templateStatuses),
      'targetTemplates': templateStatuses,
    },
    'commandTemplate': [
      'dart',
      'run',
      'tool/web_manual_validation.dart',
      '--input=$manualDir',
      '--write-templates=$templatesDir',
      ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
    ],
    'rootCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-manual-validation',
      '--input=$manualDir',
      '--write-templates=$templatesDir',
      ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
    ],
  };
}

List<Map<String, Object?>> _manualTemplateStatuses({
  required String manualDir,
  required List<String> targetIds,
}) {
  return [
    for (final targetId in targetIds)
      _manualTemplateStatus(manualDir: manualDir, targetId: targetId),
  ];
}

Map<String, Object?> _manualTemplateStatus({
  required String manualDir,
  required String targetId,
}) {
  final path = _joinPath(
    _joinPath(manualDir, 'templates'),
    '$targetId.template.json',
  );
  final file = File(path);
  if (!file.existsSync()) {
    return <String, Object?>{
      'targetId': targetId,
      'path': path,
      'status': 'missing',
      'blockers': const ['template file is missing'],
    };
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return <String, Object?>{
      'targetId': targetId,
      'path': path,
      'status': 'invalid',
      'fingerprint': _fileFingerprint(path),
      'blockers': const ['template JSON is invalid'],
    };
  }

  final blockers = <String>[];
  final expectedTarget = manualValidationTargetById(targetId);
  if (decoded is! Map) {
    blockers.add('template JSON root must be an object');
  } else {
    final json = decoded.cast<String, Object?>();
    if (expectedTarget != null) {
      blockers.addAll(manualValidationTemplateBlockers(expectedTarget, json));
    } else {
      if (json['kind'] != 'fleuryWebManualValidationEntry') {
        blockers.add('template kind must be fleuryWebManualValidationEntry');
      }
      if (json['targetId'] != targetId) {
        blockers.add('template targetId must be $targetId');
      }
      final targetMetadata = _map(json['target']);
      if (targetMetadata['id'] != targetId) {
        blockers.add('template target.id must be $targetId');
      }
      for (final key in ['label', 'phase', 'category', 'browser', 'platform']) {
        if ((targetMetadata[key]?.toString() ?? '').trim().isEmpty) {
          blockers.add('template target.$key must be non-empty');
        }
      }
      final reviewInstructions = _map(json['reviewInstructions']);
      if (reviewInstructions['manualValidationPage'] !=
          manualValidationEvidencePage) {
        blockers.add(
          'template reviewInstructions.manualValidationPage must be manual_validation.html',
        );
      }
      if ((reviewInstructions['readySignal']?.toString() ?? '')
          .trim()
          .isEmpty) {
        blockers.add(
          'template reviewInstructions.readySignal must be non-empty',
        );
      }
      if (_strings(reviewInstructions['manualPageSmokeCommand']).isEmpty) {
        blockers.add(
          'template reviewInstructions.manualPageSmokeCommand must be non-empty',
        );
      }
      final statusValues = _strings(reviewInstructions['statusValues']);
      for (final status in ['pass', 'fail', 'blocked', 'needsReview']) {
        if (!statusValues.contains(status)) {
          blockers.add(
            'template reviewInstructions.statusValues must include $status',
          );
        }
      }
      final environmentKeys = _strings(
        reviewInstructions['requiredEnvironmentKeys'],
      );
      for (final key in [
        'browser',
        'browserVersion',
        'platform',
        'fleuryWebPage',
      ]) {
        if (!environmentKeys.contains(key)) {
          blockers.add(
            'template reviewInstructions.requiredEnvironmentKeys must include $key',
          );
        }
      }
      if ((reviewInstructions['completionRule']?.toString() ?? '')
          .trim()
          .isEmpty) {
        blockers.add(
          'template reviewInstructions.completionRule must be non-empty',
        );
      }
      if ((json['status']?.toString() ?? '') != 'needsReview') {
        blockers.add('template status must be needsReview');
      }
      if ((json['capturedAt']?.toString() ?? '').trim().isNotEmpty) {
        blockers.add('template capturedAt must be blank');
      }
      if ((json['reviewedBy']?.toString() ?? '').trim().isNotEmpty) {
        blockers.add('template reviewedBy must be blank');
      }
    }
  }

  return <String, Object?>{
    'targetId': targetId,
    'path': path,
    'status': blockers.isEmpty ? 'current' : 'stale',
    'fingerprint': _fileFingerprint(path),
    if (blockers.isNotEmpty) 'blockers': blockers,
  };
}

String _aggregateManualTemplateStatus(
  List<Map<String, Object?>> templateStatuses,
) {
  if (templateStatuses.isEmpty) return 'unknown';
  if (templateStatuses.every((status) => status['status'] == 'current')) {
    return 'current';
  }
  if (templateStatuses.any((status) => status['status'] == 'missing')) {
    return 'missing';
  }
  if (templateStatuses.any((status) => status['status'] == 'invalid')) {
    return 'invalid';
  }
  return 'stale';
}

Map<String, Object?> _manualEvidenceAction({
  required String manualDir,
  required Map<String, Object?> target,
  required List<String> blockers,
  required String targetPreset,
  required List<String> targetIds,
  required List<String> dependsOn,
  required Map<String, Object?>? templateStatus,
}) {
  final targetId = target['id']?.toString() ?? '<target>';
  final templatePath = _joinPath(
    _joinPath(manualDir, 'templates'),
    '$targetId.template.json',
  );
  final evidenceDirectory = _joinPath(manualDir, 'evidence');
  final starterEvidencePath = _joinPath(
    evidenceDirectory,
    '$targetId.review.json',
  );
  final manualTarget = manualValidationTargetById(targetId);
  final templateIsCurrent = templateStatus?['status'] == 'current';
  final starterEvidenceFile = File(starterEvidencePath);
  final starterEvidenceExists = starterEvidenceFile.existsSync();
  return <String, Object?>{
    'id': 'collect-manual-evidence:$targetId',
    'kind': 'manual-validation',
    'label': 'Collect reviewed manual web evidence for $targetId',
    'blockingChecks': const ['manualValidation'],
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    'targetId': targetId,
    'status': target['status']?.toString() ?? 'unknown',
    'blockers': blockers,
    'details': <String, Object?>{
      if (target['requiredCheckCount'] != null)
        'requiredCheckCount': target['requiredCheckCount'],
      if (target['passedRequiredCheckCount'] != null)
        'passedRequiredCheckCount': target['passedRequiredCheckCount'],
      if (_strings(target['missingCheckIds']).isNotEmpty)
        'missingCheckIds': _strings(target['missingCheckIds']),
      'templatePath': templatePath,
      if (templateStatus != null) ...<String, Object?>{
        'templateStatus': templateStatus['status'],
        if (templateStatus['fingerprint'] != null)
          'templateFingerprint': templateStatus['fingerprint'],
        if (_strings(templateStatus['blockers']).isNotEmpty)
          'templateBlockers': _strings(templateStatus['blockers']),
      },
      'manualValidationPage': manualValidationHostedPage,
      'requiredEvidencePage': manualValidationEvidencePage,
      'manualPageCommandWorkingDirectory':
          manualValidationCommandWorkingDirectory,
      'manualValidationReadySignal': manualValidationReadySignal,
      'manualPageSmokeCommand': manualValidationPageSmokeCommand,
      'manualPageLocalUrl': manualValidationLocalUrl,
      'manualPageServeNote': manualValidationPageServeNote,
      'manualPageProvenanceAttributes': manualValidationProvenanceAttributes,
      if (manualTarget != null)
        'requiredPageSignals': [
          for (final signal in manualTarget.requiredPageSignals)
            signal.toJson(),
        ],
      'evidenceDirectory': evidenceDirectory,
      'starterEvidencePath': starterEvidencePath,
      'starterEvidenceStatus': starterEvidenceExists ? 'exists' : 'missing',
      if (starterEvidenceExists)
        'starterEvidenceFingerprint': _fileFingerprint(starterEvidencePath),
      'suggestedEvidencePath': _joinPath(
        evidenceDirectory,
        '$targetId-YYYY-MM-DD.json',
      ),
      'starterOverwritePolicy': 'fail-if-destination-exists',
      'provenanceCommandRunnable': false,
      'provenanceCommandPlaceholders': const [
        <String, Object?>{
          'name': 'reviewer',
          'argument': '--reviewed-by',
          'placeholder': '<reviewer>',
          'description': 'human reviewer name or handle',
        },
        <String, Object?>{
          'name': 'browserVersion',
          'argument': '--browser-version',
          'placeholder': '<Chrome version used for manual validation>',
          'description':
              'Chrome version from the browser used for the manual session',
        },
      ],
      'pageSignalCommandRunnable': false,
      'pageSignalCommandPlaceholders': const [
        <String, Object?>{
          'name': 'signalId',
          'argument': '--signal-id',
          'placeholder': '<required-page-signal-id>',
          'description': 'one required page signal ID from requiredPageSignals',
        },
        <String, Object?>{
          'name': 'observedValue',
          'argument': '--observed-value',
          'placeholder': '<expected-value>',
          'description':
              'the required page signal expectedValue observed in the page',
        },
        <String, Object?>{
          'name': 'reviewerObservation',
          'argument': '--signal-notes',
          'placeholder': '<reviewer observation>',
          'description': 'specific observation from the manual browser session',
        },
      ],
      'checkCommandRunnable': false,
      'checkCommandPlaceholders': const [
        <String, Object?>{
          'name': 'checkId',
          'argument': '--check-id',
          'placeholder': '<required-check-id>',
          'description': 'one required check ID from missingCheckIds',
        },
        <String, Object?>{
          'name': 'reviewerObservation',
          'argument': '--check-notes',
          'placeholder': '<reviewer observation>',
          'description': 'specific observation from the manual browser session',
        },
      ],
      'reviewerNextStep': starterEvidenceExists
          ? 'replace provenanceCommandTemplate placeholders during or after the manual session, use pageSignalCommandTemplate for each required page signal, use checkCommandTemplate for each observed required check, set top-level status to pass after all checks/page signals pass, then run auditCommand'
          : 'run starterCommand once, replace provenanceCommandTemplate placeholders during or after the manual session, use pageSignalCommandTemplate for each required page signal, use checkCommandTemplate for each observed required check, set top-level status to pass after all checks/page signals pass, then run auditCommand',
    },
    if (!templateIsCurrent)
      'commandTemplate': [
        'dart',
        'run',
        'tool/web_manual_validation.dart',
        '--write-template=$templatePath',
        '--template-target=$targetId',
      ],
    if (!templateIsCurrent)
      'rootCommandTemplate': [
        'dart',
        'run',
        'tool/fleury_dev.dart',
        'benchmark',
        'web-manual-validation',
        '--write-template=$templatePath',
        '--template-target=$targetId',
      ],
    'manualPageBuildCommand': manualValidationPageBuildCommand,
    'manualPageSmokeCommand': manualValidationPageSmokeCommand,
    'manualPageServeSetupCommand': manualValidationPageServeSetupCommand,
    'manualPageServeCommand': manualValidationPageServeCommand,
    if (!starterEvidenceExists)
      'starterCommand': [
        'dart',
        'run',
        'tool/web_manual_validation.dart',
        '--write-starter=$starterEvidencePath',
        '--starter-template=$templatePath',
        '--template-target=$targetId',
      ],
    if (!starterEvidenceExists)
      'rootStarterCommand': [
        'dart',
        'run',
        'tool/fleury_dev.dart',
        'benchmark',
        'web-manual-validation',
        '--write-starter=$starterEvidencePath',
        '--starter-template=$templatePath',
        '--template-target=$targetId',
      ],
    'provenanceCommandTemplate': [
      'dart',
      'run',
      'tool/web_manual_validation.dart',
      '--update-provenance=$starterEvidencePath',
      '--template-target=$targetId',
      '--reviewed-by=<reviewer>',
      '--captured-at=now',
      '--browser-version=<Chrome version used for manual validation>',
    ],
    'pageSignalCommandTemplate': [
      'dart',
      'run',
      'tool/web_manual_validation.dart',
      '--update-page-signal=$starterEvidencePath',
      '--template-target=$targetId',
      '--signal-id=<required-page-signal-id>',
      '--signal-status=pass',
      '--observed-value=<expected-value>',
      '--signal-notes=<reviewer observation>',
    ],
    'checkCommandTemplate': [
      'dart',
      'run',
      'tool/web_manual_validation.dart',
      '--update-check=$starterEvidencePath',
      '--template-target=$targetId',
      '--check-id=<required-check-id>',
      '--check-status=pass',
      '--check-notes=<reviewer observation>',
    ],
    'rootProvenanceCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-manual-validation',
      '--update-provenance=$starterEvidencePath',
      '--template-target=$targetId',
      '--reviewed-by=<reviewer>',
      '--captured-at=now',
      '--browser-version=<Chrome version used for manual validation>',
    ],
    'rootPageSignalCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-manual-validation',
      '--update-page-signal=$starterEvidencePath',
      '--template-target=$targetId',
      '--signal-id=<required-page-signal-id>',
      '--signal-status=pass',
      '--observed-value=<expected-value>',
      '--signal-notes=<reviewer observation>',
    ],
    'rootCheckCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-manual-validation',
      '--update-check=$starterEvidencePath',
      '--template-target=$targetId',
      '--check-id=<required-check-id>',
      '--check-status=pass',
      '--check-notes=<reviewer observation>',
    ],
    'auditCommand': [
      'dart',
      'run',
      'tool/web_manual_validation.dart',
      '--input=$manualDir',
      ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
      '--json-output=${_joinPath(manualDir, 'manual-validation-audit.json')}',
      '--strict',
    ],
    'rootAuditCommand': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-manual-validation',
      '--input=$manualDir',
      ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
      '--json-output=${_joinPath(manualDir, 'manual-validation-audit.json')}',
      '--strict',
    ],
  };
}

Map<String, Object?> _regenerateBundleAction({
  required String captureDir,
  required String manualDir,
  required String outputDir,
  required String? thresholdPolicyPath,
  required String? thresholdReviewPath,
  required bool requireComparableRunEnvironment,
  required bool requireScenarioThresholds,
  required bool requireThresholdReviewSummary,
  required String targetPreset,
  required List<String> targetIds,
  required List<String> dependsOn,
  required String? completionAuditPath,
}) {
  final bundleJsonPath = _joinPath(outputDir, 'web-readiness-bundle.json');
  final readinessJsonPath = _joinPath(outputDir, 'web-readiness.json');
  return <String, Object?>{
    'id': 'regenerate-readiness-bundle',
    'kind': 'artifact-refresh',
    'label': 'Regenerate the readiness bundle from reviewed evidence',
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    'details': <String, Object?>{
      'captureDir': captureDir,
      'manualDir': manualDir,
      'outputDir': outputDir,
      'bundleJsonPath': bundleJsonPath,
      'readinessJsonPath': readinessJsonPath,
      if (thresholdPolicyPath != null)
        'thresholdPolicyPath': thresholdPolicyPath,
      if (thresholdReviewPath != null)
        'thresholdReviewPath': thresholdReviewPath,
      'maxFallbackCells': 0,
      if (targetIds.isEmpty) 'targetPreset': targetPreset,
      if (targetIds.isNotEmpty) 'targetIds': targetIds,
      if (completionAuditPath != null)
        'completionAuditPath': completionAuditPath,
      'writeDefaultPreflights': true,
      'strictRequired': true,
      'jsonOutput': true,
      'reviewerNextStep':
          'run after human-review and manual-validation dependencies pass',
    },
    'commandTemplate': [
      'dart',
      'run',
      'tool/web_readiness_bundle.dart',
      '--captures=$captureDir',
      '--manual=$manualDir',
      '--output-dir=$outputDir',
      if (thresholdPolicyPath != null) '--thresholds=$thresholdPolicyPath',
      if (thresholdReviewPath != null)
        '--threshold-review=$thresholdReviewPath',
      '--max-fallback-cells=0',
      ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
      '--write-default-preflights',
      if (completionAuditPath != null)
        '--completion-audit=$completionAuditPath',
      if (!requireComparableRunEnvironment)
        '--no-require-comparable-environment',
      if (!requireScenarioThresholds) '--no-require-scenario-thresholds',
      if (!requireThresholdReviewSummary)
        '--no-require-threshold-review-summary',
      '--strict',
      '--json',
    ],
    'rootCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-readiness-bundle',
      '--captures=$captureDir',
      '--manual=$manualDir',
      '--output-dir=$outputDir',
      if (thresholdPolicyPath != null) '--thresholds=$thresholdPolicyPath',
      if (thresholdReviewPath != null)
        '--threshold-review=$thresholdReviewPath',
      '--max-fallback-cells=0',
      ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
      '--write-default-preflights',
      if (completionAuditPath != null)
        '--completion-audit=$completionAuditPath',
      if (!requireComparableRunEnvironment)
        '--no-require-comparable-environment',
      if (!requireScenarioThresholds) '--no-require-scenario-thresholds',
      if (!requireThresholdReviewSummary)
        '--no-require-threshold-review-summary',
      '--strict',
      '--json',
    ],
  };
}

List<String> _manualTargetArgs({
  required String targetPreset,
  required List<String> targetIds,
}) {
  if (targetIds.isEmpty) return ['--target-preset=$targetPreset'];
  return [for (final targetId in targetIds) '--target=$targetId'];
}

Map<String, Object?> _verifyBundleAction({
  required String bundleJsonPath,
  required List<String> dependsOn,
}) {
  return <String, Object?>{
    'id': 'verify-readiness-bundle',
    'kind': 'artifact-verification',
    'label': 'Verify generated and source-input bundle fingerprints',
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    'details': <String, Object?>{
      'bundleJsonPath': bundleJsonPath,
      'strictRequired': true,
      'jsonOutput': true,
      'verificationScope': const <String>[
        'generated-artifact-fingerprints',
        'source-input-fingerprints',
        'expected-source-input-path-coverage',
        'command-working-directory-metadata',
        'manual-evidence-latest-entry-fingerprints',
        'threshold-review-release-action',
        'manual-evidence-release-actions',
        'generated-default-preflight-diagnostics',
        'release-action-command-templates',
      ],
      'reviewerNextStep':
          'run after regenerate-readiness-bundle and require strictPass true',
    },
    'commandTemplate': [
      'dart',
      'run',
      'tool/web_readiness_bundle.dart',
      '--verify=$bundleJsonPath',
      '--strict',
      '--json',
    ],
    'rootCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-readiness-bundle',
      '--verify=$bundleJsonPath',
      '--strict',
      '--json',
    ],
  };
}

Map<String, Object?> _automatedWebHostTestsAction({
  required String automatedValidationJsonPath,
  required List<String> dependsOn,
}) {
  return <String, Object?>{
    'id': 'run-automated-web-host-tests',
    'kind': 'automated-validation',
    'label': 'Run retained DOM automated host tests',
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    'details': <String, Object?>{
      'sourceInputGroup': 'webAutomatedTestFiles',
      'automatedValidationJsonPath': automatedValidationJsonPath,
      'browserTestFileCount': webAutomatedBrowserTestPaths.length,
      'vmTestFileCount': webAutomatedVmTestPaths.length,
      'fixtureFileCount': webAutomatedFixturePaths.length,
      'browserTestFiles': webAutomatedBrowserTestPaths,
      'vmTestFiles': webAutomatedVmTestPaths,
      'fixtureFiles': webAutomatedFixturePaths,
      'requiredPass': true,
      'verificationScope': const <String>[
        'retained-dom-host-assembly',
        'browser-frame-flush-scheduling',
        'browser-input-trace-replay',
        'semantic-dom-projection',
        'clipboard-and-focus-adapters',
        'public-api-boundary',
      ],
      'reviewerNextStep':
          'run after strict bundle verification and require the generated JSON artifact to strict-pass before changing web defaults',
    },
    'commandTemplate': [
      'dart',
      'run',
      'tool/web_automated_validation.dart',
      '--json-output=$automatedValidationJsonPath',
      '--strict',
      '--json',
    ],
    'rootCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-automated-validation',
      '--json-output=$automatedValidationJsonPath',
      '--strict',
      '--json',
    ],
    'browserTestCommand': webAutomatedBrowserTestCommand(),
    'vmTestCommand': webAutomatedVmTestCommand(),
  };
}

Map<String, Object?> _defaultPreflightAction({
  required String targetId,
  required String readinessJsonPath,
  required String bundleJsonPath,
  required String automatedValidationJsonPath,
  required bool previewStrictPass,
  required List<String> dependsOn,
}) {
  return <String, Object?>{
    'id': 'run-default-preflight:$targetId',
    'kind': 'release-gate',
    'label': 'Run bundle-bound default preflight for $targetId',
    'dependsOn': dependsOn,
    'targetId': targetId,
    'details': <String, Object?>{
      'targetId': targetId,
      'readinessJsonPath': readinessJsonPath,
      'bundleJsonPath': bundleJsonPath,
      'automatedValidationJsonPath': automatedValidationJsonPath,
      'strictRequired': true,
      'jsonOutput': true,
      'requiresBundleBinding': true,
      'generatedPreviewStrictPass': previewStrictPass,
      'generatedPreviewBundleBound': false,
      'generatedPreviewDiagnosticOnly': true,
      'verificationScope': const <String>[
        'generated-artifact-fingerprints',
        'source-input-fingerprints',
        'expected-source-input-path-coverage',
        'command-working-directory-metadata',
        'readiness-json-path-binding',
        'automated-validation-artifact',
      ],
      'reviewerNextStep':
          'run after bundle verification and require strictPass true before changing this default',
    },
    'commandTemplate': [
      'dart',
      'run',
      'tool/web_default_preflight.dart',
      '--readiness=$readinessJsonPath',
      '--bundle=$bundleJsonPath',
      '--automated-validation=$automatedValidationJsonPath',
      '--target=$targetId',
      '--strict',
      '--json',
    ],
    'rootCommandTemplate': [
      'dart',
      'run',
      'tool/fleury_dev.dart',
      'benchmark',
      'web-default-preflight',
      '--readiness=$readinessJsonPath',
      '--bundle=$bundleJsonPath',
      '--automated-validation=$automatedValidationJsonPath',
      '--target=$targetId',
      '--strict',
      '--json',
    ],
  };
}

Map<String, Object?> _buildCompletionAudit({
  required Map<String, Object?> bundle,
  required Map<String, Object?> verification,
  required String generatedAt,
}) {
  final artifacts = _map(bundle['artifacts']);
  final readiness = _map(bundle['readiness']);
  final manualAudit = _readJsonMap(_string(artifacts['manualAudit']));
  final semanticAudit = _readJsonMap(_string(artifacts['semanticAudit']));
  final actions = _maps(bundle['remainingReleaseActions']);
  final automatedAction = _releaseAction(
    actions,
    'run-automated-web-host-tests',
  );
  final automatedValidationPath = _string(
    _map(automatedAction?['details'])['automatedValidationJsonPath'],
  );
  final automatedValidation = _readJsonMap(automatedValidationPath);
  final makeDomDefaultPreflight = _completionDefaultPreflightSummary(
    artifacts,
    'make-dom-default',
  );
  final retireTemporaryPathsPreflight = _completionDefaultPreflightSummary(
    artifacts,
    'retire-temporary-paths',
  );

  final readinessStrictPass = readiness['strictPass'] == true;
  final verificationStrictPass = verification['strictPass'] == true;
  final automatedStrictPass = automatedValidation['strictPass'] == true;
  final releaseEvidenceReady =
      readinessStrictPass && verificationStrictPass && automatedStrictPass;
  final defaultFlipReady = makeDomDefaultPreflight['ready'] == true;
  final temporaryPathRetirementReady =
      retireTemporaryPathsPreflight['ready'] == true;
  final releaseReady =
      releaseEvidenceReady && defaultFlipReady && temporaryPathRetirementReady;
  final architectureReviewReady =
      verificationStrictPass && semanticAudit['strictPass'] == true;
  final blockers = _completionBlockers(
    readiness: readiness,
    verification: verification,
    automatedValidation: automatedValidation,
    releaseEvidenceReady: releaseEvidenceReady,
    defaultFlipReady: defaultFlipReady,
    temporaryPathRetirementReady: temporaryPathRetirementReady,
  );
  final releaseActionStatuses = [
    for (final action in actions)
      _completionReleaseActionStatus(
        action,
        readiness: readiness,
        verification: verification,
        automatedValidation: automatedValidation,
      ),
  ];

  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebRfcCompletionAudit',
    'generatedAt': generatedAt,
    'worktree': 'codex/fleury-web-phase1',
    'baselineDirectory': _string(_map(bundle['input'])['captureDir']),
    'readinessBundlePath': _string(artifacts['bundleJson']),
    'overallStatus': releaseReady
        ? 'release-ready'
        : releaseEvidenceReady
        ? 'release-evidence-ready-default-actions-pending'
        : architectureReviewReady
        ? 'implementation-review-ready-release-blocked'
        : 'implementation-review-needs-attention',
    'architectureReviewReady': architectureReviewReady,
    'releaseEvidenceReady': releaseEvidenceReady,
    'releaseReady': releaseReady,
    'defaultFlipReady': defaultFlipReady,
    'temporaryPathRetirementReady': temporaryPathRetirementReady,
    'goalCompletionClaim': 'not-complete',
    'completionScopes': _completionScopes(
      architectureReviewReady: architectureReviewReady,
      releaseEvidenceReady: releaseEvidenceReady,
      releaseReady: releaseReady,
      defaultFlipReady: defaultFlipReady,
      temporaryPathRetirementReady: temporaryPathRetirementReady,
      actionStatuses: releaseActionStatuses,
    ),
    'completionBlockers': blockers,
    'phaseStatus': _completionPhaseStatus(
      readiness: readiness,
      manualAudit: manualAudit,
      input: _map(bundle['input']),
      artifacts: artifacts,
      actions: actions,
      releaseReady: releaseReady,
      releaseEvidenceReady: releaseEvidenceReady,
    ),
    'automatedEvidence': <String, Object?>{
      'strictBundleVerification': <String, Object?>{
        'strictPass': verificationStrictPass,
        'checkedArtifactCount': verification['checkedArtifactCount'],
        'checkedSourceInputCount': verification['checkedSourceInputCount'],
        'checkedManifestFieldCount': verification['checkedManifestFieldCount'],
        'manifestMismatchCount': verification['manifestMismatchCount'],
        'missingManifestFieldCount': verification['missingManifestFieldCount'],
      },
      'semanticCoverage': <String, Object?>{
        'strictPass': semanticAudit['strictPass'] == true,
        'scenarioCount': semanticAudit['scenarioCount'],
        'captureCount': semanticAudit['captureCount'],
        'frameCount': semanticAudit['frameCount'],
        'fallbackCellCount': semanticAudit['fallbackCellCount'],
        'fallbackNodeCount': semanticAudit['fallbackNodeCount'],
      },
      'automatedWebHostValidation': <String, Object?>{
        'strictPass': automatedStrictPass,
        'status': automatedValidation.isEmpty
            ? 'missing'
            : automatedStrictPass
            ? 'pass'
            : 'fail',
        if (automatedValidationPath != null) 'path': automatedValidationPath,
        'checks': [
          for (final check in _maps(automatedValidation['checks']))
            <String, Object?>{
              'id': check['id'],
              'strictPass': check['strictPass'] == true,
              'blockerCount': _strings(check['blockers']).length,
            },
        ],
      },
    },
    'releaseGateEvidence': <String, Object?>{
      'releaseEvidenceReady': releaseEvidenceReady,
      'defaultPreflights': <String, Object?>{
        'make-dom-default': makeDomDefaultPreflight,
        'retire-temporary-paths': retireTemporaryPathsPreflight,
      },
    },
    'manualEvidence': _manualEvidenceCompletionSummary(manualAudit),
    'releaseActions': [for (final action in releaseActionStatuses) action],
  };
}

Map<String, Object?> _completionScopes({
  required bool architectureReviewReady,
  required bool releaseEvidenceReady,
  required bool releaseReady,
  required bool defaultFlipReady,
  required bool temporaryPathRetirementReady,
  required List<Map<String, Object?>> actionStatuses,
}) {
  return <String, Object?>{
    'architectureReview': <String, Object?>{
      'ready': architectureReviewReady,
      'status': architectureReviewReady
          ? 'ready-for-re-review'
          : 'needs-attention',
      'claim': architectureReviewReady
          ? 'implementation-review-ready'
          : 'implementation-review-not-ready',
      'releaseScope': false,
      'includedEvidence': const <String>[
        'shared-runtime-and-frame-loop',
        'explicit-retained-dom-host',
        'retained-semantics-defaults',
        'browser-input-and-clipboard-harness',
        'benchmark-readiness-and-release-gate-tooling',
        'readiness-bundle-source-and-artifact-verification',
      ],
      'deferredReleaseGateIds': _deferredReleaseGateIds(
        releaseEvidenceReady: releaseEvidenceReady,
        defaultFlipReady: defaultFlipReady,
        temporaryPathRetirementReady: temporaryPathRetirementReady,
      ),
    },
    'releaseEvidence': <String, Object?>{
      'ready': releaseEvidenceReady,
      'status': releaseEvidenceReady ? 'ready' : 'blocked',
      'requires': const <String>[
        'reviewed-threshold-policy',
        'scoped-manual-evidence',
        'strict-phase-6-readiness',
        'strict-readiness-bundle-verification',
        'strict-retained-host-automated-validation',
      ],
      'remainingReleaseActionIds': releaseEvidenceReady
          ? const <String>[]
          : _remainingReleaseActionIds(
              actionStatuses,
              excludeDefaultPreflights: true,
            ),
      'satisfiedCurrentEvidenceActionIds': _satisfiedReleaseActionIds(
        actionStatuses,
        excludeDefaultPreflights: true,
      ),
    },
    'releaseDefault': <String, Object?>{
      'ready': releaseReady,
      'status': releaseReady ? 'ready' : 'blocked',
      'requires': const <String>[
        'release-evidence',
        'bundle-bound-make-dom-default-preflight',
        'bundle-bound-retire-temporary-paths-preflight',
      ],
      'remainingGateIds': releaseReady
          ? const <String>[]
          : <String>[
              if (!releaseEvidenceReady) 'release-evidence',
              if (!defaultFlipReady) 'run-default-preflight:make-dom-default',
              if (!temporaryPathRetirementReady)
                'run-default-preflight:retire-temporary-paths',
            ],
      'remainingReleaseActionIds': releaseReady
          ? const <String>[]
          : _remainingReleaseActionIds(
              actionStatuses,
              defaultPreflightOnly: true,
            ),
      'satisfiedCurrentEvidenceActionIds': _satisfiedReleaseActionIds(
        actionStatuses,
        defaultPreflightOnly: true,
      ),
    },
  };
}

List<String> _deferredReleaseGateIds({
  required bool releaseEvidenceReady,
  required bool defaultFlipReady,
  required bool temporaryPathRetirementReady,
}) {
  return <String>[
    if (!releaseEvidenceReady) 'release-evidence',
    if (!defaultFlipReady) 'make-dom-default',
    if (!temporaryPathRetirementReady) 'retire-temporary-paths',
  ];
}

List<String> _remainingReleaseActionIds(
  List<Map<String, Object?>> actionStatuses, {
  bool defaultPreflightOnly = false,
  bool excludeDefaultPreflights = false,
}) {
  final ids = <String>[];
  for (final action in actionStatuses) {
    final id = action['id']?.toString().trim();
    if (id == null || id.isEmpty) continue;
    final isDefaultPreflight = id.startsWith('run-default-preflight:');
    if (defaultPreflightOnly && !isDefaultPreflight) continue;
    if (excludeDefaultPreflights && isDefaultPreflight) continue;
    if (_releaseActionStatusIsSatisfied(action['status'])) continue;
    ids.add(id);
  }
  return ids;
}

List<String> _satisfiedReleaseActionIds(
  List<Map<String, Object?>> actionStatuses, {
  bool defaultPreflightOnly = false,
  bool excludeDefaultPreflights = false,
}) {
  final ids = <String>[];
  for (final action in actionStatuses) {
    final id = action['id']?.toString().trim();
    if (id == null || id.isEmpty) continue;
    final isDefaultPreflight = id.startsWith('run-default-preflight:');
    if (defaultPreflightOnly && !isDefaultPreflight) continue;
    if (excludeDefaultPreflights && isDefaultPreflight) continue;
    if (!_releaseActionStatusIsSatisfied(action['status'])) continue;
    ids.add(id);
  }
  return ids;
}

bool _releaseActionStatusIsSatisfied(Object? status) {
  return switch (status?.toString()) {
    'satisfied' || 'not-needed' || 'passes-current-candidate-packet' => true,
    _ => false,
  };
}

List<String> _completionBlockers({
  required Map<String, Object?> readiness,
  required Map<String, Object?> verification,
  required Map<String, Object?> automatedValidation,
  required bool releaseEvidenceReady,
  required bool defaultFlipReady,
  required bool temporaryPathRetirementReady,
}) {
  final blockers = <String>[];
  final frameCheck = _readinessCheck(readiness, 'frameScoreboard');
  if (frameCheck != null && frameCheck['strictPass'] != true) {
    blockers.add(
      'candidate thresholds need human review and promotion to thresholds.json plus threshold-review.json',
    );
  }
  final manualCheck = _readinessCheck(readiness, 'manualValidation');
  if (manualCheck != null && manualCheck['strictPass'] != true) {
    final details = _map(manualCheck['details']);
    final needsReviewTargets = _strings(details['needsReviewTargets']);
    if (needsReviewTargets.contains('chrome-ime-macos')) {
      blockers.add(
        'chrome-ime-macos manual evidence must be collected and reviewed with real Chrome/macOS IME',
      );
    }
  }
  if (verification['strictPass'] != true) {
    blockers.add('strict readiness bundle verification must pass');
  }
  if (automatedValidation['strictPass'] != true) {
    blockers.add('automated retained-host validation artifact must pass');
  }
  if (readiness['strictPass'] != true) {
    blockers.add(
      'strict Phase 6 readiness must pass after reviewed threshold policy and scoped evidence',
    );
  }
  if (!releaseEvidenceReady) {
    blockers.add(
      'release evidence prerequisites must pass before final default/retirement actions',
    );
  }
  if (!defaultFlipReady) {
    blockers.add(
      'bundle-bound make-dom-default preflight must pass before changing the package default',
    );
  }
  if (!temporaryPathRetirementReady) {
    blockers.add(
      'bundle-bound retire-temporary-paths preflight must pass before removing temporary/xterm-compatible paths',
    );
  }
  return blockers;
}

Map<String, Object?> _completionDefaultPreflightSummary(
  Map<String, Object?> artifacts,
  String targetId,
) {
  final defaultPreflights = _map(artifacts['defaultPreflights']);
  final targetArtifacts = _map(defaultPreflights[targetId]);
  final path = _string(targetArtifacts['json']);
  final preflight = _readJsonMap(path);
  final ready =
      preflight['target'] == targetId &&
      preflight['strictPass'] == true &&
      preflight['bundleBound'] == true &&
      preflight['bundleRequired'] == true &&
      preflight['automatedValidationBound'] == true &&
      preflight['automatedValidationRequired'] == true &&
      preflight['diagnosticOnly'] != true;
  return <String, Object?>{
    'targetId': targetId,
    'ready': ready,
    'status': preflight.isEmpty
        ? 'missing'
        : ready
        ? 'pass'
        : preflight['diagnosticOnly'] == true
        ? 'diagnostic-only'
        : 'fail',
    if (path != null) 'path': path,
    if (preflight.isNotEmpty) ...<String, Object?>{
      'strictPass': preflight['strictPass'] == true,
      'bundleBound': preflight['bundleBound'] == true,
      'bundleRequired': preflight['bundleRequired'] == true,
      'automatedValidationBound': preflight['automatedValidationBound'] == true,
      'automatedValidationRequired':
          preflight['automatedValidationRequired'] == true,
      'diagnosticOnly': preflight['diagnosticOnly'] == true,
      'finalGateRequiresBundle': preflight['finalGateRequiresBundle'] == true,
      'finalGateRequiresAutomatedValidation':
          preflight['finalGateRequiresAutomatedValidation'] == true,
    },
  };
}

List<Map<String, Object?>> _completionPhaseStatus({
  required Map<String, Object?> readiness,
  required Map<String, Object?> manualAudit,
  required Map<String, Object?> input,
  required Map<String, Object?> artifacts,
  required List<Map<String, Object?>> actions,
  required bool releaseReady,
  required bool releaseEvidenceReady,
}) {
  final frameReady =
      _readinessCheck(readiness, 'frameScoreboard')?['strictPass'] == true;
  final thresholdAction = _releaseAction(actions, 'review-threshold-policy');
  final thresholdActionDetails = _map(thresholdAction?['details']);
  final defaultPreflights = _map(artifacts['defaultPreflights']);
  final manualTargets = _manualEvidenceCompletionTargets(manualAudit);
  final imeRequired = manualTargets.any(
    (target) => target['id'] == 'chrome-ime-macos',
  );
  final imeReady = manualTargets.any(
    (target) =>
        target['id'] == 'chrome-ime-macos' && target['strictPass'] == true,
  );
  return <Map<String, Object?>>[
    <String, Object?>{
      'phase': 'Phase 1',
      'name': 'Shared Runtime and Damage Handoff',
      'status': 'landed',
      'releaseBlocking': false,
      'evidence': const <String>[
        'packages/fleury/lib/fleury_host.dart',
        'packages/fleury/lib/src/runtime/tui_runtime.dart',
        'packages/fleury/lib/src/runtime/tui_frame_loop.dart',
        'packages/fleury/test/runtime/tui_runtime_test.dart',
        'packages/fleury/test/runtime/tui_frame_loop_test.dart',
      ],
    },
    <String, Object?>{
      'phase': 'Phase 2',
      'name': 'Host Skeleton and Visual DOM',
      'status': 'landed',
      'releaseBlocking': false,
      'evidence': const <String>[
        'packages/fleury_web/lib/src/run_tui_surface.dart',
        'packages/fleury_web/lib/src/run_tui_web_dom.dart',
        'packages/fleury_web/lib/src/frame_presentation.dart',
        'packages/fleury_web/lib/src/dom_grid/dom_grid_surface.dart',
        'packages/fleury_web/test/run_tui_surface_test.dart',
        'packages/fleury_web/test/run_tui_web_dom_test.dart',
      ],
    },
    <String, Object?>{
      'phase': 'Phase 3',
      'name': 'Input, Resize, Clipboard, IME',
      'status': imeReady
          ? 'manual-ime-evidence-reviewed'
          : imeRequired
          ? 'automated-path-landed-manual-ime-blocked'
          : 'automated-path-landed-ime-roadmap-follow-up',
      'releaseBlocking': imeRequired && !imeReady,
      'evidence': const <String>[
        'packages/fleury_web/lib/src/input/dom_input_source.dart',
        'packages/fleury_web/lib/src/clipboard/web_clipboard.dart',
        'packages/fleury_web/test/dom_input_trace_fixture_test.dart',
        'packages/fleury_web/test/web_clipboard_test.dart',
      ],
      if (imeRequired)
        'manualEvidence':
            'profiling/web/manual/evidence/chrome-ime-macos.review.json',
      if (imeRequired && !imeReady)
        'remainingGate': 'reviewed pass evidence from real Chrome/macOS IME',
      if (!imeRequired)
        'followUpGate':
            'reviewed pass evidence from real Chrome/macOS IME before claiming IME support',
    },
    <String, Object?>{
      'phase': 'Phase 4',
      'name': 'Retained Semantics, Focus, Accessibility',
      'status': 'automated-path-landed-voiceover-follow-up',
      'releaseBlocking': false,
      'evidence': const <String>[
        'packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart',
        'packages/fleury_web/lib/src/semantics/semantic_coverage.dart',
        'packages/fleury_web/lib/src/focus/web_focus_coordinator.dart',
        'packages/fleury_web/test/semantic_dom_presenter_test.dart',
      ],
      'followUpGate':
          'reviewed screen-reader evidence from real Chrome/macOS VoiceOver',
    },
    <String, Object?>{
      'phase': 'Phase 5',
      'name': 'Benchmark Gate',
      'status': frameReady
          ? 'reviewed-thresholds-ready'
          : 'instrumentation-and-candidate-baseline-landed-threshold-review-blocked',
      'releaseBlocking': !frameReady,
      'evidence': <String>[
        if (_string(artifacts['scoreboard']) case final path?) path,
        if (_string(input['thresholdPolicyPath']) case final path?) path,
        if (_string(thresholdActionDetails['thresholdReviewPlanPath'])
            case final path?)
          path,
      ],
      if (!frameReady)
        'remainingGate':
            'human review and promotion of per-scenario thresholds',
    },
    <String, Object?>{
      'phase': 'Phase 6',
      'name': 'Harden and Retire Temporary Paths',
      'status': releaseReady
          ? 'release-ready'
          : releaseEvidenceReady
          ? 'release-evidence-ready-default-actions-pending'
          : 'guards-landed-default-flip-and-retirement-blocked',
      'releaseBlocking': !releaseReady,
      'evidence': <String>[
        'packages/fleury_web/tool/web_readiness.dart',
        'packages/fleury_web/tool/web_readiness_bundle.dart',
        'packages/fleury_web/tool/web_automated_validation.dart',
        'packages/fleury_web/tool/web_default_preflight.dart',
        if (_string(artifacts['readinessJson']) case final path?) path,
        if (_string(_map(defaultPreflights['make-dom-default'])['json'])
            case final path?)
          path,
        if (_string(_map(defaultPreflights['retire-temporary-paths'])['json'])
            case final path?)
          path,
      ],
      if (!releaseReady)
        'remainingGate':
            'strict readiness and bundle-bound default/retirement preflights must pass',
    },
  ];
}

Map<String, Object?> _manualEvidenceCompletionSummary(
  Map<String, Object?> manualAudit,
) {
  return <String, Object?>{
    'strictPass': manualAudit['strictPass'] == true,
    'targetCount': manualAudit['targetCount'],
    'passedTargetCount': manualAudit['passedTargetCount'],
    'invalidEntryCount': manualAudit['invalidEntryCount'],
    'needsReviewTargets': _strings(manualAudit['needsReviewTargets']),
    'targets': _manualEvidenceCompletionTargets(manualAudit),
  };
}

List<Map<String, Object?>> _manualEvidenceCompletionTargets(
  Map<String, Object?> manualAudit,
) {
  return [
    for (final target in _maps(manualAudit['targets']))
      <String, Object?>{
        'id': target['id'],
        'status': target['status'],
        'strictPass': target['strictPass'] == true,
        'passedRequiredCheckCount': target['passedRequiredCheckCount'],
        'requiredCheckCount': target['requiredCheckCount'],
        if (target['latestEntryFile'] != null)
          'latestEntryFile': target['latestEntryFile'],
        if (target['latestEntryFingerprint'] != null)
          'latestEntryFingerprint': target['latestEntryFingerprint'],
      },
  ];
}

Map<String, Object?> _completionReleaseActionStatus(
  Map<String, Object?> action, {
  required Map<String, Object?> readiness,
  required Map<String, Object?> verification,
  required Map<String, Object?> automatedValidation,
}) {
  final id = _string(action['id']) ?? '<unknown>';
  final details = _map(action['details']);
  final status = switch (id) {
    'review-threshold-policy' =>
      _readinessCheck(readiness, 'frameScoreboard')?['strictPass'] == true
          ? 'satisfied'
          : 'required',
    String value when value.startsWith('collect-manual-evidence:') =>
      _readinessCheck(readiness, 'manualValidation')?['strictPass'] == true
          ? 'satisfied'
          : 'required',
    'regenerate-readiness-bundle' =>
      readiness['strictPass'] == true ? 'not-needed' : 'waiting-on-human-gates',
    'verify-readiness-bundle' =>
      verification['strictPass'] == true
          ? 'passes-current-candidate-packet'
          : 'failing-current-candidate-packet',
    'run-automated-web-host-tests' =>
      automatedValidation['strictPass'] == true
          ? 'passes-current-candidate-packet'
          : 'required',
    'run-default-preflight:make-dom-default' =>
      readiness['strictPass'] == true
          ? 'pending-final-bundle-bound-preflight'
          : 'waiting-on-strict-readiness',
    'run-default-preflight:retire-temporary-paths' =>
      readiness['strictPass'] == true
          ? 'pending-final-bundle-bound-preflight'
          : 'waiting-on-strict-readiness',
    _ => 'present',
  };
  return <String, Object?>{
    'id': id,
    'status': status,
    if (action['kind'] != null) 'kind': action['kind'],
    if (details['thresholdReviewPlanPath'] != null)
      'path': details['thresholdReviewPlanPath'],
    if (details['starterEvidencePath'] != null)
      'path': details['starterEvidencePath'],
  };
}

Map<String, Object?>? _releaseAction(
  List<Map<String, Object?>> actions,
  String id,
) {
  for (final action in actions) {
    if (action['id'] == id) return action;
  }
  return null;
}

Map<String, Object?> _readJsonMap(String? path) {
  if (path == null || path.trim().isEmpty) return const <String, Object?>{};
  final file = File(path);
  if (!file.existsSync()) return const <String, Object?>{};
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
  } catch (_) {
    return const <String, Object?>{};
  }
  return const <String, Object?>{};
}

Map<String, Object?>? _readinessCheck(
  Map<String, Object?> readiness,
  String id,
) {
  for (final check in _maps(readiness['checks'])) {
    if (check['id'] == id) return check;
  }
  return null;
}

String? _reviewedThresholdOutputPath(String? thresholdPolicyPath) {
  if (thresholdPolicyPath == null || thresholdPolicyPath.trim().isEmpty) {
    return null;
  }
  const suffix = '.candidate.json';
  if (thresholdPolicyPath.endsWith(suffix)) {
    return '${thresholdPolicyPath.substring(0, thresholdPolicyPath.length - suffix.length)}.json';
  }
  return _joinPath(File(thresholdPolicyPath).parent.path, 'thresholds.json');
}

String _joinPath(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
  return '$parent${Platform.pathSeparator}$child';
}

Map<String, Object?> _verifyBundle(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Readiness bundle not found: $path');
    exit(2);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('Readiness bundle is not valid JSON: ${error.message}');
    exit(2);
  }
  if (decoded is! Map) {
    stderr.writeln('Readiness bundle must be a JSON object.');
    exit(2);
  }
  final bundle = decoded.cast<String, Object?>();
  if (bundle['kind'] != 'fleuryWebReadinessBundle') {
    stderr.writeln(
      'Readiness bundle kind is `${bundle['kind']}`, expected `fleuryWebReadinessBundle`.',
    );
    exit(2);
  }
  final artifacts = bundle['artifacts'];
  if (artifacts is! Map) {
    stderr.writeln('Readiness bundle artifacts must be a JSON object.');
    exit(2);
  }
  final fingerprints = bundle['artifactFingerprints'];
  if (fingerprints is! Map) {
    return <String, Object?>{
      'schemaVersion': 1,
      'kind': 'fleuryWebReadinessBundleVerification',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'bundlePath': file.absolute.path,
      'strictPass': false,
      'checkedArtifactCount': 0,
      'mismatchCount': 0,
      'missingArtifactCount': 0,
      'missingFingerprintCount': 1,
      'missingFingerprints': ['artifactFingerprints'],
      'checkedSourceInputCount': 0,
      'sourceMismatchCount': 0,
      'missingSourceInputCount': 0,
      'missingSourceFingerprintCount': 0,
      'checkedMetadataCount': 0,
      'metadataMismatchCount': 0,
      'missingMetadataCount': 0,
      'checkedManifestFieldCount': 0,
      'manifestMismatchCount': 0,
      'missingManifestFieldCount': 0,
    };
  }
  final state = ReadinessBundleVerificationState();
  verifyReadinessBundleArtifacts(
    artifacts: artifacts.cast<String, Object?>(),
    fingerprints: fingerprints.cast<String, Object?>(),
    state: state,
  );
  final sourceInputFingerprints = bundle['sourceInputFingerprints'];
  if (sourceInputFingerprints is Map) {
    verifyReadinessBundleSourceInputFingerprints(
      sourceInputFingerprints.cast<String, Object?>(),
      state: state,
    );
    verifyReadinessBundleExpectedSourceInputCoverage(bundle, state: state);
  } else {
    state.missingSourceFingerprints.add('sourceInputFingerprints');
  }
  verifyReadinessBundleCommandWorkingDirectory(bundle, state: state);
  verifyReadinessBundleManifestConsistency(bundle, state: state);
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebReadinessBundleVerification',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'bundlePath': file.absolute.path,
    'strictPass': state.strictPass,
    'checkedArtifactCount': state.checkedArtifactCount,
    'mismatchCount': state.mismatches.length,
    'missingArtifactCount': state.missingArtifacts.length,
    'missingFingerprintCount': state.missingFingerprints.length,
    'checkedSourceInputCount': state.checkedSourceInputCount,
    'sourceMismatchCount': state.sourceMismatches.length,
    'missingSourceInputCount': state.missingSourceInputs.length,
    'missingSourceFingerprintCount': state.missingSourceFingerprints.length,
    'checkedMetadataCount': state.checkedMetadataCount,
    'metadataMismatchCount': state.metadataMismatches.length,
    'missingMetadataCount': state.missingMetadata.length,
    'checkedManifestFieldCount': state.checkedManifestFieldCount,
    'manifestMismatchCount': state.manifestMismatches.length,
    'missingManifestFieldCount': state.missingManifestFields.length,
    if (state.mismatches.isNotEmpty) 'mismatches': state.mismatches,
    if (state.missingArtifacts.isNotEmpty)
      'missingArtifacts': state.missingArtifacts,
    if (state.missingFingerprints.isNotEmpty)
      'missingFingerprints': state.missingFingerprints,
    if (state.sourceMismatches.isNotEmpty)
      'sourceMismatches': state.sourceMismatches,
    if (state.missingSourceInputs.isNotEmpty)
      'missingSourceInputs': state.missingSourceInputs,
    if (state.missingSourceFingerprints.isNotEmpty)
      'missingSourceFingerprints': state.missingSourceFingerprints,
    if (state.metadataMismatches.isNotEmpty)
      'metadataMismatches': state.metadataMismatches,
    if (state.missingMetadata.isNotEmpty)
      'missingMetadata': state.missingMetadata,
    if (state.manifestMismatches.isNotEmpty)
      'manifestMismatches': state.manifestMismatches,
    if (state.missingManifestFields.isNotEmpty)
      'missingManifestFields': state.missingManifestFields,
  };
}

Map<String, Object?> _artifactFingerprints(Map<String, Object?> artifacts) {
  final fingerprints = <String, Object?>{};
  for (final entry in artifacts.entries) {
    if (entry.key == 'bundleJson') continue;
    final value = entry.value;
    if (value is String) {
      fingerprints[entry.key] = _fileFingerprint(value);
    } else if (value is Map) {
      fingerprints[entry.key] = _artifactFingerprints(
        value.cast<String, Object?>(),
      );
    }
  }
  return fingerprints;
}

String _fileFingerprint(String path) => readinessFileFingerprint(path);

String? _defaultThresholdReviewPath(String? thresholdPolicyPath) {
  if (thresholdPolicyPath == null || thresholdPolicyPath.trim().isEmpty) {
    return null;
  }
  return '${File(thresholdPolicyPath).parent.path}${Platform.pathSeparator}threshold-review.json';
}

String? _thresholdReviewPlanPath(String? reviewedThresholdOutputPath) {
  if (reviewedThresholdOutputPath == null ||
      reviewedThresholdOutputPath.trim().isEmpty) {
    return null;
  }
  return '${File(reviewedThresholdOutputPath).parent.path}${Platform.pathSeparator}threshold-review-plan.md';
}

final class _Options {
  const _Options({
    required this.help,
    required this.verifyPath,
    required this.captureDir,
    required this.manualDir,
    required this.outputDir,
    required this.minRuns,
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
    required this.thresholdsPath,
    required this.thresholdReviewPath,
    required this.requireComparableRunEnvironment,
    required this.maxFallbackCells,
    required this.maxFallbackFramePercent,
    required this.maxFallbackViewportPercent,
    required this.targetPreset,
    required this.targetIds,
    required this.requireScoreboardGates,
    required this.requireTotalFrameGate,
    required this.requireReviewedThresholdPolicy,
    required this.requireThresholdReviewSummary,
    required this.requireScenarioThresholds,
    required this.requireSemanticGates,
    required this.writeDefaultPreflights,
    required this.completionAuditPath,
    required this.json,
    required this.strict,
  });

  final bool help;
  final String? verifyPath;
  final String captureDir;
  final String manualDir;
  final String outputDir;
  final int minRuns;
  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;
  final String? thresholdsPath;
  final String? thresholdReviewPath;
  final bool requireComparableRunEnvironment;
  final int? maxFallbackCells;
  final double? maxFallbackFramePercent;
  final double? maxFallbackViewportPercent;
  final String targetPreset;
  final List<String> targetIds;
  final bool requireScoreboardGates;
  final bool requireTotalFrameGate;
  final bool requireReviewedThresholdPolicy;
  final bool requireThresholdReviewSummary;
  final bool requireScenarioThresholds;
  final bool requireSemanticGates;
  final bool writeDefaultPreflights;
  final String? completionAuditPath;
  final bool json;
  final bool strict;

  static _Options parse(List<String> args) {
    var help = false;
    String? verifyPath;
    var captureDir = '../../profiling/web/baselines';
    var manualDir = '../../profiling/web/manual';
    var outputDir = '../../profiling/web/baselines/web-readiness-bundle';
    var minRuns = 3;
    double? maxTotalFrameP95Ms;
    double? maxDomApplyP95Ms;
    double? maxSemanticApplyP95Ms;
    double? maxOverBudgetPercent;
    double? maxSemanticUncoveredCells;
    String? thresholdsPath;
    String? thresholdReviewPath;
    var requireComparableRunEnvironment = true;
    int? maxFallbackCells;
    double? maxFallbackFramePercent;
    double? maxFallbackViewportPercent;
    var targetPreset = 'primary';
    final targetIds = <String>[];
    var requireScoreboardGates = true;
    var requireTotalFrameGate = true;
    var requireReviewedThresholdPolicy = true;
    var requireThresholdReviewSummary = true;
    var requireScenarioThresholds = true;
    var requireSemanticGates = true;
    var writeDefaultPreflights = false;
    String? completionAuditPath;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--verify=')) {
        verifyPath = arg.substring('--verify='.length).trim();
        if (verifyPath.isEmpty) {
          stderr.writeln('--verify requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--captures=')) {
        captureDir = arg.substring('--captures='.length);
      } else if (arg.startsWith('--manual=')) {
        manualDir = arg.substring('--manual='.length);
      } else if (arg.startsWith('--output-dir=')) {
        outputDir = arg.substring('--output-dir='.length);
      } else if (arg.startsWith('--min-runs=')) {
        minRuns = _positiveInt(arg, '--min-runs=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveDouble(arg, '--max-total-frame-p95-ms=');
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--thresholds=')) {
        thresholdsPath = arg.substring('--thresholds='.length);
      } else if (arg.startsWith('--threshold-review=')) {
        thresholdReviewPath = arg
            .substring('--threshold-review='.length)
            .trim();
      } else if (arg == '--no-require-comparable-environment') {
        requireComparableRunEnvironment = false;
      } else if (arg.startsWith('--max-fallback-cells=')) {
        maxFallbackCells = _nonNegativeInt(arg, '--max-fallback-cells=');
      } else if (arg.startsWith('--max-fallback-frame-percent=')) {
        maxFallbackFramePercent = _nonNegativeDouble(
          arg,
          '--max-fallback-frame-percent=',
        );
      } else if (arg.startsWith('--max-fallback-viewport-percent=')) {
        maxFallbackViewportPercent = _nonNegativeDouble(
          arg,
          '--max-fallback-viewport-percent=',
        );
      } else if (arg.startsWith('--target-preset=')) {
        targetPreset = arg.substring('--target-preset='.length);
      } else if (arg.startsWith('--target=')) {
        targetIds.add(arg.substring('--target='.length));
      } else if (arg == '--no-require-scoreboard-gates') {
        requireScoreboardGates = false;
      } else if (arg == '--no-require-total-frame-gate') {
        requireTotalFrameGate = false;
      } else if (arg == '--no-require-reviewed-threshold-policy') {
        requireReviewedThresholdPolicy = false;
      } else if (arg == '--no-require-threshold-review-summary') {
        requireThresholdReviewSummary = false;
      } else if (arg == '--no-require-scenario-thresholds') {
        requireScenarioThresholds = false;
      } else if (arg == '--no-require-semantic-gates') {
        requireSemanticGates = false;
      } else if (arg == '--write-default-preflights') {
        writeDefaultPreflights = true;
      } else if (arg.startsWith('--completion-audit=')) {
        completionAuditPath = arg
            .substring('--completion-audit='.length)
            .trim();
        if (completionAuditPath.isEmpty) {
          stderr.writeln('--completion-audit requires a non-empty path.');
          exit(2);
        }
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for web_readiness_bundle: $arg');
        _printUsage();
        exit(2);
      }
    }
    if (thresholdReviewPath != null && thresholdReviewPath.isEmpty) {
      stderr.writeln('--threshold-review requires a non-empty path.');
      exit(2);
    }

    return _Options(
      help: help,
      verifyPath: verifyPath,
      captureDir: captureDir,
      manualDir: manualDir,
      outputDir: outputDir,
      minRuns: minRuns,
      maxTotalFrameP95Ms: maxTotalFrameP95Ms,
      maxDomApplyP95Ms: maxDomApplyP95Ms,
      maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
      maxOverBudgetPercent: maxOverBudgetPercent,
      maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      thresholdsPath: thresholdsPath,
      thresholdReviewPath: thresholdReviewPath,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
      maxFallbackCells: maxFallbackCells,
      maxFallbackFramePercent: maxFallbackFramePercent,
      maxFallbackViewportPercent: maxFallbackViewportPercent,
      targetPreset: targetPreset,
      targetIds: List.unmodifiable(targetIds),
      requireScoreboardGates: requireScoreboardGates,
      requireTotalFrameGate: requireTotalFrameGate,
      requireReviewedThresholdPolicy: requireReviewedThresholdPolicy,
      requireThresholdReviewSummary: requireThresholdReviewSummary,
      requireScenarioThresholds: requireScenarioThresholds,
      requireSemanticGates: requireSemanticGates,
      writeDefaultPreflights: writeDefaultPreflights,
      completionAuditPath: completionAuditPath,
      json: json,
      strict: strict,
    );
  }
}

enum _DefaultPreflightTarget {
  makeDomDefault('make-dom-default'),
  retireTemporaryPaths('retire-temporary-paths');

  const _DefaultPreflightTarget(this.id);

  final String id;
}

int _positiveInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive integer.');
    exit(2);
  }
  return value;
}

double _positiveDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive number.');
    exit(2);
  }
  return value;
}

int _nonNegativeInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative integer.');
    exit(2);
  }
  return value;
}

double _nonNegativeDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative number.');
    exit(2);
  }
  return value;
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_readiness_bundle.dart [options]');
  stdout.writeln('');
  stdout.writeln(
    'Builds the reviewed JSON artifact bundle consumed by web_readiness.dart.',
  );
  stdout.writeln('It does not capture browser runs or create manual evidence.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --captures=DIR                      Capture directory, default ../../profiling/web/baselines.',
  );
  stdout.writeln(
    '  --manual=DIR                        Manual evidence directory, default ../../profiling/web/manual.',
  );
  stdout.writeln(
    '  --output-dir=DIR                    Bundle directory, default ../../profiling/web/baselines/web-readiness-bundle.',
  );
  stdout.writeln(
    '  --verify=PATH                       Verify artifact fingerprints in an existing web-readiness-bundle.json.',
  );
  stdout.writeln(
    '  --min-runs=N                        Minimum runs, default 3.',
  );
  stdout.writeln('  --max-total-frame-p95-ms=N          Frame gate.');
  stdout.writeln('  --max-dom-apply-p95-ms=N            DOM apply gate.');
  stdout.writeln('  --max-semantic-apply-p95-ms=N       Semantic apply gate.');
  stdout.writeln('  --max-over-budget-percent=N         Over-budget gate.');
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N    Semantic uncovered-cell gate.',
  );
  stdout.writeln(
    '  --thresholds=PATH                   JSON threshold policy with defaults/scenarios.',
  );
  stdout.writeln(
    '  --threshold-review=PATH             Threshold promotion summary JSON artifact.',
  );
  stdout.writeln(
    '  --no-require-comparable-environment Do not require comparable run environments.',
  );
  stdout.writeln(
    '  --max-fallback-cells=N              Semantic fallback gate.',
  );
  stdout.writeln(
    '  --max-fallback-frame-percent=N      Semantic fallback gate.',
  );
  stdout.writeln(
    '  --max-fallback-viewport-percent=N   Semantic fallback gate.',
  );
  stdout.writeln('  --target-preset=v1|primary|all     Manual target preset.');
  stdout.writeln(
    '  --target=ID                         Restrict manual audit target.',
  );
  stdout.writeln('  --no-require-scoreboard-gates       Relax readiness gate.');
  stdout.writeln('  --no-require-total-frame-gate       Relax readiness gate.');
  stdout.writeln(
    '  --no-require-reviewed-threshold-policy Relax readiness gate.',
  );
  stdout.writeln(
    '  --no-require-threshold-review-summary Relax threshold-review summary gate.',
  );
  stdout.writeln(
    '  --no-require-scenario-thresholds    Relax per-scenario threshold gate.',
  );
  stdout.writeln('  --no-require-semantic-gates         Relax readiness gate.');
  stdout.writeln(
    '  --write-default-preflights          Write make-dom-default and retire-temporary-paths preflight artifacts.',
  );
  stdout.writeln(
    '  --completion-audit=PATH             Write an RFC completion status audit JSON.',
  );
  stdout.writeln(
    '  --strict                            Exit non-zero unless readiness passes.',
  );
  stdout.writeln(
    '  --json                              Print machine-readable bundle JSON.',
  );
}
