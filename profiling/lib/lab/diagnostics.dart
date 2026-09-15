import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'catalog.dart';

/// The VM client lives OUTSIDE the app so decoding profiles does not pollute
/// the heap being measured. Only tiny pause/phase markers execute in the app.
Future<int> traceWorkload(
    String package, Directory out, LabOptions config) async {
  final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--profiler',
        '--profile_period=1000',
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        '--pause-isolates-on-start',
        'run',
        'bin/lab_workload.dart',
        '--scenario=${config.scenario}',
        '--samples=${config.samples}',
        '--warmup=${config.warmup}',
        '--trace=true',
      ],
      workingDirectory: package);
  final stdoutLog = File('${out.path}/workload.stdout').openWrite();
  final stderrLog = File('${out.path}/workload.stderr').openWrite();
  final uri = Completer<Uri>();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    stdoutLog.writeln(line);
    final match = RegExp(r'The Dart VM service is listening on (http://\S+)')
        .firstMatch(line);
    if (match != null && !uri.isCompleted) uri.complete(Uri.parse(match[1]!));
  }).asFuture<void>();
  final stderrDone = stderrLog.addStream(process.stderr);
  VmService? service;
  StreamSubscription<Event>? extensionEvents;
  var completed = false;
  try {
    final server = await uri.future.timeout(const Duration(seconds: 30));
    final vm = service = await vmServiceConnectUri(
        server.replace(scheme: 'ws', path: '${server.path}ws').toString());
    await vm.streamListen(EventStreams.kDebug);
    await vm.streamListen(EventStreams.kExtension);
    final starts = Completer<int>(), ends = Completer<int>();
    extensionEvents = vm.onExtensionEvent.listen((event) {
      if (event.extensionKind != 'FleuryLab') return;
      final data = event.extensionData!.data;
      if (data['phase'] == 'start' && !starts.isCompleted)
        starts.complete(data['micros'] as int);
      if (data['phase'] == 'end' && !ends.isCompleted)
        ends.complete(data['micros'] as int);
    });
    final isolate = (await vm.getVM()).isolates!.single.id!;
    Future<void> waitPause(String kind) async {
      final watch = Stopwatch()..start();
      while ((await vm.getIsolate(isolate)).pauseEvent?.kind != kind) {
        if (watch.elapsed > const Duration(minutes: 3)) {
          throw TimeoutException('Waiting for $kind');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    await waitPause(EventKind.kPauseStart);
    await vm.resume(isolate);
    await waitPause(EventKind.kPauseBreakpoint);
    final before =
        await vm.getAllocationProfile(isolate, gc: true, reset: true);
    await vm.setVMTimelineFlags(['GC']);
    await vm.clearVMTimeline();
    await vm.clearCpuSamples(isolate);
    await vm.resume(isolate);
    final start = await starts.future.timeout(const Duration(seconds: 10));
    final end = await ends.future.timeout(const Duration(minutes: 3));
    await waitPause(EventKind.kPauseBreakpoint);
    final cpu = await vm.getCpuSamples(isolate, start, end - start);
    // Collect CPU symbols before diagnostic GC can discard old JIT code.
    final after = await vm.getAllocationProfile(isolate);
    final retained = await vm.getAllocationProfile(isolate, gc: true);
    final timeline = await vm.getVMTimeline(
        timeOriginMicros: start, timeExtentMicros: end - start);
    await vm.resume(isolate);
    final code = await process.exitCode.timeout(const Duration(seconds: 15));
    final functions = cpu.functions ?? [];
    final exclusive = <int, int>{}, inclusive = <int, int>{};
    for (final sample in cpu.samples ?? <CpuSample>[]) {
      final stack = sample.stack;
      if (stack == null || stack.isEmpty) continue;
      exclusive.update(stack.first, (n) => n + 1, ifAbsent: () => 1);
      for (final i in stack.toSet()) {
        inclusive.update(i, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    List<Map<String, Object?>> rank(Map<int, int> counts) {
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in entries.take(40))
          {
            'samples': e.value,
            'function': functions[e.key].function?.toJson(),
          }
      ];
    }

    final totalSamples = cpu.samples?.length ?? 0;
    final unknownSamples = exclusive.entries
        .where((e) =>
            functions[e.key].function?.toJson()['name'] ==
            '<unknown Dart function>')
        .fold<int>(0, (n, e) => n + e.value);
    final quality = totalSamples < 100
        ? 'Too few CPU samples for stable rankings; run longer.'
        : unknownSamples > totalSamples * .2
            ? 'More than 20% of leaf samples lack symbols; attribution is incomplete.'
            : null;

    await File('${out.path}/trace.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert({
      'schema': labSchema,
      'diagnosticOnly': true,
      'runtime': 'JIT with profiler',
      'collection': 'external supervisor; app paused for heap snapshots',
      'windowMicros': end - start,
      'cpuSampleCount': totalSamples,
      'unknownLeafSamples': unknownSamples,
      'qualityWarning': quality,
      'exclusive': rank(exclusive),
      'inclusive': rank(inclusive),
      'cpu': cpu.toJson(),
      'gcTimeline': timeline.toJson(),
      'heapBefore': before.toJson(),
      'heapAfter': after.toJson(),
      'heapAfterForcedGc': retained.toJson(),
      'note': 'Includes SDK classes and workload bookkeeping. Class inventories '
          'are not allocation stack traces. Forced GC brackets this diagnostic '
          'run only. CPU samples exclude startup, warmup, collection and teardown.',
    }));
    final summary = StringBuffer('# Fleury workload diagnosis\n\n')
      ..writeln(
          'Scenario: `${config.scenario}`. JIT diagnostic; timings are not AOT comparison results.\n')
      ..writeln(
          '$totalSamples CPU samples over ${((end - start) / 1000000).toStringAsFixed(2)} seconds; '
          '$unknownSamples unknown leaf samples.\n')
      ..writeln(quality == null
          ? 'Profiles collected by an external supervisor.\n'
          : '**$quality**\n')
      ..writeln('Heap before: ${before.memoryUsage?.heapUsage} bytes; '
          'after: ${after.memoryUsage?.heapUsage}; after forced GC: ${retained.memoryUsage?.heapUsage}. '
          'These include workload bookkeeping and JIT runtime state.\n')
      ..writeln('| Exclusive samples | Function |\n|---:|---|');
    for (final row in rank(exclusive).take(20)) {
      final function = row['function'] as Map?;
      summary.writeln(
          '| ${row['samples']} | `${function?['name'] ?? 'unknown'}` |');
    }
    summary.writeln(
        '\nInspect trace.json for inclusive stacks, source locations, GC events, '
        'and complete class inventories, including SDK allocations. Repeat a '
        'targeted run before attributing a regression to a small sample count.');
    await File('${out.path}/trace.md').writeAsString(summary.toString());
    completed = true;
    return code;
  } finally {
    if (!completed) process.kill(ProcessSignal.sigkill);
    await extensionEvents?.cancel();
    await service?.dispose();
    await Future.wait([stdoutDone, stderrDone]);
    await stdoutLog.close();
    await stderrLog.close();
  }
}
