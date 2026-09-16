// Targeted AOT comparison of automatic key snapshots vs an explicit revision.
// Run fresh process pairs in alternating order; do not pool frames from
// different processes as independent measurements. See profiling-v2.md.
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';

class _Host extends StatefulWidget {
  const _Host(this.count, this.useRevision, {super.key});
  final int count;
  final bool useRevision;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final controller = ListController();
  int keys = 0, rows = 0, update = 0;
  void tick() => setState(() => update++);

  @override
  Widget build(BuildContext context) => ListView.builder(
        controller: controller,
        itemCount: widget.count,
        // Only row content changes; the ordered integer keys stay the same.
        itemKeyRevision: widget.useRevision ? 0 : null,
        itemKeyBuilder: (i) {
          keys++;
          return i;
        },
        itemBuilder: (_, i, highlighted) {
          rows++;
          return Text('Item $i update $update');
        },
      );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

void main(List<String> args) {
  if (args.length != 2 || !{'auto', 'revision'}.contains(args[1])) {
    throw ArgumentError(
        'Usage: keyed_list_rebuild_probe <item-count> <auto|revision>');
  }
  final count = int.parse(args[0]);
  if (count < 20) throw ArgumentError('item-count must be >= 20');
  const samples = 150, warmup = 30;
  final key = GlobalKey<_HostState>();
  final tester = FleuryTester(viewportSize: const CellSize(80, 20));
  try {
    tester.pumpWidget(_Host(count, args[1] == 'revision', key: key));
    tester.pump();
    final state = key.currentState!;
    for (var i = 0; i < warmup; i++) {
      state.tick();
      tester.pump();
    }
    state.keys = 0;
    state.rows = 0;
    final times = <int>[];
    for (var i = 0; i < samples; i++) {
      final watch = Stopwatch()..start();
      state.tick();
      tester.pump();
      times.add(watch.elapsedMicroseconds);
    }
    final keyCalls = state.keys;
    final rowCalls = state.rows;
    final text = tester.renderToString(emptyMark: ' ');
    for (var i = 0; i < 20; i++) {
      if (!text.contains('Item $i update ${samples + warmup}')) {
        throw StateError('Visible row $i did not update');
      }
    }
    final expectedKeys = args[1] == 'revision' ? 0 : count * samples;
    if (keyCalls != expectedKeys)
      throw StateError('Unexpected key calls: $keyCalls');
    stdout.writeln(jsonEncode({
      'scenario': 'keyed-list-parent-rebuild',
      'boundary':
          'setState through pump; excludes encoding, transport and display',
      'count': count,
      'mode': args[1],
      'samples': samples,
      'warmup': warmup,
      'keysPerUpdate': keyCalls / samples,
      'rowsPerUpdate': rowCalls / samples,
      'verifiedVisibleRows': 20,
      'rawUs': times,
    }));
  } finally {
    tester.dispose();
  }
}
