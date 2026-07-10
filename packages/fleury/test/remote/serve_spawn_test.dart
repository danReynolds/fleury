// `fleury serve --spawn`: integration tests that spawn the real CLI,
// connect a WebSocket as "the browser," verify a subprocess is
// launched with the right environment, exchanges bytes, and gets
// cleaned up on disconnect. Also verifies session isolation — two
// concurrent browsers get two independent subprocesses.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('fleury serve --spawn (integration)', () {
    late Directory tempDir;
    late Process serveProcess;
    late int port;
    late String pkgRoot;
    final stderrLines = <String>[];
    late StreamSubscription<String> stderrSub;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('fleury_spawn_test_');
      port = await _unusedLoopbackPort();
      pkgRoot = Directory.current.path;
      stderrLines.clear();
      final childCwd = Directory('${tempDir.path}/child-cwd')..createSync();

      // Spawn the CLI in spawn mode pointing at our fixture subprocess.
      serveProcess = await Process.start(Platform.resolvedExecutable, [
        'run',
        '$pkgRoot/bin/fleury.dart',
        'serve',
        '--port=$port',
        '--spawn',
        Platform.resolvedExecutable,
        'run',
        '$pkgRoot/test/fixtures/spawn_app.dart',
        'spawn-app',
        childCwd.path,
        '--hostile-log',
      ], workingDirectory: tempDir.path);

      final ready = Completer<void>();
      stderrSub = serveProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stderrLines.add(line);
            if (line.contains('spawn mode') && !ready.isCompleted) {
              ready.complete();
            }
          });
      await ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          'serve did not start within 10s. stderr:\n${stderrLines.join('\n')}',
        ),
      );
    });

    tearDown(() async {
      await stderrSub.cancel();
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

    test('browser connect spawns a subprocess that connects back', () async {
      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');

      // The subprocess sends `HELLO_FROM_spawn-app\n` as the first
      // OUTPUT frame on connect; we can find it by feeding what the
      // browser receives through a frame decoder.
      final inbound = BytesBuilder();
      final wsSub = ws.listen((data) {
        if (data is List<int>) inbound.add(data);
      });

      // The browser-side JS would send INIT here. Mimic it so the
      // subprocess's transport sees expected handshake bytes — our
      // fixture ignores INIT, so this is for protocol realism.
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

      // Wait until we see the fixture's hello bytes come back.
      await _waitFor(
        () => _hasHelloFrame(inbound.toBytes(), 'spawn-app'),
        timeout: const Duration(seconds: 8),
        what: 'HELLO_FROM_spawn-app over WS',
      );

      // The serve process should also have logged the spawn.
      expect(
        stderrLines.any((l) => l.contains('[serve s1] spawned')),
        isTrue,
        reason: 'serve should log subprocess spawn',
      );

      await wsSub.cancel();
      await ws.close();

      // Closing the browser should tear the subprocess down.
      await _waitFor(
        () =>
            stderrLines.any((l) => l.contains('[serve s1] subprocess exited')),
        timeout: const Duration(seconds: 8),
        what: 'subprocess exited log line after browser disconnect',
      );
    });

    test('sanitizes subprocess log output before writing to stderr', () async {
      await _waitFor(
        () => stderrLines.any((line) => line.contains('HOSTILE')),
        timeout: const Duration(seconds: 8),
        what: 'hostile subprocess log line',
      );

      final line = stderrLines.singleWhere((line) => line.contains('HOSTILE'));
      expect(line, contains(replacementCharacter));
      expect(line, isNot(contains('\x1B')));
      expect(line, isNot(contains('SECRET')));
      expect(line, isNot(contains('[2J')));
    });

    test('a warm standby is pre-spawned and pairs the first browser', () async {
      // The eager warm standby's subprocess spawns at serve start, before any
      // browser connects — that's the cold start being paid ahead of time.
      await _waitFor(
        () => stderrLines.any((l) => l.contains('[serve s1] spawned')),
        timeout: const Duration(seconds: 8),
        what: 'warm standby spawned before any connection',
      );

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
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

      // The connection pairs with the warm standby (not a fresh cold spawn),
      // and the standby's buffered hello reaches the browser through the pump.
      await _waitFor(
        () =>
            _hasHelloFrame(inbound.toBytes(), 'spawn-app') &&
            stderrLines.any(
              (l) => l.contains('paired browser to warm standby'),
            ),
        timeout: const Duration(seconds: 8),
        what: 'browser paired to warm standby + hello delivered',
      );

      await wsSub.cancel();
      await ws.close();
    });

    test(
      'two concurrent browsers spawn two independent subprocesses',
      () async {
        final ws1 = await WebSocket.connect('ws://127.0.0.1:$port/ws');
        final ws2 = await WebSocket.connect('ws://127.0.0.1:$port/ws');

        final inbound1 = BytesBuilder();
        final inbound2 = BytesBuilder();
        final sub1 = ws1.listen((d) {
          if (d is List<int>) inbound1.add(d);
        });
        final sub2 = ws2.listen((d) {
          if (d is List<int>) inbound2.add(d);
        });

        // Each subprocess sends its hello on connect — wait for both.
        await _waitFor(
          () =>
              _hasHelloFrame(inbound1.toBytes(), 'spawn-app') &&
              _hasHelloFrame(inbound2.toBytes(), 'spawn-app'),
          timeout: const Duration(seconds: 12),
          what: 'hello on both WS connections',
        );

        // Both browsers were served by their own subprocess (the hellos above
        // prove isolation). With the warm-standby pool, serve also pre-spawns
        // idle standbys, so the spawn count is >= 2 rather than exactly 2.
        final spawns = stderrLines.where((l) => l.contains('spawned')).toList();
        expect(spawns.length, greaterThanOrEqualTo(2));
        expect(stderrLines.any((l) => l.contains('[serve s1]')), isTrue);
        expect(stderrLines.any((l) => l.contains('[serve s2]')), isTrue);

        await sub1.cancel();
        await sub2.cancel();
        await ws1.close();
        await ws2.close();
      },
    );
  }, tags: ['integration']);

  group('fleury serve --spawn with a real runApp app', () {
    late Directory tempDir;
    late Process serveProcess;
    late int port;
    late String pkgRoot;
    final stderrLines = <String>[];
    late StreamSubscription<String> stderrSub;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('fleury_spawn_run_app_');
      port = await _unusedLoopbackPort();
      pkgRoot = Directory.current.path;
      stderrLines.clear();

      serveProcess = await Process.start(Platform.resolvedExecutable, [
        'run',
        '$pkgRoot/bin/fleury.dart',
        'serve',
        '--port=$port',
        '--spawn',
        Platform.resolvedExecutable,
        'run',
        '$pkgRoot/example/counter_quickstart.dart',
      ], workingDirectory: tempDir.path);

      final ready = Completer<void>();
      stderrSub = serveProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stderrLines.add(line);
            if (line.contains('spawn mode') && !ready.isCompleted) {
              ready.complete();
            }
          });
      await ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          'serve did not start within 10s. stderr:\n${stderrLines.join('\n')}',
        ),
      );
    });

    tearDown(() async {
      await stderrSub.cancel();
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

    test('preserves browser INIT sent before the app connects', () async {
      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final inbound = BytesBuilder();
      final wsSub = ws.listen((data) {
        if (data is List<int>) inbound.add(data);
      });

      // Real browsers send INIT immediately on WebSocket open. The server must
      // preserve that frame while the spawned runApp process starts and
      // connects back to the per-session Unix socket.
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

      await _waitFor(
        () => _hasOutputFrameText(inbound.toBytes(), 'count: 0'),
        timeout: const Duration(seconds: 20),
        what: 'counter first paint over WS',
      );

      await wsSub.cancel();
      await ws.close();
    });
  }, tags: ['integration']);

  group(
    'fleury serve --spawn hardening (integration)',
    () {
      /// Starts a fresh `fleury serve --spawn` with [serveArgs] and [appCmd],
      /// returning its port + stderr lines. Teardown is registered here.
      Future<(int, List<String>)> startServe(
        List<String> serveArgs,
        List<String> appCmd,
      ) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_spawn_hard_',
        );
        final port = await _unusedLoopbackPort();
        final pkgRoot = Directory.current.path;
        final stderrLines = <String>[];
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          '$pkgRoot/bin/fleury.dart',
          'serve',
          '--port=$port',
          ...serveArgs,
          '--spawn',
          ...appCmd,
        ], workingDirectory: tempDir.path);
        final ready = Completer<void>();
        final sub = process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              stderrLines.add(line);
              if (line.contains('spawn mode') && !ready.isCompleted) {
                ready.complete();
              }
            });
        addTearDown(() async {
          process.kill(ProcessSignal.sigint);
          await process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return process.exitCode;
            },
          );
          await sub.cancel();
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });
        await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'serve did not start within 10s. stderr:\n${stderrLines.join('\n')}',
          ),
        );
        return (port, stderrLines);
      }

      void sendInit(WebSocket ws) {
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
      }

      test('connections beyond --max-sessions are rejected (F8)', () async {
        final pkgRoot = Directory.current.path;
        final childCwd = Directory.systemTemp.createTempSync('fleury_cap_cwd_');
        addTearDown(() => childCwd.deleteSync(recursive: true));
        final (port, stderrLines) = await startServe(
          ['--max-sessions=1'],
          [
            Platform.resolvedExecutable,
            'run',
            '$pkgRoot/test/fixtures/spawn_app.dart',
            'cap-app',
            childCwd.path,
          ],
        );

        // First browser attaches (fills the cap).
        final ws1 = await WebSocket.connect('ws://127.0.0.1:$port/ws');
        final inbound = BytesBuilder();
        final sub = ws1.listen((data) {
          if (data is List<int>) inbound.add(data);
        });
        sendInit(ws1);
        await _waitFor(
          () => _hasHelloFrame(inbound.toBytes(), 'cap-app'),
          timeout: const Duration(seconds: 8),
          what: 'first session attached',
        );

        // Second browser must be turned away — each session is a whole Dart VM,
        // and the cap is what keeps an open reconnect loop from fork-bombing.
        await expectLater(
          WebSocket.connect('ws://127.0.0.1:$port/ws'),
          throwsA(isA<WebSocketException>()),
          reason: 'the upgrade is refused with 503 at the cap',
        );
        await _waitFor(
          () => stderrLines.any((l) => l.contains('session limit reached')),
          timeout: const Duration(seconds: 4),
          what: 'rejection logged',
        );

        await sub.cancel();
        await ws1.close();
      });

      test('the debug wire is OFF for spawned apps unless serve gets --debug '
          '(F15)', () async {
        final pkgRoot = Directory.current.path;
        Future<(WebSocket, BytesBuilder)> connectAndInit(int port) async {
          final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
          final inbound = BytesBuilder();
          ws.listen((data) {
            if (data is List<int>) inbound.add(data);
          });
          // v2 = the STRUCTURED (presentation-plan) path — the only path
          // where runApp wires onDebugRequest at all. A v1 init would make
          // the OFF assertion vacuous (no negotiatedSink → never answered).
          ws.add(
            encodeFrame(
              const InitFrame(
                size: CellSize(80, 24),
                colorMode: ColorMode.truecolor,
                imageProtocol: ImageProtocol.halfBlock,
                tmuxPassthrough: false,
                protocolVersion: 2,
              ),
            ),
          );
          // Wait for the app's first structured frame so the session is
          // fully up before we query the debug channel.
          await _waitFor(
            () => _frameCount(inbound.toBytes()) > 0,
            timeout: const Duration(seconds: 10),
            what: 'fixture first structured frame',
          );
          return (ws, inbound);
        }

        final appCmd = [
          Platform.resolvedExecutable,
          'run',
          '$pkgRoot/test/fixtures/serve_debug_fixture.dart',
        ];

        // Default: no --debug. The JIT app has debug tooling on, but the WIRE
        // must stay silent — a shared URL must not pull logs/stacks by default.
        final (portOff, _) = await startServe(const [], appCmd);
        final (wsOff, inboundOff) = await connectAndInit(portOff);
        wsOff.add(encodeFrame(const DebugRequestFrame(7, 'errors', limit: 5)));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        expect(
          _hasDebugResponse(inboundOff.toBytes()),
          isFalse,
          reason: 'without --debug the app must not answer debugRequest frames',
        );
        await wsOff.close();

        // Opt-in: --debug re-enables the wire (the local-dev loop).
        final (portOn, _) = await startServe(const ['--debug'], appCmd);
        final (wsOn, inboundOn) = await connectAndInit(portOn);
        wsOn.add(encodeFrame(const DebugRequestFrame(7, 'errors', limit: 5)));
        await _waitFor(
          () => _hasDebugResponse(inboundOn.toBytes()),
          timeout: const Duration(seconds: 5),
          what: 'debugResponse with --debug',
        );
        await wsOn.close();
      });
    },
    tags: ['integration'],
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

/// Polls [check] every 50ms until it returns true or [timeout] elapses.
/// Throws with [what] in the message if the deadline passes.

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

/// Decodes [bytes] as a frame stream and returns true if any OUTPUT
/// frame contains `HELLO_FROM_<tag>`.

/// How many complete frames [bytes] (cumulative WS inbound) decode to.
int _frameCount(Uint8List bytes) {
  final decoder = FrameDecoder()..feed(bytes);
  return decoder.drain().length;
}

/// Whether [bytes] (cumulative WS inbound) contain a decoded
/// [DebugResponseFrame].
bool _hasDebugResponse(Uint8List bytes) {
  final decoder = FrameDecoder()..feed(bytes);
  return decoder.drain().any((frame) => frame is DebugResponseFrame);
}

bool _hasHelloFrame(Uint8List bytes, String tag) {
  final decoder = FrameDecoder()..feed(bytes);
  final needle = 'HELLO_FROM_$tag';
  for (final frame in decoder.drain()) {
    if (frame is! OutputFrame) continue;
    if (utf8.decode(frame.bytes, allowMalformed: true).contains(needle)) {
      return true;
    }
  }
  return false;
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

Future<int> _unusedLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
