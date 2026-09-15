import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../lib/lab/catalog.dart';
import '../lib/lab/workload.dart';

Future<void> main(List<String> args) async {
  final flags = <String, String>{};
  for (final arg in args) {
    final split = arg.indexOf('=');
    if (!arg.startsWith('--') || split < 0) throw ArgumentError(arg);
    flags[arg.substring(2, split)] = arg.substring(split + 1);
  }
  final options = LabOptions(
      scenario: flags['scenario'] ?? 'typing',
      samples: int.parse(flags['samples'] ?? '300'),
      warmup: int.parse(flags['warmup'] ?? '30'));
  final trace = flags['trace'] == 'true';
  try {
    final result = await runWorkload(options,
        start: !trace
            ? null
            : () async {
                developer.debugger(message: 'FleuryLab: warmed');
                developer.postEvent('FleuryLab',
                    {'phase': 'start', 'micros': developer.Timeline.now});
              },
        stop: !trace
            ? null
            : () async {
                developer.postEvent('FleuryLab',
                    {'phase': 'end', 'micros': developer.Timeline.now});
                developer.debugger(message: 'FleuryLab: measured');
              });
    stdout.writeln(jsonEncode(
        {...result, 'mode': !trace ? 'unprofiled' : 'JIT diagnostic'}));
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    stdout.writeln(jsonEncode({
      if (e is WorkloadFailure) ...e.partial,
      'schema': labSchema,
      'status': 'failed',
      'config': options.toJson(),
      'error': '$e'
    }));
    exitCode = 1;
  }
}
