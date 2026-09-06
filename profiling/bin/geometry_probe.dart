// Geometry probe.
//
// Fleury derives every render object's screen position from layout state
// (`RenderObject.screenGeometry`): nothing is recorded during paint and a
// repaint boundary's cache hit skips the subtree walk entirely. This probe
// measures the frame paths that geometry feeds on one fixture, so a change
// to the render tier can be judged on numbers — and compared with the
// paint-time-capture baseline recorded before the migration
// (docs/rfcs/0024-derived-geometry.md):
//
//   paint      a localized update (one row) and a full update
//   pointer    hover and tap events, hit-tested by walking the render tree
//   focus      Tab traversal steps (geometry-sorted order)
//   semantics  a full semantic snapshot (bounds derived at collection)
//   derived    the raw cost of deriving geometry for every region and every
//              render object in one epoch
//   late       the paint, hover, and semantics rows again after everything
//              else has run, so JIT warmth is comparable across orderings
//              and probes — compare those, not the first rows
//
//   dart run bin/geometry_probe.dart [--items=N] [--frames=N] [--events=N]
//                                    [--json=PATH]
//
// Fixture: a ListView.builder of N rows (auto repaint boundary per row), each
// row a GestureDetector + Focus + Semantics list item around a live Text, so
// every row has a pointer region, a focus rectangle, a semantic bound, and
// text selection geometry.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_internal.dart';
import 'package:fleury/fleury_test_support.dart';

import 'gate_support.dart';

const _cols = 120;
const _rows = 60;

class _Row extends StatelessWidget {
  const _Row({required this.index, required this.model, required this.node});
  final int index;
  final RowModel model;
  final FocusNode node;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {},
        child: Focus(
          focusNode: node,
          child: Semantics(
            role: SemanticRole.listItem,
            label: 'row $index',
            child: ListenableBuilder(
              listenable: model,
              builder: (context, child) => Text('row $index tick=${model.v}'),
            ),
          ),
        ),
      );
}

final class _Sample {
  _Sample(this.name, this.ops, List<int> micros)
      : micros = micros..sort(),
        mean =
            micros.isEmpty ? 0 : micros.reduce((a, b) => a + b) / micros.length;
  final String name;
  final int ops;
  final List<int> micros;
  final double mean;
  int get p50 => micros[micros.length ~/ 2];
  int get p95 =>
      micros[(micros.length * 0.95).floor().clamp(0, micros.length - 1)];
  Map<String, Object?> toJson() => {
        'ops': ops,
        'meanUs': double.parse(mean.toStringAsFixed(2)),
        'p50Us': p50,
        'p95Us': p95,
      };
}

_Sample _measure(String name, int ops, void Function(int i) op,
    {int warmup = 20}) {
  for (var i = 0; i < warmup; i++) {
    op(i);
  }
  final micros = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < ops; i++) {
    sw
      ..reset()
      ..start();
    op(i);
    sw.stop();
    micros.add(sw.elapsedMicroseconds);
  }
  return _Sample(name, ops, micros);
}

void main(List<String> args) {
  var items = 1000;
  var frames = 200;
  var events = 1000;
  String? jsonPath;
  for (final arg in args) {
    items = parseIntFlag(arg, 'items') ?? items;
    frames = parseIntFlag(arg, 'frames') ?? frames;
    events = parseIntFlag(arg, 'events') ?? events;
    if (arg.startsWith('--json=')) jsonPath = arg.substring('--json='.length);
  }

  final tester = FleuryTester(viewportSize: const CellSize(_cols, _rows));
  final models = [for (var i = 0; i < items; i++) RowModel()];
  final nodes = [for (var i = 0; i < items; i++) FocusNode()];
  tester.pumpFleuryHome(
    ListView.builder(
      itemCount: items,
      itemBuilder: (context, index, _) =>
          _Row(index: index, model: models[index], node: nodes[index]),
    ),
  );
  // The tester is headless: pump() flushes builds, render() produces a frame
  // (layout + paint into a fresh buffer). The lazy list mounts its rows during
  // layout, so render one frame before counting what is on screen.
  tester.pump();
  tester.render();
  final visible = tester.semantics().byRole(SemanticRole.listItem).length;
  stdout.writeln(
    'fixture: $items rows, $visible mounted (${_cols}x$_rows), '
    '${frames} frames, $events events',
  );

  final samples = <_Sample>[];
  final rnd = Random(1);

  samples.add(
    _measure('paint: one row changes', frames, (i) {
      models[i % visible].bump();
      tester.pump();
      tester.render();
    }, warmup: 200),
  );
  samples.add(
    _measure('paint: all mounted rows change', frames, (i) {
      for (var v = 0; v < visible; v++) {
        models[v].bump();
      }
      tester.pump();
      tester.render();
    }, warmup: 200),
  );
  samples.add(
    _measure('pointer: hover event', events, (i) {
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.moved,
          button: MouseButton.none,
          col: rnd.nextInt(_cols),
          row: rnd.nextInt(_rows),
        ),
      );
    }),
  );
  samples.add(
    _measure('pointer: tap (down + up)', events, (i) {
      final col = rnd.nextInt(_cols);
      final row = rnd.nextInt(_rows);
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: col,
          row: row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: col,
          row: row,
        ),
      );
      tester.pump();
      tester.render();
    }),
  );
  samples.add(
    _measure('focus: Tab step + frame', events, (i) {
      tester.press(KeyCode.tab);
      tester.pump();
      tester.render();
    }),
  );
  samples.add(
    _measure('semantics: full snapshot', 50, (i) {
      tester.semantics();
    }, warmup: 5),
  );

  // ---- derivation cost ----------------------------------------------------
  //
  // Geometry is memoized per epoch, so a frame that asks for many nodes pays
  // one short walk per node; a new epoch (any invalidation) starts over.
  final root = tester.rootRenderObject!;
  final listeners =
      renderSubtree(root).whereType<RenderPointerListener>().toList();
  final all = renderSubtree(root).length;
  stdout.writeln(
    'derived: ${listeners.length} pointer regions, $all render objects',
  );
  samples.add(
    _measure('derived: geometry of every region (fresh epoch)', 200, (i) {
      models[i % visible].bump();
      tester.pump();
      tester.render();
      for (final listener in listeners) {
        listener.screenGeometry();
      }
    }),
  );
  samples.add(
    _measure('derived: geometry of every render object', 50, (i) {
      for (final node in renderSubtree(root)) {
        node.screenGeometry();
      }
    }, warmup: 5),
  );

  // ---- late rows ------------------------------------------------------------
  //
  // The same paths again after every other row has run, so JIT warmth is
  // comparable across probes and orderings; plus a frame with nothing dirty.

  samples.add(
    _measure('late: no-op frame (nothing dirty)', frames, (i) {
      tester.pump();
      tester.render();
    }, warmup: 200),
  );
  samples.add(
    _measure('late: paint one row changes', frames, (i) {
      models[i % visible].bump();
      tester.pump();
      tester.render();
    }, warmup: 200),
  );
  samples.add(
    _measure('late: paint all mounted rows change', frames, (i) {
      for (var v = 0; v < visible; v++) {
        models[v].bump();
      }
      tester.pump();
      tester.render();
    }, warmup: 200),
  );
  samples.add(
    _measure('late: hover event', events, (i) {
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.moved,
          button: MouseButton.none,
          col: rnd.nextInt(_cols),
          row: rnd.nextInt(_rows),
        ),
      );
    }),
  );
  samples.add(
    _measure('late: semantics full snapshot', 50, (i) {
      tester.semantics();
    }, warmup: 5),
  );

  stdout.writeln('');
  stdout.writeln(
    '${'operation'.padRight(34)} ${'ops'.padLeft(6)} '
    '${'mean µs'.padLeft(9)} ${'p50'.padLeft(7)} ${'p95'.padLeft(7)}',
  );
  for (final s in samples) {
    stdout.writeln(
      '${s.name.padRight(34)} ${s.ops.toString().padLeft(6)} '
      '${s.mean.toStringAsFixed(1).padLeft(9)} '
      '${s.p50.toString().padLeft(7)} ${s.p95.toString().padLeft(7)}',
    );
  }
  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'fixture': {
          'items': items,
          'mounted': visible,
          'cols': _cols,
          'rows': _rows
        },
        for (final s in samples) s.name: s.toJson(),
      }),
    );
    stdout.writeln('wrote $jsonPath');
  }
  tester.dispose();
}
