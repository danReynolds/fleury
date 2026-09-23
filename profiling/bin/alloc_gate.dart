// Per-frame allocation regression gate (G3).
//
// Drives a steady-state reactive scenario through the REAL per-frame path —
// build -> reconcile -> layout -> paint -> AnsiRenderer diff — for a fixed
// frame count, entirely in-process against a reused double-buffer (mirroring
// the runtime's front/back buffers in tui_frame_loop, so NO per-frame
// CellBuffer allocation pollutes the number). It samples the VM allocation
// profile before/after the measured window -> bytes/frame on a fixed workload.
//
// Two measured axes:
//   total   allocation bytes for classes with a Dart library, except vm_service;
//   project allocation bytes for package:fleury classes only.
//
// Core Dart lists, strings, and iterators belong to dart:core even when the
// framework creates them. The total axis includes them; the project axis does
// not. Neither is a complete heap accounting: VM-internal classes and closure
// contexts without library metadata are excluded. Core objects allocated while
// decoding profiler responses remain in the total and add measurement noise.
//
// Steady-state per-frame churn is what RSS deltas hide and what GC pauses turn
// into dropped frames. It's the axis the encoder zero-image fast path (#30) and
// the reconcile redundant-copy cleanup (#35) both moved — and nothing gated it.
//
// The project axis is stable on a fixed SDK; the total includes bounded
// profiler overhead. Separate tolerances catch allocation regressions. The
// absolute baseline shifts with the Dart SDK (object layout / list growth) and the
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

/// bytes/frame fails beyond this relative increase; a decrease should be locked
/// in with --update-baseline. Deterministic measurement, so this headroom is
/// for SDK / machine drift, not run noise.
const _failFraction = 0.10;

/// Includes core objects allocated by profiler response decoding as well as
/// the frame. A 5% band allows bounded sampling noise on the pinned SDK; refresh
/// the baseline after an intentional workload or SDK change.
const _totalFailFraction = 0.05;

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
  await service.getAllocationProfile(isolateId, gc: true, reset: true);
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
    if (bytes <= 0) continue;
    total += bytes;
    if (uri.startsWith('package:fleury/')) project += bytes;
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

Future<void> main(List<String> args) async {
  var frames = _defaultFrames;
  var warmup = _defaultWarmup;
  var top = 12;
  var gate = false;
  var update = false;
  var baselinePath = 'alloc_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (parsePositiveIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
    } else if (parseIntFlag(arg, 'top') case final v?) {
      top = v;
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  if (warmup < 0 || top < 0) {
    stderr.writeln('--warmup and --top must be nonnegative');
    exitCode = 64;
    return;
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

    final result = await _measure(
      service,
      isolateId,
      work: () {
        for (var i = 0; i < frames; i++) {
          frame();
        }
      },
    );
    final perFrame = result.totalBytes / frames;
    final projectPerFrame = result.projectBytes / frames;

    if (update) {
      writeBaselineJson(baselinePath, {
        'bytesPerFrame': perFrame,
        'projectBytesPerFrame': projectPerFrame,
        'totalBytes': result.totalBytes,
        'projectBytes': result.projectBytes,
        'frames': frames,
      });
      stdout.writeln('alloc gate: wrote baseline $baselinePath '
          '(${perFrame.toStringAsFixed(1)} B/frame total, '
          '${projectPerFrame.toStringAsFixed(1)} B/frame project, '
          'over $frames frames).');
      return;
    }

    stdout.writeln('per-frame allocation churn over $frames frames:');
    stdout.writeln('  total   ${perFrame.toStringAsFixed(1)} B/frame '
        '(${result.totalBytes} B)');
    stdout.writeln('  project ${projectPerFrame.toStringAsFixed(1)} B/frame '
        '(${result.projectBytes} B, '
        '${(result.projectBytes * 100 / result.totalBytes).toStringAsFixed(1)}%'
        ' of total)');
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
      'measured Dart allocation churn regressed past tolerance. This includes the '
          'dart:core lists, strings and iterators that framework code creates '
          'but does not own — inspect the top-classes breakdown above for the '
          'classes, then use alloc-trace to locate call sites. If the change is '
          'intentional, re-baseline with '
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
