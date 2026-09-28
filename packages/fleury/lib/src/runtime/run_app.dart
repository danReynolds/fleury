// runApp: the application entry point that ties everything together.
//
// Mounts a root widget, owns a terminal driver, runs a frame loop
// (event -> setState -> flushBuild -> renderFrame -> ANSI diff -> stdout),
// attaches hot-reload handlers, and cleans up on exit even when an
// exception bubbles up.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io'
    show File, FileMode, Platform, RandomAccessFile, Stdout, stderr, stdout;

import 'package:meta/meta.dart';

import '../debug/debug_events.dart';
import '../debug/debug_invalidation.dart';
import '../debug/debug_shell.dart';
import '../debug/debug_state.dart';
import '../foundation/fleury_error.dart';
import '../remote/remote_driver.dart';
import '../remote/remote_protocol.dart' show maxRemoteDebugResponseJsonLength;
import '../remote/unix_socket_transport.dart';
import '../rendering/ansi_byte_budget.dart';
import '../rendering/ansi_renderer.dart';
import 'runtime_error_overlay.dart';
import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import '../terminal/diagnostics.dart';
import '../input/events.dart';
import '../input/keyboard_latch.dart';
import 'dev_bootstrap.dart';
import 'package:stdio/stdio.dart' as fd;

import '../terminal/native_driver.dart';
import '../terminal/posix_driver.dart';
import '../terminal/posix_input_lease.dart';
import '../terminal/terminal_driver.dart';
import '../terminal/pointer_shapes.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/terminal_session.dart';
import '../widgets/keyboard.dart';
import '../widgets/overlay.dart';
import '../widgets/selection/selection_area.dart';
import 'clipboard.dart';
import '../terminal/ansi_frame_presenter.dart';
import '../terminal/terminal_image_encoder.dart';
import 'frame_driver.dart';
import 'frame_semantics_pipeline.dart';
import 'frame_presentation.dart';
import 'handle_discovery.dart';
import '../remote/remote_clipboard.dart';
import '../remote/wire_semantic_frame_presenter.dart';
import 'wire_frame_presenter.dart';
import 'hot_reload.dart';
import 'semantic_flush_scheduler.dart';
import 'system_clipboard.dart';
import 'input_dispatcher.dart';
import '../debug/debug_frame_log.dart';
import 'debug_query.dart';
import 'output_capture.dart';
import 'remote_surface_sink.dart';
import 'tui_frame_loop.dart';
import 'tui_root.dart';
import 'tui_runtime.dart';

/// What a [TuiEventHandler] can tell the runtime about an event.
sealed class EventResponse {
  const EventResponse();
}

/// Returned by an event handler in [runApp] to ask the loop to exit
/// cleanly ([runApp] resolves with [AppExit.requested]).
final class ExitRequested extends EventResponse {
  const ExitRequested();
}

/// Returned by an event handler to claim an event whose *unhandled*
/// default would act — today that's [SignalEvent], whose unclaimed
/// default is "terminate" ([AppExit.signal]). Claiming hands the
/// shutdown to the app, which finishes by calling [exitApp] once
/// its cleanup is done. Mind the driver's grace deadline: shutdown
/// must complete within it or the process is force-terminated.
final class EventHandled extends EventResponse {
  const EventHandled();
}

/// Why [runApp] ended — so the caller owns process exit semantics
/// (map [signal] to `128 + n` exit codes, run cleanup in `finally`,
/// then `exit()` yourself).
@immutable
final class AppExit {
  /// An orderly exit: [exitApp], an [ExitRequested] response, or the
  /// input stream ending (stdin EOF / remote disconnect).
  const AppExit.requested() : signal = null;

  /// An unclaimed [SignalEvent] or unhandled Ctrl+C ended the app.
  /// Ctrl+C reports [AppSignal.interrupt] even when raw input delivers it as
  /// a key, so callers can preserve the same exit status as SIGINT.
  const AppExit.signal(AppSignal this.signal);

  final AppSignal? signal;

  @override
  String toString() =>
      signal == null ? 'AppExit.requested' : 'AppExit.signal(${signal!.name})';
}

/// Optional handler called for every input event before the framework
/// re-renders.
///
/// Returning [ExitRequested] terminates the loop (and triggers cleanup).
/// Returning [EventHandled] claims the event, suppressing its unhandled
/// default (see [SignalEvent]). Returning null lets the event through to
/// the rest of the app (typically widgets that subscribed to the driver's
/// event stream directly).
typedef TuiEventHandler = EventResponse? Function(TuiEvent event);

// Admission and exit identity have different lifetimes: closing an app stops
// accepting exit requests immediately, but retains admission through cleanup.
// This is an isolate-local owner, not an OS lock against other terminal users.
final _invocationZoneKey = Object();
_RunAppInvocation? _activeInvocation;

final class _RunAppInvocation {
  _RunAppInvocation() {
    final owner = _activeInvocation;
    if (owner != null) {
      if (owner._finished) {
        throw StateError(
          'The previous Fleury session has unfinished or failed terminal '
          'cleanup (${owner._criticalResources.values.toSet().join(', ')}). '
          'Resolve that cleanup before starting another session.',
        );
      }
      throw StateError(
        'A Fleury runApp session is already starting, running, or closing. '
        'Await its completion before starting another session.',
      );
    }
    _activeInvocation = this;
  }

  final exit = Completer<AppExit>();
  bool closing = false;
  bool _finished = false;
  final _criticalResources = <Object, String>{};

  // An asynchronous startup can outlive fatal-error cleanup. Keep admission
  // until it settles; its late-result cleanup must be part of this operation.
  Future<T> startResource<T>(String resource, Future<T> Function() action) {
    final token = Object();
    _criticalResources[token] = resource;
    return Future<T>.sync(action).whenComplete(() {
      _criticalResources.remove(token);
      _releaseIfSafe();
    });
  }

  bool exitApp() {
    if (closing || exit.isCompleted) return false;
    exit.complete(const AppExit.requested());
    return true;
  }

  void release() {
    closing = true;
    _finished = true;
    _releaseIfSafe();
  }

  // Track the underlying operation, never its timeout wrapper. A deadline can
  // fail runApp, but cannot cancel native I/O or establish restored ownership.
  Future<void> restoreCritical(
    String resource,
    FutureOr<void> Function() action,
  ) {
    final token = Object();
    _criticalResources[token] = resource;
    return Future<void>.sync(action).then((_) {
      _criticalResources.remove(token);
      _releaseIfSafe();
    });
    // On error the entry deliberately remains: restoration was not proven.
  }

  void _releaseIfSafe() {
    if (_finished &&
        _criticalResources.isEmpty &&
        identical(_activeInvocation, this)) {
      _activeInvocation = null;
    }
  }
}

FleuryError _terminalCleanupError(Iterable<String> resources) => FleuryError(
  summary: 'Fleury could not safely release the terminal.',
  details: 'Cleanup failed or is still pending: ${resources.join(', ')}.',
  hint:
      'Do not start another prompt or UI while terminal cleanup is unfinished. '
      'Resolve outstanding terminal operations, or end this CLI invocation. '
      'Fleury keeps new sessions blocked until ownership is proven released.',
);

/// Starts an orderly exit from the current [runApp] invocation.
///
/// Stops the UI and restores the terminal without ending the Dart process.
/// Await [runApp]'s future for cleanup to finish; it resolves with
/// [AppExit.requested]. There is no exit-veto callback.
///
/// This is the programmatic quit for `q` keys, palette "Quit" commands,
/// and app-owned signal shutdown (claim the [SignalEvent] with
/// [EventHandled], run your teardown, then call this). Returns false
/// when no app is running or an exit is already in flight.
/// Calls from an app callback remain bound to that invocation: a callback that
/// outlives its app returns false and cannot exit a subsequent session. A host
/// call outside an app's zone targets the currently running invocation.
bool exitApp() {
  final invocation =
      Zone.current[_invocationZoneKey] as _RunAppInvocation? ??
      _activeInvocation;
  return invocation?.exitApp() ?? false;
}

/// Bounded replay for driver events that arrive while [TerminalDriver.enter]
/// negotiates capabilities and the application tree mounts.
///
/// Driver event streams are broadcast. Subscribing after `enter()` silently
/// loses ready stdin, enter-time keystrokes, and EOF-time input; subscribing
/// early without a bound merely moves the problem into unbounded startup
/// memory. This queue makes the handoff explicit and fails startup loudly if a
/// custom driver exceeds the short negotiation budget.
final class _StartupEventBuffer {
  static const maxEvents = 4096;
  static const maxPayloadBytes = 1024 * 1024;

  final Queue<TuiEvent> _events = Queue<TuiEvent>();
  var _payloadBytes = 0;
  StateError? overflowError;

  void add(TuiEvent event) {
    if (overflowError != null) return;
    final payloadBytes = _eventPayloadBytes(event);
    if (_events.length >= maxEvents ||
        _payloadBytes + payloadBytes > maxPayloadBytes) {
      overflowError = StateError(
        'Terminal input exceeded the bounded startup replay buffer '
        '($maxEvents events / $maxPayloadBytes UTF-8 bytes) before the app '
        'finished mounting.',
      );
      return;
    }
    _events.addLast(event);
    _payloadBytes += payloadBytes;
  }

  Iterable<TuiEvent> drain() sync* {
    while (_events.isNotEmpty) {
      yield _events.removeFirst();
    }
    _payloadBytes = 0;
  }

  static int _eventPayloadBytes(TuiEvent event) {
    final text = switch (event) {
      TextInputEvent(:final text) => text,
      TextCompositionEvent(:final text) => text,
      PasteEvent(:final text) => text,
      KeyEvent(:final code) => code.character,
      InputBatch(:final committedText, :final key) =>
        committedText ?? key?.code.character,
      _ => null,
    };
    return text == null ? 0 : utf8.encode(text).length;
  }
}

/// Maximum time teardown waits for one asynchronous resource before moving on.
///
/// A broken custom stream/controller must not strand the process in raw mode or
/// keep [runApp] pending forever. Timed-out futures may still settle later, but
/// every callback they can reach observes `disposed` before teardown starts.
const _cleanupResourceTimeout = Duration(seconds: 1);

/// `package:stdio` already bounds inherited-child drain at two seconds. Leave
/// headroom for that valid tail flush while retaining an outer fail-safe.
const _stdioCleanupResourceTimeout = Duration(seconds: 3);

/// One stalled remote semantic handler must not retain an unbounded chain of
/// actions (and their optional values) for the lifetime of the session.
const _maxPendingRemoteSemanticActions = 64;

/// How long a served semantic action holds the actions queued behind it
/// before the queue moves on without its result: long enough for a handler's
/// own async work (an awaited validation, a store write), short of a handler
/// awaiting UI that a later action answers.
const _semanticActionQueueHold = Duration(milliseconds: 500);

/// Runs an fleury application.
///
/// This thin wrapper exists for one safety property: if ANYTHING escapes the
/// implementation as a throw — including setup failures before the guarded
/// zone (and its cleanup) are established — the fd-level stray-output capture
/// is stopped so fd 1/2 point back at the real terminal. Without it, an
/// embedding caller that catches the throw and keeps running would find its
/// process's stdout/stderr silently swallowed. Once normal cleanup takes
/// ownership, only that operation stops capture, after terminal borrows settle.
///
/// ## Own your shutdown
///
/// Resolves with an [AppExit] saying why the app ended, AFTER the terminal is
/// restored. The caller owns process-exit semantics.
/// A terminal-critical cleanup failure throws [FleuryError] instead. Overlapping
/// invocations are rejected, including while an earlier cleanup is unfinished.
///
/// ```dart
/// try {
///   final result = await runApp(app);
///   io.exitCode = switch (result.signal) {
///     AppSignal.interrupt => 130,
///     AppSignal.terminate => 143,
///     AppSignal.hangup => 129,
///     null => 0,
///   };
/// } finally {
///   await host.shutdown(); // resources owned by your command
/// }
/// ```
///
/// SIGINT/SIGTERM/SIGHUP arrive as [SignalEvent]s;
/// an unclaimed one terminates with [AppExit.signal]. The POSIX driver arms a
/// grace deadline at delivery ([PosixTerminalDriver.signalGrace], default 5s)
/// and force-terminates a hung app — a second same-signal forces immediately —
/// so claiming a signal obliges finishing within the grace.
/// To keep the UI visible during cleanup, claim the signal with [EventHandled]
/// and call [exitApp] when finished. Preserve the original signal yourself:
/// that later exit returns [AppExit.requested]. Raw Ctrl+C reaches widget key
/// bindings first; if unhandled it exits before [onEvent] with an interrupt.
///
/// [onStrayOutput] takes ownership of captured output instead of replaying it
/// after exit. A throwing hook is disabled and reported through the runtime
/// error handler; its failed line and subsequent output return to normal replay.
/// Earlier successfully handled lines are not replayed a second time.
///
/// [root] is mounted exactly as supplied. The runtime owns terminal and
/// framework host services, but it does not choose an application shell.
/// Wrap the root in `FleuryApp(home: ...)` for Fleury's standard navigation
/// shell, or supply a `Navigator`/custom shell explicitly. Bare single-screen
/// roots remain valid.
/// Pass your `main()` argv as [args] if the app reads it: a dev hot-reload
/// respawn re-runs the entrypoint, and a process cannot portably recover its
/// own script arguments, so without this the restarted app sees an empty argv
/// and may show something other than what was asked for.
///
/// ```dart
/// Future<void> main(List<String> args) => runApp(MyApp(), args: args);
/// ```
///
Future<AppExit> runApp(
  Widget root, {
  TerminalDriver? driver,
  TerminalMode mode = TerminalMode.interactive,
  bool enableHotReload = true,
  bool requireInteractiveTerminal = true,
  void Function(LogLine line)? onStrayOutput,
  TuiEventHandler? onEvent,
  Clipboard? clipboard,
  Duration sequenceTimeout = const Duration(milliseconds: 500),
  DebugConfig debug = const DebugConfig(),
  Duration frameInterval = Duration.zero,
  List<String> args = const [],
}) async {
  // Acquire synchronously, before bootstrap awaits or descriptor capture.
  // Queuing an overlapping call would deadlock a nested, awaited runApp.
  final invocation = _RunAppInvocation();
  try {
    // Plain `dart run` dev sessions hand the process to the dev supervisor:
    // it re-spawns this same script as a child process with the VM service
    // enabled (the child re-enters runApp and takes the classic path below),
    // and drives save-to-reload + hot restart from outside the app. Every
    // other kind of run — tests (injected driver), AOT, Windows, no TTY,
    // serve handles, editor/debugger sessions with a live VM service — falls
    // through untouched, and (shouldConsider being synchronous) with runApp's
    // original synchronous prefix intact.
    if (DevBootstrap.shouldConsider(
      driverInjected: driver != null,
      enableHotReload: enableHotReload,
    )) {
      await DevBootstrap.runOrFallThrough(args: args);
      // Reaching here means this run was ineligible after async checks or the
      // bootstrap could not start; run classically.
    }
    // The supervised child's half of the handshake: silently self-enable the
    // VM service and tell the supervisor where it is. Fire-and-forget; a
    // no-op outside supervised sessions.
    DevBootstrap.maybeStartSupervisedChildHandshake();
    fd.Stdio? cap;
    var captureCleanupOwned = false;
    try {
      return await runZoned(
        () => _runAppImpl(
          root,
          invocation: invocation,
          driver: driver,
          mode: mode,
          enableHotReload: enableHotReload,
          requireInteractiveTerminal: requireInteractiveTerminal,
          onStrayOutput: onStrayOutput,
          onEvent: onEvent,
          clipboard: clipboard,
          sequenceTimeout: sequenceTimeout,
          debug: debug,
          frameInterval: frameInterval,
          onFdCaptureStarted: (c) => cap = c,
          onFdCaptureCleanupOwned: () => captureCleanupOwned = true,
        ),
        zoneValues: {_invocationZoneKey: invocation},
      );
    } on Object {
      invocation.closing = true;
      final c = cap;
      // Once normal cleanup owns capture, its actual operation can outlive a
      // reporting timeout. Stopping it here would bypass the terminal/child
      // barrier and close the saved output handle while it is still borrowed.
      if (c != null && c.isActive && !captureCleanupOwned) {
        try {
          await invocation
              .restoreCritical('stdio capture', c.stop)
              .timeout(_stdioCleanupResourceTimeout);
        } catch (_) {
          throw _terminalCleanupError(['stdio capture']);
        }
      }
      rethrow;
    }
  } finally {
    invocation.release();
  }
}

/// Implementation of [runApp] — see the wrapper for the fd-capture safety
/// contract.
///
/// Sequence:
///
///   1. Acquire a [TerminalDriver] (defaults to the native platform driver).
///   2. Subscribe to driver events into a bounded startup replay buffer.
///   3. Enter [mode] (raw input, alt screen, hidden cursor by default).
///   4. Mount [root] under a [BuildOwner]; render the first
///      frame.
///   5. Attach hot-reload handlers (`ext.fleury.reassemble` extension
///      + VM-service `IsolateReload` listener) unless [enableHotReload]
///      is false.
///   6. Replay buffered input in source order, then dispatch live driver
///      events. On each event, optionally consult
///      [onEvent]; if it returns [ExitRequested], or the event is an
///      unhandled Ctrl+C, or it is a [SignalEvent] the handler did not
///      claim with [EventHandled], exit the loop. [exitApp] exits
///      programmatically from anywhere in the app.
///   7. Schedule a render frame after every event and after every
///      `setState` (via [BuildOwner.onScheduleBuild]).
///   8. On exit (normal or exceptional): cancel subscriptions, dispose
///      hot-reload, restore the terminal.
///
/// The frame loop renders on demand — the first frame is painted
/// eagerly, then frames happen only after events, `setState`, or an
/// animation tick. The render loop itself is never free-running: the
/// animation `TickerScheduler` (≈30 Hz) only fires while something is
/// animating, and each tick marks elements dirty, which coalesces into
/// a single on-demand frame. Idle apps schedule no frames at all.
///
/// Multiple updates within one event-loop turn already coalesce into one
/// frame. To also cap the rate ACROSS turns — so a high-rate stream (tokens,
/// log lines) or rapid `setState`s collapse to one frame per interval instead
/// of one each — pass [frameInterval] (e.g. `Duration(milliseconds: 16)` for
/// ~60 fps). This trims frame COUNT, which is what drives perceived latency on
/// round-trip-bound transports (WAN SSH) and streaming agent UIs. The default
/// ([Duration.zero]) is uncapped. Updates are merged, never dropped.
///
/// Requires an interactive terminal: if standard output is piped or
/// redirected (no TTY), this throws before entering rather than spewing
/// cursor-control sequences into the stream. Pass
/// [requireInteractiveTerminal] = false to run anyway (screen control and
/// raw input are skipped where there's no terminal).
Future<AppExit> _runAppImpl(
  Widget root, {
  required _RunAppInvocation invocation,
  TerminalDriver? driver,
  TerminalMode mode = TerminalMode.interactive,
  bool enableHotReload = true,
  bool requireInteractiveTerminal = true,
  void Function(LogLine line)? onStrayOutput,
  TuiEventHandler? onEvent,
  Clipboard? clipboard,
  Duration sequenceTimeout = const Duration(milliseconds: 500),
  DebugConfig debug = const DebugConfig(),
  Duration frameInterval = Duration.zero,
  void Function(fd.Stdio capture)? onFdCaptureStarted,
  void Function()? onFdCaptureCleanupOwned,
}) async {
  final runtimeMarkers = _RuntimeMarkerRecorder.fromEnvironment();
  // Explicit drivers own their output surface, which need not be process
  // stdio (or even support terminal queries on its IOOverrides).
  final stdoutWasTerminal = driver == null && stdout.hasTerminal;
  final stderrWasTerminal = driver == null && stderr.hasTerminal;
  bool outputHungUp(int descriptor) =>
      (descriptor == 1 ? stdoutWasTerminal : stderrWasTerminal) &&
      posixDescriptorHungUp(descriptor);
  runtimeMarkers?.mark('runApp.entry');
  // The stray-output guard. When the session resolves to the local native
  // driver on POSIX with a real-TTY stdout, redirect fd 1/2 (dup2, via
  // package:stdio) BEFORE the driver binds its stdout, and hand the driver
  // the saved real-terminal handle. Descriptor-level capture catches EVERY
  // writer in the process — Dart print, loggers, native/FFI libraries,
  // inheritStdio children, code outside runApp's zone — which is why it is
  // the only mechanism: zone/IOOverrides layers were removed as redundant
  // where this engages and misleadingly partial where it can't. Where the
  // guard does not engage (remote/serve sessions — frames aren't on fd 1;
  // custom drivers — they own output policy; Windows — pending stdio
  // support; FLEURY_FD_CAPTURE=0), stray output flows wherever fd 1/2
  // point, conventionally.
  fd.Stdio? fdCapture;
  Future<Stdout?> startFdCapture() async {
    if (Platform.isWindows) return null;
    if (Platform.environment['FLEURY_FD_CAPTURE'] == '0') return null;
    // Only guard a real screen. On a piped/redirected stdout there are no
    // frames to corrupt — and redirecting the descriptors there would swallow
    // even the "needs an interactive terminal" error runApp is about to
    // throw (stderr is fd 2). `stdout` is still the real descriptor here:
    // this runs before any redirection.
    if (!stdout.hasTerminal) return null;
    try {
      fdCapture = await fd.Stdio.start();
    } on Object {
      return null; // capture unavailable (e.g. another session) — fall back
    }
    onFdCaptureStarted?.call(fdCapture!);
    return fdCapture!.terminal;
  }

  // Remote sessions (serve --spawn / a shell handle) skip the
  // terminal fd guard above — frames go over the socket, not fd 1, so there's
  // nothing to protect. But that also left the LogBuffer unfed, so an agent's
  // read_logs came back empty. When debug tooling is on, capture on the real
  // remote paths too — with `mirrorToOriginal`: stdio's reader isolate mirrors
  // every raw captured chunk back through the saved descriptors,
  // byte-transparent and split-intact, so the parent's own log forwarding
  // (fleury_mcp's [app out/err], serve's sanitized relay) keeps working
  // exactly as before capture. Mirroring lives OFF the main isolate and never
  // blocks it: a parent that stops draining costs a bounded backlog, then
  // mirror loss — never a frozen app. `remoteFdMirror` also suppresses the
  // replay-on-exit below: the parent already received everything live.
  // Invoked by the RESOLVER on its remote branches — the one place that knows
  // this is a real handle-connected session — so a test handing in a
  // RemoteTerminalDriver over a fake transport never has its runner's
  // descriptors captured.
  var remoteFdMirror = false;
  Future<void> startRemoteFdCapture() async {
    if (fdCapture != null) return;
    if (!debug.enabled) return;
    if (Platform.isWindows) return;
    if (Platform.environment['FLEURY_FD_CAPTURE'] == '0') return;
    try {
      fdCapture = await fd.Stdio.start(mirrorToOriginal: true);
      remoteFdMirror = true;
      onFdCaptureStarted?.call(fdCapture!);
    } on Object {
      // Capture unavailable (nested session, unsupported platform build):
      // read_logs stays empty, everything else works.
    }
  }

  // Captured before the frame-loop scope shadows `driver` with the
  // FrameDriver local — the hot-restart gate below needs the injection fact.
  final driverInjected = driver != null;
  final usedDriver =
      driver ??
      await _resolveDefaultDriver(
        nativeStdout: startFdCapture,
        remoteCapture: startRemoteFdCapture,
      );
  // Long-lived shell-state holder. Survives setState / rebuilds; the
  // root is rebuilt whenever the viewport resizes, so a per-build
  // controller would lose mode + tab selection on every SIGWINCH.
  final debugController = DebugController(debug);
  TerminalDiagnosis currentTerminalDiagnosis() => diagnoseTerminal(
    usedDriver,
    environment: Platform.environment,
    stdoutIsTerminal: usedDriver.isInteractive,
  );
  debugController.setTerminalDiagnosisProvider(currentTerminalDiagnosis);
  DebugEvents.emitTerminalDiagnosis(currentTerminalDiagnosis());

  // Fail fast (before touching the terminal or allocating the tree) when
  // there's no interactive display to draw to. A visual TUI piped to a file
  // or a CI log would only emit cursor-control garbage; surfacing a clear
  // error beats producing corrupt output. Opt out with
  // requireInteractiveTerminal: false when the caller is deliberately
  // capturing the stream.
  if (requireInteractiveTerminal && !usedDriver.isInteractive) {
    throw FleuryError(
      summary:
          'runApp needs an interactive terminal, but standard output '
          'is not a TTY.',
      details:
          'Standard output looks piped or redirected — `app > out.txt`, '
          '`app | less`, or a CI log. A TUI emits cursor-positioning and '
          'screen-control sequences that only make sense on a real terminal; '
          'sending them to a file or pipe would just corrupt the stream.',
      hint:
          'Run the app attached to a terminal. To intentionally capture '
          'the stream (e.g. for tests), pass '
          '`requireInteractiveTerminal: false` — raw input and screen '
          'control are skipped when no terminal is present.',
    );
  }

  final runtime = TuiRuntime();
  final focusManager = runtime.focusManager;
  final owner = runtime.owner;
  final binding = runtime.binding;
  final pointerRouter = runtime.pointerRouter;
  // Floating OutputCaptureConsole lives in the unified DebugShell — F12 is a binding on
  // DebugShell that opens the docked panel with the Logs tab focused (rather
  // than a separate Overlay entry), backed by the always-available `debug`
  // config.
  final overlayKey = GlobalKey<OverlayState>();

  final dispatcher = InputDispatcher(
    focusManager: focusManager,
    pointerRouter: pointerRouter,
    sequenceTimeout: sequenceTimeout,
  );
  // Publishes the session keyboard to `Keyboard.of` (capabilities reactive,
  // sampled state not — RFC 0020 §15).
  final keyboardNotifier = KeyboardStateNotifier(dispatcher);
  // The keyboard latch is wired to both its clocks here, and exactly ONE of
  // them publishes at a time — the session arbitrates on ticker registration
  // (RFC 0020 §5.6). Never call `publishLatch` anywhere else: two live
  // publishers is the measured defect, because a latch expires edges, so the
  // second site destroys the first's `wasPressed` edges before their
  // consumers read them (0 of 5 presses observed;
  // test/integration/ticker_edge_visibility_test.dart).
  //
  // Which clock is live is the correctness question. Edges are read from
  // ticks, so while a ticker runs the TICKER clock owns expiry: any render in
  // between — a clock in the status bar, an async update — leaves the latch
  // alone, and a tap survives to the tick that samples it. With no ticker
  // registered nothing would advance the latch at all, so the FRAME clock
  // takes over and `wasPressed` cannot report a stale tap forever.
  final publishFrameLatch = installKeyboardLatch(
    session: dispatcher.keyboardSession,
    scheduler: binding.tickerScheduler,
  );
  // A surface can answer the capability query truthfully and then not honour
  // it. When the session catches that mid-session it demotes itself to
  // press-only, and `Keyboard.capabilities` is reactive — so republishing here
  // is what flips an app's control scheme over to the one that works.
  dispatcher.onKeyboardCapabilitiesChanged =
      keyboardNotifier.notifyCapabilitiesChanged;
  // Optional byte telemetry: set FLEURY_BYTE_TELEMETRY=1 to wrap the live
  // output sink and print a per-frame byte budget on exit. Aggregate mode
  // (no per-frame list) so a long session stays bounded; zero cost when off.
  final driverSink = _DriverSink(usedDriver, runtimeMarkers);
  final byteTelemetry = Platform.environment['FLEURY_BYTE_TELEMETRY'] == '1'
      ? CountingAnsiSink.aggregate(driverSink)
      : null;
  // Optional diagnostic: FLEURY_ANSI_CAPTURE=/path tees every byte we emit to a
  // file (in addition to the terminal) so a rendering bug can be reproduced and
  // the exact escape stream inspected offline — no PTY/`script` needed.
  final capturePath = Platform.environment['FLEURY_ANSI_CAPTURE'];
  final AnsiSink sink = (capturePath != null && capturePath.isNotEmpty)
      ? _CapturingAnsiSink.wrap(byteTelemetry ?? driverSink, capturePath)
      : (byteTelemetry ?? driverSink);
  // Downsample colors to whatever the terminal actually supports.
  // DEC-2026 synchronized updates are selected by the entered session profile:
  // native POSIX negotiates them with DECRQM, while queryless transports stay
  // off. `FLEURY_SYNC_OUTPUT=1|0` is the explicit operator override for a
  // terminal whose report or implementation is known to be wrong.
  // Built after enter() below, from its immutable session profile.
  late final AnsiRenderer renderer;
  late final TerminalSessionProfile sessionProfile;
  AnsiTerminalPresentation? ansiPresentation;
  // Null for ANSI sessions; set from the sealed presentation choice returned
  // by enter() for structured remote sessions.
  RemoteSurfaceSink? surfaceSink;
  const presentationPlanner = FramePresentationPlanner();
  var disposed = false;
  // Constructed after the handshake (the presenter choice depends on the
  // negotiated path) and owns the frame program from then on.
  FrameDriver? frameDriver;
  // The shared semantics engine (structured path only): coverage fallback,
  // retained-leaf updates, and same-task wire flushes.
  FrameSemanticsPipeline? semanticsPipeline;
  // Structured-path clipboard (copy travels to the peer); disposed with
  // the session.
  RemoteClipboard? remoteClipboard;
  // Assigned once the negotiated path is known (buildRoot closes over it
  // but only runs at mount, after assignment).
  late final Clipboard effectiveClipboard;

  // Shared double-buffer and damage lifecycle. The host still owns
  // presentation, debug timings, input, and post-frame behavior.
  final frameLoop = TuiFrameLoop(renderDamage: runtime.renderDamageTracker);
  // The frame program lives in FrameDriver (constructed post-handshake);
  // this shim keeps every call site stable and safely coalesces requests
  // that arrive before mount.
  void scheduleFrame([String reason = 'scheduled']) {
    if (disposed) return;
    frameDriver?.requestFrame(reason);
  }

  HotReloadController? hotReload;
  InAppDevReload? devSelfReload;
  StreamSubscription<TuiEvent>? eventSub;
  final exit = invocation.exit;

  final done = Completer<AppExit>();
  Future<void>? cleanupFuture;

  // Captures stray output (see below). The buffer powers replay-on-exit; the
  // optional hook lets the caller route lines live (e.g. to a file).
  final logBuffer = LogBuffer();
  var strayOutputHook = onStrayOutput;
  // A healthy hook owns disposition. If it fails, retain the failed line and
  // later diagnostics for normal replay without duplicating earlier deliveries.
  int? replayFromLine = onStrayOutput == null ? 0 : null;
  // Headless frame log for a remote debug consumer (agent bridge / browser
  // DevTools). Created only when a served session has debug enabled; its
  // subscription is what turns on per-frame timing capture, so it stays off
  // otherwise. Disposed in cleanup.
  DebugFrameLog? debugFrameLog;
  final capture = OutputCapture(
    buffer: logBuffer,
    onLine: onStrayOutput == null
        ? null
        : (line) {
            final hook = strayOutputHook;
            if (hook == null) return;
            try {
              hook(line);
            } catch (error, stack) {
              // Disable before reporting: the reporter itself writes stderr,
              // which re-enters capture. A broken hook must not form an error
              // feedback loop or escape the runtime's terminal-restoring zone.
              strayOutputHook = null;
              replayFromLine = logBuffer.totalAdded - 1;
              Zone.current.handleUncaughtError(error, stack);
            }
          },
    sanitizeForTerminal: true,
  );

  // fd-capture wiring: assembled lines stream into the consumer pipeline
  // (sanitize -> LogBuffer -> onStrayOutput -> replay-on-exit). During an
  // editor/pager handoff the capture pauses so the child inherits the real
  // descriptors.
  StreamSubscription<fd.CapturedLine>? fdCaptureSub;
  void attachFdCapture() {
    final activeFdCapture = fdCapture;
    if (activeFdCapture == null) return;
    // (Remote sessions ALSO mirror raw bytes to the parent — but that happens
    // on stdio's reader isolate via mirrorToOriginal, not here; this consumer
    // only feeds the in-app LogBuffer.)
    void consume(fd.CapturedLine line) => capture.addLine(
      line.text,
      line.stream == fd.StdStream.err ? LogSource.stderr : LogSource.stdout,
    );

    // Anything written between capture start and this subscription (driver
    // construction runs in between) is retained in the capture's history —
    // seed the consumer so those lines replay too.
    activeFdCapture.history.forEach(consume);
    fdCaptureSub = activeFdCapture.output.listen(consume);
    if (usedDriver is PosixTerminalDriver) {
      usedDriver
        ..onHandoffStart = activeFdCapture.pause
        ..onHandoffEnd = activeFdCapture.resume;
    }
  }

  // Uncaught runtime errors (a throwing event handler, a failed async callback)
  // are reported and surfaced on screen rather than killing the session — see
  // the zone guard and the event-dispatch try/catch below. The listener
  // repaints so the banner appears/auto-dismisses.
  final errorReporter = RuntimeErrorReporter(
    onLog: (message) => stderr.writeln(message),
  )..addListener(() => scheduleFrame('runtime-error'));
  // Developer warnings ride the same surface as uncaught errors: stderr, the
  // on-screen banner, and the debug shell's history. A warning printed
  // straight to stdout would be painted over by the next frame.
  dispatcher.onDeveloperWarning = (warning) =>
      errorReporter.report(warning, StackTrace.current);
  // Contained layout/paint failures surface like any other survivable
  // error: stderr + the on-screen banner (once per error-state entry),
  // while the boundary renders the in-place presentation.
  owner.onContainedRenderError = (contained) =>
      errorReporter.report(contained.error, contained.stack);
  // Build-phase failures surface through the SAME reporter as every other
  // error class (stderr line, on-screen banner, debug-shell Errors tab, serve
  // read_errors wire). Without this a throwing build() only shows the red
  // ErrorWidget pixels — its stack trace is otherwise lost everywhere.
  owner.onBuildError = errorReporter.report;
  debugController.setErrorHistoryProvider(() => errorReporter.history);

  final startupEvents = _StartupEventBuffer();
  var driverEventsReady = false;
  var driverEventStreamDone = false;
  Object? driverEventStreamError;
  StackTrace? driverEventStreamStack;

  void handleDriverEvent(TuiEvent event) {
    if (disposed || exit.isCompleted) return;
    try {
      DebugEvents.emitInput(event);
      if (event is ResizeEvent) {
        // Same-size resize events represent a resumed/handed-off terminal and
        // still require a full repaint even though size comparison sees no
        // change.
        runtime.pointerRouter.cancel();
        frameDriver?.forceFullRepaint();
        DebugEvents.emitTerminalDiagnosis(currentTerminalDiagnosis());
      }

      if (event is TerminalFocusEvent) {
        // Focus left this terminal window: the keys the user is holding
        // will be released into whatever took focus, so this terminal will
        // never report them. Recover now (RFC 0020 §10) — otherwise every
        // held key stays held forever, a hold never ends, and sampled
        // state lies until something else is pressed.
        if (!event.focused) {
          dispatcher.recoverHeldKeys();
          runtime.pointerRouter.cancel();
        }
        return;
      }

      // Debug-shell hotkeys bypass modal suppression at the same escape-hatch
      // tier as Ctrl+C.
      if (event is KeyEvent && tryConsumeDebugKey(debugController, event)) {
        scheduleFrame('debug-key');
        return;
      }
      if (event is TextInputEvent &&
          tryConsumeDebugText(debugController, event)) {
        scheduleFrame('debug-key');
        return;
      }
      // A correlated batch's text half takes the same debug-hotkey route the
      // bare TextInputEvent shape did for identical wire input.
      if (event is InputBatch &&
          event.committedText != null &&
          tryConsumeDebugText(
            debugController,
            TextInputEvent(event.committedText!),
          )) {
        scheduleFrame('debug-key');
        return;
      }

      KeyEventResult dispatchResult = KeyEventResult.ignored;
      if (event is KeyEvent ||
          event is TextInputEvent ||
          event is TextCompositionEvent ||
          event is PasteEvent ||
          event is MouseEvent ||
          event is InputBatch) {
        // Bare pointer motion is not input the user stops to stop an error:
        // counting it would keep a genuine error loop alive while the mouse
        // moves.
        if (!(event is MouseEvent &&
            (event.kind == MouseEventKind.moved ||
                event.kind == MouseEventKind.leave ||
                event.kind == MouseEventKind.cancel))) {
          errorReporter.noteInput();
        }
        try {
          dispatchResult = dispatcher.dispatch(event);
        } catch (error, stack) {
          // A throwing handler is reported (the error overlay paints it) but
          // must not take the framework's own quit guard below down with it:
          // the result stays `ignored`, so an unhandled Ctrl+C still exits.
          // Before this, a handler that threw on every press — a stale
          // selection's copy, any app binding — left the app unquittable
          // from the keyboard.
          errorReporter.report(error, stack);
        }
        semanticsPipeline?.markSemanticsDirty();
      }

      // Ctrl+C exits only when the app did not handle it first. Structured
      // browser sessions are exempt because browser Cmd+C maps to Ctrl+C.
      if (event is KeyEvent &&
          // Once per physical press, on the press itself. A release always
          // dispatches as `ignored` (the fence), and so does a repeat, which
          // bindings skip: an app that handled the press would otherwise
          // exit on its up, or on its auto-repeat when the key is held
          // (RFC 0020 §6). An unhandled press exits on its down first.
          event.type == KeyEventType.down &&
          event.code.character == 'c' &&
          event.hasCtrl &&
          dispatchResult != KeyEventResult.handled &&
          surfaceSink == null) {
        if (!exit.isCompleted) {
          exit.complete(const AppExit.signal(AppSignal.interrupt));
        }
        return;
      }

      EventResponse? response;
      if (onEvent != null) {
        response = onEvent(event);
        if (response is ExitRequested) {
          if (!exit.isCompleted) exit.complete(const AppExit.requested());
          return;
        }
      }

      if (event is SignalEvent && response is! EventHandled) {
        if (!exit.isCompleted) exit.complete(AppExit.signal(event.signal));
        return;
      }

      scheduleFrame(_frameReasonForEvent(event));
    } catch (error, stack) {
      // A throwing app handler must not kill the input loop.
      errorReporter.report(error, stack);
      scheduleFrame('event-error');
    }
  }

  void handleDriverStreamError(Object error, StackTrace stack) {
    if (disposed) return;
    try {
      errorReporter.report(error, stack);
    } finally {
      if (!exit.isCompleted) exit.complete(const AppExit.requested());
    }
  }

  void handleDriverStreamDone() {
    if (!exit.isCompleted) exit.complete(const AppExit.requested());
  }

  void activateDriverEvents() {
    final overflow = startupEvents.overflowError;
    if (overflow != null) throw overflow;
    // Keep startup mode active while draining. A synchronous custom stream can
    // emit recursively from an app callback; those events append behind the
    // already-buffered input and preserve source order.
    for (final event in startupEvents.drain()) {
      handleDriverEvent(event);
    }
    final replayOverflow = startupEvents.overflowError;
    if (replayOverflow != null) throw replayOverflow;
    driverEventsReady = true;
    final streamError = driverEventStreamError;
    if (streamError != null && !exit.isCompleted) {
      handleDriverStreamError(
        streamError,
        driverEventStreamStack ?? StackTrace.current,
      );
    } else if (driverEventStreamDone && !exit.isCompleted) {
      handleDriverStreamDone();
    }
  }

  // Single idempotent teardown, driven by either the normal exit path or the
  // zone's uncaught-error handler. Every resource gets its own fault boundary:
  // a failed subscription cancel must not skip State.dispose, and a failed
  // restore must never leave runApp's returned future unresolved.
  Future<void> performCleanup() async {
    disposed = true;
    invocation.closing = true;
    // frameDriver.dispose() stays the first resource action: synchronously,
    // before
    // the first await, a frame microtask scheduled just before cleanup (e.g. by
    // the error reporter's listener) must find the driver disposed, or it
    // re-renders a crashing tree outside the guarded zone.
    //
    final teardownErrors =
        <({String resource, Object error, StackTrace stack})>[];
    final criticalFailures = <String>[];
    void captureSync(String resource, void Function() action) {
      try {
        action();
      } catch (error, stack) {
        teardownErrors.add((resource: resource, error: error, stack: stack));
      }
    }

    Future<bool> captureAsync(
      String resource,
      FutureOr<void> Function() action, {
      Duration timeout = _cleanupResourceTimeout,
      bool terminalCritical = false,
      int? outputDescriptor,
    }) async {
      try {
        Future<void> completeAction() async {
          try {
            await action();
          } catch (error) {
            // A completed write to a vanished terminal cannot outlive this
            // invocation. Pending writes and other cleanup failures still
            // retain admission; a timeout is never treated as completion.
            if (outputDescriptor == null ||
                !isTerminalGoneError(error) ||
                !outputHungUp(outputDescriptor)) {
              rethrow;
            }
          }
        }

        final operation = terminalCritical
            ? invocation.restoreCritical(resource, completeAction)
            : completeAction();
        await operation.timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            '$resource did not finish during teardown',
            timeout,
          ),
        );
        return true;
      } catch (error, stack) {
        teardownErrors.add((resource: resource, error: error, stack: stack));
        if (terminalCritical) criticalFailures.add(resource);
        return false;
      }
    }

    captureSync('frame driver', () => frameDriver?.dispose());
    captureSync('semantics pipeline', () => semanticsPipeline?.dispose());
    captureSync('remote clipboard', () => remoteClipboard?.dispose());

    final activeEventSub = eventSub;
    eventSub = null;
    if (activeEventSub != null) {
      await captureAsync('terminal event subscription', activeEventSub.cancel);
    }

    final activeHotReload = hotReload;
    hotReload = null;
    if (activeHotReload != null) {
      await captureAsync('hot reload controller', activeHotReload.dispose);
    }

    final activeSelfReload = devSelfReload;
    devSelfReload = null;
    if (activeSelfReload != null) {
      await captureAsync('dev self-reload', activeSelfReload.dispose);
    }

    captureSync(
      'debug semantic provider',
      () => debugController.setSemanticTreeProvider(null),
    );
    captureSync(
      'debug hot-restart handler',
      () => debugController.setHotRestartHandler(null),
    );
    captureSync(
      'debug terminal provider',
      () => debugController.setTerminalDiagnosisProvider(null),
    );
    captureSync('debug frame log', () => debugFrameLog?.dispose());
    captureSync('debug invalidations', DebugInvalidations.reset);
    captureSync('input dispatcher', dispatcher.dispose);
    captureSync('runtime error reporter', errorReporter.dispose);
    // Must run even if every prior cleanup resource failed: this is the owner
    // of State.dispose, focus, pointer, binding, and inactive-element teardown.
    captureSync('runtime', runtime.dispose);
    captureSync('debug controller', debugController.dispose);

    captureSync(
      'terminal restore marker',
      () => runtimeMarkers?.mark('terminal.restore.start'),
    );
    Future<void>? terminalRestoration;
    await captureAsync(
      'terminal restore',
      () => terminalRestoration = Future<void>.sync(usedDriver.restore),
      terminalCritical: true,
    );
    // Restore may still be pending after its reporting deadline. Keep capture
    // and replay behind that actual operation so a stray print is not lost or
    // replayed over a child that still owns the terminal.
    Future<void>? captureRestoration;
    final fdCap = fdCapture;
    if (fdCap != null) {
      // Transfer ownership to this tracked operation before its first await.
      // A deadline can fail runApp while this operation still owns capture;
      // only it may stop capture, cancel its subscription, replay, and flush.
      onFdCaptureCleanupOwned?.call();
      Future<void> restoreCapture() async {
        // Restore can still be waiting for an inherited-stdio child after
        // its reporting deadline. Capture's saved terminal handle and its
        // pause/resume hooks must remain alive until that borrow settles.
        // A failed restore still permits independent capture restoration;
        // its own failed critical resource continues to quarantine entry.
        try {
          await terminalRestoration;
        } catch (_) {}

        Object? stopError;
        StackTrace? stopStack;
        try {
          // Stop delivers in-flight lines before closing the streams and
          // the driver's saved terminal handle. Replay must follow it.
          await fdCap.stop();
        } catch (error, stack) {
          stopError = error;
          stopStack = stack;
        }
        final activeFdCaptureSub = fdCaptureSub;
        fdCaptureSub = null;
        if (activeFdCaptureSub != null) {
          await captureAsync(
            'stdio capture subscription',
            activeFdCaptureSub.cancel,
          );
        }
        if (stopError != null) {
          Error.throwWithStackTrace(stopError, stopStack!);
        }

        // The remote mirror already delivered everything to the parent.
        final replayFrom = replayFromLine;
        if (replayFrom != null && !remoteFdMirror && !logBuffer.isEmpty) {
          // Do not enqueue new output to a detached terminal. Existing/
          // pending writes still need to settle or retain admission.
          final stdoutGone = outputHungUp(1);
          final stderrGone = outputHungUp(2);
          (Object, StackTrace)? outputFailure;
          Future<void> deliver(
            FutureOr<void> Function() action, {
            int? descriptor,
          }) async {
            try {
              await action();
            } catch (error, stack) {
              if (descriptor == null ||
                  !isTerminalGoneError(error) ||
                  !outputHungUp(descriptor)) {
                outputFailure ??= (error, stack);
              }
            }
          }

          await deliver(() {
            for (final (index, line) in logBuffer.lines.indexed) {
              if (logBuffer.baseIndex + index < replayFrom) continue;
              switch (line.source) {
                case LogSource.stdout:
                  if (!stdoutGone) stdout.writeln(line.text);
                case LogSource.stderr:
                  if (!stderrGone) stderr.writeln(line.text);
              }
            }
          });
          // Attempt both independent destinations and await their actual
          // completion. The enclosing operation owns the reporting deadline;
          // reporting cannot race a still-pending replay flush.
          await Future.wait([
            if (!stdoutGone) deliver(stdout.flush, descriptor: 1),
            if (!stderrGone) deliver(stderr.flush, descriptor: 2),
          ]);
          final failed = outputFailure;
          if (failed != null) Error.throwWithStackTrace(failed.$1, failed.$2);
        }
      }

      await captureAsync(
        'stdio capture',
        () => captureRestoration = restoreCapture(),
        timeout: _stdioCleanupResourceTimeout,
        terminalCritical: true,
      );
    }

    // Reporting also waits for the actual operations, not their deadline
    // wrappers. During handoff capture is paused, so early diagnostics would
    // overwrite the child's screen. Keep admission through this final flush.
    await captureAsync('teardown reporting', () async {
      Future<void> settled(String resource, Future<void>? operation) async {
        try {
          await operation;
        } catch (error, stack) {
          // The reporting deadline may have elapsed before the real failure
          // arrived. Retain it in the final report alongside the timeout.
          if (!teardownErrors.any(
            (failure) =>
                failure.resource == resource && identical(failure.error, error),
          )) {
            teardownErrors.add((
              resource: resource,
              error: error,
              stack: stack,
            ));
          }
        }
      }

      await settled('terminal restore', terminalRestoration);
      await settled('stdio capture', captureRestoration);
      captureSync(
        'terminal restored marker',
        () => runtimeMarkers?.mark('terminal.restore.end'),
      );
      final diagnosticsGone = outputHungUp(2);
      if (byteTelemetry != null && !diagnosticsGone) {
        captureSync(
          'byte telemetry',
          () => stderr.write(_formatByteTelemetry(byteTelemetry)),
        );
      }
      captureSync(
        'cleanup marker',
        () => runtimeMarkers?.mark('runApp.cleanup.complete'),
      );
      captureSync('runtime marker output', () => runtimeMarkers?.write());

      // Widget/subscription faults remain diagnostic. Failed terminal
      // resources retain their own critical tokens after this report ends.
      for (final failure in teardownErrors) {
        if (diagnosticsGone) break;
        try {
          stderr.writeln(
            'fleury: error during teardown (${failure.resource}): '
            '${failure.error}',
          );
          stderr.writeln(failure.stack);
        } catch (_) {
          // There is no safer reporting channel left.
        }
      }
      if (!diagnosticsGone &&
          (teardownErrors.isNotEmpty || byteTelemetry != null)) {
        await captureAsync(
          'teardown diagnostics flush',
          stderr.flush,
          terminalCritical: true,
          outputDescriptor: 2,
        );
      }
    }, terminalCritical: true);
    final unresolved = invocation._criticalResources.values;
    if (criticalFailures.isNotEmpty || unresolved.isNotEmpty) {
      throw _terminalCleanupError({...criticalFailures, ...unresolved});
    }
  }

  Future<void> cleanup() {
    final active = cleanupFuture;
    if (active != null) return active;
    final completer = Completer<void>();
    cleanupFuture = completer.future;
    performCleanup().then(completer.complete, onError: completer.completeError);
    return completer.future;
  }

  // runZonedGuarded is the safety net. A throw inside an async callback —
  // an event handler, a scheduled frame, a hot-reload hook — escapes the
  // try/finally below entirely and would otherwise leave the terminal in
  // alt-screen / raw mode. Routing every uncaught error (sync or async)
  // here lets us restore the terminal before surfacing the failure.
  void runGuarded() {
    runZonedGuarded(
      () async {
        // History replay and stream callbacks must run in this guarded zone,
        // including failures in onStrayOutput and log-buffer listeners.
        attachFdCapture();
        if (disposed) return;
        // The binding and the error reporter were built before this zone
        // existed. Their timers — animation ticks, the banner's dismiss —
        // run here from now on, so an error in one reaches this guard even
        // when the ticker was started from outside it.
        binding.tickerScheduler.bindZone(Zone.current);
        errorReporter.bindZone(Zone.current);
        // Why the app ended; overwritten by the exit completer's value on
        // the normal path (the fatal-error path bypasses it entirely and
        // completes `done` with the error instead).
        var appExit = const AppExit.requested();
        // A startup failure thrown after mount, captured across the finally
        // so `done` is completed with it only once the terminal is restored.
        Object? startupError;
        StackTrace? startupStack;
        // Subscribe BEFORE enter(): POSIX starts stdin/probe handling during
        // enter, and TerminalDriver.events is broadcast, so attaching later
        // silently drops ready pipe input, fast keystrokes, and enter-time
        // bytes. Events replay only after mount so autofocus/claimants exist.
        eventSub = usedDriver.events.listen(
          (event) {
            if (driverEventsReady) {
              handleDriverEvent(event);
            } else if (driverEventStreamError == null &&
                !driverEventStreamDone) {
              // The live path completes [exit] on the first stream error/EOF,
              // so later data is ignored there. Preserve that ordering while
              // startup is buffered instead of replaying post-terminal data.
              startupEvents.add(event);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (driverEventsReady) {
              handleDriverStreamError(error, stack);
            } else {
              driverEventStreamError ??= error;
              driverEventStreamStack ??= stack;
            }
          },
          onDone: () {
            if (driverEventsReady) {
              handleDriverStreamDone();
            } else {
              driverEventStreamDone = true;
            }
          },
        );
        runtimeMarkers?.mark('terminal.enter.start');
        sessionProfile = await invocation.startResource(
          'terminal startup',
          () => usedDriver.enter(mode),
        );
        if (disposed) return;
        runtimeMarkers?.mark('terminal.enter.end');
        final startupOverflow = startupEvents.overflowError;
        if (startupOverflow != null) throw startupOverflow;
        dispatcher.updateKeyboardCapabilities(sessionProfile.keyboard);
        keyboardNotifier.notifyCapabilitiesChanged();
        switch (sessionProfile.presentation) {
          case final AnsiTerminalPresentation ansi:
            ansiPresentation = ansi;
            if (ansi.pointerShapes) {
              runtime.pointerRouter.onCursorChanged = (cursor) {
                if (!disposed) usedDriver.write(pointerShapeSequence(cursor));
              };
            }
            final capabilities = ansi.capabilities;
            renderer = AnsiRenderer(
              colorMode: capabilities.colorMode,
              synchronizedOutput: ansi.synchronizedOutput,
              // RFC 0019 decision 9: the pin keys off the RESOLVED ambiguous
              // axis — the same policy layout measures with — not a passively
              // defaulted capability field.
              ambiguousCharsAreWide: capabilities.textPolicy.pinsAmbiguousWidth,
              hyperlinks: capabilities.hyperlinks,
            );
          case final StructuredTerminalPresentation structured:
            surfaceSink = structured.sink;
        }
        final negotiatedSink = surfaceSink;
        if (negotiatedSink != null) {
          // Report a link fault WITHOUT ever throwing back into the serialize
          // link. errorReporter.report → notify() can throw (a
          // throwing listener); if that escaped the link it would reject the
          // tail future and skip every later queued action — the exact wedge
          // the per-link catch exists to prevent. Degrade to a no-op instead:
          // keeping the queue alive wins over this one log line.
          void reportSemanticActionFault(Object error, StackTrace stack) {
            try {
              errorReporter.report(error, stack);
            } catch (_) {
              // The reporter itself faulted; swallow so the tail still resolves.
            }
          }

          // Per-connection serialize queue for inbound semantic actions.
          // Deliberately DIVERGES from fleury_mcp's `_serializeMutation` (do
          // NOT converge them): that path carries revision/settle bookkeeping,
          // rate limiting, a synchronous idle fast-path, and returns T to the
          // caller; this raw-wire path is fire-and-forget void with no result
          // plumbing. Both must stay serialized, but under different contracts
          // — a change to one shouldn't silently retrofit the other. One
          // session per runApp, so this local is per-connection and a fresh
          // runApp starts with an empty tail; it lives beside the sink /
          // errorReporter the chained link uses.
          var semanticActionTail = Future<void>.value();
          var pendingSemanticActions = 0;
          var semanticActionOverflowReported = false;
          // The peer can activate a node in its accessible DOM; invoke the
          // action against the live tree and re-render, completing the
          // semantics round trip (presentSemantics ships the tree out, this
          // brings activations back). Mirrors the in-browser host.
          negotiatedSink.onDeveloperWarning = (warning) =>
              errorReporter.report(warning, StackTrace.current);
          negotiatedSink.onSemanticAction = (id, action, value, {targetToken}) {
            if (pendingSemanticActions >= _maxPendingRemoteSemanticActions) {
              // Queue one marker behind every earlier admitted action. RESULT
              // has no sequence number, so sending this immediately would put
              // a rejection ahead of results for indistinguishable earlier
              // id/action requests. Keep the epoch set until the marker itself
              // runs: there can be at most 64 action closures plus one marker,
              // even if the source keeps flooding while the queue drains.
              if (!semanticActionOverflowReported) {
                semanticActionOverflowReported = true;
                semanticActionTail = semanticActionTail.then((_) {
                  try {
                    negotiatedSink.presentSemanticActionResult(
                      id,
                      action,
                      SemanticActionInvocationStatus.failed,
                    );
                  } catch (error, stackTrace) {
                    reportSemanticActionFault(error, stackTrace);
                  } finally {
                    semanticActionOverflowReported = false;
                  }
                });
              }
              return;
            }
            pendingSemanticActions++;
            // Serialize on a per-connection tail: an agent that sends
            // setValue(field) then activate(submit) back-to-back needs the
            // activate to snapshot the tree the setValue mutated, and the
            // RESULT frames to return in submission order. Chaining each
            // action onto the tail runs N+1's snapshot + invocation after N
            // settles — but N is waited for only so long: a handler that
            // presents a dialog and awaits its answer settles only when a
            // LATER action answers it, which must not queue behind it. Past
            // the hold the queue moves on, and N's RESULT still goes out when
            // N settles. The closure still returns immediately after
            // appending — it never awaits the tail — so frame dispatch is not
            // blocked.
            semanticActionTail = semanticActionTail.then<void>((_) {
              var settling = false;
              try {
                // Read the LIVE root HERE, not at arrival: the link runs
                // arbitrarily later — behind prior queued actions and across
                // their awaits — by which point a rebuild may have replaced
                // the root Element (updateRoot's unmount+mount branch) or the
                // session may be tearing down. An arrival-captured root would
                // snapshot a detached tree. Mirrors the semantics pipeline's
                // `readRoot: () => frameDriver?.rootElement`.
                final root = frameDriver?.rootElement;
                // No live root (torn down, or an action that raced ahead of
                // mount): skip rather than invoke against an absent/detached
                // tree. A dead session can't honor the action.
                if (root == null) return null;
                // Flush pending semantics first so the peer's view is current
                // when the action's result lands — the embed contract, now on
                // both paths. Deferred into the link (not fired at arrival) so
                // it reflects the tree AFTER the prior action mutated it.
                semanticsPipeline?.flushPendingNow('semantic-action');
                final liveTree = SemanticTree.fromElement(root);
                if (isPositionalSemanticId(id.value)) {
                  final liveNode = liveTree.nodeById(id);
                  if (targetToken == null ||
                      liveNode?.actionTargetToken != targetToken) {
                    negotiatedSink.presentSemanticActionResult(
                      id,
                      action,
                      SemanticActionInvocationStatus.notFound,
                    );
                    return null;
                  }
                }
                // An agent's or assistive technology's action is input too:
                // errors it causes stop when it stops.
                errorReporter.noteInput();
                // Runs the handler's synchronous part now; the rest settles
                // later, and the next action need not wait for it.
                final invocation = invokeSemanticActionFromElement(
                  tree: liveTree,
                  id: id,
                  action: action,
                  value: value,
                );
                settling = true;
                final settled = invocation
                    .then((result) {
                      // Ship the outcome back so the peer (agent bridge, AT
                      // mirror) gets a real status instead of guessing from
                      // tree diffs — and surface a throwing onAction handler
                      // like any other app error rather than swallowing it.
                      negotiatedSink.presentSemanticActionResult(
                        id,
                        action,
                        result.status,
                      );
                      if (result.status ==
                          SemanticActionInvocationStatus.failed) {
                        reportSemanticActionFault(
                          result.error ??
                              StateError(
                                'semantic action ${action.name} failed',
                              ),
                          result.stackTrace ?? StackTrace.current,
                        );
                      }
                    })
                    .catchError((Object error, StackTrace stackTrace) {
                      // A throwing sink: the handler's fault is already in
                      // its result.
                      reportSemanticActionFault(error, stackTrace);
                    })
                    .whenComplete(() => pendingSemanticActions--);
                final released = Completer<void>();
                final hold = Timer(_semanticActionQueueHold, () {
                  if (!released.isCompleted) released.complete();
                });
                unawaited(
                  settled.whenComplete(() {
                    hold.cancel();
                    if (!released.isCompleted) released.complete();
                  }),
                );
                return released.future;
              } catch (error, stackTrace) {
                // Catch INSIDE the link so a fault never rejects the tail — a
                // rejected tail future would skip every later action's
                // callback and wedge the queue for the rest of the session.
                // invokeSemanticActionFromElement already turns a throwing
                // handler into a failed RESULT (reported above), so reaching
                // here is an unexpected fault in the flush/snapshot/result
                // path (e.g. a throwing sink). reportSemanticActionFault can
                // NOT throw, so the link's future always RESOLVES.
                reportSemanticActionFault(error, stackTrace);
              } finally {
                // A settling invocation counts itself down when it settles.
                if (!settling) pendingSemanticActions--;
              }
            });
            scheduleFrame('semantic-action:${action.name}');
          };

          // Agent devtools (DT1): the peer pulls recent frame stats / logs /
          // errors. Only when the app opted into debug tooling — otherwise a
          // served production session exposes nothing and the peer's timeout
          // reports it as not debuggable.
          //
          // FLEURY_DEBUG_WIRE=0 is the host's kill switch for THIS wire
          // surface specifically: `fleury serve --spawn` sets it unless the
          // operator passed --debug, so a shared URL can't pull captured
          // logs / frame stats / error stacks out of a JIT demo by default.
          // The in-app debug shell (Ctrl+G) is unaffected.
          // A supervisor that spoke first — `fleury serve` in bridge mode,
          // with a provisional INIT — owns this default: its `--debug`
          // decision travels in that frame, since it cannot set this
          // process's environment. Peers that handshake themselves (`fleury
          // shell`, MCP) leave it null and keep the environment rule.
          final supervisorDebugWire = negotiatedSink is RemoteTerminalDriver
              ? negotiatedSink.supervisorDebugWire
              : null;
          if (debugController.config.enabled &&
              Platform.environment['FLEURY_DEBUG_WIRE'] != '0' &&
              (supervisorDebugWire ?? true)) {
            debugFrameLog = DebugFrameLog();
            negotiatedSink.onDebugRequest = (seq, kind, limit) {
              negotiatedSink.presentDebugResponse(
                seq,
                kind,
                buildDebugResponseJson(
                  kind,
                  limit: limit,
                  maxBytes: maxRemoteDebugResponseJsonLength(kind),
                  frameLog: debugFrameLog,
                  logBuffer: logBuffer,
                  errorReporter: errorReporter,
                ),
              );
            };
          }
        }
        try {
          // Wrap the app in host services only:
          //   - TuiBindingScope so animation (and future cross-cutting
          //     services) can reach the binding via TuiBinding.of(context).
          //   - FocusManagerScope so descendants can reach the manager
          //     via FocusManager.of(context).
          //   - Overlay as the floating-layer primitive (direct OverlayEntry
          //     use: tooltips, toasts).
          // The user's root is otherwise mounted as supplied, with one host
          // addition: a default text selection ([DefaultRootSelection]).
          // Selection is input infrastructure, not app policy — it turns
          // rendered Text into copyable content, which terminal users expect of
          // everything on screen — so it belongs with the clipboard / pointer /
          // focus scopes above, not with FleuryApp's navigation / theme /
          // command scopes. App-authored bindings win over it (deepest-first
          // dispatch); a subtree opts out via SelectionArea.disabled /
          // Text(allowSelect: false). It wraps only the app root, so floating
          // entries (the error overlay below, toasts, menus) keep their own
          // selection context.
          // The root entry is created once; rebuilding `buildRoot` only swaps
          // the ambient MediaQuery data when the terminal resizes, preserving
          // the app subtree (and all its state).
          final rootEntry = OverlayEntry(
            builder: (_) => DefaultRootSelection(child: root),
          );
          // A full-screen layer above the app that shows the uncaught-error
          // banner. As its own entry it never touches the app's layout — the
          // app keeps rendering full-screen underneath. Created once so its
          // subtree state survives resize rebuilds, but mounted lazily:
          // inserted while an error is showing, removed when the reporter
          // empties — each converging a microtask after report/dismiss (the
          // banner's idle SizedBox branch covers the dismiss→unmount gap). A
          // permanently-mounted empty entry would keep the root overlay's
          // adaptive repaint boundaries engaged in every native app — a
          // full-screen cache write + blit per app-dirty frame, for a banner
          // that is almost never showing. The listener is dropped with the
          // reporter's other listeners in cleanup().
          final errorEntry = OverlayEntry(
            builder: (_) => RuntimeErrorOverlay(reporter: errorReporter),
          );
          OverlayMount(
            entry: errorEntry,
            overlay: () => overlayKey.currentState,
            mountWhen: () => errorReporter.current != null,
          ).attachTo(errorReporter);
          // The shared scope stack (see buildTuiRoot). The native host supplies
          // every layer — captured-output buffer and the debug shell included.
          Widget buildRoot() => buildTuiRoot(
            binding: binding,
            size: usedDriver.size,
            // The widget-facing capability vocabulary is backend-neutral; the
            // terminal snapshot is one projection of it. A structured remote
            // driver reports what its PEER declared (a browser: placements,
            // sub-cell pointer).
            capabilities: sessionProfile.surface,
            focusManager: focusManager,
            pointerRouter: pointerRouter,
            clipboard: effectiveClipboard,
            overlayKey: overlayKey,
            overlayEntries: [rootEntry],
            // What lets an app hand the terminal to a child ($EDITOR, a
            // pager) from a default runApp — see TerminalSession. Installed
            // above the Overlay so floating entries share it.
            session: TerminalSession(usedDriver),
            logBuffer: logBuffer,
            debugController: debugController,
            pendingSequenceNotifier: dispatcher.pendingSequenceNotifier,
            keyboardNotifier: keyboardNotifier,
          );
          final activeSurfaceSink = surfaceSink;
          // The clipboard is a host service shared via ClipboardScope in
          // buildRoot. Selection follows the negotiated path: a structured
          // remote session copies to the PEER's clipboard over the wire
          // (the user's machine — a SystemClipboard here would hit the
          // server's); everything else gets the platform clipboard.
          //
          // OSC 52 must go through the DRIVER's write path, not the process
          // stdout: under fd-capture (the POSIX TTY default) fd 1 is
          // redirected into the stray-output pipe, so a bare stdout.write
          // would swallow the escape as a "stray log line" (sanitized on
          // replay) and the copy silently never reaches the terminal — the
          // only clipboard path that works over SSH. The driver holds the
          // saved real-terminal handle.
          effectiveClipboard =
              clipboard ??
              (activeSurfaceSink != null
                  ? (remoteClipboard = RemoteClipboard(activeSurfaceSink))
                  : SystemClipboard(stdoutWrite: usedDriver.write));
          if (activeSurfaceSink != null) {
            semanticsPipeline = FrameSemanticsPipeline(
              presenter: WireSemanticFramePresenter(activeSurfaceSink),
              dirtyTracker: runtime.semanticDirtyTracker,
              readRoot: () => frameDriver?.rootElement,
              // Same-task flush: semantics for a rendered frame reach the
              // peer in the same event-loop task as its plan, so agents
              // still read "semantics for the just-rendered frame".
              flushScheduler: MicrotaskSemanticFlushScheduler(),
            );
          }
          final driver = frameDriver = FrameDriver(
            runtime: runtime,
            frameLoop: frameLoop,
            readViewport: () => FrameViewportSnapshot(usedDriver.size),
            // Frame start, after input drained (events are pumped before
            // frames are produced): publish the keyboard latch so every read
            // within this frame agrees. Live only while the app has no
            // ticker; with one running the ticker clock publishes instead
            // and this is a no-op (RFC 0020 §5.6, wired above).
            onLatchInput: publishFrameLatch,
            // Remote drivers surface their transport's send backlog;
            // the frame program defers production while the peer stalls
            // (structured AND v1-byte modes — dropped bytes are never
            // safe on either).
            flowControl: usedDriver is OutputFlowControl
                ? usedDriver as OutputFlowControl
                : null,
            presenter: activeSurfaceSink != null
                // Structured serve path: hand the frame's buffers and
                // damage plan to the driver instead of emitting ANSI.
                ? WireFramePresenter(
                    activeSurfaceSink,
                    readCaret: () => focusManager.focusedNode?.caretRect,
                  )
                : AnsiFramePresenter(
                    sink: sink,
                    renderer: renderer,
                    debug: debugController,
                    readTarget: usedDriver is PosixTerminalDriver
                        ? () => usedDriver.renderTarget
                        : null,
                    onCursorPositioned: usedDriver is PosixTerminalDriver
                        ? usedDriver.recordInlineCursor
                        : null,
                    readCaret: () => focusManager.focusedNode?.caretRect,
                    // Native graphics protocol, when the terminal has one:
                    // widgets place neutral image placements; the encoder
                    // emits Kitty/iTerm2/Sixel escapes after each diff.
                    imageEncoder:
                        ansiPresentation!.capabilities.imageProtocol ==
                            ImageProtocol.halfBlock
                        ? null
                        : TerminalImageEncoder(
                            protocol:
                                ansiPresentation!.capabilities.imageProtocol,
                            tmuxPassthrough:
                                ansiPresentation!.capabilities.tmuxPassthrough,
                          ),
                  ),
            planner: presentationPlanner,
            onFramePresented: activeSurfaceSink == null
                ? null
                : (frame, plan) =>
                      semanticsPipeline?.onFramePresented(frame, plan),
            // A visually-skipped frame (input changed only semantic state,
            // no repaint) must still flush the owed semantics on serve —
            // otherwise the peer's a11y/agent tree goes stale until an
            // unrelated visual frame. The embed host wires the same hook;
            // this closes the shared-engine parity gap. (While the output
            // is backlogged the producer gate returns before the skip gate,
            // so this stays behind backpressure like frame production.)
            onFrameSkipped: activeSurfaceSink == null
                ? null
                : (reason, size) =>
                      semanticsPipeline?.onFrameSkippedWithPendingWork(),
            isDebugWatching: () =>
                // Capture per-phase timings only when the debug stream has
                // live listeners — when no one's watching this
                // short-circuits to zero per-frame debug cost. NOTE: do NOT
                // gate on `DebugEvents.stream.isBroadcast`.
                debugController.config.enabled && DebugEvents.hasListeners,
            // Backstop errors (escaped every boundary; session continues
            // on a full-screen error frame) surface like other survivable
            // errors: stderr + banner.
            onBackstopError: errorReporter.report,
            markOnce: runtimeMarkers?.markOnce,
            frameInterval: frameInterval,
          );
          driver.mountRoot(buildRoot);
          runtimeMarkers?.mark('root.mounted');
          debugController.setSemanticTreeProvider(() {
            final root = frameDriver?.rootElement;
            return root == null ? null : SemanticTree.fromElement(root);
          });
          scheduleFrame('initial');

          if (enableHotReload) {
            // Reload outcomes (from the dev bootstrap or in-app watcher)
            // surface in the debug shell: Logs on success, Errors on
            // failure — never the terminal, which the frame owns.
            void reportReload(HotReloadReport report) {
              if (disposed) return;
              if (report.success) {
                final n = report.loadedLibraryCount;
                capture.addLine(
                  'Reloaded $n librar${n == 1 ? 'y' : 'ies'} '
                  'in ${report.elapsed.inMilliseconds}ms',
                  LogSource.stderr,
                );
              } else {
                // Teach the recovery at the moment of need: a rejected edit
                // is exactly when hot restart applies. Only when the taught
                // keys can actually work: a supervisor session AND the debug
                // shell enabled (Ctrl+G is dead when the shell is off).
                final restartHint =
                    DevBootstrap.isSupervisedChild &&
                        debugController.config.enabled
                    ? ' — hot restart applies it: Ctrl+G, then F5 (drops '
                          'state)'
                    : '';
                errorReporter.report(
                  StateError(
                    'hot reload failed: '
                    '${report.message ?? 'rejected by the VM'}$restartHint',
                  ),
                  StackTrace.current,
                );
              }
            }

            // Surface the shell's F5 hot-restart action when a supervisor is
            // listening (plain `dart run` sessions). Gated like the hint —
            // and on a real (non-injected) driver, so runApp-driven tests
            // never grow the affordance from an inherited environment.
            if (!driverInjected &&
                DevBootstrap.isSupervisedChild &&
                debugController.config.enabled) {
              debugController.setHotRestartHandler(
                DevBootstrap.requestRestartFromApp,
              );
            }

            hotReload = await invocation.startResource(
              'hot reload startup',
              () async {
                final controller = await HotReloadController.attach(
                  onReassemble: () {
                    if (disposed) return;
                    runtime.reassembleApplication();
                    // Fire scheduler-level reassemble after the element-tree
                    // walk so Animations + FrameTickers reset to a
                    // known state under the freshly-reloaded code. Order
                    // matters: tree reassembly may dispose old controllers
                    // (which unregister themselves), so reset only the
                    // controllers that survive.
                    binding.tickerScheduler.reassemble();
                    scheduleFrame('hot-reload');
                  },
                  onReloadReport: reportReload,
                  // The dev supervisor's hot restart: tear this session down
                  // through the normal exit path (terminal restore, capture
                  // stop, socket close); the supervisor respawns the process
                  // fresh.
                  onShutdownRequested: exitApp,
                );
                if (disposed) {
                  await controller.dispose();
                  return null;
                }
                return controller;
              },
            );
            if (disposed) return;
            // Save-to-reload for supervised (serve/remote) sessions, where
            // the bootstrap must not run but the developer is still
            // iterating — reloads flow straight to the browser preview.
            // (Sync pre-gate: ineligible runs must not add an await here.)
            if (InAppDevReload.shouldConsider(
              enableHotReload: enableHotReload,
            )) {
              devSelfReload = await invocation.startResource(
                'dev reload startup',
                () async {
                  final controller = await InAppDevReload.maybeStart(
                    onReport: reportReload,
                  );
                  if (disposed) {
                    await controller?.dispose();
                    return null;
                  }
                  return controller;
                },
              );
              if (disposed) return;
            }
          }

          activateDriverEvents();

          appExit = await exit.future;
        } catch (error, stack) {
          // A throw during startup (most reachably a post-mount
          // startup-input overflow from activateDriverEvents, thrown after
          // enter() returned) must fail runApp's future LOUDLY, not leave it
          // forever unresolved with the terminal already restored. Record it
          // and complete `done` only after cleanup() below has torn down —
          // so the caller never sees the error before the terminal is safe.
          startupError = error;
          startupStack = stack;
        } finally {
          try {
            await cleanup();
          } catch (error, stack) {
            startupError = error;
            startupStack = stack;
          }
        }
        if (startupError != null) {
          if (!done.isCompleted) {
            done.completeError(startupError, startupStack!);
          }
        } else if (!done.isCompleted) {
          done.complete(appExit);
        }
      },
      (error, stack) {
        // Report and keep running (Flutter's posture): an uncaught handler or
        // async error surfaces on screen instead of tearing the session down.
        // report() logs it and repaints the banner. Two cases stay fatal — an
        // error before the app has mounted (nothing to recover into), and a
        // storm of errors every frame (an unrecoverable loop) — both restore
        // the terminal and fail the run.
        var reportingFailed = false;
        try {
          errorReporter.report(error, stack);
        } catch (reportError, reportStack) {
          reportingFailed = true;
          try {
            stderr.writeln(
              'fleury: error reporter failed while handling a fatal runtime '
              'error: $reportError',
            );
            stderr.writeln(reportStack);
          } catch (_) {
            // Cleanup remains the only safe response even if stderr is broken.
          }
        }
        // Stay fatal (restore the terminal, fail the run) only for the
        // cases that genuinely can't continue: the driver declared the
        // session unrecoverable (a backstop storm — render crashes are
        // otherwise contained per-boundary or absorbed by the backstop),
        // an error before the app mounted (nothing to recover into), or
        // a storm of errors every frame. Everything else is reported and
        // survived.
        // Once the reporter is disposed, report() above was a silent no-op and
        // the fatal gate below would misread the still non-null rootElement as
        // survivable. Surface the error on stderr — the terminal is already
        // restored — so a late async throw (a Timer or socket callback
        // outliving the session, an error during shutdown) isn't discarded with
        // zero trace. Keyed on the reporter's own disposed state, not merely on
        // teardown having begun: there is a brief window where cleanup has
        // started but the reporter is still live and DID log the error, and
        // stderr-ing here too would double-report it.
        final teardownStarted = cleanupFuture != null;
        if (errorReporter.isDisposed && !reportingFailed) {
          try {
            stderr.writeln('fleury: uncaught error after teardown: $error');
            stderr.writeln(stack);
          } catch (_) {
            // stderr may itself be broken; nothing more we can do.
          }
        }
        final driver = frameDriver;
        if (reportingFailed ||
            teardownStarted ||
            (driver?.renderUnrecoverable ?? false) ||
            driver?.rootElement == null ||
            errorReporter.isStorming) {
          cleanup().then(
            (_) {
              if (!done.isCompleted) done.completeError(error, stack);
            },
            onError: (Object cleanupError, StackTrace cleanupStack) {
              if (!done.isCompleted) {
                done.completeError(cleanupError, cleanupStack);
              }
            },
          );
        }
      },
    );
  }

  runGuarded();

  return done.future;
}

String _frameReasonForEvent(TuiEvent event) {
  return switch (event) {
    ResizeEvent() => 'resize',
    TerminalFocusEvent() => 'terminal-focus',
    KeyEvent(:final code) => 'key:${code.special?.name ?? code.character!}',
    InputBatch(:final key) =>
      key != null
          ? 'key:${key.code.special?.name ?? key.code.character!}'
          : 'text-input',
    TextInputEvent() => 'text-input',
    TextCompositionEvent(:final kind) => 'text-composition:${kind.name}',
    PasteEvent() => 'paste',
    MouseEvent() => 'mouse',
    // Reached only for a CLAIMED signal (unclaimed ones exit before
    // scheduling): the app's shutdown likely set state worth painting
    // ("disconnecting…").
    SignalEvent(:final signal) => 'signal:${signal.name}',
  };
}

/// Tees every emitted byte to a file (diagnostic; `FLEURY_ANSI_CAPTURE`).
/// Writes synchronously so the capture survives a Ctrl-C mid-session.
class _CapturingAnsiSink implements AnsiSink {
  _CapturingAnsiSink(this._inner, this._file);

  /// Wraps [inner] to also tee to [path]. If the file can't be opened (bad
  /// path, no permission) the capture is skipped with a warning rather than
  /// crashing the app over a mistyped diagnostic env var — same best-effort
  /// policy as [_RuntimeMarkerRecorder].
  static AnsiSink wrap(AnsiSink inner, String path) {
    try {
      return _CapturingAnsiSink(
        inner,
        File(path).openSync(mode: FileMode.write),
      );
    } on Object catch (error) {
      stderr.writeln(
        '[fleury] FLEURY_ANSI_CAPTURE: cannot open "$path": '
        '$error — capture disabled.',
      );
      return inner;
    }
  }

  final AnsiSink _inner;
  final RandomAccessFile _file;

  @override
  void write(String data) {
    _inner.write(data);
    try {
      _file.writeStringSync(data);
    } catch (_) {
      // Best-effort capture; never break rendering over a diagnostic write.
    }
  }

  @override
  Future<void> flush() async {
    await _inner.flush();
    try {
      _file.flushSync();
    } catch (_) {}
  }
}

class _DriverSink implements AnsiSink {
  _DriverSink(this._driver, this._runtimeMarkers);
  final TerminalDriver _driver;
  final _RuntimeMarkerRecorder? _runtimeMarkers;

  @override
  void write(String data) {
    if (data.isNotEmpty) {
      _runtimeMarkers?.markOnce('first.output.write');
    }
    _driver.write(data);
  }

  @override
  Future<void> flush() async {}
}

final class _RuntimeMarkerRecorder {
  _RuntimeMarkerRecorder._(this._path) : _watch = Stopwatch()..start();

  static _RuntimeMarkerRecorder? fromEnvironment() {
    final path = Platform.environment['FLEURY_RUNTIME_MARKERS']?.trim();
    if (path == null || path.isEmpty) return null;
    return _RuntimeMarkerRecorder._(path);
  }

  final String _path;
  final Stopwatch _watch;
  final List<Map<String, Object?>> _markers = <Map<String, Object?>>[];
  final Set<String> _seenOnce = <String>{};

  void mark(String label) {
    final now = DateTime.now().toUtc();
    _markers.add(<String, Object?>{
      'label': label,
      'epochMicros': now.microsecondsSinceEpoch,
      'elapsedMicros': _watch.elapsedMicroseconds,
    });
  }

  void markOnce(String label) {
    if (_seenOnce.add(label)) mark(label);
  }

  void write() {
    try {
      final output = File(_path);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'schemaVersion': 1,
          'kind': 'fleuryRuntimeMarkers',
          'markers': _markers,
        }),
      );
    } on Object catch (error) {
      stderr.writeln('[fleury runtime markers] failed to write $_path: $error');
    }
  }
}

/// Renders a one-shot byte-telemetry summary for the FLEURY_BYTE_TELEMETRY
/// path: aggregate byte budget by category plus estimated per-frame wire time
/// across transport profiles. Real-terminal capture is the point — run a
/// Fleury app with the env var set on the target terminal/SSH session.
String _formatByteTelemetry(CountingAnsiSink sink) {
  final t = sink.total;
  final frames = sink.frameCount;
  final avg = frames == 0 ? 0 : (t.total / frames).round();
  String pct(int part) =>
      t.total == 0 ? '0%' : '${(100 * part / t.total).round()}%';
  final latency = TransportProfile.defaults
      .map((p) => '${p.name} ${p.frameMs(avg).toStringAsFixed(1)}ms')
      .join('  ');
  return '\n[fleury byte telemetry] frames=$frames '
      'totalBytes=${t.total} avg=$avg B/frame\n'
      '  content ${pct(t.content)}  sgr ${pct(t.sgr)}  '
      'cursor ${pct(t.cursor)}  sync ${pct(t.sync)}\n'
      '  est avg-frame latency: $latency\n';
}

/// Picks the right default driver when the caller didn't pass one.
///
/// Detection order:
///   1. `$FLEURY_HANDLE` env var — `fleury serve --spawn` set this for a
///      subprocess it just started, pointing at a session-specific
///      socket. Each browser session gets its own isolated app
///      process this way.
///   2. `.fleury/handle` in CWD or an ancestor within the nearest Dart package
///      — `fleury shell` or single-session `fleury serve` is running locally;
///      connect to it so the TUI renders into the shell's terminal or browser,
///      leaving the IDE's stdout free for the debugger.
///   3. Fall back to the native platform driver (the normal path).
///
/// A handle that exists but points to a dead socket falls through to
/// the native platform driver with a one-line stderr warning rather than
/// hanging — the shell may have crashed and the user's app shouldn't
/// be held hostage.
Future<TerminalDriver> _resolveDefaultDriver({
  Future<Stdout?> Function()? nativeStdout,
  Future<void> Function()? remoteCapture,
}) async {
  // Per-session env var wins outright — when `fleury serve --spawn`
  // started us, the env var is *intentional* and a missing or stale
  // socket here is a real bug, not a fallback case.
  final envHandle = Platform.environment['FLEURY_HANDLE'];
  if (envHandle != null && envHandle.isNotEmpty) {
    try {
      final transport = await UnixSocketFrameTransport.connect(envHandle);
      await remoteCapture?.call();
      return RemoteTerminalDriver(transport);
    } on Object catch (e) {
      throw StateError(
        'FLEURY_HANDLE=$envHandle is set but the socket is unreachable: $e. '
        'This usually means `fleury serve --spawn` failed to set up the '
        'session socket before launching us.',
      );
    }
  }

  final handle = findImplicitFleuryHandle();
  if (handle == null) {
    return createNativeTerminalDriver(
      stdoutOverride: await nativeStdout?.call(),
    );
  }
  final path = (await handle.readAsString()).trim();
  if (path.isEmpty) {
    return createNativeTerminalDriver(
      stdoutOverride: await nativeStdout?.call(),
    );
  }
  try {
    final transport = await UnixSocketFrameTransport.connect(path);
    await remoteCapture?.call();
    // The .fleury/handle path is a user-launched app (`fleury shell`,
    // single-session serve), not a serve-supervised spawn — keep the bounded
    // INIT fuse here regardless of an inherited FLEURY_REMOTE_WAIT, so it
    // can't be tricked into waiting forever on a silent peer. Only the
    // FLEURY_HANDLE spawn path above opts into the supervised unbounded wait.
    return RemoteTerminalDriver(transport, superviseHandshakeWait: false);
  } on Object catch (e) {
    // ignore: avoid_print
    print(
      '[fleury] ${handle.path} present but socket unreachable ($e); '
      'falling back to local terminal.',
    );
    return createNativeTerminalDriver(
      stdoutOverride: await nativeStdout?.call(),
    );
  }
}

/// Emits the paint-flash overlay for one frame.
///
/// Two passes, both terminal-level (no buffer mutation):
///   1. UN-tint: any cell in [lastFlashed] that's NOT in [currentDirty]
///      gets re-emitted at its real style — restores the underlying
///      cell so flashes from the previous frame don't linger.
///   2. Tint: every cell in [currentDirty] gets a green-background
///      re-emit on top of the diff's normal output.
///
/// We accept the doubled emit cost on dirty cells; paint-flash is a
/// dev-only mode and the overhead is bounded by the dirty count.
