// The transport half of the handshake contract: frames the peer sends
// BEFORE the app side subscribes to [incoming] must be delivered, not
// dropped. The peer speaks the moment the socket opens (the agent bridge
// sends INIT on accept), while the app side doesn't listen until the
// driver's enter() — and any await in between (fd-capture startup, any
// future async setup step) opens a real-time window. [incoming] is a
// broadcast stream, which drops events with no listener, so the transport
// parks the socket subscription until the first listener attaches.
// Regression guard for the enter()-hangs-forever failure that surfaced
// when remote fd-capture added the first such await.
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';
import 'package:test/test.dart';

void main() {
  test(
    'frames sent before incoming has a listener are buffered, in order',
    () async {
      final tmp = Directory.systemTemp.createTempSync('fleury-prelisten-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = '${tmp.path}/sock';
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      addTearDown(server.close);

      final acceptedFuture = server.first;
      final transport = await UnixSocketFrameTransport.connect(path);
      addTearDown(transport.close);
      final accepted = await acceptedFuture;
      addTearDown(() async {
        try {
          await accepted.close();
        } catch (_) {}
      });

      // The peer speaks IMMEDIATELY — before anyone listens to incoming.
      accepted.add(encodeFrame(const ResizeFrame(CellSize(101, 41))));
      accepted.add(encodeFrame(const ByeFrame()));
      await accepted.flush();

      // The pre-listen window: real event-loop turns in which, before the
      // fix, the socket handler decoded these frames into the listenerless
      // broadcast controller and they vanished.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now subscribe — the way RemoteTerminalDriver.enter() does — and both
      // frames must arrive, in order.
      final received = <RemoteFrame>[];
      final sub = transport.incoming.listen(received.add);
      addTearDown(sub.cancel);
      for (var i = 0; i < 100 && received.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(received, hasLength(2), reason: 'nothing dropped pre-listen');
      expect(received[0], isA<ResizeFrame>());
      expect((received[0] as ResizeFrame).size, const CellSize(101, 41));
      expect(received[1], isA<ByeFrame>());
    },
  );

  test('peer closing before the first send is contained', () async {
    final tmp = Directory.systemTemp.createTempSync('fleury-send-close-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = '${tmp.path}/sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    addTearDown(server.close);

    final acceptedFuture = server.first;
    final transport = await UnixSocketFrameTransport.connect(path);
    addTearDown(transport.close);
    final accepted = await acceptedFuture;
    accepted.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    transport.send(
      const InitFrame(
        size: CellSize(80, 24),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        protocolVersion: 1,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await transport.sendDrained.timeout(const Duration(seconds: 1));
    expect(transport.isSendBacklogged, isFalse);
  });
}
