// Shared spawn-and-attach for native process hosts (`fleury serve --spawn`, the
// MCP/agent bridge). Both bind a Unix socket, point `FLEURY_HANDLE` at it, spawn
// the app, and wait for it to connect back — so the mechanics live here once
// instead of drifting across two call sites.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../fleury_core.dart' show sanitizeForDisplay;

/// A spawned Fleury app and its single live connection.
final class SpawnedFleuryApp {
  SpawnedFleuryApp._(this.socket, this.process, this._dispose);

  /// The app's connection (the render wire). Wrap it in a transport to drive the
  /// app, or pump its bytes to a browser.
  final Socket socket;

  /// The app subprocess.
  final Process process;

  final Future<int> Function() _dispose;

  /// Tears down: cancels stdout/stderr forwarding, signals the process
  /// (SIGTERM, then SIGKILL after a grace period), and removes the socket (and
  /// its temp dir, if this spawn created it). Idempotent. Returns the process's
  /// exit code (or the grace-kill sentinel), so a caller needn't await
  /// `process.exitCode` itself.
  Future<int> dispose() => _dispose();
}

/// Thrown when an app can't be attached — failed to spawn, never connected, or
/// exited before connecting.
final class FleurySpawnException implements Exception {
  const FleurySpawnException(this.message);
  final String message;
  @override
  String toString() => 'FleurySpawnException: $message';
}

/// Binds a Unix socket, spawns [command] with `FLEURY_HANDLE` pointed at it, and
/// awaits the app's FIRST connection — racing the process exiting before it
/// connects and [connectTimeout]. Once connected the listening socket is CLOSED,
/// so the host only ever reads that one connection: a later connect is refused
/// (ECONNREFUSED), and any connection already queued in the OS backlog is never
/// accepted or read — so it can inject nothing and its writes ultimately fail.
/// The accepted connection stays open.
///
/// [socketPath] overrides the auto-generated path (e.g. a per-session socket);
/// when null a short `/tmp/fleury-host-*/app-$pid.sock` is used and removed on
/// [SpawnedFleuryApp.dispose]. With an explicit [socketPath] only the socket file
/// is removed — the caller owns its directory.
///
/// [onLog] receives the app's own stdout/stderr line by line (sanitized), tagged
/// `out`/`err`, so the host can forward it without it polluting the wire.
///
/// [abort], if given and it completes before the app connects, abandons the
/// spawn (tears the process + socket down and throws) — e.g. `fleury serve`
/// passes the browser-closed signal so a vanished browser doesn't leave an
/// orphan app.
///
/// Throws [FleurySpawnException] on exit-before-connect, timeout, or abort, and
/// rethrows a [ProcessException] if the command can't be launched.
Future<SpawnedFleuryApp> spawnFleuryApp({
  required List<String> command,
  String? socketPath,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration killGrace = const Duration(seconds: 2),
  Map<String, String>? environment,
  void Function(String tag, String line)? onLog,
  Future<void>? abort,
}) async {
  if (command.isEmpty) {
    throw ArgumentError.value(command, 'command', 'must be non-empty');
  }

  final Directory? ownedDir = socketPath == null ? _createHandleDir() : null;
  final path = socketPath ?? '${ownedDir!.path}/app-$pid.sock';
  try {
    File(path).deleteSync();
  } on FileSystemException {
    // Not there — fine.
  }

  final ServerSocket server;
  try {
    server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
  } catch (_) {
    // Bind failed (e.g. the unix path exceeded the ~104-byte limit, or the
    // address is in use) — release the temp dir we just created so a failed
    // spawn doesn't leak it under /tmp. The socket file (if any) goes too.
    try {
      File(path).deleteSync();
    } catch (_) {}
    if (ownedDir != null) {
      try {
        ownedDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    rethrow;
  }
  var serverClosed = false;
  Future<void> closeServer() async {
    if (serverClosed) return;
    serverClosed = true;
    await server.close();
  }

  Future<void> removeSocket() async {
    await closeServer();
    try {
      File(path).deleteSync();
    } catch (_) {}
    if (ownedDir != null) {
      try {
        ownedDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  final env = Map<String, String>.from(environment ?? Platform.environment)
    ..['FLEURY_HANDLE'] = path;
  env['COLORTERM'] = env['COLORTERM'] ?? 'truecolor';

  final Process process;
  try {
    process = await Process.start(
      command.first,
      command.sublist(1),
      environment: env,
    );
  } on ProcessException {
    await removeSocket();
    rethrow;
  }

  // The app renders to the socket; its stdout/stderr is its own log output.
  StreamSubscription<String> forward(String tag, Stream<List<int>> source) =>
      source
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => onLog?.call(tag, sanitizeForDisplay(line)));
  final outSub = forward('out', process.stdout);
  final errSub = forward('err', process.stderr);

  Future<int> killProcess() {
    process.kill(ProcessSignal.sigterm);
    return process.exitCode
        .timeout(
          killGrace,
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -9;
          },
        )
        .catchError((_) => -1);
  }

  // A cancellable timeout arm, so a successful connect doesn't leave a timer
  // armed for the rest of connectTimeout.
  final timedOut = Completer<Object>();
  final timer = Timer(connectTimeout, () {
    if (!timedOut.isCompleted) timedOut.complete(const _ConnectTimedOut());
  });
  final connection = await Future.any<Object>([
    server.first,
    process.exitCode.then((code) => _AppExited(code)),
    timedOut.future,
    if (abort != null) abort.then((_) => const _Aborted()),
  ]);
  timer.cancel();

  if (connection is! Socket) {
    await outSub.cancel();
    await errSub.cancel();
    // SIGTERM→grace→SIGKILL and, crucially, AWAIT exitCode — a bare fire-and-
    // forget kill never reaps the child, leaking a process handle per failed
    // spawn (a host that retries flaky apps accumulates them). For _AppExited the
    // process is already gone, so this resolves instantly.
    await killProcess();
    await removeSocket();
    final reason = switch (connection) {
      _AppExited(:final code) => 'app exited (code $code) before connecting',
      _Aborted() => 'aborted before the app connected',
      _ => 'app did not connect within ${connectTimeout.inSeconds}s',
    };
    throw FleurySpawnException(
      'Failed to attach to `${command.join(' ')}`: $reason. '
      'Make sure it calls runApp(...) so it auto-discovers FLEURY_HANDLE.',
    );
  }

  // Connected: stop accepting, so the host only ever reads this one socket. A
  // later connect is refused; one already queued in the backlog may complete at
  // the socket layer but is never accept()ed or read, so it injects nothing and
  // its writes eventually fail. The accepted socket lives on.
  await closeServer();

  // Cache the teardown future so concurrent (or repeat) dispose() calls all await
  // the SAME run and observe the real exit code — not a stale sentinel from a
  // second call that raced in while the first was still inside killProcess().
  Future<int>? disposing;
  Future<int> dispose() {
    return disposing ??= () async {
      await outSub.cancel();
      await errSub.cancel();
      final code = await killProcess();
      await removeSocket();
      return code;
    }();
  }

  return SpawnedFleuryApp._(connection, process, dispose);
}

// Unix socket paths cap at ~104 bytes on macOS, so prefer a short /tmp base over
// the (often deep) system temp dir.
Directory _createHandleDir() {
  final shortTemp = Directory('/tmp');
  final base = !Platform.isWindows && shortTemp.existsSync()
      ? shortTemp
      : Directory.systemTemp;
  return base.createTempSync('fleury-host-');
}

final class _AppExited {
  const _AppExited(this.code);
  final int code;
}

final class _ConnectTimedOut {
  const _ConnectTimedOut();
}

final class _Aborted {
  const _Aborted();
}
