import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';

import 'catalog.dart';
import 'workload.dart' show MeasurementHook, WorkloadFailure;

class _ListHost extends StatefulWidget {
  const _ListHost(this.scenario, {super.key});
  final String scenario;

  @override
  State<_ListHost> createState() => _ListHostState();
}

class _ListHostState extends State<_ListHost> {
  final controller = ListController();
  late final items = List<Object>.generate(
    listRebuildCount(widget.scenario),
    (i) => widget.scenario == 'keyed-list-strings' ? 'item-$i' : i,
  );
  int keys = 0, rows = 0, update = 0;

  void tick() => setState(() {
        update++;
        if (widget.scenario == 'keyed-list-reorder') {
          final first = items[0];
          items[0] = items[1];
          items[1] = first;
        } else if (widget.scenario == 'keyed-list-replace') {
          items[items.length - 1] = items.length + update;
        }
      });

  @override
  Widget build(BuildContext context) => ListView.builder(
        controller: controller,
        itemCount: items.length,
        itemKeyBuilder: widget.scenario == 'unkeyed-list-rebuild'
            ? null
            : (i) {
                keys++;
                return items[i];
              },
        itemBuilder: (_, i, highlighted) {
          rows++;
          return Text('Item ${items[i]} update $update');
        },
      );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

Future<Map<String, Object?>> runListRebuild(LabOptions options,
    {MeasurementHook? start, MeasurementHook? stop}) async {
  final key = GlobalKey<_ListHostState>();
  final tester = FleuryTester(viewportSize: const CellSize(80, 20));
  final samples = <Map<String, num>>[];
  var verified = 0;
  try {
    tester.pumpWidget(_ListHost(options.scenario, key: key));
    tester.pump();
    final state = key.currentState!;
    void verify() {
      final text = tester.renderToString(emptyMark: ' ');
      // A swap can move the viewport down one row. Verify the actual range,
      // rather than assuming the first data index remains visible.
      final range = state.controller.visibleRange;
      if (range == null) throw StateError('The list has no visible range');
      final first = range.first;
      if (range.last - first + 1 != 20) {
        throw StateError('Expected 20 visible rows, got $range');
      }
      for (var i = first; i < first + 20; i++) {
        if (!text.contains('Item ${state.items[i]} update ${state.update}')) {
          throw StateError('Visible row $i did not update');
        }
      }
    }

    for (var i = 0; i < options.warmup; i++) {
      state.tick();
      tester.pump();
      verify();
    }
    state.keys = state.rows = 0;
    await start?.call();
    for (var i = 0; i < options.samples; i++) {
      final watch = Stopwatch()..start();
      state.tick();
      tester.pump();
      final elapsed = watch.elapsedMicroseconds;
      verify();
      verified++;
      samples.add({'id': i, 'totalUs': elapsed});
    }
    await stop?.call();
    final expectedKeys = options.scenario == 'unkeyed-list-rebuild'
        ? 0
        : state.items.length * options.samples;
    if (state.keys != expectedKeys) {
      throw StateError('Unexpected key calls: ${state.keys} != $expectedKeys');
    }
    return {
      'metrics': ['totalUs'],
      'samples': samples,
      'checks': {
        'verifiedUpdates': verified,
        'visibleRowsVerifiedPerUpdate': 20,
        'keysRead': state.keys,
        'rowsBuilt': state.rows,
      },
    };
  } catch (error) {
    throw WorkloadFailure(
        error, {'samples': samples, 'verifiedUpdates': verified});
  } finally {
    tester.dispose();
  }
}
