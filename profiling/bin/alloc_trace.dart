// Per-frame allocation ATTRIBUTION: which call sites produce the churn that
// `alloc-gate` counts.
//
// The gate answers "how many bytes per frame, and in which classes". When the
// total axis goes red, that is not yet actionable: the classes on top are
// `_List` and `_OneByteString`, which say nothing about who allocated them.
// This tool closes that gap. It drives the SAME scenario the gate drives (see
// alloc_scenario.dart), turns on the VM's per-class allocation tracing, and
// aggregates the resulting stack traces — so a red gate maps to a file and a
// function.
//
// It is a diagnostic, not a gate: it has no baseline and never fails.
//
// MUST be launched with the profiler ENABLED, and therefore WITHOUT
// `--deterministic` (that flag disables the profiler, and `getAllocationTraces`
// then fails with "Feature is disabled"). Sampling does not need the
// determinism the gate does — stacks are stable even when byte counts are not.
//   dart --profiler --enable-vm-service=0 --disable-service-auth-codes \
//     bin/alloc_trace.dart [--class=_List,_OneByteString] [--frames=N]
//
// With no --class, the top allocating classes of the measured window are
// traced automatically.
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'alloc_scenario.dart';
import 'gate_support.dart';

const _defaultFrames = 40;
const _defaultWarmup = 300;

Future<void> main(List<String> args) async {
  var frames = _defaultFrames;
  var warmup = _defaultWarmup;
  var stacks = 8;
  var depth = 9;
  var auto = 4;
  final wanted = <String>[];
  for (final arg in args) {
    if (parseIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
    } else if (parseIntFlag(arg, 'stacks') case final v?) {
      stacks = v;
    } else if (parseIntFlag(arg, 'depth') case final v?) {
      depth = v;
    } else if (parseIntFlag(arg, 'auto') case final v?) {
      auto = v;
    } else if (arg.startsWith('--class=')) {
      wanted.addAll(arg.substring('--class='.length).split(','));
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  final info = await developer.Service.getInfo();
  final server = info.serverUri;
  if (server == null) {
    stderr.writeln(
      'alloc_trace: no VM service. Launch with `dart --profiler '
      '--enable-vm-service=0 --disable-service-auth-codes '
      'bin/alloc_trace.dart ...` (fleury benchmark alloc-trace does this).',
    );
    exitCode = 64;
    return;
  }
  final wsUri = server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString();

  final service = await vmServiceConnectUri(wsUri);
  try {
    final vm = await service.getVM();
    final isolateId = vm.isolates!.first.id!;

    final owner = BuildOwner();
    final model = AllocModel();
    final root = owner.mountRoot(allocScenario(model));
    final frame = allocFrameDriver(owner: owner, model: model, root: root);

    for (var i = 0; i < warmup; i++) {
      frame();
    }

    // One measured window to rank classes and resolve their ids.
    await service.getAllocationProfile(isolateId, gc: true, reset: true);
    for (var i = 0; i < frames; i++) {
      frame();
    }
    final profile = await service.getAllocationProfile(isolateId);

    final ranked = <({String name, String id, int bytes})>[];
    for (final m in profile.members ?? const <ClassHeapStats>[]) {
      final uri = m.classRef?.library?.uri ?? '';
      final id = m.classRef?.id;
      final name = m.classRef?.name;
      // Same exclusions as the gate: VM-internal artifacts and this tool's own
      // profiler traffic are not the frame's churn.
      if (uri.isEmpty || uri.startsWith('package:vm_service')) continue;
      if (id == null || name == null) continue;
      final bytes = m.accumulatedSize ?? 0;
      if (bytes == 0) continue;
      ranked.add((name: name, id: id, bytes: bytes));
    }
    ranked.sort((a, b) => b.bytes.compareTo(a.bytes));

    final targets = wanted.isEmpty
        ? ranked.take(auto).toList()
        : [
            for (final name in wanted)
              if (ranked.where((r) => r.name == name).firstOrNull
                  case final hit?)
                hit,
          ];
    if (targets.isEmpty) {
      stderr.writeln(
        'alloc_trace: none of ${wanted.join(', ')} allocated in the window.',
      );
      exitCode = 64;
      return;
    }

    stdout.writeln(
      'allocation call sites over $frames frames '
      '(scenario: the alloc-gate dashboard):',
    );

    for (final target in targets) {
      await service.setTraceClassAllocation(isolateId, target.id, true);
      for (var i = 0; i < frames; i++) {
        frame();
      }
      final traces = await service.getAllocationTraces(
        isolateId,
        classId: target.id,
      );
      await service.setTraceClassAllocation(isolateId, target.id, false);

      final functions = traces.functions ?? const <ProfileFunction>[];
      String nameOf(int index) {
        if (index < 0 || index >= functions.length) return '?';
        final function = functions[index].function;
        if (function is FuncRef) {
          final owner = function.owner;
          final prefix = owner is ClassRef ? '${owner.name}.' : '';
          return '$prefix${function.name}';
        }
        return function?.toString() ?? '?';
      }

      final samples = traces.samples ?? const <CpuSample>[];
      final counts = <String, int>{};
      for (final sample in samples) {
        final chain = <String>[];
        for (final index in (sample.stack ?? const <int>[]).take(depth)) {
          final name = nameOf(index);
          if (name == '?') continue;
          chain.add(name);
        }
        final key = chain.join(' < ');
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      stdout.writeln(
        '\n=== ${target.name}: ${samples.length} traced allocations '
        '(${(samples.length / frames).toStringAsFixed(1)}/frame) ===',
      );
      for (final entry in sorted.take(stacks)) {
        stdout.writeln(
          '  ${(entry.value / frames).toStringAsFixed(1).padLeft(7)}/frame  '
          '${entry.key}',
        );
      }
    }
  } finally {
    await service.dispose();
  }
}
