import 'dart:convert';
import 'dart:io';

import 'readiness_bundle_verifier.dart';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final audit = _buildAudit(options);
  final jsonText = const JsonEncoder.withIndent('  ').convert(audit);
  if (options.jsonOutputPath != null) {
    final output = File(options.jsonOutputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$jsonText\n');
  }
  if (options.json) {
    stdout.writeln(jsonText);
  }

  final markdown = _markdown(audit);
  if (options.outputPath == null) {
    if (!options.json) stdout.write(markdown);
  } else {
    final output = File(options.outputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(markdown);
    if (!options.json) stdout.writeln('wrote ${output.path}');
  }

  if (options.strict && audit['strictPass'] != true) exit(1);
}

Map<String, Object?> _buildAudit(_Options options) {
  final loaded = _loadReadiness(options.readinessPath);
  final checks = <_PreflightCheck>[];
  final readiness = loaded.json;
  if (loaded.failure != null) {
    checks.add(loaded.failure!);
  } else if (readiness == null) {
    checks.add(
      _PreflightCheck(
        id: 'readinessArtifact',
        label: 'Phase 6 readiness artifact',
        strictPass: false,
        blockers: const ['readiness artifact could not be loaded'],
        details: const <String, Object?>{},
      ),
    );
  } else {
    checks.add(_readinessCheck(readiness));
  }
  if (options.bundlePath != null) {
    checks.add(
      _readinessBundleCheck(options.bundlePath!, options.readinessPath),
    );
  } else if (!options.allowUnbundled) {
    checks.add(_missingReadinessBundleCheck(options.readinessPath));
  }
  if (options.automatedValidationPath != null) {
    checks.add(_automatedValidationCheck(options.automatedValidationPath!));
  }

  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebDefaultPreflight',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'target': options.target.id,
    'targetDescription': options.target.description,
    'diagnosticOnly': options.allowUnbundled,
    if (options.allowUnbundled)
      'diagnosticReason':
          'Unbundled readiness-only diagnostics do not satisfy default or temporary-path-retirement release gates.',
    'finalGateRequiresBundle': true,
    'finalGateRequiresAutomatedValidation': true,
    if (options.allowUnbundled) ...<String, Object?>{
      'finalGateBundlePath': _defaultBundlePathFor(options.readinessPath),
      'finalGateAutomatedValidationPath': _defaultAutomatedValidationPathFor(
        options.readinessPath,
      ),
    },
    'readinessPath': options.readinessPath,
    if (options.bundlePath != null) 'bundlePath': options.bundlePath,
    'bundleRequired': !options.allowUnbundled,
    'bundleBound': options.bundlePath != null,
    if (options.automatedValidationPath != null)
      'automatedValidationPath': options.automatedValidationPath,
    'automatedValidationRequired': !options.allowUnbundled,
    'automatedValidationBound': options.automatedValidationPath != null,
    'strictPass': checks.every((check) => check.strictPass),
    'checks': [for (final check in checks) check.toJson()],
  };
}

_PreflightCheck _readinessCheck(Map<String, Object?> readiness) {
  final blockers = <String>[];
  final failedChecks = <Map<String, Object?>>[];
  if (readiness['strictPass'] != true) {
    for (final check in _maps(readiness['checks'])) {
      if (check['strictPass'] == true) continue;
      final id = check['id']?.toString() ?? '?';
      final label = check['label']?.toString() ?? id;
      final checkBlockers = _strings(check['blockers']);
      final checkDetails = _map(check['details']);
      failedChecks.add(<String, Object?>{
        'id': id,
        'label': label,
        'blockers': checkBlockers,
        if (checkDetails.isNotEmpty) 'details': checkDetails,
      });
      if (checkBlockers.isEmpty) {
        blockers.add('$label did not strict-pass');
      } else {
        blockers.add('$label: ${checkBlockers.join('; ')}');
      }
    }
    if (blockers.isEmpty) {
      blockers.add('readiness strictPass is not true');
    }
  }

  return _PreflightCheck(
    id: 'phase6Readiness',
    label: 'Phase 6 readiness',
    strictPass: blockers.isEmpty,
    blockers: blockers,
    details: <String, Object?>{
      'readinessStrictPass': readiness['strictPass'] == true,
      if (failedChecks.isNotEmpty) 'failedChecks': failedChecks,
    },
  );
}

_LoadedReadiness _loadReadiness(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return _LoadedReadiness.failure(
      _PreflightCheck(
        id: 'readinessArtifact',
        label: 'Phase 6 readiness artifact',
        strictPass: false,
        blockers: ['missing readiness artifact: $path'],
        details: const <String, Object?>{},
      ),
    );
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return _LoadedReadiness.failure(
      _PreflightCheck(
        id: 'readinessArtifact',
        label: 'Phase 6 readiness artifact',
        strictPass: false,
        blockers: ['invalid JSON: ${error.message}'],
        details: const <String, Object?>{},
      ),
    );
  }
  if (decoded is! Map) {
    return _LoadedReadiness.failure(
      const _PreflightCheck(
        id: 'readinessArtifact',
        label: 'Phase 6 readiness artifact',
        strictPass: false,
        blockers: ['readiness artifact is not a JSON object'],
        details: <String, Object?>{},
      ),
    );
  }
  final json = decoded.cast<String, Object?>();
  if (json['kind'] != 'fleuryWebReadinessAudit') {
    return _LoadedReadiness.failure(
      _PreflightCheck(
        id: 'readinessArtifact',
        label: 'Phase 6 readiness artifact',
        strictPass: false,
        blockers: [
          'unexpected artifact kind ${json['kind'] ?? '<missing>'}; expected fleuryWebReadinessAudit',
        ],
        details: const <String, Object?>{},
      ),
    );
  }
  return _LoadedReadiness.success(json);
}

_PreflightCheck _missingReadinessBundleCheck(String readinessPath) {
  return _PreflightCheck(
    id: 'readinessBundle',
    label: 'Readiness bundle fingerprints',
    strictPass: false,
    blockers: const [
      'readiness bundle is required; pass --bundle=PATH or use --allow-unbundled for diagnostics only',
    ],
    details: <String, Object?>{
      'bundleRequired': true,
      'readinessPath': File(readinessPath).absolute.path,
    },
  );
}

_PreflightCheck _readinessBundleCheck(String bundlePath, String readinessPath) {
  final file = File(bundlePath);
  if (!file.existsSync()) {
    return _PreflightCheck(
      id: 'readinessBundle',
      label: 'Readiness bundle fingerprints',
      strictPass: false,
      blockers: ['missing readiness bundle: $bundlePath'],
      details: <String, Object?>{'bundlePath': file.absolute.path},
    );
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return _PreflightCheck(
      id: 'readinessBundle',
      label: 'Readiness bundle fingerprints',
      strictPass: false,
      blockers: ['invalid readiness bundle JSON: ${error.message}'],
      details: <String, Object?>{'bundlePath': file.absolute.path},
    );
  }
  if (decoded is! Map) {
    return _PreflightCheck(
      id: 'readinessBundle',
      label: 'Readiness bundle fingerprints',
      strictPass: false,
      blockers: const ['readiness bundle is not a JSON object'],
      details: <String, Object?>{'bundlePath': file.absolute.path},
    );
  }

  final bundle = decoded.cast<String, Object?>();
  if (bundle['kind'] != 'fleuryWebReadinessBundle') {
    return _PreflightCheck(
      id: 'readinessBundle',
      label: 'Readiness bundle fingerprints',
      strictPass: false,
      blockers: [
        'unexpected bundle kind ${bundle['kind'] ?? '<missing>'}; expected fleuryWebReadinessBundle',
      ],
      details: <String, Object?>{'bundlePath': file.absolute.path},
    );
  }

  final artifactsRaw = bundle['artifacts'];
  final fingerprintsRaw = bundle['artifactFingerprints'];
  final sourceInputFingerprintsRaw = bundle['sourceInputFingerprints'];
  final blockers = <String>[];
  final details = <String, Object?>{
    'bundlePath': file.absolute.path,
    'readinessPath': File(readinessPath).absolute.path,
  };

  if (artifactsRaw is! Map) {
    blockers.add('readiness bundle artifacts must be a JSON object');
  }
  if (fingerprintsRaw is! Map) {
    blockers.add('readiness bundle artifactFingerprints must be a JSON object');
  }
  if (sourceInputFingerprintsRaw is! Map) {
    blockers.add(
      'readiness bundle sourceInputFingerprints must be a JSON object',
    );
  }
  if (artifactsRaw is! Map || fingerprintsRaw is! Map) {
    return _PreflightCheck(
      id: 'readinessBundle',
      label: 'Readiness bundle fingerprints',
      strictPass: false,
      blockers: blockers,
      details: details,
    );
  }

  final artifacts = artifactsRaw.cast<String, Object?>();
  final fingerprints = fingerprintsRaw.cast<String, Object?>();
  final bundleReadinessPath = artifacts['readinessJson'];
  if (bundleReadinessPath is String && bundleReadinessPath.trim().isNotEmpty) {
    details['bundleReadinessPath'] = File(bundleReadinessPath).absolute.path;
    if (File(bundleReadinessPath).absolute.path !=
        File(readinessPath).absolute.path) {
      blockers.add(
        'bundle readinessJson path ${File(bundleReadinessPath).absolute.path} does not match preflight readiness path ${File(readinessPath).absolute.path}',
      );
    }
  } else {
    blockers.add('readiness bundle artifacts.readinessJson is missing');
  }

  final state = ReadinessBundleVerificationState();
  verifyReadinessBundleArtifacts(
    artifacts: artifacts,
    fingerprints: fingerprints,
    state: state,
  );
  if (sourceInputFingerprintsRaw is Map) {
    verifyReadinessBundleSourceInputFingerprints(
      sourceInputFingerprintsRaw.cast<String, Object?>(),
      state: state,
    );
    verifyReadinessBundleExpectedSourceInputCoverage(bundle, state: state);
  } else {
    state.missingSourceFingerprints.add('sourceInputFingerprints');
  }
  verifyReadinessBundleCommandWorkingDirectory(bundle, state: state);
  verifyReadinessBundleManifestConsistency(bundle, state: state);
  if (state.mismatches.isNotEmpty) {
    blockers.add(
      'readiness bundle has ${state.mismatches.length} artifact fingerprint mismatch${state.mismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingArtifacts.isNotEmpty) {
    blockers.add(
      'readiness bundle is missing ${state.missingArtifacts.length} artifact${state.missingArtifacts.length == 1 ? '' : 's'}',
    );
  }
  if (state.missingFingerprints.isNotEmpty) {
    blockers.add(
      'readiness bundle is missing ${state.missingFingerprints.length} artifact fingerprint${state.missingFingerprints.length == 1 ? '' : 's'}',
    );
  }
  if (state.sourceMismatches.isNotEmpty) {
    blockers.add(
      'readiness bundle has ${state.sourceMismatches.length} source input fingerprint mismatch${state.sourceMismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingSourceInputs.isNotEmpty) {
    blockers.add(
      'readiness bundle is missing ${state.missingSourceInputs.length} source input${state.missingSourceInputs.length == 1 ? '' : 's'}',
    );
  }
  if (state.missingSourceFingerprints.isNotEmpty) {
    blockers.add(
      'readiness bundle is missing ${state.missingSourceFingerprints.length} source input fingerprint${state.missingSourceFingerprints.length == 1 ? '' : 's'}',
    );
  }
  if (state.metadataMismatches.isNotEmpty) {
    blockers.add(
      'readiness bundle has ${state.metadataMismatches.length} metadata mismatch${state.metadataMismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingMetadata.isNotEmpty) {
    blockers.add(
      'readiness bundle is missing ${state.missingMetadata.length} required metadata field${state.missingMetadata.length == 1 ? '' : 's'}',
    );
  }
  if (state.manifestMismatches.isNotEmpty) {
    blockers.add(
      'readiness bundle has ${state.manifestMismatches.length} manifest mismatch${state.manifestMismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingManifestFields.isNotEmpty) {
    blockers.add(
      'readiness bundle is missing ${state.missingManifestFields.length} manifest field${state.missingManifestFields.length == 1 ? '' : 's'}',
    );
  }

  details
    ..['checkedArtifactCount'] = state.checkedArtifactCount
    ..['mismatchCount'] = state.mismatches.length
    ..['missingArtifactCount'] = state.missingArtifacts.length
    ..['missingFingerprintCount'] = state.missingFingerprints.length
    ..['checkedSourceInputCount'] = state.checkedSourceInputCount
    ..['sourceMismatchCount'] = state.sourceMismatches.length
    ..['missingSourceInputCount'] = state.missingSourceInputs.length
    ..['missingSourceFingerprintCount'] = state.missingSourceFingerprints.length
    ..['checkedMetadataCount'] = state.checkedMetadataCount
    ..['metadataMismatchCount'] = state.metadataMismatches.length
    ..['missingMetadataCount'] = state.missingMetadata.length
    ..['checkedManifestFieldCount'] = state.checkedManifestFieldCount
    ..['manifestMismatchCount'] = state.manifestMismatches.length
    ..['missingManifestFieldCount'] = state.missingManifestFields.length;
  if (state.mismatches.isNotEmpty) details['mismatches'] = state.mismatches;
  if (state.missingArtifacts.isNotEmpty) {
    details['missingArtifacts'] = state.missingArtifacts;
  }
  if (state.missingFingerprints.isNotEmpty) {
    details['missingFingerprints'] = state.missingFingerprints;
  }
  if (state.sourceMismatches.isNotEmpty) {
    details['sourceMismatches'] = state.sourceMismatches;
  }
  if (state.missingSourceInputs.isNotEmpty) {
    details['missingSourceInputs'] = state.missingSourceInputs;
  }
  if (state.missingSourceFingerprints.isNotEmpty) {
    details['missingSourceFingerprints'] = state.missingSourceFingerprints;
  }
  if (state.metadataMismatches.isNotEmpty) {
    details['metadataMismatches'] = state.metadataMismatches;
  }
  if (state.missingMetadata.isNotEmpty) {
    details['missingMetadata'] = state.missingMetadata;
  }
  if (state.manifestMismatches.isNotEmpty) {
    details['manifestMismatches'] = state.manifestMismatches;
  }
  if (state.missingManifestFields.isNotEmpty) {
    details['missingManifestFields'] = state.missingManifestFields;
  }

  return _PreflightCheck(
    id: 'readinessBundle',
    label: 'Readiness bundle fingerprints',
    strictPass: blockers.isEmpty,
    blockers: blockers,
    details: details,
  );
}

_PreflightCheck _automatedValidationCheck(String automatedValidationPath) {
  final file = File(automatedValidationPath);
  if (!file.existsSync()) {
    return _PreflightCheck(
      id: 'automatedValidation',
      label: 'Automated retained host validation',
      strictPass: false,
      blockers: [
        'missing automated validation artifact: $automatedValidationPath',
      ],
      details: <String, Object?>{'automatedValidationPath': file.absolute.path},
    );
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    return _PreflightCheck(
      id: 'automatedValidation',
      label: 'Automated retained host validation',
      strictPass: false,
      blockers: ['invalid automated validation JSON: ${error.message}'],
      details: <String, Object?>{'automatedValidationPath': file.absolute.path},
    );
  }
  if (decoded is! Map) {
    return _PreflightCheck(
      id: 'automatedValidation',
      label: 'Automated retained host validation',
      strictPass: false,
      blockers: const ['automated validation artifact is not a JSON object'],
      details: <String, Object?>{'automatedValidationPath': file.absolute.path},
    );
  }

  final validation = decoded.cast<String, Object?>();
  final state = ReadinessBundleVerificationState();
  verifyWebAutomatedValidationArtifact(validation, state: state);
  final blockers = <String>[];
  if (state.sourceMismatches.isNotEmpty) {
    blockers.add(
      'automated validation has ${state.sourceMismatches.length} source input fingerprint mismatch${state.sourceMismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingSourceInputs.isNotEmpty) {
    blockers.add(
      'automated validation is missing ${state.missingSourceInputs.length} source input${state.missingSourceInputs.length == 1 ? '' : 's'}',
    );
  }
  if (state.missingSourceFingerprints.isNotEmpty) {
    blockers.add(
      'automated validation is missing ${state.missingSourceFingerprints.length} source input fingerprint${state.missingSourceFingerprints.length == 1 ? '' : 's'}',
    );
  }
  if (state.metadataMismatches.isNotEmpty) {
    blockers.add(
      'automated validation has ${state.metadataMismatches.length} metadata mismatch${state.metadataMismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingMetadata.isNotEmpty) {
    blockers.add(
      'automated validation is missing ${state.missingMetadata.length} required metadata field${state.missingMetadata.length == 1 ? '' : 's'}',
    );
  }
  if (state.manifestMismatches.isNotEmpty) {
    blockers.add(
      'automated validation has ${state.manifestMismatches.length} manifest mismatch${state.manifestMismatches.length == 1 ? '' : 'es'}',
    );
  }
  if (state.missingManifestFields.isNotEmpty) {
    blockers.add(
      'automated validation is missing ${state.missingManifestFields.length} manifest field${state.missingManifestFields.length == 1 ? '' : 's'}',
    );
  }

  final details = <String, Object?>{
    'automatedValidationPath': file.absolute.path,
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
  };
  if (state.sourceMismatches.isNotEmpty) {
    details['sourceMismatches'] = state.sourceMismatches;
  }
  if (state.missingSourceInputs.isNotEmpty) {
    details['missingSourceInputs'] = state.missingSourceInputs;
  }
  if (state.missingSourceFingerprints.isNotEmpty) {
    details['missingSourceFingerprints'] = state.missingSourceFingerprints;
  }
  if (state.metadataMismatches.isNotEmpty) {
    details['metadataMismatches'] = state.metadataMismatches;
  }
  if (state.missingMetadata.isNotEmpty) {
    details['missingMetadata'] = state.missingMetadata;
  }
  if (state.manifestMismatches.isNotEmpty) {
    details['manifestMismatches'] = state.manifestMismatches;
  }
  if (state.missingManifestFields.isNotEmpty) {
    details['missingManifestFields'] = state.missingManifestFields;
  }

  return _PreflightCheck(
    id: 'automatedValidation',
    label: 'Automated retained host validation',
    strictPass: blockers.isEmpty,
    blockers: blockers,
    details: details,
  );
}

String _markdown(Map<String, Object?> audit) {
  final checks = _maps(audit['checks']);
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Default Preflight')
    ..writeln()
    ..writeln('Generated at `${audit['generatedAt']}`.')
    ..writeln()
    ..writeln('Target: `${audit['target']}`.')
    ..writeln()
    ..writeln('${audit['targetDescription']}')
    ..writeln()
    ..writeln('Diagnostic only: `${audit['diagnosticOnly']}`.')
    ..writeln();
  if (audit['diagnosticOnly'] == true) {
    buffer
      ..writeln('${audit['diagnosticReason']}')
      ..writeln()
      ..writeln('Final gate bundle path: `${audit['finalGateBundlePath']}`.')
      ..writeln()
      ..writeln(
        'Final gate automated validation path: `${audit['finalGateAutomatedValidationPath']}`.',
      )
      ..writeln();
  }
  buffer
    ..writeln('Readiness artifact: `${audit['readinessPath']}`.')
    ..writeln()
    ..writeln('Readiness bundle required: `${audit['bundleRequired']}`.')
    ..writeln()
    ..writeln(
      'Final gate requires bundle: `${audit['finalGateRequiresBundle']}`.',
    )
    ..writeln()
    ..writeln('Bundle bound: `${audit['bundleBound']}`.')
    ..writeln()
    ..writeln(
      'Automated validation required: `${audit['automatedValidationRequired']}`.',
    )
    ..writeln()
    ..writeln(
      'Final gate requires automated validation: `${audit['finalGateRequiresAutomatedValidation']}`.',
    )
    ..writeln()
    ..writeln(
      'Automated validation bound: `${audit['automatedValidationBound']}`.',
    )
    ..writeln()
    ..writeln('Strict pass: `${audit['strictPass']}`.')
    ..writeln()
    ..writeln('| Check | Status | Blockers |')
    ..writeln('| --- | --- | --- |');
  for (final check in checks) {
    final blockers = _strings(check['blockers']);
    buffer.writeln(
      '| ${check['label']} | ${check['strictPass'] == true ? 'pass' : 'FAIL'} | '
      '${blockers.isEmpty ? '-' : blockers.join('<br>')} |',
    );
  }
  _writeManualTargetDiagnostics(buffer, checks);
  return buffer.toString();
}

void _writeManualTargetDiagnostics(
  StringBuffer buffer,
  List<Map<String, Object?>> checks,
) {
  final targets = <Map<String, Object?>>[];
  for (final preflightCheck in checks) {
    final details = _map(preflightCheck['details']);
    for (final failedCheck in _maps(details['failedChecks'])) {
      final failedDetails = _map(failedCheck['details']);
      if (failedCheck['id'] != 'manualValidation') continue;
      targets.addAll(_maps(failedDetails['failingTargetDetails']));
    }
  }
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

int _int(Map<String, Object?> json, String key) =>
    (json[key] as num?)?.toInt() ?? 0;

final class _LoadedReadiness {
  const _LoadedReadiness.success(this.json) : failure = null;
  const _LoadedReadiness.failure(this.failure) : json = null;

  final Map<String, Object?>? json;
  final _PreflightCheck? failure;
}

final class _PreflightCheck {
  const _PreflightCheck({
    required this.id,
    required this.label,
    required this.strictPass,
    required this.blockers,
    required this.details,
  });

  final String id;
  final String label;
  final bool strictPass;
  final List<String> blockers;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'strictPass': strictPass,
      'blockers': blockers,
      'details': details,
    };
  }
}

enum _PreflightTarget {
  makeDomDefault(
    'make-dom-default',
    'Allow the retained DOM host to become the default Fleury-owned web surface.',
  ),
  retireTemporaryPaths(
    'retire-temporary-paths',
    'Allow temporary web transport paths to be retired after retained DOM readiness.',
  );

  const _PreflightTarget(this.id, this.description);

  final String id;
  final String description;

  static _PreflightTarget parse(String value) {
    for (final target in values) {
      if (target.id == value) return target;
    }
    stderr.writeln('Unknown web default preflight target: $value');
    _printUsage();
    exit(2);
  }
}

final class _Options {
  const _Options({
    required this.help,
    required this.readinessPath,
    required this.bundlePath,
    required this.automatedValidationPath,
    required this.target,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.json,
    required this.strict,
    required this.allowUnbundled,
  });

  final bool help;
  final String readinessPath;
  final String? bundlePath;
  final String? automatedValidationPath;
  final _PreflightTarget target;
  final String? outputPath;
  final String? jsonOutputPath;
  final bool json;
  final bool strict;
  final bool allowUnbundled;

  static _Options parse(List<String> args) {
    var help = false;
    var readinessPath =
        '../../profiling/web/baselines/web-readiness-bundle/web-readiness.json';
    String? bundlePath;
    String? automatedValidationPath;
    var target = _PreflightTarget.makeDomDefault;
    String? outputPath;
    String? jsonOutputPath;
    var json = false;
    var strict = false;
    var allowUnbundled = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--readiness=')) {
        readinessPath = arg.substring('--readiness='.length);
      } else if (arg.startsWith('--bundle=')) {
        bundlePath = arg.substring('--bundle='.length).trim();
      } else if (arg.startsWith('--automated-validation=')) {
        automatedValidationPath = arg
            .substring('--automated-validation='.length)
            .trim();
      } else if (arg.startsWith('--target=')) {
        target = _PreflightTarget.parse(arg.substring('--target='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length).trim();
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg == '--allow-unbundled') {
        allowUnbundled = true;
      } else {
        stderr.writeln('Unknown option for web_default_preflight: $arg');
        _printUsage();
        exit(2);
      }
    }
    if (jsonOutputPath != null && jsonOutputPath.isEmpty) {
      stderr.writeln('--json-output requires a non-empty path.');
      exit(2);
    }
    if (bundlePath != null && bundlePath.isEmpty) {
      stderr.writeln('--bundle requires a non-empty path.');
      exit(2);
    }
    if (automatedValidationPath != null && automatedValidationPath.isEmpty) {
      stderr.writeln('--automated-validation requires a non-empty path.');
      exit(2);
    }

    final effectiveBundlePath =
        bundlePath ??
        (allowUnbundled ? null : _defaultBundlePathFor(readinessPath));
    final effectiveAutomatedValidationPath =
        automatedValidationPath ??
        (allowUnbundled
            ? null
            : _defaultAutomatedValidationPathFor(readinessPath));

    return _Options(
      help: help,
      readinessPath: readinessPath,
      bundlePath: effectiveBundlePath,
      automatedValidationPath: effectiveAutomatedValidationPath,
      target: target,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      json: json,
      strict: strict,
      allowUnbundled: allowUnbundled,
    );
  }
}

String _defaultBundlePathFor(String readinessPath) {
  return '${File(readinessPath).parent.path}${Platform.pathSeparator}web-readiness-bundle.json';
}

String _defaultAutomatedValidationPathFor(String readinessPath) {
  return '${File(readinessPath).parent.path}${Platform.pathSeparator}$webAutomatedValidationFileName';
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_default_preflight.dart [options]');
  stdout.writeln('');
  stdout.writeln(
    'Consumes a strict Phase 6 web-readiness JSON artifact and reports whether',
  );
  stdout.writeln(
    'a retained-DOM default flip or temporary-path retirement is unblocked.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --readiness=PATH  web_readiness.dart JSON artifact.');
  stdout.writeln(
    '  --bundle=PATH     web-readiness-bundle.json manifest to verify.',
  );
  stdout.writeln(
    '                    Defaults to sibling web-readiness-bundle.json.',
  );
  stdout.writeln('  --automated-validation=PATH');
  stdout.writeln(
    '                    web_automated_validation.dart JSON evidence.',
  );
  stdout.writeln(
    '                    Defaults to sibling $webAutomatedValidationFileName.',
  );
  stdout.writeln(
    '  --allow-unbundled Permit readiness-only diagnostics; not a release gate.',
  );
  stdout.writeln(
    '  --target=ID       make-dom-default or retire-temporary-paths.',
  );
  stdout.writeln('  --output=PATH     Markdown output path.');
  stdout.writeln('  --json-output=PATH Write machine-readable preflight JSON.');
  stdout.writeln('  --strict          Exit non-zero unless preflight passes.');
  stdout.writeln('  --json            Print machine-readable preflight JSON.');
}
