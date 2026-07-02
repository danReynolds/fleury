// The transport half of the backpressure contract, against a REAL unix
// socket pair: a stalled reader makes the sender report itself
// backlogged (Socket.flush pends while the kernel buffers are full), a
// resumed reader drains it, and nothing sent is ever lost or reordered.
// Stalling is done the only way it can be in-process: pausing the
// accepting side's subscription stops reads, the kernel buffers fill,
// and the writer's flush stops completing.
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';
import 'package:test/test.dart';

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late Directory tmp;
  late ServerSocket server;
  late Socket accepted;
  late UnixSocketFrameTransport transport;

  Future<void> start({required int highWaterMark}) async {
    tmp = Directory.systemTemp.createTempSync('fleury-bp-');
    final path = '${tmp.path}/sock';
    server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final acceptedFuture = server.first;
    transport = await UnixSocketFrameTransport.connect(
      path,
      sendHighWaterMark: highWaterMark,
    );
    accepted = await acceptedFuture;
  }

  Future<void> stop() async {
    await transport.close();
    try {
      await accepted.close();
    } catch (_) {}
    await server.close();
    tmp.deleteSync(recursive: true);
  }

  test(
    'a stalled peer backlogs the sender; resume drains byte-exactly',
    () async {
      await start(highWaterMark: 64 * 1024);
      final received = BytesBuilder(copy: true);
      final subscription = accepted.listen(received.add);

      // Stall the peer: no reads → kernel buffers fill → flush pends.
      subscription.pause();

      // Pump until the transport reports the backlog (bounded — unix
      // socket buffers are a few hundred KiB at most).
      final payload = Uint8List.fromList(
        List<int>.generate(32 * 1024, (i) => i & 0xFF),
      );
      var framesSent = 0;
      while (!transport.isSendBacklogged && framesSent < 512) {
        transport.send(OutputFrame(payload));
        framesSent++;
        await _pump();
      }
      expect(
        transport.isSendBacklogged,
        isTrue,
        reason: 'a paused reader must surface as a send backlog',
      );

      var drained = false;
      unawaited(transport.sendDrained.then((_) => drained = true));
      await _pump();
      expect(drained, isFalse, reason: 'the drain future pends with the peer');

      // The peer catches up.
      subscription.resume();
      await transport.sendDrained.timeout(const Duration(seconds: 10));
      expect(transport.isSendBacklogged, isFalse);
      await _pump();
      expect(drained, isTrue);

      // Every frame arrives, in order, byte-exact.
      final decoder = FrameDecoder();
      // Give the reader a moment to finish consuming the tail.
      for (
        var i = 0;
        i < 100 && received.length < framesSent * (payload.length + 5);
        i++
      ) {
        await _pump();
      }
      decoder.feed(received.takeBytes());
      final frames = decoder.drain().toList();
      expect(frames, hasLength(framesSent));
      for (final frame in frames) {
        expect((frame as OutputFrame).bytes, payload);
      }

      await subscription.cancel();
      await stop();
    },
  );

  test(
    'close() while backlogged completes sendDrained (no wedged host)',
    () async {
      await start(highWaterMark: 32 * 1024);
      final subscription = accepted.listen((_) {});
      subscription.pause();

      final payload = Uint8List(32 * 1024);
      var framesSent = 0;
      while (!transport.isSendBacklogged && framesSent < 512) {
        transport.send(OutputFrame(payload));
        framesSent++;
        await _pump();
      }
      expect(transport.isSendBacklogged, isTrue);

      final drainFuture = transport.sendDrained;
      await transport.close();
      // The contract: a gated frame program must never wait forever on a
      // dead peer.
      await drainFuture.timeout(const Duration(seconds: 5));
      expect(transport.isSendBacklogged, isFalse);

      await subscription.cancel();
      try {
        await accepted.close();
      } catch (_) {}
      await server.close();
      tmp.deleteSync(recursive: true);
    },
  );
}
