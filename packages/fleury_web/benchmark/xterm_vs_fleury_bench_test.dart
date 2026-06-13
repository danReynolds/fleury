// Head-to-head browser render benchmark: fleury's retained DomGridSurface (the
// surface the serve client renders through) vs xterm.js across ALL THREE of its
// renderer tiers — DOM (default), canvas addon, WebGL addon — fed the SAME frame
// stream. fleury renders from a presentation plan; xterm renders from the
// equivalent ANSI produced by fleury's own AnsiRenderer (the exact bytes an
// ANSI-relay peer would send). Measures per-frame main-thread render cost, the
// budget that determines whether a renderer drops frames at 60 fps.
//
// Why three xterm tiers: ttyd/gotty/textual-web/VS Code all render through
// xterm.js (or hterm), so the meaningful render-peer axis is xterm's renderer
// tier, not the product. xterm's *parse* (write→buffer) is renderer-independent
// — the same core ANSI parser for all three — so the tier only changes the
// deferred render. The WebGL tier is the one that could beat a DOM surface; it
// needs a real GL context (the harness reports the backend and self-skips WebGL
// when none is available, rather than silently falling back to DOM).
//
// Metrics:
//   fleury apply+render — applyRemotePlan + present + forced layout, all sync
//     (fleury has no deferred render; this is its full per-frame cost).
//   xterm parse         — synchronous write()→buffer.
//   xterm parse→render  — wall time write()→onRender; xterm renders on its own
//     rAF, so this includes ~one frame of scheduling latency over the
//     (typically sub-frame) render compute.
// Excluded: GPU rasterization/compositing (not measurable from JS for either).
//
// NOT a CI test — tagged `benchmark`, lives outside test/, run on demand:
//   (cd packages/fleury_web && ./benchmark/fetch_xterm.sh &&
//    dart test -p chrome -t benchmark benchmark/xterm_vs_fleury_bench_test.dart -r expanded)
@TestOn('browser')
@Tags(['benchmark'])
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/remote_client/plan_adapter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

// --- xterm.js + renderer-addon interop (UMD globals) ------------------------

@JS('Terminal')
extension type _Term._(JSObject _) implements JSObject {
  external _Term(JSObject options);
  external void open(web.Element parent);
  external void write(JSString data, [JSFunction callback]);
  external JSObject onRender(JSFunction handler);
  external void loadAddon(JSObject addon);
  external void dispose();
}

@JS('Terminal')
external JSAny? get _termCtor;

@JS('_CanvasAddon')
extension type _CanvasAddon._(JSObject _) implements JSObject {
  external _CanvasAddon();
}

@JS('_CanvasAddon')
external JSAny? get _canvasCtor;

@JS('_WebglAddon')
extension type _WebglAddon._(JSObject _) implements JSObject {
  external _WebglAddon();
}

@JS('_WebglAddon')
external JSAny? get _webglCtor;

double _now() => web.window.performance.now();

Future<double> _rafBaseline() {
  final c = Completer<double>();
  final t0 = _now();
  web.window.requestAnimationFrame(((JSNumber _) => c.complete(_now() - t0)).toJS);
  return c.future;
}

/// The unmasked WebGL renderer string, or 'none' if no GL context exists in
/// this browser (e.g. headless without a GPU) — in which case the WebGL tier
/// cannot be measured and must be skipped rather than faked.
String _glBackend() {
  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
  final gl = canvas.getContext('webgl2') ?? canvas.getContext('webgl');
  if (gl == null) return 'none';
  final dbg =
      gl.callMethod<JSAny?>('getExtension'.toJS, 'WEBGL_debug_renderer_info'.toJS);
  if (!dbg.isDefinedAndNotNull) return 'masked';
  final param =
      (dbg as JSObject).getProperty<JSAny?>('UNMASKED_RENDERER_WEBGL'.toJS);
  return (gl.callMethod<JSAny?>('getParameter'.toJS, param) as JSString?)?.toDart ??
      'unknown';
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

Workload _churn(String name, int cols, int rows) => (
      name: name,
      cols: cols,
      rows: rows,
      frames: [
        for (var i = 0; i < 60; i++)
          (b) {
            const g = 'abcdefghijklmnopqrstuvwxyz0123456789 .,#@/|-+';
            for (var r = 0; r < rows; r++) {
              final sb = StringBuffer();
              for (var c = 0; c < cols; c++) {
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
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

double _p95(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  return s[min(s.length - 1, (s.length * 0.95).floor())];
}

String _ms(double v) => v.isNaN ? '   - ' : v.toStringAsFixed(2).padLeft(5);

const _warmup = 10; // discard early samples (JIT warmup)

List<double> _fleury(Workload w) {
  final size = CellSize(w.cols, w.rows);
  final root = web.document.createElement('div');
  web.document.body!.append(root);
  final surface = DomGridSurface(root: root, size: size);
  final mirror = CellBuffer(size);
  var prev = CellBuffer(size);
  final samples = <double>[];
  for (var i = 0; i < w.frames.length; i++) {
    final next = CellBuffer(size);
    _copy(prev, next);
    w.frames[i](next);
    // buildRemotePlan is the server's per-frame diff (excluded). The client's
    // job, timed here, is to apply the wire patches and render — the fair
    // analogue of xterm's parse-the-ANSI-and-render.
    final wirePlan = buildRemotePlan(prev, next, fullRepaint: i == 0);
    final t0 = _now();
    final plan = applyRemotePlan(wirePlan, mirror);
    surface.present(mirror, mirror, plan);
    root.getBoundingClientRect(); // force synchronous layout
    if (i >= _warmup) samples.add(_now() - t0);
    prev = next;
  }
  unawaited(surface.dispose());
  root.remove();
  return samples;
}

/// Runs the workload through xterm with the given renderer tier
/// ('dom' | 'canvas' | 'webgl'), or returns null if that tier is unavailable.
Future<({List<double> parse, List<double> render})?> _xterm(
    Workload w, String tier) async {
  // The canvas and WebGL renderers both need a real rendering context; in a
  // headless/software browser (no GL backend) xterm's accelerated renderers
  // fail to initialize — and the canvas addon fails *asynchronously* inside its
  // renderer creation, which a sync try/catch can't trap. So gate both on a
  // real GL context: skip + report unavailable here, auto-run on a GPU browser.
  if (tier == 'canvas' && (_canvasCtor == null || _glBackend() == 'none')) {
    return null;
  }
  if (tier == 'webgl' && (_webglCtor == null || _glBackend() == 'none')) {
    return null;
  }
  final size = CellSize(w.cols, w.rows);
  final root = web.document.createElement('div');
  web.document.body!.append(root);
  final term = _Term(<String, Object?>{
    'cols': w.cols,
    'rows': w.rows,
    'scrollback': 0,
    'convertEol': false,
    'disableStdin': true,
  }.jsify() as JSObject);
  term.open(root);
  try {
    if (tier == 'canvas') term.loadAddon(_CanvasAddon());
    if (tier == 'webgl') term.loadAddon(_WebglAddon());
  } catch (_) {
    term.dispose();
    root.remove();
    return null; // addon failed to initialize (e.g. no GL) — don't fake it
  }

  Completer<void>? pendingRender;
  term.onRender(((JSAny? _) {
    pendingRender?.complete();
    pendingRender = null;
  }).toJS);

  final sink = _AnsiStringSink();
  final ansi = AnsiRenderer(colorMode: ColorMode.truecolor);
  var prev = CellBuffer(size);
  final parse = <double>[];
  final render = <double>[];
  for (var i = 0; i < w.frames.length; i++) {
    final next = CellBuffer(size);
    _copy(prev, next);
    w.frames[i](next);
    ansi.renderDiff(i == 0 ? CellBuffer(size) : prev, next, sink,
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
    if (i >= _warmup) {
      parse.add(tParse - t0);
      render.add(_now() - t0);
    }
    prev = next;
  }
  term.dispose();
  root.remove();
  return (parse: parse, render: render);
}

void main() {
  test('fleury DomGridSurface vs xterm.js (DOM/canvas/WebGL) render cost',
      () async {
    expect(_termCtor != null, isTrue,
        reason: 'vendor/xterm.js must be fetched (see fetch_xterm.sh)');

    final glBackend = _glBackend();
    final baselines = <double>[for (var i = 0; i < 60; i++) await _rafBaseline()];
    final baseline = _median(baselines);

    final out = <String>[];
    out.add('');
    out.add('=== fleury DomGridSurface vs xterm.js — per-frame render cost, '
        'ms (median; p95) ===');
    out.add('rAF interval ${baseline.toStringAsFixed(1)}ms · 60fps budget '
        '16.7ms · WebGL backend: $glBackend');
    out.add('');

    try {
      for (final w in [
        _typing(),
        _dashboard(),
        _churn('churn 120x40', 120, 40),
        _churn('churn 200x60', 200, 60),
      ]) {
        out.add('-- ${w.name} --');
        final f = _fleury(w);
        out.add('  fleury  apply+render  ${_ms(_median(f))} (p95 ${_ms(_p95(f))})');
        for (final tier in ['dom', 'canvas', 'webgl']) {
          final r = await _xterm(w, tier);
          if (r == null) {
            out.add('  xterm $tier'.padRight(17) +
                'unavailable — needs a GPU browser (GL backend: $glBackend)');
            continue;
          }
          out.add('  xterm $tier'.padRight(17) +
              'parse ${_ms(_median(r.parse))}  '
                  'parse→render ${_ms(_median(r.render))} (p95 ${_ms(_p95(r.render))})');
        }
      }
    } catch (e, st) {
      out.add('!! threw: $e');
      out.add(st.toString().split('\n').take(4).join('\n'));
    }

    out.add('');
    out.add('fleury apply+render is fully synchronous (no deferred render). '
        'xterm parse is renderer-independent (shared core); parse→render '
        'includes ~one rAF of scheduling.');
    // ignore: avoid_print
    print(out.join('\n'));
  });
}

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
