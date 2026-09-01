// `RemoteFrameTransport.close()` is documented idempotent, and the driver
// takes that literally: `enter`'s INIT fuse fires `unawaited(close())` and
// then throws, after which `restore()` awaits `close()` again. Idempotent has
// to mean "a second caller waits for the SAME teardown", not "a second caller
// returns while the first is still flushing" — a returning `close()` is the
// signal the socket is done with.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:fleury/fleury_wire_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late ServerSocket server;
  late Socket accepted;
  late UnixSocketFrameTransport transport;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('fleury-close-');
    final path = '${tmp.path}/sock';
    server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final acceptedFuture = server.first;
    transport = await UnixSocketFrameTransport.connect(path);
    accepted = await acceptedFuture;
  });

  tearDown(() async {
    try {
      await accepted.close();
    } catch (_) {}
    await server.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a concurrent second close() waits for the first teardown', () async {
    // The incoming controller is closed by the LAST step of the graceful
    // teardown, after the socket has been flushed and closed — so a `close()`
    // that returns before this fired returned early on a live socket.
    var incomingDone = false;
    transport.incoming.listen((_) {}, onDone: () => incomingDone = true);

    final first = transport.close();
    final second = transport.close();
    await second;

    expect(
      incomingDone,
      isTrue,
      reason:
          'the second close() returned while the first was still tearing the '
          'socket down',
    );
    await first;
  });

  test('close() stays idempotent when called again after it completed',
      () async {
    await transport.close();
    await transport.close();
    await transport.close();
  });
}
