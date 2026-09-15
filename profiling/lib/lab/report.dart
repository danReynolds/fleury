import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'catalog.dart';
import 'statistics.dart';

void validateResult(Map<String, dynamic> result, Map<String, dynamic> config) {
  if (result['schema'] != labSchema ||
      result['status'] != 'complete' ||
      jsonEncode(result['config']) != jsonEncode(config)) {
    throw StateError('Incompatible or incomplete workload result');
  }
  final scenario = config['scenario'] as String;
  final expected = (config['samples'] as int) *
      (scenario == 'burst' || scenario == 'slow-output' ? 16 : 1);
  final samples = result['samples'] as List;
  if (samples.length != expected) throw StateError('Missing raw samples');
  final metrics = (result['metrics'] as List).cast<String>();
  if (!metrics.contains('totalUs')) throw StateError('Missing total timing');
  for (var i = 0; i < samples.length; i++) {
    final row = samples[i] as Map;
    if (row['id'] != i)
      throw StateError('Duplicated or missing input/frame ID');
    for (final key in metrics) {
      final value = row[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw StateError('Invalid metric $key at sample $i');
      }
    }
  }
  final checks = result['checks'] as Map;
  if (isPipeline(scenario)) {
    if (checks['changedFrames'] != expected ||
        checks['expectedFrames'] != expected) {
      throw StateError('Frame correctness check failed');
    }
  } else if (checks['processedInputs'] != expected ||
      checks['expectedInputs'] != expected ||
      (scenario != 'list' && checks['appliedEdits'] != expected) ||
      checks['finalStateVerified'] != true ||
      checks['semanticChainVerified'] != true) {
    throw StateError('Input/output correctness check failed');
  }
}

Map<String, Object?> buildReport(Map<String, dynamic> manifest,
    Map<String, Map<String, dynamic>> artifacts) {
  if (manifest['schema'] != labSchema)
    throw StateError('Unsupported lab schema');
  final runs = (manifest['runs'] as List).cast<Map<String, dynamic>>();
  final requested = manifest['pairs'] as int;
  final results = <Map<String, Object?>>[];
  final problems = <String>[...(manifest['errors'] as List).cast<String>()];
  for (final rawConfig in manifest['configs'] as List) {
    final config = Map<String, dynamic>.from(rawConfig as Map);
    final scenario = config['scenario'] as String;
    final pairs = <(Map<String, dynamic>, Map<String, dynamic>)>[];
    for (var pair = 0; pair < requested; pair++) {
      final sides = <Map<String, dynamic>>[];
      for (final side in ['baseline', 'candidate']) {
        final match = runs
            .where((r) =>
                r['scenario'] == scenario &&
                r['pair'] == pair &&
                r['side'] == side)
            .toList();
        try {
          if (match.length != 1 || match.single['status'] != 'complete') {
            throw StateError('missing or failed process');
          }
          final run = match.single;
          if (run['source'] != (manifest['sources'] as Map)[side] ||
              run['harnessHash'] != manifest['harnessHash']) {
            throw StateError('source or harness mismatch');
          }
          final result = artifacts[run['artifact']];
          if (result == null) throw StateError('missing raw artifact');
          validateResult(result, config);
          sides.add(result);
        } catch (e) {
          problems.add('$scenario pair $pair $side: $e');
        }
      }
      if (sides.length == 2) {
        if (jsonEncode(sides[0]['metrics']) !=
            jsonEncode(sides[1]['metrics'])) {
          problems.add('$scenario pair $pair: metric contracts differ');
        } else {
          pairs.add((sides[0], sides[1]));
        }
      }
    }
    if (pairs.isEmpty) continue;
    for (final metric in pairs.first.$1['metrics'] as List) {
      for (final (label, quantile) in [
        ('p50', .5),
        ('p95', .95),
        ('p99', .99)
      ]) {
        double read(Map<String, dynamic> result) => percentile(
            (result['samples'] as List).map((s) => (s as Map)[metric] as num),
            quantile);
        final estimate = pairedEstimate(pairs.map((p) => read(p.$1)).toList(),
            pairs.map((p) => read(p.$2)).toList(),
            practicalPercent: (manifest['practicalPercent'] as num).toDouble());
        // A partial experiment must never produce a directional claim, even if
        // all retained pairs happen to look good.
        if (pairs.length != requested ||
            problems.isNotEmpty ||
            manifest['status'] != 'complete') {
          estimate['verdict'] = 'incomplete experiment';
        }
        results.add({
          'scenario': scenario,
          'metric': metric,
          'quantile': label,
          ...estimate
        });
      }
    }
  }
  final complete = problems.isEmpty && manifest['status'] == 'complete';
  // Problems discovered in a later scenario invalidate earlier claims too.
  if (!complete) {
    for (final result in results) {
      result['verdict'] = 'incomplete experiment';
    }
  }
  return {
    'schema': labSchema,
    'status': complete ? 'complete' : 'incomplete',
    'sources': manifest['sources'],
    'harnessHash': manifest['harnessHash'],
    'problems': problems,
    'comparisons': results
  };
}

String markdownReport(Map<String, Object?> report) {
  final buffer = StringBuffer('# Fleury profiling comparison\n\n')
    ..writeln('Status: **${report['status']}**. Lower timing is better. '
        'All timings are microseconds; these are not physical display latencies.\n')
    ..writeln('Sources: `${jsonEncode(report['sources'])}`\n')
    ..writeln('The interval resamples paired fresh-process summaries. '
        'It is exploratory evidence from this machine/session. Many metrics are '
        'reported without a multiple-comparison correction; reproduce interesting '
        'changes in a targeted run before making a performance claim. '
        'Change is computed within each pair, not from the two displayed medians.\n')
    ..writeln(
        '| Scenario | Metric | Baseline median | Candidate median | Paired change | 95% interval | Assessment |')
    ..writeln('|---|---|---:|---:|---:|---|---|');
  String n(Object? v) => v is num ? v.toStringAsFixed(1) : 'n/a';
  for (final row in (report['comparisons'] as List).cast<Map>()) {
    // Detailed phases and p99 remain in report.json; keep the first view useful.
    if (row['metric'] != 'totalUs' || row['quantile'] == 'p99') continue;
    final interval = row['interval95Percent'] as List?;
    buffer.writeln('| ${row['scenario']} | ${row['quantile']} | '
        '${n(row['baseline'])} | ${n(row['candidate'])} | '
        '${n(row['deltaPercent'])}% | '
        '${interval == null ? 'n/a' : '${n(interval[0])}% to ${n(interval[1])}%'} | '
        '${row['verdict']} |');
  }
  buffer.writeln(
      '\nPhase timings, all per-process summaries, p99, and raw input/frame '
      'samples are in report.json and runs/. Output counts, encoded bytes, batch '
      'drain times, correctness checks and process RSS are preserved per run. '
      'A slow-output dispatch checkpoint can precede output drain; inspect both.\n');
  for (final problem in report['problems'] as List) {
    buffer.writeln('- $problem');
  }
  return '${buffer.toString().trimRight()}\n';
}

Future<Map<String, Object?>> writeReport(Directory directory) async {
  final manifest =
      jsonDecode(await File('${directory.path}/manifest.json').readAsString())
          as Map<String, dynamic>;
  final artifacts = <String, Map<String, dynamic>>{};
  for (final run in (manifest['runs'] as List).cast<Map>()) {
    final name = run['artifact'] as String?;
    if (name == null) continue;
    try {
      final bytes = await File('${directory.path}/$name').readAsBytes();
      if (sha256.convert(bytes).toString() != run['artifactSha256']) continue;
      artifacts[name] = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {/* Missing/corrupt artifacts are reported as incomplete. */}
  }
  final report = buildReport(manifest, artifacts);
  await File('${directory.path}/report.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  await File('${directory.path}/report.md')
      .writeAsString(markdownReport(report));
  return report;
}
