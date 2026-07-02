// The frame program's ordering invariants, asserted as observable
// properties through the structured serve path (a fake transport records
// exactly what a peer would see). Written against the pre-extraction
// runApp loop and kept green through the FrameDriver refactor — the
// contract, not the implementation:
//
//   1. Every rendered frame is presented exactly once, and committed only
//      after presentation: each PlanFrame applies cleanly, in order, to a
//      mirror seeded from the previous state (a double-present or a
//      commit-before-present would corrupt the diff chain).
//   2. Post-frame callbacks run after the frame's bytes are out, and are
//      drained even on skipped (no-work) frames.
//   3. A no-work frame writes nothing to the wire.
//   4. A resize resets the diff base: the next plan is a full repaint at
//      the new size.
//   5. Input is dispatched before the skip gate: an event that only
//      mutates state still produces a frame.
//   6. Semantic frames ship only when semantics changed, after the plan
//      for the same frame, and the diff chain decodes cleanly.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

import '../remote/remote_test_support.dart';

const _init = InitFrame(
  size: CellSize(40, 6),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

class _Counter extends StatefulWidget {
  const _Counter({required this.onPostFrame});
  final void Function(String tag) onPostFrame;

  static final tap = KeyChord.char('t');
  static final silent = KeyChord.char('s');

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;
  var _silentPokes = 0;

  @override
  Widget build(BuildContext context) {
    TuiBinding.of(context).addPostFrameCallback((_) {
      widget.onPostFrame('after-frame-$_count');
    });
    return KeyBindings(
      bindings: [
        KeyBinding(_Counter.tap, onEvent: (_) => setState(() => _count++)),
        KeyBinding(
          _Counter.silent,
          // Mutates non-visual state without setState: dispatch happens,
          // nothing rebuilds, the frame is a no-work skip.
          onEvent: (_) => _silentPokes++,
        ),
      ],
      child: Semantics(
        id: const SemanticNodeId('count'),
        role: SemanticRole.text,
        label: 'count',
        value: '$_count',
        child: Focus(autofocus: true, child: Text('count: $_count')),
      ),
    );
  }
}

void main() {
  test('frame program invariants hold on the structured path', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));

    final postFrameTags = <String>[];
    final done = runApp(
      _Counter(
        onPostFrame: (tag) {
          // Record how many presentation frames were on the wire when the
          // callback ran: every callback must observe its own frame's plan
          // and semantics already sent. (Absolute positions would be
          // brittle — e.g. the v3 INIT echo also occupies a slot.)
          final p = transport.sent.whereType<PlanFrame>().length;
          final sem = transport.sent.whereType<SemanticsFrame>().length;
          postFrameTags.add('$tag@p${p}s$sem');
        },
      ),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    // --- Invariant 1+6: plans and semantics decode in order onto a mirror.
    List<PlanFrame> plans() => transport.sent.whereType<PlanFrame>().toList();
    List<SemanticsFrame> semantics() =>
        transport.sent.whereType<SemanticsFrame>().toList();

    expect(plans(), hasLength(1), reason: 'initial frame presented once');
    expect(semantics(), hasLength(1), reason: 'initial semantics shipped');
    expect(
      transport.sent.indexOf(plans().single),
      lessThan(transport.sent.indexOf(semantics().single)),
      reason: 'semantics follow the plan for the same frame',
    );

    final mirror = CellBuffer(_init.size);
    final decoder = SemanticsWireDecoder();
    void applyAll() {
      for (final f in plans()) {
        applyRemotePlanToBuffer(f.plan, mirror);
      }
      for (final f in semantics()) {
        expect(
          decoder.apply(f.json),
          isNotNull,
          reason: 'semantic diff chain unbroken',
        );
      }
    }

    applyAll();
    expect(
      mirror.textInRange(CellRect.fromLTWH(0, 0, mirror.size.cols, 1)),
      contains('count: 0'),
    );

    // --- Invariant 2: initial post-frame callback ran after its frame's
    // plan was sent. Semantics flush as a same-task microtask (the shared
    // pipeline's deferred engine), so they land after the callbacks but
    // before anything else runs — the ordering assertion above already
    // pinned plan-before-semantics on the wire.
    expect(postFrameTags, isNotEmpty);
    expect(
      postFrameTags.first,
      'after-frame-0@p1s0',
      reason: 'callback for frame 0 runs after its plan is on the wire',
    );

    // --- Invariant 5: input dispatched before the skip gate.
    final sentBefore = transport.sent.length;
    transport.emit(const InputEventFrame(KeyEvent(char: 't')));
    await _settle();
    expect(
      plans(),
      hasLength(2),
      reason: 'a state-mutating key produces a new frame',
    );
    final mirror2 = CellBuffer(_init.size);
    for (final f in plans()) {
      applyRemotePlanToBuffer(f.plan, mirror2);
    }
    expect(
      mirror2.textInRange(CellRect.fromLTWH(0, 0, mirror2.size.cols, 1)),
      contains('count: 1'),
    );
    expect(transport.sent.length, greaterThan(sentBefore));

    // --- Invariant 3: a no-work frame writes nothing.
    final sentBeforeSilent = transport.sent.length;
    final tagsBeforeSilent = postFrameTags.length;
    transport.emit(const InputEventFrame(KeyEvent(char: 's')));
    await _settle();
    expect(
      transport.sent.length,
      sentBeforeSilent,
      reason: 'no-work frame writes zero frames to the wire',
    );
    expect(
      postFrameTags.length,
      tagsBeforeSilent,
      reason: 'no new frame -> the build added no new callback',
    );

    // --- Invariant 4: resize resets the diff base to a full repaint.
    transport.emit(const ResizeFrame(CellSize(30, 4)));
    await _settle();
    final lastPlan = plans().last.plan;
    expect(lastPlan.size, const CellSize(30, 4));
    expect(
      lastPlan.fullRepaint,
      isTrue,
      reason: 'resized frame is a full repaint at the new size',
    );
    final resized = CellBuffer(const CellSize(30, 4));
    applyRemotePlanToBuffer(lastPlan, resized);
    expect(
      resized.textInRange(CellRect.fromLTWH(0, 0, resized.size.cols, 1)),
      contains('count: 1'),
    );

    // Two builds ran (initial + the 't' rebuild); the resize re-renders
    // without rebuilding _Counter (it reads no MediaQuery), so exactly two
    // callbacks — each recorded AFTER its own frame's wire writes.
    expect(postFrameTags, hasLength(2));

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });
}
