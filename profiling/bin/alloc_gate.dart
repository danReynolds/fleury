// Per-frame allocation regression gate (G3).
//
// Drives a steady-state reactive scenario through the REAL per-frame path —
// build -> reconcile -> layout -> paint -> AnsiRenderer diff — for a fixed
// frame count, entirely in-process against a reused double-buffer (mirroring
// the runtime's front/back buffers in tui_frame_loop, so NO per-frame
// CellBuffer allocation pollutes the number). It samples the VM allocation
// profile before/after the measured window -> deterministic bytes/frame.
//
// TWO axes, both gated:
//
//   total   every Dart-level class (any `dart:` or `package:` library). This is
//           the number the GC actually sees, and it is what a frame costs.
//   project `package:fleury` classes only — project-owned churn, isolated.
//
// The total axis exists because the project axis alone is nearly blind. A
// framework frame allocates mostly dart:core: lists, strings, and iterators
// created BY fleury code but BELONGING to dart:core, so they were invisible
// here. The three fixes this axis shipped with (a runes-iterator-free width
// scan, an allocation-free unkeyed semantic-anchor pre-scan, and cursor moves
// written without intermediate strings) moved this scenario 103667 -> 93764
// B/frame total (-9.6%) while moving the `package:fleury` axis -2.4% — well
// inside its tolerance, i.e. a gate watching only the project axis would have
// called all three nothing. On a border-heavy 120x40 dashboard, where box
// drawing makes the width path far hotter, the same fixes cut measured churn
// by ~34%.
//
// Excluded from both: classes with no library (VM-internal JIT artifacts —
// Code, Instructions, ICData, ObjectPool — plus closure Contexts, which are
// real churn but not separable from the JIT noise they share a bucket with),
// and `package:vm_service`, which is this gate's own profiler traffic.
//
// Steady-state per-frame churn is what RSS deltas hide and what GC pauses turn
// into dropped frames. It's the axis the encoder zero-image fast path (#30) and
// the reconcile redundant-copy cleanup (#35) both moved — and nothing gated it.
//
// The number is deterministic byte-for-byte on a fixed SDK, so a small
// tolerance catches a real per-frame allocation without flaking. The absolute
// baseline shifts with the Dart SDK (object layout / list growth) and the
// scenario; regenerate with --update-baseline after an intentional change or an
// SDK bump, exactly like the wire gate.
//
// MUST be launched with the VM service enabled so it can self-connect, AND
// with --deterministic: without it, the background JIT can land an
// allocation-sinking tier mid-window at a nondeterministic frame, collapsing
// the measured churn by ~25× on some runs (observed at --frames=800; the
// default window happened to be stable, but that's machine luck, not a
// guarantee). --deterministic pins compilation order and does not change the
// default-window number.
//   dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//     bin/alloc_gate.dart [--gate] [--update-baseline] [--frames=N] [--top=N]
//
// Exit codes: 0 pass, 1 regression, 64 usage/setup error.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'alloc_scenario.dart';
import 'gate_support.dart';

const _defaultFrames = 400;
const _defaultWarmup = 300;

/// Measurement windows per run; the reported number is their MEDIAN.
///
/// One window is not a stable estimate of the total axis: the gate's own
/// vm_service response decoding lands inside the window, and its volume varies,
/// producing occasional low outliers ~2% under the typical value. A single
/// window is therefore a coin flip for `--update-baseline` too — a baseline
/// written from a low outlier leaves almost no usable band, which is exactly
/// how a gate becomes flaky. A median over an odd number of windows discards
/// isolated outliers on both sides and costs a fraction of a second.
const _defaultRepeats = 5;

/// bytes/frame fails beyond this relative increase; a decrease should be locked
/// in with --update-baseline. Deterministic measurement, so this headroom is
/// for SDK / machine drift, not run noise.
const _failFraction = 0.10;

/// The total axis gets a tighter band than the project axis, because it is the
/// one that can actually see a dart:core regression and a wide band wastes it:
/// at the project axis's 10%, reverting either of the fixes this axis was built
/// for sails straight through (the width scan reads +4.6% total / +0.0%
/// project, the semantic-anchor pre-scan +5.3% / +2.5%).
///
/// 3% is calibrated, not guessed. With the double reset and the discarded
/// warm-up window (see [_measure] and the measurement loop), six consecutive
/// runs against a fresh baseline landed between -0.2% and 0.0% — no excursion
/// above it at all — while the regressions above sit at +4.6% and +5.3%.
///
/// Two honest caveats. The axis is NOT byte-exact the way the project axis is,
/// and it carries a roughly constant instrument offset: one profile-response
/// decode (~15 kB/frame at this window size) is allocated inside every measured
/// window and cannot be separated from the frame's own churn by class. That
/// offset inflates the absolute number and therefore DAMPS relative deltas by
/// ~15%. Read this axis as a regression detector against a baseline measured
/// the same way — not as the absolute cost of a frame.
const _totalFailFraction = 0.03;

/// Sums accumulated allocation bytes over [work] on both axes, and returns the
/// top classes by bytes (for the diagnostic breakdown).
Future<
    ({
      int totalBytes,
      int projectBytes,
      List<({String name, String library, int bytes, int instances})> top,
    })> _measure(
  VmService service,
  String isolateId, {
  required void Function() work,
}) async {
  // Reset TWICE. The RPC returns the profile accumulated so far and then
  // clears it, so the client-side JSON decode of that response is proportional
  // to what the previous window accumulated — and it lands inside THIS window.
  // With one reset the windows alternate by ~10% (a big response inflates the
  // window, whose small accumulation then deflates the next). The second reset
  // returns only what the first response's own decode allocated: small, and
  // near-constant regardless of history.
  await service.getAllocationProfile(isolateId, gc: true, reset: true);
  await service.getAllocationProfile(isolateId, reset: true);
  work();
  final after = await service.getAllocationProfile(isolateId);
  var total = 0;
  var project = 0;
  final classes = <({String name, String library, int bytes, int instances})>[];
  for (final m in after.members ?? const <ClassHeapStats>[]) {
    final uri = m.classRef?.library?.uri ?? '';
    // A class with no library is a VM-internal artifact (JIT code objects and
    // closure contexts); vm_service is this gate's own profiler traffic.
    // Neither is per-frame churn the framework controls.
    if (uri.isEmpty || uri.startsWith('package:vm_service')) continue;
    final bytes = m.accumulatedSize ?? 0;
    if (bytes == 0) continue;
    total += bytes;
    if (uri.startsWith('package:fleury')) project += bytes;
    classes.add((
      name: m.classRef?.name ?? '?',
      library: uri,
      bytes: bytes,
      instances: m.instancesAccumulated ?? 0,
    ));
  }
  classes.sort((a, b) => b.bytes.compareTo(a.bytes));
  return (totalBytes: total, projectBytes: project, top: classes);
}

/// Median of [values]; mutates nothing the caller can observe.
double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

Future<void> main(List<String> args) async {
  var frames = _defaultFrames;
  var warmup = _defaultWarmup;
  var top = 12;
  var repeats = _defaultRepeats;
  var gate = false;
  var update = false;
  var baselinePath = 'alloc_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (parseIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
    } else if (parseIntFlag(arg, 'top') case final v?) {
      top = v;
    } else if (parseIntFlag(arg, 'repeats') case final v?) {
      repeats = v;
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  final info = await developer.Service.getInfo();
  final server = info.serverUri;
  if (server == null) {
    stderr.writeln(
      'alloc_gate: no VM service. Launch with '
      '`dart --enable-vm-service=0 --disable-service-auth-codes '
      'bin/alloc_gate.dart ...` (fleury benchmark alloc-gate does this).',
    );
    exitCode = 64;
    return;
  }
  final wsUri = server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString();

  final service = await vmServiceConnectUri(wsUri);
  try {
    final vm = await service.getVM();
    final isolateId = vm.isolates!.first.id!;

    final owner = BuildOwner();
    final model = AllocModel();
    final root = owner.mountRoot(allocScenario(model));
    final frame = allocFrameDriver(owner: owner, model: model, root: root);

    for (var i = 0; i < warmup; i++) {
      frame();
    }

    final totals = <double>[];
    final projects = <double>[];
    // repeats + 1 windows: the first is discarded as measurement warm-up. It
    // runs consistently low (the isolate's first profiled window after the
    // frame warm-up), and keeping it widened the spread from ~2% to ~7%.
    var result = await _measure(service, isolateId, work: () {});
    for (var round = 0; round <= repeats; round++) {
      final window = await _measure(
        service,
        isolateId,
        work: () {
          for (var i = 0; i < frames; i++) {
            frame();
          }
        },
      );
      if (round == 0) continue;
      totals.add(window.totalBytes / frames);
      projects.add(window.projectBytes / frames);
      // Keep one window's breakdown: the class ranking is stable, and a single
      // window's instance counts are easier to reason about than a sum.
      if (round == 1) result = window;
    }
    final perFrame = _median(totals);
    final projectPerFrame = _median(projects);

    if (update) {
      writeBaselineJson(baselinePath, {
        'bytesPerFrame': perFrame,
        'projectBytesPerFrame': projectPerFrame,
        'frames': frames,
        'windows': repeats,
      });
      stdout.writeln('alloc gate: wrote baseline $baselinePath '
          '(${perFrame.toStringAsFixed(1)} B/frame total, '
          '${projectPerFrame.toStringAsFixed(1)} B/frame project, '
          'over $frames frames).');
      return;
    }

    final spread = totals.isEmpty
        ? 0.0
        : (totals.reduce((a, b) => a > b ? a : b) -
                totals.reduce((a, b) => a < b ? a : b)) /
            perFrame *
            100;
    stdout.writeln('per-frame allocation churn over $frames frames '
        '(median of $repeats windows, spread '
        '${spread.toStringAsFixed(2)}%):');
    stdout.writeln('  total   ${perFrame.toStringAsFixed(1)} B/frame');
    stdout.writeln('  project ${projectPerFrame.toStringAsFixed(1)} B/frame '
        '(${(projectPerFrame * 100 / perFrame).toStringAsFixed(1)}% of total)');
    stdout.writeln('  top $top allocating classes (window):');
    for (final c in result.top.take(top)) {
      final lib = c.library.startsWith('package:fleury/src/')
          ? 'f:${c.library.substring('package:fleury/src/'.length)}'
          : c.library;
      stdout.writeln('    ${c.bytes.toString().padLeft(9)} B  '
          '${c.instances.toString().padLeft(7)} inst  ${c.name}  [$lib]');
    }

    if (!gate) return;

    final base = readBaselineOrNull(baselinePath, gateName: 'alloc gate');
    if (base == null) {
      exitCode = 64;
      return;
    }

    var failed = false;
    void check(
      String axis,
      double measured,
      num? baseline,
      double failFraction,
      String hint,
    ) {
      if (baseline == null) {
        stdout.writeln('alloc gate [$axis]: no baseline recorded — '
            're-baseline with --update-baseline.');
        failed = true;
        return;
      }
      final basePerFrame = baseline.toDouble();
      final limit = basePerFrame * (1 + failFraction);
      final delta = (measured - basePerFrame) / basePerFrame * 100;
      final line = 'alloc gate [$axis]: ${measured.toStringAsFixed(1)} B/frame '
          'vs baseline ${basePerFrame.toStringAsFixed(1)} '
          '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%, '
          'limit +${(failFraction * 100).toStringAsFixed(0)}%)';
      if (measured <= limit) {
        stdout.writeln('$line — pass.');
        if (measured < basePerFrame * (1 - failFraction)) {
          stdout.writeln('alloc gate [$axis]: per-frame churn improved '
              '${delta.toStringAsFixed(1)}% below baseline — lock it in with '
              '--update-baseline so the ceiling drops and a later regression '
              "back up to today's baseline can't slip through.");
        }
      } else {
        stdout.writeln('$line — FAIL.');
        stderr.writeln('alloc gate [$axis]: $hint');
        failed = true;
      }
    }

    check(
      'total',
      perFrame,
      base['bytesPerFrame'] as num?,
      _totalFailFraction,
      'total per-frame allocation churn regressed past tolerance. This axis '
          'counts every Dart-level allocation the frame makes, including the '
          'dart:core lists, strings and iterators that framework code creates '
          'but does not own — inspect the top-classes breakdown above for the '
          'call site. If the change is intentional, re-baseline with '
          '--update-baseline.',
    );
    check(
      'project',
      projectPerFrame,
      base['projectBytesPerFrame'] as num?,
      _failFraction,
      'package:fleury per-frame allocation churn regressed past tolerance. A '
          'new per-frame allocation in build/reconcile/layout/paint/diff? '
          'Inspect the top-classes breakdown above; if the change is '
          'intentional, re-baseline with --update-baseline.',
    );
    if (failed) exitCode = 1;
  } finally {
    await service.dispose();
  }
}
