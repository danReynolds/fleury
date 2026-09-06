// Post-GC retention after repeated ordinary widget/semantic lifecycles.
// Every core control-tree host is disposed by core.main. This measures remaining
// Fleury-class objects, not allocation rate, total process RAM or general leaks.
// dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//   bin/core_lifetime_probe.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

import 'core_lifecycle_probe.dart' as core;

Future<void> main() async {
  final server = (await developer.Service.getInfo()).serverUri;
  if (server == null) throw StateError('Run with --enable-vm-service=0');
  final service = await vmServiceConnectUri(server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString());
  try {
    final isolate = (await service.getVM()).isolates!.first.id!;
    Future<void> reportHeap(int cycle) async {
      final profile = await service.getAllocationProfile(isolate, gc: true);
      final classes = <Map<String, Object?>>[];
      var bytes = 0;
      var instances = 0;
      for (final member in profile.members!) {
        final uri = member.classRef?.library?.uri ?? '';
        if (!uri.startsWith('package:fleury')) continue;
        final liveBytes = member.bytesCurrent ?? 0;
        final liveInstances = member.instancesCurrent ?? 0;
        bytes += liveBytes;
        instances += liveInstances;
        if (liveInstances == 0) continue;
        classes.add({
          'class': member.classRef!.name,
          'library': uri,
          'bytes': liveBytes,
          'instances': liveInstances,
        });
      }
      classes.sort((a, b) => (b['bytes'] as int).compareTo(a['bytes'] as int));
      stdout.writeln(jsonEncode({
        'kind': 'post-dispose-heap',
        'cycle': cycle,
        'projectLiveBytes': bytes,
        'projectLiveInstances': instances,
        'heap': profile.memoryUsage?.toJson(),
        'classes': classes,
        'dart': Platform.version,
      }));
    }

    core.main(['10', 'structured']);
    for (var cycle = 0; cycle <= 3; cycle++) {
      if (cycle > 0) core.main(['30', 'structured']);
      // Release each previous profiling response before the next collection.
      await Future<void>.delayed(Duration.zero);
      await reportHeap(cycle);
    }
  } finally {
    await service.dispose();
  }
}
