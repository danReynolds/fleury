// Stale-socket detection: `fleury serve` (and `fleury shell`) refuse
// to start if another live instance owns the directory's
// `.fleury/handle`, but take over cleanly when the handle file is
// pointing at a dead socket left by a crashed previous run.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

void main() {
  group('fleury serve stale-socket detection (integration)', () {
    late String pkgRoot;

    setUpAll(() {
      pkgRoot = Directory.current.path;
    });

    test(
      'second serve in the same directory exits cleanly with a clear error',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_stale_concurrent_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final firstPort = 5950 + Random.secure().nextInt(40);
        final secondPort = firstPort + 1;

        final first = await _startServe(pkgRoot, tempDir, firstPort);
        addTearDown(() async {
          first.process.kill(ProcessSignal.sigint);
          await first.process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              first.process.kill(ProcessSignal.sigkill);
              return -9;
            },
          );
        });

        // Now try a second serve in the SAME directory — should be
        // refused, not silently nuke the first.
        final second = await Process.start(Platform.resolvedExecutable, [
          'run',
          '$pkgRoot/bin/fleury.dart',
          'serve',
          '--port=$secondPort',
        ], workingDirectory: tempDir.path);
        final secondStderr = StringBuffer();
        second.stderr.transform(utf8.decoder).listen(secondStderr.write);

        final exitCode = await second.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => -1,
        );
        expect(
          exitCode,
          2,
          reason: 'second instance must exit non-zero rather than overwrite',
        );
        expect(
          secondStderr.toString(),
          contains('another fleury serve/shell is already running here'),
        );

        // The first serve must STILL be running and serving its page —
        // the probe connection from the second instance shouldn't have
        // killed it.
        final client = HttpClient();
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:$firstPort/'),
        );
        final resp = await req.close();
        expect(
          resp.statusCode,
          200,
          reason:
              'the original serve must still be alive after the failed probe',
        );
        await resp.drain<void>();
        client.close();
      },
    );

    test(
      'a stale handle from a crashed serve lets a new one take over',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_stale_takeover_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Hand-craft a stale handle pointing at a socket path that
        // doesn't exist. This is exactly the state a crashed serve
        // leaves behind.
        final fleuryDir = Directory('${tempDir.path}/.fleury')..createSync();
        File(
          '${fleuryDir.path}/handle',
        ).writeAsStringSync('${fleuryDir.path}/dead.sock');

        final port = 6000 + Random.secure().nextInt(40);
        final svc = await _startServe(pkgRoot, tempDir, port);
        addTearDown(() async {
          svc.process.kill(ProcessSignal.sigint);
          await svc.process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              svc.process.kill(ProcessSignal.sigkill);
              return -9;
            },
          );
        });

        // If the takeover worked, the new serve is reachable on HTTP.
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
        final resp = await req.close();
        expect(resp.statusCode, 200);
        await resp.drain<void>();
        client.close();
      },
    );
  }, tags: ['integration']);
}

class _ServeHandle {
  _ServeHandle(this.process);
  final Process process;
}

Future<_ServeHandle> _startServe(
  String pkgRoot,
  Directory cwd,
  int port,
) async {
  final proc = await Process.start(Platform.resolvedExecutable, [
    'run',
    '$pkgRoot/bin/fleury.dart',
    'serve',
    '--port=$port',
  ], workingDirectory: cwd.path);
  final ready = Completer<void>();
  final buf = StringBuffer();
  proc.stderr.transform(utf8.decoder).listen((chunk) {
    buf.write(chunk);
    if (buf.toString().contains('fleury serve ready') && !ready.isCompleted) {
      ready.complete();
    }
  });
  await ready.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () =>
        throw StateError('serve did not start within 10s. stderr:\n$buf'),
  );
  return _ServeHandle(proc);
}
