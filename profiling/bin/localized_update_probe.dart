// Throwaway: when does a localized update actually cost paint?
//
// Sample apps answer "is this expensive on today's UI?" This probe answers
// "under what tree shape would skip-paint or incremental caches pay?"
//
// One of N styled rows rebuilds per frame. Three wrappings:
//   none  — no RepaintBoundary; every child paints
//   fine  — each row wrapped (ListView policy); one miss, N-1 hits
//   fat   — one RepaintBoundary around the whole column; one miss of all N
//
//   dart run bin/localized_update_probe.dart [--frames=400] [--warmup=80]
//
// Not a gate.
import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' show RepaintBoundaryDebugStats;

import 'gate_support.dart';

const _cols = 100;

enum _Wrap { none, fine, fat }

Widget _scene(List<RowModel> models, _Wrap wrap) {
  final rows = [
    for (var i = 0; i < models.length; i++)
      wrap == _Wrap.fine
          ? RepaintBoundary(
              child: liveRow(index: i, model: models[i], cols: _cols),
            )
          : liveRow(index: i, model: models[i], cols: _cols),
  ];
  final column = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: rows,
  );
  return wrap == _Wrap.fat ? RepaintBoundary(child: column) : column;
}

({double paintUs, double miss, double hit, double copied}) _run({
  required int rows,
  required int frames,
  required int warmup,
  required _Wrap wrap,
}) {
  final size = CellSize(_cols, rows);
  const renderer = AnsiRenderer();
  const sink = NullAnsiSink();
  final owner = BuildOwner();
  final models = [for (var i = 0; i < rows; i++) RowModel()];
  final root = owner.mountRoot(_scene(models, wrap));
  var front = CellBuffer(size);
  var back = CellBuffer(size);
  var paintTotal = 0;
  var missTotal = 0;
  var hitTotal = 0;
  var copiedTotal = 0;
  var active = 0;

  void frame({required bool measure}) {
    models[active].bump();
    active = (active + 1) % rows;
    back.withoutDamageTracking(back.clear);
    var paint = Duration.zero;
    RepaintBoundaryDebugStats.beginFrame(enabled: true);
    owner.renderFrame(root, back, onPhaseTiming: (b, l, p) => paint = p);
    final stats = RepaintBoundaryDebugStats.takeFrameStats();
    renderer.renderDiff(front, back, sink);
    if (measure) {
      paintTotal += paint.inMicroseconds;
      missTotal += stats.repaintedCount;
      hitTotal += stats.cachedCount;
      copiedTotal += stats.copiedCellCount;
    }
    final tmp = front;
    front = back;
    back = tmp;
  }

  for (var i = 0; i < warmup; i++) {
    frame(measure: false);
  }
  for (var i = 0; i < frames; i++) {
    frame(measure: true);
  }
  return (
    paintUs: paintTotal / frames,
    miss: missTotal / frames,
    hit: hitTotal / frames,
    copied: copiedTotal / frames,
  );
}

void main(List<String> args) {
  var frames = 400;
  var warmup = 80;
  for (final a in args) {
    if (parseIntFlag(a, 'frames') case final v?) frames = v;
    if (parseIntFlag(a, 'warmup') case final v?) warmup = v;
  }

  const rowCounts = [10, 40, 80];
  const wraps = _Wrap.values;
  const reps = 3;

  stdoutWrite(
    'localized-update probe — $_cols cols, one row rebuilds/frame '
    '($frames frames × $reps reps)',
  );
  stdoutWrite(
    'wrap   rows   paint µs    miss    hit   copied cells',
  );
  stdoutWrite(
    '------ ------ ---------- ------ ------ -------------',
  );

  for (final rows in rowCounts) {
    for (final wrap in wraps) {
      var paint = 0.0, miss = 0.0, hit = 0.0, copied = 0.0;
      for (var r = 0; r < reps; r++) {
        final sample = _run(
          rows: rows,
          frames: frames,
          warmup: warmup,
          wrap: wrap,
        );
        paint += sample.paintUs;
        miss += sample.miss;
        hit += sample.hit;
        copied += sample.copied;
      }
      paint /= reps;
      miss /= reps;
      hit /= reps;
      copied /= reps;
      stdoutWrite(
        '${wrap.name.padRight(6)} ${rows.toString().padLeft(6)} '
        '${paint.toStringAsFixed(1).padLeft(10)} '
        '${miss.toStringAsFixed(1).padLeft(6)} '
        '${hit.toStringAsFixed(1).padLeft(6)} '
        '${copied.toStringAsFixed(0).padLeft(13)}',
      );
    }
  }
}

void stdoutWrite(String line) {
  // ignore: avoid_print
  print(line);
}
