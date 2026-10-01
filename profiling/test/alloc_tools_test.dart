import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/allocation_trace_config.dart';

Future<ProcessResult> runTool(String script, List<String> args,
        {bool service = false, bool preserveSamples = true}) =>
    Process.run(Platform.resolvedExecutable, [
      if (service)
        ...allocationTraceVmFlags
            .where((flag) => preserveSamples || flag != '--profile-startup'),
      'bin/$script.dart',
      ...args,
    ]);

void main() {
  test(
      'allocation trace canary counts retained and discarded objects across GC',
      () async {
    final result = await runTool('allocation_trace_probe', [], service: true);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
        result.stdout,
        contains(
            '4096 discarded allocations, 4096 traced after GC (inside=true'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('allocation trace refuses truncated windows', () async {
    final result = await runTool('allocation_trace_probe', ['--exhaust-buffer'],
        service: true);
    expect(result.exitCode, isNot(0));
    // The bounded canaries must succeed before the deliberately oversized
    // window fails, so startup exhaustion cannot masquerade as this regression.
    expect(result.stdout, contains('4096 traced after GC (inside=true'));
    expect(result.stderr, contains('Incomplete allocation trace window'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('allocation trace rejects a ring buffer that could lose middle samples',
      () async {
    final result = await runTool('allocation_trace_probe', [],
        service: true, preserveSamples: false);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('requires --profile-startup'));
  });

  test('input gate counts dispatcher objects and rejects regression', () async {
    final directory =
        Directory.systemTemp.createTempSync('fleury-input-alloc-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final baseline = File('${directory.path}/baseline.json')
      ..writeAsStringSync(jsonEncode({
        'measurement': 'allocation-traces-v1-objects',
        'objectsPerKey': 1,
      }));
    final result = await runTool(
        'input_alloc_gate', ['--gate', '--baseline=${baseline.path}'],
        service: true);
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(
        result.stdout,
        contains(
            '2002 objects  package:fleury/src/input/events.dart::KeyEvent'));
    expect(
        result.stdout,
        contains(
            '2002 objects  package:fleury/src/input/keyboard_state.dart::_PressRecord'));
    expect(result.stdout, contains('FAIL'));
  });

  for (final (script, argument) in [
    ('alloc_gate', '--frames=0'),
    ('alloc_gate', '--warmup=-1'),
    ('alloc_gate', '--top=-1'),
    ('alloc_trace', '--frames=0'),
    ('alloc_trace', '--warmup=-1'),
    ('alloc_trace', '--depth=0'),
    ('alloc_trace', '--stacks=0'),
    ('alloc_trace', '--auto=0'),
  ]) {
    test('$script $argument fails before starting a profiler session',
        () async {
      final result = await runTool(script, [argument]);
      expect(result.exitCode, 64, reason: '$script $argument');
      expect(result.stderr, isNot(contains('no VM service')));
      expect(
          result.stderr, anyOf(contains('positive'), contains('nonnegative')));
    });
  }

  test('both allocation axes independently reject regressions', () async {
    final directory = Directory.systemTemp.createTempSync('fleury-alloc-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final baseline = File('${directory.path}/baseline.json');
    final args = ['--frames=4', '--warmup=50', '--baseline=${baseline.path}'];
    final capture = await runTool('alloc_gate', [...args, '--update-baseline'],
        service: true);
    expect(capture.exitCode, 0, reason: '${capture.stdout}\n${capture.stderr}');
    final measured = jsonDecode(baseline.readAsStringSync()) as Map;
    final total = measured['objectsPerFrame'] as num;
    final project = measured['projectObjectsPerFrame'] as num;
    expect(project, greaterThan(0));
    expect(total, greaterThan(project));

    for (final axis in ['total', 'project']) {
      baseline.writeAsStringSync(jsonEncode({
        'measurement': 'allocation-traces-v1-objects',
        'objectsPerFrame': axis == 'total' ? 1 : total * 100,
        'projectObjectsPerFrame': axis == 'project' ? 1 : project * 100,
      }));
      final result = await runTool('alloc_gate', [...args, '--gate', '--top=0'],
          service: true);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      final output = result.stdout as String;
      final failing = output.split('\n').where((line) => line.contains('FAIL'));
      expect(failing, hasLength(1));
      expect(failing.single, contains('[$axis]'));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
