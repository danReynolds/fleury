// Paint-cost regression gate (paint-gate).
//
// Paint was the one gated hot path with no regression protection. The
// paint-walk probe (bin/paint_walk_probe.dart) measured the win —
// RepaintBoundary pruning turns a localized update's full-tree paint re-walk
// into one repaint + N−1 cache blits — and that win now ships as ListView
// per-item auto-boundaries plus Overlay per-entry ADAPTIVE boundaries
// (engaged only while >1 entry is visible; see PR #84). This gate keeps all
// three behaviors true as the code moves: the pruning, the adaptive
// engagement, and the lazy-layer convention.
//
// Primary axes are DETERMINISTIC COUNTERS, not timings: per-frame
// RepaintBoundaryFrameStats (boundaryCount / repaintedCount / cachedCount /
// emptyCount / copiedCellCount) captured via
// RepaintBoundaryDebugStats.beginFrame / takeFrameStats around each
// renderFrame. On a fixed widget fixture the per-frame signature is exact —
// machine- and SDK-independent, zero tolerance — so the gate fails on ANY
// counter drift. Paint-phase µs (onPhaseTiming) is recorded and baselined
// WARN-ONLY (the wire gate's precedent for timing axes): it prints drift,
// never fails on it.
//
// Scenarios (steady-state: warm-up frames, then every measured frame must
// repeat the same signature — in-run stability is itself asserted):
//
//   S1 list-localized     ListView.builder rows — the REAL widget, so its
//                         per-item auto-boundaries are what's measured. ONE
//                         row's own model bumps per frame: exactly one
//                         repaint, every other visible row cache-blits.
//   S2 overlay-churn      Explicit Overlay: static full-screen base entry +
//                         churning non-opaque floater. The floater repaints;
//                         the base blits from cache instead of re-walking.
//   S3 overlay-idle-lazy  THE GUARDRAIL for the lazy-layer convention: an
//                         app-shaped fixture (Overlay whose only mounted
//                         entry is the app, wrapped in a real Toaster with
//                         zero toasts) must be PURE PASS-THROUGH while idle —
//                         boundaryCount == 0 on every frame. A widget that
//                         permanently mounts an empty overlay entry keeps
//                         the host overlay multi-entry, which keeps the
//                         per-entry boundaries engaged and taxes every
//                         app-dirty frame with a full-screen cache write +
//                         blit (the regression PR #84's review caught in
//                         Toaster itself) — that flips this scenario red.
//                         Mid-run a toast is enqueued (engagement must
//                         appear: boundaryCount 2) and auto-dismissed via
//                         the fake scheduler (pass-through must return):
//                         the full adaptive cycle in one scenario.
//   S4 full-invalidate    Every row changes every frame: cachedCount must
//                         be 0 and repaintedCount == boundaryCount. A
//                         boundary that cache-hits while everything under
//                         it is dirty is serving STALE cells — this is the
//                         staleness detector.
//   S5 dropdown-typing    INFORMATIONAL (warn-only, no counter gate): base
//                         and floater BOTH dirty every frame — the
//                         autocomplete-while-typing shape. Recorded so the
//                         known both-dirty tax stays visible in the report
//                         and baseline; it never fails the gate.
//
// Structural invariants (the relations above) are enforced on EVERY run —
// including --update-baseline — so a broken shape cannot be baselined away.
// The committed baseline pins the exact integers on top of that.
//
//   dart run bin/paint_gate.dart [--gate] [--update-baseline]
//       [--frames=N] [--warmup=N] [--baseline=path]
//
// Exit codes: 0 pass, 1 regression / invariant failure, 64 usage error.

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
// The repaint-boundary debug counters and the fake clock/scheduler are
// deliberately published through the test barrel only. Profiling is a
// harness (publish_to: none), so a gate binary importing the test surface
// is intended reuse, not a leak into production.
import 'package:fleury/fleury_test.dart'
    show
        FakeClock,
        FakeTickerScheduler,
        RepaintBoundaryDebugStats,
        RepaintBoundaryFrameStats;
import 'package:fleury_widgets/fleury_widgets.dart' show Toaster;

const _cols = 80;
const _rows = 24;
const _size = CellSize(_cols, _rows);
const _listItemCount = 40; // more items than the viewport: pins lazy mount

const _defaultFrames = 300; // measured frames per steady-state window
const _defaultWarmup = 60;

/// Timing axes warn beyond this relative change, never fail (paint µs is
/// machine-dependent; the counters are the gate).
const _timingWarnFraction = 0.5;

// ---------------------------------------------------------------------------
// Fixture widgets
// ---------------------------------------------------------------------------

class _Model extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

/// Full-width styled row (the paint-walk probe's row): wide enough that a
/// skipped repaint is a real saving, padded to a fixed width so damage
/// bounds — and therefore copiedCellCount — cannot wobble as ticks grow.
Widget _rowText(int index, int tick) {
  final label = 'row $index  tick=$tick  ';
  return Text(
    label.padRight(_cols, '·'),
    style: CellStyle(
      foreground: RgbColor(120 + (index % 8) * 12, 200, 160),
      bold: index.isEven,
    ),
  );
}

/// One list row listening to its OWN model — the streaming-token / live-row
/// shape from the probe.
Widget _listRow(int index, _Model model) => ListenableBuilder(
  listenable: model,
  builder: (context, _) => _rowText(index, model.v),
);

/// A static full-screen dashboard: [rows] full-width styled rows that never
/// rebuild. The overlay base entry for S2/S5.
Widget _staticDashboard() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < _rows; i++) _rowText(i, 0)],
);

/// A dashboard whose EVERY row carries the model's tick — one bump dirties
/// the whole subtree (the app-dirty frame S3's convention protects).
Widget _churningDashboard(_Model model) => ListenableBuilder(
  listenable: model,
  builder: (context, _) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (var i = 0; i < _rows; i++) _rowText(i, model.v)],
  ),
);

/// A small churning floater box, bottom-right — a toast/dropdown stand-in
/// with a fixed footprint (3 rows × 24 cols) so its damage bounds are exact.
Widget _floaterBox(_Model model) => Align(
  alignment: Alignment.bottomRight,
  child: ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('┌ floater ┐'.padRight(24, '·')),
        Text('│ tick=${model.v} '.padRight(24, '·')),
        Text('└──────────┘'.padRight(24, '·')),
      ],
    ),
  ),
);

/// Hands its own BuildContext to the caller (for `Toaster.show`) and builds
/// [child]. The same shape the Toaster widget tests use.
class _ContextProbe extends StatelessWidget {
  const _ContextProbe({required this.onContext, required this.child});
  final void Function(BuildContext) onContext;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onContext(context);
    return child;
  }
}

// ---------------------------------------------------------------------------
// Host: ambient scopes + probe-style frame loop
// ---------------------------------------------------------------------------

final class _NullAnsiSink implements AnsiSink {
  const _NullAnsiSink();
  @override
  void write(String data) {}
  @override
  Future<void> flush() async {}
}

/// Mounts a scene under the ambient scopes the widget tests install
/// (FleuryTester's wrap: binding + media query + focus + pointer scopes), so
/// real widgets — ListView, Overlay, Toaster — run app-shaped. Frames are
/// probe-style: renderFrame into a reused double buffer + AnsiRenderer diff
/// into a null sink, with the boundary debug stats armed around each frame.
/// Time is a FakeClock: it moves only when a scenario advances it, so
/// ticker-driven behavior (the toast auto-dismiss) lands on an exact frame.
final class _Host {
  _Host(Widget scene) {
    binding = TuiBinding(tickerScheduler: scheduler);
    root = owner.mountRoot(
      TuiBindingScope(
        binding: binding,
        child: MediaQuery(
          data: const MediaQueryData(size: _size),
          child: FocusManagerScope(
            manager: focusManager,
            child: PointerRouterScope(router: pointerRouter, child: scene),
          ),
        ),
      ),
    );
  }

  final FakeClock clock = FakeClock();
  late final FakeTickerScheduler scheduler = FakeTickerScheduler(clock: clock);
  late final TuiBinding binding;
  final FocusManager focusManager = FocusManager();
  final PointerRouter pointerRouter = PointerRouter();
  final BuildOwner owner = BuildOwner();
  late final Element root;

  static const _renderer = AnsiRenderer();
  static const _sink = _NullAnsiSink();

  CellBuffer _front = CellBuffer(_size);
  CellBuffer _back = CellBuffer(_size);

  /// Paint-phase µs of the most recent [frame].
  int lastPaintUs = 0;

  RepaintBoundaryFrameStats frame() {
    RepaintBoundaryDebugStats.beginFrame(enabled: true);
    pointerRouter.beginFrame();
    _back.withoutDamageTracking(_back.clear);
    var paint = Duration.zero;
    owner.renderFrame(root, _back, onPhaseTiming: (b, l, p) => paint = p);
    _renderer.renderDiff(_front, _back, _sink);
    final stats = RepaintBoundaryDebugStats.takeFrameStats();
    lastPaintUs = paint.inMicroseconds;
    binding.flushPostFrameCallbacks(clock.now);
    final tmp = _front;
    _front = _back;
    _back = tmp;
    return stats;
  }

  void dispose() {
    RepaintBoundaryDebugStats.beginFrame(enabled: false);
    binding.dispose();
    focusManager.dispose();
  }
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

typedef _Signature = ({
  int boundaries,
  int repainted,
  int cached,
  int empty,
  int copiedCells,
});

const _Signature _zeroSignature = (
  boundaries: 0,
  repainted: 0,
  cached: 0,
  empty: 0,
  copiedCells: 0,
);

_Signature _sig(RepaintBoundaryFrameStats s) => (
  boundaries: s.boundaryCount,
  repainted: s.repaintedCount,
  cached: s.cachedCount,
  empty: s.emptyCount,
  copiedCells: s.copiedCellCount,
);

String _fmt(_Signature s) =>
    'boundaries=${s.boundaries} repainted=${s.repainted} cached=${s.cached} '
    'empty=${s.empty} copiedCells=${s.copiedCells}';

/// One gated (or informational) measurement: a scenario phase whose every
/// frame produced [signature].
final class _Check {
  _Check({
    required this.scenario,
    required this.phase,
    required this.signature,
    required this.paintUsMean,
    required this.frames,
    this.gated = true,
  });

  final String scenario;
  final String phase;
  final _Signature signature;
  final double paintUsMean;
  final int frames;

  /// False for informational checks (S5): counters are reported and
  /// baselined but drift warns instead of failing.
  final bool gated;

  String get id => '$scenario/$phase';
}

final class _GateFailure implements Exception {
  _GateFailure(this.message);
  final String message;
}

/// Structural invariant: a relation that must hold regardless of baseline —
/// it fails even under --update-baseline, so a broken shape cannot be
/// locked in.
void _require(String id, bool condition, String expectation) {
  if (condition) return;
  throw _GateFailure('paint gate: [$id] invariant violated — $expectation');
}

/// Runs [count] frames, calling [perFrame] before each, and requires every
/// frame to produce the SAME counter signature — steady-state is asserted,
/// not assumed. Returns the signature and the mean paint-phase µs.
(_Signature, double) _measureWindow(
  _Host host,
  int count,
  void Function(int frame) perFrame, {
  required String id,
}) {
  _Signature? sig;
  var usTotal = 0;
  for (var i = 0; i < count; i++) {
    perFrame(i);
    final s = _sig(host.frame());
    usTotal += host.lastPaintUs;
    if (sig == null) {
      sig = s;
    } else if (s != sig) {
      throw _GateFailure(
        'paint gate: [$id] steady-state broke at frame $i of the measured '
        'window: ${_fmt(s)} != first frame ${_fmt(sig)}. The scenario is not '
        'reaching a stable signature — fix the fixture (or the framework '
        'regression it exposed); do not paper over with tolerance.',
      );
    }
  }
  return (sig!, usTotal / count);
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

/// S1: one visible row's model bumps per frame; the REAL ListView's per-item
/// auto-boundaries must prune the paint walk to exactly that row.
List<_Check> _runListLocalized(int frames, int warmup) {
  final models = [for (var i = 0; i < _listItemCount; i++) _Model()];
  final host = _Host(
    ListView.builder(
      itemCount: models.length,
      itemBuilder: (context, index, selected) => _listRow(index, models[index]),
    ),
  );
  try {
    // Cycle bumps across the MOUNTED window only: the lazy list mounts
    // exactly the viewport's rows (anchor 0, one-line items), and bumping an
    // unmounted row's notifier reaches no listener — that frame would show
    // repainted=0 and (deliberately) trip the stability assert.
    var next = 0;
    void bumpOne(int _) {
      models[next].bump();
      next = (next + 1) % _rows;
    }

    for (var i = 0; i < warmup; i++) {
      bumpOne(i);
      host.frame();
    }
    final (sig, us) = _measureWindow(
      host,
      frames,
      bumpOne,
      id: 'list-localized/steady',
    );
    _require(
      'list-localized/steady',
      sig.boundaries == _rows,
      'the lazy list should mount one boundary per visible row '
      '($_rows), got ${sig.boundaries} — auto-boundaries missing or the '
      'mount window changed',
    );
    _require(
      'list-localized/steady',
      sig.repainted == 1 && sig.cached == sig.boundaries - 1,
      'a localized update must repaint exactly 1 boundary and cache-blit '
      'the rest, got ${_fmt(sig)}',
    );
    return [
      _Check(
        scenario: 'list-localized',
        phase: 'steady',
        signature: sig,
        paintUsMean: us,
        frames: frames,
      ),
    ];
  } finally {
    host.dispose();
  }
}

/// S2: two-entry overlay, only the floater churns; the static base entry
/// must blit from cache instead of re-walking its paint.
List<_Check> _runOverlayChurn(int frames, int warmup) {
  final floater = _Model();
  final host = _Host(
    Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => _staticDashboard()),
        OverlayEntry(builder: (_) => _floaterBox(floater)),
      ],
    ),
  );
  try {
    void bump(int _) => floater.bump();
    for (var i = 0; i < warmup; i++) {
      bump(i);
      host.frame();
    }
    final (sig, us) = _measureWindow(
      host,
      frames,
      bump,
      id: 'overlay-churn/steady',
    );
    _require(
      'overlay-churn/steady',
      sig.boundaries == 2 && sig.repainted == 1 && sig.cached == 1,
      'with two visible entries and only the floater dirty, the floater '
      'repaints and the base blits (2/1/1), got ${_fmt(sig)}',
    );
    return [
      _Check(
        scenario: 'overlay-churn',
        phase: 'steady',
        signature: sig,
        paintUsMean: us,
        frames: frames,
      ),
    ];
  } finally {
    host.dispose();
  }
}

/// S3: the lazy-layer guardrail. Idle app (Toaster mounted, zero toasts)
/// must be pure pass-through; a toast engages the boundaries; auto-dismiss
/// returns to pass-through.
Future<List<_Check>> _runOverlayIdleLazy(int frames, int warmup) async {
  const toastDuration = Duration(seconds: 2);
  final app = _Model();
  late BuildContext appContext;
  final host = _Host(
    Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => Toaster(
            duration: toastDuration,
            child: _ContextProbe(
              onContext: (c) => appContext = c,
              child: _churningDashboard(app),
            ),
          ),
        ),
      ],
    ),
  );
  try {
    void bump(int _) => app.bump();
    for (var i = 0; i < warmup; i++) {
      bump(i);
      host.frame();
    }

    // Idle: the app is dirty EVERY frame, and with a single visible entry
    // the overlay's boundaries must stay disengaged — no cache write, no
    // blit, no boundary at all.
    final (idleSig, idleUs) = _measureWindow(
      host,
      frames,
      bump,
      id: 'overlay-idle-lazy/idle',
    );
    _require(
      'overlay-idle-lazy/idle',
      idleSig == _zeroSignature,
      'an idle app must be PURE PASS-THROUGH (all counters 0 every frame). '
      'A permanently-mounted empty overlay entry (e.g. an eager toast/error '
      'layer) keeps the overlay multi-entry and re-engages per-entry '
      'boundaries, taxing every app-dirty frame with a full-screen cache '
      'write + blit. Got ${_fmt(idleSig)}',
    );

    // Enqueue a toast: the Toaster's lazily-mounted layer entry appears and
    // the overlay's adaptive boundaries engage on the next frame — one
    // warm-up repaint for both entries (the base's just-engaged boundary
    // cannot trust a cache it never wrote).
    Toaster.show(appContext, 'Saved — paint gate', duration: toastDuration);
    bump(0);
    final engageSig = _sig(host.frame());
    final engageUs = host.lastPaintUs.toDouble();
    _require(
      'overlay-idle-lazy/engage',
      engageSig.boundaries == 2 &&
          engageSig.repainted == 2 &&
          engageSig.cached == 0,
      'the engagement frame must arm both entry boundaries and repaint both '
      '(2/2/0), got ${_fmt(engageSig)}',
    );

    // Engaged steady state: the app churns (repaints); the toast blits.
    final (engagedSig, engagedUs) = _measureWindow(
      host,
      frames,
      bump,
      id: 'overlay-idle-lazy/engaged',
    );
    _require(
      'overlay-idle-lazy/engaged',
      engagedSig.boundaries == 2 &&
          engagedSig.repainted == 1 &&
          engagedSig.cached == 1,
      'while a toast shows, the dirty app repaints and the toast blits '
      '(2/1/1), got ${_fmt(engagedSig)}',
    );

    // Auto-dismiss: advance the fake scheduler past the toast duration; the
    // Toaster's FrameTicker fires synchronously, the queue empties, and the
    // layer entry unmounts. Drain microtasks (the deferred ticker disposal)
    // so nothing smears into the next measured window.
    host.scheduler.advance(toastDuration + host.scheduler.frameInterval);
    await Future<void>.delayed(Duration.zero);

    // Idle again: the overlay must return to pass-through immediately.
    final (idle2Sig, idle2Us) = _measureWindow(
      host,
      frames,
      bump,
      id: 'overlay-idle-lazy/idle-after',
    );
    _require(
      'overlay-idle-lazy/idle-after',
      idle2Sig == _zeroSignature,
      'after the last toast dismisses, the layer entry must unmount and the '
      'overlay return to pass-through (all counters 0). Got ${_fmt(idle2Sig)}',
    );

    return [
      _Check(
        scenario: 'overlay-idle-lazy',
        phase: 'idle',
        signature: idleSig,
        paintUsMean: idleUs,
        frames: frames,
      ),
      _Check(
        scenario: 'overlay-idle-lazy',
        phase: 'engage',
        signature: engageSig,
        paintUsMean: engageUs,
        frames: 1,
      ),
      _Check(
        scenario: 'overlay-idle-lazy',
        phase: 'engaged',
        signature: engagedSig,
        paintUsMean: engagedUs,
        frames: frames,
      ),
      _Check(
        scenario: 'overlay-idle-lazy',
        phase: 'idle-after',
        signature: idle2Sig,
        paintUsMean: idle2Us,
        frames: frames,
      ),
    ];
  } finally {
    host.dispose();
  }
}

/// S4: everything is dirty every frame — the staleness detector. A boundary
/// that cache-hits here is serving stale cells.
List<_Check> _runFullInvalidate(int frames, int warmup) {
  final models = [for (var i = 0; i < _listItemCount; i++) _Model()];
  final host = _Host(
    ListView.builder(
      itemCount: models.length,
      itemBuilder: (context, index, selected) => _listRow(index, models[index]),
    ),
  );
  try {
    void bumpAll(int _) {
      for (final m in models) {
        m.bump();
      }
    }

    for (var i = 0; i < warmup; i++) {
      bumpAll(i);
      host.frame();
    }
    final (sig, us) = _measureWindow(
      host,
      frames,
      bumpAll,
      id: 'full-invalidate/steady',
    );
    _require(
      'full-invalidate/steady',
      sig.boundaries > 1 &&
          sig.cached == 0 &&
          sig.repainted == sig.boundaries,
      'when every row is dirty, every boundary must repaint '
      '(cached==0, repainted==boundaries) — a cache hit here means stale '
      'cells are being served. Got ${_fmt(sig)}',
    );
    return [
      _Check(
        scenario: 'full-invalidate',
        phase: 'steady',
        signature: sig,
        paintUsMean: us,
        frames: frames,
      ),
    ];
  } finally {
    host.dispose();
  }
}

/// S5 (informational): base AND floater dirty every frame — the
/// autocomplete-while-typing shape. Both boundaries pay cache write + blit
/// on top of their paint; recorded so the known tax stays visible.
List<_Check> _runDropdownTyping(int frames, int warmup) {
  final base = _Model();
  final floater = _Model();
  final host = _Host(
    Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => _churningDashboard(base)),
        OverlayEntry(builder: (_) => _floaterBox(floater)),
      ],
    ),
  );
  try {
    void bumpBoth(int _) {
      base.bump();
      floater.bump();
    }

    for (var i = 0; i < warmup; i++) {
      bumpBoth(i);
      host.frame();
    }
    final (sig, us) = _measureWindow(
      host,
      frames,
      bumpBoth,
      id: 'dropdown-typing/steady',
    );
    return [
      _Check(
        scenario: 'dropdown-typing',
        phase: 'steady',
        signature: sig,
        paintUsMean: us,
        frames: frames,
        gated: false,
      ),
    ];
  } finally {
    host.dispose();
  }
}

// ---------------------------------------------------------------------------
// Baseline + gate
// ---------------------------------------------------------------------------

Map<String, Object?> _checkToJson(_Check c) => {
  'boundaries': c.signature.boundaries,
  'repainted': c.signature.repainted,
  'cached': c.signature.cached,
  'empty': c.signature.empty,
  'copiedCells': c.signature.copiedCells,
  'paintUsMean': double.parse(c.paintUsMean.toStringAsFixed(1)),
  'gated': c.gated,
};

_Signature _signatureFromJson(Map<String, Object?> json) => (
  boundaries: json['boundaries']! as int,
  repainted: json['repainted']! as int,
  cached: json['cached']! as int,
  empty: json['empty']! as int,
  copiedCells: json['copiedCells']! as int,
);

Future<void> main(List<String> args) async {
  var frames = _defaultFrames;
  var warmup = _defaultWarmup;
  var gate = false;
  var update = false;
  var baselinePath = 'paint_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (arg.startsWith('--frames=')) {
      frames = int.parse(arg.substring('--frames='.length));
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  final List<_Check> checks;
  try {
    checks = [
      ..._runListLocalized(frames, warmup),
      ..._runOverlayChurn(frames, warmup),
      ...await _runOverlayIdleLazy(frames, warmup),
      ..._runFullInvalidate(frames, warmup),
      ..._runDropdownTyping(frames, warmup),
    ];
  } on _GateFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'paint gate — repaint-boundary counter signatures '
    '(${_cols}x$_rows, $frames frames/window, warmup $warmup)',
  );
  for (final c in checks) {
    final tag = c.gated ? '' : '   (informational)';
    stdout.writeln('  ${c.id.padRight(28)} ${_fmt(c.signature)}$tag');
  }
  stdout.writeln('timings (paint µs/frame, warn-only):');
  for (final c in checks) {
    stdout.writeln(
      '  ${c.id.padRight(28)} ${c.paintUsMean.toStringAsFixed(1)}',
    );
  }

  if (update) {
    final json = const JsonEncoder.withIndent('  ').convert({
      'viewport': '${_cols}x$_rows',
      'frames': frames,
      'warmup': warmup,
      'checks': {for (final c in checks) c.id: _checkToJson(c)},
    });
    File(baselinePath).writeAsStringSync('$json\n');
    stdout.writeln(
      'paint gate: wrote baseline $baselinePath (${checks.length} checks).',
    );
    return;
  }

  if (!gate) return;

  final file = File(baselinePath);
  if (!file.existsSync()) {
    stderr.writeln(
      'paint gate: no baseline at $baselinePath — run with '
      '--update-baseline first.',
    );
    exitCode = 64;
    return;
  }
  final base = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final baseChecks = (base['checks']! as Map).cast<String, Object?>();

  var failed = false;
  final currentIds = {for (final c in checks) c.id};
  for (final id in baseChecks.keys) {
    if (!currentIds.contains(id)) {
      stderr.writeln(
        'paint gate: baseline check "$id" no longer produced — scenario '
        'renamed/removed? Re-baseline with --update-baseline.',
      );
      failed = true;
    }
  }

  for (final c in checks) {
    final entry = baseChecks[c.id];
    if (entry == null) {
      stderr.writeln(
        'paint gate: no baseline entry for "${c.id}" — new scenario/phase? '
        'Re-baseline with --update-baseline.',
      );
      failed = true;
      continue;
    }
    final baseline = (entry as Map).cast<String, Object?>();
    final baseSig = _signatureFromJson(baseline);
    final baseUs = (baseline['paintUsMean']! as num).toDouble();

    if (c.signature != baseSig) {
      final line =
          'paint gate: [${c.id}] counter signature drifted:\n'
          '  baseline ${_fmt(baseSig)}\n'
          '  current  ${_fmt(c.signature)}';
      if (c.gated) {
        stderr.writeln('$line\n  counters are exact (tolerance 0) — a drift '
            'is a behavior change. If intentional, re-baseline with '
            '--update-baseline in the same PR.');
        failed = true;
      } else {
        stdout.writeln('$line\n  (informational check — warn only)');
      }
    }

    final usDelta = baseUs == 0 ? 0.0 : (c.paintUsMean - baseUs) / baseUs;
    if (usDelta.abs() > _timingWarnFraction) {
      stdout.writeln(
        'paint gate: [${c.id}] paint µs ${c.paintUsMean.toStringAsFixed(1)} '
        'vs baseline ${baseUs.toStringAsFixed(1)} '
        '(${usDelta >= 0 ? '+' : ''}${(usDelta * 100).toStringAsFixed(0)}% '
        '— warn only, timings never fail this gate)',
      );
    }
  }

  if (failed) {
    stderr.writeln('paint gate: FAIL — counter drift or check-set mismatch '
        '(see above).');
    exitCode = 1;
    return;
  }
  stdout.writeln('paint gate: all counter signatures match baseline — pass.');
}
