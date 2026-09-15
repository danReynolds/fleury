import 'dart:convert';
import 'dart:io';

import 'package:fleury_profiling/lab/catalog.dart';
import 'package:fleury_profiling/lab/report.dart';
import 'package:test/test.dart';

void main() {
  test('trace collects externally between explicit workload boundaries',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('fleury-lab-trace-test-');
    addTearDown(() => temp.delete(recursive: true));
    final out = '${temp.path}/trace';
    final process = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/profile_lab.dart',
      'trace',
      '--scenario=typing',
      '--samples=20',
      '--warmup=4',
      '--out=$out',
    ]);
    expect(process.exitCode, 0, reason: '${process.stdout}\n${process.stderr}');
    final trace =
        jsonDecode(await File('$out/trace.json').readAsString()) as Map;
    expect(trace['collection'], contains('external supervisor'));
    expect(trace['windowMicros'], greaterThan(0));
    expect(trace['heapBefore']['memoryUsage']['heapUsage'], greaterThan(0));
    for (final entry in trace['heapAfter']['members'] as List) {
      if (['VmService', 'CpuSample', 'ClassHeapStats', 'AllocationProfile']
          .contains(entry['class']['name'])) {
        expect(entry['instancesCurrent'], 0,
            reason: 'The profiler must not allocate inside the measured app');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
  // Each production runApp owns process-global state. Match the real lab's
  // isolation instead of running these fixtures concurrently in one isolate.
  for (final scenario in scenarios.keys) {
    test('$scenario completes with all expected work and valid output',
        () async {
      final config = LabOptions(scenario: scenario, samples: 4, warmup: 2);
      final process = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/lab_workload.dart',
        '--scenario=$scenario',
        '--samples=4',
        '--warmup=2'
      ]);
      expect(process.exitCode, 0, reason: '${process.stderr}');
      final result =
          jsonDecode(process.stdout as String) as Map<String, dynamic>;
      validateResult(result, config.toJson());
      if (scenario == 'slow-output') {
        // Structural invariant, not a machine-sensitive timing gate: each
        // stalled burst must drain as one frame with the final verified state.
        expect(result['output']['plans'], config.samples);
      }
    }, timeout: const Timeout(Duration(minutes: 1)));
  }
}
