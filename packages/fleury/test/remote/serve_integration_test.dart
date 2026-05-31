// Spawns the real `fleury serve` process and verifies end-to-end:
//
//   1. HTTP GET / serves the xterm.js page
//   2. The Unix socket binds at `.fleury/shell.sock`
//   3. Bytes round-trip both ways: bytes sent from a "browser"
//      WebSocket reach the "app" Unix socket and vice versa
//
// Runs in a temp directory so the process doesn't stomp on the
// repo's `.fleury/` (`fleury serve` writes its handle file in cwd).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

void main() {
  group(
    'fleury serve (integration)',
    () {
      late Directory tempDir;
      late Process serveProcess;
      late int port;

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('fleury_serve_test_');
        // Pick a fresh port. The 5800–5899 range avoids common ports;
        // a tiny chance of collision is acceptable for a test that
        // takes ~2s to run.
        port = 5800 + Random.secure().nextInt(100);

        // Locate the package root so we can point `dart run` at bin/fleury.dart
        // with an absolute path (tests run from the package root, but we cd
        // into tempDir before spawning so the process's cwd is the temp dir).
        final pkgRoot = Directory.current.path;

        serveProcess = await Process.start(
          Platform.resolvedExecutable, // `dart`
          ['run', '$pkgRoot/bin/fleury.dart', 'serve', '--port=$port'],
          workingDirectory: tempDir.path,
        );

        // Wait for "fleury serve ready" on stderr before proceeding.
        final ready = Completer<void>();
        final stderrBuf = StringBuffer();
        serveProcess.stderr.transform(utf8.decoder).listen((chunk) {
          stderrBuf.write(chunk);
          if (stderrBuf.toString().contains('fleury serve ready') &&
              !ready.isCompleted) {
            ready.complete();
          }
        });
        await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'serve did not start within 10s. stderr:\n$stderrBuf',
          ),
        );
      });

      tearDown(() async {
        serveProcess.kill(ProcessSignal.sigint);
        await serveProcess.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            serveProcess.kill(ProcessSignal.sigkill);
            return -9;
          },
        );
        tempDir.deleteSync(recursive: true);
      });

      test('GET / serves the xterm.js page', () async {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
        final resp = await req.close();
        expect(resp.statusCode, 200);
        final body = await resp.transform(utf8.decoder).join();
        expect(body, contains('xterm'));
        expect(body, contains('/ws'));
        client.close();
      });

      test('app + browser pair, bytes flow both ways', () async {
        // Open both ends in parallel — the pairing logic shouldn't care
        // about arrival order.
        final socketPath = '${tempDir.path}/.fleury/shell.sock';
        final wsFuture = WebSocket.connect('ws://127.0.0.1:$port/ws');
        // Give the WS handshake a brief head start so the serve process
        // is past `WebSocketTransformer.upgrade` before we connect the
        // app side — keeps the test deterministic about pairing order.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final appSocket = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        final ws = await wsFuture;

        // Collect what each side receives.
        final receivedByApp = BytesBuilder();
        final appSub = appSocket.listen(receivedByApp.add);

        final receivedByBrowser = BytesBuilder();
        final wsSub = ws.listen((data) {
          if (data is List<int>) receivedByBrowser.add(data);
        });

        // Browser → app. Send something distinctive.
        final fromBrowser = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
        ws.add(fromBrowser);

        // App → browser.
        final fromApp = Uint8List.fromList([0x11, 0x22, 0x33, 0x44, 0x55]);
        appSocket.add(fromApp);
        await appSocket.flush();

        // Give the pump a beat to land bytes on both sides. The pump is
        // event-driven (no polling) so this is just yielding the event
        // loop a few times.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(receivedByApp.toBytes(), fromBrowser);
        expect(receivedByBrowser.toBytes(), fromApp);

        await appSub.cancel();
        await wsSub.cancel();
        await appSocket.close();
        await ws.close();
      });
    },
    // Spawning a real dart process is slow (~1-2s) and depends on
    // the dart toolchain being on PATH; tag as integration so a CI
    // step that wants the fast path can `dart test -x integration`.
    tags: ['integration'],
  );
}
