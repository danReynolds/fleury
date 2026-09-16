import 'dart:convert';

import 'package:fleury_profiling/lab/catalog.dart';
import 'package:fleury_profiling/lab/report.dart';
import 'package:fleury_profiling/lab/statistics.dart';
import 'package:test/test.dart';

Map<String, dynamic> result(LabOptions config, num time) => {
      'schema': 2,
      'status': 'complete',
      'config': config.toJson(),
      'metrics': ['totalUs'],
      'samples': [
        for (var i = 0; i < config.samples; i++) {'id': i, 'totalUs': time}
      ],
      'checks': {
        'processedInputs': config.samples,
        'expectedInputs': config.samples,
        'appliedEdits': config.samples,
        'finalStateVerified': true,
        'semanticChainVerified': true
      },
    };

void main() {
  test('list rebuild results require every update and key scan', () {
    final config = LabOptions(scenario: 'keyed-list', samples: 10);
    final r = result(config, 10);
    final checks = <String, Object>{
      'verifiedUpdates': 10,
      'keysRead': 1000000,
      'visibleRowsVerifiedPerUpdate': 20,
    };
    r['checks'] = checks;
    validateResult(r, config.toJson());
    for (final key in checks.keys) {
      final valid = checks[key]!;
      checks[key] = 0;
      expect(() => validateResult(r, config.toJson()), throwsStateError);
      checks[key] = valid;
    }
  });
  test('percentiles retain precision and do not mutate raw samples', () {
    final values = [4, 1, 3, 2];
    expect(percentile(values, .5), 2.5);
    expect(percentile(values, .95), closeTo(3.85, .001));
    expect(values, [4, 1, 3, 2]);
  });
  test('known slowdown and speedup are detected at the process level', () {
    final baseline = [90.0, 110.0, 100.0, 120.0, 95.0];
    expect(
        pairedEstimate(
            baseline, baseline.map((n) => n * 1.3).toList())['verdict'],
        'regression');
    expect(
        pairedEstimate(
            baseline, baseline.map((n) => n * .7).toList())['verdict'],
        'improvement');
    expect(pairedEstimate(baseline, baseline)['verdict'], 'no clear change');
    expect(
        pairedEstimate(
            baseline, baseline.map((n) => n * 1.01).toList())['verdict'],
        'no clear change');
  });
  test('no directional claim from too few runs, zero baseline, or noisy pairs',
      () {
    expect(
        pairedEstimate([100, 100], [1, 1])['verdict'], contains('exploratory'));
    expect(pairedEstimate([0], [1])['verdict'], 'below timer resolution');
    expect(pairedEstimate([1], [0])['verdict'], 'below timer resolution');
    expect(
        pairedEstimate(List.filled(5, 100), [50, 150, 100, 80, 120])['verdict'],
        'no clear change');
  });

  final config = LabOptions(scenario: 'typing', samples: 10, warmup: 2);
  late Map<String, dynamic> manifest;
  late Map<String, Map<String, dynamic>> artifacts;
  setUp(() {
    manifest = {
      'schema': 2,
      'status': 'complete',
      'pairs': 5,
      'practicalPercent': 5,
      'sources': {'baseline': 'old', 'candidate': 'new'},
      'harnessHash': 'same',
      'configs': [config.toJson()],
      'errors': [],
      'runs': <Map<String, dynamic>>[],
    };
    artifacts = {};
    for (var i = 0; i < 5; i++) {
      for (final side in ['baseline', 'candidate']) {
        final id = '$i-$side';
        (manifest['runs'] as List).add({
          'scenario': 'typing',
          'pair': i,
          'side': side,
          'status': 'complete',
          'source': side == 'baseline' ? 'old' : 'new',
          'harnessHash': 'same',
          'artifact': id,
        });
        artifacts[id] = result(config, side == 'baseline' ? 100 : 50);
      }
    }
  });
  test('complete paired experiment produces reproducible report', () {
    final first = buildReport(manifest, artifacts);
    expect(first['status'], 'complete');
    expect((first['comparisons'] as List).first['verdict'], 'improvement');
    expect(jsonEncode(first), jsonEncode(buildReport(manifest, artifacts)));
  });
  test('one failed process suppresses all performance claims', () {
    (manifest['runs'] as List).last['status'] = 'failed';
    final report = buildReport(manifest, artifacts);
    expect(report['status'], 'incomplete');
    expect(
        (report['comparisons'] as List)
            .every((c) => c['verdict'] == 'incomplete experiment'),
        isTrue);
  });
  test('source/harness mismatch cannot masquerade as a valid pair', () {
    (manifest['runs'] as List).first['harnessHash'] = 'changed';
    expect(buildReport(manifest, artifacts)['status'], 'incomplete');
  });
  test('missing raw samples and duplicated IDs invalidate the run', () {
    final r = result(config, 10);
    (r['samples'] as List).removeLast();
    expect(() => validateResult(r, config.toJson()), throwsStateError);
    final repeated = result(config, 10);
    (repeated['samples'] as List).last['id'] = 0;
    expect(() => validateResult(repeated, config.toJson()), throwsStateError);
  });
  test('correctness failure and timing boundary mismatch invalidate the run',
      () {
    final r = result(config, 10);
    (r['checks'] as Map)['finalStateVerified'] = false;
    expect(() => validateResult(r, config.toJson()), throwsStateError);
    final mismatch = result(config, 10);
    (mismatch['config'] as Map)['boundary'] = 'different';
    expect(() => validateResult(mismatch, config.toJson()), throwsStateError);
  });
  test('matching final state does not excuse dropped intermediate edits', () {
    final r = result(config, 10);
    (r['checks'] as Map)['appliedEdits'] = config.samples - 2;
    expect(() => validateResult(r, config.toJson()), throwsStateError);
  });
  test('interrupted build still yields an incomplete, reviewable report', () {
    manifest['status'] = 'preparing';
    manifest['runs'] = [];
    manifest['errors'] = ['candidate compilation failed'];
    final report = buildReport(manifest, {});
    expect(report['status'], 'incomplete');
    expect(report['comparisons'], isEmpty);
    expect(markdownReport(report), contains('candidate compilation failed'));
  });
}
