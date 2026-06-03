import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';
import 'package:test/test.dart';

void main() {
  group('fleury shell lifecycle', () {
    late Directory tempDir;
    late ServerSocket server;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('fleury_shell_lifecycle_');
      final handleDir = Directory('${tempDir.path}/.fleury')..createSync();
      server = await ServerSocket.bind(
        InternetAddress(
          '${handleDir.path}/shell.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
    });

    tearDown(() async {
      await server.close();
      tempDir.deleteSync(recursive: true);
    });

    test('remote driver closes events when the shell peer sends BYE', () async {
      final socketPath = '${tempDir.path}/.fleury/shell.sock';
      final accepted = server.first;
      final appTransport = await UnixSocketFrameTransport.connect(socketPath);
      final shellTransport = UnixSocketFrameTransport.fromSocket(
        await accepted.timeout(const Duration(seconds: 10)),
      );
      addTearDown(shellTransport.close);

      final driver = RemoteTerminalDriver(appTransport);
      final done = Completer<void>();
      final eventSub = driver.events.listen((_) {}, onDone: done.complete);
      addTearDown(() async {
        await eventSub.cancel();
        await driver.restore();
      });

      final entering = driver.enter(TerminalMode.interactive);
      shellTransport.send(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        ),
      );
      await entering;

      shellTransport.send(const ByeFrame());
      await shellTransport.close();

      await done.future.timeout(const Duration(seconds: 5));
      expect(driver.isActive, isFalse);
    });

    test('real runTui app exits when the shell peer sends BYE', () async {
      final pkgRoot = Directory.current.path;
      final socketPath = '${tempDir.path}/.fleury/shell.sock';
      final accepted = server.first;
      final app = await Process.start(
        Platform.resolvedExecutable,
        ['$pkgRoot/example/counter_quickstart.dart'],
        workingDirectory: tempDir.path,
        environment: {'FLEURY_HANDLE': socketPath},
      );
      final appStderr = StringBuffer();
      final stderrSub = app.stderr
          .transform(utf8.decoder)
          .listen(appStderr.write);
      final stdoutSub = app.stdout.drain<void>();
      addTearDown(() async {
        if (await _isRunning(app)) {
          app.kill(ProcessSignal.sigkill);
          await app.exitCode;
        }
        await stderrSub.cancel();
        await stdoutSub;
      });

      final socket = await accepted.timeout(const Duration(seconds: 30));
      final transport = UnixSocketFrameTransport.fromSocket(socket);
      final output = StringBuffer();
      final frameSub = transport.incoming.listen((frame) {
        if (frame is OutputFrame) {
          output.write(utf8.decode(frame.bytes, allowMalformed: true));
        }
      });
      addTearDown(() async {
        await frameSub.cancel();
        await transport.close();
      });

      transport.send(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        ),
      );

      await _waitFor(
        () => output.toString().contains('count: 0'),
        timeout: const Duration(seconds: 30),
        what: 'counter first paint; stderr:\n$appStderr',
      );

      transport.send(const ByeFrame());
      await transport.close();

      final exitCode = await app.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () => -1,
      );
      expect(exitCode, 0);
    });
  }, tags: ['integration']);
}

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return false;
  } on TimeoutException {
    return true;
  }
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
  throw StateError('Timed out waiting for $what');
}
