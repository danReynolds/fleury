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
// counter drift. The counters are pure functions of fixture state, so the
// windows are short: every measured frame must repeat the window's
// signature (the stability assert is the safety net, not frame count).
//
// Paint-phase µs is recorded and baselined WARN-ONLY (the wire gate's
// precedent for timing axes) — and it is measured with the boundary debug
// stats ENABLED, so it is debug-inflated non-uniformly with boundaryCount:
// useful for spotting gross drift, NEVER to be promoted to a gating axis
// as-is (baseline key: paintUsDebugStats).
//
// The frame loop is renderFrame into one reused, cleared buffer — no ANSI
// diff: the counters are collected inside renderFrame's paint pass, and the
// diff contributes nothing to any gated or reported axis (the probe keeps
// the full diff loop; it measures the paint phase in situ).
//
// Fixture honesty: S1/S4 drive the REAL ListView.builder; S3 genuinely
// mounts the real fleury_widgets Toaster inside an app-like overlay; S2/S5
// are real leaf widgets in bespoke scaffolding (a hand-built two-entry
// Overlay), shaped like a dashboard + floater rather than taken from an app.
//
// Scenarios:
//
//   S1 list-localized     ListView.builder rows — the real widget, so its
//                         per-item auto-boundaries are what's measured. ONE
//                         row's own model bumps per frame: exactly one
//                         repaint, every other visible row cache-blits. The
//                         bump cycle covers the OBSERVED mounted window
//                         (read from the mount frame's boundary count), so
//                         the driver never bumps an unmounted row.
//   S2 overlay-churn      Two-entry Overlay: static full-screen base +
//                         churning non-opaque floater. The floater
//                         repaints; the base blits from cache instead of
//                         re-walking its paint.
//   S3 overlay-idle-lazy  THE GUARDRAIL for the lazy-layer convention: an
//                         Overlay whose only mounted entry is the app
//                         (wrapped in a real Toaster with zero toasts) must
//                         be PURE PASS-THROUGH while idle — boundaryCount
//                         == 0 on every frame. Mid-run a toast is enqueued
//                         (engagement must appear: boundaryCount 2) and
//                         auto-dismissed (pass-through must return): the
//                         full adaptive cycle in one scenario.
//   S4 full-invalidate    Every row changes every frame (same mounted
//                         fixture as S1, driver swapped): cachedCount must
//                         be 0 and repaintedCount == boundaryCount. A
//                         boundary that cache-hits while everything under
//                         it is dirty is serving STALE cells — the
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

import 'dart:io';

import 'package:fleury/fleury.dart';
// The repaint-boundary debug counters and fake clock/scheduler are
// deliberately published through the package-neutral test-support barrel.
// Profiling is a harness (publish_to: none), so a gate binary importing that
// support surface is intended reuse, not a leak into production.
import 'package:fleury/fleury_test_support.dart'
    show
        FakeClock,
        FakeTickerScheduler,
        RepaintBoundaryDebugStats,
        RepaintBoundaryFrameStats;
import 'package:fleury_widgets/fleury_widgets.dart' show Toaster;

import 'gate_support.dart';

const _cols = 80;
const _rows = 24;
const _size = CellSize(_cols, _rows);
const _viewportLabel = '${_cols}x$_rows';
const _listItemCount = 40; // more items than the viewport: pins lazy mount

/// Counters are pure functions of fixture state and every measured frame is
/// asserted identical, so a window needs only one full driver period (the
/// S1 bump cycle: the mounted-row count) plus margin — not statistics.
const _defaultFrames = 40;
const _defaultWarmup = 8;

/// S3's return-to-idle window: the disengage transition is proven by the
/// first post-dismiss frame (included in the window); a longer window would
/// just re-prove a constant.
const _idleAfterFrames = 10;

/// S4 re-warm after swapping S1's driver on the shared fixture: the all-dirty
/// signature holds from the first bumpAll frame; this is margin only.
const _fullInvalidateRewarm = 4;

/// Timing axes warn beyond this relative change, never fail (paint µs is
/// machine-dependent and debug-stats-inflated; the counters are the gate).
const _timingWarnFraction = 0.5;

// ---------------------------------------------------------------------------
// Fixture widgets (row shape shared with the probe via gate_support.dart)
// ---------------------------------------------------------------------------

/// A static full-screen dashboard: full-width styled rows that never
/// rebuild. The overlay base entry for S2.
Widget _staticDashboard() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var i = 0; i < _rows; i++) styledRow(index: i, tick: 0, cols: _cols),
  ],
);

/// A dashboard whose EVERY row carries the model's tick — one bump dirties
/// the whole subtree (the app-dirty frame S3's convention protects).
Widget _churningDashboard(RowModel model) => ListenableBuilder(
  listenable: model,
  builder: (context, _) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < _rows; i++)
        styledRow(index: i, tick: model.v, cols: _cols),
    ],
  ),
);

/// A small churning floater box, bottom-right — a toast/dropdown stand-in
/// with a fixed footprint (3 rows × 24 cols) so its damage bounds are exact.
Widget _floaterBox(RowModel model) => Align(
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
// Host: ambient scopes + frame loop
// ---------------------------------------------------------------------------

/// Mounts a scene under the ambient scopes the widget tests install (see
/// [wrapWithAmbientScopes]) and drives frames: renderFrame into one reused
/// cleared buffer, with the boundary debug stats armed around each frame.
/// Time is a FakeClock: it moves only when a scenario advances it, so
/// ticker-driven behavior (the toast auto-dismiss) lands on an exact frame.
final class _Host {
  _Host(Widget scene) {
    binding = TuiBinding(tickerScheduler: scheduler);
    root = owner.mountRoot(
      wrapWithAmbientScopes(
        scene: scene,
        binding: binding,
        focusManager: focusManager,
        pointerRouter: pointerRouter,
        size: _size,
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

  final CellBuffer _buffer = CellBuffer(_size);

  /// Renders one frame and returns its boundary stats + paint-phase µs.
  /// The µs is measured with the debug stats enabled (see file header):
  /// warn-only material, never a gating axis.
  (RepaintBoundaryFrameStats, int) frame() {
    RepaintBoundaryDebugStats.beginFrame(enabled: true);
    pointerRouter.beginFrame();
    _buffer.withoutDamageTracking(_buffer.clear);
    var paint = Duration.zero;
    owner.renderFrame(root, _buffer, onPhaseTiming: (b, l, p) => paint = p);
    final stats = RepaintBoundaryDebugStats.takeFrameStats();
    binding.flushPostFrameCallbacks(clock.now);
    return (stats, paint.inMicroseconds);
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

/// One measurement: a scenario phase (id `scenario/phase`) whose every
/// measured frame produced [signature] over a [frames]-frame window.
final class _Check {
  _Check({
    required this.id,
    required this.signature,
    required this.paintUsDebugStats,
    required this.frames,
    this.gated = true,
  });

  final String id;
  final _Signature signature;

  /// Mean paint-phase µs over the window, measured with the boundary debug
  /// stats enabled — debug-inflated, warn-only, never a gating axis.
  final double paintUsDebugStats;

  /// The measured window size (1 for a transition frame).
  final int frames;

  /// False for informational checks (S5): counters are reported and
  /// baselined but drift warns instead of failing. Lives in code, not the
  /// baseline schema — a baseline edit cannot change a check's gating mode.
  final bool gated;
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
  throw _GateFailure(
    'paint gate: [$id] invariant violated — $expectation\n'
    '  Two possible causes: the gate fixture changed shape, or framework '
    'repaint behavior changed. Identify which; invariants cannot be '
    're-baselined away.',
  );
}

/// Runs [warmup] unmeasured frames, then [frames] measured frames — calling
/// [drive] before each — and requires every measured frame to produce the
/// SAME counter signature: steady-state is asserted, not assumed. Returns
/// the signature and the mean paint-phase µs.
(_Signature, double) _measureWindow(
  _Host host, {
  required String id,
  required int warmup,
  required int frames,
  required void Function(int frame) drive,
}) {
  for (var i = 0; i < warmup; i++) {
    drive(i);
    host.frame();
  }
  _Signature? sig;
  var usTotal = 0;
  for (var i = 0; i < frames; i++) {
    drive(i);
    final (stats, us) = host.frame();
    final s = _sig(stats);
    usTotal += us;
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
  return (sig!, usTotal / frames);
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

/// S1 + S4 on one mounted fixture (identical tree; only the driver differs,
/// and copiedCells is tick-invariant by the row padding design).
///
/// S1: one visible row's model bumps per frame; the real ListView's per-item
/// auto-boundaries must prune the paint walk to exactly that row.
/// S4: every row bumps every frame; every boundary must repaint — a cache
/// hit here means stale cells.
List<_Check> _runListScenarios(int frames, int warmup) {
  const idLocalized = 'list-localized/steady';
  const idFullInvalidate = 'full-invalidate/steady';
  final models = [for (var i = 0; i < _listItemCount; i++) RowModel()];
  final host = _Host(
    ListView.builder(
      itemCount: models.length,
      itemBuilder: (context, index, selected) =>
          liveRow(index: index, model: models[index], cols: _cols),
    ),
  );
  try {
    // Mount frame: everything paints once. OBSERVE how many item boundaries
    // the lazy list actually mounted and cycle the localized driver across
    // exactly that window — the driver must never bump an unmounted row
    // (no listener → a repainted=0 frame → the stability assert trips).
    // The baseline still pins the exact count: a real overscan/mount-window
    // change shows up there, visibly, rather than being silently absorbed.
    final (mountStats, _) = host.frame();
    final window = mountStats.boundaryCount;
    _require(
      idLocalized,
      window > 1,
      'expected the lazy ListView to mount multiple per-item boundaries on '
      'the mount frame (relation: boundaryCount > 1), got $window',
    );

    var next = 0;
    void bumpOne(int _) {
      models[next].bump();
      next = (next + 1) % window;
    }

    final (localizedSig, localizedUs) = _measureWindow(
      host,
      id: idLocalized,
      warmup: warmup,
      frames: frames,
      drive: bumpOne,
    );
    _require(
      idLocalized,
      localizedSig.boundaries == window,
      'steady-state boundary count should equal the mounted window observed '
      'at mount (relation: boundaries == $window), got '
      '${localizedSig.boundaries}',
    );
    _require(
      idLocalized,
      localizedSig.repainted == 1 &&
          localizedSig.cached == localizedSig.boundaries - 1,
      'a localized update must repaint exactly one boundary and cache-blit '
      'the rest (relation: repainted == 1 && cached == boundaries − 1), got '
      '${_fmt(localizedSig)}',
    );

    // S4 on the same fixture: swap the driver, short re-warm, everything
    // dirty every frame.
    void bumpAll(int _) {
      for (final m in models) {
        m.bump();
      }
    }

    final (fullSig, fullUs) = _measureWindow(
      host,
      id: idFullInvalidate,
      warmup: _fullInvalidateRewarm,
      frames: frames,
      drive: bumpAll,
    );
    _require(
      idFullInvalidate,
      fullSig.boundaries > 1 &&
          fullSig.cached == 0 &&
          fullSig.repainted == fullSig.boundaries,
      'when every row is dirty, every boundary must repaint (relation: '
      'cached == 0 && repainted == boundaries) — a cache hit here means '
      'stale cells are being served. Got ${_fmt(fullSig)}',
    );

    return [
      _Check(
        id: idLocalized,
        signature: localizedSig,
        paintUsDebugStats: localizedUs,
        frames: frames,
      ),
      _Check(
        id: idFullInvalidate,
        signature: fullSig,
        paintUsDebugStats: fullUs,
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
  const id = 'overlay-churn/steady';
  final floater = RowModel();
  final host = _Host(
    Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => _staticDashboard()),
        OverlayEntry(builder: (_) => _floaterBox(floater)),
      ],
    ),
  );
  try {
    final (sig, us) = _measureWindow(
      host,
      id: id,
      warmup: warmup,
      frames: frames,
      drive: (_) => floater.bump(),
    );
    _require(
      id,
      sig.boundaries == 2 && sig.repainted == 1 && sig.cached == 1,
      'with two visible entries and only the floater dirty, the floater '
      'repaints and the base blits (relation: boundaries == 2 && repainted '
      '== 1 && cached == 1), got ${_fmt(sig)}',
    );
    return [
      _Check(id: id, signature: sig, paintUsDebugStats: us, frames: frames),
    ];
  } finally {
    host.dispose();
  }
}

/// S3: the lazy-layer guardrail. Idle app (real Toaster mounted, zero
/// toasts) must be pure pass-through; a toast engages the boundaries;
/// auto-dismiss returns to pass-through.
///
/// CONTRACT: if a Toaster refactor makes it mount its layer entry eagerly,
/// this scenario turning red is the guardrail WORKING — the lazy-layer
/// convention is the thing under test, not an incidental fixture detail.
/// The auto-dismiss is driven through the binding's tickerScheduler (a
/// FakeTickerScheduler advanced past the toast duration); if Toaster's
/// dismiss clock source ever changes, this drive must change with it.
Future<List<_Check>> _runOverlayIdleLazy(int frames, int warmup) async {
  const idIdle = 'overlay-idle-lazy/idle';
  const idEngage = 'overlay-idle-lazy/engage';
  const idEngaged = 'overlay-idle-lazy/engaged';
  const idIdleAfter = 'overlay-idle-lazy/idle-after';
  const toastDuration = Duration(seconds: 2);
  final app = RowModel();
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

    // Idle: the app is dirty EVERY frame, and with a single visible entry
    // the overlay's boundaries must stay disengaged — no cache write, no
    // blit, no boundary at all.
    final (idleSig, idleUs) = _measureWindow(
      host,
      id: idIdle,
      warmup: warmup,
      frames: frames,
      drive: bump,
    );
    _require(
      idIdle,
      idleSig == _zeroSignature,
      'an idle app must be PURE PASS-THROUGH (relation: every counter == 0 '
      'on every frame). A permanently-mounted empty overlay entry (e.g. an '
      'eager toast/error layer) keeps the overlay multi-entry and re-engages '
      'per-entry boundaries, taxing every app-dirty frame with a full-screen '
      'cache write + blit. Got ${_fmt(idleSig)}',
    );

    // Enqueue a toast: the Toaster's lazily-mounted layer entry appears and
    // the overlay's adaptive boundaries engage on the next frame — one
    // warm-up repaint for both entries (the base's just-engaged boundary
    // cannot trust a cache it never wrote).
    Toaster.show(appContext, 'Saved — paint gate', duration: toastDuration);
    bump(0);
    final (engageStats, engageUs) = host.frame();
    final engageSig = _sig(engageStats);
    _require(
      idEngage,
      engageSig.boundaries == 2 &&
          engageSig.repainted == 2 &&
          engageSig.cached == 0,
      'the engagement frame must arm both entry boundaries and repaint both '
      '(relation: boundaries == 2 && repainted == 2 && cached == 0), got '
      '${_fmt(engageSig)}',
    );

    // Engaged steady state: the app churns (repaints); the toast blits.
    // No extra warm-up: the engage frame above IS the boundary warm-up.
    final (engagedSig, engagedUs) = _measureWindow(
      host,
      id: idEngaged,
      warmup: 0,
      frames: frames,
      drive: bump,
    );
    _require(
      idEngaged,
      engagedSig.boundaries == 2 &&
          engagedSig.repainted == 1 &&
          engagedSig.cached == 1,
      'while a toast shows, the dirty app repaints and the toast blits '
      '(relation: boundaries == 2 && repainted == 1 && cached == 1), got '
      '${_fmt(engagedSig)}',
    );

    // Auto-dismiss: advance the fake scheduler past the toast duration; the
    // Toaster's FrameTicker fires synchronously, the queue empties, and the
    // layer entry unmounts. Drain microtasks (the deferred ticker disposal)
    // so nothing smears into the next measured window.
    host.scheduler.advance(toastDuration + host.scheduler.frameInterval);
    await Future<void>.delayed(Duration.zero);

    // Idle again. The window's FIRST frame is the disengage transition
    // itself — pass-through must return immediately, so the whole short
    // window (transition included) asserts all-zero.
    final (idleAfterSig, idleAfterUs) = _measureWindow(
      host,
      id: idIdleAfter,
      warmup: 0,
      frames: _idleAfterFrames,
      drive: bump,
    );
    _require(
      idIdleAfter,
      idleAfterSig == _zeroSignature,
      'after the last toast dismisses, the layer entry must unmount and the '
      'overlay return to pass-through from the very next frame (relation: '
      'every counter == 0). Got ${_fmt(idleAfterSig)}',
    );

    return [
      _Check(
        id: idIdle,
        signature: idleSig,
        paintUsDebugStats: idleUs,
        frames: frames,
      ),
      _Check(
        id: idEngage,
        signature: engageSig,
        paintUsDebugStats: engageUs.toDouble(),
        frames: 1,
      ),
      _Check(
        id: idEngaged,
        signature: engagedSig,
        paintUsDebugStats: engagedUs,
        frames: frames,
      ),
      _Check(
        id: idIdleAfter,
        signature: idleAfterSig,
        paintUsDebugStats: idleAfterUs,
        frames: _idleAfterFrames,
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
  const id = 'dropdown-typing/steady';
  final base = RowModel();
  final floater = RowModel();
  final host = _Host(
    Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => _churningDashboard(base)),
        OverlayEntry(builder: (_) => _floaterBox(floater)),
      ],
    ),
  );
  try {
    final (sig, us) = _measureWindow(
      host,
      id: id,
      warmup: warmup,
      frames: frames,
      drive: (_) {
        base.bump();
        floater.bump();
      },
    );
    return [
      _Check(
        id: id,
        signature: sig,
        paintUsDebugStats: us,
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

// Baseline schema note: counters + paintUsDebugStats + the window size per
// check. A check's gating mode (exact vs informational) deliberately lives
// in code, NOT here — editing the baseline cannot change what gates.
Map<String, Object?> _checkToJson(_Check c) => {
  'boundaries': c.signature.boundaries,
  'repainted': c.signature.repainted,
  'cached': c.signature.cached,
  'empty': c.signature.empty,
  'copiedCells': c.signature.copiedCells,
  'paintUsDebugStats': double.parse(c.paintUsDebugStats.toStringAsFixed(1)),
  'frames': c.frames,
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
    } else if (parseIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
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
      ..._runListScenarios(frames, warmup),
      ..._runOverlayChurn(frames, warmup),
      ...await _runOverlayIdleLazy(frames, warmup),
      ..._runDropdownTyping(frames, warmup),
    ];
  } on _GateFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'paint gate — repaint-boundary counter signatures '
    '($_viewportLabel, $frames frames/window, warmup $warmup)',
  );
  for (final c in checks) {
    final tag = c.gated ? '' : '   (informational)';
    stdout.writeln('  ${c.id.padRight(28)} ${_fmt(c.signature)}$tag');
  }
  stdout.writeln(
    'timings (paint-phase µs/frame, warn-only; measured with debug stats '
    'ENABLED — inflated with boundaryCount, never a gating axis):',
  );
  for (final c in checks) {
    stdout.writeln(
      '  ${c.id.padRight(28)} '
      '${c.paintUsDebugStats.toStringAsFixed(1)}  (n=${c.frames})',
    );
  }

  if (update) {
    writeBaselineJson(baselinePath, {
      'viewport': _viewportLabel,
      'frames': frames,
      'warmup': warmup,
      'checks': {for (final c in checks) c.id: _checkToJson(c)},
    });
    stdout.writeln(
      'paint gate: wrote baseline $baselinePath (${checks.length} checks).',
    );
    return;
  }

  if (!gate) return;

  final base = readBaselineOrNull(baselinePath, gateName: 'paint gate');
  if (base == null) {
    exitCode = 64;
    return;
  }

  var failed = false;

  // Metadata: the counters are functions of the fixture geometry, so a
  // viewport mismatch makes every comparison meaningless — fail. Window
  // sizes only affect µs comparability — warn.
  final baseViewport = base['viewport'] as String?;
  if (baseViewport != _viewportLabel) {
    stderr.writeln(
      'paint gate: baseline viewport $baseViewport != current '
      '$_viewportLabel — counters are not comparable across fixture '
      'geometry. Re-baseline with --update-baseline.',
    );
    failed = true;
  }
  final baseFrames = base['frames'] as int?;
  final baseWarmup = base['warmup'] as int?;
  if (baseFrames != frames || baseWarmup != warmup) {
    stdout.writeln(
      'paint gate: window mismatch vs baseline (frames $frames vs '
      '$baseFrames, warmup $warmup vs $baseWarmup) — counters are '
      'window-invariant so the gate still applies; µs comparability is '
      'reduced (warn only).',
    );
  }

  final baseChecks = (base['checks']! as Map).cast<String, Object?>();
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
    final baseUs = (baseline['paintUsDebugStats']! as num).toDouble();

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

    final usDelta = baseUs == 0
        ? 0.0
        : (c.paintUsDebugStats - baseUs) / baseUs;
    if (usDelta.abs() > _timingWarnFraction) {
      stdout.writeln(
        'paint gate: [${c.id}] paint µs (debug-stats) '
        '${c.paintUsDebugStats.toStringAsFixed(1)} vs baseline '
        '${baseUs.toStringAsFixed(1)} '
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
