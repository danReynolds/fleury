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

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(
    'fleury serve (integration)',
    () {
      late Directory tempDir;
      late Process serveProcess;
      late int port;
      late String pkgRoot;

      setUp(() async {
        tempDir = Directory.systemTemp.createTempSync('fleury_serve_test_');
        // Pick a fresh port. The 5800–5899 range avoids common ports;
        // a tiny chance of collision is acceptable for a test that
        // takes ~2s to run.
        port = 5800 + Random.secure().nextInt(100);

        // Locate the package root so we can point `dart run` at bin/fleury.dart
        // with an absolute path (tests run from the package root, but we cd
        // into tempDir before spawning so the process's cwd is the temp dir).
        pkgRoot = Directory.current.path;

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

      test('GET / serves the fleury renderer page (no xterm)', () async {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
        final resp = await req.close();
        expect(resp.statusCode, 200);
        final body = await resp.transform(utf8.decoder).join();
        expect(body, contains('fleury-remote'));
        expect(body, contains('/remote_client.js'));
        expect(body, isNot(contains('xterm')));
        client.close();
      });

      test('GET /remote_client.js serves the embedded client bundle', () async {
        final client = HttpClient();
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/remote_client.js'),
        );
        final resp = await req.close();
        expect(resp.statusCode, 200);
        expect(
          resp.headers.contentType?.mimeType,
          'application/javascript',
        );
        final bytes = await resp.fold<int>(0, (n, chunk) => n + chunk.length);
        expect(bytes, greaterThan(10000));
        client.close();
      });

      test('rejects cross-origin WebSocket upgrades', () async {
        await expectLater(
          WebSocket.connect(
            'ws://127.0.0.1:$port/ws',
            headers: {'origin': 'http://evil.example'},
          ),
          throwsA(anything),
        );

        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
        final resp = await req.close();
        expect(resp.statusCode, 200);
        await resp.drain<void>();
        client.close();
      });

      test(
        'browser-first app pair buffers input and bytes flow both ways',
        () async {
          // Open both ends in parallel — the pairing logic shouldn't care
          // about arrival order.
          final socketPath = '${tempDir.path}/.fleury/shell.sock';
          final ws = await WebSocket.connect(
            'ws://127.0.0.1:$port/ws',
            headers: {'origin': 'http://127.0.0.1:$port'},
          );

          // Browser → app, before the app has connected. Real xterm.js clients
          // send INIT in this window; bridge mode must preserve early frames.
          final fromBrowser = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
          ws.add(fromBrowser);
          await Future<void>.delayed(const Duration(milliseconds: 50));

          final appSocket = await Socket.connect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
          );

          // Collect what each side receives.
          final receivedByApp = BytesBuilder();
          final appSub = appSocket.listen(receivedByApp.add);

          final receivedByBrowser = BytesBuilder();
          final wsSub = ws.listen((data) {
            if (data is List<int>) receivedByBrowser.add(data);
          });

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
        },
      );

      test(
        'browser-first bridge preserves INIT for a real runTui app',
        () async {
          final socketPath = '${tempDir.path}/.fleury/shell.sock';
          final ws = await WebSocket.connect(
            'ws://127.0.0.1:$port/ws',
            headers: {'origin': 'http://127.0.0.1:$port'},
          );
          final inbound = BytesBuilder();
          final wsSub = ws.listen((data) {
            if (data is List<int>) inbound.add(data);
          });

          ws.add(
            encodeFrame(
              const InitFrame(
                size: CellSize(80, 24),
                colorMode: ColorMode.truecolor,
                imageProtocol: ImageProtocol.halfBlock,
                tmuxPassthrough: false,
                protocolVersion: 1,
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));

          final appStderr = StringBuffer();
          final appProcess = await Process.start(
            Platform.resolvedExecutable,
            ['run', '$pkgRoot/example/counter_quickstart.dart'],
            workingDirectory: tempDir.path,
            environment: {'FLEURY_HANDLE': socketPath},
          );
          final stderrSub = appProcess.stderr
              .transform(utf8.decoder)
              .listen(appStderr.write);
          final stdoutSub = appProcess.stdout.drain<void>();

          try {
            await _waitFor(
              () => _hasOutputFrameText(inbound.toBytes(), 'count: 0'),
              timeout: const Duration(seconds: 20),
              what:
                  'counter first paint over bridge-mode WS; stderr:\n$appStderr',
            );
          } finally {
            await wsSub.cancel();
            await ws.close();
            appProcess.kill(ProcessSignal.sigint);
            await appProcess.exitCode.timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                appProcess.kill(ProcessSignal.sigkill);
                return -9;
              },
            );
            await stderrSub.cancel();
            await stdoutSub;
          }
        },
      );
    },
    // Spawning a real dart process is slow (~1-2s) and depends on
    // the dart toolchain being on PATH; tag as integration so a CI
    // step that wants the fast path can `dart test -x integration`.
    tags: ['integration'],
  );

  group('fleury serve origin policy (integration)', () {
    late String pkgRoot;

    setUpAll(() {
      pkgRoot = Directory.current.path;
    });

    test('allows an explicit cross-origin WebSocket origin', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_serve_origin_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final port = 6100 + Random.secure().nextInt(100);
      final serveProcess = await _startServeProcess(
        pkgRoot: pkgRoot,
        tempDir: tempDir,
        port: port,
        args: const ['--allow-origin=http://allowed.example'],
      );
      addTearDown(() => _stopProcess(serveProcess));

      final ws = await WebSocket.connect(
        'ws://127.0.0.1:$port/ws',
        headers: {'origin': 'http://allowed.example'},
      );
      await ws.close();
    });

    test('rejects invalid allow-origin values before binding', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_serve_bad_origin_',
      );
      try {
        final port = 6200 + Random.secure().nextInt(100);
        final result = await Process.run(Platform.resolvedExecutable, [
          'run',
          '$pkgRoot/bin/fleury.dart',
          'serve',
          '--port=$port',
          '--allow-origin=not-an-origin',
        ], workingDirectory: tempDir.path);

        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('--allow-origin must be'));
        expect(Directory('${tempDir.path}/.fleury').existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  }, tags: ['integration']);
}

Future<Process> _startServeProcess({
  required String pkgRoot,
  required Directory tempDir,
  required int port,
  List<String> args = const <String>[],
}) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    '$pkgRoot/bin/fleury.dart',
    'serve',
    '--port=$port',
    ...args,
  ], workingDirectory: tempDir.path);
  final ready = Completer<void>();
  final stderrBuf = StringBuffer();
  process.stderr.transform(utf8.decoder).listen((chunk) {
    stderrBuf.write(chunk);
    if (stderrBuf.toString().contains('fleury serve ready') &&
        !ready.isCompleted) {
      ready.complete();
    }
  });
  await ready.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () =>
        throw StateError('serve did not start within 10s. stderr:\n$stderrBuf'),
  );
  return process;
}

Future<void> _stopProcess(Process process) async {
  process.kill(ProcessSignal.sigint);
  await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -9;
    },
  );
}

Future<void> _waitFor(
  bool Function() check, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('timed out waiting for $what', timeout);
}

bool _hasOutputFrameText(Uint8List bytes, String text) {
  final decoder = FrameDecoder()..feed(bytes);
  for (final frame in decoder.drain()) {
    if (frame is! OutputFrame) continue;
    if (utf8.decode(frame.bytes, allowMalformed: true).contains(text)) {
      return true;
    }
  }
  return false;
}
