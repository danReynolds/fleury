// `fleury` — companion CLI for the fleury framework.
//
// Subcommands:
//
//   fleury shell    Run a local-display proxy so an fleury app launched
//                  under a debugger (VSCode, IntelliJ) can render into
//                  THIS terminal instead of fighting the IDE's stdout.
//                  Implements the Unix-socket transport defined in
//                  `lib/src/remote/`.
//
//   fleury serve    (future) Same idea, websocket transport: app
//                  renders into a browser xterm.js client.
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

import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/serve_index_html.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';
import 'package:fleury/src/terminal/capabilities.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(2);
  }
  switch (args[0]) {
    case 'shell':
      exit(await _runShell(args.sublist(1)));
    case 'serve':
      exit(await _runServe(args.sublist(1)));
    case 'diagnose':
      _runDiagnose();
      exit(0);
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
  stderr.writeln('Subcommands:');
  stderr.writeln(
    '  shell    Proxy fleury-app rendering through this terminal '
    'so the app can be',
  );
  stderr.writeln('           launched under an IDE debugger.');
  stderr.writeln(
    '  serve    Proxy fleury-app rendering to a browser via '
    'WebSocket + xterm.js.',
  );
  stderr.writeln(
    '           Options: --port=<n> (default 5777), '
    '--host=<addr> (default 127.0.0.1),',
  );
  stderr.writeln(
    '                    --spawn <cmd ...> (per-browser '
    'subprocess isolation).',
  );
  stderr.writeln(
    '  diagnose Print terminal + capability information for bug '
    'reports.',
  );
}

Future<int> _runShell(List<String> args) async {
  if (!stdout.hasTerminal) {
    stderr.writeln(
      'fleury shell: stdout is not a terminal — nothing to '
      'render into.',
    );
    return 2;
  }

  final handleDir = Directory('.fleury');
  if (!handleDir.existsSync()) handleDir.createSync(recursive: true);
  final socketPath = '${handleDir.path}/shell.sock';
  final handleFile = File('${handleDir.path}/handle');

  final stale = await _checkExistingHandle(handleFile);
  if (stale == _HandleStatus.live) {
    stderr.writeln(
      'fleury shell: another fleury shell/serve is already running here '
      '(handle at ${handleFile.path}).',
    );
    stderr.writeln('Stop it first, or run from a different directory.');
    return 2;
  }

  // A stale socket from a crashed previous shell will block `bind`.
  // Removing it is safe: the only contract on `.fleury/handle` is the
  // path it points to, not the inode behind it.
  try {
    File(socketPath).deleteSync();
  } on FileSystemException {
    /* not there, fine */
  }

  final server = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );
  handleFile.writeAsStringSync(socketPath);
  final absSocket = File(socketPath).absolute.path;
  stderr.writeln('fleury shell ready at $socketPath');
  stderr.writeln('');
  stderr.writeln('To attach an app:');
  stderr.writeln('  • run it from this directory:  dart run app.dart');
  stderr.writeln('  • or from any directory, set FLEURY_HANDLE:');
  stderr.writeln('      FLEURY_HANDLE=$absSocket dart run app.dart');
  stderr.writeln('  • or launch it from your IDE — the discovery file');
  stderr.writeln('    handles the rest automatically.');

  final exitCode = Completer<int>();

  Future<void> cleanup() async {
    await server.close();
    try {
      handleFile.deleteSync();
    } catch (_) {}
    try {
      File(socketPath).deleteSync();
    } catch (_) {}
  }

  // SIGINT in the shell tears down the proxy. The connected app sees
  // its transport drop and exits cleanly via the events `onDone` path.
  late StreamSubscription<ProcessSignal> intSub;
  intSub = ProcessSignal.sigint.watch().listen((_) async {
    await intSub.cancel();
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(130);
  });

  server.listen((client) async {
    // One app at a time. A second connection while one is live gets
    // dropped — the shell terminal can only show one TUI's frames.
    final code = await _runSession(client);
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(code);
  });

  return exitCode.future;
}

/// Drives a single connected app: hand off our terminal to the app's
/// frames, pump local stdin and SIGWINCH back to the app, and clean
/// up when the socket closes.
Future<int> _runSession(Socket client) async {
  final transport = UnixSocketFrameTransport.fromSocket(client);

  // Take over our own terminal. The app's enter sequences would do this
  // on the LOCAL side normally; here, the app is remote and its alt
  // screen / hide-cursor / raw-mode sequences arrive as OUTPUT frames,
  // which we write verbatim to our stdout. But WE need to be the one
  // who set raw mode on our stdin (so we read keystrokes instead of
  // line-buffered input) and put OUR terminal into a clean state.
  final originalLine = stdin.lineMode;
  final originalEcho = stdin.echoMode;
  stdin.lineMode = false;
  stdin.echoMode = false;
  // Bracketed paste + Kitty keyboard mirror the app's own setup so the
  // bytes coming back to it match what a normal terminal would send.
  stdout.write('\x1B[?1049h\x1B[?25l\x1B[?2004h\x1B[>1u');

  // Initial handshake — send what the app needs to lay out its first
  // frame correctly: actual size + the capabilities OUR terminal
  // negotiated with the user's real terminal emulator.
  transport.send(
    InitFrame(
      size: _localSize(),
      colorMode: _detectColorMode(),
      imageProtocol: _detectImageProtocol(),
      tmuxPassthrough: (Platform.environment['TMUX'] ?? '').isNotEmpty,
    ),
  );

  // SIGWINCH → RESIZE frame. The app reflows on its end.
  final winchSub = ProcessSignal.sigwinch.watch().listen((_) {
    transport.send(ResizeFrame(_localSize()));
  });

  // Stdin bytes → INPUT frame. No parsing; the app's own InputParser
  // does the work on the other end.
  final stdinSub = stdin.listen(
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

  await winchSub.cancel();
  await stdinSub.cancel();
  // Restore terminal modes. Mirror order of the enter sequences.
  stdout.write('\x1B[<u\x1B[?2004l\x1B[?25h\x1B[?1049l');
  stdin.lineMode = originalLine;
  stdin.echoMode = originalEcho;
  await transport.close();
  return 0;
}

CellSize _localSize() {
  try {
    return CellSize(stdout.terminalColumns, stdout.terminalLines);
  } on StdoutException {
    return const CellSize(80, 24);
  }
}

ColorMode _detectColorMode() {
  final env = Platform.environment;
  if ((env['NO_COLOR'] ?? '').isNotEmpty) return ColorMode.none;
  final colorterm = env['COLORTERM']?.toLowerCase() ?? '';
  final term = env['TERM']?.toLowerCase() ?? '';
  if (colorterm.contains('truecolor') || colorterm.contains('24bit')) {
    return ColorMode.truecolor;
  }
  if (term.contains('256')) return ColorMode.indexed256;
  if (term.isNotEmpty) return ColorMode.ansi16;
  return ColorMode.none;
}

ImageProtocol _detectImageProtocol() {
  final env = Platform.environment;
  final program = env['TERM_PROGRAM']?.toLowerCase() ?? '';
  final lcTerminal = env['LC_TERMINAL']?.toLowerCase() ?? '';
  final term = env['TERM']?.toLowerCase() ?? '';
  if ((env['KITTY_WINDOW_ID'] ?? '').isNotEmpty) return ImageProtocol.kitty;
  if (term == 'xterm-kitty') return ImageProtocol.kitty;
  if (program == 'wezterm' || program == 'ghostty') return ImageProtocol.kitty;
  if (program == 'iterm.app' || lcTerminal == 'iterm2' || program == 'mintty') {
    return ImageProtocol.iterm2;
  }
  if (term.contains('sixel')) return ImageProtocol.sixel;
  return ImageProtocol.halfBlock;
}

/// Stdin's stream gives us `List<int>`; the protocol wants `Uint8List`
/// for zero-copy framing downstream.
Uint8List _asUint8(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

Future<int> _runServe(List<String> args) async {
  var port = 5777;
  var host = '127.0.0.1';
  List<String>? spawnCmd;
  // `--spawn` is greedy: everything after it (in argv order) becomes
  // the subprocess command. So `--port=N` and `--host=...` must come
  // BEFORE `--spawn`, which is the natural shell ordering anyway.
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--port=')) {
      port = int.parse(arg.substring('--port='.length));
    } else if (arg.startsWith('--host=')) {
      host = arg.substring('--host='.length);
    } else if (arg == '--spawn') {
      spawnCmd = args.sublist(i + 1);
      if (spawnCmd.isEmpty) {
        stderr.writeln(
          '--spawn requires a command, e.g. `fleury serve --spawn dart run '
          'my_app.dart`',
        );
        return 2;
      }
      break;
    } else if (arg == '-h' || arg == '--help') {
      stderr.writeln(
        'fleury serve [--port=<n>] [--host=<addr>] [--spawn <cmd> ...]',
      );
      return 0;
    } else {
      stderr.writeln('Unknown option: $arg');
      return 2;
    }
  }

  return spawnCmd != null
      ? _runServeSpawn(host: host, port: port, command: spawnCmd)
      : _runServeBridge(host: host, port: port);
}

/// Bridge mode: one shared socket; user starts the app process
/// themselves. Single session at a time. Good for IDE debug and
/// local demos.
Future<int> _runServeBridge({required String host, required int port}) async {
  final handleDir = Directory('.fleury');
  if (!handleDir.existsSync()) handleDir.createSync(recursive: true);
  final socketPath = '${handleDir.path}/shell.sock';
  final handleFile = File('${handleDir.path}/handle');

  final stale = await _checkExistingHandle(handleFile);
  if (stale == _HandleStatus.live) {
    stderr.writeln(
      'fleury serve: another fleury serve/shell is already running here '
      '(handle at ${handleFile.path}).',
    );
    stderr.writeln('Stop it first, or run from a different directory.');
    return 2;
  }

  try {
    File(socketPath).deleteSync();
  } on FileSystemException {
    /* not there */
  }

  final appServer = await ServerSocket.bind(
    InternetAddress(socketPath, type: InternetAddressType.unix),
    0,
  );
  handleFile.writeAsStringSync(socketPath);
  final httpServer = await HttpServer.bind(host, port);

  final absSocket = File(socketPath).absolute.path;
  stderr.writeln('fleury serve ready (bridge mode)');
  stderr.writeln('  browser:    http://$host:$port');
  stderr.writeln('  app handle: $socketPath');
  stderr.writeln('');
  stderr.writeln('Open the URL in your browser, then attach your app:');
  stderr.writeln('  • from this directory:  dart run my_app.dart');
  stderr.writeln(
    '  • from any directory:   FLEURY_HANDLE=$absSocket dart run '
    'my_app.dart',
  );
  stderr.writeln('');
  stderr.writeln(
    'Or use --spawn to have serve own the subprocess and isolate '
    'per browser:',
  );
  stderr.writeln('  fleury serve --spawn dart run my_app.dart');

  final exitCode = Completer<int>();

  // Pairing state. Order of arrival doesn't matter — first one
  // through the door waits for its partner.
  Socket? pendingApp;
  WebSocket? pendingBrowser;
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
      browser: browser,
      onDone: () {
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
      final ws = await WebSocketTransformer.upgrade(req);
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
      pendingBrowser = ws;
      stderr.writeln('[serve] browser connected, waiting for an app');
      tryPair();
    } else {
      req.response.headers.contentType = ContentType.html;
      req.response.write(serveIndexHtml);
      await req.response.close();
    }
  });

  Future<void> cleanup() async {
    await appServer.close();
    await httpServer.close(force: true);
    try {
      handleFile.deleteSync();
    } catch (_) {}
    try {
      File(socketPath).deleteSync();
    } catch (_) {}
  }

  late StreamSubscription<ProcessSignal> intSub;
  intSub = ProcessSignal.sigint.watch().listen((_) async {
    await intSub.cancel();
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(130);
  });

  return exitCode.future;
}

/// Pure byte pump between an app's Unix-socket end and a browser's
/// WebSocket end. Both sides speak our framed binary protocol, so the
/// pump doesn't decode — bytes in, bytes out, in order.
void _pumpBytes({
  required Socket app,
  required WebSocket browser,
  required void Function() onDone,
}) {
  var stopped = false;
  Future<void> stop() async {
    if (stopped) return;
    stopped = true;
    try {
      await browser.close();
    } catch (_) {}
    try {
      await app.close();
    } catch (_) {}
    onDone();
  }

  // App → browser. App's frame bytes ride as WebSocket binary messages
  // verbatim; if a single TCP read carries multiple of our frames or
  // splits one across chunks, the browser-side decoder handles it.
  app.listen(
    (bytes) {
      try {
        browser.add(bytes);
      } catch (_) {
        stop();
      }
    },
    onError: (Object _) => stop(),
    onDone: stop,
    cancelOnError: false,
  );

  // Browser → app. WebSocket text messages are ignored; the protocol
  // is binary-only.
  browser.listen(
    (data) {
      if (data is List<int>) {
        try {
          app.add(data);
        } catch (_) {
          stop();
        }
      }
    },
    onError: (Object _) => stop(),
    onDone: stop,
    cancelOnError: false,
  );
}

/// Spawn mode: each browser connect spawns a fresh subprocess of
/// [command], bound to a session-specific Unix socket exposed via
/// `$FLEURY_HANDLE`. Sessions are isolated — separate state, separate
/// resources, one crash doesn't take the others down. This is the
/// "TUI is a multi-user web app" model.
Future<int> _runServeSpawn({
  required String host,
  required int port,
  required List<String> command,
}) async {
  final handleDir = Directory('.fleury');
  if (!handleDir.existsSync()) handleDir.createSync(recursive: true);
  final httpServer = await HttpServer.bind(host, port);
  stderr.writeln('fleury serve ready (spawn mode)');
  stderr.writeln('  browser: http://$host:$port');
  stderr.writeln('  spawn:   ${command.join(' ')}');
  stderr.writeln(
    'Each browser connection spawns a fresh process; sessions are isolated.',
  );

  final exitCode = Completer<int>();
  final sessions = <_SpawnSession>{};
  var sessionCounter = 0;

  httpServer.listen((req) async {
    if (req.uri.path != '/ws') {
      req.response.headers.contentType = ContentType.html;
      req.response.write(serveIndexHtml);
      await req.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    final id = ++sessionCounter;
    final session = _SpawnSession(id: id);
    sessions.add(session);
    final ok = await session.start(
      command: command,
      handleDir: handleDir.path,
      browser: ws,
      tag: 's$id',
    );
    if (!ok) {
      try {
        await ws.close();
      } catch (_) {}
      sessions.remove(session);
      return;
    }
    unawaited(
      session.done.then((_) {
        sessions.remove(session);
        stderr.writeln(
          '[serve s$id] session ended (active: ${sessions.length})',
        );
      }),
    );
  });

  Future<void> cleanup() async {
    await httpServer.close(force: true);
    // Tear down every live session — kills subprocesses and removes
    // session sockets.
    final pending = sessions.toList();
    await Future.wait(pending.map((s) => s.shutdown()));
  }

  late StreamSubscription<ProcessSignal> intSub;
  intSub = ProcessSignal.sigint.watch().listen((_) async {
    await intSub.cancel();
    stderr.writeln(
      '[serve] SIGINT — shutting down ${sessions.length} '
      'live session(s)',
    );
    await cleanup();
    if (!exitCode.isCompleted) exitCode.complete(130);
  });

  return exitCode.future;
}

/// One spawn-mode session: a subprocess, its session socket, and the
/// browser WebSocket that paired with it. Owns the full lifecycle.
class _SpawnSession {
  _SpawnSession({required this.id});

  final int id;
  Process? _process;
  ServerSocket? _server;
  String? _socketPath;
  WebSocket? _browser;
  final _done = Completer<void>();
  var _shuttingDown = false;

  Future<void> get done => _done.future;

  /// Bring up the session: bind the per-session socket, spawn the
  /// command, wait briefly for it to connect, then pump bytes between
  /// the subprocess socket and the browser WS. Returns false if the
  /// subprocess didn't connect within the grace window (the WS should
  /// be closed by the caller).
  Future<bool> start({
    required List<String> command,
    required String handleDir,
    required WebSocket browser,
    required String tag,
  }) async {
    _browser = browser;
    _socketPath = '$handleDir/spawn-$pid-$id.sock';
    try {
      File(_socketPath!).deleteSync();
    } on FileSystemException {
      /* not there */
    }

    _server = await ServerSocket.bind(
      InternetAddress(_socketPath!, type: InternetAddressType.unix),
      0,
    );

    final env = Map<String, String>.from(Platform.environment);
    env['FLEURY_HANDLE'] = _socketPath!;
    // Pure cosmetic: most TUIs sniff $TERM to pick colors. The browser
    // xterm.js advertises truecolor, so encourage the subprocess to
    // do the same when it has no other signal.
    env['COLORTERM'] = env['COLORTERM'] ?? 'truecolor';

    try {
      _process = await Process.start(
        command.first,
        command.sublist(1),
        environment: env,
      );
    } on ProcessException catch (e) {
      stderr.writeln('[serve $tag] failed to spawn ${command.first}: $e');
      await _cleanupSocket();
      _done.complete();
      return false;
    }
    stderr.writeln(
      '[serve $tag] spawned ${command.first} '
      '(pid ${_process!.pid})',
    );

    // Forward the subprocess's own stdout/stderr to ours, prefixed.
    // The TUI never writes to its own stdout (its renders go via the
    // socket), so anything we see here is print()/log output.
    _process!.stdout
        .transform(utf8.decoder)
        .listen((line) => _forwardLog(tag, 'out', line));
    _process!.stderr
        .transform(utf8.decoder)
        .listen((line) => _forwardLog(tag, 'err', line));

    // Race: subprocess connects to its socket (success) vs. it exits
    // first (e.g., couldn't find the runtime). Either way we don't
    // hang.
    final socketAccepted = _server!.first;
    final processExitedFirst = _process!.exitCode.then((_) => null);
    final firstEvent = await Future.any([
      socketAccepted.then((s) => _Connected(s)),
      processExitedFirst.then((_) => _ExitedBeforeConnect()),
      Future<dynamic>.delayed(
        const Duration(seconds: 10),
        () => _ConnectTimeout(),
      ),
    ]);

    if (firstEvent is! _Connected) {
      stderr.writeln(
        '[serve $tag] subprocess never connected to session '
        'socket ($firstEvent); shutting down',
      );
      await shutdown();
      return false;
    }

    final appSocket = firstEvent.socket;
    _pumpBytes(app: appSocket, browser: browser, onDone: () => shutdown());

    // Subprocess exiting is just as much a "session done" signal as
    // browser disconnect.
    unawaited(_process!.exitCode.then((_) => shutdown()));

    return true;
  }

  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    final proc = _process;
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      final killed = await proc.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
      // Logging the exit code keeps subprocess crashes auditable.
      stderr.writeln('[serve s$id] subprocess exited ($killed)');
    }
    try {
      await _browser?.close();
    } catch (_) {}
    await _server?.close();
    await _cleanupSocket();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> _cleanupSocket() async {
    final p = _socketPath;
    if (p == null) return;
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  void _forwardLog(String tag, String stream, String chunk) {
    // Honour line boundaries so multi-line print() output reads cleanly
    // alongside other sessions.
    final lines = chunk.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty && i == lines.length - 1) continue;
      stderr.writeln('[$tag $stream] $line');
    }
  }
}

sealed class _StartEvent {
  const _StartEvent();
}

class _Connected extends _StartEvent {
  const _Connected(this.socket);
  final Socket socket;
}

class _ExitedBeforeConnect extends _StartEvent {
  const _ExitedBeforeConnect();
  @override
  String toString() => 'subprocess exited before connecting';
}

class _ConnectTimeout extends _StartEvent {
  const _ConnectTimeout();
  @override
  String toString() => 'timed out waiting for subprocess to connect (10s)';
}

/// `fleury diagnose` — prints the terminal environment, fleury + Dart
/// versions, detected capabilities, and the current `.fleury/handle`
/// state. Output is markdown so it pastes cleanly into a GitHub
/// issue. Mirrors Textual's `textual diagnose`.
void _runDiagnose() {
  final env = Platform.environment;
  final cwd = Directory.current.path;
  final hasHandle = File('$cwd/.fleury/handle').existsSync();
  final handleContents = hasHandle
      ? File('$cwd/.fleury/handle').readAsStringSync().trim()
      : null;

  String? envOr(String name) {
    final v = env[name];
    return (v == null || v.isEmpty) ? null : v;
  }

  void row(String k, Object? v) => stdout.writeln('| $k | ${v ?? '(unset)'} |');

  stdout.writeln('<!-- Paste this block into your GitHub issue. -->');
  stdout.writeln('# fleury diagnose');
  stdout.writeln();
  stdout.writeln('## Versions');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('Dart', Platform.version);
  row('fleury', '(0.0.0 — pre-release)');
  stdout.writeln();
  stdout.writeln('## Platform');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('OS', Platform.operatingSystem);
  row('OS version', Platform.operatingSystemVersion);
  row('Local hostname', Platform.localHostname);
  row('Executable', Platform.executable);
  stdout.writeln();
  stdout.writeln('## Terminal');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('TERM', envOr('TERM'));
  row('COLORTERM', envOr('COLORTERM'));
  row('TERM_PROGRAM', envOr('TERM_PROGRAM'));
  row('TERM_PROGRAM_VERSION', envOr('TERM_PROGRAM_VERSION'));
  row('LC_TERMINAL', envOr('LC_TERMINAL'));
  row('LC_TERMINAL_VERSION', envOr('LC_TERMINAL_VERSION'));
  row('KITTY_WINDOW_ID', envOr('KITTY_WINDOW_ID'));
  row('TMUX', envOr('TMUX'));
  row('SSH_TTY', envOr('SSH_TTY'));
  row('NO_COLOR', envOr('NO_COLOR'));
  row('CLICOLOR_FORCE', envOr('CLICOLOR_FORCE'));
  try {
    row('Terminal size', '${stdout.terminalColumns} × ${stdout.terminalLines}');
  } on StdoutException {
    row('Terminal size', '(not a terminal — piped)');
  }
  row('stdout is terminal', stdout.hasTerminal);
  row('stdin is terminal', stdin.hasTerminal);
  stdout.writeln();
  stdout.writeln('## Detected capabilities');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('Color mode', _detectColorMode().name);
  row('Image protocol', _detectImageProtocol().name);
  row('tmux passthrough', (env['TMUX'] ?? '').isNotEmpty ? 'on' : 'off');
  stdout.writeln();
  stdout.writeln('## fleury shell / serve');
  stdout.writeln('| | |');
  stdout.writeln('|---|---|');
  row('CWD', cwd);
  row('.fleury/handle exists', hasHandle);
  if (handleContents != null) row('.fleury/handle →', handleContents);
  row('FLEURY_HANDLE env', envOr('FLEURY_HANDLE'));
}

enum _HandleStatus { absent, stale, live }

/// Decides what to do about an existing `.fleury/handle` file before
/// `fleury shell` / `fleury serve` (bridge mode) bind a new socket.
///
///   - absent: no handle file present, nothing to worry about.
///   - stale:  handle file exists but its socket is dead (previous
///             shell/serve crashed) — caller cleans up and proceeds.
///   - live:   handle file points at a socket that accepts connections
///             — another instance is alive; caller refuses to start.
///
/// We probe by connecting to the socket with a short timeout. If we
/// connect, someone's listening; if it fails, the socket is gone. The
/// probe connection IS observed by a live peer (it shows up as a
/// momentary stale app connection), which is the lesser evil compared
/// to the previous behavior of silently nuking the other instance's
/// socket file.
Future<_HandleStatus> _checkExistingHandle(File handleFile) async {
  if (!handleFile.existsSync()) return _HandleStatus.absent;
  final path = (await handleFile.readAsString()).trim();
  if (path.isEmpty) return _HandleStatus.stale;
  try {
    final probe = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ).timeout(const Duration(milliseconds: 500));
    await probe.close();
    return _HandleStatus.live;
  } on Object {
    return _HandleStatus.stale;
  }
}
