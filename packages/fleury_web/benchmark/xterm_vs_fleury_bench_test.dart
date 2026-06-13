// Head-to-head browser render benchmark: fleury's retained DomGridSurface (the
// surface the serve client renders through) vs xterm.js, fed the SAME frame
// stream. fleury renders from a presentation plan; xterm renders from the
// equivalent ANSI (produced by fleury's own AnsiRenderer — the exact bytes an
// ANSI-relay peer would send). Measures per-frame main-thread render cost, the
// budget that determines whether a renderer drops frames at 60 fps.
//
// Two metrics, measured identically where possible:
//   sync   — synchronous main-thread cost to apply + lay out one frame.
//            fleury: present() + forced layout (it has no deferred render).
//            xterm:  (write -> onRender) minus the empty-rAF baseline, i.e.
//                    its compute with the frame-scheduling latency removed.
//   torender — wall time from handing the frame to the surface until it is
//            rendered (fleury: present + one rAF; xterm: write -> onRender).
//            Includes one frame of scheduling latency for both.
//
// Excluded: GPU rasterization/compositing (not measurable from JS for either).
// xterm uses its default DOM renderer here (no canvas/WebGL addon); the WebGL
// addon would change raw-glyph throughput but is not the default and is
// typically unavailable in headless Chrome.
//
// NOT a CI test — tagged `benchmark`, run on demand:
//   (cd packages/fleury_web && ./benchmark/fetch_xterm.sh &&
//    dart test -p chrome -t benchmark benchmark/xterm_vs_fleury_bench_test.dart)
@TestOn('browser')
@Tags(['benchmark'])
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/remote_client/plan_adapter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

// --- xterm.js interop (UMD global `Terminal`) -------------------------------

@JS('Terminal')
extension type _Term._(JSObject _) implements JSObject {
  external _Term(JSObject options);
  external void open(web.Element parent);
  external void write(JSString data, [JSFunction callback]);
  external JSObject onRender(JSFunction handler);
  external void dispose();
}

@JS('Terminal')
external JSAny? get _termCtor;

double _now() => web.window.performance.now();

Future<double> _rafBaseline() {
  final c = Completer<double>();
  final t0 = _now();
  web.window.requestAnimationFrame(((JSNumber _) => c.complete(_now() - t0)).toJS);
  return c.future;
}

// --- frame sequences (same logical stream for both renderers) ---------------

typedef Workload = ({String name, int cols, int rows, List<void Function(CellBuffer)> frames});

Workload _typing() => (
      name: 'typing 80x24',
      cols: 80,
      rows: 24,
      frames: [
        for (var i = 0; i < 60; i++)
          (b) => b.writeText(const CellOffset(0, 10), 'x' * (i % 70 + 1)),
      ],
    );

Workload _dashboard() => (
      name: 'dashboard 80x24',
      cols: 80,
      rows: 24,
      frames: [
        for (var i = 0; i < 60; i++)
          (b) {
            for (var r = 0; r < 10; r++) {
              b.writeText(CellOffset(0, r * 2),
                  'metric $r: ${(i * 7 + r) % 100}% ${'=' * ((i + r) % 40)}');
            }
          },
      ],
    );

Workload _bigChurn() => (
      name: 'big churn 120x40',
      cols: 120,
      rows: 40,
      frames: [
        for (var i = 0; i < 60; i++)
          (b) {
            const g = 'abcdefghijklmnopqrstuvwxyz0123456789 .,#@/|-+';
            for (var r = 0; r < 40; r++) {
              final sb = StringBuffer();
              for (var c = 0; c < 120; c++) {
                sb.writeCharCode(g.codeUnitAt((i * 7 + r * 13 + c * 3) % g.length));
              }
              b.writeText(CellOffset(0, r), sb.toString());
            }
          },
      ],
    );

class _AnsiStringSink implements AnsiSink {
  final StringBuffer _buf = StringBuffer();
  @override
  void write(String data) => _buf.write(data);
  @override
  Future<void> flush() async {}
  String take() {
    final s = _buf.toString();
    _buf.clear();
    return s;
  }
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

double _p95(List<double> xs) {
  final s = [...xs]..sort();
  return s[min(s.length - 1, (s.length * 0.95).floor())];
}

void main() {
  test('fleury DomGridSurface vs xterm.js per-frame render cost', () async {
    final xtermAvailable = _termCtor != null;
    expect(xtermAvailable, isTrue,
        reason: 'vendor/xterm.js must be fetched (see fetch_xterm.sh)');

    // Headless Chrome's animation-frame interval, for context: the wall time a
    // deferred (rAF-scheduled) render waits before running. Both renderers'
    // actual *work* is what we isolate below; this is the floor it hides under.
    final baselines = <double>[for (var i = 0; i < 60; i++) await _rafBaseline()];
    final baseline = _median(baselines);

    const warmup = 10; // discard early samples (JIT warmup)
    final rows = <String>[];
    rows.add('workload          | fleury apply+render | xterm parse | '
        'xterm parse→render');
    rows.add('-' * 78);

    for (final w in [_typing(), _dashboard(), _bigChurn()]) {
      final size = CellSize(w.cols, w.rows);

      // --- fleury: build plans live, time only present() + forced layout ---
      // fleury has no deferred render: present() synchronously mutates the DOM
      // and the forced getBoundingClientRect commits layout, so this span is
      // its full per-frame main-thread render cost (GPU paint excluded).
      final fleuryRoot = web.document.createElement('div');
      web.document.body!.append(fleuryRoot);
      final surface = DomGridSurface(root: fleuryRoot, size: size);
      final mirror = CellBuffer(size);
      var prev = CellBuffer(size);
      final fPresent = <double>[];
      for (var i = 0; i < w.frames.length; i++) {
        final next = CellBuffer(size);
        _copy(prev, next);
        w.frames[i](next);
        // buildRemotePlan is the *server's* per-frame diff (excluded). The
        // client's job, timed here, is to apply the wire patches and render —
        // the fair analogue of xterm's parse-the-ANSI-and-render.
        final wirePlan = buildRemotePlan(prev, next, fullRepaint: i == 0);
        final t0 = _now();
        final plan = applyRemotePlan(wirePlan, mirror);
        surface.present(mirror, mirror, plan);
        fleuryRoot.getBoundingClientRect(); // force synchronous layout
        if (i >= warmup) fPresent.add(_now() - t0);
        prev = next;
      }
      await surface.dispose();
      fleuryRoot.remove();

      // --- xterm: time parse (write->callback) and render (write->onRender) -
      // Both are synchronous main-thread spans; parse runs in write(), render
      // on xterm's own rAF. parse→render is wall time and so includes one frame
      // of scheduling latency (≈ the baseline) on top of the render compute.
      final xtermRoot = web.document.createElement('div');
      web.document.body!.append(xtermRoot);
      final term = _Term(<String, Object?>{
        'cols': w.cols,
        'rows': w.rows,
        'scrollback': 0,
        'convertEol': false,
        'disableStdin': true,
      }.jsify() as JSObject);
      term.open(xtermRoot);
      Completer<void>? pendingRender;
      term.onRender(((JSAny? _) {
        pendingRender?.complete();
        pendingRender = null;
      }).toJS);

      final sink = _AnsiStringSink();
      final ansi = AnsiRenderer(colorMode: ColorMode.truecolor);
      var xprev = CellBuffer(size);
      final xParse = <double>[];
      final xRender = <double>[];
      for (var i = 0; i < w.frames.length; i++) {
        final next = CellBuffer(size);
        _copy(xprev, next);
        w.frames[i](next);
        ansi.renderDiff(i == 0 ? CellBuffer(size) : xprev, next, sink,
            dirtyBounds: null);
        final data = sink.take();
        final renderC = Completer<void>();
        final parseC = Completer<void>();
        pendingRender = renderC;
        final t0 = _now();
        term.write(data.toJS, (() => parseC.complete()).toJS);
        await parseC.future
            .timeout(const Duration(milliseconds: 250), onTimeout: () {});
        final tParse = _now();
        await renderC.future.timeout(const Duration(milliseconds: 250),
            onTimeout: () => pendingRender = null);
        final tRender = _now();
        if (i >= warmup) {
          xParse.add(tParse - t0);
          xRender.add(tRender - t0);
        }
        xprev = next;
      }
      term.dispose();
      xtermRoot.remove();

      rows.add('${w.name.padRight(18)}| '
          '${_ms(_median(fPresent))} (p95 ${_ms(_p95(fPresent))})    | '
          '${_ms(_median(xParse))}     | '
          '${_ms(_median(xRender))} (p95 ${_ms(_p95(xRender))})');
    }

    // ignore: avoid_print
    print('\n=== per-frame render cost, ms (median) — headless rAF interval '
        '${baseline.toStringAsFixed(1)}ms; 60fps budget 16.7ms ===');
    for (final r in rows) {
      // ignore: avoid_print
      print(r);
    }
    // ignore: avoid_print
    print('fleury apply+render = applyRemotePlan + present + forced layout, '
        'all sync (no deferral). xterm parse = write()→buffer; parse→render '
        'incl. one rAF of scheduling.\n');
  });
}

String _ms(double v) => v.toStringAsFixed(2).padLeft(5);

void _copy(CellBuffer from, CellBuffer to) {
  for (var r = 0; r < from.size.rows; r++) {
    for (var c = 0; c < from.size.cols; c++) {
      final cell = from.atColRow(c, r);
      if (cell.role == CellRole.leading && cell.grapheme != null) {
        to.writeText(CellOffset(c, r), cell.grapheme!, style: cell.style);
      }
    }
  }
}
