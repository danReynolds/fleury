import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final input = File(options.inputPath!);
  final policy = _loadPolicy(input);
  final inputPolicyFingerprint = _jsonFingerprint(policy);
  _validateExpectedInputFingerprint(
    actual: inputPolicyFingerprint,
    expected: options.expectedInputFingerprint,
  );
  final overBudgetScenarios = _overBudgetScenarios(policy);
  if (options.writePlanPath != null) {
    final planOutput = File(options.writePlanPath!);
    planOutput.parent.createSync(recursive: true);
    final reviewedOutputPath =
        options.outputPath ?? _defaultReviewedOutputPath(input.path);
    planOutput.writeAsStringSync(
      _reviewPlanMarkdown(
        policy,
        inputPath: input.absolute.path,
        inputPolicyFingerprint: inputPolicyFingerprint,
        reviewedOutputPath: reviewedOutputPath,
        reviewContextHint: options.reviewContextHint,
        summaryOutputPath:
            options.jsonOutputPath ??
            _defaultReviewSummaryPath(reviewedOutputPath),
      ),
    );
    stdout.writeln('wrote ${planOutput.path}');
  }
  if (!options.promote) return;

  if (overBudgetScenarios.isNotEmpty) {
    if (!options.allowOverBudgetThresholds) {
      stderr.writeln(
        'threshold review input allows over-budget frames for '
        '${overBudgetScenarios.length} scenario'
        '${overBudgetScenarios.length == 1 ? '' : 's'}; rerun with '
        '--allow-over-budget-thresholds and a concrete --review-note=TEXT '
        'after explicitly accepting those thresholds',
      );
      exit(2);
    }
    if (options.reviewNote == null ||
        options.reviewNote!.trim().isEmpty ||
        _containsPlaceholder(options.reviewNote!)) {
      stderr.writeln(
        'web_threshold_review requires --review-note=TEXT to justify '
        '--allow-over-budget-thresholds',
      );
      exit(2);
    }
  }

  final reviewedAt = _reviewedAt(options.reviewedAt);
  final reviewed = _reviewPolicy(
    policy,
    reviewedBy: options.reviewedBy!,
    reviewedAt: reviewedAt,
    reviewContext: options.reviewContext!,
    reviewNote: options.reviewNote,
    overBudgetScenarios: overBudgetScenarios,
  );
  final outputPolicyFingerprint = _jsonFingerprint(reviewed);

  final output = File(options.outputPath!);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(reviewed)}\n',
  );

  final summary = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebThresholdReview',
    'inputPath': input.absolute.path,
    'outputPath': output.absolute.path,
    'reviewState': reviewed['reviewState'],
    'reviewedBy': reviewed['reviewedBy'],
    'reviewedAt': reviewed['reviewedAt'],
    'reviewContext': reviewed['reviewContext'],
    'scenarioCount': (reviewed['scenarios'] as Map<String, Object?>).length,
    'inputPolicyFingerprint': inputPolicyFingerprint,
    'outputPolicyFingerprint': outputPolicyFingerprint,
    if (reviewed['generatedFrom'] != null)
      'generatedFrom': reviewed['generatedFrom'],
    'overBudgetThresholdScenarioCount': overBudgetScenarios.length,
    'overBudgetThresholdScenarioIds': [
      for (final scenario in overBudgetScenarios) scenario.id,
    ],
    'overBudgetThresholdsAcknowledged': overBudgetScenarios.isEmpty
        ? false
        : options.allowOverBudgetThresholds,
    'scenarioIds': [
      for (final id in (reviewed['scenarios'] as Map<String, Object?>).keys) id,
    ],
  };
  if (options.jsonOutputPath != null) {
    final jsonOutput = File(options.jsonOutputPath!);
    jsonOutput.parent.createSync(recursive: true);
    jsonOutput.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
    );
  }

  if (options.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
  } else {
    stdout.writeln('wrote ${output.path}');
  }
}

String _reviewPlanMarkdown(
  Map<String, Object?> policy, {
  required String inputPath,
  required String inputPolicyFingerprint,
  required String reviewedOutputPath,
  required String? reviewContextHint,
  required String summaryOutputPath,
}) {
  final scenarios = (policy['scenarios'] as Map).cast<String, Object?>();
  final generatedFrom = _map(policy['generatedFrom']);
  final generatedCaptureEnvironment = _map(generatedFrom['captureEnvironment']);
  final generatedReviewContextHint = _nonEmptyString(
    generatedCaptureEnvironment['reviewContextHint'],
  );
  final overBudgetScenarios = _overBudgetScenarios(policy);
  final missingRuntimeSubphaseScenarios = _missingRuntimeSubphaseScenarios(
    scenarios,
  );
  final explicitReviewContextHint = _nonEmptyString(reviewContextHint);
  final promotionReviewContext =
      explicitReviewContextHint ??
      generatedReviewContextHint ??
      'Chrome <version> on <platform>, retained DOM product baseline';
  final buffer = StringBuffer()
    ..writeln('# Fleury Web Threshold Review Plan')
    ..writeln()
    ..writeln('- Input: `$inputPath`')
    ..writeln('- Input fingerprint: `$inputPolicyFingerprint`')
    ..writeln('- Review state: `${policy['reviewState'] ?? '<missing>'}`')
    ..writeln('- Scenario count: `${scenarios.length}`');
  if (policy['generatedAt'] != null) {
    buffer.writeln('- Candidate generated at: `${policy['generatedAt']}`');
  }
  if (generatedFrom.isNotEmpty) {
    buffer
      ..writeln('- Capture run count: `${generatedFrom['runCount'] ?? '?'}`')
      ..writeln(
        '- Source metric: `${generatedFrom['sourceMetric'] ?? '<unknown>'}`',
      )
      ..writeln(
        '- Threshold headroom: `${generatedFrom['thresholdHeadroomPercent'] ?? '?'}%`, minimum `${generatedFrom['thresholdMinHeadroomMs'] ?? '?'}ms`',
      );
    if (generatedFrom['inputDir'] != null) {
      buffer.writeln('- Capture input: `${generatedFrom['inputDir']}`');
    }
  }
  if (explicitReviewContextHint != null) {
    buffer.writeln('- Review context hint: `$promotionReviewContext`');
    if (generatedReviewContextHint != null &&
        generatedReviewContextHint != explicitReviewContextHint) {
      buffer.writeln(
        '- Captured review context hint: `$generatedReviewContextHint`',
      );
    }
  } else if (generatedReviewContextHint != null) {
    buffer.writeln('- Review context hint: `$generatedReviewContextHint`');
  }
  buffer
    ..writeln()
    ..writeln('## Review Checklist')
    ..writeln()
    ..writeln(
      '- Confirm the capture input represents the agreed product/browser configuration.',
    )
    ..writeln(
      '- Confirm every release scenario has an explicit threshold entry.',
    )
    ..writeln(
      '- Inspect total-frame thresholds separately from DOM and semantic apply thresholds.',
    )
    ..writeln(
      '- Check runtime build/layout/paint subphase availability before using this review to choose a Dart-side optimization path.',
    )
    ..writeln(
      '- Check over-budget thresholds for scenarios with intentionally slow frames.',
    )
    ..writeln(
      '- Confirm semantic uncovered-cell thresholds remain zero unless an accessibility exception is reviewed.',
    )
    ..writeln(
      '- Record reviewer, timestamp, and product/browser context before promotion.',
    );
  if (missingRuntimeSubphaseScenarios.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Runtime Subphase Timing Availability')
      ..writeln()
      ..writeln(
        'Runtime build/layout/paint subphase samples are unavailable for ${missingRuntimeSubphaseScenarios.length} of ${scenarios.length} scenario${scenarios.length == 1 ? '' : 's'}. This policy still gates total frame, DOM apply, and semantic apply thresholds, but it should not be used to decide whether Dart work is build-, layout-, or paint-bound for scenarios without subphase samples. Regenerate captures with runtime subphase timing before making that optimization call.',
      )
      ..writeln()
      ..writeln('| Scenario | Build | Layout | Paint |')
      ..writeln('| --- | --- | --- | --- |');
    for (final scenario in missingRuntimeSubphaseScenarios) {
      buffer.writeln(
        '| ${scenario.id} | ${_availabilityCell(scenario.buildAvailable)} | ${_availabilityCell(scenario.layoutAvailable)} | ${_availabilityCell(scenario.paintAvailable)} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Scenario Thresholds')
    ..writeln()
    ..writeln(
      '| Scenario | Frames / steps | Extra frames | Max frames/step | Total frame p95 ms | DOM apply p95 ms | Semantic apply p95 ms | Over budget % | Semantic uncovered cells |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final entry in scenarios.entries) {
    final scenario = _map(entry.value);
    final observedFrameCount = _cell(scenario['observedFrameCount']);
    final observedRequestedStepCount = _cell(
      scenario['observedRequestedStepCount'],
    );
    final frameAccounting =
        observedFrameCount.isEmpty && observedRequestedStepCount.isEmpty
        ? ''
        : '$observedFrameCount / $observedRequestedStepCount';
    buffer.writeln(
      '| ${entry.key} | $frameAccounting | ${_cell(scenario['observedExtraFrameCount'])} | ${_cell(scenario['observedMaxFramesPerStep'])} | ${_cell(scenario['maxTotalFrameP95Ms'])} | ${_cell(scenario['maxDomApplyP95Ms'])} | ${_cell(scenario['maxSemanticApplyP95Ms'])} | ${_cell(scenario['maxOverBudgetPercent'])} | ${_cell(scenario['maxSemanticUncoveredCells'])} |',
    );
  }
  if (overBudgetScenarios.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Over-Budget Thresholds')
      ..writeln()
      ..writeln(
        'This candidate permits over-budget frames in ${overBudgetScenarios.length} scenario${overBudgetScenarios.length == 1 ? '' : 's'}. Promotion requires `--allow-over-budget-thresholds` and a concrete `--review-note=TEXT` that explains why those thresholds are acceptable for this reviewed baseline.',
      )
      ..writeln()
      ..writeln(
        '| Scenario | Extra frames | Max frames/step | Total frame p95 ms | Over budget % |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: |');
    for (final scenario in overBudgetScenarios) {
      final rawScenario = _map(scenarios[scenario.id]);
      buffer.writeln(
        '| ${scenario.id} | ${_cell(rawScenario['observedExtraFrameCount'])} | ${_cell(rawScenario['observedMaxFramesPerStep'])} | ${_cell(scenario.maxTotalFrameP95Ms)} | ${_cell(scenario.maxOverBudgetPercent)} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Promotion Command')
    ..writeln()
    ..writeln(
      'This command is intentionally not runnable as written: replace the reviewer placeholder and any generic browser/platform values before promotion.',
    )
    ..writeln()
    ..writeln('```sh')
    ..write(
      _shellCommand(
        const ['dart', 'run', 'tool/web_threshold_review.dart'],
        [
          '--input=$inputPath',
          '--output=$reviewedOutputPath',
          '--json-output=$summaryOutputPath',
          '--expect-input-fingerprint=$inputPolicyFingerprint',
          '--reviewed-by=<reviewer>',
          '--review-context=$promotionReviewContext',
          if (overBudgetScenarios.isNotEmpty) '--allow-over-budget-thresholds',
          if (overBudgetScenarios.isNotEmpty)
            '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>',
        ],
      ),
    )
    ..writeln('```');
  return buffer.toString();
}

String _cell(Object? value) => value?.toString() ?? '';

String? _nonEmptyString(Object? value) {
  final string = value?.toString().trim();
  return string == null || string.isEmpty ? null : string;
}

String _shellCommand(List<String> head, List<String> args) {
  final buffer = StringBuffer()..writeln(head.map(_shellArg).join(' ') + r' \');
  for (var index = 0; index < args.length; index += 1) {
    final suffix = index == args.length - 1 ? '' : r' \';
    buffer.writeln('  ${_shellArg(args[index])}$suffix');
  }
  return buffer.toString();
}

String _shellArg(String arg) {
  if (arg.isEmpty) return "''";
  final safe = RegExp(r'^[A-Za-z0-9_./:=+,-]+$');
  if (safe.hasMatch(arg)) return arg;
  return "'${arg.replaceAll("'", "'\\''")}'";
}

Map<String, Object?> _map(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) return raw.cast<String, Object?>();
  return const <String, Object?>{};
}

Map<String, Object?> _loadPolicy(File input) {
  if (!input.existsSync()) {
    stderr.writeln('threshold review input not found: ${input.path}');
    exit(2);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(input.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('threshold review input is not valid JSON: $error');
    exit(2);
  }

  if (decoded is! Map) {
    stderr.writeln('threshold review input must be a JSON object');
    exit(2);
  }
  final policy = decoded.cast<String, Object?>();
  if (policy['kind'] != 'fleuryWebFrameThresholds') {
    stderr.writeln(
      'threshold review input kind is ${policy['kind'] ?? '<missing>'}; '
      'expected fleuryWebFrameThresholds',
    );
    exit(2);
  }
  final scenarios = policy['scenarios'];
  if (scenarios is! Map || scenarios.isEmpty) {
    stderr.writeln('threshold review input must contain at least one scenario');
    exit(2);
  }
  if (policy['reviewState'] == 'reviewed') {
    stderr.writeln(
      'threshold review input is already reviewed; use the reviewed file directly',
    );
    exit(2);
  }
  return policy;
}

void _validateExpectedInputFingerprint({
  required String actual,
  required String? expected,
}) {
  final trimmed = expected?.trim();
  if (trimmed == null || trimmed.isEmpty) return;
  if (actual == trimmed) return;
  stderr.writeln(
    'threshold review input fingerprint $actual does not match expected $trimmed; rerun the review plan for the current candidate before promotion',
  );
  exit(2);
}

String _reviewedAt(String? raw) {
  if (raw == null || raw.isEmpty) {
    return DateTime.now().toUtc().toIso8601String();
  }
  try {
    return DateTime.parse(raw).toUtc().toIso8601String();
  } on FormatException {
    stderr.writeln('reviewed-at must be an ISO-8601 date/time');
    exit(2);
  }
}

Map<String, Object?> _reviewPolicy(
  Map<String, Object?> policy, {
  required String reviewedBy,
  required String reviewedAt,
  required String reviewContext,
  required String? reviewNote,
  required List<_OverBudgetScenario> overBudgetScenarios,
}) {
  final scenarios = (policy['scenarios'] as Map).cast<String, Object?>();
  return <String, Object?>{
    ...policy,
    'reviewState': 'reviewed',
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt,
    'reviewContext': reviewContext,
    'reviewNote':
        reviewNote ??
        'Reviewed threshold policy promoted from candidate browser evidence.',
    if (overBudgetScenarios.isNotEmpty) ...{
      'overBudgetThresholdsAcknowledged': true,
      'overBudgetThresholdScenarioIds': [
        for (final scenario in overBudgetScenarios) scenario.id,
      ],
    },
    'scenarios': scenarios,
  };
}

List<_OverBudgetScenario> _overBudgetScenarios(Map<String, Object?> policy) {
  final scenarios = (policy['scenarios'] as Map).cast<String, Object?>();
  final result = <_OverBudgetScenario>[];
  for (final entry in scenarios.entries) {
    final scenario = _map(entry.value);
    final maxOverBudgetPercent = _number(scenario['maxOverBudgetPercent']);
    if (maxOverBudgetPercent == null || maxOverBudgetPercent <= 0) continue;
    result.add(
      _OverBudgetScenario(
        id: entry.key,
        maxTotalFrameP95Ms: _number(scenario['maxTotalFrameP95Ms']),
        maxOverBudgetPercent: maxOverBudgetPercent,
      ),
    );
  }
  return result;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<_RuntimeSubphaseScenario> _missingRuntimeSubphaseScenarios(
  Map<String, Object?> scenarios,
) {
  final result = <_RuntimeSubphaseScenario>[];
  for (final entry in scenarios.entries) {
    final scenario = _map(entry.value);
    final availability = _RuntimeSubphaseScenario(
      id: entry.key,
      buildAvailable: _number(scenario['observedMaxRuntimeBuildP95Ms']) != null,
      layoutAvailable:
          _number(scenario['observedMaxRuntimeLayoutP95Ms']) != null,
      paintAvailable: _number(scenario['observedMaxRuntimePaintP95Ms']) != null,
    );
    if (!availability.allAvailable) result.add(availability);
  }
  return result;
}

String _availabilityCell(bool available) => available ? 'present' : 'missing';

final class _OverBudgetScenario {
  const _OverBudgetScenario({
    required this.id,
    required this.maxTotalFrameP95Ms,
    required this.maxOverBudgetPercent,
  });

  final String id;
  final double? maxTotalFrameP95Ms;
  final double maxOverBudgetPercent;
}

final class _RuntimeSubphaseScenario {
  const _RuntimeSubphaseScenario({
    required this.id,
    required this.buildAvailable,
    required this.layoutAvailable,
    required this.paintAvailable,
  });

  final String id;
  final bool buildAvailable;
  final bool layoutAvailable;
  final bool paintAvailable;

  bool get allAvailable => buildAvailable && layoutAvailable && paintAvailable;
}

final class _Options {
  const _Options({
    required this.help,
    required this.inputPath,
    required this.outputPath,
    required this.writePlanPath,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewContext,
    required this.reviewContextHint,
    required this.reviewNote,
    required this.expectedInputFingerprint,
    required this.allowOverBudgetThresholds,
    required this.jsonOutputPath,
    required this.json,
  });

  final bool help;
  final String? inputPath;
  final String? outputPath;
  final String? writePlanPath;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? reviewContext;
  final String? reviewContextHint;
  final String? reviewNote;
  final String? expectedInputFingerprint;
  final bool allowOverBudgetThresholds;
  final String? jsonOutputPath;
  final bool json;

  bool get promote =>
      writePlanPath == null ||
      outputPath != null ||
      reviewedBy != null ||
      reviewedAt != null ||
      reviewContext != null ||
      reviewNote != null ||
      json;

  static _Options parse(List<String> args) {
    var help = false;
    String? inputPath;
    String? outputPath;
    String? writePlanPath;
    String? reviewedBy;
    String? reviewedAt;
    String? reviewContext;
    String? reviewContextHint;
    String? reviewNote;
    String? expectedInputFingerprint;
    var allowOverBudgetThresholds = false;
    String? jsonOutputPath;
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
      } else if (arg.startsWith('--write-plan=')) {
        writePlanPath = arg.substring('--write-plan='.length).trim();
        if (writePlanPath.isEmpty) {
          stderr.writeln('--write-plan requires a non-empty path.');
          _printUsage();
          exit(2);
        }
      } else if (arg.startsWith('--reviewed-by=')) {
        reviewedBy = arg.substring('--reviewed-by='.length).trim();
      } else if (arg.startsWith('--reviewed-at=')) {
        reviewedAt = arg.substring('--reviewed-at='.length).trim();
      } else if (arg.startsWith('--review-context=')) {
        reviewContext = arg.substring('--review-context='.length).trim();
      } else if (arg.startsWith('--review-context-hint=')) {
        reviewContextHint = arg
            .substring('--review-context-hint='.length)
            .trim();
      } else if (arg.startsWith('--review-note=')) {
        reviewNote = arg.substring('--review-note='.length).trim();
      } else if (arg.startsWith('--expect-input-fingerprint=')) {
        expectedInputFingerprint = arg
            .substring('--expect-input-fingerprint='.length)
            .trim();
        if (expectedInputFingerprint.isEmpty) {
          stderr.writeln(
            '--expect-input-fingerprint requires a non-empty value.',
          );
          _printUsage();
          exit(2);
        }
      } else if (arg == '--allow-over-budget-thresholds') {
        allowOverBudgetThresholds = true;
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length).trim();
        if (jsonOutputPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printUsage();
          exit(2);
        }
      } else if (arg == '--json') {
        json = true;
      } else {
        stderr.writeln('Unknown option for web_threshold_review: $arg');
        _printUsage();
        exit(2);
      }
    }

    if (!help) {
      if (inputPath == null || inputPath.isEmpty) {
        stderr.writeln('web_threshold_review requires --input=PATH');
        _printUsage();
        exit(2);
      }
      final promote =
          writePlanPath == null ||
          outputPath != null ||
          reviewedBy != null ||
          reviewedAt != null ||
          reviewContext != null ||
          reviewNote != null ||
          json;
      if (promote && (outputPath == null || outputPath.isEmpty)) {
        stderr.writeln('web_threshold_review requires --output=PATH');
        _printUsage();
        exit(2);
      }
      if (promote && (reviewedBy == null || reviewedBy.isEmpty)) {
        stderr.writeln('web_threshold_review requires --reviewed-by=NAME');
        _printUsage();
        exit(2);
      }
      if (promote && _isPlaceholderReviewer(reviewedBy!)) {
        stderr.writeln(
          'web_threshold_review requires --reviewed-by=NAME to replace the reviewer placeholder',
        );
        _printUsage();
        exit(2);
      }
      if (promote && (reviewContext == null || reviewContext.isEmpty)) {
        stderr.writeln('web_threshold_review requires --review-context=TEXT');
        _printUsage();
        exit(2);
      }
      if (promote && _containsPlaceholder(reviewContext!)) {
        stderr.writeln(
          'web_threshold_review requires --review-context=TEXT to replace placeholder browser/platform values',
        );
        _printUsage();
        exit(2);
      }
    }

    return _Options(
      help: help,
      inputPath: inputPath,
      outputPath: outputPath,
      writePlanPath: writePlanPath,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt,
      reviewContext: reviewContext,
      reviewContextHint: reviewContextHint == null || reviewContextHint.isEmpty
          ? null
          : reviewContextHint,
      reviewNote: reviewNote == null || reviewNote.isEmpty ? null : reviewNote,
      expectedInputFingerprint:
          expectedInputFingerprint == null || expectedInputFingerprint.isEmpty
          ? null
          : expectedInputFingerprint,
      allowOverBudgetThresholds: allowOverBudgetThresholds,
      jsonOutputPath: jsonOutputPath,
      json: json,
    );
  }
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
  return RegExp(r'\b(VERSION|PLATFORM|REVIEWER)\b').hasMatch(trimmed);
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_threshold_review.dart [options]');
  stdout.writeln('');
  stdout.writeln(
    'Promotes a candidate Fleury web frame threshold policy to a reviewed policy.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --input=PATH        Candidate threshold policy JSON');
  stdout.writeln(
    '  --output=PATH       Reviewed threshold policy JSON to write',
  );
  stdout.writeln(
    '  --write-plan=PATH   Write a non-promoting Markdown review plan',
  );
  stdout.writeln('  --reviewed-by=NAME  Human reviewer name or handle');
  stdout.writeln(
    '  --reviewed-at=TIME  ISO-8601 review time, default current UTC time',
  );
  stdout.writeln(
    '  --review-context=TEXT Required product/browser/environment basis for approval',
  );
  stdout.writeln(
    '  --review-context-hint=TEXT Suggested review context written into review plans',
  );
  stdout.writeln('  --review-note=TEXT  Optional review note');
  stdout.writeln(
    '  --expect-input-fingerprint=FNV Require the loaded candidate policy to match a review-plan fingerprint',
  );
  stdout.writeln(
    '  --allow-over-budget-thresholds  Required when any scenario threshold allows over-budget frames',
  );
  stdout.writeln(
    '  --json-output=PATH  Promotion summary JSON path; with --write-plan only, embed this path in the generated command',
  );
  stdout.writeln('  --json              Print machine-readable summary JSON');
}

String _defaultReviewedOutputPath(String inputPath) {
  const candidateSuffix = '.candidate.json';
  if (inputPath.endsWith(candidateSuffix)) {
    return '${inputPath.substring(0, inputPath.length - candidateSuffix.length)}.json';
  }
  const jsonSuffix = '.json';
  if (inputPath.endsWith(jsonSuffix)) {
    return '${inputPath.substring(0, inputPath.length - jsonSuffix.length)}.reviewed.json';
  }
  return '$inputPath.reviewed.json';
}

String _defaultReviewSummaryPath(String reviewedOutputPath) {
  return '${File(reviewedOutputPath).parent.path}${Platform.pathSeparator}threshold-review.json';
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
