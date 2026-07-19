// Single-owner coordination: `fleury serve` (and `fleury shell`) refuse to
// start while another live instance holds the directory lock, but take over
// cleanly when a crashed process left only a stale `.fleury/handle`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

void main() {
  group('fleury serve single-owner coordination (integration)', () {
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
        final secondStderrSub = second.stderr
            .transform(utf8.decoder)
            .listen(secondStderr.write);
        final secondStdoutDone = second.stdout.drain<void>();

        final exitCode = await _waitForExit(
          second,
          timeout: const Duration(seconds: 15),
          what: 'second fleury serve lock attempt',
        );
        await secondStderrSub.cancel();
        await secondStdoutDone;
        expect(
          exitCode,
          2,
          reason: 'second instance must exit non-zero rather than overwrite',
        );
        expect(
          secondStderr.toString(),
          contains('another fleury serve/shell is already running here'),
        );

        // The first serve must still be running and serving its page. The
        // second instance must not connect to or disturb its app socket.
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
      'a stale managed endpoint is reclaimed before a new serve starts',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_stale_takeover_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Reproduce the exact short endpoint layout a crashed serve leaves.
        final staleEndpoint = Directory.systemTemp.createTempSync('flr_');
        addTearDown(() {
          if (staleEndpoint.existsSync()) {
            staleEndpoint.deleteSync(recursive: true);
          }
        });
        File('${staleEndpoint.path}/owner.lock').createSync();
        final staleSocket = File('${staleEndpoint.path}/s')
          ..writeAsStringSync('stale socket placeholder');
        final fleuryDir = Directory('${tempDir.path}/.fleury')..createSync();
        File('${fleuryDir.path}/handle').writeAsStringSync(staleSocket.path);

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

        expect(
          staleEndpoint.existsSync(),
          isFalse,
          reason: 'the managed endpoint from the crashed owner should go away',
        );

        // If the takeover worked, the new serve is reachable on HTTP.
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
        final resp = await req.close();
        expect(resp.statusCode, 200);
        await resp.drain<void>();
        client.close();
      },
    );

    test('takeover never reclaims another project live endpoint', () async {
      final tempRoot = Directory.systemTemp.createTempSync(
        'fleury_stale_cross_project_',
      );
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      final projectA = Directory('${tempRoot.path}/project_a')..createSync();
      final projectB = Directory('${tempRoot.path}/project_b')..createSync();
      final firstPort = 6120 + Random.secure().nextInt(30);
      final secondPort = firstPort + 40;

      final first = await _startServe(pkgRoot, projectA, firstPort);
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

      final firstHandle = File('${projectA.path}/.fleury/handle');
      final firstSocketPath = firstHandle.readAsStringSync().trim();
      final firstEndpoint = File(firstSocketPath).parent;
      expect(firstEndpoint.existsSync(), isTrue);
      expect(File('${firstEndpoint.path}/owner.lock').existsSync(), isTrue);

      // Project-writable handle input must not be enough to claim ownership:
      // point project B at project A's live endpoint and start a new bridge.
      final projectBHandle = File('${projectB.path}/.fleury/handle');
      projectBHandle.parent.createSync(recursive: true);
      projectBHandle.writeAsStringSync(firstSocketPath);

      final second = await _startServe(pkgRoot, projectB, secondPort);
      addTearDown(() async {
        second.process.kill(ProcessSignal.sigint);
        await second.process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            second.process.kill(ProcessSignal.sigkill);
            return -9;
          },
        );
      });

      expect(
        firstEndpoint.existsSync(),
        isTrue,
        reason: 'project B must not delete project A\'s locked endpoint',
      );
      expect(
        File(firstSocketPath).existsSync(),
        isTrue,
        reason: 'project A\'s app socket must remain attachable',
      );
      expect(File('${firstEndpoint.path}/owner.lock').existsSync(), isTrue);
      expect(firstHandle.readAsStringSync().trim(), firstSocketPath);
      expect(projectBHandle.readAsStringSync().trim(), isNot(firstSocketPath));

      // Project A must remain usable after project B's attempted takeover.
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$firstPort/'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
      client.close();
    });

    test(
      'takeover never deletes an arbitrary path from the handle file',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_stale_unmanaged_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final foreignDir = Directory('${tempDir.path}/do-not-delete')
          ..createSync();
        final sentinel = File('${foreignDir.path}/s')
          ..writeAsStringSync('keep me');
        final fleuryDir = Directory('${tempDir.path}/.fleury')..createSync();
        File('${fleuryDir.path}/handle').writeAsStringSync(sentinel.path);

        final port = 6040 + Random.secure().nextInt(40);
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

        expect(sentinel.readAsStringSync(), 'keep me');
      },
    );

    test(
      'managed-looking endpoint with an extra entry is never reclaimed',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_stale_extra_entry_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // This has the exact path and lock shape of a Fleury endpoint, but the
        // project-controlled handle is not proof that Fleury owns every entry
        // in the directory. Reclamation must refuse it rather than recurse.
        final endpoint = Directory.systemTemp.createTempSync('flr_');
        addTearDown(() {
          if (endpoint.existsSync()) endpoint.deleteSync(recursive: true);
        });
        final ownerLock = File('${endpoint.path}/owner.lock')..createSync();
        final staleSocket = File('${endpoint.path}/s')
          ..writeAsStringSync('stale socket placeholder');
        final sentinel = File('${endpoint.path}/keep.txt')
          ..writeAsStringSync('do not delete');
        final handle = File('${tempDir.path}/.fleury/handle');
        handle.parent.createSync(recursive: true);
        handle.writeAsStringSync(staleSocket.path);

        final port = 6060 + Random.secure().nextInt(20);
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

        expect(endpoint.existsSync(), isTrue);
        expect(ownerLock.existsSync(), isTrue);
        expect(staleSocket.existsSync(), isTrue);
        expect(sentinel.readAsStringSync(), 'do not delete');
        expect(
          handle.readAsStringSync().trim(),
          isNot(staleSocket.path),
          reason:
              'serve should publish its fresh endpoint without reclaiming '
              'the untrusted directory',
        );
      },
    );

    test(
      'SIGTERM removes the bridge handle and private endpoint',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'fleury_serve_sigterm_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final handleFile = File('${tempDir.path}/.fleury/handle');

        final port = 6080 + Random.secure().nextInt(40);
        final svc = await _startServe(pkgRoot, tempDir, port);
        final socketPath = handleFile.readAsStringSync().trim();
        final endpointDirectory = File(socketPath).parent;
        expect(endpointDirectory.existsSync(), isTrue);

        expect(svc.process.kill(ProcessSignal.sigterm), isTrue);
        expect(
          await svc.process.exitCode.timeout(const Duration(seconds: 10)),
          143,
        );
        await _waitFor(
          () => !handleFile.existsSync() && !endpointDirectory.existsSync(),
          timeout: const Duration(seconds: 5),
          what: 'SIGTERM bridge cleanup',
        );
      },
      skip: Platform.isWindows
          ? 'POSIX Unix sockets and SIGTERM are unavailable on Windows.'
          : null,
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

Future<int> _waitForExit(
  Process process, {
  required Duration timeout,
  required String what,
}) async {
  try {
    return await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -9,
    );
    throw StateError(
      '$what did not exit within ${timeout.inSeconds}s; '
      'killed with exit code $exitCode.',
    );
  }
}

Future<void> _waitFor(
  bool Function() condition, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('Timed out waiting for $what', timeout);
}
