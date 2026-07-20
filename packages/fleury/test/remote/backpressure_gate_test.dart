// The frame program's producer gate, end to end through a real runApp
// session: while the peer's transport is backlogged the app produces
// NOTHING (no plans, no semantics, no image bytes — the retained tree
// just absorbs state), and the drain wake-up ships exactly ONE coalesced
// frame whose diff is valid against the last frame the peer actually
// received. No plan is ever built-then-dropped, so the mirror never
// needs a resync.

import 'dart:async';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

import 'remote_test_support.dart';

const _size = CellSize(40, 4);
const _init = InitFrame(
  size: _size,
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.char('t'),
          onEvent: (_) => setState(() => _count++),
        ),
      ],
      child: Focus(
        autofocus: true,
        child: Semantics(
          id: const SemanticNodeId('count'),
          role: SemanticRole.text,
          label: 'count',
          value: '$_count',
          child: Text('count: $_count'),
        ),
      ),
    );
  }
}

/// Places [bytesFor] output as an inline image; 'i' advances the content
/// (an animation stand-in) so each frame carries distinct image bytes.
class _ImageApp extends StatefulWidget {
  const _ImageApp();

  @override
  State<_ImageApp> createState() => _ImageAppState();
}

class _ImageAppState extends State<_ImageApp> {
  var _generation = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.char('i'),
          onEvent: (_) => setState(() => _generation++),
        ),
      ],
      child: Focus(autofocus: true, child: _ImageProbe(_generation)),
    );
  }
}

class _ImageProbe extends LeafRenderObjectWidget {
  const _ImageProbe(this.generation);

  final int generation;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderImageProbe(generation);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderImageProbe).generation = generation;
  }
}

class _RenderImageProbe extends RenderObject {
  _RenderImageProbe(this._generation);

  int _generation;
  set generation(int value) {
    if (value == _generation) return;
    _generation = value;
    markNeedsPaint();
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(4, 2));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellRect? clipRect,
    CellOffset? screenOffset,
  }) {
    buffer.writeImage(
      offset,
      Uint8List.fromList([_generation, 1, 2, 3]),
      width: 4,
      height: 2,
    );
  }
}

class _PostFrameApp extends StatefulWidget {
  const _PostFrameApp({required this.onPostFrame});
  final void Function() onPostFrame;

  @override
  State<_PostFrameApp> createState() => _PostFrameAppState();
}

class _PostFrameAppState extends State<_PostFrameApp> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    TuiBinding.of(context).addPostFrameCallback((_) => widget.onPostFrame());
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.char('t'),
          onEvent: (_) => setState(() => _count++),
        ),
      ],
      child: Focus(autofocus: true, child: Text('count: $_count')),
    );
  }
}

void main() {
  test('a stalled peer freezes production; drain ships ONE coalesced plan '
      'that keeps the mirror exact', () async {
    final transport = GatedFakeTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    final done = runApp(
      const _App(),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    List<PlanFrame> plans() => transport.sent.whereType<PlanFrame>().toList();
    final plansBeforeStall = plans().length;
    expect(plansBeforeStall, greaterThan(0), reason: 'session is rendering');

    // The peer stalls; the app keeps absorbing state changes.
    transport.stall();
    for (var i = 0; i < 3; i++) {
      transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('t'))));
      await _settle();
    }
    expect(
      plans().length,
      plansBeforeStall,
      reason: 'ZERO frames produced while the transport is backlogged',
    );

    transport.drain();
    await _settle();
    expect(
      plans().length,
      plansBeforeStall + 1,
      reason: 'the wake-up ships exactly one coalesced frame',
    );

    // Mirror oracle: applying every plan the peer received, in order,
    // reproduces the final state — the coalesced diff was valid against
    // the pre-stall frame, no resync required.
    final mirror = CellBuffer(_size);
    for (final frame in plans()) {
      applyRemotePlanToBuffer(frame.plan, mirror);
    }
    expect(
      mirror.textInRange(CellRect(offset: CellOffset.zero, size: _size)),
      contains('count: 3'),
      reason: 'all three coalesced increments visible after one plan',
    );

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });

  test(
    'semantics coalesce across a stall and the diff chain decodes',
    () async {
      final transport = GatedFakeTransport();
      final driver = RemoteTerminalDriver(transport);
      scheduleMicrotask(() => transport.emit(_init));
      final done = runApp(
        const _App(),
        driver: driver,
        enableHotReload: false,
        requireInteractiveTerminal: false,
      );
      await _settle();

      List<SemanticsFrame> semantics() =>
          transport.sent.whereType<SemanticsFrame>().toList();
      final before = semantics().length;

      transport.stall();
      transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('t'))));
      await _settle();
      transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('t'))));
      await _settle();
      expect(semantics().length, before, reason: 'no semantics while stalled');

      transport.drain();
      await _settle();
      expect(
        semantics().length,
        before + 1,
        reason: 'two changes → one coalesced semantic frame',
      );

      // The chain must decode cleanly onto the pre-stall tree.
      final decoder = SemanticsWireDecoder();
      SemanticTree? tree;
      for (final frame in semantics()) {
        tree = decoder.apply(frame.json);
        expect(tree, isNotNull);
      }
      final values = [
        for (final node in tree!.nodesById.values)
          if (node.value != null) node.value!,
      ].join(',');
      expect(values, contains('2'), reason: 'final value, not an intermediate');

      transport.emit(const ByeFrame());
      await done;
      await transport.close();
    },
  );

  test('image bytes across a stall: the final content ships once, before '
      'the plan that references it; skipped frames never ship', () async {
    final transport = GatedFakeTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    final done = runApp(
      const _ImageApp(),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();
    final imagesBefore = transport.sent.whereType<InlineImageFrame>().length;
    expect(imagesBefore, 1, reason: 'generation 0 shipped at mount');

    transport.stall();
    // Two generations advance during the stall; only the last may ship.
    transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('i'))));
    await _settle();
    transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('i'))));
    await _settle();
    expect(
      transport.sent.whereType<InlineImageFrame>().length,
      imagesBefore,
      reason: 'no image bytes while stalled',
    );

    transport.drain();
    await _settle();

    final images = transport.sent.whereType<InlineImageFrame>().toList();
    expect(
      images.length,
      imagesBefore + 1,
      reason:
          'exactly one new image (generation 2) — the intermediate '
          'generation-1 frame was never produced, so its bytes never ship',
    );
    final lastImage = images.last;
    expect(lastImage.bytes[0], 2, reason: 'the FINAL generation shipped');

    // Ordering invariant: the bytes precede the plan that references
    // their id, within the post-drain send sequence.
    final sent = transport.sent;
    final imageIndex = sent.lastIndexWhere((f) => f is InlineImageFrame);
    final referencingPlanIndex = sent.indexWhere(
      (f) =>
          f is PlanFrame && f.plan.placements.any((p) => p.id == lastImage.id),
    );
    expect(referencingPlanIndex, greaterThan(imageIndex));

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });

  test('a resize during the stall resumes as one full repaint at the new '
      'size', () async {
    final transport = GatedFakeTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    final done = runApp(
      const _App(),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    List<PlanFrame> plans() => transport.sent.whereType<PlanFrame>().toList();
    final before = plans().length;

    transport.stall();
    const newSize = CellSize(60, 8);
    transport.emit(const ResizeFrame(newSize));
    await _settle();
    transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('t'))));
    await _settle();
    expect(plans().length, before, reason: 'resize is deferred too');

    transport.drain();
    await _settle();
    final resumed = plans().sublist(before);
    expect(resumed, hasLength(1));
    expect(resumed.single.plan.size, newSize);
    expect(
      resumed.single.plan.fullRepaint,
      isTrue,
      reason: 'a size change across the stall forces the full-repaint plan',
    );
    // And the fresh mirror at the new size shows the coalesced state.
    final mirror = CellBuffer(newSize);
    applyRemotePlanToBuffer(resumed.single.plan, mirror);
    expect(
      mirror.textInRange(CellRect(offset: CellOffset.zero, size: newSize)),
      contains('count: 1'),
    );

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });

  test('post-frame callbacks do not run while a frame is deferred', () async {
    // A deferred frame has not laid out; its post-frame callbacks'
    // geometry contract ("matches what the user sees") would not hold.
    // They run when the coalesced frame actually renders.
    final transport = GatedFakeTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    var postFrameRuns = 0;
    final done = runApp(
      _PostFrameApp(onPostFrame: () => postFrameRuns++),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();
    final baseline = postFrameRuns;
    expect(baseline, greaterThan(0));

    transport.stall();
    transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('t'))));
    await _settle();
    expect(
      postFrameRuns,
      baseline,
      reason: 'no post-frame callbacks while the frame is deferred',
    );

    transport.drain();
    await _settle();
    expect(
      postFrameRuns,
      greaterThan(baseline),
      reason: 'the coalesced frame runs its post-frame callbacks',
    );

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });
}
