// `fleury` — companion CLI for the fleury framework.
//
// Subcommands:
//
//   fleury create  Generate a tested Fleury application with a terminal-safe
//                  VS Code F5 configuration.
//
//   fleury shell    Run a local-display proxy so a Fleury app launched
//                  under a debugger (VS Code, IntelliJ) can render into
//                  THIS terminal instead of fighting the IDE's stdout.
//                  Implements the Unix-socket transport defined in
//                  `lib/src/remote/`.
//
//   fleury serve    Same idea, WebSocket transport: the app renders into a
//                  DOM cell grid in the browser (no terminal emulator).
//
//   fleury benchmark
//                  Run contributor benchmark and profiling workflows from
//                  a local Fleury framework checkout.
//
// Usage:
//
//   $ fleury shell                 # in terminal A
//   # → "fleury shell ready, waiting for an app to attach..."
//
//   # In VSCode / IntelliJ, F5 your app as you normally would.
//   # The app auto-detects `.fleury/handle` and connects.
//   # Terminal A shows the TUI; the IDE keeps the debugger console.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:fleury/src/cli/create_command.dart';
import 'package:fleury/src/cli/dart_sdk.dart';
import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/remote/buffered_browser_input.dart';
import 'package:fleury/src/remote/remote_client_asset.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/serve_index_html.dart';
import 'package:fleury/src/remote/shell_init.dart';
import 'package:fleury/src/remote/spawn.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';
import 'package:fleury/src/terminal/capabilities.dart';
import 'package:fleury/src/terminal/diagnostics.dart';
import 'package:fleury/src/terminal/native_driver.dart';
import 'package:fleury/src/terminal/terminal_probe.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(2);
  }
  switch (args[0]) {
    case 'create':
      exit(await runCreateCommand(args.sublist(1)));
    case 'shell':
      exit(await _runShell(args.sublist(1)));
    case 'serve':
      exit(await _runServe(args.sublist(1)));
    case 'diagnose':
      exit(await _runDiagnose(args.sublist(1)));
    case 'dev':
      exit(await _runDev(args.sublist(1)));
    case 'benchmark':
      exit(await _runBenchmark(args.sublist(1)));
    case '-h':
    case '--help':
    case 'help':
      _printUsage();
      exit(0);
    default:
      stderr.writeln('Unknown subcommand: ${args[0]}');
      _printUsage();
      exit(2);
  }
}

void _printUsage() {
  stderr.writeln('fleury <subcommand> [args]');
  stderr.writeln('');
  stderr.writeln('App developer commands:');
  stderr.writeln(
    '  create   Create a Fleury application with tests and a working F5 setup.',
  );
  stderr.writeln(
    '           Usage: fleury create <directory> [--no-editor-config] [--no-pub]',
  );
  stderr.writeln(
    '  shell    Proxy fleury-app rendering through this terminal '
    'so the app can be',
  );
  stderr.writeln('           launched under an IDE debugger.');
  stderr.writeln(
    '  serve    Proxy fleury-app rendering to a browser via '
    'WebSocket into a DOM cell grid.',
  );
  stderr.writeln(
    '           Options: --port=<n> (default 5777), '
    '--host=<addr> (default 127.0.0.1),',
  );
  stderr.writeln(
    '                    --allow-origin=<origin>, --token=<secret> '
    '(require ?token= on /ws),',
  );
  stderr.writeln(
    '                    --spawn <cmd ...> '
    '(per-browser subprocess isolation).',
  );
  stderr.writeln(
    '  diagnose Print terminal + capability information for bug '
    'reports.',
  );
  stderr.writeln(
    '           Options: --json, --json-output=<path>, --probe, '
    '--probe-timeout=<ms>',
  );
  stderr.writeln('');
  stderr.writeln('Framework checkout commands:');
  stderr.writeln(
    '  dev      Fleury framework contributor commands. Requires a '
    'framework checkout.',
  );
  stderr.writeln(
    '           Examples: fleury dev list; fleury dev check --quick; '
    'fleury dev demo; fleury dev storybook verify',
  );
  stderr.writeln(
    '  benchmark Run local and peer benchmark/profiling workflows. '
    'Requires a',
  );
  stderr.writeln('           framework checkout.');
  stderr.writeln(
    '           Examples: fleury benchmark list; fleury benchmark wire sb6 --help',
  );
}

Future<int> _runDev(List<String> args) async {
  final forwarded = args.isEmpty || (args.length == 1 && args.first == 'help')
      ? const <String>['--help']
      : args;
  return _runRepoDevTool(forwarded, commandName: 'fleury dev');
}

Future<int> _runBenchmark(List<String> args) async {
  final forwarded = args.isEmpty || (args.length == 1 && args.first == 'help')
      ? const <String>['benchmark', '--help']
      : <String>['benchmark', ...args];
  return _runRepoDevTool(forwarded, commandName: 'fleury benchmark');
}

Future<int> _runRepoDevTool(
  List<String> forwarded, {
  required String commandName,
}) async {
  final root = _findFleuryRepoRoot(Directory.current);
  if (root == null) {
    stderr.writeln(
      '$commandName commands require a Fleury framework checkout.',
    );
    stderr.writeln(
      'Run from the repo root or a subdirectory, or use public commands '
      'like `fleury diagnose`.',
    );
    return 2;
  }

  final devTool = File('${root.path}/tool/fleury_dev.dart');
  final Process process;
  try {
    process = await Process.start(
      dartSdkExecutable,
      <String>[devTool.path, ...forwarded],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException catch (error) {
    stderr.writeln(
      '$commandName could not start the Dart SDK: ${error.message}',
    );
    stderr.writeln('Install the Dart SDK and ensure `dart` is on PATH.');
    return 1;
  }
  return process.exitCode;
}

Directory? _findFleuryRepoRoot(Directory start) {
  var directory = start.absolute;
  while (true) {
    if (_isFleuryRepoRoot(directory)) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

bool _isFleuryRepoRoot(Directory directory) {
  return File('${directory.path}/tool/fleury_dev.dart').existsSync() &&
      File('${directory.path}/packages/fleury/bin/fleury.dart').existsSync();
}

Future<int> _runShell(List<String> args) async {
  // The shell proxies a real terminal to a remote app: it forwards local
  // keystrokes (so it puts its own stdin into raw mode) and writes the app's
  // frames to stdout. Refuse a non-tty stdin up front — otherwise a
  // backgrounded / redirected-stdin invocation (`fleury shell < /dev/null`)
  // binds the socket, then the first app-attach throws a StdinException from
  // _runSession's `stdin.lineMode` setup, escaping the accept callback as an
  // unhandled async error and killing the shell without cleanup (a stale
  // .fleury/handle + shell.sock left behind). Checked before the stdout guard
  // so a stdin-less shell is named even when stdout is also redirected.
  if (!stdin.hasTerminal) {
    stderr.writeln(
      'fleury shell: stdin is not a terminal — no keystrokes to forward. Run '
      'it in an interactive terminal, not backgrounded or with redirected '
      'stdin.',
    );
    return 2;
  }
  if (!stdout.hasTerminal) {
    stderr.writeln(
      'fleury shell: stdout is not a terminal — nothing to '
      'render into.',
    );
    return 2;
  }
  if (!stdin.hasTerminal || !_stdinSupportsTerminalModes()) {
    stderr.writeln(
      'fleury shell: stdin is not a terminal — input cannot be forwarded.',
    );
    return 2;
  }

  final handleDir = Directory('.fleury');
  if (!handleDir.existsSync()) handleDir.createSync(recursive: true);
  final handleFile = File('${handleDir.path}/handle');
  final handleLock = _tryAcquireHandleLock(handleDir);
  if (handleLock == null) {
    stderr.writeln(
      'fleury shell: another fleury shell/serve is already running here '
      '(handle at ${handleFile.path}).',
    );
    stderr.writeln('Stop it first, or run from a different directory.');
    return 2;
  }
  _LocalSocketEndpoint.reclaimStaleFrom(handleFile);

  late final _LocalSocketEndpoint endpoint;
  try {
    endpoint = _LocalSocketEndpoint.create();
  } on FileSystemException catch (error) {
    _releaseHandleLock(handleLock);
    stderr.writeln('fleury shell: could not allocate a local socket: $error');
    return 1;
  }
  final socketPath = endpoint.path;

  late final ServerSocket server;
  try {
    server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    handleFile.writeAsStringSync(socketPath);
  } on Object catch (error) {
    endpoint.delete();
    _releaseHandleLock(handleLock);
    stderr.writeln('fleury shell: could not bind the local socket: $error');
    return 1;
  }
  final exitCode = Completer<int>();

  final shutdownSession = Completer<void>();
  Future<int>? activeSession;
  Future<void>? cleanupFuture;

  Future<void> cleanup() {
    final existing = cleanupFuture;
    if (existing != null) return existing;

    cleanupFuture = () async {
      if (!shutdownSession.isCompleted) shutdownSession.complete();
      try {
        await server.close();
      } catch (_) {
        // Keep cleaning up the discovery file and endpoint even when the
        // listener has already been torn down by the operating system.
      }

      final session = activeSession;
      if (session != null) {
        try {
          await session.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // The process is exiting; avoid hanging forever if the terminal
          // stream refuses to drain during signal handling.
        } catch (_) {
          // Session cleanup is best-effort during signal handling. Keep the
          // shell exit path deterministic even if the PTY has already closed.
        }
      }

      try {
        handleFile.deleteSync();
      } catch (_) {}
      endpoint.delete();
      _releaseHandleLock(handleLock);
    }();

    return cleanupFuture!;
  }

  // Terminal shutdown signals tear down the proxy. The connected app sees its
  // transport drop and exits cleanly via the events `onDone` path.
  var signalShutdownStarted = false;
  late final List<StreamSubscription<ProcessSignal>> signalSubs;
  signalSubs = _watchShutdownSignals((code, _) async {
    if (signalShutdownStarted) return;
    signalShutdownStarted = true;
    await _cancelSignalSubscriptions(signalSubs);
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(code);
  });

  server.listen((client) async {
    // One app at a time. A second connection while one is live gets
    // dropped — the shell terminal can only show one TUI's frames.
    if (activeSession != null) {
      client.destroy();
      stderr.writeln(
        '[shell] another app connected while a session was live - dropped',
      );
      return;
    }
    final session = _runSession(client, shutdownSignal: shutdownSession.future);
    activeSession = session;
    var code = 1;
    try {
      code = await session;
    } on Object catch (error, stackTrace) {
      stderr
        ..writeln('fleury shell: session failed: $error')
        ..writeln(stackTrace);
    }
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(code);
  });

  // Readiness is a lifecycle contract: only announce it after the listener and
  // shutdown cleanup are both armed.
  stderr.writeln('fleury shell ready (handle at ${handleFile.path})');
  stderr.writeln('');
  stderr.writeln('To attach an app:');
  stderr.writeln('  • run it from this directory:  dart run bin/run_app.dart');
  stderr.writeln('  • or from any directory, set FLEURY_HANDLE:');
  stderr.writeln(
    '      FLEURY_HANDLE=${_posixShellQuote(socketPath)} '
    'dart run bin/run_app.dart',
  );
  stderr.writeln('  • or launch it from your IDE — the discovery file');
  stderr.writeln('    handles the rest automatically.');

  return exitCode.future;
}

/// Drives a single connected app: hand off our terminal to the app's
/// frames, pump local stdin and SIGWINCH back to the app, and clean
/// up when the socket closes.
Future<int> _runSession(Socket client, {Future<void>? shutdownSignal}) async {
  final transport = UnixSocketFrameTransport.fromSocket(client);
  if (shutdownSignal != null) {
    unawaited(
      shutdownSignal.then((_) async {
        try {
          transport.send(const ByeFrame());
        } catch (_) {
          // Peer may already be gone; close below still tears down locally.
        }
        await transport.close();
      }),
    );
  }

  // Take over our own terminal. The app's enter sequences would do this
  // on the LOCAL side normally; here, the app is remote and its alt
  // screen / hide-cursor / raw-mode sequences arrive as OUTPUT frames,
  // which we write verbatim to our stdout. But WE need to be the one
  // who set raw mode on our stdin (so we read keystrokes instead of
  // line-buffered input) and put OUR terminal into a clean state.
  bool? originalLine;
  bool? originalEcho;
  try {
    originalLine = stdin.lineMode;
    originalEcho = stdin.echoMode;
    stdin.lineMode = false;
    stdin.echoMode = false;
  } on Object {
    try {
      if (originalLine != null) stdin.lineMode = originalLine;
    } catch (_) {}
    try {
      if (originalEcho != null) stdin.echoMode = originalEcho;
    } catch (_) {}
    rethrow;
  }
  StreamSubscription<ProcessSignal>? winchSub;
  StreamSubscription<List<int>>? stdinSub;
  try {
    // Bracketed paste + Kitty keyboard mirror the app's own setup so the
    // bytes coming back to it match what a normal terminal would send.
    stdout.write('\x1B[?1049h\x1B[?25l\x1B[?2004h\x1B[>1u');

    // Initial handshake — send what the app needs to lay out its first
    // frame correctly: actual size + the capabilities OUR terminal
    // negotiated with the user's real terminal emulator.
    final capabilities = detectTerminalCapabilitiesFromEnvironment(
      Platform.environment,
    );
    transport.send(
      buildShellInitFrame(size: _localSize(), capabilities: capabilities),
    );

    // SIGWINCH → RESIZE frame. The app reflows on its end.
    winchSub = ProcessSignal.sigwinch.watch().listen((_) {
      transport.send(ResizeFrame(_localSize()));
    });

    // Stdin bytes → INPUT frame. No parsing; the app's own InputParser
    // does the work on the other end.
    stdinSub = stdin.listen(
      (bytes) => transport.send(InputFrame(_asUint8(bytes))),
      cancelOnError: false,
    );

    // App's OUTPUT frames → stdout verbatim.
    await for (final frame in transport.incoming) {
      if (frame is OutputFrame) {
        stdout.add(frame.bytes);
      } else if (frame is ByeFrame) {
        break;
      }
      // INIT / INPUT / RESIZE from the app side would be a protocol
      // violation; silently drop rather than crash the shell.
    }
  } finally {
    await winchSub?.cancel();
    await stdinSub?.cancel();
    // Restore terminal modes. Mirror order of the enter sequences.
    try {
      stdout.write('\x1B[<u\x1B[?2004l\x1B[?25h\x1B[?1049l');
    } catch (_) {}
    try {
      stdin.lineMode = originalLine;
    } catch (_) {}
    try {
      stdin.echoMode = originalEcho;
    } catch (_) {}
    await transport.close();
  }
  return 0;
}

CellSize _localSize() {
  try {
    return CellSize(stdout.terminalColumns, stdout.terminalLines);
  } on StdoutException {
    return const CellSize(80, 24);
  }
}

bool _stdinSupportsTerminalModes() {
  try {
    stdin.lineMode;
    stdin.echoMode;
    return true;
  } on StdinException {
    return false;
  }
}

/// Stdin's stream gives us `List<int>`; the protocol wants `Uint8List`
/// for zero-copy framing downstream.
Uint8List _asUint8(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

String _posixShellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

Future<int> _runServe(List<String> args) async {
  var port = 5777;
  var host = '127.0.0.1';
  var originPolicy = const _ServeOriginPolicy.sameOrigin();
  String? token;
  List<String>? spawnCmd;
  // The debug wire (read_frames / read_logs / read_errors with full stacks)
  // is opt-in for served apps: a shared URL must not exfiltrate diagnostics
  // by default. `--debug` re-enables it (the local-dev loop).
  var debugWire = false;
  // Every browser session is a full app subprocess; cap them so an open
  // port (or a reconnect loop) can't fork-bomb the host.
  var maxSessions = 8;
  // --debug / --max-sessions only apply in --spawn mode (bridge mode connects
  // to an app it doesn't own, so it can neither set its env nor multi-session).
  // Track a seen spawn-only flag to warn if there's no --spawn.
  String? spawnOnlyFlagSeen;
  // `--spawn` is greedy: everything after it (in argv order) becomes
  // the subprocess command. So `--port=N` and `--host=...` must come
  // BEFORE `--spawn`, which is the natural shell ordering anyway.
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--port=')) {
      port = int.parse(arg.substring('--port='.length));
    } else if (arg.startsWith('--host=')) {
      host = arg.substring('--host='.length);
    } else if (arg.startsWith('--allow-origin=')) {
      final origin = arg.substring('--allow-origin='.length);
      final updated = originPolicy.allow(origin);
      if (updated == null) {
        stderr.writeln(
          '--allow-origin must be "*" or an http(s) origin such as '
          'http://localhost:3000.',
        );
        return 2;
      }
      originPolicy = updated;
    } else if (arg.startsWith('--token=')) {
      token = arg.substring('--token='.length);
      if (token.isEmpty) {
        stderr.writeln('--token requires a non-empty secret.');
        return 2;
      }
    } else if (arg == '--debug') {
      debugWire = true;
      spawnOnlyFlagSeen = '--debug';
    } else if (arg.startsWith('--max-sessions=')) {
      final raw = arg.substring('--max-sessions='.length);
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 1) {
        stderr.writeln('--max-sessions requires a positive integer.');
        return 2;
      }
      maxSessions = parsed;
      spawnOnlyFlagSeen = '--max-sessions';
    } else if (arg == '--spawn') {
      spawnCmd = args.sublist(i + 1);
      if (spawnCmd.isEmpty) {
        stderr.writeln(
          '--spawn requires a command, e.g. `fleury serve --spawn dart run '
          'bin/run_app.dart`',
        );
        return 2;
      }
      break;
    } else if (arg == '-h' || arg == '--help') {
      stderr.writeln(
        'fleury serve [--port=<n>] [--host=<addr>] '
        '[--allow-origin=<origin>] [--token=<secret>] [--debug] '
        '[--max-sessions=<n>] [--spawn <cmd> ...]',
      );
      return 0;
    } else {
      stderr.writeln('Unknown option: $arg');
      return 2;
    }
  }

  // --debug / --max-sessions are inert without --spawn (bridge mode doesn't
  // own the app) — say so rather than silently ignore them.
  if (spawnCmd == null && spawnOnlyFlagSeen != null) {
    stderr.writeln(
      '[serve] WARNING: $spawnOnlyFlagSeen only applies with --spawn; '
      'ignored in bridge mode.',
    );
  }

  // The wire carries full app control: semantic actions, key/text
  // injection, and the (redacted) semantic tree. Off loopback, anyone
  // who can reach the port owns the app — make that loud.
  if (!_isLoopbackHost(host)) {
    stderr.writeln(
      '[serve] WARNING: binding to $host exposes this app to the '
      'network. Anyone who can reach the port can drive the UI and '
      'read its (redacted) semantic tree.',
    );
    if (token == null) {
      stderr.writeln(
        '[serve] WARNING: no --token set. Pass --token=<secret> and '
        'share the URL as http://$host:$port/?token=<secret>.',
      );
    }
  }

  return spawnCmd != null
      ? _runServeSpawn(
          host: host,
          port: port,
          originPolicy: originPolicy,
          token: token,
          command: spawnCmd,
          debugWire: debugWire,
          maxSessions: maxSessions,
        )
      : _runServeBridge(
          host: host,
          port: port,
          originPolicy: originPolicy,
          token: token,
        );
}

bool _isLoopbackHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  final parsed = InternetAddress.tryParse(host);
  return parsed != null && parsed.isLoopback;
}

/// Token gate for the WebSocket endpoint. Origin checks stop cross-site
/// browser pages; the token additionally stops any local process (or,
/// off loopback, any network peer) that can open a socket but doesn't
/// know the secret.
bool _isAuthorizedWebSocketRequest(HttpRequest req, String? token) {
  if (token == null) return true;
  return req.uri.queryParameters['token'] == token;
}

Future<void> _rejectUnauthorizedWebSocket(HttpRequest req) async {
  req.response.statusCode = HttpStatus.forbidden;
  req.response.write('missing or invalid token');
  await req.response.close();
}

/// Bridge mode: one shared socket; user starts the app process
/// themselves. Single session at a time. Good for IDE debug and
/// local demos.
Future<int> _runServeBridge({
  required String host,
  required int port,
  required _ServeOriginPolicy originPolicy,
  String? token,
}) async {
  final handleDir = Directory('.fleury');
  if (!handleDir.existsSync()) handleDir.createSync(recursive: true);
  final handleFile = File('${handleDir.path}/handle');
  final handleLock = _tryAcquireHandleLock(handleDir);
  if (handleLock == null) {
    stderr.writeln(
      'fleury serve: another fleury serve/shell is already running here '
      '(handle at ${handleFile.path}).',
    );
    stderr.writeln('Stop it first, or run from a different directory.');
    return 2;
  }
  _LocalSocketEndpoint.reclaimStaleFrom(handleFile);

  late final _LocalSocketEndpoint endpoint;
  try {
    endpoint = _LocalSocketEndpoint.create();
  } on FileSystemException catch (error) {
    _releaseHandleLock(handleLock);
    stderr.writeln('fleury serve: could not allocate a local socket: $error');
    return 1;
  }
  final socketPath = endpoint.path;

  late final ServerSocket appServer;
  try {
    appServer = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    handleFile.writeAsStringSync(socketPath);
  } on Object catch (error) {
    endpoint.delete();
    _releaseHandleLock(handleLock);
    stderr.writeln('fleury serve: could not bind the local socket: $error');
    return 1;
  }
  late final HttpServer httpServer;
  try {
    httpServer = await HttpServer.bind(host, port);
  } on Object catch (error) {
    await appServer.close();
    try {
      handleFile.deleteSync();
    } catch (_) {}
    endpoint.delete();
    _releaseHandleLock(handleLock);
    stderr.writeln('fleury serve: could not bind $host:$port: $error');
    return 1;
  }

  final exitCode = Completer<int>();

  // Pairing state. Order of arrival doesn't matter — first one
  // through the door waits for its partner.
  Socket? pendingApp;
  BufferedBrowserInput? pendingBrowser;
  var sessionInFlight = false;

  void tryPair() {
    final app = pendingApp;
    final browser = pendingBrowser;
    if (app == null || browser == null) return;
    pendingApp = null;
    pendingBrowser = null;
    sessionInFlight = true;
    stderr.writeln('[serve] paired app ↔ browser; session live');
    _pumpBytes(
      app: app,
      browser: browser.webSocket!,
      browserInput: browser.stream,
      onDone: () {
        unawaited(browser.dispose());
        sessionInFlight = false;
        stderr.writeln('[serve] session ended; ready for the next attach');
      },
    );
  }

  appServer.listen((appSocket) {
    if (sessionInFlight || pendingApp != null) {
      // One session at a time. Drop the new connection cleanly.
      appSocket.destroy();
      stderr.writeln(
        '[serve] another app connected while a session was live — dropped',
      );
      return;
    }
    pendingApp = appSocket;
    stderr.writeln('[serve] app connected, waiting for a browser');
    tryPair();
  });

  httpServer.listen((req) async {
    if (req.uri.path == '/ws') {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      if (!_isAllowedWebSocketOrigin(req, originPolicy, boundHost: host)) {
        await _rejectForbiddenWebSocketOrigin(req);
        return;
      }
      if (!_isAuthorizedWebSocketRequest(req, token)) {
        await _rejectUnauthorizedWebSocket(req);
        return;
      }
      // Contain any upgrade-time error (client reset mid-handshake, I/O fault)
      // so it can't escape as an unhandled async error from this root-zone
      // listener. This bridge path has no admission counter, so nothing to
      // release — just drop the connection.
      final WebSocket ws;
      try {
        ws = await WebSocketTransformer.upgrade(req);
      } catch (error) {
        stderr.writeln(
          '[serve] rejecting connection: websocket upgrade '
          'failed ($error).',
        );
        try {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
        } catch (_) {
          // The socket may already be hijacked/closed by the failed upgrade.
        }
        return;
      }
      if (sessionInFlight || pendingBrowser != null) {
        ws.add(
          Uint8List.fromList(
            encodeFrame(
              OutputFrame(
                Uint8List.fromList(
                  '\x1B[31mAnother browser session is already live.\x1B[0m\r\n'
                      .codeUnits,
                ),
              ),
            ),
          ),
        );
        await ws.close();
        return;
      }
      final browser = BufferedBrowserInput(ws);
      pendingBrowser = browser;
      unawaited(
        browser.closed.then((_) {
          if (pendingBrowser == browser) {
            pendingBrowser = null;
            // `closed` intentionally wins the race with a potentially stalled
            // WebSocket close handshake. Deterministically release the source
            // subscription/controller before admitting the next browser.
            unawaited(
              browser.dispose().catchError((Object error) {
                stderr.writeln(
                  '[serve] browser input cleanup failed before attach: $error',
                );
              }),
            );
            stderr.writeln('[serve] browser disconnected before app attach');
          }
        }),
      );
      stderr.writeln('[serve] browser connected, waiting for an app');
      tryPair();
    } else {
      await _serveStaticAsset(req);
    }
  });

  Future<void>? cleanupFuture;
  Future<void> cleanup() {
    final existing = cleanupFuture;
    if (existing != null) return existing;
    cleanupFuture = () async {
      try {
        await appServer.close();
      } catch (_) {}
      try {
        await httpServer.close(force: true);
      } catch (_) {}
      pendingApp?.destroy();
      try {
        await pendingBrowser?.dispose();
      } catch (_) {}
      try {
        handleFile.deleteSync();
      } catch (_) {}
      endpoint.delete();
      _releaseHandleLock(handleLock);
    }();
    return cleanupFuture!;
  }

  var signalShutdownStarted = false;
  late final List<StreamSubscription<ProcessSignal>> signalSubs;
  signalSubs = _watchShutdownSignals((code, _) async {
    if (signalShutdownStarted) return;
    signalShutdownStarted = true;
    await _cancelSignalSubscriptions(signalSubs);
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(code);
  });

  // Do not let callers treat the bridge as ready until its listeners and
  // shutdown cleanup are fully armed.
  stderr.writeln('fleury serve ready (bridge mode)');
  stderr.writeln('  browser:    http://$host:$port');
  stderr.writeln('  app handle: $socketPath');
  stderr.writeln('');
  stderr.writeln('Open the URL in your browser, then attach your app:');
  stderr.writeln('  • from this directory:  dart run bin/run_app.dart');
  stderr.writeln(
    '  • from any directory:   '
    'FLEURY_HANDLE=${_posixShellQuote(socketPath)} '
    'dart run bin/run_app.dart',
  );
  stderr.writeln('');
  stderr.writeln(
    'Or use --spawn to have serve own the subprocess and isolate '
    'per browser:',
  );
  stderr.writeln('  fleury serve --spawn dart run bin/run_app.dart');

  return exitCode.future;
}

/// Pure byte pump between an app's Unix-socket end and a browser's
/// WebSocket end. Both sides speak our framed binary protocol, so the
/// pump doesn't decode — bytes in, bytes out, in order.
void _pumpBytes({
  required Socket app,
  required WebSocket browser,
  Stream<List<int>>? browserInput,
  required void Function() onDone,
}) {
  var stopped = false;
  Future<void> stop() async {
    if (stopped) return;
    stopped = true;
    // Destroy (not close) the app socket: it forcibly ends the stream
    // bound by `browser.addStream(app)` and errors the sink bound by
    // `app.addStream(...)`, so neither addStream is left dangling — which
    // a graceful `close()` mid-addStream would trip over.
    try {
      app.destroy();
    } catch (_) {}
    try {
      await browser.close();
    } catch (_) {}
    onDone();
  }

  // App → browser. `addStream` (not per-chunk `add`) is the backpressure
  // path: it forwards each app chunk as one WebSocket binary message AND
  // pauses reading from the app socket when the browser's socket send
  // buffer is full. A slow/stalled browser therefore stalls the app
  // rather than buffering its frames unboundedly in server memory — the
  // slow-consumer memory-DoS the per-chunk `add` was exposed to. (Frame
  // boundaries are still recovered by the browser-side decoder.)
  unawaited(
    browser.addStream(app).then((_) => stop(), onError: (Object _) => stop()),
  );

  // Browser → app. WebSocket text messages are rejected; the protocol is
  // binary-only. `addStream` pauses its input when the app socket stalls;
  // BufferedBrowserInput propagates that pause to the WebSocket subscription
  // and independently caps bytes already queued between the two.
  final browserBytes =
      browserInput ??
      browser.where((data) => data is List<int>).cast<List<int>>();
  unawaited(
    app
        .addStream(browserBytes)
        .then((_) => stop(), onError: (Object _) => stop()),
  );
}

/// Serves the index page and the embedded client bundle. Everything else
/// 404s — the serve surface is exactly two files.
Future<void> _serveStaticAsset(HttpRequest req) async {
  final path = req.uri.path;
  if (path == serveClientJsPath) {
    req.response.headers.contentType = ContentType(
      'application',
      'javascript',
      charset: 'utf-8',
    );
    // The bundle is regenerated per build and embedded in the binary; never
    // let a browser serve a stale client against a freshly restarted server.
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.add(remoteClientJs());
    await req.response.close();
    return;
  }
  if (path == '/' || path.isEmpty) {
    req.response.headers.contentType = ContentType.html;
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.write(serveIndexHtml);
    await req.response.close();
    return;
  }
  req.response.statusCode = HttpStatus.notFound;
  await req.response.close();
}

bool _isAllowedWebSocketOrigin(
  HttpRequest req,
  _ServeOriginPolicy originPolicy, {
  required String boundHost,
}) {
  final origin = req.headers.value('origin');
  if (origin == null || origin.isEmpty) return true;

  final originUri = Uri.tryParse(origin);
  if (originUri == null || originUri.host.isEmpty) return false;

  final requestHost = req.headers.value(HttpHeaders.hostHeader);
  if (requestHost == null || requestHost.isEmpty) return false;

  final normalizedOrigin = _ServeOriginPolicy._normalizeOrigin(origin);
  // Synthesize the same-origin from the request's OWN scheme, not a hardcoded
  // http://. Behind a TLS-terminating proxy the browser's Origin is
  // `https://host`; a hardcoded `http://host` never matches it, so a genuine
  // same-origin upgrade would be wrongly rejected (and fall through to the
  // empty-by-default allow-list). See [_sameOriginScheme].
  final sameOrigin = _ServeOriginPolicy._normalizeOrigin(
    '${_sameOriginScheme(req)}://${requestHost.trim()}',
  );
  if (normalizedOrigin != null &&
      normalizedOrigin == sameOrigin &&
      _isAllowedSameOriginHost(requestHost, boundHost)) {
    return true;
  }
  return originPolicy.allows(origin);
}

/// Whether the request Host is eligible for the implicit same-origin path.
///
/// When `serve` is bound to loopback, trusting an arbitrary Host header turns
/// the normal same-origin comparison into a DNS-rebinding bypass: a hostile
/// hostname can resolve to 127.0.0.1 and send matching Host + Origin headers.
/// Keep the zero-config local path limited to loopback hostnames. An operator
/// who deliberately uses a custom local hostname can still opt it in with
/// `--allow-origin`, and non-loopback binds retain their explicit, warned-about
/// trusted-network behavior.
bool _isAllowedSameOriginHost(String requestHost, String boundHost) {
  if (!_isLoopbackHost(boundHost)) return true;
  final uri = Uri.tryParse('http://${requestHost.trim()}');
  return uri != null && uri.host.isNotEmpty && _isLoopbackHost(uri.host);
}

/// The scheme the browser actually used to reach this server, for the
/// same-origin comparison.
///
/// A TLS-terminating proxy forwards the browser's original scheme in
/// `X-Forwarded-Proto` (a proxy chain may comma-join them — the first token is
/// the client-facing one). Absent that header, we fall back to the scheme of
/// this very connection: `https` on a direct TLS bind, `http` otherwise.
///
/// Never throws: `HttpRequest.requestedUri` raises a `FormatException` on a
/// multi-valued / malformed forwarded scheme, and an exception escaping the
/// origin check would abort the upgrade handler. A value we can't parse degrades
/// to the empty scheme, which yields no same-origin match — the explicit
/// allow-list stays the only path, i.e. it fails closed, never open. (Reading
/// `X-Forwarded-Proto` here is safe: browsers can't set it on a WebSocket
/// handshake, and it can only ever change the scheme compared against the SAME
/// host — never widen the check to a different origin.)
String _sameOriginScheme(HttpRequest req) {
  final forwarded = req.headers.value('x-forwarded-proto');
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    return forwarded.split(',').first.trim().toLowerCase();
  }
  try {
    return req.requestedUri.scheme;
  } on FormatException {
    return '';
  }
}

Future<void> _rejectForbiddenWebSocketOrigin(HttpRequest req) async {
  req.response.statusCode = HttpStatus.forbidden;
  req.response.headers.contentType = ContentType.text;
  req.response.write('Forbidden WebSocket origin.\n');
  await req.response.close();
}

final class _ServeOriginPolicy {
  const _ServeOriginPolicy.sameOrigin()
    : allowAny = false,
      allowedOrigins = const <String>{};

  const _ServeOriginPolicy._({
    required this.allowAny,
    required this.allowedOrigins,
  });

  final bool allowAny;
  final Set<String> allowedOrigins;

  _ServeOriginPolicy? allow(String origin) {
    final trimmed = origin.trim();
    if (trimmed == '*') {
      return _ServeOriginPolicy._(
        allowAny: true,
        allowedOrigins: allowedOrigins,
      );
    }

    final normalized = _normalizeOrigin(trimmed);
    if (normalized == null) return null;
    return _ServeOriginPolicy._(
      allowAny: allowAny,
      allowedOrigins: {...allowedOrigins, normalized},
    );
  }

  bool allows(String origin) {
    if (allowAny) return true;
    final normalized = _normalizeOrigin(origin);
    if (normalized == null) return false;
    return allowedOrigins.contains(normalized);
  }

  static String? _normalizeOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return null;
    }
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return '$scheme://${uri.authority.toLowerCase()}';
  }
}

/// Spawn mode: each browser connect spawns a fresh subprocess of
/// [command], bound to a session-specific Unix socket exposed via
/// `$FLEURY_HANDLE`. Sessions are isolated — separate state, separate
/// resources, one crash doesn't take the others down. This is the
/// "TUI is a multi-user web app" model.
Future<int> _runServeSpawn({
  required String host,
  required int port,
  required _ServeOriginPolicy originPolicy,
  required List<String> command,
  required bool debugWire,
  required int maxSessions,
  String? token,
}) async {
  // Spawned apps get the debug wire only when the operator asked for it:
  // without --debug, FLEURY_DEBUG_WIRE=0 tells runApp not to answer
  // debugRequest frames (logs / frame stats / error stacks stay private).
  // The in-app debug shell is unaffected.
  //
  // FORCE the value both ways (never inherit): if the serve process's own
  // env already carried FLEURY_DEBUG_WIRE=0 (an exported shell var, a nested
  // serve, a CI harness), a bare `--debug` that merely omitted the override
  // would silently stay OFF. NOTE: spawnFleuryApp's `environment` is a full
  // replacement env, so we merge over the parent's — passing just the flag
  // would strip PATH/HOME and break `dart run` resolution in the child.
  final spawnEnv = {
    ...Platform.environment,
    'FLEURY_DEBUG_WIRE': debugWire ? '1' : '0',
  };
  final handleDir = _createSpawnHandleDir();
  final httpServer = await HttpServer.bind(host, port);

  final exitCode = Completer<int>();
  final sessions = <_SpawnSession>{};
  var sessionCounter = 0;
  var shuttingDown = false;
  // Synchronous admission reservation. `sessions.where(isAttached)` can't be
  // the cap gate: attach happens two awaits after the check, so a BURST of
  // concurrent /ws connects would all observe the same pre-attach count and
  // all be admitted (TOCTOU) — the fork bomb the cap exists to stop. This
  // counter is incremented BEFORE the first await (atomic in Dart's single
  // isolate) and released when the serving session's subprocess exits, so it
  // bounds live subprocesses accurately even under concurrent connects.
  var admitted = 0;

  // A single warm standby: its subprocess is spawned and connected ahead of
  // the browser, so the expensive cold start (Dart VM + JIT compile of the
  // app) is paid here, not on the connection. Each connect claims the standby
  // and prepares the next, so sequential reloads stay warm.
  _SpawnSession? warm;
  Future<bool>? warmReady;

  void prepareWarm() {
    if (shuttingDown) return;
    final id = ++sessionCounter;
    final s = _SpawnSession(id: id);
    warm = s;
    sessions.add(s);
    warmReady = s.bringUp(
      command: command,
      handleDir: handleDir.path,
      tag: 's$id',
      environment: spawnEnv,
    );
    unawaited(
      s.done.then((_) {
        sessions.remove(s);
        if (identical(warm, s)) {
          warm = null;
          warmReady = null;
        }
        stderr.writeln(
          '[serve s${s.id}] session ended (active: ${sessions.length})',
        );
      }),
    );
  }

  httpServer.listen((req) async {
    if (req.uri.path != '/ws') {
      await _serveStaticAsset(req);
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    if (!_isAllowedWebSocketOrigin(req, originPolicy, boundHost: host)) {
      await _rejectForbiddenWebSocketOrigin(req);
      return;
    }
    if (!_isAuthorizedWebSocketRequest(req, token)) {
      await _rejectUnauthorizedWebSocket(req);
      return;
    }
    if (shuttingDown) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      req.response.write('server is shutting down');
      await req.response.close();
      return;
    }
    // Admission cap: each browser session is a full app subprocess, so an
    // open reconnect loop (or anything hostile that reached the port) must
    // not be able to fork-bomb the host. Reserve the slot SYNCHRONOUSLY here,
    // before any await, so concurrent connects can't all slip past the check.
    // The warm standby holds a subprocess too but isn't a browser session, so
    // it doesn't count against the browser cap.
    if (admitted >= maxSessions) {
      stderr.writeln(
        '[serve] rejecting connection: session limit reached '
        '($admitted/$maxSessions; raise with --max-sessions=<n>).',
      );
      req.response.statusCode = HttpStatus.serviceUnavailable;
      req.response.write('session limit reached');
      await req.response.close();
      return;
    }
    admitted++;
    // Release the reservation exactly once — when this connection's serving
    // session ends (its subprocess exits) or the connect fails outright. The
    // slot is held for the whole teardown, which is correct: the subprocess
    // is still alive until then.
    var released = false;
    void release() {
      if (released) return;
      released = true;
      admitted--;
    }

    // upgrade() can complete with an error — a client that resets mid-handshake,
    // an I/O fault on the detached socket, a protocol edge case. This runs in a
    // root-zone request listener with no runZonedGuarded, so an unhandled upgrade
    // error both escapes as an unhandled async error AND leaks the admission slot
    // reserved just above (release() would otherwise never run for this
    // connection). Contain it: free the slot and drop only this connection.
    // (Dart's upgrade() is robust to merely-malformed headers — a bad-handshake
    // "process crash" was not reproducible — so this is defensive containment
    // plus the concrete slot-leak fix.)
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(req);
    } catch (error) {
      release();
      stderr.writeln(
        '[serve] rejecting connection: websocket upgrade '
        'failed ($error).',
      );
      try {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
      } catch (_) {
        // The socket may already be hijacked/closed by the failed upgrade.
      }
      return;
    }
    if (shuttingDown) {
      release();
      try {
        await ws.close();
      } catch (_) {}
      return;
    }

    // Claim the warm standby and immediately prepare the next one.
    final claimed = warm;
    final claimedReady = warmReady;
    warm = null;
    warmReady = null;
    prepareWarm();

    if (claimed != null && claimedReady != null) {
      // Usually already complete (instant); if a connect races the warmup,
      // this waits out the remainder — still no worse than a cold spawn, and
      // it avoids spawning a second process for the same browser.
      final ready = await claimedReady;
      if (shuttingDown) {
        release();
        try {
          await ws.close();
        } catch (_) {}
        return;
      }
      if (ready && claimed.isReady) {
        stderr.writeln('[serve s${claimed.id}] paired browser to warm standby');
        claimed.attach(ws);
        unawaited(claimed.done.then((_) => release()));
        return; // cleanup runs via the done handler wired in prepareWarm
      }
      // The standby failed to come up; fall through to a cold spawn.
    }

    // Cold fallback: bind + spawn while the browser waits (legacy behavior).
    final id = ++sessionCounter;
    final session = _SpawnSession(id: id);
    sessions.add(session);
    final ok = await session.start(
      command: command,
      handleDir: handleDir.path,
      browser: ws,
      tag: 's$id',
      environment: spawnEnv,
    );
    if (shuttingDown) {
      await session.shutdown();
      sessions.remove(session);
      release();
      try {
        await ws.close();
      } catch (_) {}
      return;
    }
    if (!ok) {
      try {
        await ws.close();
      } catch (_) {}
      sessions.remove(session);
      release();
      return;
    }
    unawaited(
      session.done.then((_) {
        sessions.remove(session);
        release();
        stderr.writeln(
          '[serve s$id] session ended (active: ${sessions.length})',
        );
      }),
    );
  });

  Future<void>? cleanupFuture;
  Future<void> cleanup() {
    // Gate request-handler continuations synchronously, before the first await
    // in cleanup. A handler may be suspended in WebSocket upgrade or warmup;
    // it must not add a cold session after the snapshot below.
    shuttingDown = true;
    final existing = cleanupFuture;
    if (existing != null) return existing;
    cleanupFuture = () async {
      try {
        await httpServer.close(force: true);
      } catch (_) {}
      // Tear down every live session — kills subprocesses and removes
      // session sockets.
      final pending = sessions.toList();
      try {
        await Future.wait(pending.map((s) => s.shutdown()));
      } catch (_) {
        // Continue to remove the shared handle directory even if one child
        // has already disappeared underneath its shutdown routine.
      }
      try {
        handleDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; individual sessions also remove their sockets.
      }
    }();
    return cleanupFuture!;
  }

  var signalShutdownStarted = false;
  late final List<StreamSubscription<ProcessSignal>> signalSubs;
  signalSubs = _watchShutdownSignals((code, signalName) async {
    if (signalShutdownStarted) return;
    signalShutdownStarted = true;
    shuttingDown = true;
    await _cancelSignalSubscriptions(signalSubs);
    stderr.writeln(
      '[serve] $signalName — shutting down ${sessions.length} '
      'live session(s)',
    );
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(code);
  });

  // Pre-spawn only after shutdown handling is armed. Once a child can exist,
  // every supported terminal signal has a path that aborts and awaits it.
  prepareWarm();

  // The ready marker is consumed by scripts, so emit it only after HTTP
  // admission, the warm-session machinery, and shutdown cleanup are armed.
  stderr.writeln('fleury serve ready (spawn mode)');
  stderr.writeln('  browser: http://$host:$port');
  stderr.writeln('  spawn:   ${command.join(' ')}');
  stderr.writeln(
    'Sessions are isolated; a warm standby is kept ready so connections '
    'skip the cold start.',
  );

  return exitCode.future;
}

Directory _createSpawnHandleDir() {
  final shortTemp = Directory('/tmp');
  final base = !Platform.isWindows && shortTemp.existsSync()
      ? shortTemp
      : Directory.systemTemp;
  return base.createTempSync('fleury-spawn-');
}

/// One spawn-mode session: a subprocess, its session socket, and the
/// browser WebSocket that paired with it. Owns the full lifecycle.
/// Unified connect deadline for a spawned session's app (warm + cold). The MCP
/// bridge uses its own (longer) default; serve's interactive sessions want a
/// snappier give-up.
const Duration _spawnConnectTimeout = Duration(seconds: 10);

class _SpawnSession {
  _SpawnSession({required this.id});

  final int id;
  SpawnedFleuryApp? _app;
  WebSocket? _browser;
  final _done = Completer<void>();
  final _abortStartup = Completer<void>();
  Future<bool>? _startup;
  Future<void>? _shutdownFuture;
  var _shuttingDown = false;

  Future<void> get done => _done.future;

  /// Whether this session's subprocess is up and connected (a warm standby
  /// brought up ahead of a browser), so [attach] can pair instantly.
  bool get isReady => _app != null && !_shuttingDown;

  /// Whether a browser is paired with this session (the warm standby is not).
  bool get isAttached => _browser != null;

  /// Marks this session dead — so a stray [isReady] reads false — and completes
  /// [done] so the warm pool drops it. Used on every terminal path.
  void _markDead() {
    _shuttingDown = true;
    if (!_done.isCompleted) _done.complete();
  }

  String _socketPathFor(String handleDir) =>
      '${Directory(handleDir).absolute.path}/spawn-$pid-$id.sock';

  /// Brings the subprocess up *ahead of a browser* — a warm standby. The app
  /// connects to its session socket and (for a runApp app) blocks awaiting
  /// INIT, so the expensive `dart run`/VM cold start is paid here, before any
  /// connection, and a later [attach] pairs instantly. Returns false if the
  /// process couldn't start or never connected.
  Future<bool> bringUp({
    required List<String> command,
    required String handleDir,
    required String tag,
    Map<String, String>? environment,
  }) {
    final operation = _bringUp(
      command: command,
      handleDir: handleDir,
      tag: tag,
      environment: environment,
    );
    _startup = operation;
    return operation;
  }

  Future<bool> _bringUp({
    required List<String> command,
    required String handleDir,
    required String tag,
    Map<String, String>? environment,
  }) async {
    if (_shuttingDown) return false;
    try {
      _app = await spawnFleuryApp(
        command: command,
        socketPath: _socketPathFor(handleDir),
        connectTimeout: _spawnConnectTimeout,
        environment: environment,
        abort: _abortStartup.future,
        onLog: (stream, line) => stderr.writeln('[$tag $stream] $line'),
      );
    } on ProcessException catch (e) {
      stderr.writeln('[serve $tag] failed to spawn ${command.first}: $e');
      _markDead();
      return false;
    } on FleurySpawnException catch (e) {
      stderr.writeln('[serve $tag] warm subprocess never connected: $e');
      _markDead();
      return false;
    }
    stderr.writeln(
      '[serve $tag] spawned ${command.first} (pid ${_app!.process.pid})',
    );
    unawaited(_app!.process.exitCode.then((_) => shutdown()));
    return true;
  }

  /// Pairs a browser with this (warm, [isReady]) session and starts pumping.
  /// The browser's INIT — buffered by the WebSocket until listened — flows to
  /// the waiting app, which renders its first frame straight away.
  void attach(WebSocket browser) {
    _browser = browser;
    _attachPump(browser, BufferedBrowserInput(browser), _app!.socket);
  }

  void _attachPump(
    WebSocket browser,
    BufferedBrowserInput browserInput,
    Socket app,
  ) {
    _pumpBytes(
      app: app,
      browser: browser,
      browserInput: browserInput.stream,
      onDone: () {
        unawaited(browserInput.dispose());
        shutdown();
      },
    );
  }

  /// Cold path: bind, spawn, and bridge to an already-connected browser, all
  /// while the browser waits. Used as the fallback when no warm standby is
  /// ready. Returns false if the subprocess didn't come up.
  Future<bool> start({
    required List<String> command,
    required String handleDir,
    required WebSocket browser,
    required String tag,
    Map<String, String>? environment,
  }) {
    final operation = _start(
      command: command,
      handleDir: handleDir,
      browser: browser,
      tag: tag,
      environment: environment,
    );
    _startup = operation;
    return operation;
  }

  Future<bool> _start({
    required List<String> command,
    required String handleDir,
    required WebSocket browser,
    required String tag,
    Map<String, String>? environment,
  }) async {
    if (_shuttingDown) return false;
    _browser = browser;
    // The browser sends INIT immediately after the WebSocket opens, before the
    // subprocess can connect back. Listen + buffer now so the handshake isn't
    // missed — and pass its close as the spawn's abort, so a browser that leaves
    // before the app connects doesn't orphan the process.
    final browserInput = BufferedBrowserInput(browser);
    try {
      _app = await spawnFleuryApp(
        command: command,
        socketPath: _socketPathFor(handleDir),
        connectTimeout: _spawnConnectTimeout,
        environment: environment,
        abort: Future.any<void>([browserInput.closed, _abortStartup.future]),
        onLog: (stream, line) => stderr.writeln('[$tag $stream] $line'),
      );
    } on ProcessException catch (e) {
      stderr.writeln('[serve $tag] failed to spawn ${command.first}: $e');
      await browserInput.dispose();
      _markDead();
      return false;
    } on FleurySpawnException catch (e) {
      stderr.writeln('[serve $tag] subprocess never connected: $e');
      await browserInput.dispose();
      _markDead();
      return false;
    }
    stderr.writeln(
      '[serve $tag] spawned ${command.first} (pid ${_app!.process.pid})',
    );
    _attachPump(browser, browserInput, _app!.socket);
    unawaited(_app!.process.exitCode.then((_) => shutdown()));
    return true;
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _shuttingDown = true;
    if (!_abortStartup.isCompleted) _abortStartup.complete();

    // A warm session may be between Process.start and socket attachment, so
    // `_app` is still null even though a child exists. The abort above makes
    // spawnFleuryApp terminate and reap that child; awaiting startup closes the
    // race before serve itself exits and removes the shared handle directory.
    final startup = _startup;
    if (startup != null) {
      try {
        await startup;
      } catch (_) {
        // Startup owns its process/socket cleanup on every failure path.
      }
    }

    // dispose() signals the process (SIGTERM → SIGKILL after a grace period) and
    // removes the session socket.
    final app = _app;
    if (app != null) {
      // dispose() returns the exit code, so we don't re-await process.exitCode
      // (which could block on a process slow to die under SIGKILL).
      final code = await app.dispose();
      // Logging the exit code keeps subprocess crashes auditable.
      stderr.writeln('[serve s$id] subprocess exited ($code)');
    }
    try {
      await _browser?.close();
    } catch (_) {}
    if (!_done.isCompleted) _done.complete();
  }
}

/// `fleury diagnose` prints terminal environment, capabilities, and
/// shell/serve state. Markdown remains the default; `--json` is the stable
/// machine-readable contract for bug reports, fixtures, and demo apps.
Future<int> _runDiagnose(List<String> args) async {
  var json = false;
  String? jsonOutputPath;
  var probe = false;
  var probeTimeout = const Duration(milliseconds: 150);
  for (final arg in args) {
    if (arg == '--json') {
      json = true;
    } else if (arg.startsWith('--json-output=')) {
      jsonOutputPath = arg.substring('--json-output='.length).trim();
    } else if (arg == '--probe') {
      probe = true;
    } else if (arg.startsWith('--probe-timeout=')) {
      final value = int.tryParse(arg.substring('--probe-timeout='.length));
      if (value == null || value < 1) {
        stderr.writeln('--probe-timeout must be a positive millisecond value.');
        return 2;
      }
      probeTimeout = Duration(milliseconds: value);
    } else if (arg == '-h' || arg == '--help') {
      stderr.writeln(
        'fleury diagnose [--json] [--json-output=<path>] [--probe] '
        '[--probe-timeout=<ms>]',
      );
      return 0;
    } else {
      stderr.writeln('Unknown option for diagnose: $arg');
      stderr.writeln(
        'fleury diagnose [--json] [--json-output=<path>] [--probe] '
        '[--probe-timeout=<ms>]',
      );
      return 2;
    }
  }
  if (jsonOutputPath != null && jsonOutputPath.isEmpty) {
    stderr.writeln('--json-output requires a non-empty path.');
    return 2;
  }

  final env = Platform.environment;
  final cwd = Directory.current.path;
  final hasHandle = File('$cwd/.fleury/handle').existsSync();
  final handleContents = hasHandle
      ? File('$cwd/.fleury/handle').readAsStringSync().trim()
      : null;
  var diagnosis = diagnoseTerminal(
    createNativeTerminalDriver(),
    environment: env,
    platform: _diagnosisPlatform(),
    stdinIsTerminal: stdin.hasTerminal,
    stdoutIsTerminal: stdout.hasTerminal,
  );
  if (probe) {
    final probeReport = await _runActiveTerminalProbes(probeTimeout);
    diagnosis = diagnosis.withActiveProbes(probeReport);
  }

  if (json || jsonOutputPath != null) {
    final jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(diagnosis.toJson());
    if (jsonOutputPath != null) {
      final output = File(jsonOutputPath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync('$jsonText\n');
      return 0;
    }
    stdout.writeln(jsonText);
    return 0;
  }

  void row(String k, Object? v) => stdout.writeln('| $k | ${v ?? '(unset)'} |');

  void messages(String title, List<TerminalDiagnosticMessage> items) {
    stdout.writeln();
    stdout.writeln('## $title');
    stdout.writeln('| | |');
    stdout.writeln('|---|---|');
    if (items.isEmpty) {
      row('none', true);
      return;
    }
    for (final item in items) {
      row(item.code, '${item.severity.name}: ${item.message}');
    }
  }

  final terminal = diagnosis.terminal;
  final environment = diagnosis.environment;
  final platform = diagnosis.platform;
  final capabilities = diagnosis.capabilities;

  stdout.writeln('<!-- Paste this block into your GitHub issue. -->');
  stdout.writeln('# fleury diagnose');
  stdout.writeln();
  stdout.writeln('## Versions');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('Dart', Platform.version);
  row('fleury', '(0.0.0 - pre-release)');
  stdout.writeln();
  stdout.writeln('## Platform');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('OS', platform?.operatingSystem ?? Platform.operatingSystem);
  row(
    'OS version',
    platform?.operatingSystemVersion ?? Platform.operatingSystemVersion,
  );
  row('Dart version', platform?.dartVersion ?? Platform.version);
  row('Local hostname', Platform.localHostname);
  row('Executable', Platform.executable);
  stdout.writeln();
  stdout.writeln('## Terminal');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('TERM', terminal.term);
  row('COLORTERM', terminal.colorterm);
  row('TERM_PROGRAM', terminal.termProgram);
  row('TERM_PROGRAM_VERSION', terminal.termProgramVersion);
  row('LC_TERMINAL', terminal.lcTerminal);
  row('LC_TERMINAL_VERSION', terminal.lcTerminalVersion);
  row('KITTY_WINDOW_ID', terminal.kittyWindowId);
  row('Terminal size', '${terminal.size.cols} x ${terminal.size.rows}');
  row('stdout is terminal', terminal.stdoutIsTerminal);
  row('stdin is terminal', terminal.stdinIsTerminal);
  row('interactive', terminal.isInteractive);
  row('multiplexer', environment.tmux);
  row('ssh', environment.ssh);
  row('NO_COLOR', environment.noColor);
  row('CLICOLOR_FORCE', environment.clicolorForce);
  stdout.writeln();
  stdout.writeln('## Detected capabilities');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('Color mode', capabilities.colorMode.name);
  row('Glyph tier', capabilities.glyphTier.name);
  row('Image protocol', capabilities.imageProtocol.name);
  row('Alternate screen', capabilities.alternateScreen);
  row('Hide cursor', capabilities.hideCursor);
  row('Bracketed paste', capabilities.bracketedPaste);
  row('Kitty keyboard', capabilities.kittyKeyboard);
  row('Mouse', capabilities.mouse);
  row('OSC 52 clipboard', capabilities.osc52Clipboard);
  row('OSC 8 hyperlinks', capabilities.osc8Hyperlinks);
  row('tmux passthrough', capabilities.tmuxPassthrough);
  _writeProbeSection(diagnosis.activeProbes, row);
  _writeCompatibilitySection(diagnosis.compatibility, row);
  messages('Fallbacks', diagnosis.fallbacks);
  messages('Warnings', diagnosis.warnings);
  stdout.writeln();
  stdout.writeln('## fleury shell / serve');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('CWD', cwd);
  row('.fleury/handle exists', hasHandle);
  if (handleContents != null) row('.fleury/handle ->', handleContents);
  row('FLEURY_HANDLE env', env['FLEURY_HANDLE']);
  return 0;
}

TerminalPlatformReport _diagnosisPlatform() {
  return TerminalPlatformReport(
    operatingSystem: Platform.operatingSystem,
    operatingSystemVersion: Platform.operatingSystemVersion,
    dartVersion: Platform.version,
  );
}

Future<TerminalProbeReport> _runActiveTerminalProbes(Duration timeout) async {
  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    return TerminalProbeReport.skipped(
      'Active probes require both stdin and stdout to be terminals.',
    );
  }

  bool? originalLineMode;
  bool? originalEchoMode;
  var changedStdin = false;
  _StdioTerminalProbeTransport? transport;
  try {
    originalLineMode = stdin.lineMode;
    originalEchoMode = stdin.echoMode;
    stdin.lineMode = false;
    stdin.echoMode = false;
    changedStdin = true;

    transport = _StdioTerminalProbeTransport();
    return await runTerminalProbeSuite(transport, perProbeTimeout: timeout);
  } on StdinException catch (error) {
    return TerminalProbeReport.skipped(
      'Could not enter raw terminal mode for active probes: $error',
    );
  } finally {
    await transport?.close();
    if (changedStdin) {
      try {
        if (originalLineMode != null) stdin.lineMode = originalLineMode;
      } on StdinException {
        // ignore; the terminal may have detached
      }
      try {
        if (originalEchoMode != null) stdin.echoMode = originalEchoMode;
      } on StdinException {
        // ignore; the terminal may have detached
      }
    }
  }
}

void _writeProbeSection(
  TerminalProbeReport? report,
  void Function(String key, Object? value) row,
) {
  stdout.writeln();
  stdout.writeln('## Active probes');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  if (report == null) {
    row('not run', 'pass --probe to collect opt-in active probe evidence');
    return;
  }
  if (report.skippedReason != null) {
    row('skipped', report.skippedReason);
    return;
  }
  if (report.probes.isEmpty) {
    row('none', true);
    return;
  }
  for (final probe in report.probes) {
    final detail = probe.detail == null ? '' : ': ${probe.detail}';
    row(probe.id, '${probe.status.name}$detail');
  }
}

void _writeCompatibilitySection(
  TerminalCompatibilityReport? report,
  void Function(String key, Object? value) row,
) {
  stdout.writeln();
  stdout.writeln('## Compatibility findings');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  if (report == null) {
    row('not run', 'pass --probe to compare passive and active evidence');
    return;
  }
  if (report.skippedReason != null) {
    row('skipped', report.skippedReason);
  }
  for (final finding in report.findings) {
    final active = finding.activeStatus == null
        ? 'no active probe'
        : finding.activeStatus!.name;
    row(
      finding.feature.name,
      '${finding.status.name}; passive=${finding.passiveSupported}; '
      'active=$active',
    );
  }
}

final class _StdioTerminalProbeTransport implements TerminalProbeTransport {
  _StdioTerminalProbeTransport() {
    _subscription = stdin.listen(
      (bytes) => _buffer.addAll(bytes),
      cancelOnError: false,
    );
  }

  late final StreamSubscription<List<int>> _subscription;
  List<int> _buffer = <int>[];

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    _buffer = <int>[];
    stdout.write(bytes);
    await stdout.flush();
    await Future<void>.delayed(timeout);
    return List<int>.unmodifiable(_buffer);
  }

  Future<void> close() => _subscription.cancel();
}

RandomAccessFile? _tryAcquireHandleLock(Directory handleDir) {
  final lock = File('${handleDir.path}/lock').openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.exclusive);
    return lock;
  } on FileSystemException {
    lock.closeSync();
    return null;
  }
}

void _releaseHandleLock(RandomAccessFile lock) {
  try {
    lock.unlockSync();
  } catch (_) {}
  try {
    lock.closeSync();
  } catch (_) {}
}

typedef _ShutdownSignalHandler =
    Future<void> Function(int exitCode, String signalName);

/// Watches the process-shutdown signals supported by the current platform.
///
/// SIGHUP matters for shells and IDE terminals that disappear without sending
/// Ctrl-C; SIGTERM is the normal supervisor/CI shutdown path. Windows exposes
/// neither through Dart, so its Ctrl-C path remains SIGINT-only.
List<StreamSubscription<ProcessSignal>> _watchShutdownSignals(
  _ShutdownSignalHandler onSignal,
) {
  final subscriptions = <StreamSubscription<ProcessSignal>>[];

  void watch(ProcessSignal signal, int code, String name) {
    try {
      subscriptions.add(
        signal.watch().listen((_) => unawaited(onSignal(code, name))),
      );
    } on SignalException {
      // A platform can expose a signal constant without allowing a watcher.
    } on UnsupportedError {
      // Keep the remaining supported shutdown paths active.
    }
  }

  watch(ProcessSignal.sigint, 130, 'SIGINT');
  if (!Platform.isWindows) {
    watch(ProcessSignal.sighup, 129, 'SIGHUP');
    watch(ProcessSignal.sigterm, 143, 'SIGTERM');
  }
  return subscriptions;
}

Future<void> _cancelSignalSubscriptions(
  List<StreamSubscription<ProcessSignal>> subscriptions,
) async {
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

/// Owns a short, private Unix-socket directory outside the project path.
///
/// Unix-domain socket addresses have a small fixed-size path field (104 bytes
/// on macOS). A perfectly valid project path can exceed it, so `.fleury/handle`
/// points to this endpoint instead of a project-local socket file.
final class _LocalSocketEndpoint {
  _LocalSocketEndpoint._(this.directory, this.path, this._ownerLock);

  final Directory directory;
  final String path;
  RandomAccessFile? _ownerLock;

  /// Removes an endpoint left behind by a crashed shell/serve process.
  ///
  /// The handle file is project-writable input, so path shape alone is not
  /// ownership. Reclamation requires the endpoint's owner lock to exist and be
  /// acquirable non-blockingly; a live Fleury owner keeps that lock held.
  static void reclaimStaleFrom(File handleFile) {
    if (!handleFile.existsSync()) return;

    String socketPath;
    try {
      socketPath = handleFile.readAsStringSync().trim();
    } catch (_) {
      return;
    }
    if (socketPath.isEmpty) return;

    final rawFile = File(socketPath);
    final normalizedFile = File.fromUri(rawFile.absolute.uri.normalizePath());
    if (normalizedFile.path != socketPath || _basename(socketPath) != 's') {
      return;
    }

    final endpointDirectory = normalizedFile.parent;
    if (!_basename(endpointDirectory.path).startsWith('flr_')) return;
    final allowedRoots = <String>{
      Directory.systemTemp.absolute.path,
      Directory('/tmp').absolute.path,
    };
    if (!allowedRoots.contains(endpointDirectory.parent.absolute.path)) return;

    final ownerLockFile = File('${endpointDirectory.path}/owner.lock');
    if (FileSystemEntity.typeSync(ownerLockFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    RandomAccessFile? ownerLock;
    try {
      ownerLock = ownerLockFile.openSync(mode: FileMode.append);
      ownerLock.lockSync(FileLock.exclusive);
    } on FileSystemException {
      try {
        ownerLock?.closeSync();
      } catch (_) {}
      return;
    }

    try {
      // The handle file and everything it points at are untrusted project
      // input. Even after acquiring the advisory owner lock, never recursively
      // delete this directory: a managed-looking path can contain unrelated
      // files. Refuse reclamation unless the directory contains only the two
      // entries Fleury itself owns. A file created after this check is still
      // safe because the final directory removal is non-recursive.
      final entries = endpointDirectory.listSync(followLinks: false);
      final containsUnknownEntry = entries.any((entry) {
        final name = _basename(entry.path);
        final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
        return switch (name) {
          'owner.lock' => type != FileSystemEntityType.file,
          's' =>
            type != FileSystemEntityType.file &&
                type != FileSystemEntityType.unixDomainSock,
          _ => true,
        };
      });
      if (containsUnknownEntry) return;

      normalizedFile.deleteSync();
      ownerLockFile.deleteSync();
      endpointDirectory.deleteSync();
      handleFile.deleteSync();
    } catch (_) {
      // Best-effort only. In particular, a concurrently-added entry makes the
      // non-recursive directory removal fail without deleting that entry.
      // Binding a fresh endpoint below remains authoritative.
    } finally {
      _releaseHandleLock(ownerLock);
    }
  }

  static _LocalSocketEndpoint create() {
    final roots = <String>{Directory.systemTemp.path, '/tmp'};
    for (final rootPath in roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      Directory? directory;
      RandomAccessFile? ownerLock;
      try {
        directory = root.createTempSync('flr_');
        ownerLock = File(
          '${directory.path}/owner.lock',
        ).openSync(mode: FileMode.append);
        ownerLock.lockSync(FileLock.exclusive);
        final path = '${directory.path}/s';
        if (utf8.encode(path).length <= 100) {
          return _LocalSocketEndpoint._(directory, path, ownerLock);
        }
      } on FileSystemException {
        // Try the shorter conventional POSIX temp root below.
      }
      if (ownerLock != null) _releaseHandleLock(ownerLock);
      try {
        directory?.deleteSync(recursive: true);
      } catch (_) {}
    }
    throw FileSystemException(
      'no writable temp directory produced a Unix-socket path under 101 bytes',
    );
  }

  void delete() {
    final ownerLock = _ownerLock;
    _ownerLock = null;
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {}
    if (ownerLock != null) _releaseHandleLock(ownerLock);
  }
}

String _basename(String path) {
  final segments = Uri.directory(
    path,
  ).pathSegments.where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? '' : segments.last;
}
