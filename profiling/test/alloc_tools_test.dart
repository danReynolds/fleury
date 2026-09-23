import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> runTool(String script, List<String> args,
        {bool service = false}) =>
    Process.run(Platform.resolvedExecutable, [
      if (service) ...[
        '--deterministic',
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
      ],
      'bin/$script.dart',
      ...args,
    ]);

void main() {
  test('invalid counts fail before starting a profiler session', () async {
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
      final result = await runTool(script, [argument]);
      expect(result.exitCode, 64, reason: '$script $argument');
      expect(result.stderr, isNot(contains('no VM service')));
      expect(
          result.stderr, anyOf(contains('positive'), contains('nonnegative')));
    }
  });

  test('both allocation axes independently reject regressions', () async {
    final directory = Directory.systemTemp.createTempSync('fleury-alloc-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final baseline = File('${directory.path}/baseline.json');
    final args = ['--frames=80', '--warmup=50', '--baseline=${baseline.path}'];
    final capture = await runTool('alloc_gate', [...args, '--update-baseline'],
        service: true);
    expect(capture.exitCode, 0, reason: '${capture.stdout}\n${capture.stderr}');
    final measured = jsonDecode(baseline.readAsStringSync()) as Map;
    final total = measured['bytesPerFrame'] as num;
    final project = measured['projectBytesPerFrame'] as num;
    expect(project, greaterThan(0));
    expect(total, greaterThan(project));

    for (final axis in ['total', 'project']) {
      baseline.writeAsStringSync(jsonEncode({
        'bytesPerFrame': axis == 'total' ? 1 : total * 100,
        'projectBytesPerFrame': axis == 'project' ? 1 : project * 100,
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
