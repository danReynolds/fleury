// Byte-budget harness: how many bytes per frame does AnsiRenderer emit, and
// WHERE do they go (content vs SGR vs cursor vs sync)?
//
// The existing scenario benchmarks report a single "ANSI bytes" total computed
// as a FULL repaint. This harness instead measures the realistic INCREMENTAL
// diff between consecutive real frames and splits each frame's bytes by
// category, so we can see whether byte-level encoding work (e.g. incremental
// SGR instead of full reset+reapply) is worth doing — and on which workloads.
//
// "Bytes on the wire" are UTF-8 (what the terminal/SSH transport carries).
//
// Run:
//   dart run benchmark/byte_budget_benchmark.dart
//   dart run benchmark/byte_budget_benchmark.dart --json
//   dart run benchmark/byte_budget_benchmark.dart --size=120x40

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

// ---- Scenario definitions -------------------------------------------------

typedef _Capture = void Function();

class _Scenario {
  const _Scenario(this.id, this.name, this.note, this.body);

  final String id;
  final String name;

  /// What byte-pattern this scenario isolates.
  final String note;

  /// Drives the tester. Call `capture` after each frame to render + diff it
  /// into the sink. The first capture is the initial full paint; the rest are
  /// incremental update frames.
  final void Function(FleuryTester tester, _Capture capture) body;
}

MouseEvent _down(int c, int r) => MouseEvent(
  kind: MouseEventKind.down,
  button: MouseButton.left,
  col: c,
  row: r,
);
MouseEvent _drag(int c, int r) => MouseEvent(
  kind: MouseEventKind.drag,
  button: MouseButton.left,
  col: c,
  row: r,
);
MouseEvent _up(int c, int r) => MouseEvent(
  kind: MouseEventKind.up,
  button: MouseButton.left,
  col: c,
  row: r,
);
const _shiftRight = KeyEvent(
  KeyCode.arrowRight,
  modifiers: {KeyModifier.shift},
);

const _palette = [
  CellStyle(foreground: AnsiColor(1)),
  CellStyle(foreground: AnsiColor(2)),
  CellStyle(foreground: AnsiColor(3)),
  CellStyle(foreground: AnsiColor(4), bold: true),
  CellStyle(foreground: AnsiColor(5)),
  CellStyle(foreground: AnsiColor(6), italic: true),
];

Widget _styledRow(int i) => RichText(
  text: TextSpan(
    children: [
      TextSpan(
        text: 'svc-${i.toString().padLeft(2, '0')} ',
        style: _palette[i % 6],
      ),
      TextSpan(
        text: 'ready ',
        style: const CellStyle(foreground: AnsiColor(2)),
      ),
      TextSpan(text: 'p95=${12 + i}ms ', style: _palette[(i + 2) % 6]),
      TextSpan(text: 'region=use1', style: const CellStyle(dim: true)),
    ],
  ),
);

final _scenarios = <_Scenario>[
  _Scenario(
    'first-paint-styled',
    'First paint — styled screen',
    'baseline full paint of a colorful screen; content vs SGR split',
    (tester, capture) {
      tester.pumpWidget(
        Column(children: [for (var i = 0; i < 20; i++) _styledRow(i)]),
      );
      capture(); // initial paint only
    },
  ),
  _Scenario(
    'selection-highlight',
    'Selection extend',
    'inverse-highlight churn as a selection grows; SGR lever',
    (tester, capture) {
      tester.pumpWidget(
        const SelectionArea(
          child: Text(
            'the quick brown fox jumps over the lazy dog and then keeps going',
          ),
        ),
      );
      capture(); // first paint (painted bounds for hit-testing)
      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(3, 0));
      tester.sendMouse(_up(3, 0));
      capture(); // selection appears
      for (var i = 0; i < 10; i++) {
        tester.sendKey(_shiftRight);
        capture(); // selection extends one cell
      }
    },
  ),
  _Scenario(
    'color-churn',
    'Color churn — heatmap',
    'every cell changes color each tick; SGR-dominant updates',
    (tester, capture) {
      List<List<int>> grid(int shift) => [
        for (var r = 0; r < 6; r++)
          [for (var c = 0; c < 12; c++) (r * 12 + c + shift) % 10],
      ];
      tester.pumpWidget(
        SizedBox(
          width: 24,
          height: 6,
          child: Heatmap(values: grid(0), cellWidth: 2),
        ),
      );
      capture();
      for (var i = 1; i <= 10; i++) {
        tester.pumpWidget(
          SizedBox(
            width: 24,
            height: 6,
            child: Heatmap(values: grid(i), cellWidth: 2),
          ),
        );
        capture();
      }
    },
  ),
  _Scenario(
    'full-content-refresh',
    'Full content refresh (scroll-equivalent)',
    'every visible line changes; content + cursor heavy',
    (tester, capture) {
      // A real scroll: every visible row shows a different full line, and the
      // window shifts each frame, so the whole row content differs (fleury has
      // no scroll-region optimization, so this is a near-full repaint).
      String line(int n) =>
          'log $n: event ${n * 31 % 997} shard ${n % 8} took ${n % 250}ms '
          'user=${n * 7 % 9973} status=ok';
      Widget body(int off) =>
          Column(children: [for (var i = 0; i < 20; i++) Text(line(off + i))]);
      tester.pumpWidget(body(0));
      capture();
      for (var i = 1; i <= 10; i++) {
        tester.pumpWidget(body(i * 100));
        capture();
      }
    },
  ),
  _Scenario(
    'scattered-numbers',
    'Scattered numbers (sparse dashboard)',
    'only a few cells change per tick; cursor overhead vs tiny content',
    (tester, capture) {
      Widget dash(int tick) => Column(
        children: [
          const Text('host        prod-edge-01'),
          const Text('uptime      14d 6h'),
          Text('requests    ${100000 + tick * 7}'),
          const Text('errors      0'),
          Text('latency     ${20 + tick % 6}ms'),
          const Text('cpu         12%'),
          const Text('memory      340MB'),
          Text('queue       ${tick % 4}'),
          const Text('region      use1'),
          const Text('build       2026.06.04'),
        ],
      );
      tester.pumpWidget(dash(0));
      capture();
      for (var i = 1; i <= 10; i++) {
        tester.pumpWidget(dash(i));
        capture();
      }
    },
  ),
];

// ---- Runner ---------------------------------------------------------------

class _ScenarioReport {
  _ScenarioReport(this.scenario, this.firstPaint, this.updateFrames);

  final _Scenario scenario;
  final AnsiByteBreakdown firstPaint;
  final List<AnsiByteBreakdown> updateFrames;

  AnsiByteBreakdown get updateTotal =>
      updateFrames.fold(const AnsiByteBreakdown(), (a, b) => a + b);

  int get updateFrameCount => updateFrames.length;

  double get avgUpdateBytes =>
      updateFrameCount == 0 ? 0 : updateTotal.total / updateFrameCount;

  Map<String, Object> toJson() => <String, Object>{
    'id': scenario.id,
    'name': scenario.name,
    'note': scenario.note,
    'firstPaint': firstPaint.toJson(),
    'updateFrameCount': updateFrameCount,
    'updateTotal': updateTotal.toJson(),
    'avgUpdateBytes': avgUpdateBytes,
    'estLatencyMs': <String, double>{
      for (final p in TransportProfile.defaults)
        p.name: p.frameMs(
          updateFrameCount > 0 ? avgUpdateBytes.round() : firstPaint.total,
        ),
    },
  };
}

_ScenarioReport _run(_Scenario scenario, CellSize size) {
  final tester = FleuryTester(viewportSize: size);
  final sink = CountingAnsiSink();
  const renderer = AnsiRenderer();
  var prev = CellBuffer(size);
  void capture() {
    final cur = tester.render(size: size);
    renderer.renderDiff(prev, cur, sink);
    prev = cur;
  }

  scenario.body(tester, capture);

  // The renderer only writes non-empty frames, so sink.frames may be shorter
  // than the number of capture() calls. The first written frame is the initial
  // paint; the rest are updates.
  final frames = sink.frames;
  final first = frames.isEmpty ? const AnsiByteBreakdown() : frames.first;
  final updates = frames.length <= 1
      ? const <AnsiByteBreakdown>[]
      : frames.sublist(1);
  return _ScenarioReport(scenario, first, updates);
}

String _pct(int part, int whole) => whole == 0
    ? '  -  '
    : '${(100 * part / whole).toStringAsFixed(0).padLeft(3)}%';

/// Estimated wire time for a frame of [bytes] across the transport profiles —
/// the bytes->latency mapping (a model; confirm on hardware per the handoff).
String _latency(int bytes) => TransportProfile.defaults
    .map((p) => '${p.name} ${p.frameMs(bytes).toStringAsFixed(1)}ms')
    .join('  ·  ');

void _printHuman(List<_ScenarioReport> reports, CellSize size) {
  stdout.writeln(
    'Byte budget — terminal ${size.cols}x${size.rows}, '
    'UTF-8 bytes on the wire\n',
  );

  for (final r in reports) {
    stdout.writeln('▸ ${r.scenario.id}  —  ${r.scenario.name}');
    stdout.writeln('  ${r.scenario.note}');

    final fp = r.firstPaint;
    stdout.writeln(
      '  first paint : ${fp.total.toString().padLeft(6)} B   '
      'content ${_pct(fp.content, fp.total)}  '
      'sgr ${_pct(fp.sgr, fp.total)}  '
      'cursor ${_pct(fp.cursor, fp.total)}  '
      'sync ${_pct(fp.sync, fp.total)}',
    );

    if (r.updateFrameCount == 0) {
      stdout.writeln('  est latency : ${_latency(fp.total)}  (first paint)\n');
      continue;
    }
    final u = r.updateTotal;
    stdout.writeln(
      '  updates     : ${r.avgUpdateBytes.toStringAsFixed(0).padLeft(6)} B/frame'
      ' over ${r.updateFrameCount} frames   '
      'content ${_pct(u.content, u.total)}  '
      'sgr ${_pct(u.sgr, u.total)}  '
      'cursor ${_pct(u.cursor, u.total)}  '
      'sync ${_pct(u.sync, u.total)}',
    );
    stdout.writeln(
      '  update overhead (non-content): '
      '${(100 * u.overheadFraction).toStringAsFixed(0)}%',
    );
    stdout.writeln(
      '  est latency : ${_latency(r.avgUpdateBytes.round())}  '
      '(avg update frame)\n',
    );
  }

  // Cross-scenario verdict: where does SGR dominate update bytes?
  final allUpdates = reports.fold(
    const AnsiByteBreakdown(),
    (a, r) => a + r.updateTotal,
  );
  stdout.writeln('— Summary across update frames —');
  stdout.writeln('  total update bytes : ${allUpdates.total}');
  stdout.writeln(
    '  content ${_pct(allUpdates.content, allUpdates.total)}   '
    'sgr ${_pct(allUpdates.sgr, allUpdates.total)}   '
    'cursor ${_pct(allUpdates.cursor, allUpdates.total)}   '
    'sync ${_pct(allUpdates.sync, allUpdates.total)}',
  );
  final sgrHeavy = reports
      .where(
        (r) =>
            r.updateTotal.total > 0 &&
            r.updateTotal.sgr / r.updateTotal.total >= 0.30,
      )
      .map((r) => r.scenario.id)
      .toList();
  stdout.writeln(
    sgrHeavy.isEmpty
        ? '  SGR is <30% of update bytes everywhere — incremental SGR is low value.'
        : '  SGR ≥30% of update bytes in: ${sgrHeavy.join(', ')} '
              '— incremental SGR would pay off here.',
  );
}

void main(List<String> args) {
  var size = const CellSize(100, 30);
  var json = false;
  for (final arg in args) {
    if (arg == '--json') json = true;
    if (arg.startsWith('--size=')) {
      final parts = arg.substring('--size='.length).split('x');
      if (parts.length == 2) {
        size = CellSize(int.parse(parts[0]), int.parse(parts[1]));
      }
    }
  }

  final reports = [for (final s in _scenarios) _run(s, size)];

  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'terminalSize': {'cols': size.cols, 'rows': size.rows},
        'scenarios': [for (final r in reports) r.toJson()],
      }),
    );
  } else {
    _printHuman(reports, size);
  }
}
