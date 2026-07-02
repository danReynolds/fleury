// End-to-end test for RemoteTerminalDriver — the structured serve path.
// Covers: handshake establishes size+caps; structured INPUT_EVENT frames
// surface as events; presentPlan emits PLAN frames; and driving runApp
// through this driver produces PLAN frames instead of ANSI.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

class _FakeTransport
    with SynchronousSendTransport
    implements RemoteFrameTransport {
  final _in = StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = [];
  bool closed = false;

  @override
  Stream<RemoteFrame> get incoming => _in.stream;

  @override
  void send(RemoteFrame frame) => sent.add(frame);

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void emit(RemoteFrame frame) {
    if (!_in.isClosed) _in.add(frame);
  }

  Future<void> disconnect() async {
    if (!_in.isClosed) await _in.close();
  }
}

const _init = InitFrame(
  size: CellSize(40, 10),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

void main() {
  group('RemoteTerminalDriver structured (serve) path', () {
    test('negotiates the plan path only after a v2 handshake', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      // Before INIT the version is unknown (defaults to v1, ANSI).
      expect(driver.wantsPresentationPlans, isFalse);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init); // v2
      await entered;
      expect(driver.wantsPresentationPlans, isTrue);
      await driver.restore();
    });

    test('a v1 handshake keeps the ANSI path', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(40, 10),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: 1,
        ),
      );
      await entered;
      expect(driver.wantsPresentationPlans, isFalse);
      driver.write('ansi');
      expect(
        transport.sent.whereType<OutputFrame>(),
        isNotEmpty,
        reason: 'v1 emits ANSI',
      );
      await driver.restore();
    });

    test('enter() blocks until INIT, then reports size + caps', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      expect(driver.size, const CellSize(40, 10));
      expect(driver.capabilities.colorMode, ColorMode.truecolor);
      expect(driver.isActive, isTrue);
      await driver.restore();
    });

    test('structured input events surface on the event stream', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.emit(const InputEventFrame(KeyEvent(keyCode: KeyCode.enter)));
      transport.emit(const InputEventFrame(PasteEvent('hi')));
      transport.emit(const InputEventFrame(ResizeEvent(CellSize(80, 24))));
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(3));
      expect(events[0], const KeyEvent(keyCode: KeyCode.enter));
      expect(events[1], const PasteEvent('hi'));
      expect(events[2], const ResizeEvent(CellSize(80, 24)));
      expect(driver.size, const CellSize(80, 24), reason: 'resize tracked');
      await sub.cancel();
      await driver.restore();
    });

    test('presentFrame emits a PLAN frame with the changed cells', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.sent.clear();
      final prev = CellBuffer(const CellSize(40, 10));
      final next = CellBuffer(const CellSize(40, 10));
      next.writeText(const CellOffset(0, 1), 'changed row');
      final plan = FramePresentationPlan(
        reason: 'test',
        fullRepaint: false,
        size: const CellSize(40, 10),
        damage: FramePresentationDamage(
          fullRepaint: false,
          requiresFullDiff: false,
          dirtyBounds: null,
          dirtyRows: TuiDirtyRows.fromRows(const [1], rowCount: 10),
          source: FrameDamageSource.paintDamage,
        ),
        dirtyRowModels: const [],
        metricsChanged: false,
        dirtyRowDiffTime: Duration.zero,
        spanBuildTime: Duration.zero,
      );
      driver.presentFrame(prev, next, plan);
      final plans = transport.sent.whereType<PlanFrame>().toList();
      expect(plans, hasLength(1));
      expect(plans.single.plan.size, const CellSize(40, 10));
      // Only the changed row ships.
      expect(plans.single.plan.patches.map((p) => p.row), contains(1));
      await driver.restore();
    });

    test('restore sends BYE and closes the events stream', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      var closed = false;
      driver.events.listen(null, onDone: () => closed = true);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      await driver.restore();
      expect(transport.sent.whereType<ByeFrame>(), isNotEmpty);
      expect(transport.closed, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue);
    });

    test(
      'runApp drives the surface driver with PLAN frames, not ANSI',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        // runApp blocks until the session ends; feed INIT so enter() unblocks.
        scheduleMicrotask(() => transport.emit(_init));
        final done = runApp(
          const Text('hello'),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        // Let the first frame render, then resize to force a second frame.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        transport.emit(const ResizeFrame(CellSize(50, 12)));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final plans = transport.sent.whereType<PlanFrame>().toList();
        expect(plans, isNotEmpty, reason: 'rendered through the surface');
        expect(
          transport.sent.whereType<OutputFrame>(),
          isEmpty,
          reason: 'no ANSI on the structured path',
        );
        // First plan repaints the whole 40x10 viewport with content.
        final first = plans.first.plan;
        expect(first.size, const CellSize(40, 10));
        expect(first.fullRepaint, isTrue);
        expect(first.patches, isNotEmpty);
        // The "hello" text shows up in some patch's runs.
        final text = first.patches
            .expand((p) => p.runs)
            .map((run) => run.text)
            .join();
        expect(text, contains('hello'));

        await transport.disconnect();
        await done;
      },
    );

    test(
      'runApp ships the app semantics as a decodable SemanticsFrame',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        scheduleMicrotask(() => transport.emit(_init));
        final done = runApp(
          Semantics(
            id: const SemanticNodeId('btn:save'),
            role: SemanticRole.button,
            label: 'Save',
            actions: const {SemanticAction.activate},
            onAction: (_) {},
            child: const Text('Save'),
          ),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final semFrames = transport.sent.whereType<SemanticsFrame>().toList();
        expect(
          semFrames,
          isNotEmpty,
          reason: 'the real run loop emits semantics on first paint',
        );
        // The first emission per connection is a FULL frame (patches need a base).
        final firstEnv =
            jsonDecode(utf8.decode(semFrames.first.json))
                as Map<String, Object?>;
        expect(firstEnv['mode'], 'full');

        // Decode the stream exactly as RemoteSurfaceClient does; the app's real
        // button — built by the framework, not hand-authored — comes through.
        final decoder = SemanticsWireDecoder();
        SemanticTree? tree;
        for (final frame in semFrames) {
          tree = decoder.apply(frame.json) ?? tree;
        }
        expect(tree, isNotNull);
        final button = tree!.root.selfAndDescendants.firstWhere(
          (n) => n.role == SemanticRole.button,
        );
        expect(button.label, 'Save');
        expect(button.actions, contains(SemanticAction.activate));

        await transport.disconnect();
        await done;
      },
    );

    test('a peer SEMANTIC_ACTION activates the live node', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      var activated = 0;
      scheduleMicrotask(() => transport.emit(_init));
      final done = runApp(
        Semantics(
          id: const SemanticNodeId('btn:go'),
          role: SemanticRole.button,
          label: 'Go',
          actions: const {SemanticAction.activate},
          onAction: (action) {
            if (action == SemanticAction.activate) activated += 1;
          },
          child: const Text('Go'),
        ),
        driver: driver,
        requireInteractiveTerminal: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The browser activates the button through its accessible DOM — the
      // path that was previously a no-op over the wire.
      transport.emit(
        const SemanticActionFrame(
          SemanticNodeId('btn:go'),
          SemanticAction.activate,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(activated, 1, reason: 'the semantic action drove the live tree');

      // An action for a missing node is a safe no-op (no crash).
      transport.emit(
        const SemanticActionFrame(
          SemanticNodeId('btn:missing'),
          SemanticAction.activate,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(activated, 1);

      await transport.disconnect();
      await done;
    });
  });

  group('hardening', () {
    test('clamps a hostile INIT grid size to the safe maximum', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(100000, 100000), // would be 10 billion cells
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        ),
      );
      await entered;
      expect(driver.size.cols, lessThanOrEqualTo(maxRemoteGridCols));
      expect(driver.size.rows, lessThanOrEqualTo(maxRemoteGridRows));
      await driver.restore();
    });

    test('clamps a hostile RESIZE and surfaces the clamped size', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.emit(const ResizeFrame(CellSize(999999, 1)));
      await Future<void>.delayed(Duration.zero);
      final resize = events.whereType<ResizeEvent>().single;
      expect(resize.size.cols, maxRemoteGridCols);
      expect(driver.size.cols, maxRemoteGridCols);
      await sub.cancel();
      await driver.restore();
    });

    test('clamps a hostile structured resize event too', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.emit(const InputEventFrame(ResizeEvent(CellSize(1, 888888))));
      await Future<void>.delayed(Duration.zero);
      final resize = events.whereType<ResizeEvent>().single;
      expect(resize.size.rows, maxRemoteGridRows);
      await sub.cancel();
      await driver.restore();
    });
  });

  group('inline image shipping', () {
    FramePresentationPlan fullPlan(CellSize size) => FramePresentationPlan(
      reason: 'test',
      fullRepaint: true,
      size: size,
      damage: FramePresentationDamage(
        fullRepaint: true,
        requiresFullDiff: true,
        dirtyBounds: null,
        dirtyRows: TuiDirtyRows.full(size.rows),
        source: FrameDamageSource.fullRepaint,
      ),
      dirtyRowModels: const [],
      metricsChanged: false,
      dirtyRowDiffTime: Duration.zero,
      spanBuildTime: Duration.zero,
    );

    CellBuffer withImage(List<int> bytes, {int at = 0}) {
      return CellBuffer(const CellSize(40, 10))..writeImage(
        CellOffset(at, 0),
        Uint8List.fromList(bytes),
        width: 3,
        height: 2,
      );
    }

    Future<RemoteTerminalDriver> connected(_FakeTransport transport) async {
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.sent.clear();
      return driver;
    }

    test('ships bytes once while an image stays on screen, then re-ships when '
        'it leaves and returns', () async {
      final transport = _FakeTransport();
      final driver = await connected(transport);
      final size = const CellSize(40, 10);
      final empty = CellBuffer(size);

      // Frame 1: image appears → bytes + plan.
      driver.presentFrame(empty, withImage([1, 2, 3, 4]), fullPlan(size));
      expect(transport.sent.whereType<InlineImageFrame>(), hasLength(1));
      transport.sent.clear();

      // Frame 2: still on screen → plan only, no re-ship.
      driver.presentFrame(
        withImage([1, 2, 3, 4]),
        withImage([1, 2, 3, 4]),
        fullPlan(size),
      );
      expect(
        transport.sent.whereType<InlineImageFrame>(),
        isEmpty,
        reason: 'an on-screen image ships once',
      );
      transport.sent.clear();

      // Frame 3: image gone.
      driver.presentFrame(withImage([1, 2, 3, 4]), empty, fullPlan(size));
      expect(transport.sent.whereType<InlineImageFrame>(), isEmpty);
      transport.sent.clear();

      // Frame 4: returns → re-shipped (the client may have evicted its blob).
      driver.presentFrame(empty, withImage([1, 2, 3, 4]), fullPlan(size));
      expect(
        transport.sent.whereType<InlineImageFrame>(),
        hasLength(1),
        reason: 'a re-appearing image is re-sent',
      );

      await driver.restore();
    });

    test(
      'the same bytes drawn twice ship once but yield two placements',
      () async {
        final transport = _FakeTransport();
        final driver = await connected(transport);
        final size = const CellSize(40, 10);
        final next = CellBuffer(size)
          ..writeImage(
            const CellOffset(0, 0),
            Uint8List.fromList([9, 9, 9]),
            width: 2,
            height: 2,
          )
          ..writeImage(
            const CellOffset(10, 0),
            Uint8List.fromList([9, 9, 9]),
            width: 2,
            height: 2,
          );

        driver.presentFrame(CellBuffer(size), next, fullPlan(size));

        expect(
          transport.sent.whereType<InlineImageFrame>(),
          hasLength(1),
          reason: 'identical bytes ship once',
        );
        final plan = transport.sent.whereType<PlanFrame>().single.plan;
        expect(
          plan.placements,
          hasLength(2),
          reason: 'each draw is its own placement',
        );
        expect(plan.placements.map((p) => p.col).toSet(), {0, 10});

        await driver.restore();
      },
    );
  });
}
