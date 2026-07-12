// Paint-walk investigation probe (architecture backlog #1).
//
// Question: every rendered frame re-walks the ENTIRE render tree to paint
// (only RepaintBoundary prunes it, and nothing auto-inserts them). How much
// paint CPU does a LOCALIZED update actually waste re-painting unchanged
// siblings, and how much does wrapping each row in a RepaintBoundary recover?
//
// Scenario: a dense screen of N full-width styled rows, each listening to its
// OWN notifier so only ONE row rebuilds per frame (a streaming-token / live-row
// update). Measures mean paint-phase time over a window, with and without a
// per-row RepaintBoundary, and reports the boundary cache hit-rate.
//
//   dart run bin/paint_walk_probe.dart [--rows=N] [--frames=N] [--warmup=N]
//
// Not a gate — an investigation harness. The delta justified it: the win
// shipped as ListView/scrollable auto-boundaries + Overlay adaptive entry
// boundaries, and the paint-cost gate is bin/paint_gate.dart
// (`fleury benchmark paint-gate`).

import 'package:fleury/fleury.dart';

const _cols = 100;

class _RowModel extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

// A row whose per-cell paint cost the caller picks: `cheap` is a short plain
// Text (the neutral-subtree case the RepaintBoundary docs warn about); the
// default is a full-width styled row (color + ~100 graphemes), where skipping
// the repaint is a real saving.
class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.model,
    required this.boundary,
    required this.cheap,
  });
  final int index;
  final _RowModel model;
  final bool boundary;
  final bool cheap;

  @override
  Widget build(BuildContext context) {
    final row = ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (cheap) return Text('row $index tick=${model.v}');
        final label = 'row $index  tick=${model.v}  ';
        final filled = label.padRight(_cols, '·');
        return Text(
          filled,
          style: CellStyle(
            foreground: RgbColor(120 + (index % 8) * 12, 200, 160),
            bold: index.isEven,
          ),
        );
      },
    );
    return boundary ? RepaintBoundary(child: row) : row;
  }
}

Widget _scene(List<_RowModel> models, bool boundary, bool cheap) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var i = 0; i < models.length; i++)
      _Row(index: i, model: models[i], boundary: boundary, cheap: cheap),
  ],
);

final class _NullAnsiSink implements AnsiSink {
  const _NullAnsiSink();
  @override
  void write(String data) {}
  @override
  Future<void> flush() async {}
}

double _run({
  required int rows,
  required int frames,
  required int warmup,
  required bool boundary,
  required bool cheap,
}) {
  final size = CellSize(_cols, rows);
  const renderer = AnsiRenderer();
  const sink = _NullAnsiSink();
  final owner = BuildOwner();
  final models = [for (var i = 0; i < rows; i++) _RowModel()];
  final root = owner.mountRoot(_scene(models, boundary, cheap));
  var front = CellBuffer(size);
  var back = CellBuffer(size);

  var paintTotalUs = 0;
  var active = 0;

  void frame({required bool measure}) {
    // Localized update: exactly one row rebuilds this frame.
    models[active].bump();
    active = (active + 1) % rows;
    back.withoutDamageTracking(back.clear);
    var paint = Duration.zero;
    owner.renderFrame(root, back, onPhaseTiming: (b, l, p) => paint = p);
    renderer.renderDiff(front, back, sink);
    if (measure) paintTotalUs += paint.inMicroseconds;
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
  return paintTotalUs / frames;
}

void main(List<String> args) {
  var rows = 40;
  var frames = 2000;
  var warmup = 400;
  var cheap = false;
  for (final a in args) {
    if (a.startsWith('--rows=')) rows = int.parse(a.substring(7));
    if (a.startsWith('--frames=')) frames = int.parse(a.substring(9));
    if (a.startsWith('--warmup=')) warmup = int.parse(a.substring(9));
    if (a == '--cheap') cheap = true;
  }

  // Interleave a few reps to average out JIT/GC noise between the two modes.
  var baseUs = 0.0, boundUs = 0.0;
  const reps = 3;
  for (var r = 0; r < reps; r++) {
    baseUs += _run(
      rows: rows, frames: frames, warmup: warmup, boundary: false, cheap: cheap,
    );
    boundUs += _run(
      rows: rows, frames: frames, warmup: warmup, boundary: true, cheap: cheap,
    );
  }
  baseUs /= reps;
  boundUs /= reps;

  final speedup = baseUs / boundUs;
  print('paint-walk probe — $rows rows × $_cols cols, one row changes/frame '
      '($frames frames × $reps reps)');
  print('  paint phase, NO boundaries : ${baseUs.toStringAsFixed(1)} µs/frame');
  print('  paint phase, per-row RB    : ${boundUs.toStringAsFixed(1)} µs/frame');
  print('  speedup                    : ${speedup.toStringAsFixed(2)}×');
}
