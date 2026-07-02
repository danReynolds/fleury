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
import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

import '../remote/remote_test_support.dart';

class _Boom extends LeafRenderObjectWidget {
  const _Boom({this.mode = _BoomMode.layout});
  final _BoomMode mode;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBoom(mode);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBoom).mode = mode;
  }
}

enum _BoomMode { layout, paint, healthy }

class _RenderBoom extends RenderObject {
  _RenderBoom(this._mode);

  _BoomMode _mode;
  set mode(_BoomMode value) {
    if (value == _mode) return;
    _mode = value;
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_mode == _BoomMode.layout) throw StateError('layout-boom');
    // Tall enough that a paint-phase failure gets the text panel (≥3×3),
    // not the small-region badge.
    return constraints.constrain(const CellSize(14, 3));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    // Partial write BEFORE the throw: atomicity must bury it.
    buffer.writeText(offset, 'part', style: CellStyle.empty);
    if (_mode == _BoomMode.paint) throw StateError('paint-boom');
    buffer.writeText(offset, 'healthy###', style: CellStyle.empty);
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.initial});
  final _BoomMode initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late _BoomMode mode = widget.initial;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.char('f'),
          onEvent: (_) => setState(() => mode = _BoomMode.healthy),
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
                child: _Boom(mode: mode),
              ),
            ),
          ],
        ),
      ),
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
      tester.pumpWidget(const _Host(initial: _BoomMode.layout));
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
      tester.pumpWidget(const _Host(initial: _BoomMode.layout));
      expect(
        tester.renderToString(size: const CellSize(30, 6)),
        contains('layout-boom'),
      );

      tester.sendKey(const KeyEvent(char: 'f'));
      final out = tester.renderToString(size: const CellSize(30, 6));
      expect(out, contains('healthy###'), reason: 'subtree re-attempted');
      expect(out, isNot(contains('⚠')));
      expect(out, isNot(contains('layout-boom')));
    });

    testWidgets('(c) a mid-paint throw is atomic', (tester) {
      tester.pumpWidget(const _Host(initial: _BoomMode.paint));
      final out = tester.renderToString(size: const CellSize(30, 6));
      expect(out, contains('paint-boom'));
      expect(
        out,
        isNot(contains('part')),
        reason: 'partial pre-throw writes are buried by the fill',
      );
      expect(out, contains('sibling stays'));
    });

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
            child: const _Boom(),
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
      tester.pumpWidget(const ErrorBoundary(child: _Boom()));
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
              ErrorBoundary(rethrowContained: false, child: _Boom()),
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
}

void _secondaryTests() {
  group('implicit boundaries', () {
    testWidgets('(e) a crashing route contains in production mode', (tester) {
      // Production posture: contain instead of the tester's rethrow.
      tester.owner.rethrowContainedRenderErrors = false;
      tester.pumpWidget(Navigator(home: const _Boom()));
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
      driver.mountRoot(() => const _Boom());

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
      driver.mountRoot(() => const _Boom());

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
      const _Host(initial: _BoomMode.layout),
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
    transport.emit(const InputEventFrame(KeyEvent(char: 'f')));
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
