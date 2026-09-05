// Geometry-model probe (derived-geometry migration baseline).
//
// Fleury's render objects do not know their own screen position; every
// consumer of geometry — pointer regions, focus rectangles, semantic bounds,
// retained selection geometry — records it during paint, and repaint
// boundaries replay those records on cache hits. The alternative is to derive
// geometry from layout state on demand. This probe measures both sides of
// that trade on one fixture, so the migration can be judged on numbers:
//
//   paint      a localized update (one row) and a full update, i.e. the cost
//              of recording + replaying geometry at every boundary (each
//              frame renders into a fresh buffer: a constant both sides pay)
//   pointer    hover and tap events routed through the region registry
//   focus      Tab traversal steps (geometry-sorted order)
//   semantics  a full semantic snapshot (bounds come from paint records)
//
//   dart run bin/geometry_probe.dart [--items=N] [--frames=N] [--events=N]
//                                    [--json=PATH]
//
// Fixture: a ListView.builder of N rows (auto repaint boundary per row), each
// row a GestureDetector + Focus + Semantics list item around a live Text, so
// every row registers a pointer region, a focus rectangle, a semantic bound,
// and a text selection record — the four capture channels.

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
    }),
  );
  samples.add(
    _measure('paint: all mounted rows change', frames, (i) {
      for (var v = 0; v < visible; v++) {
        models[v].bump();
      }
      tester.pump();
      tester.render();
    }),
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

  // ---- derived model ------------------------------------------------------
  //
  // The same fixture with the four capture channels switched off at every
  // boundary (paint rows), and the geometry consumers answered by walking
  // layout state instead (query rows). The query rows are upper bounds: a
  // migrated hit-test would walk top-down and stop early; here every
  // candidate's geometry is derived on every event.
  RenderRepaintBoundary.debugSkipGeometryCapture = true;
  for (var v = 0; v < visible; v++) {
    models[v].bump(); // invalidate every cache once so the flag takes effect
  }
  tester.pump();
  tester.render();
  samples.add(
    _measure('paint (no capture): one row changes', frames, (i) {
      models[i % visible].bump();
      tester.pump();
      tester.render();
    }),
  );
  samples.add(
    _measure('paint (no capture): all mounted rows change', frames, (i) {
      for (var v = 0; v < visible; v++) {
        models[v].bump();
      }
      tester.pump();
      tester.render();
    }),
  );
  final root = tester.rootRenderObject!;
  final listeners =
      renderSubtree(root).whereType<RenderPointerListener>().toList();
  final all = renderSubtree(root).length;
  stdout.writeln(
    'derived: ${listeners.length} pointer regions, $all render objects',
  );
  samples.add(
    _measure('derived: hover hit-test (all regions)', events, (i) {
      final col = rnd.nextInt(_cols);
      final row = rnd.nextInt(_rows);
      RenderPointerListener? hit;
      for (final listener in listeners) {
        final visibleRect = screenGeometryOf(listener)?.visible;
        if (visibleRect != null && visibleRect.contains(CellOffset(col, row))) {
          hit = listener; // last in paint order wins
        }
      }
      if (hit == null && col < 0) stdout.write(''); // keep the loop honest
    }),
  );
  samples.add(
    _measure('derived: geometry of every region', 200, (i) {
      for (final listener in listeners) {
        screenGeometryOf(listener);
      }
    }),
  );
  samples.add(
    _measure('derived: geometry of every render object', 50, (i) {
      for (final node in renderSubtree(root)) {
        screenGeometryOf(node);
      }
    }, warmup: 5),
  );
  RenderRepaintBoundary.debugSkipGeometryCapture = false;

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
