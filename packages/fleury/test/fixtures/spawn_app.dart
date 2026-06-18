// Minimal subprocess fixture for the `fleury serve --spawn` integration
// tests. Reads `$FLEURY_HANDLE`, connects to the per-session socket,
// sends a tagged OUTPUT frame so the test can prove this specific
// subprocess connected, then sits waiting for BYE.
//
// Lives under test/fixtures/ rather than example/ because it's a test
// helper — it doesn't use runTui at all (we're testing the transport +
// spawn lifecycle, not the framework).

import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';

Future<void> main(List<String> args) async {
  final handle = Platform.environment['FLEURY_HANDLE'];
  if (handle == null || handle.isEmpty) {
    stderr.writeln('spawn_app fixture: FLEURY_HANDLE not set');
    exit(2);
  }
  final tag = args.isNotEmpty ? args.first : 'spawn-app';
  if (args.length > 1 && !args[1].startsWith('--')) {
    Directory.current = args[1];
  }
  if (args.contains('--hostile-log')) {
    stderr.writeln('HOSTILE \x1b]52;c;SECRET\x07 after \x1b[2J end');
  }
  final transport = await UnixSocketFrameTransport.connect(handle);

  // Signal "I'm alive and connected to the right session socket"
  // by sending a tagged OUTPUT frame.
  transport.send(
    OutputFrame(Uint8List.fromList('HELLO_FROM_$tag\n'.codeUnits)),
  );

  // Sit on the socket until the peer (the serve pump, via the
  // browser WS) closes or sends BYE. This is what a real TUI's
  // event loop does — it's `runTui`'s `await exit.future` in
  // miniature.
  await for (final frame in transport.incoming) {
    if (frame is ByeFrame) break;
  }
  await transport.close();
  exit(0);
}
