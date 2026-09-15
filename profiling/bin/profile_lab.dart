import 'dart:io';
import 'dart:convert';

import '../lib/lab/catalog.dart';
import '../lib/lab/diagnostics.dart';
import '../lib/lab/report.dart';
import '../lib/lab/runner.dart';

const usage = '''Fleury profiling lab (V2)
  benchmark lab list
  benchmark lab compare --baseline=origin/main --candidate=HEAD --out=/tmp/lab-run
      [--scenario=typing,list,panes-40] [--runs=5] [--samples=300] [--warmup=30]
      [--practical-percent=5]
  benchmark lab report --out=/tmp/lab-run
  benchmark lab trace --scenario=typing --out=/tmp/lab-trace
      [--samples=3000] [--warmup=100]

Compare pins both revisions, overlays the SAME workload, compiles AOT, and
alternates fresh process pairs. Output must be a new directory. Sources,
binaries, logs, raw samples and failures are retained. Run alone on a quiet
machine. Use >=5 pairs; reproduce interesting changes with a focused run.
Trace diagnoses the current checkout in JIT; its timing is not an AOT result.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || ['--help', '-h', 'help'].contains(args.first)) {
    stdout.write(usage);
    return;
  }
  final command = args.first;
  if (command == 'list' && args.length == 1) {
    for (final e in scenarios.entries) {
      stdout.writeln('${e.key}: ${e.value}');
    }
    return;
  }
  try {
    final flags = <String, String>{};
    for (final arg in args.skip(1)) {
      final at = arg.indexOf('=');
      if (!arg.startsWith('--') || at < 3)
        throw ArgumentError('Expected --name=value: $arg');
      final name = arg.substring(2, at);
      if (flags.containsKey(name)) throw ArgumentError('Duplicate flag: $name');
      flags[name] = arg.substring(at + 1);
    }
    final allowed = switch (command) {
      'compare' => {
          'baseline',
          'candidate',
          'out',
          'scenario',
          'runs',
          'samples',
          'warmup',
          'practical-percent'
        },
      'trace' => {'scenario', 'out', 'samples', 'warmup'},
      'report' => {'out'},
      _ => throw ArgumentError('Unknown command: $command'),
    };
    if (!allowed.containsAll(flags.keys))
      throw ArgumentError(
          'Unknown flags: ${flags.keys.toSet().difference(allowed)}');
    final outPath = flags['out'];
    if (outPath == null || outPath.isEmpty)
      throw ArgumentError('--out is required');
    final out = Directory(outPath).absolute;
    final root = File.fromUri(Platform.script).parent.parent.parent.path;
    if (command == 'report') {
      final report = await writeReport(out);
      stdout.writeln('${out.path}/report.md (${report['status']})');
      if (report['status'] != 'complete') exitCode = 1;
      return;
    }
    final samples =
        int.parse(flags['samples'] ?? (command == 'trace' ? '3000' : '300'));
    final warmup =
        int.parse(flags['warmup'] ?? (command == 'trace' ? '100' : '30'));
    final selected = (flags['scenario'] ??
            (command == 'trace' ? 'typing' : scenarios.keys.join(',')))
        .split(',');
    if (selected.toSet().length != selected.length)
      throw ArgumentError('Duplicate scenarios');
    final configs = selected
        .map((s) => LabOptions(scenario: s, samples: samples, warmup: warmup))
        .toList();
    if (command == 'compare') {
      if (flags['baseline'] == null || flags['candidate'] == null) {
        throw ArgumentError('--baseline and --candidate are required');
      }
      if (!await compare(
          root: root,
          baseline: flags['baseline']!,
          candidate: flags['candidate']!,
          out: out,
          pairs: int.parse(flags['runs'] ?? '5'),
          configs: configs,
          practicalPercent: double.parse(flags['practical-percent'] ?? '5'))) {
        exitCode = 1;
      }
    } else {
      if (configs.length != 1) throw ArgumentError('Trace takes one scenario');
      if (await out.exists()) throw ArgumentError('Output already exists');
      await out.create(recursive: true);
      final git = await Process.run('git', ['rev-parse', 'HEAD'],
          workingDirectory: root);
      final status = await Process.run('git', ['status', '--short'],
          workingDirectory: root);
      final metadata = {
        'schema': labSchema,
        'diagnosticOnly': true,
        'source': git.stdout.toString().trim(),
        'sourceCheckoutStatus': status.stdout.toString(),
        'config': configs.single.toJson(),
        'sdk': Platform.version,
        'os': Platform.operatingSystemVersion,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'running',
        'workloadFiles': {
          for (final f in Directory('$root/profiling/lib/lab')
              .listSync()
              .whereType<File>())
            f.uri.pathSegments.last: await digest(f),
        },
      };
      final manifestFile = File('${out.path}/manifest.json');
      await manifestFile.writeAsString(jsonEncode(metadata));
      var code = 1;
      try {
        code = await traceWorkload('$root/profiling', out, configs.single);
      } catch (e) {
        metadata['error'] = '$e';
        stderr.writeln('Trace failed: $e');
      }
      metadata['status'] = code == 0 ? 'complete' : 'failed';
      metadata['exitCode'] = code;
      await manifestFile.writeAsString(jsonEncode(metadata));
      stdout.writeln('Diagnostic artifacts: ${out.path} (exit $code)');
      exitCode = code;
    }
  } catch (e) {
    stderr.writeln('$e\n\n$usage');
    exitCode = 1;
  }
}
