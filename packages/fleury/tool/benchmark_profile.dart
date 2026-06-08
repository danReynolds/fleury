import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _schemaVersion = 1;
const _defaultCpuTop = 25;
const _defaultAllocationTop = 25;
const _defaultProfilePeriodUs = 1000;
const _serviceTimeout = Duration(seconds: 20);
const _pauseExitTimeout = Duration(minutes: 5);

Future<void> main(List<String> rawArgs) async {
  final options = _ProfileOptions.parse(rawArgs);
  if (options.help) {
    _printUsage();
    return;
  }

  final repoRoot = _repoRoot();
  final target = _targetFor(options.scenarioId);
  if (target == null) {
    stderr.writeln('Unknown local benchmark scenario: ${options.scenarioId}');
    _printUsage();
    exit(2);
  }

  final savePath = options.savePath == null
      ? null
      : _resolveRepoPath(repoRoot, options.savePath!);

  final report = await _runProfile(repoRoot, target, options);
  if (savePath != null) {
    final file = File(savePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stderr.writeln('profile saved $savePath');
  }

  if (options.printJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else {
    _printSummary(report);
  }
  exit((report['exitCode'] as int?) ?? 0);
}

Future<Map<String, Object?>> _runProfile(
  String repoRoot,
  _BenchmarkTarget target,
  _ProfileOptions options,
) async {
  final workingDirectory = '$repoRoot/${target.packagePath}';
  final runnerArgs = <String>[
    '--filter=${options.scenarioId}',
    ...options.runnerArgs,
  ];
  final processArgs = <String>[
    '--profiler',
    '--profile_period=${options.profilePeriodUs}',
    '--sample_buffer_duration=60',
    'run',
    '--enable-vm-service=0',
    '--disable-service-auth-codes',
    '--pause-isolates-on-start',
    '--pause-isolates-on-exit',
    'benchmark/scenario_benchmarks.dart',
    ...runnerArgs,
  ];

  final childStdout = <String>[];
  final childStderr = <String>[];
  final serviceUri = Completer<Uri>();
  final wall = Stopwatch()..start();
  Process? child;
  VmService? vm;
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;
  StreamSubscription<Event>? debugSub;
  var resumedAfterExitPause = false;
  var childExited = false;
  Future<int>? childExitFuture;

  try {
    child = await Process.start(
      Platform.resolvedExecutable,
      processArgs,
      workingDirectory: workingDirectory,
    );
    childExitFuture = child.exitCode.then((code) {
      childExited = true;
      return code;
    });

    void handleChildLine(List<String> sink, String prefix, String line) {
      sink.add(line);
      stderr.writeln('$prefix| $line');
      if (!serviceUri.isCompleted) {
        final uri = _parseServiceUri(line);
        if (uri != null) serviceUri.complete(uri);
      }
    }

    stdoutSub = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => handleChildLine(childStdout, 'runner', line));
    stderrSub = child.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => handleChildLine(childStderr, 'runner!', line));

    final wsUri = await _awaitServiceUriOrExit(
      serviceUri.future,
      childExitFuture,
    );
    vm = await vmServiceConnectUri(wsUri.toString());
    final isolateId = await _firstIsolateId(vm);
    await vm.streamListen(EventStreams.kDebug);
    final pauseExit = Completer<void>();
    debugSub = vm.onDebugEvent.listen((event) {
      if (event.kind == EventKind.kPauseExit &&
          event.isolate?.id == isolateId &&
          !pauseExit.isCompleted) {
        pauseExit.complete();
      }
    });

    await _awaitPaused(vm, isolateId);
    await vm.clearCpuSamples(isolateId);
    await vm.getAllocationProfile(isolateId, reset: true);
    final startMicros = (await vm.getVMTimelineMicros()).timestamp!;

    await vm.resume(isolateId);
    final runEnd = await Future.any<Object>([
      pauseExit.future.then<Object>((_) => const _PausedAtExit()),
      childExitFuture.then<Object>(_ChildExited.new),
      Future<Object>.delayed(_pauseExitTimeout, () {
        throw TimeoutException(
          'Profiled benchmark did not reach pause-on-exit',
          _pauseExitTimeout,
        );
      }),
    ]);
    if (runEnd is _ChildExited) {
      throw StateError(
        'Profiled benchmark exited before pause-on-exit '
        '(exit ${runEnd.exitCode}).',
      );
    }
    final endMicros = (await vm.getVMTimelineMicros()).timestamp!;
    final extentMicros = endMicros - startMicros;

    final cpuSamples = await vm.getCpuSamples(
      isolateId,
      startMicros,
      extentMicros <= 0 ? 1 : extentMicros,
    );
    final allocationProfile = await vm.getAllocationProfile(isolateId);
    final afterGcProfile = await vm.getAllocationProfile(isolateId, gc: true);

    await vm.resume(isolateId);
    resumedAfterExitPause = true;
    final exitCode = await childExitFuture;
    wall.stop();

    return <String, Object?>{
      'schemaVersion': _schemaVersion,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'scenarioId': options.scenarioId,
      'packagePath': target.packagePath,
      'workingDirectory': workingDirectory,
      'runMode': 'vm-service-local-profile',
      'diagnosticOnly': true,
      'command': [Platform.resolvedExecutable, ...processArgs],
      'runnerArgs': runnerArgs,
      'profilePeriodUs': options.profilePeriodUs,
      'wallMs': wall.elapsedMicroseconds / 1000,
      'exitCode': exitCode,
      'cpu': _cpuProfileToJson(cpuSamples, options.cpuTop),
      'allocation': _allocationProfileToJson(
        allocationProfile,
        afterGcProfile,
        options.allocationTop,
      ),
      'childOutput': <String, Object?>{
        'stdoutLineCount': childStdout.length,
        'stderrLineCount': childStderr.length,
        'stdoutTail': _tail(childStdout, 20),
        'stderrTail': _tail(childStderr, 20),
      },
    };
  } finally {
    if (vm != null && child != null && !resumedAfterExitPause && !childExited) {
      try {
        final isolateId = await _firstIsolateId(vm);
        await vm.resume(isolateId);
      } catch (_) {
        child.kill(ProcessSignal.sigterm);
      }
    }
    await debugSub?.cancel();
    await vm?.dispose();
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
    if (child != null && childExitFuture != null) {
      final exited = await childExitFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          child!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (exited != 0 && resumedAfterExitPause) {
        stderr.writeln('profiled benchmark exited with code $exited');
      }
    }
  }
}

Map<String, Object?> _cpuProfileToJson(CpuSamples samples, int topCount) {
  final functions = samples.functions ?? const <ProfileFunction>[];
  final totalExclusive = functions.fold<int>(
    0,
    (sum, fn) => sum + (fn.exclusiveTicks ?? 0),
  );
  final totalInclusive = functions.fold<int>(
    0,
    (sum, fn) => sum + (fn.inclusiveTicks ?? 0),
  );

  final topExclusive = _topProfileFunctions(
    functions,
    topCount,
    (fn) => fn.exclusiveTicks ?? 0,
  );
  final topInclusive = _topProfileFunctions(
    functions,
    topCount,
    (fn) => fn.inclusiveTicks ?? 0,
  );
  final projectFunctions = functions.where(_isProjectFunction).toList();

  return <String, Object?>{
    'samplePeriodUs': samples.samplePeriod,
    'sampleCount': samples.sampleCount,
    'timeOriginMicros': samples.timeOriginMicros,
    'timeExtentMicros': samples.timeExtentMicros,
    'totalExclusiveTicks': totalExclusive,
    'totalInclusiveTicks': totalInclusive,
    'topExclusive': topExclusive,
    'topInclusive': topInclusive,
    'topProjectExclusive': _topProfileFunctions(
      projectFunctions,
      topCount,
      (fn) => fn.exclusiveTicks ?? 0,
    ),
    'topProjectInclusive': _topProfileFunctions(
      projectFunctions,
      topCount,
      (fn) => fn.inclusiveTicks ?? 0,
    ),
  };
}

List<Map<String, Object?>> _topProfileFunctions(
  Iterable<ProfileFunction> functions,
  int topCount,
  int Function(ProfileFunction fn) metric,
) {
  final sorted = functions.where((fn) => metric(fn) > 0).toList()
    ..sort((a, b) => metric(b).compareTo(metric(a)));
  return [
    for (final fn in sorted.take(topCount))
      <String, Object?>{
        'name': _functionName(fn),
        'owner': _functionOwner(fn),
        'kind': fn.kind,
        'resolvedUrl': fn.resolvedUrl,
        'exclusiveTicks': fn.exclusiveTicks,
        'inclusiveTicks': fn.inclusiveTicks,
      },
  ];
}

Map<String, Object?> _allocationProfileToJson(
  AllocationProfile profile,
  AllocationProfile afterGcProfile,
  int topCount,
) {
  final members = profile.members ?? const <ClassHeapStats>[];
  final afterGcMembers = afterGcProfile.members ?? const <ClassHeapStats>[];
  final projectMembers = members.where(_isProjectClass).toList();
  final projectAfterGcMembers = afterGcMembers.where(_isProjectClass).toList();

  return <String, Object?>{
    'memoryUsage': profile.memoryUsage?.toJson(),
    'afterGcMemoryUsage': afterGcProfile.memoryUsage?.toJson(),
    'topAccumulatedSize': _topClassStats(
      members,
      topCount,
      (stat) => stat.accumulatedSize ?? 0,
    ),
    'topInstancesAccumulated': _topClassStats(
      members,
      topCount,
      (stat) => stat.instancesAccumulated ?? 0,
    ),
    'topCurrentSize': _topClassStats(
      members,
      topCount,
      (stat) => stat.bytesCurrent ?? 0,
    ),
    'topAfterGcCurrentSize': _topClassStats(
      afterGcMembers,
      topCount,
      (stat) => stat.bytesCurrent ?? 0,
    ),
    'topProjectAccumulatedSize': _topClassStats(
      projectMembers,
      topCount,
      (stat) => stat.accumulatedSize ?? 0,
    ),
    'topProjectCurrentSize': _topClassStats(
      projectMembers,
      topCount,
      (stat) => stat.bytesCurrent ?? 0,
    ),
    'topProjectAfterGcCurrentSize': _topClassStats(
      projectAfterGcMembers,
      topCount,
      (stat) => stat.bytesCurrent ?? 0,
    ),
  };
}

List<Map<String, Object?>> _topClassStats(
  Iterable<ClassHeapStats> stats,
  int topCount,
  int Function(ClassHeapStats stat) metric,
) {
  final sorted = stats.where((stat) => metric(stat) > 0).toList()
    ..sort((a, b) => metric(b).compareTo(metric(a)));
  return [
    for (final stat in sorted.take(topCount))
      <String, Object?>{
        'class': stat.classRef?.name,
        'library': stat.classRef?.library?.uri,
        'accumulatedSize': stat.accumulatedSize,
        'instancesAccumulated': stat.instancesAccumulated,
        'bytesCurrent': stat.bytesCurrent,
        'instancesCurrent': stat.instancesCurrent,
      },
  ];
}

bool _isProjectFunction(ProfileFunction fn) {
  final url = fn.resolvedUrl ?? '';
  if (_isProjectUri(url)) return true;
  final owner = _functionOwner(fn);
  return _isProjectUri(owner);
}

bool _isProjectClass(ClassHeapStats stat) {
  return _isProjectUri(stat.classRef?.library?.uri ?? '');
}

bool _isProjectUri(String value) {
  return value.startsWith('package:fleury') ||
      value.startsWith('package:fleury_widgets') ||
      value.startsWith('package:fleury_example_console') ||
      value.contains('/packages/fleury/') ||
      value.contains('/packages/fleury_widgets/') ||
      value.contains('/packages/fleury_example_console/');
}

String _functionName(ProfileFunction fn) {
  final raw = fn.function;
  if (raw is FuncRef) return raw.name ?? '<anonymous>';
  final json = _toJsonMap(raw);
  return json?['name']?.toString() ?? raw?.toString() ?? '<unknown>';
}

String _functionOwner(ProfileFunction fn) {
  final raw = fn.function;
  dynamic owner;
  if (raw is FuncRef) {
    owner = raw.owner;
  } else {
    owner = _toJsonMap(raw)?['owner'];
  }
  if (owner is LibraryRef) return owner.uri ?? owner.name ?? '';
  if (owner is ClassRef) {
    final library = owner.library?.uri;
    return library == null ? owner.name ?? '' : '$library::${owner.name}';
  }
  if (owner is FuncRef) return owner.name ?? '';
  if (owner is Map) {
    final uri = owner['uri']?.toString();
    final name = owner['name']?.toString();
    if (uri != null && name != null) return '$uri::$name';
    return uri ?? name ?? '';
  }
  return owner?.toString() ?? '';
}

Map<String, Object?>? _toJsonMap(dynamic value) {
  if (value == null) return null;
  late final Object? json;
  try {
    json = value.toJson();
  } catch (_) {
    return null;
  }
  if (json is Map) return Map<String, Object?>.from(json);
  return null;
}

Future<String> _firstIsolateId(VmService vm) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final vmInfo = await vm.getVM();
    final isolates = vmInfo.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty && isolates.first.id != null) {
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('No isolate appeared on the VM service.');
}

Future<Uri> _awaitServiceUriOrExit(
  Future<Uri> serviceUri,
  Future<int> childExitFuture,
) async {
  final result = await Future.any<Object>([
    serviceUri,
    childExitFuture.then<Object>(_ChildExited.new),
    Future<Object>.delayed(_serviceTimeout, () {
      throw TimeoutException('VM service URI was not printed', _serviceTimeout);
    }),
  ]);
  if (result is Uri) return result;
  if (result is _ChildExited) {
    throw StateError(
      'Profiled benchmark exited before the VM service started '
      '(exit ${result.exitCode}).',
    );
  }
  throw StateError('Unexpected VM service wait result: $result');
}

final class _PausedAtExit {
  const _PausedAtExit();
}

Future<void> _awaitPaused(VmService vm, String isolateId) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final isolate = await vm.getIsolate(isolateId);
    final kind = isolate.pauseEvent?.kind;
    if (kind == EventKind.kPauseStart ||
        kind == EventKind.kPauseBreakpoint ||
        kind == EventKind.kPauseInterrupted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Isolate did not pause before profiling start.');
}

final class _ChildExited {
  const _ChildExited(this.exitCode);
  final int exitCode;
}

Uri? _parseServiceUri(String line) {
  final match = RegExp(r'(http://[^\s]+)').firstMatch(line);
  if (match == null) return null;
  final httpUri = Uri.parse(match.group(1)!);
  return httpUri.replace(
    scheme: 'ws',
    path: httpUri.path.endsWith('/')
        ? '${httpUri.path}ws'
        : '${httpUri.path}/ws',
  );
}

List<String> _tail(List<String> lines, int count) {
  if (lines.length <= count) return List<String>.from(lines);
  return lines.sublist(lines.length - count);
}

void _printSummary(Map<String, Object?> report) {
  stdout.writeln(
    '${report['scenarioId']} profile: '
    'samples=${(report['cpu'] as Map)['sampleCount']}, '
    'wallMs=${(report['wallMs'] as num).toStringAsFixed(1)}',
  );
  _printTop('Top project CPU exclusive', report, [
    'cpu',
    'topProjectExclusive',
  ], 'exclusiveTicks');
  _printTop('Top project allocations', report, [
    'allocation',
    'topProjectAccumulatedSize',
  ], 'accumulatedSize');
  _printTop('Top project retained after GC', report, [
    'allocation',
    'topProjectAfterGcCurrentSize',
  ], 'bytesCurrent');
}

void _printTop(
  String title,
  Map<String, Object?> report,
  List<String> path,
  String metric,
) {
  dynamic value = report;
  for (final segment in path) {
    value = (value as Map)[segment];
  }
  final rows = value as List;
  stdout.writeln('\n$title');
  if (rows.isEmpty) {
    stdout.writeln('  (none)');
    return;
  }
  for (final row in rows.take(10)) {
    final map = row as Map;
    final label = map['name'] ?? map['class'];
    final source = map['resolvedUrl'] ?? map['library'] ?? map['owner'] ?? '';
    stdout.writeln('  ${map[metric]}  $label  $source');
  }
}

String _repoRoot() {
  final script = File(Platform.script.toFilePath()).absolute;
  return script.parent.parent.parent.parent.path;
}

String _resolveRepoPath(String repoRoot, String path) {
  if (_isAbsolutePath(path)) return path;
  return '$repoRoot/$path';
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/')) return true;
  if (path.startsWith(r'\\')) return true;
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

_BenchmarkTarget? _targetFor(String scenarioId) {
  for (final target in _targets) {
    if (target.scenarios.contains(scenarioId)) return target;
  }
  return null;
}

String _normalizeScenarioId(String value) {
  final normalized = value.trim().toUpperCase();
  final match = RegExp(r'^SB\.?(\d+)$').firstMatch(normalized);
  if (match == null) return normalized;
  return 'SB.${match.group(1)}';
}

int _positiveInt(String value, String optionName) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    stderr.writeln('$optionName must be a positive integer: $value');
    exit(2);
  }
  return parsed;
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/benchmark_profile.dart <SB.id> [options] [runner options]',
  );
  stdout.writeln('');
  stdout.writeln('Profiler options:');
  stdout.writeln(
    '  --save=PATH                Save profile JSON; relative to repo root',
  );
  stdout.writeln('  --json                     Print profile JSON');
  stdout.writeln(
    '  --cpu-top=N                CPU rows to keep, default $_defaultCpuTop',
  );
  stdout.writeln(
    '  --allocation-top=N         Allocation rows to keep, default $_defaultAllocationTop',
  );
  stdout.writeln(
    '  --profile-period-us=N      CPU sample period, default $_defaultProfilePeriodUs',
  );
  stdout.writeln(
    '  --runner-json              Forward --json to the benchmark runner',
  );
  stdout.writeln(
    '  --runner-save=PATH         Forward --save to the runner; relative to repo root',
  );
  stdout.writeln('');
  stdout.writeln('Common runner options are forwarded:');
  stdout.writeln(
    '  --warmup=N --iterations=N --rows=N --size=COLSxROWS --sb12-phase=PHASE',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  dart run tool/benchmark_profile.dart SB.6 --warmup=1 --iterations=5 --save=profiling/caps/sb6-profile.json',
  );
  stdout.writeln(
    '  dart run tool/benchmark_profile.dart SB.12 --sb12-phase=viewport --warmup=1 --iterations=10',
  );
}

final class _ProfileOptions {
  const _ProfileOptions({
    required this.scenarioId,
    required this.runnerArgs,
    required this.savePath,
    required this.printJson,
    required this.cpuTop,
    required this.allocationTop,
    required this.profilePeriodUs,
    required this.help,
  });

  final String scenarioId;
  final List<String> runnerArgs;
  final String? savePath;
  final bool printJson;
  final int cpuTop;
  final int allocationTop;
  final int profilePeriodUs;
  final bool help;

  factory _ProfileOptions.parse(List<String> args) {
    if (args.isEmpty ||
        args.first == '-h' ||
        args.first == '--help' ||
        args.first == 'help') {
      return const _ProfileOptions(
        scenarioId: '',
        runnerArgs: <String>[],
        savePath: null,
        printJson: false,
        cpuTop: _defaultCpuTop,
        allocationTop: _defaultAllocationTop,
        profilePeriodUs: _defaultProfilePeriodUs,
        help: true,
      );
    }

    final scenarioId = _normalizeScenarioId(args.first);
    final runnerArgs = <String>[];
    String? savePath;
    var printJson = false;
    var cpuTop = _defaultCpuTop;
    var allocationTop = _defaultAllocationTop;
    var profilePeriodUs = _defaultProfilePeriodUs;

    for (final arg in args.skip(1)) {
      if (arg == '--json') {
        printJson = true;
      } else if (arg == '--runner-json') {
        runnerArgs.add('--json');
      } else if (arg.startsWith('--save=')) {
        savePath = arg.substring('--save='.length);
      } else if (arg.startsWith('--runner-save=')) {
        final path = arg.substring('--runner-save='.length);
        runnerArgs.add('--save=${_resolveRepoPath(_repoRoot(), path)}');
      } else if (arg.startsWith('--cpu-top=')) {
        cpuTop = _positiveInt(arg.substring('--cpu-top='.length), '--cpu-top');
      } else if (arg.startsWith('--allocation-top=')) {
        allocationTop = _positiveInt(
          arg.substring('--allocation-top='.length),
          '--allocation-top',
        );
      } else if (arg.startsWith('--profile-period-us=')) {
        profilePeriodUs = _positiveInt(
          arg.substring('--profile-period-us='.length),
          '--profile-period-us',
        );
      } else if (arg == '-h' || arg == '--help') {
        return _ProfileOptions(
          scenarioId: scenarioId,
          runnerArgs: runnerArgs,
          savePath: savePath,
          printJson: printJson,
          cpuTop: cpuTop,
          allocationTop: allocationTop,
          profilePeriodUs: profilePeriodUs,
          help: true,
        );
      } else {
        runnerArgs.add(arg);
      }
    }

    return _ProfileOptions(
      scenarioId: scenarioId,
      runnerArgs: runnerArgs,
      savePath: savePath,
      printJson: printJson,
      cpuTop: cpuTop,
      allocationTop: allocationTop,
      profilePeriodUs: profilePeriodUs,
      help: false,
    );
  }
}

final class _BenchmarkTarget {
  const _BenchmarkTarget({required this.packagePath, required this.scenarios});

  final String packagePath;
  final List<String> scenarios;
}

const _targets = <_BenchmarkTarget>[
  _BenchmarkTarget(
    packagePath: 'packages/fleury',
    scenarios: <String>['SB.1', 'SB.2', 'SB.12'],
  ),
  _BenchmarkTarget(
    packagePath: 'packages/fleury_widgets',
    scenarios: <String>[
      'SB.3',
      'SB.4',
      'SB.5',
      'SB.6',
      'SB.7',
      'SB.8',
      'SB.9',
      'SB.11',
    ],
  ),
  _BenchmarkTarget(
    packagePath: 'packages/fleury_example_console',
    scenarios: <String>['SB.10'],
  ),
];
