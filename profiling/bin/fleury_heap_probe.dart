/// Heap composition probe for wire fixtures.
///
/// Spawns a fixture under a JIT VM with the service protocol enabled, samples
/// the allocation profile mid-run, and prints the top classes by live bytes
/// (post-GC) and by bytes allocated during the sampled window. Live bytes rank
/// retained owners; window allocations rank per-frame churn. JIT absolute
/// numbers do not match AOT RSS — use this for composition, capture_pty for
/// totals.
///
/// The fixture must already be running with `--enable-vm-service=PORT
/// --disable-service-auth-codes` (typically under capture_pty, since runApp
/// needs a TTY); this probe only connects, samples, and exits.
///
/// usage: dart run bin/fleury_heap_probe.dart --connect=ws://127.0.0.1:PORT/ws
///   [--sample-after-ms=N] [--window-ms=N] [--top=N]
import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  var sampleAfterMs = 1500;
  var windowMs = 1500;
  var cpuWindowMs = 0;
  var top = 25;
  String? filter;
  String? wsUri;
  for (final arg in args) {
    if (arg.startsWith('--cpu-window-ms=')) {
      cpuWindowMs = int.parse(arg.substring('--cpu-window-ms='.length));
    } else if (arg.startsWith('--sample-after-ms=')) {
      sampleAfterMs = int.parse(arg.substring('--sample-after-ms='.length));
    } else if (arg.startsWith('--window-ms=')) {
      windowMs = int.parse(arg.substring('--window-ms='.length));
    } else if (arg.startsWith('--top=')) {
      top = int.parse(arg.substring('--top='.length));
    } else if (arg.startsWith('--filter=')) {
      filter = arg.substring('--filter='.length);
    } else if (arg.startsWith('--connect=')) {
      wsUri = arg.substring('--connect='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }
  if (wsUri == null) {
    stderr.writeln(
      'usage: dart run bin/fleury_heap_probe.dart '
      '--connect=ws://127.0.0.1:PORT/ws '
      '[--sample-after-ms=N] [--window-ms=N] [--top=N]',
    );
    exitCode = 64;
    return;
  }
  final service = await vmServiceConnectUri(wsUri);
  try {
    final vm = await service.getVM();
    final isolateId = vm.isolates!.first.id!;
    await Future<void>.delayed(Duration(milliseconds: sampleAfterMs));

    final live = await service.getAllocationProfile(
      isolateId,
      gc: true,
      reset: true,
    );
    await Future<void>.delayed(Duration(milliseconds: windowMs));
    final window = await service.getAllocationProfile(isolateId);

    _printTop(
      'live bytes after GC (retained owners)',
      live.members!,
      (m) => (m.bytesCurrent ?? 0),
      (m) => (m.instancesCurrent ?? 0),
      top,
      filter,
    );
    _printTop(
      'bytes allocated in ${windowMs}ms window (churn)',
      window.members!,
      (m) => (m.accumulatedSize ?? 0),
      (m) => (m.instancesAccumulated ?? 0),
      top,
      filter,
    );
    final usage = await service.getMemoryUsage(isolateId);
    stdout.writeln(
      '\nheap usage: ${usage.heapUsage} bytes used / '
      '${usage.heapCapacity} capacity / ${usage.externalUsage} external',
    );
    if (cpuWindowMs > 0) {
      final t0 = (await service.getVMTimelineMicros()).timestamp!;
      await Future<void>.delayed(Duration(milliseconds: cpuWindowMs));
      final t1 = (await service.getVMTimelineMicros()).timestamp!;
      final samples = await service.getCpuSamples(isolateId, t0, t1 - t0);
      _printCpuTop(samples, top);
    }
  } finally {
    await service.dispose();
  }
}

void _printCpuTop(CpuSamples samples, int top) {
  final functions = samples.functions ?? const [];
  final exclusive = <int, int>{};
  final inclusive = <int, int>{};
  for (final sample in samples.samples ?? const <CpuSample>[]) {
    final stack = sample.stack;
    if (stack == null || stack.isEmpty) continue;
    exclusive.update(stack.first, (n) => n + 1, ifAbsent: () => 1);
    for (final fn in {...stack}) {
      inclusive.update(fn, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final total = (samples.samples ?? const <CpuSample>[]).length;
  String nameOf(int index) {
    if (index < 0 || index >= functions.length) return '<unknown>';
    final f = functions[index].function;
    if (f is FuncRef) {
      final owner = f.owner;
      final ownerName = owner is ClassRef
          ? '${owner.name}.'
          : owner is LibraryRef
              ? ''
              : '';
      final uri = f.location?.script?.uri ?? '';
      return '$ownerName${f.name}  $uri';
    }
    if (f is NativeFunction) return '[native] ${f.name}';
    return '$f';
  }

  stdout.writeln('\ncpu samples: $total in window');
  stdout.writeln('top $top by exclusive samples:');
  final rankedEx = exclusive.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in rankedEx.take(top)) {
    final pct = total == 0 ? 0 : (e.value * 1000 ~/ total) / 10;
    stdout.writeln('  ${e.value.toString().padLeft(6)}  '
        '${pct.toString().padLeft(5)}%  ${nameOf(e.key)}');
  }
  stdout.writeln('top $top by inclusive samples:');
  final rankedIn = inclusive.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in rankedIn.take(top)) {
    final pct = total == 0 ? 0 : (e.value * 1000 ~/ total) / 10;
    stdout.writeln('  ${e.value.toString().padLeft(6)}  '
        '${pct.toString().padLeft(5)}%  ${nameOf(e.key)}');
  }
}

void _printTop(
  String title,
  List<ClassHeapStats> members,
  int Function(ClassHeapStats) bytes,
  int Function(ClassHeapStats) instances,
  int top,
  String? filter,
) {
  final filtered = filter == null
      ? members
      : members
          .where((m) =>
              (m.classRef?.library?.uri ?? '').contains(filter))
          .toList();
  final ranked = [...filtered]..sort((a, b) => bytes(b).compareTo(bytes(a)));
  stdout.writeln('\ntop $top by $title:');
  for (final m in ranked.take(top)) {
    if (bytes(m) == 0) break;
    final lib = m.classRef?.library?.uri ?? '';
    stdout.writeln(
      '  ${bytes(m).toString().padLeft(10)} B  '
      '${instances(m).toString().padLeft(8)} inst  '
      '${m.classRef?.name}  $lib',
    );
  }
}
