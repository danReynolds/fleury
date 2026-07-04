// Per-frame allocation regression gate (G3).
//
// Drives a steady-state reactive scenario through the REAL per-frame path —
// build -> reconcile -> layout -> paint -> AnsiRenderer diff — for a fixed
// frame count, entirely in-process against a reused double-buffer (mirroring
// the runtime's front/back buffers in tui_frame_loop, so NO per-frame
// CellBuffer allocation pollutes the number). It samples the VM allocation
// profile before/after the measured window and sums the bytes allocated by
// `package:fleury` classes -> deterministic bytes/frame of project churn.
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
// MUST be launched with the VM service enabled so it can self-connect:
//   dart --enable-vm-service=0 --disable-service-auth-codes \
//     bin/alloc_gate.dart [--gate] [--update-baseline] [--frames=N] [--top=N]
//
// Exit codes: 0 pass, 1 regression, 64 usage/setup error.

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _defaultFrames = 400;
const _defaultWarmup = 300;

/// bytes/frame fails beyond this relative increase; a decrease should be locked
/// in with --update-baseline. Deterministic measurement, so this headroom is
/// for SDK / machine drift, not run noise.
const _failFraction = 0.10;

/// A steady-state metric model bumped once per frame.
class _Model extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

/// Dashboard-shaped tree: a static header + a watched block whose three
/// metric lines rebuild + repaint every frame. Exercises build, reconcile,
/// layout (widths shift as values grow), and paint — the churn-producing path.
Widget _scenario(_Model m) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Fleury alloc-gate dashboard'),
      const Text('────────────────────────────'),
      ListenableBuilder(
        listenable: m,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('requests : ${m.v}'),
            Text('errors   : ${m.v % 97}'),
            Text('rate/s   : ${(m.v * 7) % 1000}'),
          ],
        ),
      ),
    ],
  );
}

/// Discards output — the runtime's real sink writes to dart:io (excluded from
/// the package:fleury filter), so a null sink keeps the measurement to the
/// renderer's own churn and nothing else.
final class _NullAnsiSink implements AnsiSink {
  const _NullAnsiSink();
  @override
  void write(String data) {}
  @override
  Future<void> flush() async {}
}

/// Sums `package:fleury` accumulated allocation bytes over [work], and returns
/// the total plus the top classes by bytes (for the diagnostic breakdown).
Future<({int totalBytes, List<({String name, int bytes, int instances})> top})>
_measure(
  VmService service,
  String isolateId, {
  required void Function() work,
}) async {
  await service.getAllocationProfile(isolateId, gc: true, reset: true);
  work();
  final after = await service.getAllocationProfile(isolateId);
  var total = 0;
  final classes = <({String name, int bytes, int instances})>[];
  for (final m in after.members ?? const <ClassHeapStats>[]) {
    final uri = m.classRef?.library?.uri ?? '';
    if (!uri.startsWith('package:fleury')) continue;
    final bytes = m.accumulatedSize ?? 0;
    if (bytes == 0) continue;
    total += bytes;
    classes.add((
      name: m.classRef?.name ?? '?',
      bytes: bytes,
      instances: m.instancesAccumulated ?? 0,
    ));
  }
  classes.sort((a, b) => b.bytes.compareTo(a.bytes));
  return (totalBytes: total, top: classes);
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
    } else if (arg.startsWith('--frames=')) {
      frames = int.parse(arg.substring('--frames='.length));
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--top=')) {
      top = int.parse(arg.substring('--top='.length));
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
  final wsUri = server
      .replace(
        scheme: 'ws',
        pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
      )
      .toString();

  final service = await vmServiceConnectUri(wsUri);
  try {
    final vm = await service.getVM();
    final isolateId = vm.isolates!.first.id!;

    // Real per-frame path with reused double-buffers (front/back), like the
    // runtime. paint into `back`, diff against `front`, swap.
    const size = CellSize(80, 24);
    const renderer = AnsiRenderer();
    const sink = _NullAnsiSink();
    final owner = BuildOwner();
    final model = _Model();
    final root = owner.mountRoot(_scenario(model));
    var front = CellBuffer(size);
    var back = CellBuffer(size);

    void frame() {
      model.bump();
      back.withoutDamageTracking(back.clear);
      owner.renderFrame(root, back);
      renderer.renderDiff(front, back, sink);
      final tmp = front;
      front = back;
      back = tmp;
    }

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

    if (update) {
      final json = const JsonEncoder.withIndent('  ').convert({
        'bytesPerFrame': perFrame,
        'totalBytes': result.totalBytes,
        'frames': frames,
      });
      File(baselinePath).writeAsStringSync('$json\n');
      stdout.writeln('alloc gate: wrote baseline $baselinePath '
          '(${perFrame.toStringAsFixed(1)} B/frame over $frames frames).');
      return;
    }

    stdout.writeln('per-frame project (package:fleury) allocation churn:');
    stdout.writeln('  ${result.totalBytes} B over $frames frames = '
        '${perFrame.toStringAsFixed(1)} B/frame');
    stdout.writeln('  top $top allocating project classes (window):');
    for (final c in result.top.take(top)) {
      stdout.writeln('    ${c.bytes.toString().padLeft(9)} B  '
          '${c.instances.toString().padLeft(7)} inst  ${c.name}');
    }

    if (!gate) return;

    final file = File(baselinePath);
    if (!file.existsSync()) {
      stderr.writeln('alloc gate: no baseline at $baselinePath — run with '
          '--update-baseline first.');
      exitCode = 64;
      return;
    }
    final base = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final basePerFrame = (base['bytesPerFrame'] as num).toDouble();
    final limit = basePerFrame * (1 + _failFraction);
    final delta = (perFrame - basePerFrame) / basePerFrame * 100;
    final line = 'alloc gate: ${perFrame.toStringAsFixed(1)} B/frame vs '
        'baseline ${basePerFrame.toStringAsFixed(1)} '
        '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%, '
        'limit +${(_failFraction * 100).toStringAsFixed(0)}%)';
    if (perFrame <= limit) {
      stdout.writeln('$line — pass.');
      if (perFrame < basePerFrame * (1 - _failFraction)) {
        stdout.writeln('alloc gate: per-frame churn improved '
            '${delta.toStringAsFixed(1)}% below baseline — lock it in with '
            '--update-baseline so the ceiling drops and a later regression '
            "back up to today's baseline can't slip through.");
      }
    } else {
      stdout.writeln('$line — FAIL.');
      stderr.writeln('alloc gate: per-frame allocation churn regressed past '
          'tolerance. A new per-frame allocation in build/reconcile/layout/'
          'paint/diff? Inspect the top-classes breakdown above; if the change '
          'is intentional, re-baseline with --update-baseline.');
      exitCode = 1;
    }
  } finally {
    await service.dispose();
  }
}
