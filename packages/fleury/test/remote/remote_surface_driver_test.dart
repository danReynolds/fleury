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

/// A transport whose RESULT-frame delivery FAILS — the sink faults inside the
/// serialize link, exercising that a fault in the result-delivery path can't
/// wedge the queue. Every other frame (PLAN/SEMANTICS/BYE) is sent normally so
/// rendering is undisturbed.
class _ResultSendFailsTransport extends _FakeTransport {
  @override
  void send(RemoteFrame frame) {
    if (frame is SemanticActionResultFrame) {
      throw StateError('result delivery failed');
    }
    super.send(frame);
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

    test('presentFrame threads the planner damage; plan bytes are byte-'
        'identical to the unbounded build', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.sent.clear();
      final prev = CellBuffer(const CellSize(8, 3));
      final next = CellBuffer(const CellSize(8, 3));
      next.writeText(
        const CellOffset(0, 1),
        'hi',
        style: const CellStyle(bold: true),
      );
      driver.presentFrame(
        prev,
        next,
        _steadyStatePlan(
          const CellSize(8, 3),
          TuiDirtyRows.fromRows(const [1], rowCount: 3),
        ),
      );
      final emitted = encodeRemotePlan(
        transport.sent.whereType<PlanFrame>().single.plan,
      );
      // Sound damage must not change the wire: the emitted plan matches the
      // unbounded build byte for byte...
      expect(
        emitted,
        encodeRemotePlan(buildRemotePlan(prev, next, fullRepaint: false)),
      );
      // ...and the exact bytes the pre-damage-hint driver emitted for this
      // frame (captured as a fixture before buildRemotePlan learned
      // dirtyRows). A codec wire change legitimately updates this pin.
      expect(emitted, [
        0, 8, 3, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0, 2, 104, 105, 0, //
      ]);
      await driver.restore();
    });

    test(
      'presentFrame surfaces under-covering damage via the debug oracle',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final entered = driver.enter(TerminalMode.interactive);
        transport.emit(_init);
        await entered;
        transport.sent.clear();
        final prev = CellBuffer(const CellSize(8, 3));
        final next = CellBuffer(const CellSize(8, 3));
        next.writeText(const CellOffset(0, 1), 'hi');
        // Deliberately UNSOUND damage (misses the changed row 1). The driver
        // hands the planner's damage straight to buildRemotePlan — a
        // wire-correctness boundary — so in debug the oracle must trip
        // BEFORE an incomplete plan can desync the peer's mirror. This both
        // proves the thread-through (a dropped hint would diff fully and
        // never diverge) and pins the loud failure mode for a broken
        // damage producer.
        expect(
          () => driver.presentFrame(
            prev,
            next,
            _steadyStatePlan(
              const CellSize(8, 3),
              TuiDirtyRows.fromRows(const [2], rowCount: 3),
            ),
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message,
              'message',
              contains('under-covers'),
            ),
          ),
        );
        await driver.restore();
      },
    );

    test(
      'a second INIT mid-session does not re-negotiate the protocol',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final entered = driver.enter(TerminalMode.interactive);
        transport.emit(_init); // v3 → structured path
        await entered;
        expect(driver.wantsPresentationPlans, isTrue);

        // A buggy/hostile peer sends a v1 INIT after the handshake.
        transport.emit(
          const InitFrame(
            size: CellSize(40, 10),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            protocolVersion: 1,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          driver.wantsPresentationPlans,
          isTrue,
          reason: 'the negotiated protocol is frozen; a repeat INIT is ignored',
        );
        await driver.restore();
      },
    );

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

  // Regression guard for the serve OSC 8 bug: the browser's `hyperlinks`
  // capability was never propagated through INIT, so a served MarkdownText read
  // MediaQuery.capabilitiesOf(context).hyperlinks == false and produced links
  // that rendered underlined-but-not-clickable. The previous full-loop coverage
  // FAKED a hyperlinks:true MediaQuery, so nothing exercised the peer's INIT
  // capability actually reaching the app. These do.
  group('hyperlinks capability propagation (OSC 8 over serve)', () {
    test('an INIT declaring hyperlinks lights up surfaceCapabilities '
        '(browser-style peer with images=placements)', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      // images != null → the peer-surface-capabilities branch.
      transport.emit(
        const InitFrame(
          size: CellSize(40, 10),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          images: InlineImageSupport.placements,
          hyperlinks: true,
        ),
      );
      await entered;
      expect(driver.surfaceCapabilities.hyperlinks, isTrue);
      await driver.restore();
    });

    test(
      'an INIT declaring hyperlinks lights up surfaceCapabilities through the '
      'terminal projection too (no images= param)',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final entered = driver.enter(TerminalMode.interactive);
        // images == null → surfaceCapabilities falls back to
        // _capabilities.toSurfaceCapabilities(); the field is threaded into
        // BOTH objects, so this branch reflects it as well.
        transport.emit(
          const InitFrame(
            size: CellSize(40, 10),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            hyperlinks: true,
          ),
        );
        await entered;
        expect(driver.surfaceCapabilities.hyperlinks, isTrue);
        await driver.restore();
      },
    );

    test(
      'hyperlinks:false and an absent field both leave the capability false',
      () async {
        const inits = [
          InitFrame(
            size: CellSize(40, 10),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            images: InlineImageSupport.placements,
            hyperlinks: false,
          ),
          // An older peer that never learned the field.
          InitFrame(
            size: CellSize(40, 10),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            images: InlineImageSupport.placements,
          ),
        ];
        for (final init in inits) {
          final transport = _FakeTransport();
          final driver = RemoteTerminalDriver(transport);
          final entered = driver.enter(TerminalMode.interactive);
          transport.emit(init);
          await entered;
          expect(driver.surfaceCapabilities.hyperlinks, isFalse);
          await driver.restore();
        }
      },
    );

    // The TRUE end-to-end guard: a real server-side producer reading the
    // propagated capability through MediaQuery must set a linkUri that then
    // rides the v4 wire. Exercises the WHOLE chain — peer INIT → driver caps →
    // runApp MediaQuery → producer gate → PLAN bytes — with NO faked capability.
    // _LinkProbe stands in for MarkdownText (which lives in fleury_widgets and
    // can't be imported here without an implementation_imports violation); it
    // mirrors MarkdownText's exact gate.
    test(
      'a peer declaring hyperlinks makes the producer emit a linkUri that rides '
      'the v4 wire',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        scheduleMicrotask(
          () => transport.emit(
            const InitFrame(
              size: CellSize(40, 10),
              colorMode: ColorMode.truecolor,
              imageProtocol: ImageProtocol.halfBlock,
              tmuxPassthrough: false,
              images: InlineImageSupport.placements,
              hyperlinks: true,
              // protocolVersion defaults to v4 → wantsHyperlinks → the plan
              // serializes the link.
            ),
          ),
        );
        final done = runApp(
          const _LinkProbe('https://example.com'),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final plan = transport.sent.whereType<PlanFrame>().first.plan;
        expect(
          plan.styleTable.any((s) => s.linkUri == 'https://example.com'),
          isTrue,
          reason: 'the producer read hyperlinks==true and attached the URI',
        );
        // And the bytes actually rode the wire (v4 serialization), not just the
        // in-memory plan: round-trip through the codec and confirm it survives.
        final roundTripped = decodeRemotePlan(encodeRemotePlan(plan));
        expect(
          roundTripped.styleTable.any(
            (s) => s.linkUri == 'https://example.com',
          ),
          isTrue,
          reason: 'the linkUri serialized onto the wire',
        );

        await transport.disconnect();
        await done;
      },
    );

    test(
      'a peer that does NOT declare hyperlinks makes the same producer emit no '
      'linkUri (the capability gates production — not a fake)',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        scheduleMicrotask(
          () => transport.emit(
            const InitFrame(
              size: CellSize(40, 10),
              colorMode: ColorMode.truecolor,
              imageProtocol: ImageProtocol.halfBlock,
              tmuxPassthrough: false,
              images: InlineImageSupport.placements,
              // hyperlinks omitted → false, the pre-fix serve default.
            ),
          ),
        );
        final done = runApp(
          const _LinkProbe('https://example.com'),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final plan = transport.sent.whereType<PlanFrame>().first.plan;
        expect(
          plan.styleTable.any((s) => s.linkUri != null),
          isFalse,
          reason: 'no capability → the producer never attaches a URI',
        );

        await transport.disconnect();
        await done;
      },
    );
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

    test('ships bytes once, then not while the peer still caches them '
        '(no re-ship on leave-and-return under the cache bound)', () async {
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

      // Frame 3: image gone. The peer keeps the blob cached (it evicts only
      // over its cache bound), so the app keeps believing it's held.
      driver.presentFrame(withImage([1, 2, 3, 4]), empty, fullPlan(size));
      expect(transport.sent.whereType<InlineImageFrame>(), isEmpty);
      transport.sent.clear();

      // Frame 4: returns → NOT re-shipped; the client still holds the bytes.
      driver.presentFrame(empty, withImage([1, 2, 3, 4]), fullPlan(size));
      expect(
        transport.sent.whereType<InlineImageFrame>(),
        isEmpty,
        reason:
            'the peer never evicted the blob (well under the cache bound), '
            'so re-shipping would be wasted bandwidth — this is what stops '
            'an animation from re-sending every frame on each loop',
      );

      await driver.restore();
    });

    test('re-ships an id only after the peer would have evicted it '
        '(cache bound exceeded)', () async {
      final transport = _FakeTransport();
      final driver = await connected(transport);
      final size = const CellSize(40, 10);
      final empty = CellBuffer(size);

      // The image under test.
      final target = [7, 7, 7, 7];
      driver.presentFrame(empty, withImage(target), fullPlan(size));
      expect(transport.sent.whereType<InlineImageFrame>(), hasLength(1));
      transport.sent.clear();

      // Push > 512 OTHER distinct images through, each on its own frame with
      // the target absent — the peer (and the app's mirror) evicts the
      // longest-unplaced ids first, so the target eventually falls out.
      for (var i = 0; i < 600; i++) {
        driver.presentFrame(
          empty,
          withImage([i, i >> 8, 1, 2]),
          fullPlan(size),
        );
      }
      transport.sent.clear();

      // The target returns after being evicted → re-shipped.
      driver.presentFrame(empty, withImage(target), fullPlan(size));
      expect(
        transport.sent.whereType<InlineImageFrame>(),
        hasLength(1),
        reason: 'an id the peer evicted (past the cache bound) is re-sent',
      );

      await driver.restore();
    });

    test('re-ships an id after byte-budget eviction', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(
        transport,
        imageCachePolicy: const InlineImageCachePolicy(
          maxEntries: 512,
          maxBytes: 8,
        ),
      );
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.sent.clear();
      final size = const CellSize(40, 10);
      final empty = CellBuffer(size);
      final target = [1, 2, 3, 4, 5, 6];
      final replacement = [7, 8, 9, 10, 11, 12];

      driver.presentFrame(empty, withImage(target), fullPlan(size));
      expect(transport.sent.whereType<InlineImageFrame>(), hasLength(1));
      transport.sent.clear();

      driver.presentFrame(withImage(target), empty, fullPlan(size));
      driver.presentFrame(empty, withImage(replacement), fullPlan(size));
      transport.sent.clear();

      driver.presentFrame(empty, withImage(target), fullPlan(size));
      expect(
        transport.sent.whereType<InlineImageFrame>(),
        hasLength(1),
        reason: 'the oldest stale id exceeded the shared byte budget',
      );

      await driver.restore();
    });

    test(
      'one plan drops image placements beyond the shared byte budget',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(
          transport,
          imageCachePolicy: const InlineImageCachePolicy(
            maxEntries: 512,
            maxBytes: 8,
          ),
        );
        final entered = driver.enter(TerminalMode.interactive);
        transport.emit(_init);
        await entered;
        transport.sent.clear();
        const size = CellSize(40, 10);
        final next = CellBuffer(size)
          ..writeImage(
            const CellOffset(0, 0),
            Uint8List.fromList([1, 2, 3, 4, 5, 6]),
            width: 2,
            height: 2,
          )
          ..writeImage(
            const CellOffset(10, 0),
            Uint8List.fromList([7, 8, 9, 10, 11, 12]),
            width: 2,
            height: 2,
          );

        driver.presentFrame(CellBuffer(size), next, fullPlan(size));

        final images = transport.sent.whereType<InlineImageFrame>().toList();
        final plan = transport.sent.whereType<PlanFrame>().single.plan;
        expect(images, hasLength(1));
        expect(plan.placements, hasLength(1));
        expect(plan.placements.single.id, images.single.id);
        expect(
          images.single.bytes.length,
          lessThanOrEqualTo(8),
          reason: 'the emitted working set remains within the cache ceiling',
        );

        await driver.restore();
      },
    );

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

  // F16: the raw serve-wire path must serialize inbound semantic actions the
  // way the MCP path does. Fire-and-forget let action N+1 snapshot the tree +
  // invoke while action N's async invocation was still in flight, so an agent
  // that sent setValue(field) then activate(submit) back-to-back could submit
  // the pre-mutation value and get its RESULT frames out of order.
  group('semantic action serialization (F16)', () {
    test('a following activate observes the value a preceding setValue set '
        '(not the pre-mutation tree)', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      // A real onSetValue mutates after an await; gate it so the race is
      // deterministic. Under the old fire-and-forget path the submit would
      // run while this handler is still parked here, reading the empty value.
      final setValueGate = Completer<void>();
      var fieldValue = '';
      String? observedBySubmit;
      scheduleMicrotask(() => transport.emit(_init));
      final done = runApp(
        Column(
          children: [
            Semantics(
              id: const SemanticNodeId('field'),
              role: SemanticRole.textField,
              actions: const {SemanticAction.setValue},
              onSetValue: (v) async {
                await setValueGate.future;
                fieldValue = (v ?? '') as String;
              },
              child: const Text('field'),
            ),
            Semantics(
              id: const SemanticNodeId('submit'),
              role: SemanticRole.button,
              actions: const {SemanticAction.activate},
              onAction: (a) async {
                observedBySubmit = fieldValue;
              },
              child: const Text('submit'),
            ),
          ],
        ),
        driver: driver,
        requireInteractiveTerminal: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Both actions arrive before the setValue handler is released.
      transport.emit(
        const SemanticActionFrame(
          SemanticNodeId('field'),
          SemanticAction.setValue,
          value: 'hello',
        ),
      );
      transport.emit(
        const SemanticActionFrame(
          SemanticNodeId('submit'),
          SemanticAction.activate,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // The submit is chained behind the still-parked setValue, so it has
      // not run yet (fire-and-forget would already have read the empty value).
      expect(
        observedBySubmit,
        isNull,
        reason: 'the activate waits for the setValue link to complete',
      );

      setValueGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        observedBySubmit,
        'hello',
        reason: 'the activate ran only after setValue mutated the value',
      );

      await transport.disconnect();
      await done;
    });

    test(
      'a throwing action does not wedge the queue for the next action',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        var okRan = 0;
        scheduleMicrotask(() => transport.emit(_init));
        final done = runApp(
          Column(
            children: [
              Semantics(
                id: const SemanticNodeId('boom'),
                role: SemanticRole.button,
                actions: const {SemanticAction.activate},
                onAction: (a) async {
                  throw StateError('boom');
                },
                child: const Text('boom'),
              ),
              Semantics(
                id: const SemanticNodeId('ok'),
                role: SemanticRole.button,
                actions: const {SemanticAction.activate},
                onAction: (a) async {
                  okRan++;
                },
                child: const Text('ok'),
              ),
            ],
          ),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        transport.emit(
          const SemanticActionFrame(
            SemanticNodeId('boom'),
            SemanticAction.activate,
          ),
        );
        transport.emit(
          const SemanticActionFrame(
            SemanticNodeId('ok'),
            SemanticAction.activate,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          okRan,
          1,
          reason: 'the second action ran even though the first threw',
        );
        // The first action fails LOUDLY (a failed RESULT), it is not swallowed —
        // and the chain still delivered the second action's completed RESULT.
        final results = transport.sent
            .whereType<SemanticActionResultFrame>()
            .toList();
        expect(results.map((r) => r.id.value), ['boom', 'ok']);
        expect(results.first.status, SemanticActionInvocationStatus.failed);
        expect(results.last.status, SemanticActionInvocationStatus.completed);

        await transport.disconnect();
        await done;
      },
    );

    test(
      'RESULT frames return in submission order when the first is slower',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final gateA = Completer<void>();
        scheduleMicrotask(() => transport.emit(_init));
        final done = runApp(
          Column(
            children: [
              Semantics(
                id: const SemanticNodeId('a'),
                role: SemanticRole.button,
                actions: const {SemanticAction.activate},
                onAction: (act) async {
                  await gateA.future; // slow
                },
                child: const Text('a'),
              ),
              Semantics(
                id: const SemanticNodeId('b'),
                role: SemanticRole.button,
                actions: const {SemanticAction.activate},
                onAction: (act) async {}, // fast
                child: const Text('b'),
              ),
            ],
          ),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        transport.emit(
          const SemanticActionFrame(
            SemanticNodeId('a'),
            SemanticAction.activate,
          ),
        );
        transport.emit(
          const SemanticActionFrame(
            SemanticNodeId('b'),
            SemanticAction.activate,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // B is chained behind the parked A, so nothing has completed — B does not
        // race ahead and ship its RESULT first.
        expect(
          transport.sent.whereType<SemanticActionResultFrame>(),
          isEmpty,
          reason: 'B must not complete ahead of the still-running A',
        );

        gateA.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final ids = transport.sent
            .whereType<SemanticActionResultFrame>()
            .map((r) => r.id.value)
            .toList();
        expect(ids, [
          'a',
          'b',
        ], reason: 'RESULT frames ship in submission order');

        await transport.disconnect();
        await done;
      },
    );

    test('a queued action resolves against the LIVE tree after an intervening '
        'resize/rebuild', () async {
      // The link reads frameDriver.rootElement at EXECUTION time, not at action
      // arrival — so a rebuild (handleResize -> updateRoot) between a queued
      // action's arrival and its turn can't strand it on a stale root. (The
      // root wrapper is reused across a same-widget resize, so this is a
      // non-regression guard for the queue<->rebuild interaction; the rarer
      // root-Element REPLACEMENT branch that would distinguish old-vs-new isn't
      // reachable through runApp's public surface, so the live-root read is
      // additionally covered by construction + parity with the semantics
      // pipeline's `readRoot: () => rootElement`.)
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final gate = Completer<void>();
      var targetRan = 0;
      scheduleMicrotask(() => transport.emit(_init));
      final done = runApp(
        Column(
          children: [
            Semantics(
              id: const SemanticNodeId('slow'),
              role: SemanticRole.button,
              actions: const {SemanticAction.activate},
              onAction: (act) async {
                await gate.future;
              },
              child: const Text('slow'),
            ),
            Semantics(
              id: const SemanticNodeId('target'),
              role: SemanticRole.button,
              actions: const {SemanticAction.activate},
              onAction: (act) async {
                targetRan++;
              },
              child: const Text('target'),
            ),
          ],
        ),
        driver: driver,
        requireInteractiveTerminal: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 'slow' parks the queue; 'target' chains behind it.
      transport.emit(
        const SemanticActionFrame(
          SemanticNodeId('slow'),
          SemanticAction.activate,
        ),
      );
      transport.emit(
        const SemanticActionFrame(
          SemanticNodeId('target'),
          SemanticAction.activate,
        ),
      );
      // A rebuild lands while the queue is parked.
      transport.emit(const ResizeFrame(CellSize(50, 20)));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        targetRan,
        1,
        reason: 'the queued action ran against the live post-rebuild tree',
      );

      await transport.disconnect();
      await done;
    });

    test('a fault delivering a RESULT does not wedge the queue', () async {
      // The RESULT send throws inside the link; the link must still RESOLVE
      // (its fault-safe catch routes the error to the reporter without
      // rethrowing) so the next queued action still runs.
      final transport = _ResultSendFailsTransport();
      final driver = RemoteTerminalDriver(transport);
      var ranA = 0;
      var ranB = 0;
      scheduleMicrotask(() => transport.emit(_init));
      final done = runApp(
        Column(
          children: [
            Semantics(
              id: const SemanticNodeId('a'),
              role: SemanticRole.button,
              actions: const {SemanticAction.activate},
              onAction: (act) async {
                ranA++;
              },
              child: const Text('a'),
            ),
            Semantics(
              id: const SemanticNodeId('b'),
              role: SemanticRole.button,
              actions: const {SemanticAction.activate},
              onAction: (act) async {
                ranB++;
              },
              child: const Text('b'),
            ),
          ],
        ),
        driver: driver,
        requireInteractiveTerminal: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      transport.emit(
        const SemanticActionFrame(SemanticNodeId('a'), SemanticAction.activate),
      );
      transport.emit(
        const SemanticActionFrame(SemanticNodeId('b'), SemanticAction.activate),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ranA, 1, reason: 'first action ran');
      expect(
        ranB,
        1,
        reason: 'the RESULT-delivery fault did not wedge the queue',
      );

      await transport.disconnect();
      await done;
    });

    test(
      'a stalled action bounds the pending queue and reports one overflow',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final firstActionGate = Completer<void>();
        var invocations = 0;
        scheduleMicrotask(() => transport.emit(_init));
        final done = runApp(
          Semantics(
            id: const SemanticNodeId('slow'),
            role: SemanticRole.button,
            actions: const {SemanticAction.activate},
            onAction: (action) async {
              invocations++;
              if (invocations == 1) await firstActionGate.future;
            },
            child: const Text('slow'),
          ),
          driver: driver,
          requireInteractiveTerminal: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        const admitted = 64;
        for (var i = 0; i < admitted + 4; i++) {
          transport.emit(
            const SemanticActionFrame(
              SemanticNodeId('slow'),
              SemanticAction.activate,
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));

        var results = transport.sent
            .whereType<SemanticActionResultFrame>()
            .toList();
        expect(invocations, 1, reason: 'the first admitted action is parked');
        expect(
          results,
          isEmpty,
          reason: 'the overflow marker must not pass admitted requests',
        );

        firstActionGate.complete();
        final stopwatch = Stopwatch()..start();
        while (stopwatch.elapsed < const Duration(seconds: 2)) {
          results = transport.sent
              .whereType<SemanticActionResultFrame>()
              .toList();
          if (results.length == admitted + 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(invocations, admitted);
        expect(
          results.map((frame) => frame.status),
          [
            ...List<SemanticActionInvocationStatus>.filled(
              admitted,
              SemanticActionInvocationStatus.completed,
            ),
            SemanticActionInvocationStatus.failed,
          ],
          reason: 'one overflow result follows every earlier admitted result',
        );

        // Draining below the cap opens a fresh epoch; later input is admitted
        // instead of leaving the connection permanently rate-limited.
        transport.emit(
          const SemanticActionFrame(
            SemanticNodeId('slow'),
            SemanticAction.activate,
          ),
        );
        final acceptanceStopwatch = Stopwatch()..start();
        while (invocations == admitted &&
            acceptanceStopwatch.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(invocations, admitted + 1);
        final finalResultStopwatch = Stopwatch()..start();
        while (finalResultStopwatch.elapsed < const Duration(seconds: 2)) {
          final completed = transport.sent
              .whereType<SemanticActionResultFrame>()
              .where(
                (frame) =>
                    frame.status == SemanticActionInvocationStatus.completed,
              )
              .length;
          if (completed == admitted + 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(
          transport.sent.whereType<SemanticActionResultFrame>().where(
            (frame) => frame.status == SemanticActionInvocationStatus.completed,
          ),
          hasLength(admitted + 1),
        );

        await transport.disconnect();
        await done;
      },
    );
  });
}

/// A minimal server-side producer that mirrors MarkdownText's OSC 8 gate
/// (markdown_text.dart): it attaches a real [CellStyle.linkUri] ONLY when the
/// surface reports it can render links. Used to exercise capability propagation
/// end-to-end through a real runApp + driver + MediaQuery, without reaching
/// across the package boundary into fleury_widgets.
final class _LinkProbe extends StatelessWidget {
  const _LinkProbe(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    final hyperlinks = MediaQuery.capabilitiesOf(context).hyperlinks;
    return Text(
      'link',
      style: hyperlinks
          ? CellStyle(underline: true, linkUri: url)
          : CellStyle.empty,
    );
  }
}

/// A steady-state (non-repaint) presentation plan whose damage carries
/// [dirtyRows] — the shape the runtime planner hands presentFrame.
FramePresentationPlan _steadyStatePlan(CellSize size, TuiDirtyRows dirtyRows) =>
    FramePresentationPlan(
      reason: 'test',
      fullRepaint: false,
      size: size,
      damage: FramePresentationDamage(
        fullRepaint: false,
        requiresFullDiff: false,
        dirtyBounds: null,
        dirtyRows: dirtyRows,
        source: FrameDamageSource.paintDamage,
      ),
      dirtyRowModels: const [],
      metricsChanged: false,
      dirtyRowDiffTime: Duration.zero,
      spanBuildTime: Duration.zero,
    );
