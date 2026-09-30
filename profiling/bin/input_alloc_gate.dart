// Object-creation regression gate using bounded VM allocation trace windows.
// Heap inventories are not churn counters on Dart 3.12.2. Counts include
// discarded objects and survive GC; the public trace API does not expose
// allocation sizes, so these are objects, never mislabeled bytes.
// Run through fleury_dev.dart benchmark for the required profiler flags.
// Old byte baselines are intentionally incompatible with this measurement.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service_io.dart';

import 'gate_support.dart';
import 'allocation_trace_measure.dart';

const _defaultKeys = 2000;
const _defaultWarmup = 1500;

/// objects/key fails beyond this relative increase. Deterministic measurement,
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
    } else if (parsePositiveIntFlag(arg, 'keys') case final v?) {
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

  if (warmup < 0 || top < 0) {
    stderr.writeln('--warmup and --top must be nonnegative');
    exitCode = 64;
    return;
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
  final wsUri = server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString();

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
      dispatcher.keyboardSession.publishLatch(KeyboardLatchClock.frame);
    }

    final warmupCycles = (warmup / keysPerCycle).ceil();
    for (var i = 0; i < warmupCycles; i++) {
      pressCycle();
    }

    final cycles = (keys / keysPerCycle).ceil();
    final measuredKeys = cycles * keysPerCycle;
    final result = await measureAllocations(isolateId,
        iterations: cycles, work: pressCycle, includeCore: false);
    final perKey = result.project / measuredKeys;

    if (update) {
      writeBaselineJson(baselinePath, {
        'measurement': 'allocation-traces-v1-objects',
        'sdk': Platform.version.split(' ').first,
        'objectsPerKey': perKey,
        'projectObjects': result.project,
        'keys': measuredKeys,
      });
      stdout.writeln(
        'input alloc gate: wrote baseline $baselinePath '
        '(${perKey.toStringAsFixed(1)} objects/key over $measuredKeys keys).',
      );
      return;
    }

    stdout.writeln('per-key project (package:fleury) allocation churn:');
    stdout.writeln(
      '  ${result.project} objects over $measuredKeys key events = '
      '${perKey.toStringAsFixed(1)} objects/key',
    );
    stdout.writeln('  top $top allocating project classes (window):');
    final ranked = result.classes.entries
        .where((e) => e.key.startsWith('package:fleury/'))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final c in ranked.take(top)) {
      stdout.writeln('    ${c.value.toString().padLeft(9)} objects  ${c.key}');
    }

    if (!gate) return;

    final base = readBaselineOrNull(baselinePath, gateName: 'input alloc gate');
    if (base == null || base['measurement'] != 'allocation-traces-v1-objects') {
      stderr.writeln('Missing or incompatible trace-count baseline.');
      exitCode = 64;
      return;
    }
    final basePerKey = (base['objectsPerKey'] as num).toDouble();
    final limit = basePerKey * (1 + _failFraction);
    final delta = (perKey - basePerKey) / basePerKey * 100;
    final line =
        'input alloc gate: ${perKey.toStringAsFixed(1)} objects/key vs '
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
