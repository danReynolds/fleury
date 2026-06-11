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
/// --disable-service-auth-codes` (typically under capture_pty, since runTui
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
  var top = 25;
  String? filter;
  String? wsUri;
  for (final arg in args) {
    if (arg.startsWith('--sample-after-ms=')) {
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
  } finally {
    await service.dispose();
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
