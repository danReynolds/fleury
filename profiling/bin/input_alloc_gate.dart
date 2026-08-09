// Per-key allocation regression gate (G5) — RFC 0020 §19.
//
// Drives raw terminal bytes through the REAL input path — InputParser ->
// InputDispatcher -> session regularizer -> binding walk / detector walk /
// text lane — and sums the bytes allocated by `package:fleury` classes, giving
// deterministic bytes/key of project churn.
//
// Why this needs its own gate, distinct from the per-frame alloc gate:
//
//   * The per-frame gate never presses a key. Every allocation in the parser,
//     the press-record regularizer, the frame latch, and the deepest-first
//     binding walk sits entirely outside its window.
//   * RFC 0020 made the input path do strictly more work: lifecycle mode
//     turns one press into a down/repeat/up trio, adds a press record per
//     held key, and adds an observation lane. "Sampling cannot cause an
//     input-rate storm" (§19) is an allocation claim, and until now nothing
//     measured it.
//   * A held key in a game repeats at the terminal's auto-repeat rate for as
//     long as the player leans on it. Churn here lands on the same GC that
//     has to not drop frames.
//
// The scenario deliberately holds a key down across the window (down, then a
// long run of repeats, then up) rather than tapping distinct keys: that is the
// shape that exercises press records, the repeat-policy filter, and the
// snapshot latch simultaneously, and it is the shape a game produces.
//
// MUST be launched with the VM service enabled and --deterministic, for the
// same reason as alloc_gate (background JIT tiering mid-window):
//   dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//     bin/input_alloc_gate.dart [--gate] [--update-baseline] [--keys=N]
//
// Exit codes: 0 pass, 1 regression, 64 usage/setup error.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:fleury/src/runtime/input_dispatcher.dart';
import 'package:fleury/src/terminal/input_parser.dart';
import 'package:fleury/src/widgets/focus.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'gate_support.dart';

const _defaultKeys = 2000;
const _defaultWarmup = 1500;

/// bytes/key fails beyond this relative increase. Deterministic measurement,
/// so the headroom is for SDK / machine drift, not run noise.
const _failFraction = 0.10;

/// A tree shaped like a real key-handling app: a global binding scope, a
/// nested modal-ish scope with a multi-step sequence, a detector floor, and a
/// focused leaf. Every layer the dispatcher walks per key is present, so a
/// regression in the walk itself shows up rather than being optimised away by
/// an empty chain.
Widget _scenario() {
  return KeyBindings(
    bindings: [
      KeyBinding(KeySequence.ctrl.s, label: 'Save', onTrigger: (_) {}),
      KeyBinding(KeySequence.ctrl.q, label: 'Quit', onTrigger: (_) {}),
      // A two-step sequence keeps the pending-prefix machinery live.
      KeyBinding(
        KeySequence.parse('g g'),
        label: 'Top',
        onTrigger: (_) {},
      ),
    ],
    child: KeyBindings(
      bindings: [
        // The positional binding the gate is really about: a game control
        // sampled every tick while the key is held.
        KeyBinding(KeyPosition.w, label: 'Thrust', onTrigger: (_) {}),
        KeyBinding(KeyCode.escape, label: 'Menu', onTrigger: (_) {}),
      ],
      child: KeyDetector(
        // A floor consumer that declines everything — the propagate-by-default
        // path, which is the one every key takes.
        onKey: (_) {},
        child: Focus(autofocus: true, child: const Text('input alloc gate')),
      ),
    ),
  );
}

/// Routes parsed events into the dispatcher, exactly as the runtime does.
class _DispatchSink implements TuiEventSink {
  _DispatchSink(this.dispatcher);
  final InputDispatcher dispatcher;
  @override
  void add(TuiEvent event) => dispatcher.dispatch(event);
}

/// One held-key cycle in raw CSI-u bytes, exactly as a lifecycle-mode
/// terminal reports it: press, a run of auto-repeats, release.
List<int> _heldKeyBytes({required int repeats}) {
  final out = <int>[];
  void csi(String body) => out.addAll(body.codeUnits);
  // `CSI 119 ; 1 : <event> ; 119 u` — the W key, no modifiers, with the
  // associated text that flag 16 supplies.
  csi('\x1B[119;1:1;119u'); // down
  for (var i = 0; i < repeats; i++) {
    csi('\x1B[119;1:2;119u'); // repeat
  }
  csi('\x1B[119;1:3;119u'); // up
  return out;
}

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
  var keys = _defaultKeys;
  var warmup = _defaultWarmup;
  var top = 12;
  var gate = false;
  var update = false;
  var baselinePath = 'input_alloc_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (parseIntFlag(arg, 'keys') case final v?) {
      keys = v;
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

  final info = await developer.Service.getInfo();
  final server = info.serverUri;
  if (server == null) {
    stderr.writeln(
      'input_alloc_gate: no VM service. Launch with '
      '`dart --deterministic --enable-vm-service=0 '
      '--disable-service-auth-codes bin/input_alloc_gate.dart ...` '
      '(fleury benchmark input-alloc-gate does this).',
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

    final owner = BuildOwner();
    final focusManager = FocusManager();
    final root = owner.mountRoot(
      FocusManagerScope(manager: focusManager, child: _scenario()),
    );
    // Lay the tree out once so focus resolves and the chain the dispatcher
    // walks is the real, populated one.
    owner.renderFrame(root, CellBuffer(const CellSize(80, 24)));

    final dispatcher = InputDispatcher(focusManager: focusManager)
      // Lifecycle mode: the tier the gate exists to measure. Under the legacy
      // projection the session skips press records entirely and the number
      // would flatter us.
      ..updateKeyboardCapabilities(KeyboardCapabilities.full);

    final parser = InputParser();
    final sink = _DispatchSink(dispatcher);

    // 24 repeats per cycle ≈ a key held for a second at a typical terminal
    // auto-repeat rate. Bytes are precomputed so the gate measures the input
    // path, not the construction of its own fixture.
    const repeatsPerCycle = 24;
    final cycle = _heldKeyBytes(repeats: repeatsPerCycle);
    const keysPerCycle = repeatsPerCycle + 2; // down + repeats + up

    void pressCycle() {
      parser.feed(cycle, sink);
      // The frame latch is part of the per-key cost: a sampling consumer
      // latches once per frame, and the latch walks the accumulated edges.
      dispatcher.keyboardSession.publishLatch();
    }

    final warmupCycles = (warmup / keysPerCycle).ceil();
    for (var i = 0; i < warmupCycles; i++) {
      pressCycle();
    }

    final cycles = (keys / keysPerCycle).ceil();
    final measuredKeys = cycles * keysPerCycle;
    final result = await _measure(
      service,
      isolateId,
      work: () {
        for (var i = 0; i < cycles; i++) {
          pressCycle();
        }
      },
    );
    final perKey = result.totalBytes / measuredKeys;

    if (update) {
      writeBaselineJson(baselinePath, {
        'bytesPerKey': perKey,
        'totalBytes': result.totalBytes,
        'keys': measuredKeys,
      });
      stdout.writeln(
        'input alloc gate: wrote baseline $baselinePath '
        '(${perKey.toStringAsFixed(1)} B/key over $measuredKeys keys).',
      );
      return;
    }

    stdout.writeln('per-key project (package:fleury) allocation churn:');
    stdout.writeln(
      '  ${result.totalBytes} B over $measuredKeys key events = '
      '${perKey.toStringAsFixed(1)} B/key',
    );
    stdout.writeln('  top $top allocating project classes (window):');
    for (final c in result.top.take(top)) {
      stdout.writeln(
        '    ${c.bytes.toString().padLeft(9)} B  '
        '${c.instances.toString().padLeft(7)} inst  ${c.name}',
      );
    }

    if (!gate) return;

    final base = readBaselineOrNull(baselinePath, gateName: 'input alloc gate');
    if (base == null) {
      exitCode = 64;
      return;
    }
    final basePerKey = (base['bytesPerKey'] as num).toDouble();
    final limit = basePerKey * (1 + _failFraction);
    final delta = (perKey - basePerKey) / basePerKey * 100;
    final line =
        'input alloc gate: ${perKey.toStringAsFixed(1)} B/key vs '
        'baseline ${basePerKey.toStringAsFixed(1)} '
        '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%, '
        'limit +${(_failFraction * 100).toStringAsFixed(0)}%)';
    if (perKey <= limit) {
      stdout.writeln('$line — pass.');
      if (perKey < basePerKey * (1 - _failFraction)) {
        stdout.writeln(
          'input alloc gate: per-key churn improved '
          '${delta.toStringAsFixed(1)}% below baseline — lock it in with '
          '--update-baseline so the ceiling drops.',
        );
      }
    } else {
      stdout.writeln('$line — FAIL.');
      stderr.writeln(
        'input alloc gate: per-key allocation churn regressed past '
        'tolerance. A new allocation in the parser, the session regularizer, '
        'the frame latch, or the binding/detector walk? Inspect the '
        'top-classes breakdown above; if the change is intentional, '
        're-baseline with --update-baseline.',
      );
      exitCode = 1;
    }
  } finally {
    await service.dispose();
  }
}
