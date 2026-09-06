// Informational JIT attribution, not an AOT timing comparison.
import 'dart:developer' as developer;
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'core_lifecycle_probe.dart' as core;

Future<void> main(List<String> args) async {
  final server = (await developer.Service.getInfo()).serverUri!;
  final service = await vmServiceConnectUri(server.replace(
      scheme: 'ws',
      pathSegments: [
        ...server.pathSegments.where((s) => s.isNotEmpty),
        'ws'
      ]).toString());
  try {
    final isolate = (await service.getVM()).isolates!.first.id!;
    core.main(['10']);
    final start = (await service.getVMTimelineMicros()).timestamp!;
    core.main(args);
    final end = (await service.getVMTimelineMicros()).timestamp!;
    _printCpuTop(await service.getCpuSamples(isolate, start, end - start), 25);
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
