// Bridges a running Fleury app to an out-of-process agent.
//
// The MCP server is a *peer* on the same structured wire `fleury serve` speaks
// (`package:fleury/src/remote/`): it sends an INIT handshake, receives the
// app's semantic snapshots (as SEMANTICS patch frames), and sends back
// SEMANTIC_ACTION / INPUT_EVENT frames to drive the UI. It ignores the visual
// PLAN/IMAGE frames entirely — an agent reads meaning, not cells.
//
// [FleuryAppBridge] is the protocol half: hand it any [RemoteFrameTransport]
// and it maintains the live semantic tree and exposes invoke/type/press. The
// [FleuryAppBridge.spawn] factory is the process half: it binds a Unix socket,
// launches the app with `FLEURY_HANDLE` pointed at it (the same discovery
// `fleury serve --spawn` uses), and wires the two together.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_core.dart';
// The remote-render wire has no public host-side library; consume it directly,
// the same way fleury_web does. See analysis_options (implementation_imports).
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/remote_semantics.dart';
import 'package:fleury/src/remote/remote_transport.dart';
import 'package:fleury/src/remote/unix_socket_transport.dart';

/// A line sink for the app subprocess's own stdout/stderr. The MCP server's
/// real stdout is reserved for JSON-RPC, so app logs must never land there.
typedef BridgeLog = void Function(String line);

/// Drives a single Fleury app over the structured remote wire and keeps its
/// latest semantic snapshot. One bridge per app session.
final class FleuryAppBridge {
  /// Wraps an existing [transport] to the app. Call [start] to handshake and
  /// begin tracking semantics. [onClose] runs during [close] (used by [spawn]
  /// to kill the subprocess and remove its socket).
  FleuryAppBridge(
    this._transport, {
    CellSize viewport = const CellSize(80, 24),
    Duration firstFrameTimeout = const Duration(seconds: 10),
    Future<void> Function()? onClose,
  }) : _viewport = viewport,
       _firstFrameTimeout = firstFrameTimeout,
       _onClose = onClose;

  final RemoteFrameTransport _transport;
  final CellSize _viewport;
  final Duration _firstFrameTimeout;
  final Future<void> Function()? _onClose;

  final SemanticsWireDecoder _decoder = SemanticsWireDecoder();
  final Completer<void> _firstSnapshot = Completer<void>();
  final Completer<void> _exited = Completer<void>();

  StreamSubscription<RemoteFrame>? _sub;
  Timer? _renderWatchdog;

  // The latest decoded tree, plus a snapshot built lazily from it and cached
  // until the next frame — so an app that animates at 60fps doesn't pay a full
  // snapshot rebuild per frame when no agent is reading.
  SemanticTree? _tree;
  SemanticInspectionSnapshot? _cachedSnapshot;

  int _revision = 0;
  bool _started = false;
  bool _closed = false;
  bool _renderTimedOut = false;

  // Replaced and completed on every semantics update so [settle] can await the
  // next one without polling.
  Completer<void> _tick = Completer<void>();

  /// The viewport the app lays out against. A taller grid surfaces more rows of
  /// windowed widgets (tables, logs) in the semantic tree.
  CellSize get viewport => _viewport;

  /// The most recent semantic snapshot, or null before the first frame lands.
  /// Built lazily from the last frame and memoized until the next one.
  SemanticInspectionSnapshot? get snapshot {
    final tree = _tree;
    if (tree == null) return null;
    return _cachedSnapshot ??= tree.toInspectionSnapshot();
  }

  /// Monotonic counter bumped on every semantics update. Capture it before an
  /// action, then [settle] past it to observe the result.
  int get revision => _revision;

  /// Whether the app is still connected (false once it sends BYE or the
  /// transport drops).
  bool get isRunning => !_exited.isCompleted;

  /// True once the app connected but did not render a first frame within
  /// [firstFrameTimeout] (e.g. it never called runTui). Lets tools fail fast
  /// with a clear message instead of each waiting out its own timeout.
  bool get renderTimedOut => _renderTimedOut;

  /// Completes when the app reaches a settled initial state — the first
  /// semantic snapshot arrived, the app exited, or the first-frame watchdog
  /// fired. Never errors; check [snapshot] / [isRunning] / [renderTimedOut]
  /// after it resolves.
  Future<void> get ready => _firstSnapshot.future;

  /// Completes when the app disconnects.
  Future<void> get done => _exited.future;

  /// Sends the INIT handshake and starts consuming frames. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _sub = _transport.incoming.listen(
      _onFrame,
      onError: (Object _, StackTrace _) => _markExited(),
      onDone: _markExited,
      cancelOnError: false,
    );
    // Bound the "connected but never renders" case so the session can't wedge.
    _renderWatchdog = Timer(_firstFrameTimeout, () {
      if (_firstSnapshot.isCompleted) return;
      _renderTimedOut = true;
      _firstSnapshot.complete();
      _signalTick();
    });
    _send(
      InitFrame(
        size: _viewport,
        colorMode: ColorMode.truecolor,
        glyphTier: GlyphTier.unicode,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        protocolVersion: remoteProtocolVersion,
      ),
    );
  }

  /// Invokes [action] on the live node [id]. The app dispatches it against its
  /// real element tree and re-renders; observe the result with [settle].
  void invokeAction(SemanticNodeId id, SemanticAction action) =>
      _send(SemanticActionFrame(id, action));

  /// Sets node [id]'s value to [value] — the payload for a `setValue` action
  /// (text into a field, a slider position…). The node must advertise
  /// `setValue`; observe the result with [settle].
  void setValue(SemanticNodeId id, Object? value) =>
      _send(SemanticActionFrame(id, SemanticAction.setValue, value: value));

  /// Types [text] into the focused widget (a structured text-input event, the
  /// same one a keypress would produce on the serve path).
  void typeText(String text) {
    if (text.isEmpty) return;
    _send(InputEventFrame(TextInputEvent(text)));
  }

  /// Presses a key — a named [keyCode] (enter, tab, arrows…) or a literal
  /// [char] — with optional [modifiers].
  void pressKey({
    KeyCode? keyCode,
    String? char,
    Set<KeyModifier> modifiers = const <KeyModifier>{},
  }) {
    _send(
      InputEventFrame(
        KeyEvent(keyCode: keyCode, char: char, modifiers: modifiers),
      ),
    );
  }

  /// Resizes the app's viewport, reflowing the layout (and thus which rows of
  /// windowed widgets are in the tree).
  void resize(CellSize size) => _send(ResizeFrame(size));

  /// Sends a frame, treating a transport failure (the socket dropped between
  /// our last `isRunning` check and now) as the app exiting — so callers get a
  /// clean "app gone" path rather than an exception thrown back at them.
  void _send(RemoteFrame frame) {
    if (!isRunning) return;
    try {
      _transport.send(frame);
    } catch (_) {
      _markExited();
    }
  }

  /// Waits for the semantics to react and then settle. Used after an action to
  /// observe what changed: it first waits (up to [timeout]) for a revision past
  /// [sinceRevision], then for a [quiet] window with no further updates, then
  /// returns the latest snapshot. The debounce is event-driven — it returns
  /// ~[quiet] after the *last* frame, with no fixed minimum sleep — and returns
  /// the current snapshot immediately if nothing changes within [timeout].
  Future<SemanticInspectionSnapshot?> settle({
    int? sinceRevision,
    Duration quiet = const Duration(milliseconds: 60),
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final stopwatch = Stopwatch()..start();
    Duration remaining() {
      final left = timeout - stopwatch.elapsed;
      return left.isNegative ? Duration.zero : left;
    }

    // Phase 1: wait for the first reaction past the captured revision.
    if (sinceRevision != null) {
      while (isRunning &&
          _revision <= sinceRevision &&
          stopwatch.elapsed < timeout) {
        await _nextTick(remaining());
      }
    }

    // Phase 2: event-driven debounce. Wait `quiet` for the next frame; if none
    // arrives in that window the burst has settled, so return — no fixed sleep.
    while (isRunning && stopwatch.elapsed < timeout) {
      final before = _revision;
      final window = quiet < remaining() ? quiet : remaining();
      await _nextTick(window);
      if (_revision == before) break;
    }
    return snapshot;
  }

  /// Tears down the transport and (for a spawned app) the subprocess.
  /// Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _renderWatchdog?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      _transport.send(const ByeFrame());
    } catch (_) {
      // Peer may already be gone.
    }
    await _transport.close();
    await _onClose?.call();
    _markExited();
  }

  void _onFrame(RemoteFrame frame) {
    switch (frame) {
      case SemanticsFrame f:
        final tree = _decoder.apply(f.json);
        if (tree == null) return; // malformed/desync — keep the last good tree.
        _tree = tree;
        _cachedSnapshot = null; // rebuilt lazily on the next read.
        _revision++;
        _renderWatchdog?.cancel();
        if (!_firstSnapshot.isCompleted) _firstSnapshot.complete();
        _signalTick();
      case ByeFrame():
        _markExited();
      // Visual + handshake frames an agent doesn't consume. (An app never
      // sends INIT/INPUT back; those would be protocol violations — ignore.)
      case PlanFrame _:
      case OutputFrame _:
      case InlineImageFrame _:
      case InitFrame _:
      case InputFrame _:
      case ResizeFrame _:
      case InputEventFrame _:
      case SemanticActionFrame _:
        break;
    }
  }

  Future<void> _nextTick(Duration timeout) {
    if (timeout <= Duration.zero) return Future<void>.value();
    return _tick.future.timeout(timeout, onTimeout: () {});
  }

  void _signalTick() {
    final pending = _tick;
    _tick = Completer<void>();
    if (!pending.isCompleted) pending.complete();
  }

  void _markExited() {
    _renderWatchdog?.cancel();
    if (!_exited.isCompleted) _exited.complete();
    // Unblock `ready` rather than erroring it — an app that exits before its
    // first frame is a settled (empty) state, not an exception for every
    // awaiter to handle. Callers check `snapshot`/`isRunning`/`renderTimedOut`.
    if (!_firstSnapshot.isCompleted) _firstSnapshot.complete();
    _signalTick();
  }

  /// Binds a Unix socket, spawns [command] with `FLEURY_HANDLE` pointed at it,
  /// waits for the app to connect, and returns a started bridge. The app's own
  /// stdout/stderr are forwarded to [log] (default: this process's stderr), so
  /// the MCP server's stdout stays a clean JSON-RPC channel.
  static Future<FleuryAppBridge> spawn({
    required List<String> command,
    CellSize viewport = const CellSize(80, 24),
    Duration connectTimeout = const Duration(seconds: 20),
    Duration firstFrameTimeout = const Duration(seconds: 10),
    BridgeLog? log,
  }) async {
    if (command.isEmpty) {
      throw ArgumentError.value(command, 'command', 'must be non-empty');
    }
    final logLine = log ?? stderr.writeln;
    final handleDir = _createHandleDir();
    final socketPath = '${handleDir.path}/app-$pid.sock';
    try {
      File(socketPath).deleteSync();
    } on FileSystemException {
      // Not there — fine.
    }

    final server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    Future<void> cleanupSocket() async {
      await server.close();
      try {
        File(socketPath).deleteSync();
      } catch (_) {}
      try {
        handleDir.deleteSync(recursive: true);
      } catch (_) {}
    }

    final env = Map<String, String>.from(Platform.environment);
    env['FLEURY_HANDLE'] = socketPath;
    env['COLORTERM'] = env['COLORTERM'] ?? 'truecolor';

    final Process process;
    try {
      process = await Process.start(
        command.first,
        command.sublist(1),
        environment: env,
      );
    } on ProcessException {
      await cleanupSocket();
      rethrow;
    }
    logLine('[fleury_mcp] spawned ${command.join(' ')} (pid ${process.pid})');

    // The app renders to the socket; anything on its stdout/stderr is its own
    // print()/log output. Forward it to our log sink, line by line, and keep
    // the subscriptions so they can be cancelled on teardown.
    StreamSubscription<String> forward(String tag, Stream<List<int>> source) {
      return source
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => logLine('[app $tag] ${sanitizeForDisplay(line)}'));
    }

    final outSub = forward('out', process.stdout);
    final errSub = forward('err', process.stderr);

    final connection = await Future.any<Object>([
      server.first,
      process.exitCode.then((code) => _AppExited(code)),
      Future<Object>.delayed(connectTimeout, () => const _ConnectTimedOut()),
    ]);

    if (connection is! Socket) {
      await outSub.cancel();
      await errSub.cancel();
      process.kill(ProcessSignal.sigkill);
      await cleanupSocket();
      final reason = connection is _AppExited
          ? 'app exited (code ${connection.code}) before connecting'
          : 'app did not connect within ${connectTimeout.inSeconds}s';
      throw FleuryAppBridgeException(
        'Failed to attach to `${command.join(' ')}`: $reason. '
        'Make sure it calls runTui(...) so it auto-discovers FLEURY_HANDLE.',
      );
    }

    final transport = UnixSocketFrameTransport.fromSocket(connection);
    final bridge = FleuryAppBridge(
      transport,
      viewport: viewport,
      firstFrameTimeout: firstFrameTimeout,
      onClose: () async {
        await outSub.cancel();
        await errSub.cancel();
        process.kill(ProcessSignal.sigterm);
        await process.exitCode
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () {
                process.kill(ProcessSignal.sigkill);
                return -9;
              },
            )
            .catchError((_) => -1);
        await cleanupSocket();
      },
    );
    // A crashing app tears the bridge down too.
    unawaited(process.exitCode.then((_) => bridge.close()));
    bridge.start();
    return bridge;
  }

  // Unix socket paths cap at ~104 bytes on macOS, so prefer a short /tmp base
  // over the (often deep) system temp dir — same reasoning as `fleury serve`.
  static Directory _createHandleDir() {
    final shortTemp = Directory('/tmp');
    final base = !Platform.isWindows && shortTemp.existsSync()
        ? shortTemp
        : Directory.systemTemp;
    return base.createTempSync('fleury-mcp-');
  }
}

/// Thrown when an app can't be attached (failed to spawn, never connected, or
/// exited before rendering).
final class FleuryAppBridgeException implements Exception {
  const FleuryAppBridgeException(this.message);
  final String message;
  @override
  String toString() => 'FleuryAppBridgeException: $message';
}

sealed class _ConnectOutcome {
  const _ConnectOutcome();
}

final class _AppExited extends _ConnectOutcome {
  const _AppExited(this.code);
  final int code;
}

final class _ConnectTimedOut extends _ConnectOutcome {
  const _ConnectTimedOut();
}
