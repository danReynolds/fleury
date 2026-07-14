// Serve-semantics CPU/allocation regression gate.
//
// The wire is O(changed) (serve_semantics_profile.dart gates that). This gates
// the OTHER axis the wire diff hides: the per-frame CPU/allocation to PRODUCE
// that diff on the server. Every semantically-dirty frame the serve presenter
// builds a full redacted `SemanticInspectionSnapshot` from the tree
// (`SemanticInspectionSnapshot.fromTree` → one redacted node allocated + every
// string field sanitized, for EVERY node) and only then does the encoder ship
// the O(changed) patch. So an O(changed) wire rides on an O(tree) allocation.
//
// serve_semantics_profile.dart's `_cpu()` block deliberately builds the
// snapshot OUTSIDE its stopwatch, so that cost was unmeasured — a genuine blind
// spot. This drives the REAL production path (snapshot build + encode) for a
// realistic large tree with a small per-frame change, and sums the
// `package:fleury` bytes allocated per frame via the VM allocation profile —
// deterministic byte-for-byte, exactly like alloc_gate.dart. A regression here
// (or a revert of the on-demand-redaction fix back to full `fromTree`) shows up
// as a per-frame allocation jump.
//
// Launch (mirrors alloc-gate) so the gate can self-connect for the profile:
//   dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//     bin/serve_semantics_alloc_gate.dart [--gate] [--update-baseline] \
//     [--frames=N] [--warmup=N] [--messages=N]
//
// Exit codes: 0 pass, 1 regression, 64 usage/setup error.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'gate_support.dart';

const _defaultFrames = 400;
const _defaultWarmup = 300;
const _defaultMessages = 120; // ~250 nodes — a realistic large served tree.

/// bytes/frame fails beyond this relative increase; a decrease should be locked
/// in with --update-baseline. Deterministic measurement (same VM harness as
/// alloc_gate), so this headroom is for SDK / machine drift, not run noise.
const _failFraction = 0.10;

/// A realistic agent-style semantic tree (mirrors serve_semantics_profile.dart):
/// a status line, a [messages]-item list, and an input field. Only the status
/// counter and the last message body change with [tick] — the common
/// live-updating case where everything else is identical frame-to-frame.
///
/// The tick is taken modulo 1000 and zero-padded to a FIXED three digits, so
/// every changed label is byte-width-stable across any warmup/frames window:
/// the nodes still change every frame (so the encoder actually redacts them),
/// but their serialized size — and thus the allocation — cannot drift as the
/// counter grows. Distinct for up to 1000 consecutive frames.
SemanticTree _appTree({required int messages, required int tick}) {
  final t = (tick % 1000).toString().padLeft(3, '0');
  return SemanticTree(
    root: SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      children: [
        SemanticNode(
          id: const SemanticNodeId('status'),
          role: SemanticRole.status,
          label: 'streaming — $t tokens',
        ),
        SemanticNode(
          id: const SemanticNodeId('messages'),
          role: SemanticRole.messageList,
          children: [
            for (var m = 0; m < messages; m++)
              SemanticNode(
                id: SemanticNodeId('msg:$m'),
                role: SemanticRole.message,
                label: m == messages - 1
                    ? 'assistant: thinking about step $t of the plan'
                    : 'turn $m: a settled message line of moderate length',
                state: SemanticState(
                  {'index': m, 'author': m.isEven ? 'user' : 'assistant'},
                ),
              ),
          ],
        ),
        SemanticNode(
          id: const SemanticNodeId('input'),
          role: SemanticRole.textField,
          label: 'Message',
          value: '',
          actions: const {SemanticAction.submit},
        ),
      ],
    ),
  );
}

/// The owner's per-frame diff, mapped to the wire's changed-set. Computed
/// OUTSIDE the measured window — this is the pipeline's job, not the
/// presenter's, so it must not pollute the present-cost number. Ids here are
/// sanitize-safe, so raw `id.value` equals the wire id (same shortcut as the
/// sibling serve_semantics_profile.dart).
SemanticWireDelta _delta(SemanticsOwner owner, SemanticTree tree) {
  final update = owner.update(tree);
  return SemanticWireDelta(
    changed: {
      for (final id in update.added) id.value,
      for (final id in update.updated) id.value,
    },
    removed: {for (final id in update.removed) id.value},
  );
}

/// Sums `package:fleury` accumulated allocation bytes over [work] (identical
/// technique to alloc_gate.dart), returning the total plus the top classes by
/// bytes for the diagnostic breakdown.
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
  var messages = _defaultMessages;
  var top = 12;
  var gate = false;
  var update = false;
  var baselinePath = 'serve_semantics_alloc_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (parseIntFlag(arg, 'frames') case final v?) {
      frames = v;
    } else if (parseIntFlag(arg, 'warmup') case final v?) {
      warmup = v;
    } else if (parseIntFlag(arg, 'messages') case final v?) {
      messages = v;
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

  final info = await developer.Service.getInfo();
  final server = info.serverUri;
  if (server == null) {
    stderr.writeln(
      'serve_semantics_alloc_gate: no VM service. Launch with '
      '`dart --enable-vm-service=0 --disable-service-auth-codes '
      'bin/serve_semantics_alloc_gate.dart ...` (fleury benchmark '
      'serve-semantics-alloc does this).',
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

    // One encoder + one owner per "peer", primed with the first (full) frame so
    // the measured window is pure steady-state patch production.
    final encoder = SemanticsWireEncoder();
    final owner = SemanticsOwner();
    final nodeCount =
        _appTree(messages: messages, tick: 0).toInspectionSnapshot().nodeCount;
    {
      final tree0 = _appTree(messages: messages, tick: 0);
      encoder.encode(tree0.toInspectionSnapshot(), delta: _delta(owner, tree0));
    }

    // One steady-state present: build the redacted snapshot from the tree and
    // encode the O(changed) patch — exactly what WireSemanticFramePresenter does
    // per semantically-dirty frame. The delta is computed OUTSIDE the window.
    void present(int tick) {
      final tree = _appTree(messages: messages, tick: tick);
      final delta = _delta(owner, tree);
      final snapshot = tree.toInspectionSnapshot();
      encoder.encode(snapshot, delta: delta);
    }

    for (var i = 1; i <= warmup; i++) {
      present(i);
    }

    final result = await _measure(
      service,
      isolateId,
      work: () {
        for (var i = 0; i < frames; i++) {
          present(warmup + 1 + i);
        }
      },
    );
    final perFrame = result.totalBytes / frames;

    if (update) {
      writeBaselineJson(baselinePath, {
        'bytesPerFrame': perFrame,
        'totalBytes': result.totalBytes,
        'frames': frames,
        'messages': messages,
        'nodeCount': nodeCount,
      });
      stdout.writeln('serve semantics alloc gate: wrote baseline $baselinePath '
          '(${perFrame.toStringAsFixed(1)} B/frame over $frames frames, '
          '$nodeCount-node tree).');
      return;
    }

    stdout.writeln('serve-semantics per-frame production (package:fleury) '
        'allocation churn ($nodeCount-node tree, patch of 2 nodes/frame):');
    stdout.writeln('  ${result.totalBytes} B over $frames frames = '
        '${perFrame.toStringAsFixed(1)} B/frame');
    stdout.writeln('  top $top allocating project classes (window):');
    for (final c in result.top.take(top)) {
      stdout.writeln('    ${c.bytes.toString().padLeft(9)} B  '
          '${c.instances.toString().padLeft(7)} inst  ${c.name}');
    }

    if (!gate) return;

    final base = readBaselineOrNull(
      baselinePath,
      gateName: 'serve semantics alloc gate',
    );
    if (base == null) {
      exitCode = 64;
      return;
    }
    final basePerFrame = (base['bytesPerFrame'] as num).toDouble();
    final limit = basePerFrame * (1 + _failFraction);
    final delta = (perFrame - basePerFrame) / basePerFrame * 100;
    final line = 'serve semantics alloc gate: ${perFrame.toStringAsFixed(1)} '
        'B/frame vs baseline ${basePerFrame.toStringAsFixed(1)} '
        '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%, '
        'limit +${(_failFraction * 100).toStringAsFixed(0)}%)';
    if (perFrame <= limit) {
      stdout.writeln('$line — pass.');
      if (perFrame < basePerFrame * (1 - _failFraction)) {
        stdout.writeln('serve semantics alloc gate: per-frame production churn '
            'improved ${delta.toStringAsFixed(1)}% below baseline — lock it in '
            'with --update-baseline so the ceiling drops.');
      }
    } else {
      stdout.writeln('$line — FAIL.');
      stderr.writeln('serve semantics alloc gate: per-frame server production '
          'churn regressed past tolerance. Did the presenter go back to '
          'building a full redacted snapshot every frame instead of redacting '
          'only the changed nodes? Inspect the top-classes breakdown; if the '
          'change is intentional, re-baseline with --update-baseline.');
      exitCode = 1;
    }
  } finally {
    await service.dispose();
  }
}
