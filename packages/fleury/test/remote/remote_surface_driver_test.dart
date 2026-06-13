// End-to-end test for RemoteTerminalDriver — the structured serve path.
// Covers: handshake establishes size+caps; structured INPUT_EVENT frames
// surface as events; presentPlan emits PLAN frames; and driving runTui
// through this driver produces PLAN frames instead of ANSI.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:fleury/src/remote/remote_transport.dart';
import 'package:test/test.dart';

class _FakeTransport implements RemoteFrameTransport {
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
      transport.emit(const InitFrame(
        size: CellSize(40, 10),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        protocolVersion: 1,
      ));
      await entered;
      expect(driver.wantsPresentationPlans, isFalse);
      driver.write('ansi');
      expect(transport.sent.whereType<OutputFrame>(), isNotEmpty,
          reason: 'v1 emits ANSI');
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

    test('presentPlan emits a PLAN frame', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entered = driver.enter(TerminalMode.interactive);
      transport.emit(_init);
      await entered;
      transport.sent.clear();
      driver.presentPlan(
        FramePresentationPlan(
          reason: 'test',
          fullRepaint: true,
          size: const CellSize(40, 10),
          damage: FramePresentationDamage(
            fullRepaint: true,
            requiresFullDiff: true,
            dirtyBounds: null,
            dirtyRows: TuiDirtyRows.full(10),
            source: FrameDamageSource.fullRepaint,
          ),
          dirtyRowModels: const [],
          metricsChanged: false,
          dirtyRowDiffTime: Duration.zero,
          spanBuildTime: Duration.zero,
        ),
      );
      final plans = transport.sent.whereType<PlanFrame>().toList();
      expect(plans, hasLength(1));
      expect(plans.single.plan.size, const CellSize(40, 10));
      expect(plans.single.plan.fullRepaint, isTrue);
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

    test('runTui drives the surface driver with PLAN frames, not ANSI', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      // runTui blocks until the session ends; feed INIT so enter() unblocks.
      scheduleMicrotask(() => transport.emit(_init));
      final done = runTui(
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
      expect(first.rows, isNotEmpty);
      // The "hello" text shows up in some row's spans.
      final text = first.rows
          .expand((r) => r.runs)
          .map((run) => run.text)
          .join();
      expect(text, contains('hello'));

      await transport.disconnect();
      await done;
    });
  });
}
