import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/manual_validation/manual_validation_targets.dart';

const _requiredSourceInputFingerprintGroups = <String>{
  'fleuryCoreImplementationFiles',
  'packageConfigurationFiles',
  'readinessToolFiles',
  'rootReleaseLauncherFiles',
  'webAutomatedTestFiles',
  'webImplementationFiles',
};

const _requiredArtifactFields = <String>{'manualPlan'};

const _readinessBundleVerificationScope = <String>[
  'generated-artifact-fingerprints',
  'source-input-fingerprints',
  'expected-source-input-path-coverage',
  'command-working-directory-metadata',
  'manual-evidence-latest-entry-fingerprints',
  'threshold-review-release-action',
  'manual-evidence-release-actions',
  'generated-default-preflight-diagnostics',
  'release-action-command-templates',
];

const webAutomatedBrowserTestPaths = <String>[
  'test/browser_frame_flush_scheduler_test.dart',
  'test/cell_metrics_test.dart',
  'test/dom_grid_surface_test.dart',
  'test/dom_input_source_test.dart',
  'test/dom_input_trace_fixture_test.dart',
  'test/run_tui_surface_test.dart',
  'test/mount_app_test.dart',
  'test/semantic_dom_presenter_test.dart',
  'test/web_clipboard_test.dart',
];

const webAutomatedVmTestPaths = <String>[
  'test/frame_presentation_test.dart',
  'test/web_focus_coordinator_test.dart',
  'test/web_host_instrumentation_test.dart',
  'test/web_public_api_boundary_test.dart',
];

const webAutomatedFixturePaths = <String>[
  'test/fixtures/browser_input_traces.dart',
];

const webAutomatedTestSourceInputPaths = <String>[
  ...webAutomatedBrowserTestPaths,
  ...webAutomatedVmTestPaths,
  ...webAutomatedFixturePaths,
];

const webAutomatedValidationFileName = 'web-automated-validation.json';

List<String> webAutomatedBrowserTestCommand() => const <String>[
  'dart',
  'test',
  '-p',
  'chrome',
  ...webAutomatedBrowserTestPaths,
];

List<String> webAutomatedVmTestCommand() => const <String>[
  'dart',
  'test',
  ...webAutomatedVmTestPaths,
];

List<Map<String, Object?>> webAutomatedTestSourceInputFingerprints() {
  return _webAutomatedTestInputFingerprints();
}

final class ReadinessBundleVerificationState {
  int checkedArtifactCount = 0;
  int checkedSourceInputCount = 0;
  int checkedMetadataCount = 0;
  int checkedManifestFieldCount = 0;
  final List<Map<String, Object?>> mismatches = <Map<String, Object?>>[];
  final List<Map<String, Object?>> missingArtifacts = <Map<String, Object?>>[];
  final List<String> missingFingerprints = <String>[];
  final List<Map<String, Object?>> sourceMismatches = <Map<String, Object?>>[];
  final List<Map<String, Object?>> missingSourceInputs =
      <Map<String, Object?>>[];
  final List<String> missingSourceFingerprints = <String>[];
  final List<Map<String, Object?>> metadataMismatches =
      <Map<String, Object?>>[];
  final List<String> missingMetadata = <String>[];
  final List<Map<String, Object?>> manifestMismatches =
      <Map<String, Object?>>[];
  final List<String> missingManifestFields = <String>[];

  bool get strictPass =>
      mismatches.isEmpty &&
      missingArtifacts.isEmpty &&
      missingFingerprints.isEmpty &&
      sourceMismatches.isEmpty &&
      missingSourceInputs.isEmpty &&
      missingSourceFingerprints.isEmpty &&
      metadataMismatches.isEmpty &&
      missingMetadata.isEmpty &&
      manifestMismatches.isEmpty &&
      missingManifestFields.isEmpty;
}

void verifyReadinessBundleCommandWorkingDirectory(
  Map<String, Object?> bundle, {
  required ReadinessBundleVerificationState state,
}) {
  final inputRaw = bundle['input'];
  if (inputRaw is! Map) {
    state.missingMetadata.add('input.commandWorkingDirectory');
    return;
  }

  final input = inputRaw.cast<String, Object?>();
  final commandWorkingDirectory = input['commandWorkingDirectory'];
  if (commandWorkingDirectory is! String ||
      commandWorkingDirectory.trim().isEmpty) {
    state.missingMetadata.add('input.commandWorkingDirectory');
    return;
  }

  state.checkedMetadataCount += 1;
  final expected = Directory.current.absolute.path;
  if (commandWorkingDirectory != expected) {
    state.metadataMismatches.add(<String, Object?>{
      'id': 'input.commandWorkingDirectory',
      'expected': expected,
      'actual': commandWorkingDirectory,
    });
  }
}

void verifyReadinessBundleArtifacts({
  required Map<String, Object?> artifacts,
  required Map<String, Object?> fingerprints,
  required ReadinessBundleVerificationState state,
  String prefix = '',
}) {
  if (prefix.isEmpty) {
    for (final field in _requiredArtifactFields) {
      if (!artifacts.containsKey(field)) {
        state.missingManifestFields.add('artifacts.$field');
      }
    }
  }
  for (final entry in artifacts.entries) {
    if (entry.key == 'bundleJson') continue;
    final id = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    final artifact = entry.value;
    final fingerprint = fingerprints[entry.key];
    if (artifact is String) {
      if (fingerprint is! String || fingerprint.trim().isEmpty) {
        state.missingFingerprints.add(id);
        continue;
      }
      final file = File(artifact);
      if (!file.existsSync()) {
        state.missingArtifacts.add(<String, Object?>{
          'id': id,
          'path': artifact,
          'expected': fingerprint,
        });
        continue;
      }
      state.checkedArtifactCount += 1;
      final actual = readinessFileFingerprint(artifact);
      if (actual != fingerprint) {
        state.mismatches.add(<String, Object?>{
          'id': id,
          'path': artifact,
          'expected': fingerprint,
          'actual': actual,
        });
      }
    } else if (artifact is Map) {
      if (fingerprint is! Map) {
        state.missingFingerprints.add(id);
        continue;
      }
      verifyReadinessBundleArtifacts(
        artifacts: artifact.cast<String, Object?>(),
        fingerprints: fingerprint.cast<String, Object?>(),
        state: state,
        prefix: id,
      );
    }
  }
}

void verifyReadinessBundleSourceInputFingerprints(
  Map<String, Object?> fingerprints, {
  required ReadinessBundleVerificationState state,
}) {
  for (final group in _requiredSourceInputFingerprintGroups) {
    final value = fingerprints[group];
    if (value is! List || value.isEmpty) {
      state.missingSourceFingerprints.add(group);
    }
  }
  for (final entry in fingerprints.entries) {
    verifyReadinessBundleSourceInputFingerprintValue(
      entry.value,
      id: entry.key,
      state: state,
    );
  }
}

void verifyReadinessBundleExpectedSourceInputCoverage(
  Map<String, Object?> bundle, {
  required ReadinessBundleVerificationState state,
}) {
  final actual = _map(bundle['sourceInputFingerprints']);
  if (actual.isEmpty) return;
  final expected = _expectedReadinessBundleSourceInputFingerprints(bundle);
  for (final entry in expected.entries) {
    _verifyExpectedSourceInputFingerprintGroup(
      group: entry.key,
      expected: entry.value,
      actual: actual[entry.key],
      state: state,
    );
  }
}

Map<String, Object?> readinessBundleSourceInputFingerprints({
  required String captureDir,
  required String manualDir,
  required List<String> manualTemplateTargetIds,
  required List<String> manualEvidenceTargetIds,
  required String? thresholdPolicyPath,
  required String? thresholdReviewPath,
  required String? thresholdReviewPlanPath,
}) {
  final fingerprints = <String, Object?>{
    'captureFiles': _captureInputFingerprints(captureDir),
    'manualEvidenceFiles': _manualEvidenceInputFingerprints(
      manualDir,
      targetIds: manualEvidenceTargetIds,
    ),
    'manualTemplateFiles': _manualTemplateInputFingerprints(
      manualDir,
      targetIds: manualTemplateTargetIds,
    ),
    'manualValidationPageFiles': _manualValidationPageInputFingerprints(),
    'webImplementationFiles': _webImplementationInputFingerprints(),
    'webAutomatedTestFiles': _webAutomatedTestInputFingerprints(),
    'fleuryCoreImplementationFiles': _packageImplementationInputFingerprints(
      'fleury',
    ),
    'readinessToolFiles': _readinessToolInputFingerprints(),
    'rootReleaseLauncherFiles': _rootReleaseLauncherInputFingerprints(),
    'packageConfigurationFiles': _packageConfigurationInputFingerprints(),
  };
  final thresholdPolicy = _optionalSourceInputFingerprint(thresholdPolicyPath);
  if (thresholdPolicy != null) {
    fingerprints['thresholdPolicy'] = thresholdPolicy;
  }
  final thresholdReview = _optionalSourceInputFingerprint(thresholdReviewPath);
  if (thresholdReview != null) {
    fingerprints['thresholdReview'] = thresholdReview;
  }
  final thresholdReviewPlan = _optionalSourceInputFingerprint(
    thresholdReviewPlanPath,
  );
  if (thresholdReviewPlan != null) {
    fingerprints['thresholdReviewPlan'] = thresholdReviewPlan;
  }
  return fingerprints;
}

void verifyReadinessBundleSourceInputFingerprintValue(
  Object? value, {
  required String id,
  required ReadinessBundleVerificationState state,
}) {
  if (value is List) {
    for (var index = 0; index < value.length; index += 1) {
      verifyReadinessBundleSourceInputFingerprintValue(
        value[index],
        id: '$id[$index]',
        state: state,
      );
    }
    return;
  }

  if (value is! Map) {
    state.missingSourceFingerprints.add(id);
    return;
  }

  final entry = value.cast<String, Object?>();
  final path = entry['path'];
  final expected = entry['fingerprint'];
  if (path is String && expected is String && expected.trim().isNotEmpty) {
    final file = File(path);
    if (!file.existsSync()) {
      state.missingSourceInputs.add(<String, Object?>{
        'id': id,
        'path': path,
        'expected': expected,
      });
      return;
    }
    state.checkedSourceInputCount += 1;
    final actual = readinessFileFingerprint(path);
    if (actual != expected) {
      state.sourceMismatches.add(<String, Object?>{
        'id': id,
        'path': path,
        'expected': expected,
        'actual': actual,
      });
    }
    return;
  }

  for (final nested in entry.entries) {
    verifyReadinessBundleSourceInputFingerprintValue(
      nested.value,
      id: '$id.${nested.key}',
      state: state,
    );
  }
}

Map<String, Object?> _expectedReadinessBundleSourceInputFingerprints(
  Map<String, Object?> bundle,
) {
  final input = _map(bundle['input']);
  final captureDir = _string(input['captureDir']);
  final manualDir = _string(input['manualDir']);
  final thresholdPolicyPath = _string(input['thresholdPolicyPath']);
  final thresholdReviewPath = _string(input['thresholdReviewPath']);
  final manualTemplateTargetIds = _expectedManualTargetIds(input);

  return readinessBundleSourceInputFingerprints(
    captureDir: captureDir ?? '',
    manualDir: manualDir ?? '',
    manualTemplateTargetIds: manualTemplateTargetIds,
    manualEvidenceTargetIds: manualTemplateTargetIds,
    thresholdPolicyPath: thresholdPolicyPath,
    thresholdReviewPath: thresholdReviewPath,
    thresholdReviewPlanPath: _thresholdReviewPlanPath(
      _reviewedThresholdOutputPath(thresholdPolicyPath),
    ),
  );
}

void _verifyExpectedSourceInputFingerprintGroup({
  required String group,
  required Object? expected,
  required Object? actual,
  required ReadinessBundleVerificationState state,
}) {
  final actualPaths = {
    for (final entry in _sourceFingerprintEntries(actual))
      if (_string(entry['path']) != null) _string(entry['path'])!,
  };
  for (final expectedEntry in _sourceFingerprintEntries(expected)) {
    final path = _string(expectedEntry['path']);
    if (path == null) continue;
    if (actualPaths.contains(path)) continue;
    state.missingSourceInputs.add(<String, Object?>{
      'id': group,
      'path': path,
      'expected': expectedEntry['fingerprint'],
    });
  }
}

List<Map<String, Object?>> _sourceFingerprintEntries(Object? value) {
  if (value is List) {
    return [for (final item in value) ..._sourceFingerprintEntries(item)];
  }
  if (value is! Map) return const <Map<String, Object?>>[];
  final map = value.cast<String, Object?>();
  if (map['path'] is String) return [map];
  return [for (final item in map.values) ..._sourceFingerprintEntries(item)];
}

void verifyReadinessBundleManifestConsistency(
  Map<String, Object?> bundle, {
  required ReadinessBundleVerificationState state,
}) {
  final artifacts = _map(bundle['artifacts']);
  final checks = _map(bundle['checks']);
  final readiness = _readArtifactJson(artifacts['readinessJson']);
  if (readiness != null) {
    final strictPass = readiness['strictPass'] == true;
    _expectManifestField(
      state,
      id: 'strictPass',
      expected: strictPass,
      actual: bundle['strictPass'],
    );
    _expectManifestField(
      state,
      id: 'checks.readinessStrictPass',
      expected: strictPass,
      actual: checks['readinessStrictPass'],
    );
  }

  _verifyArtifactStrictPass(
    state,
    artifacts: artifacts,
    checks: checks,
    artifactKey: 'scoreboard',
    checkKey: 'scoreboardStrictPass',
  );
  _verifyArtifactStrictPass(
    state,
    artifacts: artifacts,
    checks: checks,
    artifactKey: 'semanticAudit',
    checkKey: 'semanticAuditStrictPass',
  );
  _verifyArtifactStrictPass(
    state,
    artifacts: artifacts,
    checks: checks,
    artifactKey: 'manualAudit',
    checkKey: 'manualAuditStrictPass',
  );
  final manualAudit = _readArtifactJson(artifacts['manualAudit']);
  if (manualAudit != null) {
    _expectManifestStringListField(
      state,
      id: 'artifacts.manualAudit.targets',
      expected: _expectedManualTargetIds(_map(bundle['input'])),
      actual: _manualTargetIdsFromAudit(
        manualAudit,
        fallbackTargetIds: const <String>[],
      ),
    );
    _verifyManualEvidenceLatestEntryFingerprints(
      state,
      targets: _maps(manualAudit['targets']),
      sourceInputFingerprints: _map(bundle['sourceInputFingerprints']),
      idPrefix: 'artifacts.manualAudit.targets',
    );
  }
  if (readiness != null) {
    final manualCheck = _checkById(
      _maps(readiness['checks']),
      'manualValidation',
    );
    if (manualCheck != null) {
      _verifyManualEvidenceLatestEntryFingerprints(
        state,
        targets: _maps(_map(manualCheck['details'])['manualEvidence']),
        sourceInputFingerprints: _map(bundle['sourceInputFingerprints']),
        idPrefix: 'artifacts.readiness.manualValidation.manualEvidence',
      );
    }
    _verifyThresholdReviewReleaseAction(
      state,
      bundle: bundle,
      readiness: readiness,
    );
    _verifyManualEvidenceReleaseActions(
      state,
      bundle: bundle,
      readiness: readiness,
    );
  }
  _verifyDefaultPreflightManifest(
    state,
    bundle: bundle,
    artifacts: artifacts,
    checks: checks,
  );
}

void _verifyThresholdReviewReleaseAction(
  ReadinessBundleVerificationState state, {
  required Map<String, Object?> bundle,
  required Map<String, Object?> readiness,
}) {
  final frameCheck = _checkById(_maps(readiness['checks']), 'frameScoreboard');
  if (frameCheck == null || frameCheck['strictPass'] == true) return;
  final actions = _maps(bundle['remainingReleaseActions']);
  final action = _releaseAction(actions, 'review-threshold-policy');
  if (action == null) {
    state.missingManifestFields.add(
      'remainingReleaseActions.review-threshold-policy',
    );
    return;
  }
  final details = _map(action['details']);
  final thresholdPolicyPath = _string(details['candidateThresholdPolicyPath']);
  final planOutputPath = _string(details['thresholdReviewPlanPath']);
  final reviewContext =
      _string(details['suggestedReviewContext']) ??
      '<Chrome version, platform, retained DOM product baseline>';
  final expectedInputFingerprint =
      _string(details['expectedInputFingerprint']) ??
      _string(details['currentThresholdPolicyFingerprint']);
  final hasOverBudgetThresholds =
      details['overBudgetAcknowledgementRequired'] == true;
  final planReviewContextHint =
      details['planCommandUsesCandidateCapturedContext'] == true
      ? null
      : _string(details['suggestedReviewContext']);

  if (thresholdPolicyPath != null && planOutputPath != null) {
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.review-threshold-policy.planCommand',
      expected: _thresholdReviewPlanCommand(
        thresholdPolicyPath: thresholdPolicyPath,
        planOutputPath: planOutputPath,
        reviewContextHint: planReviewContextHint,
      ),
      actual: action['planCommand'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.review-threshold-policy.rootPlanCommand',
      expected: _rootThresholdReviewPlanCommand(
        thresholdPolicyPath: thresholdPolicyPath,
        planOutputPath: planOutputPath,
        reviewContextHint: planReviewContextHint,
      ),
      actual: action['rootPlanCommand'],
    );
  }

  _expectManifestStringListField(
    state,
    id: 'remainingReleaseActions.review-threshold-policy.commandTemplate',
    expected: _thresholdReviewCommandTemplate(
      thresholdPolicyPath: thresholdPolicyPath,
      outputPath: _string(details['reviewedThresholdPolicyPath']),
      jsonOutputPath: _string(details['thresholdReviewPath']),
      expectedInputFingerprint: expectedInputFingerprint,
      reviewContext: reviewContext,
      hasOverBudgetThresholds: hasOverBudgetThresholds,
    ),
    actual: action['commandTemplate'],
  );
  _expectManifestStringListField(
    state,
    id: 'remainingReleaseActions.review-threshold-policy.rootCommandTemplate',
    expected: _rootThresholdReviewCommandTemplate(
      thresholdPolicyPath: thresholdPolicyPath,
      outputPath: _string(details['reviewedThresholdPolicyPath']),
      jsonOutputPath: _string(details['thresholdReviewPath']),
      expectedInputFingerprint: expectedInputFingerprint,
      reviewContext: reviewContext,
      hasOverBudgetThresholds: hasOverBudgetThresholds,
    ),
    actual: action['rootCommandTemplate'],
  );
}

List<String> _thresholdReviewPlanCommand({
  required String thresholdPolicyPath,
  required String planOutputPath,
  required String? reviewContextHint,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_threshold_review.dart',
    '--input=$thresholdPolicyPath',
    '--write-plan=$planOutputPath',
    if (reviewContextHint != null) '--review-context-hint=$reviewContextHint',
  ];
}

List<String> _rootThresholdReviewPlanCommand({
  required String thresholdPolicyPath,
  required String planOutputPath,
  required String? reviewContextHint,
}) {
  return <String>[
    'dart',
    'run',
    'tool/fleury_dev.dart',
    'benchmark',
    'web-threshold-review',
    '--input=$thresholdPolicyPath',
    '--write-plan=$planOutputPath',
    if (reviewContextHint != null) '--review-context-hint=$reviewContextHint',
  ];
}

List<String> _thresholdReviewCommandTemplate({
  required String? thresholdPolicyPath,
  required String? outputPath,
  required String? jsonOutputPath,
  required String? expectedInputFingerprint,
  required String reviewContext,
  required bool hasOverBudgetThresholds,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_threshold_review.dart',
    if (thresholdPolicyPath != null) '--input=$thresholdPolicyPath',
    if (outputPath != null) '--output=$outputPath',
    if (jsonOutputPath != null) '--json-output=$jsonOutputPath',
    if (expectedInputFingerprint != null)
      '--expect-input-fingerprint=$expectedInputFingerprint',
    '--reviewed-by=<reviewer>',
    '--review-context=$reviewContext',
    if (hasOverBudgetThresholds) '--allow-over-budget-thresholds',
    if (hasOverBudgetThresholds)
      '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
  ];
}

List<String> _rootThresholdReviewCommandTemplate({
  required String? thresholdPolicyPath,
  required String? outputPath,
  required String? jsonOutputPath,
  required String? expectedInputFingerprint,
  required String reviewContext,
  required bool hasOverBudgetThresholds,
}) {
  return <String>[
    'dart',
    'run',
    'tool/fleury_dev.dart',
    'benchmark',
    'web-threshold-review',
    if (thresholdPolicyPath != null) '--input=$thresholdPolicyPath',
    if (outputPath != null) '--output=$outputPath',
    if (jsonOutputPath != null) '--json-output=$jsonOutputPath',
    if (expectedInputFingerprint != null)
      '--expect-input-fingerprint=$expectedInputFingerprint',
    '--reviewed-by=<reviewer>',
    '--review-context=$reviewContext',
    if (hasOverBudgetThresholds) '--allow-over-budget-thresholds',
    if (hasOverBudgetThresholds)
      '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
  ];
}

void _verifyManualEvidenceReleaseActions(
  ReadinessBundleVerificationState state, {
  required Map<String, Object?> bundle,
  required Map<String, Object?> readiness,
}) {
  final manualCheck = _checkById(
    _maps(readiness['checks']),
    'manualValidation',
  );
  if (manualCheck == null || manualCheck['strictPass'] == true) return;
  final input = _map(bundle['input']);
  final manualDir = _string(input['manualDir']);
  if (manualDir == null) {
    state.missingManifestFields.add('input.manualDir');
    return;
  }
  final targetPreset = _string(input['targetPreset']) ?? 'primary';
  final targetIds = _strings(
    input['targetIds'],
  ).map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
  final details = _map(manualCheck['details']);
  final failingTargets = _maps(details['failingTargetDetails']);
  final actions = _maps(bundle['remainingReleaseActions']);
  final prepareAction = _releaseAction(
    actions,
    'prepare-manual-evidence-templates',
  );
  if (prepareAction != null) {
    final templatesDir = _joinPath(manualDir, 'templates');
    final prepareDetails = _map(prepareAction['details']);
    final prepareTargetIds = _maps(prepareDetails['targetTemplates'])
        .map((template) => _string(template['targetId']))
        .whereType<String>()
        .where((targetId) => targetId.trim().isNotEmpty)
        .toList();
    final expectedTargetIds = prepareTargetIds.isNotEmpty
        ? prepareTargetIds
        : targetIds;
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.prepare-manual-evidence-templates.commandTemplate',
      expected: _manualTemplatePreparationCommand(
        manualDir: manualDir,
        templatesDir: templatesDir,
        targetPreset: targetPreset,
        targetIds: expectedTargetIds,
      ),
      actual: prepareAction['commandTemplate'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.prepare-manual-evidence-templates.rootCommandTemplate',
      expected: _rootManualTemplatePreparationCommand(
        manualDir: manualDir,
        templatesDir: templatesDir,
        targetPreset: targetPreset,
        targetIds: expectedTargetIds,
      ),
      actual: prepareAction['rootCommandTemplate'],
    );
  }
  for (final target in failingTargets) {
    final targetId = _string(target['id']);
    if (targetId == null) continue;
    final action = _releaseAction(actions, 'collect-manual-evidence:$targetId');
    if (action == null) {
      state.missingManifestFields.add(
        'remainingReleaseActions.collect-manual-evidence:$targetId',
      );
      continue;
    }
    final starterEvidencePath = _joinPath(
      _joinPath(manualDir, 'evidence'),
      '$targetId.review.json',
    );
    final templatePath = _joinPath(
      _joinPath(manualDir, 'templates'),
      '$targetId.template.json',
    );
    final actionDetails = _map(action['details']);
    final templateStatus = _string(actionDetails['templateStatus']);
    if (templateStatus != null && templateStatus != 'current') {
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.collect-manual-evidence:$targetId.commandTemplate',
        expected: _manualEvidenceTemplateCommand(
          templatePath: templatePath,
          targetId: targetId,
        ),
        actual: action['commandTemplate'],
      );
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.collect-manual-evidence:$targetId.rootCommandTemplate',
        expected: _rootManualEvidenceTemplateCommand(
          templatePath: templatePath,
          targetId: targetId,
        ),
        actual: action['rootCommandTemplate'],
      );
    }
    if (actionDetails['starterEvidenceStatus'] == 'missing') {
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.collect-manual-evidence:$targetId.starterCommand',
        expected: _manualEvidenceStarterCommand(
          starterEvidencePath: starterEvidencePath,
          templatePath: templatePath,
          targetId: targetId,
        ),
        actual: action['starterCommand'],
      );
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.collect-manual-evidence:$targetId.rootStarterCommand',
        expected: _rootManualEvidenceStarterCommand(
          starterEvidencePath: starterEvidencePath,
          templatePath: templatePath,
          targetId: targetId,
        ),
        actual: action['rootStarterCommand'],
      );
    }
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.provenanceCommandTemplate',
      expected: _manualEvidenceProvenanceCommand(
        starterEvidencePath: starterEvidencePath,
        targetId: targetId,
      ),
      actual: action['provenanceCommandTemplate'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.rootProvenanceCommandTemplate',
      expected: _rootManualEvidenceProvenanceCommand(
        starterEvidencePath: starterEvidencePath,
        targetId: targetId,
      ),
      actual: action['rootProvenanceCommandTemplate'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.pageSignalCommandTemplate',
      expected: _manualEvidencePageSignalCommand(
        starterEvidencePath: starterEvidencePath,
        targetId: targetId,
      ),
      actual: action['pageSignalCommandTemplate'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.rootPageSignalCommandTemplate',
      expected: _rootManualEvidencePageSignalCommand(
        starterEvidencePath: starterEvidencePath,
        targetId: targetId,
      ),
      actual: action['rootPageSignalCommandTemplate'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.checkCommandTemplate',
      expected: _manualEvidenceCheckCommand(
        starterEvidencePath: starterEvidencePath,
        targetId: targetId,
      ),
      actual: action['checkCommandTemplate'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.rootCheckCommandTemplate',
      expected: _rootManualEvidenceCheckCommand(
        starterEvidencePath: starterEvidencePath,
        targetId: targetId,
      ),
      actual: action['rootCheckCommandTemplate'],
    );
    final auditJsonPath = _joinPath(manualDir, 'manual-validation-audit.json');
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.auditCommand',
      expected: _manualEvidenceAuditCommand(
        manualDir: manualDir,
        targetPreset: targetPreset,
        targetIds: targetIds,
        auditJsonPath: auditJsonPath,
      ),
      actual: action['auditCommand'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.collect-manual-evidence:$targetId.rootAuditCommand',
      expected: _rootManualEvidenceAuditCommand(
        manualDir: manualDir,
        targetPreset: targetPreset,
        targetIds: targetIds,
        auditJsonPath: auditJsonPath,
      ),
      actual: action['rootAuditCommand'],
    );
  }
}

List<String> _manualTemplatePreparationCommand({
  required String manualDir,
  required String templatesDir,
  required String targetPreset,
  required List<String> targetIds,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--input=$manualDir',
    '--write-templates=$templatesDir',
    ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
  ];
}

List<String> _rootManualTemplatePreparationCommand({
  required String manualDir,
  required String templatesDir,
  required String targetPreset,
  required List<String> targetIds,
}) {
  return <String>[
    'dart',
    'run',
    'tool/fleury_dev.dart',
    'benchmark',
    'web-manual-validation',
    '--input=$manualDir',
    '--write-templates=$templatesDir',
    ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
  ];
}

List<String> _manualEvidenceTemplateCommand({
  required String templatePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--write-template=$templatePath',
    '--template-target=$targetId',
  ];
}

List<String> _rootManualEvidenceTemplateCommand({
  required String templatePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/fleury_dev.dart',
    'benchmark',
    'web-manual-validation',
    '--write-template=$templatePath',
    '--template-target=$targetId',
  ];
}

List<String> _manualEvidenceStarterCommand({
  required String starterEvidencePath,
  required String templatePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--write-starter=$starterEvidencePath',
    '--starter-template=$templatePath',
    '--template-target=$targetId',
  ];
}

List<String> _rootManualEvidenceStarterCommand({
  required String starterEvidencePath,
  required String templatePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/fleury_dev.dart',
    'benchmark',
    'web-manual-validation',
    '--write-starter=$starterEvidencePath',
    '--starter-template=$templatePath',
    '--template-target=$targetId',
  ];
}

List<String> _manualEvidenceProvenanceCommand({
  required String starterEvidencePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--update-provenance=$starterEvidencePath',
    '--template-target=$targetId',
    '--reviewed-by=<reviewer>',
    '--captured-at=now',
    '--browser-version=<Chrome version used for manual validation>',
  ];
}

List<String> _rootManualEvidenceProvenanceCommand({
  required String starterEvidencePath,
  required String targetId,
}) {
  return <String>[
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
  ];
}

List<String> _manualEvidencePageSignalCommand({
  required String starterEvidencePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--update-page-signal=$starterEvidencePath',
    '--template-target=$targetId',
    '--signal-id=<required-page-signal-id>',
    '--signal-status=pass',
    '--observed-value=<expected-value>',
    '--signal-notes=<reviewer observation>',
  ];
}

List<String> _rootManualEvidencePageSignalCommand({
  required String starterEvidencePath,
  required String targetId,
}) {
  return <String>[
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
  ];
}

List<String> _manualEvidenceCheckCommand({
  required String starterEvidencePath,
  required String targetId,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--update-check=$starterEvidencePath',
    '--template-target=$targetId',
    '--check-id=<required-check-id>',
    '--check-status=pass',
    '--check-notes=<reviewer observation>',
  ];
}

List<String> _rootManualEvidenceCheckCommand({
  required String starterEvidencePath,
  required String targetId,
}) {
  return <String>[
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
  ];
}

List<String> _manualEvidenceAuditCommand({
  required String manualDir,
  required String targetPreset,
  required List<String> targetIds,
  required String auditJsonPath,
}) {
  return <String>[
    'dart',
    'run',
    'tool/web_manual_validation.dart',
    '--input=$manualDir',
    ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
    '--json-output=$auditJsonPath',
    '--strict',
  ];
}

List<String> _rootManualEvidenceAuditCommand({
  required String manualDir,
  required String targetPreset,
  required List<String> targetIds,
  required String auditJsonPath,
}) {
  return <String>[
    'dart',
    'run',
    'tool/fleury_dev.dart',
    'benchmark',
    'web-manual-validation',
    '--input=$manualDir',
    ..._manualTargetArgs(targetPreset: targetPreset, targetIds: targetIds),
    '--json-output=$auditJsonPath',
    '--strict',
  ];
}

List<String> _manualTargetArgs({
  required String targetPreset,
  required List<String> targetIds,
}) {
  if (targetIds.isEmpty) return ['--target-preset=$targetPreset'];
  return [for (final targetId in targetIds) '--target=$targetId'];
}

void verifyWebAutomatedValidationArtifact(
  Map<String, Object?> validation, {
  required ReadinessBundleVerificationState state,
}) {
  _expectManifestField(
    state,
    id: 'webAutomatedValidation.kind',
    expected: 'fleuryWebAutomatedValidation',
    actual: validation['kind'],
  );
  _expectManifestField(
    state,
    id: 'webAutomatedValidation.strictPass',
    expected: true,
    actual: validation['strictPass'],
  );
  _verifyWebAutomatedValidationCommandWorkingDirectory(
    validation,
    state: state,
  );

  final checks = _maps(validation['checks']);
  final browser = _checkById(checks, 'browser');
  final vm = _checkById(checks, 'vm');
  if (browser == null) {
    state.missingManifestFields.add('webAutomatedValidation.checks.browser');
  } else {
    _verifyWebAutomatedValidationCheck(
      state,
      id: 'browser',
      check: browser,
      expectedCommand: webAutomatedBrowserTestCommand(),
      expectedFiles: webAutomatedBrowserTestPaths,
    );
  }
  if (vm == null) {
    state.missingManifestFields.add('webAutomatedValidation.checks.vm');
  } else {
    _verifyWebAutomatedValidationCheck(
      state,
      id: 'vm',
      check: vm,
      expectedCommand: webAutomatedVmTestCommand(),
      expectedFiles: webAutomatedVmTestPaths,
    );
  }

  _expectManifestField(
    state,
    id: 'webAutomatedValidation.sourceInputGroup',
    expected: 'webAutomatedTestFiles',
    actual: validation['sourceInputGroup'],
  );
  _expectManifestStringListField(
    state,
    id: 'webAutomatedValidation.browserTestFiles',
    expected: webAutomatedBrowserTestPaths,
    actual: validation['browserTestFiles'],
  );
  _expectManifestStringListField(
    state,
    id: 'webAutomatedValidation.vmTestFiles',
    expected: webAutomatedVmTestPaths,
    actual: validation['vmTestFiles'],
  );
  _expectManifestStringListField(
    state,
    id: 'webAutomatedValidation.fixtureFiles',
    expected: webAutomatedFixturePaths,
    actual: validation['fixtureFiles'],
  );

  final sourceInputFingerprints = _map(validation['sourceInputFingerprints']);
  if (sourceInputFingerprints.isEmpty) {
    state.missingSourceFingerprints.add(
      'webAutomatedValidation.sourceInputFingerprints',
    );
  } else {
    verifyReadinessBundleSourceInputFingerprintValue(
      sourceInputFingerprints['webAutomatedTestFiles'],
      id: 'webAutomatedValidation.sourceInputFingerprints.webAutomatedTestFiles',
      state: state,
    );
    _verifyExpectedSourceInputFingerprintGroup(
      group:
          'webAutomatedValidation.sourceInputFingerprints.webAutomatedTestFiles',
      expected: webAutomatedTestSourceInputFingerprints(),
      actual: sourceInputFingerprints['webAutomatedTestFiles'],
      state: state,
    );
  }
}

void _verifyWebAutomatedValidationCommandWorkingDirectory(
  Map<String, Object?> validation, {
  required ReadinessBundleVerificationState state,
}) {
  final commandWorkingDirectory = validation['commandWorkingDirectory'];
  if (commandWorkingDirectory is! String ||
      commandWorkingDirectory.trim().isEmpty) {
    state.missingMetadata.add('webAutomatedValidation.commandWorkingDirectory');
    return;
  }

  state.checkedMetadataCount += 1;
  final expected = Directory.current.absolute.path;
  if (commandWorkingDirectory != expected) {
    state.metadataMismatches.add(<String, Object?>{
      'id': 'webAutomatedValidation.commandWorkingDirectory',
      'expected': expected,
      'actual': commandWorkingDirectory,
    });
  }
}

void _verifyWebAutomatedValidationCheck(
  ReadinessBundleVerificationState state, {
  required String id,
  required Map<String, Object?> check,
  required List<String> expectedCommand,
  required List<String> expectedFiles,
}) {
  _expectManifestField(
    state,
    id: 'webAutomatedValidation.checks.$id.strictPass',
    expected: true,
    actual: check['strictPass'],
  );
  _expectManifestField(
    state,
    id: 'webAutomatedValidation.checks.$id.exitCode',
    expected: 0,
    actual: check['exitCode'],
  );
  _expectManifestStringListField(
    state,
    id: 'webAutomatedValidation.checks.$id.command',
    expected: expectedCommand,
    actual: check['command'],
  );
  _expectManifestStringListField(
    state,
    id: 'webAutomatedValidation.checks.$id.testFiles',
    expected: expectedFiles,
    actual: check['testFiles'],
  );
}

Map<String, Object?>? _checkById(List<Map<String, Object?>> checks, String id) {
  for (final check in checks) {
    if (check['id'] == id) return check;
  }
  return null;
}

void _verifyArtifactStrictPass(
  ReadinessBundleVerificationState state, {
  required Map<String, Object?> artifacts,
  required Map<String, Object?> checks,
  required String artifactKey,
  required String checkKey,
}) {
  if (!artifacts.containsKey(artifactKey) && !checks.containsKey(checkKey)) {
    return;
  }
  final artifact = _readArtifactJson(artifacts[artifactKey]);
  if (artifact == null) {
    state.missingManifestFields.add('artifacts.$artifactKey.strictPass');
    return;
  }
  _expectManifestField(
    state,
    id: 'checks.$checkKey',
    expected: artifact['strictPass'] == true,
    actual: checks[checkKey],
  );
}

void _verifyDefaultPreflightManifest(
  ReadinessBundleVerificationState state, {
  required Map<String, Object?> bundle,
  required Map<String, Object?> artifacts,
  required Map<String, Object?> checks,
}) {
  final defaultPreflights = _map(artifacts['defaultPreflights']);
  if (defaultPreflights.isEmpty) return;

  final strictPassByTarget = _map(checks['defaultPreflightStrictPass']);
  final bundleBoundByTarget = _map(checks['defaultPreflightBundleBound']);
  _expectManifestField(
    state,
    id: 'checks.defaultPreflightFinalGateRequiresBundle',
    expected: true,
    actual: checks['defaultPreflightFinalGateRequiresBundle'],
  );

  final actions = _maps(bundle['remainingReleaseActions']);
  final verifyBundleAction = _releaseAction(actions, 'verify-readiness-bundle');
  if (verifyBundleAction == null) {
    state.missingManifestFields.add(
      'remainingReleaseActions.verify-readiness-bundle',
    );
  } else {
    final details = _map(verifyBundleAction['details']);
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.verify-readiness-bundle.details.verificationScope',
      expected: _readinessBundleVerificationScope,
      actual: details['verificationScope'],
    );
    final bundleJsonPath = _string(details['bundleJsonPath']);
    if (bundleJsonPath == null) {
      state.missingManifestFields.add(
        'remainingReleaseActions.verify-readiness-bundle.details.bundleJsonPath',
      );
    } else {
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.verify-readiness-bundle.commandTemplate',
        expected: <String>[
          'dart',
          'run',
          'tool/web_readiness_bundle.dart',
          '--verify=$bundleJsonPath',
          '--strict',
          '--json',
        ],
        actual: verifyBundleAction['commandTemplate'],
      );
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.verify-readiness-bundle.rootCommandTemplate',
        expected: <String>[
          'dart',
          'run',
          'tool/fleury_dev.dart',
          'benchmark',
          'web-readiness-bundle',
          '--verify=$bundleJsonPath',
          '--strict',
          '--json',
        ],
        actual: verifyBundleAction['rootCommandTemplate'],
      );
    }
  }
  final automatedTestsAction = _releaseAction(
    actions,
    'run-automated-web-host-tests',
  );
  String? automatedValidationPath;
  if (automatedTestsAction == null) {
    state.missingManifestFields.add(
      'remainingReleaseActions.run-automated-web-host-tests',
    );
  } else {
    final details = _map(automatedTestsAction['details']);
    automatedValidationPath = _string(details['automatedValidationJsonPath']);
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.sourceInputGroup',
      expected: 'webAutomatedTestFiles',
      actual: details['sourceInputGroup'],
    );
    if (automatedValidationPath == null) {
      state.missingManifestFields.add(
        'remainingReleaseActions.run-automated-web-host-tests.details.automatedValidationJsonPath',
      );
    }
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.browserTestFileCount',
      expected: webAutomatedBrowserTestPaths.length,
      actual: details['browserTestFileCount'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.vmTestFileCount',
      expected: webAutomatedVmTestPaths.length,
      actual: details['vmTestFileCount'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.fixtureFileCount',
      expected: webAutomatedFixturePaths.length,
      actual: details['fixtureFileCount'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.browserTestFiles',
      expected: webAutomatedBrowserTestPaths,
      actual: details['browserTestFiles'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.vmTestFiles',
      expected: webAutomatedVmTestPaths,
      actual: details['vmTestFiles'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.details.fixtureFiles',
      expected: webAutomatedFixturePaths,
      actual: details['fixtureFiles'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.browserTestCommand',
      expected: webAutomatedBrowserTestCommand(),
      actual: automatedTestsAction['browserTestCommand'],
    );
    _expectManifestStringListField(
      state,
      id: 'remainingReleaseActions.run-automated-web-host-tests.vmTestCommand',
      expected: webAutomatedVmTestCommand(),
      actual: automatedTestsAction['vmTestCommand'],
    );
    if (automatedValidationPath != null) {
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.run-automated-web-host-tests.commandTemplate',
        expected: <String>[
          'dart',
          'run',
          'tool/web_automated_validation.dart',
          '--json-output=$automatedValidationPath',
          '--strict',
          '--json',
        ],
        actual: automatedTestsAction['commandTemplate'],
      );
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.run-automated-web-host-tests.rootCommandTemplate',
        expected: <String>[
          'dart',
          'run',
          'tool/fleury_dev.dart',
          'benchmark',
          'web-automated-validation',
          '--json-output=$automatedValidationPath',
          '--strict',
          '--json',
        ],
        actual: automatedTestsAction['rootCommandTemplate'],
      );
    }
  }
  for (final entry in defaultPreflights.entries) {
    final targetId = entry.key;
    final preflightArtifacts = _map(entry.value);
    final preflight = _readArtifactJson(preflightArtifacts['json']);
    if (preflight == null) {
      state.missingManifestFields.add(
        'artifacts.defaultPreflights.$targetId.json.strictPass',
      );
      continue;
    }
    final previewStrictPass = preflight['strictPass'] == true;
    final previewBundleBound = preflight['bundlePath'] is String;
    final previewDiagnosticOnly = preflight['diagnosticOnly'] == true;
    final previewAutomatedValidationBound =
        preflight['automatedValidationPath'] is String;
    _expectManifestField(
      state,
      id: 'checks.defaultPreflightStrictPass.$targetId',
      expected: previewStrictPass,
      actual: strictPassByTarget[targetId],
    );
    _expectManifestField(
      state,
      id: 'checks.defaultPreflightBundleBound.$targetId',
      expected: previewBundleBound,
      actual: bundleBoundByTarget[targetId],
    );
    _expectManifestField(
      state,
      id: 'artifacts.defaultPreflights.$targetId.json.diagnosticOnly',
      expected: true,
      actual: preflight['diagnosticOnly'],
    );
    _expectManifestField(
      state,
      id: 'artifacts.defaultPreflights.$targetId.json.finalGateRequiresBundle',
      expected: true,
      actual: preflight['finalGateRequiresBundle'],
    );
    _expectManifestField(
      state,
      id: 'artifacts.defaultPreflights.$targetId.json.finalGateRequiresAutomatedValidation',
      expected: true,
      actual: preflight['finalGateRequiresAutomatedValidation'],
    );
    _expectManifestField(
      state,
      id: 'artifacts.defaultPreflights.$targetId.json.finalGateBundlePath',
      expected: artifacts['bundleJson'],
      actual: preflight['finalGateBundlePath'],
    );
    _expectManifestField(
      state,
      id: 'artifacts.defaultPreflights.$targetId.json.bundleRequired',
      expected: false,
      actual: preflight['bundleRequired'],
    );
    _expectManifestField(
      state,
      id: 'artifacts.defaultPreflights.$targetId.json.bundleBound',
      expected: false,
      actual: preflight['bundleBound'],
    );

    final action = _releaseAction(actions, 'run-default-preflight:$targetId');
    if (action == null) {
      state.missingManifestFields.add(
        'remainingReleaseActions.run-default-preflight:$targetId',
      );
      continue;
    }
    final details = _map(action['details']);
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-default-preflight:$targetId.details.generatedPreviewStrictPass',
      expected: previewStrictPass,
      actual: details['generatedPreviewStrictPass'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-default-preflight:$targetId.details.generatedPreviewBundleBound',
      expected: previewBundleBound,
      actual: details['generatedPreviewBundleBound'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-default-preflight:$targetId.details.generatedPreviewDiagnosticOnly',
      expected: previewDiagnosticOnly,
      actual: details['generatedPreviewDiagnosticOnly'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-default-preflight:$targetId.details.requiresBundleBinding',
      expected: true,
      actual: details['requiresBundleBinding'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-default-preflight:$targetId.details.readinessJsonPath',
      expected: artifacts['readinessJson'],
      actual: details['readinessJsonPath'],
    );
    _expectManifestField(
      state,
      id: 'remainingReleaseActions.run-default-preflight:$targetId.details.bundleJsonPath',
      expected: artifacts['bundleJson'],
      actual: details['bundleJsonPath'],
    );
    final preflightAutomatedValidationPath = _string(
      details['automatedValidationJsonPath'],
    );
    if (preflightAutomatedValidationPath == null) {
      state.missingManifestFields.add(
        'remainingReleaseActions.run-default-preflight:$targetId.details.automatedValidationJsonPath',
      );
    } else {
      if (automatedValidationPath != null) {
        _expectManifestField(
          state,
          id: 'remainingReleaseActions.run-default-preflight:$targetId.details.automatedValidationJsonPath',
          expected: automatedValidationPath,
          actual: preflightAutomatedValidationPath,
        );
      }
      _expectManifestField(
        state,
        id: 'artifacts.defaultPreflights.$targetId.json.finalGateAutomatedValidationPath',
        expected: preflightAutomatedValidationPath,
        actual: preflight['finalGateAutomatedValidationPath'],
      );
      _expectManifestField(
        state,
        id: 'artifacts.defaultPreflights.$targetId.json.automatedValidationRequired',
        expected: false,
        actual: preflight['automatedValidationRequired'],
      );
      _expectManifestField(
        state,
        id: 'artifacts.defaultPreflights.$targetId.json.automatedValidationBound',
        expected: previewAutomatedValidationBound,
        actual: preflight['automatedValidationBound'],
      );
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.run-default-preflight:$targetId.commandTemplate',
        expected: <String>[
          'dart',
          'run',
          'tool/web_default_preflight.dart',
          '--readiness=${artifacts['readinessJson']}',
          '--bundle=${artifacts['bundleJson']}',
          '--automated-validation=$preflightAutomatedValidationPath',
          '--target=$targetId',
          '--strict',
          '--json',
        ],
        actual: action['commandTemplate'],
      );
      _expectManifestStringListField(
        state,
        id: 'remainingReleaseActions.run-default-preflight:$targetId.rootCommandTemplate',
        expected: <String>[
          'dart',
          'run',
          'tool/fleury_dev.dart',
          'benchmark',
          'web-default-preflight',
          '--readiness=${artifacts['readinessJson']}',
          '--bundle=${artifacts['bundleJson']}',
          '--automated-validation=$preflightAutomatedValidationPath',
          '--target=$targetId',
          '--strict',
          '--json',
        ],
        actual: action['rootCommandTemplate'],
      );
    }
  }
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

void _expectManifestField(
  ReadinessBundleVerificationState state, {
  required String id,
  required Object? expected,
  required Object? actual,
}) {
  if (actual == null) {
    state.missingManifestFields.add(id);
    return;
  }
  state.checkedManifestFieldCount += 1;
  if (actual != expected) {
    state.manifestMismatches.add(<String, Object?>{
      'id': id,
      'expected': expected,
      'actual': actual,
    });
  }
}

void _expectManifestStringListField(
  ReadinessBundleVerificationState state, {
  required String id,
  required List<String> expected,
  required Object? actual,
}) {
  if (actual == null) {
    state.missingManifestFields.add(id);
    return;
  }
  state.checkedManifestFieldCount += 1;
  final actualStrings = _strings(actual);
  if (!_sameStringList(actualStrings, expected)) {
    state.manifestMismatches.add(<String, Object?>{
      'id': id,
      'expected': expected,
      'actual': actualStrings,
    });
  }
}

bool _sameStringList(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < expected.length; index += 1) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

Map<String, Object?>? _readArtifactJson(Object? rawPath) {
  if (rawPath is! String || rawPath.trim().isEmpty) return null;
  final file = File(rawPath);
  if (!file.existsSync()) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) return decoded.cast<String, Object?>();
  return null;
}

Map<String, Object?> _map(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) return raw.cast<String, Object?>();
  return const <String, Object?>{};
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

List<Map<String, Object?>> _captureInputFingerprints(String captureDir) {
  final root = Directory(captureDir);
  if (!root.existsSync()) return const <Map<String, Object?>>[];
  final entries = <Map<String, Object?>>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    if (_jsonKind(entity) != 'fleuryWebFrameCapture') continue;
    entries.add(_sourceInputFingerprint(entity));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _manualEvidenceInputFingerprints(
  String manualDir, {
  required List<String> targetIds,
}) {
  final root = Directory(manualDir);
  if (!root.existsSync()) return const <Map<String, Object?>>[];
  final selectedTargets = targetIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty);
  final selectedTargetSet = selectedTargets.toSet();
  final entries = <Map<String, Object?>>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final name = _basename(entity.path);
    if (name.endsWith('.template.json')) continue;
    if (name == 'manual-validation-audit.json') continue;
    if (selectedTargetSet.isNotEmpty) {
      final targetId = _manualEvidenceTargetId(entity);
      if (targetId == null || !selectedTargetSet.contains(targetId)) continue;
    }
    entries.add(_sourceInputFingerprint(entity));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

String? _manualEvidenceTargetId(File file) {
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['kind']?.toString() != 'fleuryWebManualValidationEntry') {
    return null;
  }
  return decoded['targetId']?.toString();
}

List<Map<String, Object?>> _manualTemplateInputFingerprints(
  String manualDir, {
  required List<String> targetIds,
}) {
  final entries = <Map<String, Object?>>[];
  for (final targetId in targetIds) {
    final file = File(
      _joinPath(_joinPath(manualDir, 'templates'), '$targetId.template.json'),
    );
    if (!file.existsSync()) continue;
    entries.add(_sourceInputFingerprint(file));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _manualValidationPageInputFingerprints() {
  const paths = <String>[
    'web/manual_validation.dart',
    'web/manual_validation.html',
    'web/manual_validation.dart.js',
    'test/manual_validation_page_test.dart',
  ];
  final entries = <Map<String, Object?>>[];
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    entries.add(_sourceInputFingerprint(file));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _webImplementationInputFingerprints() {
  final entries = <Map<String, Object?>>[];
  final barrel = File('lib/fleury_web.dart');
  if (barrel.existsSync()) {
    entries.add(_sourceInputFingerprint(barrel));
  }
  final srcRoot = Directory('lib/src');
  if (srcRoot.existsSync()) {
    for (final entity in srcRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      entries.add(_sourceInputFingerprint(entity));
    }
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _webAutomatedTestInputFingerprints() {
  final entries = <Map<String, Object?>>[];
  for (final path in webAutomatedTestSourceInputPaths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    entries.add(_sourceInputFingerprint(file));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _packageImplementationInputFingerprints(
  String packageName,
) {
  final libDir = _packageLibDirectory(packageName);
  if (libDir == null || !libDir.existsSync()) {
    return const <Map<String, Object?>>[];
  }
  final entries = <Map<String, Object?>>[];
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    entries.add(_sourceInputFingerprint(entity));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _readinessToolInputFingerprints() {
  final toolDir = Directory('tool');
  if (!toolDir.existsSync()) return const <Map<String, Object?>>[];
  final entries = <Map<String, Object?>>[];
  for (final entity in toolDir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    entries.add(_sourceInputFingerprint(entity));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _rootReleaseLauncherInputFingerprints() {
  final entries = <Map<String, Object?>>[];
  for (final path in const <String>['tool/fleury_dev.dart']) {
    final file = File.fromUri(
      Directory.current.absolute.uri.resolve('../../$path'),
    );
    if (!file.existsSync()) continue;
    entries.add(_sourceInputFingerprint(file));
  }
  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

List<Map<String, Object?>> _packageConfigurationInputFingerprints() {
  final entries = <Map<String, Object?>>[];
  void addConfigFiles(Directory packageRoot) {
    for (final path in const <String>[
      'pubspec.yaml',
      'pubspec.lock',
      '.dart_tool/package_config.json',
    ]) {
      final file = File.fromUri(packageRoot.absolute.uri.resolve(path));
      if (!file.existsSync()) continue;
      entries.add(_sourceInputFingerprint(file));
    }
  }

  addConfigFiles(Directory.current);
  final fleuryRoot = _packageRootDirectory('fleury');
  if (fleuryRoot != null) addConfigFiles(fleuryRoot);

  entries.sort((a, b) => a['path'].toString().compareTo(b['path'].toString()));
  return entries;
}

Directory? _packageLibDirectory(String packageName) {
  final packageRoot = _packageRootDirectory(packageName);
  if (packageRoot == null) return null;
  final packageUri = _packageUri(packageName);
  if (packageUri == null) return null;
  return Directory.fromUri(
    packageRoot.uri.resolve(_directoryUriString(packageUri)),
  );
}

Directory? _packageRootDirectory(String packageName) {
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) return null;
  try {
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
    final configDir = configFile.absolute.parent.uri;
    final rootUriValue = config['configVersion'] == 2
        ? _packageRootUri(packageName, config)
        : null;
    if (rootUriValue == null) return null;
    final rootUri = configDir.resolve(_directoryUriString(rootUriValue));
    return Directory.fromUri(rootUri);
  } catch (_) {
    return null;
  }
}

String? _packageRootUri(String packageName, Map<String, Object?> config) {
  final packages = config['packages'];
  if (packages is! List) return null;
  for (final package in packages) {
    if (package is! Map) continue;
    if (package['name'] != packageName) continue;
    final rootUri = package['rootUri'];
    return rootUri is String ? rootUri : null;
  }
  return null;
}

String? _packageUri(String packageName) {
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) return null;
  try {
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
    final packages = config['packages'];
    if (packages is! List) return null;
    for (final package in packages) {
      if (package is! Map) continue;
      if (package['name'] != packageName) continue;
      final packageUriValue = package['packageUri'];
      if (packageUriValue is! String) return null;
      return packageUriValue;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _directoryUriString(String uri) => uri.endsWith('/') ? uri : '$uri/';

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

void _verifyManualEvidenceLatestEntryFingerprints(
  ReadinessBundleVerificationState state, {
  required List<Map<String, Object?>> targets,
  required Map<String, Object?> sourceInputFingerprints,
  required String idPrefix,
}) {
  final expectedByPath = <String, String>{};
  for (final entry in _sourceFingerprintEntries(
    sourceInputFingerprints['manualEvidenceFiles'],
  )) {
    final path = _string(entry['path']);
    if (path == null) continue;
    final fingerprint = _manualEvidenceJsonFingerprint(path);
    if (fingerprint == null) continue;
    expectedByPath[path] = fingerprint;
  }
  for (final target in targets) {
    final path = _string(target['latestEntryPath']);
    if (path == null) continue;
    final expected = expectedByPath[path];
    if (expected == null) continue;
    final targetId = _string(target['id']) ?? _basename(path);
    final actual = _string(target['latestEntryFingerprint']);
    final id = '$idPrefix.$targetId.latestEntryFingerprint';
    if (actual == null) {
      state.missingManifestFields.add(id);
      continue;
    }
    state.checkedManifestFieldCount += 1;
    if (actual != expected) {
      state.manifestMismatches.add(<String, Object?>{
        'id': id,
        'path': path,
        'expected': expected,
        'actual': actual,
      });
    }
  }
}

List<String> _expectedManualTargetIds(Map<String, Object?> input) {
  final explicitTargetIds = _strings(
    input['targetIds'],
  ).map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
  if (explicitTargetIds.isNotEmpty) return explicitTargetIds;
  return manualValidationTargetIdsForPreset(
        _string(input['targetPreset']) ?? 'primary',
      ) ??
      const <String>[];
}

Map<String, Object?>? _optionalSourceInputFingerprint(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  return _sourceInputFingerprint(file);
}

Map<String, Object?> _sourceInputFingerprint(File file) {
  return <String, Object?>{
    'path': file.absolute.path,
    'fingerprint': readinessFileFingerprint(file.path),
  };
}

String? _jsonKind(File file) {
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  return decoded['kind']?.toString();
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash == -1 ? normalized : normalized.substring(slash + 1);
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

String? _thresholdReviewPlanPath(String? reviewedThresholdOutputPath) {
  if (reviewedThresholdOutputPath == null ||
      reviewedThresholdOutputPath.trim().isEmpty) {
    return null;
  }
  return '${File(reviewedThresholdOutputPath).parent.path}${Platform.pathSeparator}threshold-review-plan.md';
}

String _joinPath(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
  return '$parent${Platform.pathSeparator}$child';
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final item in raw) item.toString()];
}

String? _string(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

String readinessFileFingerprint(String path) {
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in File(path).readAsBytesSync()) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
}

String? _manualEvidenceJsonFingerprint(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (decoded is Map<String, Object?>) return _jsonFingerprint(decoded);
  if (decoded is Map) return _jsonFingerprint(decoded.cast<String, Object?>());
  return null;
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
  if (value is List) return [for (final item in value) _canonicalizeJson(item)];
  return value;
}
