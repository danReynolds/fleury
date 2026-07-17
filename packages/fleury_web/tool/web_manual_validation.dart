import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/manual_validation/manual_validation_targets.dart';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final targets = _selectedTargets(options);
  if (options.writePlanPath != null) {
    final output = File(options.writePlanPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(_planMarkdown(targets));
    stdout.writeln('wrote ${output.path}');
  }
  if (options.writeTemplatePath != null) {
    final target = _targetById(options.templateTargetId ?? targets.first.id);
    _writeTemplate(target, options.writeTemplatePath!);
  }
  if (options.writeStarterPath != null) {
    final target = _targetById(options.templateTargetId ?? targets.first.id);
    _writeStarter(
      target,
      outputPath: options.writeStarterPath!,
      templatePath: options.starterTemplatePath,
    );
  }
  if (options.updateProvenancePath != null) {
    _updateEvidenceProvenance(
      evidencePath: options.updateProvenancePath!,
      expectedTargetId: options.templateTargetId,
      reviewedBy: options.reviewedBy,
      capturedAt: options.capturedAt,
      browserVersion: options.browserVersion,
    );
  }
  if (options.updatePageSignalPath != null) {
    _updateEvidencePageSignal(
      evidencePath: options.updatePageSignalPath!,
      expectedTargetId: options.templateTargetId,
      signalId: options.signalId,
      signalStatus: options.signalStatus,
      observedValue: options.observedValue,
      signalNotes: options.signalNotes,
    );
  }
  if (options.updateCheckPath != null) {
    _updateEvidenceCheck(
      evidencePath: options.updateCheckPath!,
      expectedTargetId: options.templateTargetId,
      checkId: options.checkId,
      checkStatus: options.checkStatus,
      checkNotes: options.checkNotes,
      entryStatus: options.entryStatus,
    );
  }
  if (options.writeTemplatesDir != null) {
    for (final target in targets) {
      _writeTemplate(
        target,
        _joinPath(options.writeTemplatesDir!, '${target.id}.template.json'),
      );
    }
  }

  final loadedEntries = _loadEntries(options.inputDir);
  final audit = _buildAudit(targets: targets, loadedEntries: loadedEntries);
  final auditJson = const JsonEncoder.withIndent('  ').convert(audit);
  if (options.jsonOutputPath != null) {
    final output = File(options.jsonOutputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$auditJson\n');
  }
  final review = _reviewMarkdown(audit);
  if (options.outputPath != null) {
    final output = File(options.outputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(review);
    stdout.writeln('wrote ${output.path}');
  }
  if (options.json) {
    stdout.writeln(auditJson);
  } else if (options.outputPath == null &&
      options.writePlanPath == null &&
      options.writeTemplatePath == null &&
      options.writeStarterPath == null &&
      options.updateProvenancePath == null &&
      options.updatePageSignalPath == null &&
      options.updateCheckPath == null &&
      options.writeTemplatesDir == null) {
    stdout.write(review);
  }

  if (options.strict && audit['strictPass'] != true) exit(1);
}

void _writeTemplate(ManualValidationTarget target, String outputPath) {
  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manualValidationTemplateFor(target))}\n',
  );
  stdout.writeln('wrote ${output.path}');
}

void _writeStarter(
  ManualValidationTarget target, {
  required String outputPath,
  required String? templatePath,
}) {
  final output = File(outputPath);
  if (output.existsSync()) {
    stderr.writeln('starter evidence already exists: ${output.path}');
    exit(1);
  }
  output.parent.createSync(recursive: true);
  final starterText = templatePath == null
      ? '${const JsonEncoder.withIndent('  ').convert(manualValidationTemplateFor(target))}\n'
      : _starterTextFromTemplate(target, templatePath);
  output.writeAsStringSync(starterText);
  stdout.writeln('wrote ${output.path}');
}

String _starterTextFromTemplate(
  ManualValidationTarget target,
  String templatePath,
) {
  final template = File(templatePath);
  if (!template.existsSync()) {
    stderr.writeln('starter template does not exist: $templatePath');
    exit(2);
  }
  final text = template.readAsStringSync();
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    stderr.writeln('starter template is invalid JSON: ${error.message}');
    exit(2);
  }
  if (decoded is! Map) {
    stderr.writeln('starter template is not a JSON object: $templatePath');
    exit(2);
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    stderr.writeln(
      'starter template kind must be fleuryWebManualValidationEntry: $templatePath',
    );
    exit(2);
  }
  if (json['targetId'] != target.id) {
    stderr.writeln(
      'starter template targetId must be ${target.id}: $templatePath',
    );
    exit(2);
  }
  final blockers = manualValidationTemplateBlockers(target, json);
  if (blockers.isNotEmpty) {
    stderr.writeln('starter template is stale: $templatePath');
    for (final blocker in blockers) {
      stderr.writeln('- $blocker');
    }
    exit(2);
  }
  return text.endsWith('\n') ? text : '$text\n';
}

void _updateEvidenceProvenance({
  required String evidencePath,
  required String? expectedTargetId,
  required String? reviewedBy,
  required String? capturedAt,
  required String? browserVersion,
}) {
  if (reviewedBy == null && capturedAt == null && browserVersion == null) {
    stderr.writeln(
      '--update-provenance requires at least one of --reviewed-by, '
      '--captured-at, or --browser-version.',
    );
    exit(2);
  }

  final file = File(evidencePath);
  if (!file.existsSync()) {
    stderr.writeln('manual evidence does not exist: $evidencePath');
    exit(2);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('manual evidence is invalid JSON: ${error.message}');
    exit(2);
  }
  if (decoded is! Map) {
    stderr.writeln('manual evidence is not a JSON object: $evidencePath');
    exit(2);
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    stderr.writeln(
      'manual evidence kind must be fleuryWebManualValidationEntry: $evidencePath',
    );
    exit(2);
  }
  final targetId = json['targetId']?.toString().trim() ?? '';
  if (targetId.isEmpty) {
    stderr.writeln('manual evidence targetId is missing: $evidencePath');
    exit(2);
  }
  final expected = expectedTargetId?.trim();
  if (expected != null && expected.isNotEmpty && expected != targetId) {
    stderr.writeln('manual evidence targetId must be $expected: $evidencePath');
    exit(2);
  }

  final target = _targetById(targetId);
  final contractBlockers = manualValidationEvidenceContractBlockers(
    target,
    json,
  );
  if (contractBlockers.isNotEmpty) {
    stderr.writeln('manual evidence contract is stale: $evidencePath');
    for (final blocker in contractBlockers) {
      stderr.writeln('- $blocker');
    }
    exit(2);
  }

  if (reviewedBy != null) {
    final value = reviewedBy.trim();
    if (value.isEmpty) {
      stderr.writeln('--reviewed-by requires a non-empty value.');
      exit(2);
    }
    json['reviewedBy'] = value;
  }
  if (capturedAt != null) {
    json['capturedAt'] = _normalizeCapturedAt(capturedAt);
  }
  if (browserVersion != null) {
    final value = browserVersion.trim();
    if (value.isEmpty) {
      stderr.writeln('--browser-version requires a non-empty value.');
      exit(2);
    }
    final rawEnvironment = json['environment'];
    final environment = rawEnvironment is Map
        ? rawEnvironment.cast<String, Object?>()
        : <String, Object?>{};
    environment['browserVersion'] = value;
    json['environment'] = environment;
  }

  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  stdout.writeln('updated provenance ${file.path}');
}

void _updateEvidencePageSignal({
  required String evidencePath,
  required String? expectedTargetId,
  required String? signalId,
  required String? signalStatus,
  required String? observedValue,
  required String? signalNotes,
}) {
  if (signalId == null ||
      signalStatus == null ||
      observedValue == null ||
      signalNotes == null) {
    stderr.writeln(
      '--update-page-signal requires --signal-id, --signal-status, '
      '--observed-value, and --signal-notes.',
    );
    exit(2);
  }

  final file = File(evidencePath);
  if (!file.existsSync()) {
    stderr.writeln('manual evidence does not exist: $evidencePath');
    exit(2);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('manual evidence is invalid JSON: ${error.message}');
    exit(2);
  }
  if (decoded is! Map) {
    stderr.writeln('manual evidence is not a JSON object: $evidencePath');
    exit(2);
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    stderr.writeln(
      'manual evidence kind must be fleuryWebManualValidationEntry: $evidencePath',
    );
    exit(2);
  }
  final targetId = json['targetId']?.toString().trim() ?? '';
  if (targetId.isEmpty) {
    stderr.writeln('manual evidence targetId is missing: $evidencePath');
    exit(2);
  }
  final expected = expectedTargetId?.trim();
  if (expected != null && expected.isNotEmpty && expected != targetId) {
    stderr.writeln('manual evidence targetId must be $expected: $evidencePath');
    exit(2);
  }

  final target = _targetById(targetId);
  final contractBlockers = manualValidationEvidenceContractBlockers(
    target,
    json,
  );
  if (contractBlockers.isNotEmpty) {
    stderr.writeln('manual evidence contract is stale: $evidencePath');
    for (final blocker in contractBlockers) {
      stderr.writeln('- $blocker');
    }
    exit(2);
  }

  final id = signalId.trim();
  if (id.isEmpty) {
    stderr.writeln('--signal-id requires a non-empty value.');
    exit(2);
  }
  final requiredSignal = _requiredPageSignalById(target, id);
  if (requiredSignal == null) {
    stderr.writeln(
      'manual evidence page signal is not required for $targetId: $id',
    );
    exit(2);
  }
  final status = _validEvidenceStatus(signalStatus, option: '--signal-status');
  final value = observedValue.trim();
  if (value.isEmpty) {
    stderr.writeln('--observed-value requires a non-empty value.');
    exit(2);
  }
  final notes = signalNotes.trim();
  if (notes.isEmpty) {
    stderr.writeln('--signal-notes requires a non-empty value.');
    exit(2);
  }
  if (status == 'pass') {
    if (value != requiredSignal.expectedValue) {
      stderr.writeln(
        '--observed-value must equal ${requiredSignal.expectedValue} for $id when --signal-status=pass.',
      );
      exit(2);
    }
    if (notes == requiredSignal.description.trim()) {
      stderr.writeln(
        '--signal-notes must describe reviewer observation, not repeat the template description.',
      );
      exit(2);
    }
  }

  final rawSignals = json['observedPageSignals'];
  if (rawSignals is! List) {
    stderr.writeln(
      'manual evidence observedPageSignals must be a list: $evidencePath',
    );
    exit(2);
  }
  var updated = false;
  final signals = <Object?>[];
  for (final raw in rawSignals) {
    if (raw is! Map) {
      signals.add(raw);
      continue;
    }
    final signal = raw.cast<String, Object?>();
    if (signal['id']?.toString() == id) {
      signal['status'] = status;
      signal['observedValue'] = value;
      signal['notes'] = notes;
      updated = true;
    }
    signals.add(signal);
  }
  if (!updated) {
    stderr.writeln('manual evidence page signal is missing: $id');
    exit(2);
  }
  json['observedPageSignals'] = signals;

  final updatedContractBlockers = manualValidationEvidenceContractBlockers(
    target,
    json,
  );
  if (updatedContractBlockers.isNotEmpty) {
    stderr.writeln(
      'manual evidence update would violate contract: $evidencePath',
    );
    for (final blocker in updatedContractBlockers) {
      stderr.writeln('- $blocker');
    }
    exit(2);
  }

  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  stdout.writeln('updated evidence ${file.path}');
}

void _updateEvidenceCheck({
  required String evidencePath,
  required String? expectedTargetId,
  required String? checkId,
  required String? checkStatus,
  required String? checkNotes,
  required String? entryStatus,
}) {
  final updatingCheck =
      checkId != null || checkStatus != null || checkNotes != null;
  if (!updatingCheck && entryStatus == null) {
    stderr.writeln(
      '--update-check requires --check-id/--check-status/--check-notes '
      'or --entry-status.',
    );
    exit(2);
  }
  if (updatingCheck &&
      (checkId == null || checkStatus == null || checkNotes == null)) {
    stderr.writeln(
      '--update-check requires --check-id, --check-status, and --check-notes '
      'when updating a check.',
    );
    exit(2);
  }

  final file = File(evidencePath);
  if (!file.existsSync()) {
    stderr.writeln('manual evidence does not exist: $evidencePath');
    exit(2);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('manual evidence is invalid JSON: ${error.message}');
    exit(2);
  }
  if (decoded is! Map) {
    stderr.writeln('manual evidence is not a JSON object: $evidencePath');
    exit(2);
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    stderr.writeln(
      'manual evidence kind must be fleuryWebManualValidationEntry: $evidencePath',
    );
    exit(2);
  }
  final targetId = json['targetId']?.toString().trim() ?? '';
  if (targetId.isEmpty) {
    stderr.writeln('manual evidence targetId is missing: $evidencePath');
    exit(2);
  }
  final expected = expectedTargetId?.trim();
  if (expected != null && expected.isNotEmpty && expected != targetId) {
    stderr.writeln('manual evidence targetId must be $expected: $evidencePath');
    exit(2);
  }

  final target = _targetById(targetId);
  final contractBlockers = manualValidationEvidenceContractBlockers(
    target,
    json,
  );
  if (contractBlockers.isNotEmpty) {
    stderr.writeln('manual evidence contract is stale: $evidencePath');
    for (final blocker in contractBlockers) {
      stderr.writeln('- $blocker');
    }
    exit(2);
  }

  if (entryStatus != null) {
    json['status'] = _validEvidenceStatus(
      entryStatus,
      option: '--entry-status',
    );
  }

  if (updatingCheck) {
    final id = checkId!.trim();
    if (id.isEmpty) {
      stderr.writeln('--check-id requires a non-empty value.');
      exit(2);
    }
    final requiredCheck = _requiredCheckById(target, id);
    if (requiredCheck == null) {
      stderr.writeln(
        'manual evidence check is not required for $targetId: $id',
      );
      exit(2);
    }
    final status = _validEvidenceStatus(checkStatus!, option: '--check-status');
    final notes = checkNotes!.trim();
    if (notes.isEmpty) {
      stderr.writeln('--check-notes requires a non-empty value.');
      exit(2);
    }
    if (status == 'pass' && notes == requiredCheck.instruction.trim()) {
      stderr.writeln(
        '--check-notes must describe reviewer observation, not repeat the template instruction.',
      );
      exit(2);
    }

    final rawChecks = json['checks'];
    if (rawChecks is! List) {
      stderr.writeln('manual evidence checks must be a list: $evidencePath');
      exit(2);
    }
    var updated = false;
    final checks = <Object?>[];
    for (final raw in rawChecks) {
      if (raw is! Map) {
        checks.add(raw);
        continue;
      }
      final check = raw.cast<String, Object?>();
      if (check['id']?.toString() == id) {
        check['status'] = status;
        check['notes'] = notes;
        updated = true;
      }
      checks.add(check);
    }
    if (!updated) {
      stderr.writeln('manual evidence check is missing: $id');
      exit(2);
    }
    json['checks'] = checks;
  }

  final updatedContractBlockers = manualValidationEvidenceContractBlockers(
    target,
    json,
  );
  if (updatedContractBlockers.isNotEmpty) {
    stderr.writeln(
      'manual evidence update would violate contract: $evidencePath',
    );
    for (final blocker in updatedContractBlockers) {
      stderr.writeln('- $blocker');
    }
    exit(2);
  }

  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  stdout.writeln('updated evidence ${file.path}');
}

ManualValidationPageSignal? _requiredPageSignalById(
  ManualValidationTarget target,
  String id,
) {
  for (final signal in target.requiredPageSignals) {
    if (signal.id == id) return signal;
  }
  return null;
}

ManualValidationCheck? _requiredCheckById(
  ManualValidationTarget target,
  String id,
) {
  for (final check in target.requiredChecks) {
    if (check.id == id) return check;
  }
  return null;
}

String _validEvidenceStatus(String raw, {required String option}) {
  final status = raw.trim();
  if (status == 'pass' ||
      status == 'fail' ||
      status == 'blocked' ||
      status == 'needsReview') {
    return status;
  }
  stderr.writeln('$option must be pass, fail, blocked, or needsReview.');
  exit(2);
}

String _normalizeCapturedAt(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    stderr.writeln('--captured-at requires a non-empty value.');
    exit(2);
  }
  if (trimmed == 'now') return DateTime.now().toUtc().toIso8601String();
  try {
    return DateTime.parse(trimmed).toUtc().toIso8601String();
  } on FormatException {
    stderr.writeln('--captured-at must be ISO-8601 or "now".');
    exit(2);
  }
}

Map<String, Object?> _buildAudit({
  required List<ManualValidationTarget> targets,
  required _ManualEntryLoadResult loadedEntries,
}) {
  final entries = loadedEntries.entries;
  final reports = [
    for (final target in targets) _targetReport(target, entries).toJson(),
  ];
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebManualValidationAudit',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'targetCount': targets.length,
    'entryCount': entries.length,
    'invalidEntryCount': loadedEntries.invalidFiles.length,
    if (loadedEntries.invalidFiles.isNotEmpty)
      'invalidEntries': [
        for (final issue in loadedEntries.invalidFiles) issue.toJson(),
      ],
    'ignoredFileCount': loadedEntries.ignoredFiles.length,
    if (loadedEntries.ignoredFiles.isNotEmpty)
      'ignoredFiles': [
        for (final issue in loadedEntries.ignoredFiles) issue.toJson(),
      ],
    'passedTargetCount': reports
        .where((report) => report['strictPass'] == true)
        .length,
    'missingTargets': [
      for (final report in reports)
        if (report['status'] == 'missing') report['id'],
    ],
    'failedTargets': [
      for (final report in reports)
        if (report['status'] == 'fail') report['id'],
    ],
    'blockedTargets': [
      for (final report in reports)
        if (report['status'] == 'blocked') report['id'],
    ],
    'needsReviewTargets': [
      for (final report in reports)
        if (report['status'] == 'needsReview') report['id'],
    ],
    'strictPass':
        loadedEntries.invalidFiles.isEmpty &&
        reports.every((report) => report['strictPass'] == true),
    'targets': reports,
  };
}

_TargetReport _targetReport(
  ManualValidationTarget target,
  List<_ManualValidationEntry> entries,
) {
  final matching = [
    for (final entry in entries)
      if (entry.targetId == target.id) entry,
  ]..sort((a, b) => a.sortCapturedAt.compareTo(b.sortCapturedAt));
  final latest = matching.isEmpty ? null : matching.last;
  if (latest == null) {
    return _TargetReport(
      target: target,
      entry: null,
      status: 'missing',
      missingCheckIds: [for (final check in target.requiredChecks) check.id],
      failedCheckIds: const <String>[],
      blockedCheckIds: const <String>[],
      provenanceBlockers: const <String>[],
      strictPass: false,
    );
  }

  final missing = <String>[];
  final failed = <String>[];
  final blocked = <String>[];
  for (final check in target.requiredChecks) {
    final status = latest.checks[check.id]?.status;
    switch (status) {
      case 'pass':
        break;
      case 'fail':
        failed.add(check.id);
      case 'blocked':
        blocked.add(check.id);
      default:
        missing.add(check.id);
    }
  }
  final provenanceBlockers = _provenanceBlockers(target, latest);
  final strictPass =
      latest.status == 'pass' &&
      missing.isEmpty &&
      failed.isEmpty &&
      blocked.isEmpty &&
      provenanceBlockers.isEmpty;
  return _TargetReport(
    target: target,
    entry: latest,
    status: latest.status == 'pass' && provenanceBlockers.isNotEmpty
        ? 'needsReview'
        : latest.status,
    missingCheckIds: missing,
    failedCheckIds: failed,
    blockedCheckIds: blocked,
    provenanceBlockers: provenanceBlockers,
    strictPass: strictPass,
  );
}

List<String> _provenanceBlockers(
  ManualValidationTarget target,
  _ManualValidationEntry entry,
) {
  final blockers = <String>[];
  if (entry.reviewedBy == null || entry.reviewedBy!.trim().isEmpty) {
    blockers.add('reviewedBy');
  } else if (_isPlaceholderReviewer(entry.reviewedBy!)) {
    blockers.add('reviewedBy placeholder');
  }
  if (entry.capturedAt.trim().isEmpty) {
    blockers.add('capturedAt');
  } else if (entry.capturedAtUtc == null) {
    blockers.add('capturedAt must be ISO-8601');
  }
  String? requireEnvironment(String key) {
    final value = entry.environment[key]?.trim();
    if (value == null || value.isEmpty) {
      blockers.add('environment.$key');
      return null;
    }
    return value;
  }

  final browser = requireEnvironment('browser');
  final browserVersion = requireEnvironment('browserVersion');
  final platform = requireEnvironment('platform');
  final fleuryWebPage = requireEnvironment('fleuryWebPage');
  if (browser != null && browser != target.browser) {
    blockers.add('environment.browser expected ${target.browser}');
  }
  if (browserVersion != null && _containsPlaceholder(browserVersion)) {
    blockers.add('environment.browserVersion placeholder');
  }
  if (platform != null && platform != target.platform) {
    blockers.add('environment.platform expected ${target.platform}');
  }
  if (fleuryWebPage != null && fleuryWebPage != 'manual_validation.html') {
    blockers.add('environment.fleuryWebPage expected manual_validation.html');
  }
  if (target.inputMethod != null) requireEnvironment('inputMethod');
  if (target.assistiveTechnology != null) {
    final assistiveTechnology = requireEnvironment('assistiveTechnology');
    if (assistiveTechnology != null &&
        assistiveTechnology != target.assistiveTechnology) {
      blockers.add(
        'environment.assistiveTechnology expected ${target.assistiveTechnology}',
      );
    }
  }
  blockers.addAll(manualValidationEvidenceContractBlockers(target, entry.json));
  return blockers;
}

bool _isPlaceholderReviewer(String value) {
  if (_containsPlaceholder(value)) return true;
  final normalized = value.trim().toLowerCase();
  return normalized == 'reviewer' ||
      normalized == 'reviewer-name' ||
      normalized == 'reviewer name' ||
      normalized == 'name';
}

bool _containsPlaceholder(String value) {
  final trimmed = value.trim();
  if (trimmed.contains('<') || trimmed.contains('>')) return true;
  return RegExp(r'\b(VERSION|PLATFORM|REVIEWER|BROWSER)\b').hasMatch(trimmed);
}

_ManualEntryLoadResult _loadEntries(String inputDir) {
  final root = Directory(inputDir);
  if (!root.existsSync()) {
    return const _ManualEntryLoadResult(
      entries: <_ManualValidationEntry>[],
      invalidFiles: <_ManualEntryFileIssue>[],
      ignoredFiles: <_ManualEntryFileIssue>[],
    );
  }
  final entries = <_ManualValidationEntry>[];
  final invalidFiles = <_ManualEntryFileIssue>[];
  final ignoredFiles = <_ManualEntryFileIssue>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final fileName = _fileName(entity.path);
    if (fileName.endsWith('.template.json')) {
      ignoredFiles.add(
        _ManualEntryFileIssue(path: entity.path, reason: 'template file'),
      );
      continue;
    }
    if (fileName == 'manual-validation-audit.json') {
      ignoredFiles.add(
        _ManualEntryFileIssue(path: entity.path, reason: 'generated audit'),
      );
      continue;
    }
    final loaded = _tryLoadEntry(entity);
    if (loaded.entry != null) {
      entries.add(loaded.entry!);
    } else if (loaded.invalidFile != null) {
      invalidFiles.add(loaded.invalidFile!);
    }
  }
  return _ManualEntryLoadResult(
    entries: List.unmodifiable(entries),
    invalidFiles: List.unmodifiable(invalidFiles),
    ignoredFiles: List.unmodifiable(ignoredFiles),
  );
}

_LoadedManualEntry _tryLoadEntry(File file) {
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return _LoadedManualEntry.invalid(
      _ManualEntryFileIssue(
        path: file.path,
        reason: 'invalid JSON: ${error.message}',
      ),
    );
  }
  if (decoded is! Map) {
    return _LoadedManualEntry.invalid(
      _ManualEntryFileIssue(
        path: file.path,
        reason: 'artifact is not a JSON object',
      ),
    );
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != 'fleuryWebManualValidationEntry') {
    return _LoadedManualEntry.invalid(
      _ManualEntryFileIssue(
        path: file.path,
        reason:
            'unexpected artifact kind ${json['kind'] ?? '<missing>'}; expected fleuryWebManualValidationEntry',
      ),
    );
  }
  final targetId = json['targetId']?.toString();
  if (targetId == null || targetId.isEmpty) {
    return _LoadedManualEntry.invalid(
      _ManualEntryFileIssue(path: file.path, reason: 'targetId is missing'),
    );
  }
  final checks = <String, _ManualCheckResult>{};
  final rawChecks = json['checks'];
  if (rawChecks is List) {
    for (final raw in rawChecks) {
      if (raw is! Map) continue;
      final check = _ManualCheckResult.fromJson(raw.cast<String, Object?>());
      checks[check.id] = check;
    }
  }
  final capturedAt = json['capturedAt']?.toString() ?? '';
  return _LoadedManualEntry.entry(
    _ManualValidationEntry(
      path: file.path,
      fingerprint: _jsonFingerprint(json),
      targetId: targetId,
      json: Map.unmodifiable(json),
      capturedAt: capturedAt,
      capturedAtUtc: _parseCapturedAt(capturedAt),
      status: _entryStatus(json['status']),
      reviewedBy: json['reviewedBy']?.toString(),
      environment: _readStringMap(json['environment']),
      checks: Map.unmodifiable(checks),
      notes: _readStringList(json['notes']),
    ),
  );
}

DateTime? _parseCapturedAt(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    return null;
  }
}

String _entryStatus(Object? raw) {
  final status = raw?.toString() ?? 'needsReview';
  return switch (status) {
    'pass' || 'fail' || 'blocked' || 'needsReview' => status,
    _ => 'needsReview',
  };
}

Map<String, String> _readStringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  return {
    for (final entry in raw.entries)
      if (entry.value != null) entry.key.toString(): entry.value.toString(),
  };
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final item in raw) item.toString()];
}

String _planMarkdown(List<ManualValidationTarget> targets) {
  final includesIme = targets.any((target) => target.category == 'ime');
  final includesScreenReader = targets.any(
    (target) => target.category == 'screenReader',
  );
  final scopeDescription = includesIme && includesScreenReader
      ? 'real IME behavior and screen-reader interaction'
      : includesScreenReader
      ? 'real screen-reader interaction'
      : includesIme
      ? 'real IME behavior'
      : 'manual browser behavior';
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Manual Validation Plan')
    ..writeln()
    ..writeln(
      'This plan covers the empirical gates that browser automation and',
    )
    ..writeln('frame captures cannot prove: $scopeDescription with the')
    ..writeln('retained DOM host.')
    ..writeln()
    ..writeln('## Setup')
    ..writeln()
    ..writeln('```sh')
    ..writeln('cd packages/fleury_web')
    ..writeln(manualValidationCommandLine(manualValidationPageBuildCommand))
    ..writeln(manualValidationCommandLine(manualValidationPageSmokeCommand))
    ..writeln(
      manualValidationCommandLine(manualValidationPageServeSetupCommand),
    )
    ..writeln(manualValidationCommandLine(manualValidationPageServeCommand))
    ..writeln('```')
    ..writeln()
    ..writeln(
      'The browser smoke command verifies the retained DOM page wiring before',
    )
    ..writeln('manual checks begin. It does not replace $scopeDescription')
    ..writeln('evidence.')
    ..writeln()
    ..writeln('Open `$manualValidationLocalUrl` from the local server.')
    ..writeln('Start manual checks only after the page reports')
    ..writeln('`$manualValidationReadySignal`;')
    ..writeln(
      '`mounted` only means host construction finished, not that the first',
    )
    ..writeln('retained DOM frame has presented.')
    ..writeln()
    ..writeln(
      'The page also exposes evidence provenance hints on `document.body`:',
    );
  for (final attribute in manualValidationProvenanceAttributes) {
    buffer.writeln('- `$attribute`');
  }
  buffer
    ..writeln()
    ..writeln('Use `data-fleury-manual-browser-version` as the browser-version')
    ..writeln('value in the provenance command after confirming the manual')
    ..writeln('session is running in the intended browser.')
    ..writeln()
    ..writeln('Record one JSON entry per target using the template command:')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
      'dart run tool/web_manual_validation.dart --write-template=../../profiling/web/manual/templates/<target>.template.json --template-target=<target>',
    )
    ..writeln('```')
    ..writeln()
    ..writeln(
      'Template files ending in `.template.json` are ignored by audits.',
    )
    ..writeln(
      'After completing validation, copy the template to a non-template',
    )
    ..writeln('evidence file such as')
    ..writeln('`../../profiling/web/manual/evidence/<target>-<date>.json`.')
    ..writeln()
    ..writeln(
      'To fill only the provenance fields on a starter or copied evidence',
    )
    ..writeln('file without changing target/check status, run:')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
      "dart run tool/web_manual_validation.dart --update-provenance=../../profiling/web/manual/evidence/<target>.review.json --template-target=<target> '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'",
    )
    ..writeln('```')
    ..writeln()
    ..writeln('To update one required page signal after observing it, run:')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
      "dart run tool/web_manual_validation.dart --update-page-signal=../../profiling/web/manual/evidence/<target>.review.json --template-target=<target> --signal-id=<required-page-signal-id> --signal-status=pass --observed-value=<expected-value> '--signal-notes=<reviewer observation>'",
    )
    ..writeln('```')
    ..writeln()
    ..writeln('To update one required check after observing it, run:')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
      "dart run tool/web_manual_validation.dart --update-check=../../profiling/web/manual/evidence/<target>.review.json --template-target=<target> --check-id=<required-check-id> --check-status=pass '--check-notes=<reviewer observation>'",
    )
    ..writeln('```')
    ..writeln()
    ..writeln('Before review can pass, each evidence entry must include:')
    ..writeln()
    ..writeln('- top-level `status: "pass"`;')
    ..writeln('- non-empty, non-placeholder `reviewedBy`;')
    ..writeln('- parseable ISO-8601 `capturedAt`;')
    ..writeln('- environment `browser`, `browserVersion`, `platform`, and')
    ..writeln('  `fleuryWebPage`;')
    ..writeln('- `browser` and `platform` values matching the target metadata;')
    ..writeln('- `fleuryWebPage: "manual_validation.html"`;')
    ..writeln('- target-specific `inputMethod` for IME entries')
    ..writeln('  or matching `assistiveTechnology` for screen-reader entries;')
    ..writeln('- `observedPageSignals` entries with `status: "pass"` and')
    ..writeln('  `observedValue` matching each required page signal;')
    ..writeln('- `status: "pass"` for every required check;')
    ..writeln('- reviewer observation notes on every passed check, rather')
    ..writeln('  than copied template instruction text.');

  for (final target in targets) {
    buffer
      ..writeln()
      ..writeln('## ${target.id}: ${target.label}')
      ..writeln()
      ..writeln('- Phase: ${target.phase}')
      ..writeln('- Category: ${target.category}')
      ..writeln('- Browser: ${target.browser}')
      ..writeln('- Platform: ${target.platform}');
    if (target.assistiveTechnology != null) {
      buffer.writeln('- Assistive technology: ${target.assistiveTechnology}');
    }
    if (target.inputMethod != null) {
      buffer.writeln('- Input method: ${target.inputMethod}');
    }
    buffer
      ..writeln()
      ..writeln('Required checks:')
      ..writeln();
    for (final check in target.requiredChecks) {
      buffer.writeln('- `${check.id}`: ${check.instruction}');
    }
  }
  return buffer.toString();
}

String _reviewMarkdown(Map<String, Object?> audit) {
  final targets = (audit['targets'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Manual Validation Audit')
    ..writeln()
    ..writeln('Generated at `${audit['generatedAt']}`.')
    ..writeln()
    ..writeln('| Target | Status | Required Checks | Latest Entry | Notes |')
    ..writeln('| --- | --- | --- | --- | --- |');
  if (targets.isEmpty) {
    buffer.writeln('| - | missing | 0/0 | - | - |');
    return buffer.toString();
  }
  for (final target in targets) {
    final missing = (target['missingCheckIds'] as List<Object?>).join(', ');
    final failed = (target['failedCheckIds'] as List<Object?>).join(', ');
    final blocked = (target['blockedCheckIds'] as List<Object?>).join(', ');
    final latestEntry = target['latestEntryFile'] == null
        ? '-'
        : '${target['latestEntryFile']}<br>${target['latestEntryFingerprint'] ?? '-'}';
    final notes = [
      if (missing.isNotEmpty) 'missing: $missing',
      if (failed.isNotEmpty) 'failed: $failed',
      if (blocked.isNotEmpty) 'blocked: $blocked',
      if ((target['provenanceBlockers'] as List<Object?>).isNotEmpty)
        'provenance: ${(target['provenanceBlockers'] as List<Object?>).join(', ')}',
    ].join('<br>');
    buffer.writeln(
      '| ${target['id']} | ${target['status']} | '
      '${target['passedRequiredCheckCount']}/${target['requiredCheckCount']} | '
      '$latestEntry | ${notes.isEmpty ? '-' : notes} |',
    );
  }
  final invalidEntries = _maps(audit['invalidEntries']);
  if (invalidEntries.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Invalid Evidence Files')
      ..writeln()
      ..writeln('| File | Reason |')
      ..writeln('| --- | --- |');
    for (final issue in invalidEntries) {
      buffer.writeln(
        '| ${_fileName(issue['path']?.toString() ?? '?')} | ${issue['reason'] ?? '?'} |',
      );
    }
  }
  return buffer.toString();
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

List<ManualValidationTarget> _selectedTargets(_Options options) {
  final ids = options.targetIds.isEmpty
      ? _targetIdsForPreset(options.targetPreset)
      : options.targetIds;
  return [for (final id in ids) _targetById(id)];
}

List<String> _targetIdsForPreset(String preset) {
  final ids = manualValidationTargetIdsForPreset(preset);
  if (ids != null) return ids;
  return _unknownPreset(preset);
}

Never _unknownPreset(String preset) {
  stderr.writeln('Unknown manual validation target preset: $preset');
  _printUsage();
  exit(2);
}

ManualValidationTarget _targetById(String id) {
  final target = manualValidationTargetById(id);
  if (target != null) return target;
  stderr.writeln('Unknown manual validation target: $id');
  _printUsage();
  exit(2);
}

String _fileName(String path) {
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

String _joinPath(String directory, String basename) {
  if (directory.endsWith(Platform.pathSeparator)) return '$directory$basename';
  return '$directory${Platform.pathSeparator}$basename';
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

final class _ManualEntryLoadResult {
  const _ManualEntryLoadResult({
    required this.entries,
    required this.invalidFiles,
    required this.ignoredFiles,
  });

  final List<_ManualValidationEntry> entries;
  final List<_ManualEntryFileIssue> invalidFiles;
  final List<_ManualEntryFileIssue> ignoredFiles;
}

final class _LoadedManualEntry {
  const _LoadedManualEntry.entry(this.entry) : invalidFile = null;

  const _LoadedManualEntry.invalid(this.invalidFile) : entry = null;

  final _ManualValidationEntry? entry;
  final _ManualEntryFileIssue? invalidFile;
}

final class _ManualEntryFileIssue {
  const _ManualEntryFileIssue({required this.path, required this.reason});

  final String path;
  final String reason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'file': _fileName(path),
      'reason': reason,
    };
  }
}

final class _TargetReport {
  const _TargetReport({
    required this.target,
    required this.entry,
    required this.status,
    required this.missingCheckIds,
    required this.failedCheckIds,
    required this.blockedCheckIds,
    required this.provenanceBlockers,
    required this.strictPass,
  });

  final ManualValidationTarget target;
  final _ManualValidationEntry? entry;
  final String status;
  final List<String> missingCheckIds;
  final List<String> failedCheckIds;
  final List<String> blockedCheckIds;
  final List<String> provenanceBlockers;
  final bool strictPass;

  Map<String, Object?> toJson() {
    final entry = this.entry;
    final passedRequiredCheckCount =
        target.requiredChecks.length -
        missingCheckIds.length -
        failedCheckIds.length -
        blockedCheckIds.length;
    return <String, Object?>{
      'id': target.id,
      'label': target.label,
      'phase': target.phase,
      'category': target.category,
      'browser': target.browser,
      'platform': target.platform,
      if (target.assistiveTechnology != null)
        'assistiveTechnology': target.assistiveTechnology,
      if (target.inputMethod != null) 'inputMethod': target.inputMethod,
      'status': status,
      'strictPass': strictPass,
      'requiredCheckCount': target.requiredChecks.length,
      'passedRequiredCheckCount': passedRequiredCheckCount,
      'missingCheckIds': missingCheckIds,
      'failedCheckIds': failedCheckIds,
      'blockedCheckIds': blockedCheckIds,
      'provenanceBlockers': provenanceBlockers,
      if (entry != null) 'latestEntryPath': entry.path,
      if (entry != null) 'latestEntryFile': _fileName(entry.path),
      if (entry != null) 'latestEntryFingerprint': entry.fingerprint,
      if (entry != null) 'latestCapturedAt': entry.capturedAt,
      if (entry != null) 'reviewedBy': entry.reviewedBy,
      if (entry != null) 'environment': entry.environment,
      if (entry != null) 'notes': entry.notes,
    };
  }
}

final class _ManualValidationEntry {
  const _ManualValidationEntry({
    required this.path,
    required this.fingerprint,
    required this.targetId,
    required this.json,
    required this.capturedAt,
    required this.capturedAtUtc,
    required this.status,
    required this.reviewedBy,
    required this.environment,
    required this.checks,
    required this.notes,
  });

  final String path;
  final String fingerprint;
  final String targetId;
  final Map<String, Object?> json;
  final String capturedAt;
  final DateTime? capturedAtUtc;
  final String status;
  final String? reviewedBy;
  final Map<String, String> environment;
  final Map<String, _ManualCheckResult> checks;
  final List<String> notes;

  DateTime get sortCapturedAt =>
      capturedAtUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

final class _ManualCheckResult {
  const _ManualCheckResult({
    required this.id,
    required this.status,
    required this.notes,
  });

  factory _ManualCheckResult.fromJson(Map<String, Object?> json) {
    return _ManualCheckResult(
      id: json['id']?.toString() ?? '',
      status: _entryStatus(json['status']),
      notes: json['notes']?.toString(),
    );
  }

  final String id;
  final String status;
  final String? notes;
}

final class _Options {
  const _Options({
    required this.help,
    required this.inputDir,
    required this.outputPath,
    required this.writePlanPath,
    required this.writeTemplatePath,
    required this.writeStarterPath,
    required this.starterTemplatePath,
    required this.updateProvenancePath,
    required this.updatePageSignalPath,
    required this.updateCheckPath,
    required this.reviewedBy,
    required this.capturedAt,
    required this.browserVersion,
    required this.signalId,
    required this.signalStatus,
    required this.observedValue,
    required this.signalNotes,
    required this.checkId,
    required this.checkStatus,
    required this.checkNotes,
    required this.entryStatus,
    required this.writeTemplatesDir,
    required this.templateTargetId,
    required this.jsonOutputPath,
    required this.targetPreset,
    required this.targetIds,
    required this.json,
    required this.strict,
  });

  final bool help;
  final String inputDir;
  final String? outputPath;
  final String? writePlanPath;
  final String? writeTemplatePath;
  final String? writeStarterPath;
  final String? starterTemplatePath;
  final String? updateProvenancePath;
  final String? updatePageSignalPath;
  final String? updateCheckPath;
  final String? reviewedBy;
  final String? capturedAt;
  final String? browserVersion;
  final String? signalId;
  final String? signalStatus;
  final String? observedValue;
  final String? signalNotes;
  final String? checkId;
  final String? checkStatus;
  final String? checkNotes;
  final String? entryStatus;
  final String? writeTemplatesDir;
  final String? templateTargetId;
  final String? jsonOutputPath;
  final String targetPreset;
  final List<String> targetIds;
  final bool json;
  final bool strict;

  static _Options parse(List<String> args) {
    var help = false;
    var inputDir = '../../profiling/web/manual';
    String? outputPath;
    String? writePlanPath;
    String? writeTemplatePath;
    String? writeStarterPath;
    String? starterTemplatePath;
    String? updateProvenancePath;
    String? updatePageSignalPath;
    String? updateCheckPath;
    String? reviewedBy;
    String? capturedAt;
    String? browserVersion;
    String? signalId;
    String? signalStatus;
    String? observedValue;
    String? signalNotes;
    String? checkId;
    String? checkStatus;
    String? checkNotes;
    String? entryStatus;
    String? writeTemplatesDir;
    String? templateTargetId;
    String? jsonOutputPath;
    var targetPreset = 'v1';
    final targetIds = <String>[];
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--input=')) {
        inputDir = arg.substring('--input='.length);
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--write-plan=')) {
        writePlanPath = arg.substring('--write-plan='.length);
      } else if (arg.startsWith('--write-template=')) {
        writeTemplatePath = arg.substring('--write-template='.length);
      } else if (arg.startsWith('--write-starter=')) {
        writeStarterPath = arg.substring('--write-starter='.length).trim();
        if (writeStarterPath.isEmpty) {
          stderr.writeln('--write-starter requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--starter-template=')) {
        starterTemplatePath = arg
            .substring('--starter-template='.length)
            .trim();
        if (starterTemplatePath.isEmpty) {
          stderr.writeln('--starter-template requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--update-provenance=')) {
        updateProvenancePath = arg
            .substring('--update-provenance='.length)
            .trim();
        if (updateProvenancePath.isEmpty) {
          stderr.writeln('--update-provenance requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--update-page-signal=')) {
        updatePageSignalPath = arg
            .substring('--update-page-signal='.length)
            .trim();
        if (updatePageSignalPath.isEmpty) {
          stderr.writeln('--update-page-signal requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--update-check=')) {
        updateCheckPath = arg.substring('--update-check='.length).trim();
        if (updateCheckPath.isEmpty) {
          stderr.writeln('--update-check requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--reviewed-by=')) {
        reviewedBy = arg.substring('--reviewed-by='.length);
      } else if (arg.startsWith('--captured-at=')) {
        capturedAt = arg.substring('--captured-at='.length);
      } else if (arg.startsWith('--browser-version=')) {
        browserVersion = arg.substring('--browser-version='.length);
      } else if (arg.startsWith('--signal-id=')) {
        signalId = arg.substring('--signal-id='.length);
      } else if (arg.startsWith('--signal-status=')) {
        signalStatus = arg.substring('--signal-status='.length);
      } else if (arg.startsWith('--observed-value=')) {
        observedValue = arg.substring('--observed-value='.length);
      } else if (arg.startsWith('--signal-notes=')) {
        signalNotes = arg.substring('--signal-notes='.length);
      } else if (arg.startsWith('--check-id=')) {
        checkId = arg.substring('--check-id='.length);
      } else if (arg.startsWith('--check-status=')) {
        checkStatus = arg.substring('--check-status='.length);
      } else if (arg.startsWith('--check-notes=')) {
        checkNotes = arg.substring('--check-notes='.length);
      } else if (arg.startsWith('--entry-status=')) {
        entryStatus = arg.substring('--entry-status='.length);
      } else if (arg.startsWith('--write-templates=')) {
        writeTemplatesDir = arg.substring('--write-templates='.length).trim();
        if (writeTemplatesDir.isEmpty) {
          stderr.writeln('--write-templates requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--template-target=')) {
        templateTargetId = arg.substring('--template-target='.length);
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length).trim();
        if (jsonOutputPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--target-preset=')) {
        targetPreset = arg.substring('--target-preset='.length);
      } else if (arg.startsWith('--target=')) {
        targetIds.add(arg.substring('--target='.length));
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for web_manual_validation: $arg');
        _printUsage();
        exit(2);
      }
    }

    return _Options(
      help: help,
      inputDir: inputDir,
      outputPath: outputPath,
      writePlanPath: writePlanPath,
      writeTemplatePath: writeTemplatePath,
      writeStarterPath: writeStarterPath,
      starterTemplatePath: starterTemplatePath,
      updateProvenancePath: updateProvenancePath,
      updatePageSignalPath: updatePageSignalPath,
      updateCheckPath: updateCheckPath,
      reviewedBy: reviewedBy,
      capturedAt: capturedAt,
      browserVersion: browserVersion,
      signalId: signalId,
      signalStatus: signalStatus,
      observedValue: observedValue,
      signalNotes: signalNotes,
      checkId: checkId,
      checkStatus: checkStatus,
      checkNotes: checkNotes,
      entryStatus: entryStatus,
      writeTemplatesDir: writeTemplatesDir,
      templateTargetId: templateTargetId,
      jsonOutputPath: jsonOutputPath,
      targetPreset: targetPreset,
      targetIds: List.unmodifiable(targetIds),
      json: json,
      strict: strict,
    );
  }
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_manual_validation.dart [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=DIR                  Manual evidence directory, default ../../profiling/web/manual.',
  );
  stdout.writeln('  --output=PATH                Markdown audit output path.');
  stdout.writeln(
    '  --write-plan=PATH            Write manual validation plan Markdown.',
  );
  stdout.writeln(
    '  --write-template=PATH        Write a JSON evidence template.',
  );
  stdout.writeln(
    '  --write-starter=PATH         Write a no-overwrite starter evidence file.',
  );
  stdout.writeln(
    '  --starter-template=PATH      Template source for --write-starter.',
  );
  stdout.writeln(
    '  --update-provenance=PATH     Update provenance fields on an evidence file.',
  );
  stdout.writeln(
    '  --update-page-signal=PATH    Update one required page signal in an evidence file.',
  );
  stdout.writeln(
    '  --update-check=PATH          Update one required check in an evidence file.',
  );
  stdout.writeln(
    '  --reviewed-by=NAME           Reviewer value for --update-provenance.',
  );
  stdout.writeln(
    '  --captured-at=ISO|now        Capture time for --update-provenance.',
  );
  stdout.writeln(
    '  --browser-version=VERSION    Browser version for --update-provenance.',
  );
  stdout.writeln(
    '  --signal-id=ID               Required page signal to update.',
  );
  stdout.writeln(
    '  --signal-status=STATUS       pass, fail, blocked, or needsReview.',
  );
  stdout.writeln('  --observed-value=VALUE       Observed page signal value.');
  stdout.writeln(
    '  --signal-notes=TEXT          Reviewer observation notes for the page signal.',
  );
  stdout.writeln('  --check-id=ID                Required check to update.');
  stdout.writeln(
    '  --check-status=STATUS        pass, fail, blocked, or needsReview.',
  );
  stdout.writeln(
    '  --check-notes=TEXT           Reviewer observation notes for the check.',
  );
  stdout.writeln(
    '  --entry-status=STATUS        Set top-level evidence status.',
  );
  stdout.writeln(
    '  --write-templates=DIR        Write selected target templates into DIR.',
  );
  stdout.writeln(
    '  --template-target=ID         Target for template generation.',
  );
  stdout.writeln('  --json-output=PATH           JSON audit output path.');
  stdout.writeln(
    '  --target-preset=v1|all          Target preset, default v1.',
  );
  stdout.writeln('  --target=ID                  Restrict audit to a target.');
  stdout.writeln(
    '  --strict                     Exit non-zero unless targets pass.',
  );
  stdout.writeln(
    '  --json                       Print machine-readable audit JSON.',
  );
}
