// A supervisor's provisional handshake (fleury serve, bridge mode).
//
// Serve speaks at accept so the app's INIT fuse cannot fire while the
// operator is still opening a browser; the browser's own INIT then replaces
// the placeholder. Also the app-side link serve reads from accept, so a
// pending app that dies is noticed and a painting app is drained.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury/src/remote/bridge_app_link.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:fleury/src/remote/serve_init.dart';
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
}

InitFrame _decodeInit(Uint8List bytes) =>
    (FrameDecoder()..feed(bytes)).drain().single as InitFrame;

const _browserInit = InitFrame(
  size: CellSize(120, 40),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
  images: InlineImageSupport.placements,
  hyperlinks: true,
  keyboard: KeyboardCapabilities.full,
  protocolVersion: remoteProtocolVersion,
);

void main() {
  group('INIT wire: provisional + debug', () {
    test('a peer INIT stays byte-flat; the supervisor fields round-trip', () {
      const plain = InitFrame(
        size: CellSize(80, 24),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
      );
      final bytes = encodeFrame(plain);
      expect(String.fromCharCodes(bytes), isNot(contains('provisional')));
      expect(String.fromCharCodes(bytes), isNot(contains('debug')));
      final decoded = _decodeInit(bytes);
      expect(decoded.provisional, isFalse);
      expect(decoded.debugWire, isNull);

      final on = _decodeInit(
        encodeFrame(buildServeProvisionalInitFrame(debugWire: true)),
      );
      expect(on.provisional, isTrue);
      expect(on.debugWire, isTrue);
      expect(on.size, const CellSize(80, 24));
      expect(on.protocolVersion, remoteProtocolVersion);
      expect(on.keyboard, KeyboardCapabilities.full);
      expect(on.images, InlineImageSupport.placements);

      final off = _decodeInit(
        encodeFrame(buildServeProvisionalInitFrame(debugWire: false)),
      );
      expect(off.debugWire, isFalse);
    });
  });

  group('RemoteTerminalDriver under a supervisor', () {
    test('a provisional INIT does not complete enter(), but the fuse no '
        'longer fires; the real INIT negotiates as usual', () async {
      final saved = RemoteTerminalDriver.initTimeout;
      RemoteTerminalDriver.initTimeout = const Duration(milliseconds: 120);
      addTearDown(() => RemoteTerminalDriver.initTimeout = saved);
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      var entered = false;
      final entering = driver
          .enter(TerminalMode.interactive)
          .then((_) => entered = true);
      transport.emit(buildServeProvisionalInitFrame(debugWire: false));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(entered, isFalse, reason: 'a greeting is not a handshake');
      expect(driver.isActive, isFalse);
      expect(driver.supervisorDebugWire, isFalse);

      transport.emit(_browserInit);
      await entering;
      expect(driver.isActive, isTrue);
      expect(driver.size, const CellSize(120, 40));
      expect(
        transport.sent.whereType<InitFrame>(),
        hasLength(1),
        reason: 'the real peer gets its echo',
      );
    });

    test(
      'a v1 (ANSI) peer after the greeting negotiates a v1 session',
      () async {
        // Bridge mode pumps whatever browser arrives; the greeting fixes
        // nothing about the protocol version.
        final transport = _FakeTransport();
        final driver = RemoteTerminalDriver(transport);
        final entering = driver.enter(TerminalMode.interactive);
        transport.emit(buildServeProvisionalInitFrame(debugWire: false));
        transport.emit(
          const InitFrame(
            size: CellSize(100, 30),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
            protocolVersion: 1,
          ),
        );
        await entering;
        expect(driver.wantsPresentationPlans, isFalse);
        expect(driver.size, const CellSize(100, 30));
      },
    );

    test('a greeting after the real handshake, or a second greeting, '
        'changes nothing', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(buildServeProvisionalInitFrame(debugWire: true));
      transport.emit(buildServeProvisionalInitFrame(debugWire: false));
      transport.emit(_browserInit);
      await entering;
      expect(driver.supervisorDebugWire, isTrue, reason: 'first word counts');
      transport.emit(buildServeProvisionalInitFrame(debugWire: false));
      await Future<void>.delayed(Duration.zero);
      expect(driver.supervisorDebugWire, isTrue);
      expect(driver.size, const CellSize(120, 40));
    });

    test('a peer that handshakes itself leaves the debug decision to the '
        'environment', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(_browserInit);
      await entering;
      expect(driver.supervisorDebugWire, isNull);
    });

    test('enter() after restore() fails loudly instead of hanging', () async {
      final transport = _FakeTransport();
      final driver = RemoteTerminalDriver(transport);
      final entering = driver.enter(TerminalMode.interactive);
      transport.emit(_browserInit);
      await entering;
      await driver.restore();
      expect(
        () => driver.enter(TerminalMode.interactive),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('re-entered'),
          ),
        ),
      );
    });
  });

  group('BridgeAppLink', () {
    test('discards before attach, forwards after, reports close', () async {
      final source = StreamController<List<int>>();
      final toApp = StreamController<List<int>>();
      var destroyed = 0;
      final link = BridgeAppLink.forStream(
        source.stream,
        sink: IOSink(toApp.sink),
        destroySource: () => destroyed++,
      );
      source.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(link.discardedBytes, 3);
      expect(link.isClosed, isFalse);

      final forwarded = <int>[];
      final sub = link.attach().listen(forwarded.addAll);
      source.add([4, 5]);
      await Future<void>.delayed(Duration.zero);
      expect(forwarded, [4, 5]);
      expect(link.discardedBytes, 3, reason: 'nothing dropped once attached');

      await source.close();
      await link.closed;
      expect(link.isClosed, isTrue);
      await sub.cancel();
      expect(destroyed, 0);
      link.destroy();
      expect(destroyed, 1);
      unawaited(toApp.close());
    });

    test('a source that ends before attach closes the attached stream at '
        'once', () async {
      final source = StreamController<List<int>>();
      final toApp = StreamController<List<int>>();
      final link = BridgeAppLink.forStream(
        source.stream,
        sink: IOSink(toApp.sink),
        destroySource: () {},
      );
      await source.close();
      await link.closed;
      expect(await link.attach().toList(), isEmpty);
      unawaited(toApp.close());
    });

    test('attach() twice is a programming error', () async {
      final source = StreamController<List<int>>();
      final toApp = StreamController<List<int>>();
      final link = BridgeAppLink.forStream(
        source.stream,
        sink: IOSink(toApp.sink),
        destroySource: () {},
      );
      link.attach();
      expect(link.attach, throwsStateError);
      link.destroy();
      await source.close();
      unawaited(toApp.close());
    });
  });
}
