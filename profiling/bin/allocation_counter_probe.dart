// Checks whether VM-service "accumulated" counters actually survive GC.
// Run from profiling/:
// dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//   bin/allocation_counter_probe.dart
// Exit 0: the canary survives in cumulative counters; 64: unsupported counters.
// This diagnoses the SDK, not application allocation performance.
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as isolates;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class _AllocationCanary {
  _AllocationCanary(this.value);
  final int value;
}

List<_AllocationCanary> _retained = [];

int _count(AllocationProfile profile) => profile.members!
    .singleWhere((entry) => entry.classRef?.name == '_AllocationCanary')
    .instancesAccumulated!;

Future<void> main() async {
  final server = (await developer.Service.getInfo()).serverUri;
  if (server == null) {
    stderr.writeln(
        'Enable the VM service; see the command at the top of this file.');
    exitCode = 64;
    return;
  }
  final service = await vmServiceConnectUri(server.replace(
    scheme: 'ws',
    pathSegments: [
      ...server.pathSegments.where((part) => part.isNotEmpty),
      'ws'
    ],
  ).toString());
  try {
    final isolate = developer.Service.getIsolateId(isolates.Isolate.current)!;
    await service.getAllocationProfile(isolate, gc: true, reset: true);
    const expected = 4096;
    _retained = List.generate(expected, _AllocationCanary.new);
    final live = _count(await service.getAllocationProfile(isolate, gc: true));
    // Read after the await so the canaries are observably retained for the
    // first census, then release them without resetting the accumulators.
    if (_retained.length != expected || _retained.last.value != expected - 1) {
      throw StateError('Canary fixture was not retained.');
    }
    _retained = [];
    final collected =
        _count(await service.getAllocationProfile(isolate, gc: true));
    stdout.writeln('Dart ${Platform.version.split(' ').first}: '
        '$live accumulated while retained; $collected after release + GC.');
    if (live < expected || collected < live) {
      stderr.writeln('UNSUPPORTED: accumulated counts lost allocated objects. '
          'Heap-profile allocation gates cannot qualify churn on this SDK.');
      exitCode = 64;
    } else {
      stdout.writeln('Cumulative counters passed the GC canary.');
    }
  } finally {
    _retained = [];
    await service.dispose();
  }
}
