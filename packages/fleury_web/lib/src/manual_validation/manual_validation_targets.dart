/// Shared target contract for Fleury web manual validation evidence.
///
/// The manual validation tool writes templates and starter evidence from this
/// registry. The readiness bundle uses the same registry to decide whether a
/// template is current enough for a generated starter command to succeed.
final class ManualValidationTarget {
  const ManualValidationTarget({
    required this.id,
    required this.phase,
    required this.category,
    required this.label,
    required this.browser,
    required this.platform,
    required this.assistiveTechnology,
    required this.inputMethod,
    required this.requiredChecks,
  });

  final String id;
  final String phase;
  final String category;
  final String label;
  final String browser;
  final String platform;
  final String? assistiveTechnology;
  final String? inputMethod;
  final List<ManualValidationCheck> requiredChecks;

  List<ManualValidationPageSignal> get requiredPageSignals {
    return <ManualValidationPageSignal>[
      manualValidationReadyPageSignal,
      if (category == 'ime') manualValidationImeCaretPageSignal,
    ];
  }

  List<String> get requiredEnvironmentKeys {
    return <String>[
      'browser',
      'browserVersion',
      'platform',
      'fleuryWebPage',
      if (inputMethod != null) 'inputMethod',
      if (assistiveTechnology != null) 'assistiveTechnology',
    ];
  }
}

final class ManualValidationCheck {
  const ManualValidationCheck({required this.id, required this.instruction});

  final String id;
  final String instruction;
}

final class ManualValidationPageSignal {
  const ManualValidationPageSignal({
    required this.id,
    required this.selector,
    required this.attribute,
    required this.expectedValue,
    required this.description,
  });

  final String id;
  final String selector;
  final String attribute;
  final String expectedValue;
  final String description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'selector': selector,
      'attribute': attribute,
      'expectedValue': expectedValue,
      'description': description,
    };
  }
}

const manualValidationEvidencePage = 'manual_validation.html';
const manualValidationHostedPage = 'web/manual_validation.html';
const manualValidationCommandWorkingDirectory = 'packages/fleury_web';
const manualValidationReadySignal =
    'document.body data-fleury-manual-validation="ready"';
const manualValidationReadyPageSignal = ManualValidationPageSignal(
  id: 'retained-dom-ready',
  selector: 'body',
  attribute: 'data-fleury-manual-validation',
  expectedValue: 'ready',
  description:
      'The manual validation page has presented its first retained DOM frame.',
);
const manualValidationImeCaretPageSignal = ManualValidationPageSignal(
  id: 'ime-caret-positioned',
  selector: 'textarea',
  attribute: 'data-fleury-caret-state',
  expectedValue: 'positioned',
  description:
      'The hidden textarea is positioned at the focused Fleury caret for IME candidate windows.',
);
const manualValidationLocalUrl = 'http://localhost:8080/manual_validation.html';
const manualValidationPageServeNote =
    'Run manualPageServeSetupCommand if dhttpd is not active, keep manualPageServeCommand running, open http://localhost:8080/manual_validation.html from that local server, and start checks only after the ready signal.';
const manualValidationProvenanceAttributes = <String>[
  'data-fleury-manual-browser-version',
  'data-fleury-manual-platform',
  'data-fleury-manual-user-agent',
  'data-fleury-manual-page',
];
const manualValidationPageBuildCommand = <String>[
  'dart',
  'compile',
  'js',
  'web/manual_validation.dart',
  '-o',
  'web/manual_validation.dart.js',
];
const manualValidationPageSmokeCommand = <String>[
  'dart',
  'test',
  '-p',
  'chrome',
  'test/manual_validation_page_test.dart',
];
const manualValidationPageServeSetupCommand = <String>[
  'dart',
  'pub',
  'global',
  'activate',
  'dhttpd',
];
const manualValidationPageServeCommand = <String>[
  'dart',
  'pub',
  'global',
  'run',
  'dhttpd',
  '--path',
  'web',
];

String manualValidationCommandLine(List<String> command) => command.join(' ');

ManualValidationTarget? manualValidationTargetById(String id) {
  for (final target in manualValidationTargets) {
    if (target.id == id) return target;
  }
  return null;
}

List<String>? manualValidationTargetIdsForPreset(String preset) {
  return switch (preset) {
    'v1' || 'primary' => manualValidationV1TargetIds,
    'all' => [for (final target in manualValidationTargets) target.id],
    _ => null,
  };
}

/// Current v1 release evidence scope.
///
/// `primary` remains an alias for existing commands, while release packets use
/// `v1` to make the current manual release gate explicit. IME and VoiceOver
/// remain defined manual targets for roadmap validation; run them with
/// `--target=chrome-ime-macos`, `--target=chrome-voiceover-macos`, or
/// `--target-preset=all`.
const manualValidationV1TargetIds = <String>[];

Map<String, Object?> manualValidationTemplateFor(
  ManualValidationTarget target,
) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebManualValidationEntry',
    'targetId': target.id,
    'target': <String, Object?>{
      'id': target.id,
      'label': target.label,
      'phase': target.phase,
      'category': target.category,
      'browser': target.browser,
      'platform': target.platform,
      if (target.assistiveTechnology != null)
        'assistiveTechnology': target.assistiveTechnology,
      if (target.inputMethod != null) 'inputMethod': target.inputMethod,
      'requiredCheckCount': target.requiredChecks.length,
    },
    'reviewInstructions': <String, Object?>{
      'manualValidationPage': manualValidationEvidencePage,
      'manualPageCommandWorkingDirectory':
          manualValidationCommandWorkingDirectory,
      'readySignal': manualValidationReadySignal,
      'manualPageBuildCommand': manualValidationPageBuildCommand,
      'manualPageSmokeCommand': manualValidationPageSmokeCommand,
      'manualPageServeSetupCommand': manualValidationPageServeSetupCommand,
      'manualPageServeCommand': manualValidationPageServeCommand,
      'manualPageLocalUrl': manualValidationLocalUrl,
      'manualPageServeNote': manualValidationPageServeNote,
      'provenanceAttributes': manualValidationProvenanceAttributes,
      'requiredPageSignals': [
        for (final signal in target.requiredPageSignals) signal.toJson(),
      ],
      'statusValues': const <String>['pass', 'fail', 'blocked', 'needsReview'],
      'requiredEnvironmentKeys': target.requiredEnvironmentKeys,
      'completionRule':
          'Set top-level status to pass only after provenance is filled, every required page signal has the expected observed value, every required check has status pass, and every passed check has reviewer observation notes rather than copied instructions.',
    },
    'observedPageSignals': [
      for (final signal in target.requiredPageSignals)
        <String, Object?>{
          ...signal.toJson(),
          'observedValue': '',
          'status': 'needsReview',
          'notes': signal.description,
        },
    ],
    'capturedAt': '',
    'status': 'needsReview',
    'reviewedBy': '',
    'environment': <String, Object?>{
      'browser': target.browser,
      'browserVersion': '',
      'platform': target.platform,
      if (target.assistiveTechnology != null)
        'assistiveTechnology': target.assistiveTechnology,
      if (target.inputMethod != null) 'inputMethod': target.inputMethod,
      'fleuryWebPage': manualValidationEvidencePage,
    },
    'checks': [
      for (final check in target.requiredChecks)
        <String, Object?>{
          'id': check.id,
          'status': 'needsReview',
          'notes': check.instruction,
        },
    ],
    'notes': <String>[],
  };
}

List<String> manualValidationTemplateBlockers(
  ManualValidationTarget target,
  Map<String, Object?> json,
) {
  final blockers = <String>[];
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    blockers.add('template kind must be fleuryWebManualValidationEntry');
  }
  if (json['targetId'] != target.id) {
    blockers.add('template targetId must be ${target.id}');
  }

  final targetMetadata = _readObjectMap(json['target']);
  _expectEqual(blockers, targetMetadata['id'], target.id, 'template target.id');
  _expectEqual(
    blockers,
    targetMetadata['label'],
    target.label,
    'template target.label',
  );
  _expectEqual(
    blockers,
    targetMetadata['phase'],
    target.phase,
    'template target.phase',
  );
  _expectEqual(
    blockers,
    targetMetadata['category'],
    target.category,
    'template target.category',
  );
  _expectEqual(
    blockers,
    targetMetadata['browser'],
    target.browser,
    'template target.browser',
  );
  _expectEqual(
    blockers,
    targetMetadata['platform'],
    target.platform,
    'template target.platform',
  );
  _expectEqual(
    blockers,
    targetMetadata['requiredCheckCount'],
    target.requiredChecks.length.toString(),
    'template target.requiredCheckCount',
  );
  if (target.inputMethod != null) {
    _expectEqual(
      blockers,
      targetMetadata['inputMethod'],
      target.inputMethod!,
      'template target.inputMethod',
    );
  }
  if (target.assistiveTechnology != null) {
    _expectEqual(
      blockers,
      targetMetadata['assistiveTechnology'],
      target.assistiveTechnology!,
      'template target.assistiveTechnology',
    );
  }

  final reviewInstructions = _readObjectMap(json['reviewInstructions']);
  _expectEqual(
    blockers,
    reviewInstructions['manualValidationPage'],
    manualValidationEvidencePage,
    'template reviewInstructions.manualValidationPage',
  );
  _expectEqual(
    blockers,
    reviewInstructions['manualPageCommandWorkingDirectory'],
    manualValidationCommandWorkingDirectory,
    'template reviewInstructions.manualPageCommandWorkingDirectory',
  );
  _expectEqual(
    blockers,
    reviewInstructions['readySignal'],
    manualValidationReadySignal,
    'template reviewInstructions.readySignal',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageBuildCommand'],
    manualValidationPageBuildCommand,
    'template reviewInstructions.manualPageBuildCommand',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageSmokeCommand'],
    manualValidationPageSmokeCommand,
    'template reviewInstructions.manualPageSmokeCommand',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageServeSetupCommand'],
    manualValidationPageServeSetupCommand,
    'template reviewInstructions.manualPageServeSetupCommand',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageServeCommand'],
    manualValidationPageServeCommand,
    'template reviewInstructions.manualPageServeCommand',
  );
  _expectEqual(
    blockers,
    reviewInstructions['manualPageLocalUrl'],
    manualValidationLocalUrl,
    'template reviewInstructions.manualPageLocalUrl',
  );
  _expectEqual(
    blockers,
    reviewInstructions['manualPageServeNote'],
    manualValidationPageServeNote,
    'template reviewInstructions.manualPageServeNote',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['provenanceAttributes'],
    manualValidationProvenanceAttributes,
    'template reviewInstructions.provenanceAttributes',
  );
  _expectPageSignalsEqual(
    blockers,
    reviewInstructions['requiredPageSignals'],
    target.requiredPageSignals,
    'template reviewInstructions.requiredPageSignals',
  );
  final statusValues = _readStringList(reviewInstructions['statusValues']);
  for (final status in ['pass', 'fail', 'blocked', 'needsReview']) {
    if (!statusValues.contains(status)) {
      blockers.add(
        'template reviewInstructions.statusValues must include $status',
      );
    }
  }
  final environmentKeys = _readStringList(
    reviewInstructions['requiredEnvironmentKeys'],
  );
  for (final key in target.requiredEnvironmentKeys) {
    if (!environmentKeys.contains(key)) {
      blockers.add(
        'template reviewInstructions.requiredEnvironmentKeys must include $key',
      );
    }
  }
  if ((reviewInstructions['completionRule']?.toString() ?? '').trim().isEmpty) {
    blockers.add(
      'template reviewInstructions.completionRule must be non-empty',
    );
  }
  _expectObservedPageSignals(
    blockers,
    json['observedPageSignals'],
    target.requiredPageSignals,
    'template observedPageSignals',
    requirePassingEvidence: false,
  );

  _expectEqual(blockers, json['status'], 'needsReview', 'template status');
  if ((json['capturedAt']?.toString() ?? '').trim().isNotEmpty) {
    blockers.add('template capturedAt must be blank');
  }
  if ((json['reviewedBy']?.toString() ?? '').trim().isNotEmpty) {
    blockers.add('template reviewedBy must be blank');
  }

  final environment = _readObjectMap(json['environment']);
  _expectEqual(
    blockers,
    environment['browser'],
    target.browser,
    'template environment.browser',
  );
  _expectEqual(
    blockers,
    environment['platform'],
    target.platform,
    'template environment.platform',
  );
  _expectEqual(
    blockers,
    environment['fleuryWebPage'],
    manualValidationEvidencePage,
    'template environment.fleuryWebPage',
  );
  if ((environment['browserVersion']?.toString() ?? '').trim().isNotEmpty) {
    blockers.add('template environment.browserVersion must be blank');
  }
  if (target.inputMethod != null) {
    _expectEqual(
      blockers,
      environment['inputMethod'],
      target.inputMethod!,
      'template environment.inputMethod',
    );
  }
  if (target.assistiveTechnology != null) {
    _expectEqual(
      blockers,
      environment['assistiveTechnology'],
      target.assistiveTechnology!,
      'template environment.assistiveTechnology',
    );
  }

  final checks = _readCheckList(json['checks']);
  final checkIds = checks.map((check) => check.id).toSet();
  final requiredById = <String, ManualValidationCheck>{
    for (final required in target.requiredChecks) required.id: required,
  };
  for (final required in target.requiredChecks) {
    if (!checkIds.contains(required.id)) {
      blockers.add('template checks must include ${required.id}');
    }
  }
  for (final check in checks) {
    final required = requiredById[check.id];
    if (required == null) {
      blockers.add('template checks must not include unknown ${check.id}');
    } else {
      _expectEqual(
        blockers,
        check.notes,
        required.instruction,
        'template check ${check.id} notes',
      );
    }
    if (check.status != 'needsReview') {
      blockers.add('template check ${check.id} status must be needsReview');
    }
    if ((check.notes ?? '').trim().isEmpty) {
      blockers.add('template check ${check.id} notes must be non-empty');
    }
  }
  return blockers;
}

List<String> manualValidationEvidenceContractBlockers(
  ManualValidationTarget target,
  Map<String, Object?> json,
) {
  final blockers = <String>[];
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    blockers.add('evidence kind must be fleuryWebManualValidationEntry');
  }
  if (json['targetId'] != target.id) {
    blockers.add('evidence targetId must be ${target.id}');
  }

  final targetMetadata = _readObjectMap(json['target']);
  _expectEqual(blockers, targetMetadata['id'], target.id, 'evidence target.id');
  _expectEqual(
    blockers,
    targetMetadata['label'],
    target.label,
    'evidence target.label',
  );
  _expectEqual(
    blockers,
    targetMetadata['phase'],
    target.phase,
    'evidence target.phase',
  );
  _expectEqual(
    blockers,
    targetMetadata['category'],
    target.category,
    'evidence target.category',
  );
  _expectEqual(
    blockers,
    targetMetadata['browser'],
    target.browser,
    'evidence target.browser',
  );
  _expectEqual(
    blockers,
    targetMetadata['platform'],
    target.platform,
    'evidence target.platform',
  );
  _expectEqual(
    blockers,
    targetMetadata['requiredCheckCount'],
    target.requiredChecks.length.toString(),
    'evidence target.requiredCheckCount',
  );
  if (target.inputMethod != null) {
    _expectEqual(
      blockers,
      targetMetadata['inputMethod'],
      target.inputMethod!,
      'evidence target.inputMethod',
    );
  }
  if (target.assistiveTechnology != null) {
    _expectEqual(
      blockers,
      targetMetadata['assistiveTechnology'],
      target.assistiveTechnology!,
      'evidence target.assistiveTechnology',
    );
  }

  final reviewInstructions = _readObjectMap(json['reviewInstructions']);
  _expectEqual(
    blockers,
    reviewInstructions['manualValidationPage'],
    manualValidationEvidencePage,
    'evidence reviewInstructions.manualValidationPage',
  );
  _expectEqual(
    blockers,
    reviewInstructions['manualPageCommandWorkingDirectory'],
    manualValidationCommandWorkingDirectory,
    'evidence reviewInstructions.manualPageCommandWorkingDirectory',
  );
  _expectEqual(
    blockers,
    reviewInstructions['readySignal'],
    manualValidationReadySignal,
    'evidence reviewInstructions.readySignal',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageBuildCommand'],
    manualValidationPageBuildCommand,
    'evidence reviewInstructions.manualPageBuildCommand',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageServeSetupCommand'],
    manualValidationPageServeSetupCommand,
    'evidence reviewInstructions.manualPageServeSetupCommand',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['manualPageServeCommand'],
    manualValidationPageServeCommand,
    'evidence reviewInstructions.manualPageServeCommand',
  );
  _expectEqual(
    blockers,
    reviewInstructions['manualPageLocalUrl'],
    manualValidationLocalUrl,
    'evidence reviewInstructions.manualPageLocalUrl',
  );
  _expectEqual(
    blockers,
    reviewInstructions['manualPageServeNote'],
    manualValidationPageServeNote,
    'evidence reviewInstructions.manualPageServeNote',
  );
  _expectStringListEqual(
    blockers,
    reviewInstructions['provenanceAttributes'],
    manualValidationProvenanceAttributes,
    'evidence reviewInstructions.provenanceAttributes',
  );
  _expectPageSignalsEqual(
    blockers,
    reviewInstructions['requiredPageSignals'],
    target.requiredPageSignals,
    'evidence reviewInstructions.requiredPageSignals',
  );
  final statusValues = _readStringList(reviewInstructions['statusValues']);
  for (final status in ['pass', 'fail', 'blocked', 'needsReview']) {
    if (!statusValues.contains(status)) {
      blockers.add(
        'evidence reviewInstructions.statusValues must include $status',
      );
    }
  }
  final environmentKeys = _readStringList(
    reviewInstructions['requiredEnvironmentKeys'],
  );
  for (final key in target.requiredEnvironmentKeys) {
    if (!environmentKeys.contains(key)) {
      blockers.add(
        'evidence reviewInstructions.requiredEnvironmentKeys must include $key',
      );
    }
  }
  if ((reviewInstructions['completionRule']?.toString() ?? '').trim().isEmpty) {
    blockers.add(
      'evidence reviewInstructions.completionRule must be non-empty',
    );
  }
  _expectObservedPageSignals(
    blockers,
    json['observedPageSignals'],
    target.requiredPageSignals,
    'evidence observedPageSignals',
    requirePassingEvidence: json['status'] == 'pass',
  );
  final checks = _readCheckList(json['checks']);
  final requiredById = <String, ManualValidationCheck>{
    for (final required in target.requiredChecks) required.id: required,
  };
  for (final check in checks) {
    final required = requiredById[check.id];
    if (required == null) {
      blockers.add('evidence checks must not include unknown ${check.id}');
      continue;
    }
    if (!_knownStatusValues.contains(check.status)) {
      blockers.add(
        'evidence check ${check.id} status must be pass fail blocked or needsReview',
      );
      continue;
    }
    if (check.status == 'pass') {
      final notes = check.notes?.trim() ?? '';
      if (notes.isEmpty) {
        blockers.add(
          'evidence check ${check.id} notes must describe observed result',
        );
      } else if (notes == required.instruction.trim()) {
        blockers.add(
          'evidence check ${check.id} notes must be reviewer observation, not copied instruction',
        );
      }
    }
  }
  return blockers;
}

const _knownStatusValues = <String>{'pass', 'fail', 'blocked', 'needsReview'};

void _expectObservedPageSignals(
  List<String> blockers,
  Object? actual,
  List<ManualValidationPageSignal> expected,
  String label, {
  required bool requirePassingEvidence,
}) {
  if (actual is! List) {
    blockers.add('$label must include ${_signalIds(expected).join(' ')}');
    return;
  }
  final byId = <String, Map<String, Object?>>{};
  for (final item in actual) {
    if (item is! Map) continue;
    final json = item.cast<String, Object?>();
    final id = json['id']?.toString();
    if (id != null && id.isNotEmpty) byId[id] = json;
  }
  for (final signal in expected) {
    final observed = byId[signal.id];
    if (observed == null) {
      blockers.add('$label must include ${signal.id}');
      continue;
    }
    _expectEqual(
      blockers,
      observed['selector'],
      signal.selector,
      '$label ${signal.id}.selector',
    );
    _expectEqual(
      blockers,
      observed['attribute'],
      signal.attribute,
      '$label ${signal.id}.attribute',
    );
    _expectEqual(
      blockers,
      observed['expectedValue'],
      signal.expectedValue,
      '$label ${signal.id}.expectedValue',
    );
    final status = observed['status']?.toString() ?? 'needsReview';
    if (!_knownStatusValues.contains(status)) {
      blockers.add(
        '$label ${signal.id}.status must be pass fail blocked or needsReview',
      );
    }
    final notes = observed['notes']?.toString().trim() ?? '';
    if (notes.isEmpty) {
      blockers.add('$label ${signal.id}.notes must be non-empty');
    }
    if (!requirePassingEvidence) continue;
    final observedValue = observed['observedValue']?.toString().trim() ?? '';
    if (status != 'pass') {
      blockers.add('$label ${signal.id}.status must be pass');
    }
    if (observedValue.isEmpty) {
      blockers.add('$label ${signal.id}.observedValue must be non-empty');
    } else if (observedValue != signal.expectedValue) {
      blockers.add(
        '$label ${signal.id}.observedValue expected ${signal.expectedValue}',
      );
    }
  }
  for (final id in byId.keys) {
    if (!expected.any((signal) => signal.id == id)) {
      blockers.add('$label must not include unknown $id');
    }
  }
}

List<String> _signalIds(List<ManualValidationPageSignal> signals) => [
  for (final signal in signals) signal.id,
];

Map<String, Object?> _readObjectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.cast<String, Object?>();
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final item in raw) item.toString()];
}

List<_TemplateCheck> _readCheckList(Object? raw) {
  if (raw is! List) return const <_TemplateCheck>[];
  return [
    for (final item in raw)
      if (item is Map) _TemplateCheck.fromJson(item.cast<String, Object?>()),
  ];
}

void _expectEqual(
  List<String> blockers,
  Object? actual,
  String expected,
  String label,
) {
  if (actual?.toString() != expected) {
    blockers.add('$label must be $expected');
  }
}

void _expectStringListEqual(
  List<String> blockers,
  Object? actual,
  List<String> expected,
  String label,
) {
  final actualList = _readStringList(actual);
  if (actualList.length != expected.length) {
    blockers.add('$label must be ${expected.join(' ')}');
    return;
  }
  for (var index = 0; index < expected.length; index++) {
    if (actualList[index] != expected[index]) {
      blockers.add('$label must be ${expected.join(' ')}');
      return;
    }
  }
}

void _expectPageSignalsEqual(
  List<String> blockers,
  Object? actual,
  List<ManualValidationPageSignal> expected,
  String label,
) {
  final actualList = actual is List ? actual : const <Object?>[];
  if (actualList.length != expected.length) {
    blockers.add(
      '$label must include ${expected.map((signal) => signal.id).join(' ')}',
    );
    return;
  }
  for (var index = 0; index < expected.length; index++) {
    final raw = actualList[index];
    final actualSignal = raw is Map
        ? raw.cast<String, Object?>()
        : const <String, Object?>{};
    final expectedSignal = expected[index];
    _expectEqual(
      blockers,
      actualSignal['id'],
      expectedSignal.id,
      '$label[$index].id',
    );
    _expectEqual(
      blockers,
      actualSignal['selector'],
      expectedSignal.selector,
      '$label[$index].selector',
    );
    _expectEqual(
      blockers,
      actualSignal['attribute'],
      expectedSignal.attribute,
      '$label[$index].attribute',
    );
    _expectEqual(
      blockers,
      actualSignal['expectedValue'],
      expectedSignal.expectedValue,
      '$label[$index].expectedValue',
    );
    _expectEqual(
      blockers,
      actualSignal['description'],
      expectedSignal.description,
      '$label[$index].description',
    );
  }
}

final class _TemplateCheck {
  const _TemplateCheck({
    required this.id,
    required this.status,
    required this.notes,
  });

  factory _TemplateCheck.fromJson(Map<String, Object?> json) {
    return _TemplateCheck(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      notes: json['notes']?.toString(),
    );
  }

  final String id;
  final String status;
  final String? notes;
}

const manualValidationTargets = <ManualValidationTarget>[
  ManualValidationTarget(
    id: 'chrome-ime-macos',
    phase: 'Phase 3',
    category: 'ime',
    label: 'Chrome primary-browser IME smoke on macOS',
    browser: 'Chrome',
    platform: 'macOS',
    assistiveTechnology: null,
    inputMethod: 'Any real composing IME, such as Japanese Romaji',
    requiredChecks: <ManualValidationCheck>[
      ManualValidationCheck(
        id: 'manual-page-loads-dom-host',
        instruction:
            'manual_validation.html reaches data-fleury-manual-validation="ready", retained DOM host output is visible, and no terminal-emulator fallback element is present.',
      ),
      ManualValidationCheck(
        id: 'keyboard-capture-focused',
        instruction:
            'The hidden textarea keeps browser focus while the Fleury text field is focused.',
      ),
      ManualValidationCheck(
        id: 'composition-start-update-visible',
        instruction:
            'Starting and updating a real IME composition updates the focused Fleury field without committing duplicate text.',
      ),
      ManualValidationCheck(
        id: 'composition-end-commits-once',
        instruction:
            'Ending composition commits the selected text exactly once into the Fleury text field.',
      ),
      ManualValidationCheck(
        id: 'candidate-window-near-caret',
        instruction:
            'The hidden textarea reports data-fleury-caret-state="positioned", and the browser IME candidate window appears near the Fleury caret, not at the page origin.',
      ),
      ManualValidationCheck(
        id: 'typing-continues-after-composition',
        instruction:
            'Normal keyboard input continues after composition without manually refocusing the page.',
      ),
    ],
  ),
  ManualValidationTarget(
    id: 'chrome-voiceover-macos',
    phase: 'Phase 4',
    category: 'screenReader',
    label: 'Chrome VoiceOver screen-reader smoke on macOS',
    browser: 'Chrome',
    platform: 'macOS',
    assistiveTechnology: 'VoiceOver',
    inputMethod: null,
    requiredChecks: <ManualValidationCheck>[
      ManualValidationCheck(
        id: 'manual-page-ready-semantic-host',
        instruction:
            'manual_validation.html reaches data-fleury-manual-validation="ready", retained semantic DOM output is reachable, and no terminal-emulator fallback element is present.',
      ),
      ManualValidationCheck(
        id: 'visual-grid-hidden',
        instruction:
            'VoiceOver does not navigate the visual .fleury-screen row grid as a live terminal log.',
      ),
      ManualValidationCheck(
        id: 'semantic-root-exposed',
        instruction:
            'VoiceOver can reach the semantic textbox, action button, link, and status content.',
      ),
      ManualValidationCheck(
        id: 'focused-textbox-announced',
        instruction:
            'The focused Fleury text field is announced as an editable textbox with its value.',
      ),
      ManualValidationCheck(
        id: 'semantic-action-works',
        instruction:
            'Activating the sample action through VoiceOver updates the Fleury status text.',
      ),
      ManualValidationCheck(
        id: 'keyboard-capture-restored',
        instruction:
            'After semantic activation, typing goes back into the Fleury text field.',
      ),
      ManualValidationCheck(
        id: 'safe-link-announced',
        instruction:
            'The sample safe link is announced as a link and exposes the expected URL.',
      ),
    ],
  ),
];
