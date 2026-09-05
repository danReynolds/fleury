// Sample-app Fleury-class heap after GC, not total heap or AOT RSS.
// SDK lists/strings and external storage are excluded from project totals.
// Dart 3.12.2 reports accumulatedSize from the same heap walk as bytesCurrent;
// neither field is a cumulative allocation counter. Do not divide it by frames.
// Run with --deterministic to keep JIT compilation order consistent:
// dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//   bin/frame_heap_probe.dart --app dashboard --mode leaf --frames 400
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:vm_service/vm_service_io.dart';

import 'sample_frame_host.dart';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 == args.length ||
        !const [
          '--app',
          '--mode',
          '--cols',
          '--rows',
          '--frames',
          '--warmup',
          '--selected'
        ].contains(args[i])) {
      throw ArgumentError('Unknown flag or missing value: ${args[i]}');
    }
    options[args[i]] = args[i + 1];
  }
  final name = options['--app'] ?? 'dashboard';
  final mode = options['--mode'] ?? 'leaf';
  final cols = int.parse(options['--cols'] ?? '120');
  final rows = int.parse(options['--rows'] ?? '40');
  final frames = int.parse(options['--frames'] ?? '400');
  final warmup = int.parse(options['--warmup'] ?? '300');
  final selectedValue = options['--selected'] ?? 'false';
  if (!['true', 'false'].contains(selectedValue))
    throw ArgumentError('Invalid selection');
  final selected = selectedValue == 'true';
  final document = !name.endsWith('-document')
      ? ''
      : List.generate(
          1000,
          (i) =>
              '${i.toString().padLeft(6, '0')}  INFO  worker accepted request; '
              'elapsed=12ms status=ok 漢字 👩‍💻').join('\n');
  final Widget app = switch (name) {
    'dashboard' => const DashboardApp(),
    'agent' => const AgentApp(),
    'files' => const FileManagerApp(),
    'editor' => const EditorApp(),
    'finance' => const FinanceApp(),
    'plain-document' => ScrollView(child: Text(document, softWrap: false)),
    'rich-document' => ScrollView(
        child: RichText(
            text: TextSpan(
                text: document,
                style: const CellStyle(foreground: AnsiColor(6))),
            softWrap: false)),
    _ => throw ArgumentError('Unknown app: $name'),
  };
  if (!['clean', 'leaf', 'full'].contains(mode) ||
      frames < 1 ||
      warmup < 1 ||
      cols < 1 ||
      rows < 1) {
    throw ArgumentError('Invalid mode or frame count');
  }
  final server = (await developer.Service.getInfo()).serverUri;
  if (server == null) throw StateError('Run with --enable-vm-service=0');
  final service = await vmServiceConnectUri(server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString());
  final host = SampleFrameHost(app, CellSize(cols, rows));
  try {
    if (selected) {
      if (!name.endsWith('-document'))
        throw ArgumentError('Selection requires a document app');
      final text = host.renderObjects.whereType<Selectable>().single;
      text.dispatchSelectionEvent(const SelectionGranularEvent(
        granularity: SelectionGranularity.all,
      ));
      if (text.getSelectedContent()?.plainText != document) {
        throw StateError('Document selection must be active');
      }
    }
    if (mode == 'leaf' && !host.hasLeaf) throw StateError('No visible leaf');
    final isolateId = (await service.getVM()).isolates!.first.id!;
    for (var i = 0; i < warmup; i++) {
      host.frame(mode, i);
    }
    final before = await service.getAllocationProfile(isolateId, gc: true);
    var changed = 0;
    for (var i = 0; i < frames; i++) {
      if (host.frame(mode, warmup + i).changed) changed++;
    }
    final after = await service.getAllocationProfile(isolateId, gc: true);
    final classes = <Map<String, Object?>>[];
    final beforeClasses = {for (final m in before.members!) m.classRef!.id: m};
    var liveBefore = 0;
    var liveAfter = 0;
    for (final m in after.members!) {
      final uri = m.classRef?.library?.uri ?? '';
      if (!uri.startsWith('package:fleury')) continue;
      final first = beforeClasses[m.classRef!.id]?.bytesCurrent ?? 0;
      final last = m.bytesCurrent ?? 0;
      liveBefore += first;
      liveAfter += last;
      if (first == 0 && last == 0) continue;
      classes.add({
        'class': m.classRef!.name,
        'library': uri,
        'instancesAfterGc': m.instancesCurrent,
        'liveBeforeBytes': first,
        'liveAfterBytes': last,
      });
    }
    classes.sort((a, b) =>
        (b['liveAfterBytes'] as int).compareTo(a['liveAfterBytes'] as int));
    stdout.writeln(jsonEncode({
      'app': name,
      'mode': mode,
      'selected': selected,
      'columns': cols,
      'rows': rows,
      'frames': frames,
      'warmup': warmup,
      'changedFrames': changed,
      'renderObjects': host.renderObjects.length,
      'projectLiveBeforeBytes': liveBefore,
      'projectLiveAfterBytes': liveAfter,
      'heapAfter': after.memoryUsage?.toJson(),
      'classes': classes,
      'dart': Platform.version,
    }));
    // Keep the mounted app alive through the post-GC snapshot.
    host.frame(mode, warmup + frames);
  } finally {
    host.tester.dispose();
    await service.dispose();
  }
}
