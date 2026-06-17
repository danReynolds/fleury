import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final audit = _buildAudit(options);
  final auditJson = const JsonEncoder.withIndent('  ').convert(audit);
  if (options.jsonOutputPath != null) {
    final output = File(options.jsonOutputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$auditJson\n');
  }
  if (options.json) {
    stdout.writeln(auditJson);
  }

  final markdown = _markdown(audit);
  if (options.outputPath == null) {
    if (!options.json) stdout.write(markdown);
  } else {
    final output = File(options.outputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(markdown);
    stdout.writeln('wrote ${output.path}');
  }

  if (options.strict && audit['strictPass'] != true) exit(1);
}

Map<String, Object?> _buildAudit(_Options options) {
  final checks = <_ReadinessCheck>[
    _scoreboardCheck(options),
    _semanticAuditCheck(options),
    _manualAuditCheck(options),
  ];
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebReadinessAudit',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'strictPass': checks.every((check) => check.strictPass),
    'checks': [for (final check in checks) check.toJson()],
  };
}

_ReadinessCheck _scoreboardCheck(_Options options) {
  final loaded = _loadJson(
    options.scoreboardPath,
    expectedKind: 'fleuryWebFrameScoreboard',
  );
  if (loaded.failure != null) return loaded.failure!;
  final json = loaded.json!;
  final blockers = <String>[];
  if (json['strictPass'] != true) {
    blockers.add('frame scoreboard strictPass is not true');
  }
  final scenarioCount = _int(json, 'scenarioCount');
  final runCount = _int(json, 'runCount');
  if (scenarioCount <= 0) blockers.add('frame scoreboard has no scenarios');
  if (runCount <= 0) blockers.add('frame scoreboard has no captures');
  final minRuns = _int(json, 'minRuns');
  if (minRuns < options.minScoreboardRuns) {
    blockers.add(
      'frame scoreboard minRuns $minRuns is below required ${options.minScoreboardRuns}',
    );
  }
  if (options.requireComparableEnvironment &&
      json['requireComparableRunEnvironment'] != true) {
    blockers.add('frame scoreboard did not require comparable environments');
  }
  final scenarios = _maps(json['scenarios']);
  final failingScenarios = [
    for (final scenario in scenarios)
      if (scenario['strictPass'] != true) scenario['id']?.toString() ?? '?',
  ];
  if (failingScenarios.isNotEmpty) {
    blockers.add('failing frame scenarios: ${failingScenarios.join(', ')}');
  }
  if (options.requireComparableEnvironment) {
    final incomparable = [
      for (final scenario in scenarios)
        if (scenario['runEnvironmentComparable'] != true)
          scenario['id']?.toString() ?? '?',
    ];
    if (incomparable.isNotEmpty) {
      blockers.add(
        'incomparable frame scenario environments: ${incomparable.join(', ')}',
      );
    }
  }
  if (options.requireScoreboardGates) {
    final missingGates = [
      for (final scenario in scenarios)
        if (_maps(scenario['gates']).isEmpty) scenario['id']?.toString() ?? '?',
    ];
    if (missingGates.isNotEmpty) {
      blockers.add(
        'frame scenarios missing threshold gates: ${missingGates.join(', ')}',
      );
    }
  }
  if (options.requireTotalFrameGate) {
    final missingTotalFrameGate = [
      for (final scenario in scenarios)
        if (!_hasGate(scenario, 'totalFrameP95MedianMs'))
          scenario['id']?.toString() ?? '?',
    ];
    if (missingTotalFrameGate.isNotEmpty) {
      blockers.add(
        'frame scenarios missing total-frame p95 gate: ${missingTotalFrameGate.join(', ')}',
      );
    }
  }
  final thresholdPolicyPath = json['thresholdPolicyPath']?.toString();
  final reviewState = json['thresholdPolicyReviewState']?.toString();
  if (options.requireReviewedThresholdPolicy) {
    if (thresholdPolicyPath == null) {
      blockers.add('frame scoreboard did not use a threshold policy');
    } else if (reviewState != 'reviewed') {
      blockers.add(
        'frame scoreboard threshold policy reviewState is ${reviewState ?? '<missing>'}; expected reviewed',
      );
    } else {
      final reviewedBy = json['thresholdPolicyReviewedBy']?.toString().trim();
      final reviewedAt = json['thresholdPolicyReviewedAt']?.toString().trim();
      final reviewContext = json['thresholdPolicyReviewContext']
          ?.toString()
          .trim();
      if (reviewedBy == null || reviewedBy.isEmpty) {
        blockers.add('frame scoreboard threshold policy reviewedBy is missing');
      }
      if (reviewedAt == null || reviewedAt.isEmpty) {
        blockers.add('frame scoreboard threshold policy reviewedAt is missing');
      }
      if (reviewContext == null || reviewContext.isEmpty) {
        blockers.add(
          'frame scoreboard threshold policy reviewContext is missing',
        );
      }
      final policyFingerprint = json['thresholdPolicyFingerprint']
          ?.toString()
          .trim();
      if (policyFingerprint == null || policyFingerprint.isEmpty) {
        blockers.add(
          'frame scoreboard threshold policy fingerprint is missing',
        );
      }
    }
  }
  final thresholdReviewPath =
      options.thresholdReviewPath ??
      _defaultThresholdReviewPath(thresholdPolicyPath);
  if (options.requireReviewedThresholdPolicy &&
      options.requireThresholdReviewSummary &&
      reviewState == 'reviewed' &&
      thresholdPolicyPath != null) {
    blockers.addAll(
      _thresholdReviewSummaryBlockers(
        path: thresholdReviewPath,
        thresholdPolicyPath: thresholdPolicyPath,
        scoreboard: json,
        scenarioCount: scenarioCount,
      ),
    );
  }
  final missingScenarioThresholdPolicy = [
    if (options.requireScenarioThresholds &&
        json['thresholdPolicyPath'] != null)
      for (final scenario in scenarios)
        if (scenario['thresholdPolicyMatchedScenario'] != true)
          scenario['id']?.toString() ?? '?',
  ];
  if (missingScenarioThresholdPolicy.isNotEmpty) {
    blockers.add(
      'frame scenarios missing scenario-specific threshold policy: ${missingScenarioThresholdPolicy.join(', ')}',
    );
  }
  return _ReadinessCheck(
    id: 'frameScoreboard',
    label: 'Frame performance scoreboard',
    path: options.scoreboardPath,
    strictPass: blockers.isEmpty,
    blockers: blockers,
    details: <String, Object?>{
      'scenarioCount': scenarioCount,
      'runCount': runCount,
      'minRuns': minRuns,
      'requireComparableRunEnvironment':
          json['requireComparableRunEnvironment'] == true,
      if (json['thresholdPolicyPath'] != null)
        'thresholdPolicyPath': json['thresholdPolicyPath'],
      if (json['thresholdPolicyReviewState'] != null)
        'thresholdPolicyReviewState': json['thresholdPolicyReviewState'],
      if (json['thresholdPolicyReviewedBy'] != null)
        'thresholdPolicyReviewedBy': json['thresholdPolicyReviewedBy'],
      if (json['thresholdPolicyReviewedAt'] != null)
        'thresholdPolicyReviewedAt': json['thresholdPolicyReviewedAt'],
      if (json['thresholdPolicyReviewContext'] != null)
        'thresholdPolicyReviewContext': json['thresholdPolicyReviewContext'],
      if (json['thresholdPolicyFingerprint'] != null)
        'thresholdPolicyFingerprint': json['thresholdPolicyFingerprint'],
      if (json['thresholdPolicyScenarioCount'] != null)
        'thresholdPolicyScenarioCount': json['thresholdPolicyScenarioCount'],
      if (thresholdReviewPath != null)
        'thresholdReviewPath': thresholdReviewPath,
      if (missingScenarioThresholdPolicy.isNotEmpty)
        'missingScenarioThresholdPolicy': missingScenarioThresholdPolicy,
    },
  );
}

List<String> _thresholdReviewSummaryBlockers({
  required String? path,
  required String thresholdPolicyPath,
  required Map<String, Object?> scoreboard,
  required int scenarioCount,
}) {
  if (path == null || path.trim().isEmpty) {
    return const ['threshold review summary path is missing'];
  }
  final loaded = _loadJsonArtifact(
    path,
    expectedKind: 'fleuryWebThresholdReview',
  );
  if (loaded.failure != null) {
    return [
      for (final blocker in loaded.failure!)
        'threshold review summary: $blocker',
    ];
  }
  final review = loaded.json!;
  final blockers = <String>[];
  if (review['reviewState'] != 'reviewed') {
    blockers.add(
      'threshold review summary reviewState is ${review['reviewState'] ?? '<missing>'}; expected reviewed',
    );
  }
  _addThresholdReviewInputProvenanceBlockers(blockers, review);
  final outputPath = review['outputPath']?.toString().trim();
  if (outputPath == null || outputPath.isEmpty) {
    blockers.add('threshold review summary outputPath is missing');
  } else if (!_samePath(outputPath, thresholdPolicyPath)) {
    blockers.add(
      'threshold review summary outputPath does not match threshold policy path',
    );
  }
  _addMatchingFieldBlocker(
    blockers,
    review,
    scoreboard,
    reviewField: 'reviewedBy',
    scoreboardField: 'thresholdPolicyReviewedBy',
    label: 'reviewedBy',
  );
  _addMatchingFieldBlocker(
    blockers,
    review,
    scoreboard,
    reviewField: 'reviewedAt',
    scoreboardField: 'thresholdPolicyReviewedAt',
    label: 'reviewedAt',
  );
  _addMatchingFieldBlocker(
    blockers,
    review,
    scoreboard,
    reviewField: 'reviewContext',
    scoreboardField: 'thresholdPolicyReviewContext',
    label: 'reviewContext',
  );
  final reviewScenarioCount = _int(review, 'scenarioCount');
  if (reviewScenarioCount != scenarioCount) {
    blockers.add(
      'threshold review summary scenarioCount $reviewScenarioCount does not match frame scoreboard scenarioCount $scenarioCount',
    );
  }
  final reviewOutputFingerprint = review['outputPolicyFingerprint']
      ?.toString()
      .trim();
  final scoreboardPolicyFingerprint = scoreboard['thresholdPolicyFingerprint']
      ?.toString()
      .trim();
  if (reviewOutputFingerprint == null || reviewOutputFingerprint.isEmpty) {
    blockers.add('threshold review summary outputPolicyFingerprint is missing');
  } else if (scoreboardPolicyFingerprint == null ||
      scoreboardPolicyFingerprint.isEmpty) {
    blockers.add('frame scoreboard threshold policy fingerprint is missing');
  } else if (reviewOutputFingerprint != scoreboardPolicyFingerprint) {
    blockers.add(
      'threshold review summary outputPolicyFingerprint does not match frame scoreboard threshold policy',
    );
  }
  return blockers;
}

void _addThresholdReviewInputProvenanceBlockers(
  List<String> blockers,
  Map<String, Object?> review,
) {
  final inputPath = review['inputPath']?.toString().trim();
  final inputPolicyFingerprint = review['inputPolicyFingerprint']
      ?.toString()
      .trim();
  if (inputPath == null || inputPath.isEmpty) {
    blockers.add('threshold review summary inputPath is missing');
  }
  if (inputPolicyFingerprint == null || inputPolicyFingerprint.isEmpty) {
    blockers.add('threshold review summary inputPolicyFingerprint is missing');
  }
  if (inputPath == null ||
      inputPath.isEmpty ||
      inputPolicyFingerprint == null ||
      inputPolicyFingerprint.isEmpty) {
    return;
  }

  final loadedInput = _loadJsonArtifact(
    inputPath,
    expectedKind: 'fleuryWebFrameThresholds',
  );
  if (loadedInput.failure != null) {
    for (final blocker in loadedInput.failure!) {
      blockers.add('threshold review summary input policy: $blocker');
    }
    return;
  }

  final inputPolicy = loadedInput.json!;
  final inputReviewState = inputPolicy['reviewState'];
  if (inputReviewState == 'reviewed') {
    blockers.add(
      'threshold review summary input policy reviewState is reviewed; expected candidate',
    );
  }
  final actualInputFingerprint = _jsonFingerprint(inputPolicy);
  if (actualInputFingerprint != inputPolicyFingerprint) {
    blockers.add(
      'threshold review summary inputPolicyFingerprint does not match inputPath policy',
    );
  }
}

void _addMatchingFieldBlocker(
  List<String> blockers,
  Map<String, Object?> review,
  Map<String, Object?> scoreboard, {
  required String reviewField,
  required String scoreboardField,
  required String label,
}) {
  final reviewValue = review[reviewField]?.toString().trim();
  final scoreboardValue = scoreboard[scoreboardField]?.toString().trim();
  if (reviewValue == null || reviewValue.isEmpty) {
    blockers.add('threshold review summary $label is missing');
  } else if (scoreboardValue != null &&
      scoreboardValue.isNotEmpty &&
      reviewValue != scoreboardValue) {
    blockers.add(
      'threshold review summary $label does not match frame scoreboard threshold policy',
    );
  }
}

String? _defaultThresholdReviewPath(String? thresholdPolicyPath) {
  if (thresholdPolicyPath == null || thresholdPolicyPath.trim().isEmpty) {
    return null;
  }
  return '${File(thresholdPolicyPath).parent.path}${Platform.pathSeparator}threshold-review.json';
}

bool _samePath(String left, String right) =>
    File(left).absolute.path == File(right).absolute.path;

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

_ReadinessCheck _semanticAuditCheck(_Options options) {
  final loaded = _loadJson(
    options.semanticAuditPath,
    expectedKind: 'fleuryWebSemanticCoverageAudit',
  );
  if (loaded.failure != null) return loaded.failure!;
  final json = loaded.json!;
  final blockers = <String>[];
  if (json['strictPass'] != true) {
    blockers.add('semantic coverage audit strictPass is not true');
  }
  final scenarioCount = _int(json, 'scenarioCount');
  final captureCount = _int(json, 'captureCount');
  final frameCount = _int(json, 'frameCount');
  if (scenarioCount <= 0) blockers.add('semantic audit has no scenarios');
  if (captureCount <= 0) blockers.add('semantic audit has no captures');
  if (frameCount <= 0) blockers.add('semantic audit has no frames');
  if (options.requireSemanticGates && _maps(json['gates']).isEmpty) {
    blockers.add('semantic audit has no fallback threshold gates');
  }
  final failingScenarios = [
    for (final scenario in _maps(json['scenarios']))
      if (scenario['strictPass'] != true) scenario['id']?.toString() ?? '?',
  ];
  if (failingScenarios.isNotEmpty) {
    blockers.add('failing semantic scenarios: ${failingScenarios.join(', ')}');
  }
  return _ReadinessCheck(
    id: 'semanticCoverage',
    label: 'Semantic coverage audit',
    path: options.semanticAuditPath,
    strictPass: blockers.isEmpty,
    blockers: blockers,
    details: <String, Object?>{
      'scenarioCount': scenarioCount,
      'captureCount': captureCount,
      'frameCount': frameCount,
      'fallbackCellCount': _int(json, 'fallbackCellCount'),
      'fallbackNodeCount': _int(json, 'fallbackNodeCount'),
      if (_maps(json['topFallbackCaptures']).isNotEmpty)
        'topFallbackCaptures': _maps(json['topFallbackCaptures']),
    },
  );
}

_ReadinessCheck _manualAuditCheck(_Options options) {
  final loaded = _loadJson(
    options.manualAuditPath,
    expectedKind: 'fleuryWebManualValidationAudit',
  );
  if (loaded.failure != null) return loaded.failure!;
  final json = loaded.json!;
  final blockers = <String>[];
  if (json['strictPass'] != true) {
    blockers.add('manual validation audit strictPass is not true');
  }
  final targetCount = _int(json, 'targetCount');
  final passedTargetCount = _int(json, 'passedTargetCount');
  final invalidEntryCount = _int(json, 'invalidEntryCount');
  if (invalidEntryCount > 0) {
    blockers.add(
      'manual validation audit has $invalidEntryCount invalid evidence file(s)',
    );
  }
  if (passedTargetCount != targetCount) {
    blockers.add(
      'manual validation passed $passedTargetCount of $targetCount targets',
    );
  }
  final manualTargetLists = <String, List<String>>{};
  for (final key in const [
    'missingTargets',
    'failedTargets',
    'blockedTargets',
    'needsReviewTargets',
  ]) {
    final targets = _strings(json[key]);
    manualTargetLists[key] = targets;
    if (targets.isNotEmpty) {
      blockers.add('$key: ${targets.join(', ')}');
    }
  }
  final provenanceBlockers = <String, List<String>>{};
  final failingTargets = [
    for (final target in _maps(json['targets']))
      if (target['strictPass'] != true) target,
  ];
  final manualEvidenceDetails = [
    for (final target in _maps(json['targets']))
      if (target['latestEntryFingerprint'] != null)
        _manualEvidenceDetails(target),
  ];
  final failingTargetDetails = [
    for (final target in failingTargets) _manualTargetDetails(target),
  ];
  for (final target in failingTargets) {
    final targetId = target['id']?.toString() ?? '?';
    final targetBlockers = _strings(target['provenanceBlockers']);
    if (targetBlockers.isNotEmpty) {
      provenanceBlockers[targetId] = targetBlockers;
    }
  }
  if (provenanceBlockers.isNotEmpty) {
    blockers.add(
      'manual evidence provenance blockers: ${_formatTargetBlockers(provenanceBlockers)}',
    );
  }
  final failingTargetIds = [
    for (final target in failingTargets) target['id']?.toString() ?? '?',
  ];
  if (failingTargetIds.isNotEmpty) {
    blockers.add('failing manual targets: ${failingTargetIds.join(', ')}');
  }
  return _ReadinessCheck(
    id: 'manualValidation',
    label: 'Manual browser validation',
    path: options.manualAuditPath,
    strictPass: blockers.isEmpty,
    blockers: blockers,
    details: <String, Object?>{
      'targetCount': targetCount,
      'passedTargetCount': passedTargetCount,
      'entryCount': _int(json, 'entryCount'),
      'invalidEntryCount': invalidEntryCount,
      if (_maps(json['invalidEntries']).isNotEmpty)
        'invalidEntries': _maps(json['invalidEntries']),
      for (final entry in manualTargetLists.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
      if (provenanceBlockers.isNotEmpty)
        'provenanceBlockers': provenanceBlockers,
      if (manualEvidenceDetails.isNotEmpty)
        'manualEvidence': manualEvidenceDetails,
      if (failingTargetDetails.isNotEmpty)
        'failingTargetDetails': failingTargetDetails,
    },
  );
}

Map<String, Object?> _manualEvidenceDetails(Map<String, Object?> target) {
  return <String, Object?>{
    'id': target['id']?.toString() ?? '?',
    if (target['latestEntryFile'] != null)
      'latestEntryFile': target['latestEntryFile'],
    if (target['latestEntryPath'] != null)
      'latestEntryPath': target['latestEntryPath'],
    if (target['latestEntryFingerprint'] != null)
      'latestEntryFingerprint': target['latestEntryFingerprint'],
    if (target['latestCapturedAt'] != null)
      'latestCapturedAt': target['latestCapturedAt'],
    if (target['reviewedBy'] != null) 'reviewedBy': target['reviewedBy'],
  };
}

Map<String, Object?> _manualTargetDetails(Map<String, Object?> target) {
  return <String, Object?>{
    'id': target['id']?.toString() ?? '?',
    if (target['status'] != null) 'status': target['status'],
    'strictPass': target['strictPass'] == true,
    'requiredCheckCount': _int(target, 'requiredCheckCount'),
    'passedRequiredCheckCount': _int(target, 'passedRequiredCheckCount'),
    if (_strings(target['missingCheckIds']).isNotEmpty)
      'missingCheckIds': _strings(target['missingCheckIds']),
    if (_strings(target['failedCheckIds']).isNotEmpty)
      'failedCheckIds': _strings(target['failedCheckIds']),
    if (_strings(target['blockedCheckIds']).isNotEmpty)
      'blockedCheckIds': _strings(target['blockedCheckIds']),
    if (_strings(target['provenanceBlockers']).isNotEmpty)
      'provenanceBlockers': _strings(target['provenanceBlockers']),
  };
}

String _formatTargetBlockers(Map<String, List<String>> blockersByTarget) {
  return blockersByTarget.entries
      .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
      .join('; ');
}

_LoadedJson _loadJson(String path, {required String expectedKind}) {
  final file = File(path);
  if (!file.existsSync()) {
    return _LoadedJson.failure(
      _ReadinessCheck(
        id: _checkIdForKind(expectedKind),
        label: _checkLabelForKind(expectedKind),
        path: path,
        strictPass: false,
        blockers: ['missing artifact'],
        details: const <String, Object?>{},
      ),
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return _LoadedJson.failure(
      _ReadinessCheck(
        id: _checkIdForKind(expectedKind),
        label: _checkLabelForKind(expectedKind),
        path: path,
        strictPass: false,
        blockers: ['invalid JSON: ${error.message}'],
        details: const <String, Object?>{},
      ),
    );
  }
  if (decoded is! Map) {
    return _LoadedJson.failure(
      _ReadinessCheck(
        id: _checkIdForKind(expectedKind),
        label: _checkLabelForKind(expectedKind),
        path: path,
        strictPass: false,
        blockers: ['artifact is not a JSON object'],
        details: const <String, Object?>{},
      ),
    );
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != expectedKind) {
    return _LoadedJson.failure(
      _ReadinessCheck(
        id: _checkIdForKind(expectedKind),
        label: _checkLabelForKind(expectedKind),
        path: path,
        strictPass: false,
        blockers: [
          'unexpected artifact kind ${json['kind'] ?? '<missing>'}; expected $expectedKind',
        ],
        details: const <String, Object?>{},
      ),
    );
  }
  return _LoadedJson.success(json);
}

_LoadedJsonArtifact _loadJsonArtifact(
  String path, {
  required String expectedKind,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    return const _LoadedJsonArtifact.failure(['missing artifact']);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return _LoadedJsonArtifact.failure(['invalid JSON: ${error.message}']);
  }
  if (decoded is! Map) {
    return const _LoadedJsonArtifact.failure(['artifact is not a JSON object']);
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != expectedKind) {
    return _LoadedJsonArtifact.failure([
      'unexpected artifact kind ${json['kind'] ?? '<missing>'}; expected $expectedKind',
    ]);
  }
  return _LoadedJsonArtifact.success(json);
}

String _checkIdForKind(String kind) => switch (kind) {
  'fleuryWebFrameScoreboard' => 'frameScoreboard',
  'fleuryWebSemanticCoverageAudit' => 'semanticCoverage',
  'fleuryWebManualValidationAudit' => 'manualValidation',
  _ => 'artifact',
};

String _checkLabelForKind(String kind) => switch (kind) {
  'fleuryWebFrameScoreboard' => 'Frame performance scoreboard',
  'fleuryWebSemanticCoverageAudit' => 'Semantic coverage audit',
  'fleuryWebManualValidationAudit' => 'Manual browser validation',
  _ => 'Artifact',
};

String _markdown(Map<String, Object?> audit) {
  final checks = _maps(audit['checks']);
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Readiness Audit')
    ..writeln()
    ..writeln('Generated at `${audit['generatedAt']}`.')
    ..writeln()
    ..writeln('Strict pass: `${audit['strictPass']}`.')
    ..writeln()
    ..writeln('| Check | Status | Artifact | Blockers |')
    ..writeln('| --- | --- | --- | --- |');
  for (final check in checks) {
    final blockers = _strings(check['blockers']);
    buffer.writeln(
      '| ${check['label']} | ${check['strictPass'] == true ? 'pass' : 'FAIL'} | '
      '`${check['path']}` | ${blockers.isEmpty ? '-' : blockers.join('<br>')} |',
    );
  }
  _writeManualTargetDiagnostics(buffer, checks);
  return buffer.toString();
}

void _writeManualTargetDiagnostics(
  StringBuffer buffer,
  List<Map<String, Object?>> checks,
) {
  Map<String, Object?>? manualCheck;
  for (final check in checks) {
    if (check['id'] == 'manualValidation') {
      manualCheck = check;
      break;
    }
  }
  final details = manualCheck?['details'];
  if (details is! Map) return;
  final targets = _maps(details['failingTargetDetails']);
  if (targets.isEmpty) return;

  buffer
    ..writeln()
    ..writeln('## Manual Target Diagnostics')
    ..writeln()
    ..writeln('| Target | Status | Checks | Missing Checks |')
    ..writeln('| --- | --- | --- | --- |');
  for (final target in targets) {
    final required = _int(target, 'requiredCheckCount');
    final passed = _int(target, 'passedRequiredCheckCount');
    final missing = _strings(target['missingCheckIds']);
    buffer.writeln(
      '| ${target['id']} | ${target['status'] ?? '?'} | $passed/$required | ${missing.isEmpty ? '-' : missing.join('<br>')} |',
    );
  }
}

bool _hasGate(Map<String, Object?> json, String gateId) {
  return _maps(json['gates']).any((gate) => gate['id'] == gateId);
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

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final item in raw) item.toString()];
}

int _int(Map<String, Object?> json, String key) =>
    (json[key] as num?)?.toInt() ?? 0;

final class _LoadedJson {
  const _LoadedJson.success(this.json) : failure = null;
  const _LoadedJson.failure(this.failure) : json = null;

  final Map<String, Object?>? json;
  final _ReadinessCheck? failure;
}

final class _LoadedJsonArtifact {
  const _LoadedJsonArtifact.success(this.json) : failure = null;
  const _LoadedJsonArtifact.failure(this.failure) : json = null;

  final Map<String, Object?>? json;
  final List<String>? failure;
}

final class _ReadinessCheck {
  const _ReadinessCheck({
    required this.id,
    required this.label,
    required this.path,
    required this.strictPass,
    required this.blockers,
    required this.details,
  });

  final String id;
  final String label;
  final String path;
  final bool strictPass;
  final List<String> blockers;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'path': path,
      'strictPass': strictPass,
      'blockers': blockers,
      'details': details,
    };
  }
}

final class _Options {
  const _Options({
    required this.help,
    required this.scoreboardPath,
    required this.semanticAuditPath,
    required this.manualAuditPath,
    required this.thresholdReviewPath,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.minScoreboardRuns,
    required this.requireComparableEnvironment,
    required this.requireScoreboardGates,
    required this.requireTotalFrameGate,
    required this.requireReviewedThresholdPolicy,
    required this.requireThresholdReviewSummary,
    required this.requireScenarioThresholds,
    required this.requireSemanticGates,
    required this.json,
    required this.strict,
  });

  final bool help;
  final String scoreboardPath;
  final String semanticAuditPath;
  final String manualAuditPath;
  final String? thresholdReviewPath;
  final String? outputPath;
  final String? jsonOutputPath;
  final int minScoreboardRuns;
  final bool requireComparableEnvironment;
  final bool requireScoreboardGates;
  final bool requireTotalFrameGate;
  final bool requireReviewedThresholdPolicy;
  final bool requireThresholdReviewSummary;
  final bool requireScenarioThresholds;
  final bool requireSemanticGates;
  final bool json;
  final bool strict;

  static _Options parse(List<String> args) {
    var help = false;
    var scoreboardPath =
        '../../profiling/web/baselines/web-frame-scoreboard.json';
    var semanticAuditPath =
        '../../profiling/web/baselines/web-semantic-coverage.json';
    var manualAuditPath =
        '../../profiling/web/manual/manual-validation-audit.json';
    String? thresholdReviewPath;
    String? outputPath;
    String? jsonOutputPath;
    var minScoreboardRuns = 3;
    var requireComparableEnvironment = true;
    var requireScoreboardGates = true;
    var requireTotalFrameGate = true;
    var requireReviewedThresholdPolicy = true;
    var requireThresholdReviewSummary = true;
    var requireScenarioThresholds = true;
    var requireSemanticGates = true;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--scoreboard=')) {
        scoreboardPath = arg.substring('--scoreboard='.length);
      } else if (arg.startsWith('--semantic-audit=')) {
        semanticAuditPath = arg.substring('--semantic-audit='.length);
      } else if (arg.startsWith('--manual-audit=')) {
        manualAuditPath = arg.substring('--manual-audit='.length);
      } else if (arg.startsWith('--threshold-review=')) {
        thresholdReviewPath = arg
            .substring('--threshold-review='.length)
            .trim();
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length).trim();
      } else if (arg.startsWith('--min-scoreboard-runs=')) {
        minScoreboardRuns = _positiveInt(arg, '--min-scoreboard-runs=');
      } else if (arg == '--no-require-comparable-environment') {
        requireComparableEnvironment = false;
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
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for web_readiness: $arg');
        _printUsage();
        exit(2);
      }
    }
    if (jsonOutputPath != null && jsonOutputPath.isEmpty) {
      stderr.writeln('--json-output requires a non-empty path.');
      exit(2);
    }
    if (thresholdReviewPath != null && thresholdReviewPath.isEmpty) {
      stderr.writeln('--threshold-review requires a non-empty path.');
      exit(2);
    }

    return _Options(
      help: help,
      scoreboardPath: scoreboardPath,
      semanticAuditPath: semanticAuditPath,
      manualAuditPath: manualAuditPath,
      thresholdReviewPath: thresholdReviewPath,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      minScoreboardRuns: minScoreboardRuns,
      requireComparableEnvironment: requireComparableEnvironment,
      requireScoreboardGates: requireScoreboardGates,
      requireTotalFrameGate: requireTotalFrameGate,
      requireReviewedThresholdPolicy: requireReviewedThresholdPolicy,
      requireThresholdReviewSummary: requireThresholdReviewSummary,
      requireScenarioThresholds: requireScenarioThresholds,
      requireSemanticGates: requireSemanticGates,
      json: json,
      strict: strict,
    );
  }
}

int _positiveInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive integer.');
    exit(2);
  }
  return value;
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_readiness.dart [options]');
  stdout.writeln('');
  stdout.writeln(
    'Consumes reviewed JSON artifacts from the retained DOM web gates and',
  );
  stdout.writeln('reports whether Phase 6 defaulting/retirement is unblocked.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --scoreboard=PATH                   Frame scoreboard JSON artifact.',
  );
  stdout.writeln(
    '  --semantic-audit=PATH               Semantic coverage audit JSON artifact.',
  );
  stdout.writeln(
    '  --manual-audit=PATH                 Manual validation audit JSON artifact.',
  );
  stdout.writeln(
    '  --threshold-review=PATH             Threshold promotion summary JSON artifact.',
  );
  stdout.writeln('  --output=PATH                       Markdown output path.');
  stdout.writeln('  --json-output=PATH                  JSON output path.');
  stdout.writeln(
    '  --min-scoreboard-runs=N             Minimum scoreboard minRuns, default 3.',
  );
  stdout.writeln(
    '  --no-require-comparable-environment Do not require comparable run environments.',
  );
  stdout.writeln(
    '  --no-require-scoreboard-gates       Do not require frame threshold gates.',
  );
  stdout.writeln(
    '  --no-require-total-frame-gate       Do not require total-frame p95 gate.',
  );
  stdout.writeln(
    '  --no-require-reviewed-threshold-policy Do not require threshold policy reviewState=reviewed.',
  );
  stdout.writeln(
    '  --no-require-threshold-review-summary Do not require matching threshold-review JSON.',
  );
  stdout.writeln(
    '  --no-require-scenario-thresholds Do not require per-scenario threshold policy matches.',
  );
  stdout.writeln(
    '  --no-require-semantic-gates         Do not require semantic fallback gates.',
  );
  stdout.writeln(
    '  --strict                            Exit non-zero unless all checks pass.',
  );
  stdout.writeln(
    '  --json                              Print machine-readable audit JSON.',
  );
}
