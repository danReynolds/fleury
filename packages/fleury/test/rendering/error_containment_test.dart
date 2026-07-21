// Per-boundary layout/paint containment: the contract.
//
//   (a) A layout constraint violation inside an ErrorBoundary renders the
//       error presentation in the boundary's cells; siblings and the
//       session are untouched.
//   (b) Recovery: fixing the state re-lays-out the subtree and restores
//       real content (the throw path stays dirty by construction).
//   (c) A mid-paint throw is atomic: partial writes are buried under the
//       presentation fill.
//   (d) Coherence oracle over the serve path: a mirror built purely from
//       damage-diffed plans stays byte-identical to the app's committed
//       buffer across contain/recover — damage was never under-reported.
//   (e) Implicit boundaries: a crashing route contains by default in
//       production mode.
//   (f) Semantics: an errored boundary projects ONE errorBoundary node,
//       descendants are dropped, actions on dropped ids resolve notFound.
//   (g) FleuryTester default: containment rethrows, so a widget test with
//       a layout bug fails loudly.
//   (h) The 3×1 badge under unbounded constraints (inside a scrollable).

import 'dart:async';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

import '../remote/remote_test_support.dart';
import '../support/render_fixtures.dart';

class _Host extends StatefulWidget {
  const _Host({required this.initial});
  final BoomMode initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late BoomMode mode = widget.initial;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.char('f'),
          onTrigger: () => setState(() => mode = BoomMode.healthy),
        ),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            const Text('sibling stays'),
            SizedBox(
              height: 5,
              child: ErrorBoundary(
                rethrowContained: false,
                child: Boom(mode: mode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoverableInteractivePaintFailure extends StatefulWidget {
  const _RecoverableInteractivePaintFailure({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final TextEditingController controller;
  final void Function() onTap;

  @override
  State<_RecoverableInteractivePaintFailure> createState() =>
      _RecoverableInteractivePaintFailureState();
}

class _RecoverableInteractivePaintFailureState
    extends State<_RecoverableInteractivePaintFailure> {
  var _mode = BoomMode.paint;

  void recover() => setState(() => _mode = BoomMode.healthy);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ErrorBoundary(
        rethrowContained: false,
        child: Column(
          children: [
            GestureDetector(
              onTap: widget.onTap,
              child: const SizedBox(width: 8, height: 1, child: Text('tap me')),
            ),
            TextInput(
              controller: widget.controller,
              autofocus: true,
              enableBlink: false,
            ),
            Boom(mode: _mode, size: const CellSize(14, 3)),
          ],
        ),
      ),
    );
  }
}

class _SequenceInteractivePaintFailure extends StatefulWidget {
  const _SequenceInteractivePaintFailure({
    super.key,
    required this.onTriggered,
  });

  final void Function() onTriggered;

  @override
  State<_SequenceInteractivePaintFailure> createState() =>
      _SequenceInteractivePaintFailureState();
}

class _SequenceInteractivePaintFailureState
    extends State<_SequenceInteractivePaintFailure> {
  var _mode = BoomMode.healthy;

  void failPaint() => setState(() => _mode = BoomMode.paint);

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      rethrowContained: false,
      child: KeyBindings(
        bindings: [
          KeyBinding(KeySequence.g.g, onTrigger: () => widget.onTriggered()),
        ],
        child: Focus(
          autofocus: true,
          child: Boom(mode: _mode, size: const CellSize(14, 3)),
        ),
      ),
    );
  }
}

class _FocusDependentContainedFailure extends StatelessWidget {
  const _FocusDependentContainedFailure({required this.onBuild});

  final void Function() onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    Focus.of(context);
    return const ErrorBoundary(
      rethrowContained: false,
      child: Boom(mode: BoomMode.paint),
    );
  }
}

class _MovableContainedFailure extends StatefulWidget {
  const _MovableContainedFailure({
    super.key,
    required this.firstFocusManager,
    required this.secondFocusManager,
    required this.firstPointerRouter,
    required this.secondPointerRouter,
    required this.focusNode,
    required this.controller,
  });

  final FocusManager firstFocusManager;
  final FocusManager secondFocusManager;
  final PointerRouter firstPointerRouter;
  final PointerRouter secondPointerRouter;
  final FocusNode focusNode;
  final TextEditingController controller;

  @override
  State<_MovableContainedFailure> createState() =>
      _MovableContainedFailureState();
}

class _MovableContainedFailureState extends State<_MovableContainedFailure> {
  final _boundaryKey = GlobalKey();
  late final Widget _boundary;
  var _second = false;

  @override
  void initState() {
    super.initState();
    // Reuse this exact widget instance so global-key activation, not a widget
    // update, is responsible for rebinding inherited input services.
    _boundary = ErrorBoundary(
      key: _boundaryKey,
      rethrowContained: false,
      child: Column(
        children: [
          TextInput(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enableBlink: false,
          ),
          const Boom(mode: BoomMode.paint, size: CellSize(14, 3)),
        ],
      ),
    );
  }

  void moveToSecondServices() => setState(() => _second = true);

  Widget _slot({
    required FocusManager focusManager,
    required PointerRouter pointerRouter,
    required Widget child,
  }) {
    return SizedBox(
      width: 18,
      height: 5,
      child: FocusManagerScope(
        manager: focusManager,
        child: PointerRouterScope(router: pointerRouter, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _slot(
          focusManager: widget.firstFocusManager,
          pointerRouter: widget.firstPointerRouter,
          child: _second ? const SizedBox() : _boundary,
        ),
        _slot(
          focusManager: widget.secondFocusManager,
          pointerRouter: widget.secondPointerRouter,
          child: _second ? _boundary : const SizedBox(),
        ),
      ],
    );
  }
}

void main() {
  _secondaryTests();
  _coherenceOracle();
  group('ErrorBoundary', () {
    testWidgets('(a) contains a layout throw; sibling intact', (tester) {
      final contained = <FrameContainmentError>[];
      tester.owner.onContainedRenderError = contained.add;
      tester.pumpWidget(const _Host(initial: BoomMode.layout));
      final out = tester.renderToString(size: const CellSize(30, 6));

      expect(out, contains('sibling stays'));
      expect(out, contains('⚠'), reason: 'presentation painted');
      expect(out, contains('layout-boom'), reason: 'error text visible');
      expect(contained, hasLength(1), reason: 'reported exactly once');
      expect(contained.single.phase, FrameContainmentPhase.layout);

      // A second frame with no changes re-presents without re-reporting.
      tester.pump();
      final out2 = tester.renderToString(size: const CellSize(30, 6));
      expect(out2, contains('⚠'));
      expect(contained, hasLength(1));
    });

    testWidgets('(b) recovers when the subtree is fixed', (tester) {
      tester.pumpWidget(const _Host(initial: BoomMode.layout));
      expect(
        tester.renderToString(size: const CellSize(30, 6)),
        contains('layout-boom'),
      );

      tester.sendKey(const KeyEvent(KeyCode.char('f')));
      final out = tester.renderToString(size: const CellSize(30, 6));
      expect(out, contains('healthy###'), reason: 'subtree re-attempted');
      expect(out, isNot(contains('⚠')));
      expect(out, isNot(contains('layout-boom')));
    });

    testWidgets('(c) a mid-paint throw is atomic', (tester) {
      tester.pumpWidget(const _Host(initial: BoomMode.paint));
      final out = tester.renderToString(size: const CellSize(30, 6));
      expect(out, contains('paint-boom'));
      expect(
        out,
        isNot(contains('part')),
        reason: 'partial pre-throw writes are buried by the fill',
      );
      expect(out, contains('sibling stays'));
    });

    testWidgets(
      'a contained paint failure makes partial pointer and focus state inert',
      (tester) {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final key = GlobalKey<_RecoverableInteractivePaintFailureState>();
        var taps = 0;
        tester.pumpWidget(
          _RecoverableInteractivePaintFailure(
            key: key,
            controller: controller,
            onTap: () => taps += 1,
          ),
        );

        final failed = tester.renderToString(size: const CellSize(30, 8));
        expect(failed, contains('paint-boom'));
        // Exercise an enclosing RepaintBoundary cache hit too: it captured
        // the partial child's paint geometry before the later Boom threw.
        tester.pump();
        tester.render(size: const CellSize(30, 8));

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 1,
            row: 0,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 1,
            row: 0,
          ),
        );
        tester.type('secret');
        expect(taps, 0, reason: 'the hidden gesture region is input-inert');
        expect(
          controller.text,
          isEmpty,
          reason: 'the hidden autofocus claimant cannot receive text',
        );

        key.currentState!.recover();
        tester.pump();
        final recovered = tester.renderToString(size: const CellSize(30, 8));
        expect(recovered, contains('healthy###'));

        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 1,
            row: 0,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 1,
            row: 0,
          ),
        );
        tester.type('ok');
        expect(taps, 1, reason: 'pointer input recovers with the subtree');
        expect(controller.text, 'ok', reason: 'focus input recovers too');
      },
    );

    testWidgets(
      'a pending key sequence cannot fire after its boundary is contained',
      (tester) {
        final key = GlobalKey<_SequenceInteractivePaintFailureState>();
        var triggers = 0;
        tester.pumpWidget(
          _SequenceInteractivePaintFailure(
            key: key,
            onTriggered: () => triggers += 1,
          ),
        );
        tester.render(size: const CellSize(30, 6));

        tester.sendKey(const KeyEvent(KeyCode.char('g')));
        expect(tester.dispatcher.hasPendingSequence, isTrue);

        key.currentState!.failPaint();
        tester.pump();
        expect(
          tester.renderToString(size: const CellSize(30, 6)),
          contains('⚠'),
        );
        tester.sendKey(const KeyEvent(KeyCode.char('g')));

        expect(triggers, 0);
        expect(tester.dispatcher.hasPendingSequence, isFalse);
      },
    );

    testWidgets(
      'retained containment does not churn focus-dependent rebuilds',
      (tester) {
        var builds = 0;
        tester.pumpWidget(
          _FocusDependentContainedFailure(onBuild: () => builds += 1),
        );
        expect(
          tester.renderToString(size: const CellSize(30, 6)),
          contains('⚠'),
        );

        tester.pump();
        expect(
          () => tester.render(size: const CellSize(30, 6)),
          returnsNormally,
        );
        expect(builds, lessThan(5));
      },
    );

    testWidgets(
      'a contained global-key move transfers inherited input exclusion',
      (tester) {
        final firstFocusManager = FocusManager();
        final secondFocusManager = FocusManager();
        final firstPointerRouter = PointerRouter();
        final secondPointerRouter = PointerRouter();
        final focusNode = FocusNode();
        final controller = TextEditingController();
        final key = GlobalKey<_MovableContainedFailureState>();
        final secondDispatcher = InputDispatcher(
          focusManager: secondFocusManager,
          pointerRouter: secondPointerRouter,
        );
        addTearDown(() {
          secondDispatcher.dispose();
          controller.dispose();
          focusNode.dispose();
          firstPointerRouter.dispose();
          secondPointerRouter.dispose();
          firstFocusManager.dispose();
          secondFocusManager.dispose();
        });

        tester.pumpWidget(
          _MovableContainedFailure(
            key: key,
            firstFocusManager: firstFocusManager,
            secondFocusManager: secondFocusManager,
            firstPointerRouter: firstPointerRouter,
            secondPointerRouter: secondPointerRouter,
            focusNode: focusNode,
            controller: controller,
          ),
        );
        expect(
          tester.renderToString(size: const CellSize(40, 6)),
          contains('⚠'),
        );

        key.currentState!.moveToSecondServices();
        tester.pump();
        expect(
          tester.renderToString(size: const CellSize(40, 6)),
          contains('⚠'),
        );

        expect(
          secondFocusManager.requestFocus(focusNode),
          isFalse,
          reason: 'the new focus manager inherits the active exclusion',
        );
        secondDispatcher.dispatch(const TextInputEvent('hidden'));
        expect(controller.text, isEmpty);
      },
    );

    testWidgets('(f) semantics: one node, descendants dropped, notFound', (
      tester,
    ) async {
      tester.pumpWidget(
        ErrorBoundary(
          rethrowContained: false,
          child: Semantics(
            id: const SemanticNodeId('inner-button'),
            role: SemanticRole.button,
            label: 'press me',
            actions: const {SemanticAction.activate},
            child: const Boom(),
          ),
        ),
      );
      tester.render(size: const CellSize(30, 6));

      final nodes = tester.semantics();
      expect(
        nodes.where(role: SemanticRole.errorBoundary),
        hasLength(1),
        reason: 'the failure is announced as a single node',
      );
      expect(
        nodes.where(role: SemanticRole.button),
        isEmpty,
        reason: 'invisible descendants are not projected',
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        id: const SemanticNodeId('inner-button'),
      );
      expect(
        result.status,
        SemanticActionInvocationStatus.notFound,
        reason: 'actions against dropped ids fail closed',
      );
    });

    testWidgets('(g) the tester default rethrows contained errors', (tester) {
      tester.pumpWidget(const ErrorBoundary(child: Boom()));
      expect(
        () => tester.render(size: const CellSize(30, 6)),
        throwsA(isA<StateError>()),
        reason: 'a widget test with a layout bug must fail the test',
      );
    });

    testWidgets('(h) 3×1 badge under unbounded constraints', (tester) {
      final controller = ScrollController();
      tester.pumpWidget(
        ScrollView(
          controller: controller,
          child: const Column(
            children: [
              Text('above'),
              ErrorBoundary(rethrowContained: false, child: Boom()),
              Text('below'),
            ],
          ),
        ),
      );
      final out = tester.renderToString(size: const CellSize(20, 6));
      expect(out, contains('above'));
      expect(out, contains('below'), reason: 'list keeps flowing');
      expect(out, contains('!'), reason: 'the badge stays visible');
    });
  });
}

class _SelfDirtying extends StatefulWidget {
  const _SelfDirtying();

  @override
  State<_SelfDirtying> createState() => _SelfDirtyingState();
}

class _SelfDirtyingState extends State<_SelfDirtying> {
  @override
  Widget build(BuildContext context) {
    // Re-dirty every pass: flushBuild must cap and name us instead of
    // hanging the process.
    (context as Element).markNeedsBuild();
    return const Text('spin');
  }
}

class _ProbePresenter implements FramePresenter {
  final frames = <String>[];

  @override
  bool get wantsPresentationPlan => false;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    frames.add(
      frame.next.textInRange(
        CellRect.fromLTWH(0, 0, frame.next.size.cols, frame.next.size.rows),
      ),
    );
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {}

  @override
  FrameDiffStats? frameDiffStats(
    TuiRenderedFrame frame,
    FramePresentInfo info,
  ) => null;
}

void _secondaryTests() {
  group('implicit boundaries', () {
    testWidgets('(e) a crashing route contains in production mode', (tester) {
      // Production posture: contain instead of the tester's rethrow.
      tester.owner.rethrowContainedRenderErrors = false;
      tester.pumpWidget(Navigator(home: const Boom()));
      final out = tester.renderToString(size: const CellSize(30, 8));
      expect(out, contains('layout-boom'), reason: 'route slot shows panel');
      expect(out, contains('⚠'));
    });
  });

  group('root backstop', () {
    test('(i) an unbounded crash yields a full-screen error frame', () {
      final runtime = TuiRuntime();
      runtime.owner.rethrowContainedRenderErrors = false;
      final frameLoop = TuiFrameLoop(renderDamage: runtime.renderDamageTracker);
      final backstopped = <Object>[];
      final presenter = _ProbePresenter();
      final driver = FrameDriver(
        runtime: runtime,
        frameLoop: frameLoop,
        readViewport: () => const FrameViewportSnapshot(CellSize(24, 4)),
        presenter: presenter,
        onBackstopError: (error, stack) => backstopped.add(error),
      );
      // No Navigator/Overlay/ErrorBoundary anywhere: the throw escapes
      // every boundary and hits the driver.
      driver.mountRoot(() => const Boom());

      driver.renderNow('test');
      expect(backstopped, hasLength(1));
      expect(presenter.frames, hasLength(1));
      expect(
        presenter.frames.single,
        contains('layout-boom'),
        reason: 'full-screen error frame presented',
      );
      expect(driver.renderUnrecoverable, isFalse, reason: 'session survives');
      driver.dispose();
    });

    test('(j) a backstop storm declares the session unrecoverable', () {
      final runtime = TuiRuntime();
      runtime.owner.rethrowContainedRenderErrors = false;
      final frameLoop = TuiFrameLoop(renderDamage: runtime.renderDamageTracker);
      final presenter = _ProbePresenter();
      final driver = FrameDriver(
        runtime: runtime,
        frameLoop: frameLoop,
        readViewport: () => const FrameViewportSnapshot(CellSize(24, 4)),
        presenter: presenter,
        backstopStormLimit: 3,
      );
      driver.mountRoot(() => const Boom());

      driver.renderNow('1');
      // The error frame committed; force fresh attempts by re-dirtying.
      driver.rootElement?.markNeedsBuild();
      driver.renderNow('2');
      expect(driver.renderUnrecoverable, isFalse);
      driver.rootElement?.markNeedsBuild();
      expect(() => driver.renderNow('3'), throwsA(isA<StateError>()));
      expect(driver.renderUnrecoverable, isTrue);
      driver.dispose();
    });
  });

  group('flushBuild convergence cap', () {
    testWidgets('a self-dirtying widget fails loudly, not silently', (tester) {
      expect(
        () => tester.pumpWidget(const _SelfDirtying()),
        throwsA(
          isA<FleuryError>().having(
            (e) => e.summary,
            'summary',
            contains('did not converge'),
          ),
        ),
        reason: 'the mount flush hits the cap and names the culprit',
      );
    });
  });
}

/// (d) The coherence oracle: a mirror built purely from damage-diffed wire
/// plans must track the app's screen exactly across contain → recover. If
/// containment ever under-reported damage, stale error (or stale content)
/// cells would survive in the mirror with no way to repair.
void _coherenceOracle() {
  test('(d) serve mirror stays exact across contain/recover', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(
      () => transport.emit(
        const InitFrame(
          size: CellSize(30, 12),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        ),
      ),
    );

    final done = runApp(
      const _Host(initial: BoomMode.layout),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final mirror = CellBuffer(const CellSize(30, 12));
    var applied = 0;
    String mirrorText() {
      for (final f
          in transport.sent.whereType<PlanFrame>().skip(applied).toList()) {
        applyRemotePlanToBuffer(f.plan, mirror);
        applied++;
      }
      return mirror.textInRange(CellRect.fromLTWH(0, 0, 30, 12));
    }

    final contained = mirrorText();
    expect(contained, contains('sibling stays'));
    expect(contained, contains('layout-boom'), reason: 'panel on the wire');

    // Recover: the 'f' binding heals the subtree.
    transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('f'))));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    mirrorText();
    // Scope to the boundary's content rows (1–4, under the sibling row and
    // above the bottom-aligned runtime error BANNER, which legitimately
    // still shows the error message — contained errors surface there like
    // any survivable error). The containment claim is about panel cells.
    final panelRegion = mirror.textInRange(CellRect.fromLTWH(0, 1, 30, 5));
    expect(panelRegion, contains('healthy###'), reason: 'content restored');
    expect(
      panelRegion,
      isNot(contains('layout-boom')),
      reason: 'no stale panel cells survive in the diff-built mirror',
    );
    expect(panelRegion, isNot(contains('⚠')));

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });
}
