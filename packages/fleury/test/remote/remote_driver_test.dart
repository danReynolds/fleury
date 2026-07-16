// End-to-end test for RemoteTerminalDriver against an in-memory
// transport. Covers the parts that matter for `fleury shell` and the
// future `fleury serve`: handshake establishes size+capabilities,
// input bytes parse into events, resize frames surface as events,
// outbound writes become OUTPUT frames, peer disconnect closes the
// events stream.

import 'dart:async';
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

  void emit(RemoteFrame frame) => _in.add(frame);
  void emitError(Object error) => _in.addError(error, StackTrace.current);
  Future<void> disconnect() async {
    if (!_in.isClosed) await _in.close();
  }
}

void main() {
  group('RemoteTerminalDriver', () {
    test(
      'enter() blocks until INIT lands, then reports its size+caps',
      (() async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);

        final entering = driver.enter(TerminalMode.interactive);
        // Drive the handshake from the peer side.
        transport.emit(
          const InitFrame(
            size: CellSize(132, 43),
            colorMode: ColorMode.truecolor,
            glyphTier: GlyphTier.ascii,
            imageProtocol: ImageProtocol.kitty,
            tmuxPassthrough: true,
            protocolVersion: 1,
          ),
        );
        await entering;

        expect(driver.isActive, isTrue);
        expect(driver.size, const CellSize(132, 43));
        expect(driver.capabilities.colorMode, ColorMode.truecolor);
        expect(driver.capabilities.glyphTier, GlyphTier.ascii);
        expect(driver.capabilities.imageProtocol, ImageProtocol.kitty);
        expect(driver.capabilities.tmuxPassthrough, isTrue);

        await driver.restore();
      }),
    );

    test('inbound INPUT bytes parse into events', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final events = <TuiEvent>[];
      final eventSub = driver.events.listen(events.add);

      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: 1,
        ),
      );
      await entering;

      // 'q' — printable ASCII routes as TextInputEvent.
      transport.emit(InputFrame(Uint8List.fromList([0x71])));
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TextInputEvent>().map((e) => e.text), ['q']);

      // ESC [ A — arrow up: keyed event.
      transport.emit(InputFrame(Uint8List.fromList([0x1B, 0x5B, 0x41])));
      await Future<void>.delayed(Duration.zero);
      final chords = events.whereType<KeyEvent>().toList();
      expect(chords.last.keyCode, KeyCode.arrowUp);

      await eventSub.cancel();
      await driver.restore();
    });

    test(
      'legacy raw INPUT flushes a lone ESC after the idle debounce',
      () async {
        final saved = RemoteTerminalDriver.inputFlushDelay;
        RemoteTerminalDriver.inputFlushDelay = const Duration(milliseconds: 5);
        addTearDown(() => RemoteTerminalDriver.inputFlushDelay = saved);
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final events = <TuiEvent>[];
        final eventSub = driver.events.listen(events.add);

        final entering = driver.enter(TerminalMode.interactive);
        transport.emit(
          const InitFrame(
            size: CellSize(80, 24),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            protocolVersion: 1,
          ),
        );
        await entering;
        transport.emit(InputFrame(Uint8List.fromList([0x1B])));

        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(events, [const KeyEvent(keyCode: KeyCode.escape)]);

        await eventSub.cancel();
        await driver.restore();
      },
    );

    test(
      'legacy raw INPUT finalizes pending paste before disconnect',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final events = <TuiEvent>[];
        final done = Completer<void>();
        final eventSub = driver.events.listen(
          events.add,
          onDone: done.complete,
        );

        final entering = driver.enter(TerminalMode.interactive);
        transport.emit(
          const InitFrame(
            size: CellSize(80, 24),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            protocolVersion: 1,
          ),
        );
        await entering;
        transport.emit(
          InputFrame(Uint8List.fromList('\x1B[200~abc'.codeUnits)),
        );
        await Future<void>.delayed(Duration.zero);

        await transport.disconnect();
        await done.future.timeout(const Duration(seconds: 1));

        expect(events.whereType<PasteEvent>(), [const PasteEvent('abc')]);
        await eventSub.cancel();
        await driver.restore();
      },
    );

    test(
      'structured negotiation rejects the legacy raw INPUT channel',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final events = <TuiEvent>[];
        final eventSub = driver.events.listen(events.add);

        final entering = driver.enter(TerminalMode.interactive);
        transport.emit(
          const InitFrame(
            size: CellSize(80, 24),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            protocolVersion: remoteProtocolVersion,
          ),
        );
        await entering;
        transport.emit(InputFrame(Uint8List.fromList('q'.codeUnits)));
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(events, isEmpty);
        await eventSub.cancel();
        await driver.restore();
      },
    );

    test(
      'remote grid clamping enforces the total cell allocation budget',
      () async {
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final entering = driver.enter(TerminalMode.interactive);
        transport.emit(
          const InitFrame(
            size: CellSize(2000, 1000),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            protocolVersion: remoteProtocolVersion,
          ),
        );
        await entering;

        expect(driver.size.cols, lessThanOrEqualTo(maxRemoteGridCols));
        expect(driver.size.rows, lessThanOrEqualTo(maxRemoteGridRows));
        expect(
          driver.size.cols * driver.size.rows,
          lessThanOrEqualTo(maxRemoteGridCells),
        );
        await driver.restore();
      },
    );

    test('RESIZE frame surfaces as ResizeEvent and updates size', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final resizes = <CellSize>[];
      final eventSub = driver.events.listen((e) {
        if (e is ResizeEvent) resizes.add(e.size);
      });

      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: 1,
        ),
      );
      await entering;

      transport.emit(const ResizeFrame(CellSize(120, 40)));
      await Future<void>.delayed(Duration.zero);

      expect(driver.size, const CellSize(120, 40));
      expect(resizes, [const CellSize(120, 40)]);

      await eventSub.cancel();
      await driver.restore();
    });

    test('write() emits an OUTPUT frame with UTF-8 bytes', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);

      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: 1,
        ),
      );
      await entering;

      driver.write('héllo ★');
      // Skip the INIT response (the driver never sends one) — only
      // OUTPUTs go on the wire from the app side.
      final outputs = transport.sent.whereType<OutputFrame>().toList();
      expect(outputs, hasLength(1));
      expect(
        outputs.single.bytes,
        // UTF-8 encoding of 'héllo ★'.
        [0x68, 0xC3, 0xA9, 0x6C, 0x6C, 0x6F, 0x20, 0xE2, 0x98, 0x85],
      );

      await driver.restore();
    });

    test('peer disconnect closes the events stream cleanly', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      var streamDone = false;
      final eventSub = driver.events.listen(
        (_) {},
        onDone: () => streamDone = true,
      );

      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: 1,
        ),
      );
      await entering;

      await transport.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(driver.isActive, isFalse);
      expect(
        streamDone,
        isTrue,
        reason:
            'events stream closing is what runApp listens for to exit cleanly',
      );

      await eventSub.cancel();
      await driver.restore();
      expect(
        transport.closed,
        isTrue,
        reason: 'restore must still close resources after peer disconnect',
      );
    });

    test('disconnect before INIT fails the enter() future', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);

      final entering = driver.enter(TerminalMode.interactive);
      await transport.disconnect();

      await expectLater(entering, throwsA(isA<StateError>()));
    });

    test('transport error before INIT fails the enter() future', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);

      final entering = driver.enter(TerminalMode.interactive);
      transport.emitError(const RemoteProtocolException('bad init'));

      await expectLater(entering, throwsA(isA<RemoteProtocolException>()));
    });

    test('a silent peer (no INIT) fails enter() at the deadline', () async {
      // A peer that connects and never speaks must not hang the app forever —
      // under serve --spawn that is a process leak an attacker can multiply
      // (open sockets, send nothing). Disconnects already failed the
      // handshake; silence must too.
      final saved = RemoteTerminalDriver.initTimeout;
      RemoteTerminalDriver.initTimeout = const Duration(milliseconds: 120);
      addTearDown(() => RemoteTerminalDriver.initTimeout = saved);

      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);

      // No frames, no error, no disconnect — pure silence.
      await expectLater(
        driver.enter(TerminalMode.interactive),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('sent no INIT'),
          ),
        ),
      );
    });

    test('restore() sends BYE and tears down', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);

      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: 1,
        ),
      );
      await entering;

      await driver.restore();
      expect(transport.sent.whereType<ByeFrame>(), hasLength(1));
      expect(transport.closed, isTrue);
    });
  });
}
