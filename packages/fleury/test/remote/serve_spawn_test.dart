// `fleury serve --spawn`: integration tests that spawn the real CLI,
// connect a WebSocket as "the browser," verify a subprocess is
// launched with the right environment, exchanges bytes, and gets
// cleaned up on disconnect. Also verifies session isolation — two
// concurrent browsers get two independent subprocesses.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
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
      port = 5900 + Random.secure().nextInt(100);
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

        // Two spawn lines, two distinct session IDs.
        final spawns = stderrLines.where((l) => l.contains('spawned')).toList();
        expect(spawns, hasLength(2));
        expect(stderrLines.any((l) => l.contains('[serve s1]')), isTrue);
        expect(stderrLines.any((l) => l.contains('[serve s2]')), isTrue);

        await sub1.cancel();
        await sub2.cancel();
        await ws1.close();
        await ws2.close();
      },
    );
  }, tags: ['integration']);

  group('fleury serve --spawn with a real runTui app', () {
    late Directory tempDir;
    late Process serveProcess;
    late int port;
    late String pkgRoot;
    final stderrLines = <String>[];
    late StreamSubscription<String> stderrSub;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('fleury_spawn_run_tui_');
      port = 6000 + Random.secure().nextInt(100);
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
      // preserve that frame while the spawned runTui process starts and
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
