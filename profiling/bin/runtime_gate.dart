// End-to-end runtime gate (runtime-gate).
//
// Every other gate stops short of the runtime. alloc-gate and paint-gate
// drive a `BuildOwner` directly; wire-gate drives a PTY but scripts no
// interaction; selection-gate drives input but renders through its own loop.
// NOTHING measured `runApp` -> `FrameDriver` -> present as one program, so a
// defect in the FRAME PROGRAM ITSELF — a frame that is owed and never
// scheduled, or a frame count that grows with the input instead of the
// change — was invisible to a fully green board. Two P1s shipped exactly
// that way, and both are fixtures here:
//
//   * S2 anchor-retraction. A paint-pass sweep retracts an observer that
//     stopped painting; the anchored float marks itself dirty INSIDE the
//     frame, after it already painted, and the loop consumes that damage
//     with the frame's own. Before the fix nothing scheduled the follow-up
//     frame and the stale float sat over the new content until an unrelated
//     rebuild. A widget test could not see it — the tester renders
//     unconditionally. Only the driver's schedule/skip logic can.
//   * S3 chunked-paste. A 512 KiB bracketed paste used to cost one full
//     frame per 2 KiB chunk (and a model edit that re-copied the whole
//     document each time). Frame COUNT is the axis; only a real driver
//     produces real frames.
//
// GATED AXES — deterministic integers, zero tolerance:
//
//   framesByReason      rendered frames bucketed by `FrameEvent.reason` —
//                       the runtime's own name for what asked for the frame
//                       ('key:a', 'paste', 'resize', 'post-frame',
//                       'paint-pass-retraction', ...). This is "frames
//                       rendered per event kind": it fails both when a frame
//                       goes missing and when one appears that nothing
//                       needed.
//   framesSkipped       scripted events that requested a frame the driver
//                       then took the no-change skip on (`requested -
//                       rendered`). An event that stops being free, or a
//                       skip that starts swallowing real work, moves it.
//   bytesPresented      total bytes the presenter wrote to the terminal for
//                       the script, and `bytesPerFrame` derived from it —
//                       the same SDK-independent axis wire-gate uses, here
//                       under scripted interaction rather than a canned app.
//
// Structural invariants, enforced on EVERY run (including
// --update-baseline, so a broken program cannot be baselined away):
// the retracted float is off the surface within `_hideWithinFrames` frames
// of the switch; the 512 KiB paste is lossless and costs a logarithmic
// number of frames (< `_pasteFrameCeiling`), not one per chunk.
//
// Determinism: the fake driver has no wall-clock content, and the app
// subtrees are wrapped in `TickerMode(enabled: false)` so a caret blink
// cannot inject a frame into a measurement window. The scenarios run one at
// a time in one isolate; `DebugEvents` is a process-global broadcast bus, so
// the collector is attached and detached around each.
//
//   dart run bin/runtime_gate.dart [--gate] [--update-baseline]
//       [--baseline=path]
//
// Exit codes: 0 pass, 1 regression / invariant failure, 64 usage/setup error.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_events.dart'
    show DebugEvent, DebugEvents, FrameDebugEvent, FrameEvent;

import 'gate_support.dart';

const _size = CellSize(60, 12);

/// How many frames after the tab switch the stale float must be gone. Two:
/// the rebuild frame still paints it (its bounds retract at the END of that
/// paint pass), the next one must not.
const _hideWithinFrames = 2;

/// A 512 KiB paste is 256 chunks at the default 2 KiB chunk size. The fixed
/// path costs a logarithmic number of steps; the pre-fix path cost one frame
/// per chunk. Anything at or above this ceiling is the old shape.
const _pasteFrameCeiling = 24;

/// The paste payload: 512 KiB of 64-column lines.
final _pastePayload = '${'x' * 63}\n' * 8192;

/// Collects the runtime's own per-frame telemetry off the debug bus, and the
/// bytes the presenter wrote to the fake terminal.
final class _Recorder {
  _Recorder(this.driver);

  final FakeTerminalDriver driver;
  final List<FrameEvent> frames = <FrameEvent>[];
  StreamSubscription<DebugEvent>? _sub;

  void attach() {
    _sub = DebugEvents.stream.listen((event) {
      if (event is FrameDebugEvent) frames.add(event.frame);
    });
  }

  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
  }

  int get frameCount => frames.length;
  int get bytes => driver.output.length;

  /// Frames rendered since [mark], as a reason -> count histogram.
  Map<String, int> reasonsSince(int mark) {
    final out = <String, int>{};
    for (final frame in frames.skip(mark)) {
      out[frame.reason] = (out[frame.reason] ?? 0) + 1;
    }
    return out;
  }
}

/// One event-loop turn plus a timer tick — enough for a microtask-scheduled
/// flush AND a `Timer(Duration.zero)` re-entrant flush to land.
Future<void> _settle([int turns = 3]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Runs [body] against a live `runApp` session on a fake terminal, then quits
/// the app the way a user does (unhandled Ctrl+C) and returns the recorder.
Future<_Recorder> _session(
  Widget root,
  Future<void> Function(_Recorder r) body, {
  CellSize size = _size,
}) async {
  final driver = FakeTerminalDriver(size: size);
  final recorder = _Recorder(driver);
  recorder.attach();
  final app = runApp(
    // Muted tickers: a focused editor's caret blink is a real frame source
    // and would make every window in this gate a race against a 500 ms timer.
    TickerMode(enabled: false, child: root),
    driver: driver,
    enableHotReload: false,
  );
  try {
    await _settle();
    await body(recorder);
  } finally {
    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await app.timeout(const Duration(seconds: 30));
    await recorder.detach();
    await driver.dispose();
  }
  return recorder;
}

/// The result of one scenario: its gated integers plus any invariant break.
final class _Scenario {
  _Scenario(this.name);

  final String name;
  final Map<String, int> framesByReason = <String, int>{};

  /// The frame reason `run_app` derives for each event the script injected
  /// (`_frameReasonForEvent`), in dispatch order. Every one of these
  /// requested a frame; the ones with no matching rendered frame are the
  /// skips.
  final List<String> eventReasons = <String>[];
  int framesRendered = 0;
  int bytesPresented = 0;
  String? broken;

  /// Scripted events whose frame request the driver answered with the
  /// no-change skip (nothing rebuilt, nothing invalidated, buffers warm).
  /// A frame's reason may be a merge of several requests (`a+b`), so a
  /// rendered frame is credited to every event reason it names.
  int get framesSkipped {
    var answered = 0;
    for (final reason in eventReasons) {
      final rendered = framesByReason.entries
          .where((e) => e.key.split('+').contains(reason))
          .fold<int>(0, (sum, e) => sum + e.value);
      if (rendered > 0) answered++;
    }
    return eventReasons.length - answered;
  }

  int get bytesPerFrame =>
      framesRendered == 0 ? 0 : bytesPresented ~/ framesRendered;

  Map<String, Object?> toJson() => {
        'framesByReason': framesByReason,
        'eventsDispatched': eventReasons.length,
        'framesRendered': framesRendered,
        'framesSkipped': framesSkipped,
        'bytesPresented': bytesPresented,
        'bytesPerFrame': bytesPerFrame,
      };
}

// ---------------------------------------------------------------------------
// S1 — event script: what does one keystroke cost, and what does a keystroke
// that changes nothing cost?
// ---------------------------------------------------------------------------

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _value = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeySequence.up,
          onTrigger: (_) => setState(() => _value++),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('count $_value'),
          const Text('a fixed second line so the frame has real content'),
        ],
      ),
    );
  }
}

Future<_Scenario> _eventScript() async {
  final s = _Scenario('event-script');
  const up = KeyEvent(KeyCode.arrowUp);
  // A chord nothing binds: it is dispatched, requests a frame, and the
  // driver's no-change gate must skip it. This is the `framesSkipped` axis.
  const inert = KeyEvent(KeyCode.char('z'), modifiers: {KeyModifier.alt});
  const stateChanging = 8;
  const inertEvents = 8;

  await _session(const _Counter(), (r) async {
    final mark = r.frameCount;
    for (var i = 0; i < stateChanging; i++) {
      r.driver.enqueue(up);
      await _settle();
    }
    for (var i = 0; i < inertEvents; i++) {
      r.driver.enqueue(inert);
      await _settle();
    }
    r.driver.clearOutput();
    // Re-measure bytes over one more state-changing key, so bytesPresented
    // is one keystroke's diff and not the startup sequence.
    r.driver.enqueue(up);
    await _settle();

    s.eventReasons.addAll([
      for (var i = 0; i < stateChanging; i++) 'key:arrowUp',
      for (var i = 0; i < inertEvents; i++) 'key:z',
      'key:arrowUp',
    ]);
    s.framesRendered = r.frameCount - mark;
    s.framesByReason.addAll(r.reasonsSince(mark));
    s.bytesPresented = r.bytes;
  });
  return s;
}

// ---------------------------------------------------------------------------
// S2 — an anchored float whose anchor stops painting must be hidden within
// N frames. The retraction happens inside a frame, after the float painted;
// the follow-up frame has to be REQUESTED by the driver or the stale float
// stays on screen.
// ---------------------------------------------------------------------------

Future<_Scenario> _anchorRetraction() async {
  final s = _Scenario('anchor-retraction');
  final chip = BoundsNotifier();
  final index = ValueNotifier<int>(0);

  await _session(
    ListenableBuilder(
      listenable: index,
      builder: (context, _) => Stack(
        children: [
          IndexedStack(
            index: index.value,
            children: [
              BoundsObserver(notifier: chip, child: const Text('tab-a')),
              const Text('tab-b'),
            ],
          ),
          BoundsAnchor(notifier: chip, child: const Text('¤')),
        ],
      ),
    ),
    (r) async {
      if (chip.visibleBounds == null) {
        s.broken = 'the anchor never painted — the fixture is wrong, not the '
            'runtime.';
        return;
      }
      final mark = r.frameCount;
      r.driver.clearOutput();

      index.value = 1;
      await _settle();

      // No driver events here: the tab switch is a ValueNotifier write, the
      // shape an app's own state change has.
      s.framesRendered = r.frameCount - mark;
      s.framesByReason.addAll(r.reasonsSince(mark));
      s.bytesPresented = r.bytes;

      if (chip.visibleBounds != null) {
        s.broken =
            'the retired anchor still reports bounds — the paint-pass sweep '
            'did not retract it.';
        return;
      }
      if (s.framesRendered < _hideWithinFrames) {
        s.broken =
            'switching away from the anchor produced only ${s.framesRendered} '
            'frame(s): ${s.framesByReason}. The rebuild frame paints the '
            'float once more with stale bounds, so a SECOND frame must '
            'follow to hide it — the runtime owes a frame it never '
            'scheduled, and the float sits over the new content until an '
            'unrelated rebuild.';
        return;
      }
      if (!s.framesByReason.keys.any(
        (reason) => reason.contains('paint-pass-retraction'),
      )) {
        s.broken = 'no frame was scheduled for the paint-pass retraction: '
            '${s.framesByReason}.';
        return;
      }
      // ...and it is a ONE-SHOT. A participant that stays mounted without
      // painting is unpublished in every later pass too; counting a
      // retraction per pass rather than per withdrawn fact made each frame
      // request the next one and pinned the app at full speed forever. The
      // exact frame count is gated by the baseline, but this is the tripwire
      // that says WHY when it moves.
      final settled = r.frameCount;
      await _settle();
      if (r.frameCount != settled) {
        s.broken = 'the runtime kept rendering after the tree went quiet: '
            '${r.frameCount - settled} more frames in one settle window. A '
            'retraction that is re-counted every pass makes every frame '
            'request the next one.';
      }
    },
  );
  index.dispose();
  return s;
}

// ---------------------------------------------------------------------------
// S3 — a 512 KiB paste costs a logarithmic number of frames, not one per
// chunk.
// ---------------------------------------------------------------------------

Future<_Scenario> _largePaste() async {
  final s = _Scenario('large-paste');
  final controller = TextEditingController();
  var edits = 0;
  controller.addListener(() => edits++);

  await _session(
    TextArea(controller: controller, autofocus: true),
    (r) async {
      final mark = r.frameCount;
      r.driver.clearOutput();

      r.driver.enqueue(PasteEvent(_pastePayload));
      // The chunker walks itself forward on post-frame callbacks; give it as
      // many turns as it needs, bounded so a wedged run fails instead of
      // hanging.
      for (var i = 0; i < 200; i++) {
        if (controller.text.length >= _pastePayload.length) break;
        await _settle(1);
      }
      await _settle();

      s.eventReasons.add('paste');
      s.framesRendered = r.frameCount - mark;
      s.framesByReason.addAll(r.reasonsSince(mark));
      s.bytesPresented = r.bytes;

      if (controller.text.length != _pastePayload.length) {
        s.broken = 'the paste was lossy: ${controller.text.length} of '
            '${_pastePayload.length} code units landed.';
        return;
      }
      if (s.framesRendered >= _pasteFrameCeiling) {
        s.broken = 'a ${_pastePayload.length ~/ 1024} KiB paste cost '
            '${s.framesRendered} frames (>= $_pasteFrameCeiling): '
            '${s.framesByReason}. One full frame per chunk is the pre-fix '
            'shape; the chunker must take a logarithmic number of steps.';
        return;
      }
      if (edits >= _pasteFrameCeiling) {
        s.broken = 'the paste cost $edits model edits — the document is being '
            'rebuilt once per chunk.';
      }
    },
  );
  return s;
}

// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  var gate = false;
  var update = false;
  var baselinePath = 'runtime_gate_baseline.json';
  for (final arg in args) {
    if (arg == '--gate') {
      gate = true;
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (arg.startsWith('--baseline=')) {
      baselinePath = arg.substring('--baseline='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  final scenarios = <_Scenario>[
    await _eventScript(),
    await _anchorRetraction(),
    await _largePaste(),
  ];

  for (final s in scenarios) {
    stdout.writeln('${s.name}:');
    stdout.writeln('  frames rendered   ${s.framesRendered}');
    stdout.writeln('  frames skipped    ${s.framesSkipped} of '
        '${s.eventReasons.length} scripted event(s)');
    stdout.writeln('  bytes presented   ${s.bytesPresented} '
        '(${s.bytesPerFrame}/frame)');
    final reasons = s.framesByReason.keys.toList()..sort();
    for (final reason in reasons) {
      stdout.writeln(
        '    ${reason.padRight(28)} ${s.framesByReason[reason]}',
      );
    }
  }

  // Structural invariants first — they hold even under --update-baseline.
  final broken = scenarios.where((s) => s.broken != null).toList();
  if (broken.isNotEmpty) {
    for (final s in broken) {
      stderr.writeln('runtime gate: ${s.name}: ${s.broken}');
    }
    exitCode = 1;
    return;
  }

  if (update) {
    writeBaselineJson(baselinePath, {
      for (final s in scenarios) s.name: s.toJson(),
    });
    stdout.writeln('runtime gate: wrote baseline $baselinePath.');
    return;
  }

  if (!gate) return;

  final base = readBaselineOrNull(baselinePath, gateName: 'runtime gate');
  if (base == null) {
    exitCode = 64;
    return;
  }
  var failed = false;
  void fail(String message) {
    stdout.writeln('runtime gate: $message');
    failed = true;
  }

  for (final s in scenarios) {
    final expected = base[s.name] as Map<String, Object?>?;
    if (expected == null) {
      fail('baseline has no scenario "${s.name}" — re-baseline.');
      continue;
    }
    for (final axis in const [
      'framesRendered',
      'framesSkipped',
      'bytesPresented',
    ]) {
      final want = (expected[axis] as num?)?.toInt();
      final got = switch (axis) {
        'framesRendered' => s.framesRendered,
        'framesSkipped' => s.framesSkipped,
        _ => s.bytesPresented,
      };
      if (want == null) {
        fail('${s.name}: baseline has no "$axis" — re-baseline.');
      } else if (want != got) {
        fail('${s.name}: $axis is $got vs baseline $want — FAIL.');
      }
    }
    final wantReasons = (expected['framesByReason'] as Map?)?.map(
      (key, value) => MapEntry('$key', (value as num).toInt()),
    );
    if (wantReasons == null) {
      fail('${s.name}: baseline has no "framesByReason" — re-baseline.');
    } else if (!_sameHistogram(wantReasons, s.framesByReason)) {
      fail(
        '${s.name}: frames per event kind is ${s.framesByReason} vs baseline '
        '$wantReasons — FAIL.',
      );
    }
  }

  if (failed) {
    stderr.writeln(
      'runtime gate: the frame program changed shape. A frame that is owed '
      'and not scheduled, one nothing needed, or a change in what a scripted '
      'event costs. If the change is intended, re-baseline with '
      '--update-baseline.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('runtime gate: every scenario matches baseline — pass.');
}

bool _sameHistogram(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
