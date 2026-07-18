// Bridges a running Fleury app to an out-of-process agent.
//
// The MCP server is a *peer* on the same structured wire `fleury serve` speaks
// (`package:fleury/fleury_host_io.dart`): it sends an INIT handshake, receives the
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

// The host SPI: semantics + the remote-render wire (frame protocol, codec,
// transport) + the Unix-socket transport — the same public surface a native
// host like `fleury serve` builds on.
import 'package:fleury/fleury_host_io.dart';

/// A line sink for the app subprocess's own stdout/stderr. The MCP server's
/// real stdout is reserved for JSON-RPC, so app logs must never land there.
typedef BridgeLog = void Function(String line);

/// The net change to the semantic tree across one settled burst: which node ids
/// changed and which were removed (and whether a full resync occurred). Lets a
/// consumer push *what* changed instead of re-sending the whole tree.
final class SemanticTreeDelta {
  const SemanticTreeDelta({
    required this.changedIds,
    required this.removedIds,
    required this.full,
  });

  /// Ids whose serialized node changed; on a [full] burst, every current id.
  final List<String> changedIds;

  /// Ids removed from the tree during the burst.
  final List<String> removedIds;

  /// A full (resync) frame occurred in the burst — treat [changedIds] as
  /// "re-read everything".
  final bool full;

  /// No observable change (no ids touched and not a full resync).
  bool get isEmpty => !full && changedIds.isEmpty && removedIds.isEmpty;
}

/// Drives a single Fleury app over the structured remote wire and keeps its
/// latest semantic snapshot. One bridge per app session.
final class FleuryAppBridge {
  /// Wraps an existing transport to the app. Call [start] to handshake and
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

  // Coalesced semantic delta: the net changed/removed ids accumulated across
  // frames since the last [takeDelta]. Paired with [settle], this yields one
  // delta per settled burst for resource-update push (no per-frame storm).
  final Set<String> _accChanged = <String>{};
  final Set<String> _accRemoved = <String>{};
  bool _accFull = false;

  // Per-frame delta folding runs only while a consumer (a resource subscription)
  // is active, set via [accumulateDeltas]. Off by default so a busy app pays no
  // delta-fold cost when nobody subscribes, and a fresh subscription starts from
  // an empty accumulator instead of inheriting an unbounded pre-subscribe backlog.
  bool _accumulateDeltas = false;

  /// Turns per-frame delta accumulation on/off. The server enables it while a
  /// resource subscription is active. Disabling clears any pending delta, so the
  /// next subscription begins from "now".
  set accumulateDeltas(bool enabled) {
    _accumulateDeltas = enabled;
    if (!enabled) {
      _accChanged.clear();
      _accRemoved.clear();
      _accFull = false;
    }
  }

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

  /// Returns the net semantic delta accumulated since the last call, and clears
  /// the accumulator. Call once after each [settle] to push exactly one coalesced
  /// delta per settled burst (a continuously-animating app coalesces into one
  /// delta per settle window rather than a per-frame storm).
  SemanticTreeDelta takeDelta() {
    final delta = SemanticTreeDelta(
      changedIds: _accChanged.toList(growable: false),
      removedIds: _accRemoved.toList(growable: false),
      full: _accFull,
    );
    _accChanged.clear();
    _accRemoved.clear();
    _accFull = false;
    return delta;
  }

  // Folds the most recent decoded frame's delta into the running accumulator. A
  // full frame resets it to "everything changed"; a patch nets out changed vs
  // removed so an id that flips both ways within a burst lands on its final side.
  void _accumulateDelta() {
    if (_decoder.wasFull) {
      _accFull = true;
      _accRemoved.clear();
      _accChanged
        ..clear()
        ..addAll(_decoder.changedIds);
      return;
    }
    for (final id in _decoder.removedIds) {
      _accChanged.remove(id);
      _accRemoved.add(id);
    }
    for (final id in _decoder.changedIds) {
      _accRemoved.remove(id);
      _accChanged.add(id);
    }
  }

  /// Whether the app is still connected (false once it sends BYE or the
  /// transport drops).
  bool get isRunning => !_exited.isCompleted;

  /// True once the app connected but did not render a first frame within
  /// [firstFrameTimeout] (e.g. it never called runApp). Lets tools fail fast
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
  /// real element tree and re-renders; observe the visual result with
  /// [settle]. The returned future carries the app-reported invocation
  /// status (v3 SEMANTIC_ACTION_RESULT), or null against an older app that
  /// doesn't send results.
  Future<SemanticActionInvocationStatus?> invokeAction(
    SemanticNodeId id,
    SemanticAction action,
  ) {
    final status = _expectActionResult(id, action);
    _send(SemanticActionFrame(id, action));
    return status;
  }

  /// Sets node [id]'s value to [value] — the payload for a `setValue` action
  /// (text into a field, a slider position…). The node must advertise
  /// `setValue`; observe the visual result with [settle]. Returns the
  /// app-reported invocation status like [invokeAction].
  Future<SemanticActionInvocationStatus?> setValue(
    SemanticNodeId id,
    Object? value,
  ) {
    final status = _expectActionResult(id, SemanticAction.setValue);
    try {
      _send(SemanticActionFrame(id, SemanticAction.setValue, value: value));
    } catch (_) {
      // The value could not be encoded into a frame (too large — see [_send]).
      // Drop the armed wait and let the failure propagate so the caller reports
      // it; the app is untouched. (invokeAction's payload is just id+action and
      // is always within the cap, so it needs no such guard.)
      _abortPendingAction();
      rethrow;
    }
    return status;
  }

  /// The in-flight mutation awaiting its SEMANTIC_ACTION_RESULT, tagged with the
  /// (id, action) it was armed for so an arriving result is correlated to the
  /// request it belongs to. Mutations are serialized by the MCP server, so at
  /// most one is pending.
  ({
    SemanticNodeId id,
    SemanticAction action,
    Completer<SemanticActionInvocationStatus?> completer,
  })?
  _pendingAction;

  /// Arms a one-shot listener for the SEMANTIC_ACTION_RESULT that echoes back
  /// [id]/[action] (the app echoes both onto the result frame). Bounded:
  /// resolves null when no result lands (a pre-v3 app, or one still running a
  /// slow async handler) so callers degrade to the tree-diff heuristic instead
  /// of hanging.
  Future<SemanticActionInvocationStatus?> _expectActionResult(
    SemanticNodeId id,
    SemanticAction action,
  ) {
    // Supersede any still-armed prior wait (shouldn't happen under the server's
    // serialization, but keeps the field single-valued defensively).
    final prior = _pendingAction;
    if (prior != null && !prior.completer.isCompleted) {
      prior.completer.complete(null);
    }
    final completer = Completer<SemanticActionInvocationStatus?>();
    final pending = (id: id, action: action, completer: completer);
    _pendingAction = pending;
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        // De-arm on timeout so a LATE result for THIS request (a >2s async
        // handler that finished after we gave up) can't bind to the NEXT
        // mutation armed in our place. Guard against a newer mutation having
        // already replaced us.
        if (identical(_pendingAction, pending)) _pendingAction = null;
        return null;
      },
    );
  }

  /// Aborts the in-flight mutation wait — its frame could not be sent — resolving
  /// its caller to null so the tool degrades to the tree-diff heuristic.
  void _abortPendingAction() {
    final pending = _pendingAction;
    _pendingAction = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(null);
    }
  }

  int _debugSeq = 0;
  final Map<int, Completer<List<Object?>?>> _pendingDebug =
      <int, Completer<List<Object?>?>>{};

  /// Pulls a bounded, newest-last list of debug records of [kind]
  /// (`frames` / `logs` / `errors`) from the running app — the DT1 agent
  /// devtools channel. Returns the decoded JSON records, or null when the app
  /// doesn't answer within the timeout (an app built before this protocol
  /// frame, or one with debug tooling disabled), so a tool call degrades to
  /// "not available" instead of hanging.
  Future<List<Object?>?> queryDebug(String kind, {int limit = 50}) {
    if (!isRunning) return Future<List<Object?>?>.value(null);
    // Wrap within the 32-bit range the wire seq round-trips (the response
    // echoes it back through a 4-byte field); collisions only matter among the
    // handful of concurrently-pending queries, which this never reaches.
    final seq = _debugSeq = (_debugSeq + 1) & 0x7FFFFFFF;
    final completer = Completer<List<Object?>?>();
    _pendingDebug[seq] = completer;
    _send(DebugRequestFrame(seq, kind, limit: limit));
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _pendingDebug.remove(seq);
        return null;
      },
    );
  }

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

  /// Sends a frame. A genuine transport failure (the socket dropped between our
  /// last `isRunning` check and now) is treated as the app exiting, so callers
  /// get a clean "app gone" path. A [RemoteProtocolException] is different: the
  /// local encoder REJECTED an oversized in-band frame ("frame was not
  /// encoded") — the connection is intact, so it rethrows for the caller to
  /// surface as a recoverable error rather than falsely declaring the healthy
  /// app dead and tearing the session down.
  void _send(RemoteFrame frame) {
    if (!isRunning) return;
    try {
      _transport.send(frame);
    } on RemoteProtocolException {
      rethrow;
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
    Duration settleCap = const Duration(milliseconds: 500),
  }) async {
    final stopwatch = Stopwatch()..start();
    Duration clampToZero(Duration d) => d.isNegative ? Duration.zero : d;
    Duration remaining() => clampToZero(timeout - stopwatch.elapsed);

    // Phase 1: wait for the first reaction past the captured revision.
    if (sinceRevision != null) {
      while (isRunning &&
          _revision <= sinceRevision &&
          stopwatch.elapsed < timeout) {
        await _nextTick(remaining());
      }
    }

    // Phase 2: event-driven debounce. Wait `quiet` for the next frame; if none
    // arrives in that window the burst has settled, so return — a discrete
    // reaction whose frames are spaced wider than `quiet` settles fully here.
    //
    // But a continuously-animating region (a ticking dashboard) bumps the
    // revision faster than `quiet` forever and NEVER goes quiet, so the debounce
    // alone would chase quiet until the full `timeout` on every observe. Bound
    // Phase 2 by `settleCap` past this point: Phase 1 already captured the
    // reaction, so when the app won't go quiet we return the live frame in
    // ~settleCap rather than eating `timeout`.
    //
    // Trade-off: for a *finite* animation that runs faster than `quiet` and lasts
    // longer than `settleCap` (e.g. a 700 ms progress fill), this returns a
    // transitional frame — the latest, but not the final settled one. That is the
    // accepted cost of not waiting out `timeout` on the common ticking case; an
    // agent that needs the settled value should `wait_for_change` or re-read.
    // Sub-`settleCap` reactions are unaffected.
    final phase2Deadline = stopwatch.elapsed + settleCap;
    Duration phase2Remaining() => clampToZero(phase2Deadline - stopwatch.elapsed);
    while (isRunning &&
        stopwatch.elapsed < timeout &&
        stopwatch.elapsed < phase2Deadline) {
      final before = _revision;
      final budget = remaining() < phase2Remaining()
          ? remaining()
          : phase2Remaining();
      final window = quiet < budget ? quiet : budget;
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
        if (_accumulateDeltas) _accumulateDelta();
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
      case CaretFrame _:
      case ClipboardResultFrame _:
      case DebugRequestFrame _:
        break;
      case DebugResponseFrame f:
        final pending = _pendingDebug.remove(f.seq);
        if (pending != null && !pending.isCompleted) {
          try {
            pending.complete(
              jsonDecode(utf8.decode(f.json)) as List<Object?>,
            );
          } catch (_) {
            pending.complete(null); // malformed payload — treat as unavailable
          }
        }
      case ClipboardWriteFrame f:
        // The app copied. An MCP bridge has no user clipboard; answer
        // immediately so the app's report degrades to its in-process
        // register without waiting out the result timeout.
        _send(ClipboardResultFrame(f.seq, RemoteClipboardStatus.unavailable));
      case SemanticActionResultFrame f:
        // Correlate the result to the request it echoes. A late result from a
        // prior slow action whose wait already timed out must NOT be attributed
        // to the next mutation now armed — match on (id, action), and drop a
        // stale straggler that matches nothing rather than mis-binding it.
        final pending = _pendingAction;
        if (pending != null &&
            pending.id == f.id &&
            pending.action == f.action) {
          _pendingAction = null;
          if (!pending.completer.isCompleted) {
            pending.completer.complete(f.status);
          }
        }
    }
  }

  Future<void> _nextTick(Duration timeout) {
    // A non-positive window yields a real event-loop turn (a zero-delay timer),
    // not just a microtask (Future.value): the settle loops can momentarily
    // compute a zero window at a deadline boundary, and a microtask would not let
    // frame I/O or timers run — so a future loop edit could hot-spin. A real turn
    // keeps that impossible by construction.
    if (timeout <= Duration.zero) return Future<void>.delayed(Duration.zero);
    return _tick.future.timeout(timeout, onTimeout: () {});
  }

  void _signalTick() {
    final pending = _tick;
    _tick = Completer<void>();
    if (!pending.isCompleted) pending.complete();
  }

  void _markExited() {
    for (final c in _pendingDebug.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pendingDebug.clear();
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
    final logLine = log ?? stderr.writeln;
    final SpawnedFleuryApp app;
    try {
      app = await spawnFleuryApp(
        command: command,
        connectTimeout: connectTimeout,
        onLog: (tag, line) => logLine('[app $tag] $line'),
      );
    } on FleurySpawnException catch (e) {
      // Preserve the bridge's exception type for existing callers/tests.
      throw FleuryAppBridgeException(e.message);
    }
    logLine(
      '[fleury_mcp] attached to ${command.join(' ')} (pid ${app.process.pid})',
    );

    final transport = UnixSocketFrameTransport.fromSocket(app.socket);
    final bridge = FleuryAppBridge(
      transport,
      viewport: viewport,
      firstFrameTimeout: firstFrameTimeout,
      onClose: app.dispose,
    );
    // A crashing app tears the bridge down too.
    unawaited(app.process.exitCode.then((_) => bridge.close()));
    bridge.start();
    return bridge;
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
