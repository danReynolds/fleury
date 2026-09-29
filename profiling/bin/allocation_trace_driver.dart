// External controller for allocation_trace_measure.dart. Never run the service
// client inside the traced VM: its JSON allocations can overwrite the workload.
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final service = await vmServiceConnectUri(args[0]);
  final isolate = args[1];
  final armed = <String>[];
  void respond(Map<String, Object> value) => stdout.writeln(jsonEncode(value));
  try {
    final flags = (await service.getFlagList()).flags!;
    for (final name in ['profiler', 'profile_startup']) {
      if (!flags
          .any((flag) => flag.name == name && flag.valueAsString == 'true')) {
        throw StateError(
            'Allocation tracing requires --${name.replaceAll('_', '-')}');
      }
    }
    final classes = <int, ClassRef>{};
    int? guard;
    for (final ref in (await service.getClassList(isolate)).classes!) {
      final uri = ref.library?.uri ?? '';
      if (uri.isEmpty || uri.startsWith('package:vm_service')) continue;
      final isGuard = ref.name == '_TraceGuard' &&
          uri.endsWith('/allocation_trace_measure.dart');
      if (args.contains('--project-only') &&
          !isGuard &&
          !uri.startsWith('package:fleury/')) continue;
      final id = int.parse(ref.id!.split('/').last);
      await service.setTraceClassAllocation(isolate, ref.id!, true);
      armed.add(ref.id!);
      classes[id] = ref;
      if (ref.name == '_TraceGuard' &&
          uri.endsWith('/allocation_trace_measure.dart')) {
        guard = id;
      }
    }
    if (guard == null)
      throw StateError('Allocation trace guard is unavailable.');
    respond({'ready': true});
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final request = jsonDecode(line) as Map<String, dynamic>;
      final operation = request['operation'];
      if (operation == 'stop') break;
      try {
        if (operation == 'gc' || request['gc'] == true) {
          // Private RPC used only to qualify this SDK with the GC canary.
          await service.callMethod('_collectAllGarbage', isolateId: isolate);
        }
        if (operation == 'gc') {
          respond({'ok': true});
          continue;
        }
        final start = request['start'] as int;
        final traces = await service.getAllocationTraces(isolate,
            timeOriginMicros: start,
            timeExtentMicros: (request['end'] as int) - start + 1);
        final samples = (traces.samples ?? const <CpuSample>[])
            .where((sample) => sample.userTag == 'fleury-allocation-window');
        final guards =
            samples.where((sample) => sample.classId == guard).length;
        // --profile-startup preserves the prefix when full rather than reusing
        // arbitrary completed blocks. Exhaustion therefore loses the end guard;
        // two surviving guards cannot mask overwritten middle blocks.
        if (guards != 2) {
          throw StateError(
              'Incomplete allocation trace window ($guards guards). '
              'The profiler buffer is exhausted; refusing a false pass.');
        }
        var total = 0;
        var project = 0;
        final counts = <String, int>{};
        for (final sample in samples) {
          if (sample.classId == guard) continue;
          final ref = classes[sample.classId];
          if (ref == null)
            throw StateError('Unregistered trace class: ${sample.classId}');
          final uri = ref.library!.uri!;
          if (uri.startsWith('file:')) continue;
          total++;
          if (uri.startsWith('package:fleury/')) project++;
          counts.update('$uri::${ref.name}', (n) => n + 1, ifAbsent: () => 1);
        }
        respond({'total': total, 'project': project, 'classes': counts});
      } catch (error) {
        respond({'error': error.toString()});
      }
    }
  } catch (error) {
    respond({'error': error.toString()});
  } finally {
    for (final id in armed) {
      await service.setTraceClassAllocation(isolate, id, false);
    }
    await service.dispose();
  }
  respond({'stopped': true});
}
