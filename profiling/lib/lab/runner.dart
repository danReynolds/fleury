import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'catalog.dart';
import 'report.dart';

/// Uses argument vectors, never a shell. Every process has a timeout, logs,
/// and an exit record; a broken sample remains part of the experiment.
Future<int> loggedProcess(String executable, List<String> args,
    {required String cwd,
    required String log,
    Duration timeout = const Duration(minutes: 3)}) async {
  final output = File('$log.stdout').openWrite();
  final errors = File('$log.stderr').openWrite();
  try {
    final process =
        await Process.start(executable, args, workingDirectory: cwd);
    final outDone = output.addStream(process.stdout);
    final errDone = errors.addStream(process.stderr);
    final code = await process.exitCode.timeout(timeout, onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return 124;
    });
    await Future.wait([outDone, errDone]);
    return code;
  } finally {
    await output.close();
    await errors.close();
  }
}

Future<String> _git(String root, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: root);
  if (result.exitCode != 0)
    throw StateError('git ${args.first}: ${result.stderr}');
  return (result.stdout as String).trim();
}

Future<String> digest(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

Future<bool> compare(
    {required String root,
    required String baseline,
    required String candidate,
    required Directory out,
    required int pairs,
    required List<LabOptions> configs,
    double practicalPercent = 5}) async {
  if (pairs < 1 ||
      configs.isEmpty ||
      practicalPercent < 0 ||
      !practicalPercent.isFinite)
    throw ArgumentError('Invalid experiment options');
  if (await out.exists())
    throw ArgumentError('Output directory already exists: ${out.path}');
  final sources = {
    'baseline':
        await _git(root, ['rev-parse', '--verify', '$baseline^{commit}']),
    'candidate':
        await _git(root, ['rev-parse', '--verify', '$candidate^{commit}']),
  };
  await out.create(recursive: true);
  await Directory('${out.path}/runs').create();
  // Freeze the workload BEFORE either build. The same bytes are overlaid on
  // both historical source trees and also retained beside the artifacts.
  final names = [
    'bin/lab_workload.dart',
    'bin/sample_frame_host.dart',
    'lib/sample_frame_host.dart',
    'pubspec.yaml',
    'pubspec_overrides.yaml',
    ...Directory('$root/profiling/lib/lab')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring('$root/profiling/'.length)),
  ]..sort();
  final hashes = <String, String>{};
  for (final name in names) {
    final file = File('$root/profiling/$name');
    final target = File('${out.path}/harness/$name');
    await target.parent.create(recursive: true);
    await file.copy(target.path);
    hashes[name] = await digest(target);
  }
  final harnessHash =
      sha256.convert(utf8.encode(jsonEncode(hashes))).toString();
  final manifest = <String, dynamic>{
    'schema': labSchema,
    'status': 'preparing',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'sources': sources,
    'requestedRefs': {'baseline': baseline, 'candidate': candidate},
    'harnessHash': harnessHash,
    'harnessFiles': hashes,
    'pairs': pairs,
    'practicalPercent': practicalPercent,
    'configs': configs.map((c) => c.toJson()).toList(),
    'environment': {
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'cpus': Platform.numberOfProcessors,
      'dartExecutable': Platform.resolvedExecutable,
      'mode': 'AOT',
      'timingUnit': 'microseconds',
      'sourceCheckoutStatus': await _git(root, ['status', '--short']),
      'hostLoad': (await Process.run('uptime', [])).stdout.toString().trim()
    },
    'builds': <String, Object?>{},
    'runs': <Map<String, Object?>>[],
    'errors': <String>[],
  };
  Future<void> save() async {
    // An interruption during a write must leave the previous manifest readable.
    final temp = File('${out.path}/manifest.json.tmp');
    await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true);
    await temp.rename('${out.path}/manifest.json');
  }

  await save();
  final binaries = <String, String>{};
  try {
    for (final side in sources.keys) {
      stdout.writeln('Preparing $side ${sources[side]!.substring(0, 12)}');
      final source = Directory('${out.path}/sources/$side');
      await source.create(recursive: true);
      final archive = '${source.path}.tar';
      await _git(root, [
        'archive',
        '--format=tar',
        '--output=$archive',
        sources[side]!,
        'packages',
        'profiling'
      ]);
      final unpack =
          await Process.run('tar', ['-xf', archive, '-C', source.path]);
      if (unpack.exitCode != 0)
        throw StateError('Source extraction failed: ${unpack.stderr}');
      await File(archive).delete();
      for (final name in names) {
        final target = File('${source.path}/profiling/$name');
        await target.parent.create(recursive: true);
        await File('${out.path}/harness/$name').copy(target.path);
      }
      final package = '${source.path}/profiling';
      // Pin external dependencies to the first side's lock. If the selected
      // sources require different dependency graphs, flag the confounder.
      if (side == 'candidate') {
        await File('${out.path}/sources/baseline/profiling/pubspec.lock')
            .copy('$package/pubspec.lock');
      }
      final pubCode = await loggedProcess(
          Platform.resolvedExecutable, ['pub', 'get'],
          cwd: package, log: '${out.path}/$side-pub');
      if (pubCode != 0) throw StateError('$side pub get failed ($pubCode)');
      final binary = '${source.path}/workload';
      final buildCode = await loggedProcess(Platform.resolvedExecutable,
          ['compile', 'exe', 'bin/lab_workload.dart', '-o', binary],
          cwd: package, log: '${out.path}/$side-build');
      if (buildCode != 0)
        throw StateError('$side compilation failed ($buildCode)');
      binaries[side] = binary;
      (manifest['builds'] as Map)[side] = {
        'binarySha256': await digest(File(binary)),
        'lockSha256': await digest(File('$package/pubspec.lock')),
        'command': ['dart', 'compile', 'exe', 'bin/lab_workload.dart'],
      };
      await save();
    }
    final builds = manifest['builds'] as Map;
    if (builds['baseline']['lockSha256'] != builds['candidate']['lockSha256']) {
      throw StateError(
          'Dependency locks differ; comparison would be confounded');
    }
    manifest['status'] = 'running';
    await save();
    // Both builds finish before timing starts. No concurrent workload processes.
    for (var pair = 0; pair < pairs; pair++) {
      for (final config in configs) {
        final order =
            pair.isEven ? ['baseline', 'candidate'] : ['candidate', 'baseline'];
        for (final side in order) {
          final id = '${config.scenario}-$pair-$side';
          final prefix = '${out.path}/runs/$id';
          final run = <String, Object?>{
            'scenario': config.scenario,
            'pair': pair,
            'side': side,
            'source': sources[side],
            'harnessHash': harnessHash,
            'order': (manifest['runs'] as List).length,
            'startedAt': DateTime.now().toUtc().toIso8601String(),
            'status': 'running',
            'artifact': 'runs/$id.json',
          };
          (manifest['runs'] as List).add(run);
          await save();
          stdout.writeln('Pair ${pair + 1}/$pairs ${config.scenario} $side');
          try {
            final code = await loggedProcess(
                binaries[side]!,
                [
                  '--scenario=${config.scenario}',
                  '--samples=${config.samples}',
                  '--warmup=${config.warmup}',
                ],
                cwd: '${out.path}/sources/$side/profiling',
                log: prefix);
            run['exitCode'] = code;
            if (code != 0)
              throw StateError('workload exited $code; see $id.stderr');
            final result =
                jsonDecode(await File('$prefix.stdout').readAsString())
                    as Map<String, dynamic>;
            validateResult(result, config.toJson());
            await File('$prefix.json').writeAsString(jsonEncode(result));
            run['artifactSha256'] = await digest(File('$prefix.json'));
            run['status'] = 'complete';
          } catch (e) {
            run['status'] = 'failed';
            run['error'] = '$e';
          }
          await save();
        }
      }
    }
    manifest['status'] =
        (manifest['runs'] as List).every((r) => r['status'] == 'complete')
            ? 'complete'
            : 'incomplete';
  } catch (e) {
    manifest['status'] = 'incomplete';
    (manifest['errors'] as List).add('$e');
  }
  manifest['finishedAt'] = DateTime.now().toUtc().toIso8601String();
  await save();
  final report = await writeReport(out);
  stdout.writeln('Report: ${out.path}/report.md (${report['status']})');
  return report['status'] == 'complete';
}
