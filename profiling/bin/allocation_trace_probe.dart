import 'dart:developer' as developer;
import 'dart:io';
import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service_io.dart';
import 'allocation_trace_measure.dart';

Object? keep;
int checksum = 0;
Future<void> main(List<String> args) async {
  final uri = (await developer.Service.getInfo()).serverUri!;
  final service = await vmServiceConnectUri(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString());
  keep = CellSize(1, 2);
  final isolate = (await service.getVM()).isolates!.first.id!;
  AllocationTraceMeter? meter;
  try {
    meter = await AllocationTraceMeter.start(isolate);
    final retained = <CellSize>[];
    for (final (count, retain, collectInside) in [
      (0, false, false),
      (123, true, false),
      (4096, false, false),
      (4096, false, true),
    ]) {
      final result = AllocationCounts();
      await meter.measure(result, () {
        for (var i = 0; i < count; i++) {
          keep = CellSize(i, i);
          if (retain) retained.add(keep as CellSize);
          checksum ^= identityHashCode(keep);
        }
        keep = null;
      }, collectAfter: true, collectInside: collectInside);
      final actual = result.classes.entries
          .where((e) => e.key.endsWith('::CellSize'))
          .fold(0, (n, e) => n + e.value);
      stdout.writeln(
          '$count ${retain ? 'retained' : 'discarded'} allocations, $actual traced after GC (inside=$collectInside, checksum=$checksum)');
      if (actual != count)
        throw StateError(
            'Incorrect churn count: expected $count, got $actual (inside=$collectInside)');
      retained.clear();
    }
    if (args.contains('--exhaust-buffer')) {
      // Exceed the configured buffer even after successful bounded windows.
      // Losing a guard must fail rather than produce a low passing count.
      await meter.measure(AllocationCounts(), () {
        for (var i = 0; i < 1000000; i++) {
          keep = CellSize(i, i);
          checksum ^= identityHashCode(keep);
        }
      });
      throw StateError(
          'Expected the bounded profiler buffer to reject this window');
    }
  } finally {
    await meter?.dispose();
    await service.dispose();
  }
}
