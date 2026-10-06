import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'SIGTERM during warm startup reaps the child and removes its endpoint',
    () async {
      final packageRoot = Directory.current.absolute;
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_spawn_sigterm_',
      );
      final stateFile = File('${tempDir.path}/child-state.json');
      final port = await _unusedLoopbackPort();
      final stderrLines = <String>[];

      Process? serve;
      StreamSubscription<String>? stderrSub;
      Future<void>? stdoutDone;
      int? childPid;
      Directory? endpointDirectory;

      addTearDown(() async {
        final process = serve;
        if (process != null) {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () => -9,
          );
        }
        await stderrSub?.cancel();
        await stdoutDone;

        final spawnedPid = childPid;
        if (spawnedPid != null && await _pidExists(spawnedPid)) {
          Process.killPid(spawnedPid, ProcessSignal.sigkill);
        }
        final endpoint = endpointDirectory;
        if (endpoint != null && endpoint.existsSync()) {
          endpoint.deleteSync(recursive: true);
        }
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      serve = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '${packageRoot.path}/bin/fleury.dart',
        'serve',
        '--port=$port',
        '--spawn',
        Platform.resolvedExecutable,
        'run',
        '${packageRoot.path}/test/fixtures/spawn_never_connect.dart',
        stateFile.path,
      ], workingDirectory: tempDir.path);

      final ready = Completer<void>();
      stderrSub = serve.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stderrLines.add(line);
            if (line.contains('fleury serve ready (spawn mode)') &&
                !ready.isCompleted) {
              ready.complete();
            }
          });
      stdoutDone = serve.stdout.drain<void>();

      await ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          'serve did not become ready. stderr:\n${stderrLines.join('\n')}',
        ),
      );
      final state = await _readChildState(stateFile);
      childPid = state.pid;
      final spawnedPid = state.pid;
      final socket = File(state.handle);
      endpointDirectory = socket.parent;
      final endpoint = socket.parent;

      expect(
        await _pidExists(spawnedPid),
        isTrue,
        reason: 'the fixture must be alive in the non-connecting startup gap',
      );
      expect(endpoint.existsSync(), isTrue);
      expect(socket.existsSync(), isTrue);

      expect(serve.kill(ProcessSignal.sigterm), isTrue);
      expect(
        await serve.exitCode.timeout(const Duration(seconds: 10)),
        143,
        reason: 'serve should finish its cleanup before reporting SIGTERM',
      );
      expect(
        await _pidExists(spawnedPid),
        isFalse,
        reason: 'serve must reap its warm child before its own exit completes',
      );

      await _waitFor(
        () async => !socket.existsSync() && !endpoint.existsSync(),
        timeout: const Duration(seconds: 5),
        what: 'spawn endpoint cleanup',
      );
    },
    skip: Platform.isWindows
        ? 'Unix-domain spawn endpoints and SIGTERM are POSIX-only.'
        : null,
    tags: const ['integration'],
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'SIGTERM during upgraded warmup cannot spawn after cleanup snapshots',
    () async {
      final packageRoot = Directory.current.absolute;
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_spawn_upgrade_sigterm_',
      );
      final stateFile = File('${tempDir.path}/child-state.json');
      final childStateDirectory = Directory('${stateFile.path}.children');
      final port = await _unusedLoopbackPort();
      final stderrLines = <String>[];

      Process? serve;
      WebSocket? browser;
      StreamSubscription<String>? stderrSub;
      Future<void>? stdoutDone;

      addTearDown(() async {
        try {
          await browser?.close().timeout(const Duration(seconds: 1));
        } catch (_) {}
        final process = serve;
        if (process != null) {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () => -9,
          );
        }
        await stderrSub?.cancel();
        await stdoutDone;

        for (final state in _readChildStates(childStateDirectory)) {
          if (await _pidExists(state.pid)) {
            Process.killPid(state.pid, ProcessSignal.sigkill);
          }
          final endpoint = File(state.handle).parent;
          if (endpoint.existsSync()) endpoint.deleteSync(recursive: true);
        }
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      serve = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '${packageRoot.path}/bin/fleury.dart',
        'serve',
        '--port=$port',
        '--spawn',
        Platform.resolvedExecutable,
        'run',
        '${packageRoot.path}/test/fixtures/spawn_never_connect.dart',
        stateFile.path,
      ], workingDirectory: tempDir.path);

      final ready = Completer<void>();
      stderrSub = serve.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            stderrLines.add(line);
            if (line.contains('fleury serve ready (spawn mode)') &&
                !ready.isCompleted) {
              ready.complete();
            }
          });
      stdoutDone = serve.stdout.drain<void>();

      await ready.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          'serve did not become ready. stderr:\n${stderrLines.join('\n')}',
        ),
      );
      await _waitFor(
        () async => _readChildStates(childStateDirectory).isNotEmpty,
        timeout: const Duration(seconds: 10),
        what: 'initial warm child',
      );

      browser = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      await _waitFor(
        () async => _readChildStates(childStateDirectory).length >= 2,
        timeout: const Duration(seconds: 10),
        what: 'replacement warm child after WebSocket upgrade',
      );
      expect(_readChildStates(childStateDirectory), hasLength(2));

      expect(serve.kill(ProcessSignal.sigterm), isTrue);
      expect(
        await serve.exitCode.timeout(const Duration(seconds: 10)),
        143,
        reason: 'serve should drain every snapshotted startup before exiting',
      );

      // A buggy handler resumes after its claimed warmup is aborted and starts
      // session 3 while cleanup is still waiting for session 2's kill grace.
      // Once the serve process has exited, every child it launched has had time
      // to record itself, so exactly two records proves the cold fallback was
      // gated as well as checking that both known children were reaped.
      final children = _readChildStates(childStateDirectory);
      expect(
        children,
        hasLength(2),
        reason: 'shutdown must not admit a post-snapshot cold session',
      );
      for (final child in children) {
        expect(
          await _pidExists(child.pid),
          isFalse,
          reason:
              'serve must reap child ${child.pid} before its own exit completes',
        );
      }
      await _waitFor(
        () async {
          for (final child in children) {
            if (File(child.handle).parent.existsSync()) {
              return false;
            }
          }
          return true;
        },
        timeout: const Duration(seconds: 5),
        what: 'upgraded warm endpoints to be cleaned',
      );
    },
    skip: Platform.isWindows
        ? 'Unix-domain spawn endpoints and SIGTERM are POSIX-only.'
        : null,
    tags: const ['integration'],
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<({int pid, String handle})> _readChildState(File stateFile) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (stateFile.existsSync()) {
      try {
        final state = jsonDecode(stateFile.readAsStringSync());
        if (state case {'pid': final int pid, 'handle': final String handle}) {
          return (pid: pid, handle: handle);
        }
      } on FormatException {
        // The fixture may still be flushing the small state file.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('timed out waiting for spawn child state');
}

List<({int pid, String handle})> _readChildStates(Directory directory) {
  if (!directory.existsSync()) return const [];
  final states = <({int pid, String handle})>[];
  for (final entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final state = jsonDecode(entity.readAsStringSync());
      if (state case {'pid': final int pid, 'handle': final String handle}) {
        states.add((pid: pid, handle: handle));
      }
    } on FormatException {
      // A child may still be flushing its own state file.
    }
  }
  states.sort((a, b) => a.pid.compareTo(b.pid));
  return states;
}

Future<bool> _pidExists(int pid) async {
  final result = await Process.run('/bin/kill', <String>['-0', '$pid']);
  return result.exitCode == 0;
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('timed out waiting for $what', timeout);
}

Future<int> _unusedLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
