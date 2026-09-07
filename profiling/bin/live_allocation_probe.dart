// Allocation traces count object creation (unlike post-GC heap inventories).
// These diagnostic JIT runs are deliberately separate from AOT latency runs.
// dart --deterministic --profiler --enable-vm-service=0 \
//   --disable-service-auth-codes bin/live_allocation_probe.dart [class] [frames]
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'notification_burst_probe.dart';

class AllocationSentinel {
  AllocationSentinel(this.value);
  final int value;
}

Future<void> main(List<String> args) async {
  final name = args.isEmpty ? 'AllocationSentinel' : args[0];
  final frames = args.length < 2 ? 5 : int.parse(args[1]);
  final structured = args.length < 3 || args[2] == 'structured';
  final operation = args.length < 4 ? 'update' : args[3];
  if (!['update', 'mount'].contains(operation) || frames < 1) {
    throw ArgumentError('Expected positive frames and update or mount');
  }
  final info = (await developer.Service.getInfo()).serverUri!;
  final service = await vmServiceConnectUri(info.replace(
    scheme: 'ws',
    pathSegments: [...info.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString());
  final workload = BurstWorkload(count: 64, structured: structured);
  final calibration = [AllocationSentinel(-1)];
  void work(int iteration) {
    if (operation == 'update') {
      workload.frame(iteration, 8);
    } else {
      final mounted = BurstWorkload(count: 64, structured: structured);
      try {
        mounted.frame(iteration, 8);
      } finally {
        mounted.dispose();
      }
    }
  }

  try {
    final isolate = (await service.getVM()).isolates!.first.id!;
    for (var i = -1000; i < 0; i++) workload.frame(i, 8);
    if (operation == 'mount') {
      for (var i = 0; i < 10; i++) work(i);
    }
    final classes = (await service.getClassList(isolate)).classes!;
    final matches = classes.where((c) => c.name == name).toList();
    if (matches.length != 1) {
      stdout.writeln(jsonEncode({
        'matches': [
          for (final c in classes)
            if (c.name!.contains(name))
              {'id': c.id, 'name': c.name, 'library': c.library?.uri}
        ]
      }));
      throw StateError('Need exactly one class named $name');
    }
    final classId = matches.single.id!;
    await service.setTraceClassAllocation(isolate, classId, true);
    for (var i = -100; i < 0; i++) workload.frame(i, 8);
    final before = await service.getAllocationProfile(isolate, gc: true);
    final start = (await service.getVMTimelineMicros()).timestamp!;
    if (name == 'AllocationSentinel') {
      for (var i = 0; i < 123; i++) {
        calibration.add(AllocationSentinel(i));
        // Keep only a bounded tail, so the later heap inventory differs from
        // the known number of allocations even after explicit collection.
        if (calibration.length > 17) calibration.removeAt(0);
      }
    } else {
      for (var i = 0; i < frames; i++) work(i);
    }
    final end = (await service.getVMTimelineMicros()).timestamp!;
    await service.setTraceClassAllocation(isolate, classId, false);
    if (name == 'AllocationSentinel') {
      await service.getAllocationProfile(isolate, gc: true);
    }
    final traces = await service.getAllocationTraces(isolate,
        classId: classId,
        timeOriginMicros: start,
        timeExtentMicros: end - start);
    final after = await service.getAllocationProfile(isolate, gc: true);
    final traceList = traces.samples ?? const <CpuSample>[];
    if (name == 'AllocationSentinel' && traceList.length != 123) {
      throw StateError(
          'Allocation trace calibration: expected 123, got ${traceList.length}');
    }
    final callers = <String, int>{};
    for (final sample in traceList) {
      final stack = <String>[];
      for (final index in sample.stack ?? const <int>[]) {
        final ref = traces.functions![index].function;
        if (ref is FuncRef) {
          final owner = ref.owner;
          stack.add('${owner is ClassRef ? '${owner.name}.' : ''}${ref.name}');
        } else if (ref is NativeFunction) {
          stack.add('[native] ${ref.name}');
        }
        if (stack.length >= 7) break;
      }
      callers.update(stack.join(' <- '), (n) => n + 1, ifAbsent: () => 1);
    }
    final sorted = callers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln(jsonEncode({
      'class': name,
      'frames': name == 'AllocationSentinel' ? 0 : frames,
      'surface': structured ? 'structured' : 'terminal',
      'operation': operation,
      'allocations': traceList.length,
      'sampleCount': traces.sampleCount,
      'traceOrigin': traces.timeOriginMicros,
      'windowStart': start,
      'windowEnd': end,
      'truncatedStacks': traceList.where((s) => s.truncated == true).length,
      'liveBefore': [
        for (final m in before.members!)
          if (m.classRef?.id == classId) m.toJson()
      ],
      'liveAfter': [
        for (final m in after.members!)
          if (m.classRef?.id == classId) m.toJson()
      ],
      'topStacks': [
        for (final e in sorted.take(15)) {'count': e.value, 'stack': e.key}
      ],
      'calibrationSum': calibration.fold(0, (n, s) => n + s.value),
      'dart': Platform.version,
    }));
  } finally {
    workload.dispose();
    await service.dispose();
  }
}
