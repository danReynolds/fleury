// runApp: the application entry point that ties everything together.
//
// Mounts a root widget, owns a terminal driver, runs a frame loop
// (event -> setState -> flushBuild -> renderFrame -> ANSI diff -> stdout),
// attaches hot-reload handlers, and cleans up on exit even when an
// exception bubbles up.

import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show File, FileMode, IOOverrides, Platform, RandomAccessFile, stderr;

import '../debug/debug_events.dart';
import '../debug/debug_invalidation.dart';
import '../debug/debug_shell.dart';
import '../debug/debug_state.dart';
import '../foundation/fleury_error.dart';
import '../remote/remote_driver.dart';
import '../remote/unix_socket_transport.dart';
import '../rendering/ansi_byte_budget.dart';
import '../rendering/ansi_renderer.dart';
import 'runtime_error_overlay.dart';
import '../semantics/semantics.dart';
import '../terminal/diagnostics.dart';
import '../input/events.dart';
import '../terminal/native_driver.dart';
import '../terminal/terminal_driver.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/key_bindings.dart';
import '../widgets/output_capture_view.dart';
import '../widgets/media_query.dart';
import '../widgets/navigator.dart';
import '../widgets/overlay.dart';
import '../widgets/pointer.dart';
import '../widgets/tui_binding.dart';
import '../widgets/clipboard_scope.dart';
import 'clipboard.dart';
import '../terminal/ansi_frame_presenter.dart';
import 'frame_driver.dart';
import 'frame_semantics_pipeline.dart';
import 'frame_presentation.dart';
import '../remote/wire_semantic_frame_presenter.dart';
import 'wire_frame_presenter.dart';
import 'hot_reload.dart';
import 'semantic_flush_scheduler.dart';
import 'system_clipboard.dart';
import 'input_dispatcher.dart';
import 'output_capture.dart';
import 'remote_surface_sink.dart';
import 'tui_frame_loop.dart';
import 'tui_runtime.dart';

/// A signal returned by an event handler in [runApp] to ask the loop to
/// exit cleanly.
class ExitRequested {
  const ExitRequested();
}

/// Optional handler called for every input event before the framework
/// re-renders.
///
/// Returning [ExitRequested] terminates the loop (and triggers cleanup).
/// Returning null lets the event through to the rest of the app
/// (typically widgets that subscribed to the driver's event stream
/// directly).
typedef TuiEventHandler = ExitRequested? Function(TuiEvent event);

/// Runs an fleury application.
///
/// Sequence:
///
///   1. Acquire a [TerminalDriver] (defaults to the native platform driver).
///   2. Enter [mode] (raw input, alt screen, hidden cursor by default).
///   3. Mount [root] under a [BuildOwner]; render the first
///      frame.
///   4. Attach hot-reload handlers (`ext.fleury.reassemble` extension
///      + VM-service `IsolateReload` listener) unless [enableHotReload]
///      is false.
///   5. Listen to driver events; on each event, optionally consult
///      [onEvent]; if it returns [ExitRequested], or the event is
///      Ctrl+C, exit the loop.
///   6. Schedule a render frame after every event and after every
///      `setState` (via [BuildOwner.onScheduleBuild]).
///   7. On exit (normal or exceptional): cancel subscriptions, dispose
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
Future<void> runApp(
  Widget root, {
  TerminalDriver? driver,
  TerminalMode mode = TerminalMode.interactive,
  bool enableHotReload = true,
  bool requireInteractiveTerminal = true,
  void Function(LogLine line)? onStrayOutput,
  TuiEventHandler? onEvent,
  Clipboard? clipboard,
  List<KeyBinding> globalBindings = const [],
  Duration sequenceTimeout = const Duration(milliseconds: 500),
  DebugConfig debug = const DebugConfig(),
  Duration frameInterval = Duration.zero,
}) async {
  final runtimeMarkers = _RuntimeMarkerRecorder.fromEnvironment();
  runtimeMarkers?.mark('runApp.entry');
  final usedDriver = driver ?? await _resolveDefaultDriver();
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

  // The clipboard is a host service: the native host owns a SystemClipboard
  // (platform tools + OSC 52) unless the app supplied its own, and shares it
  // with widgets via ClipboardScope in buildRoot.
  final effectiveClipboard = clipboard ?? SystemClipboard();

  final runtime = TuiRuntime();
  final focusManager = runtime.focusManager;
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
    globalBindings: globalBindings,
  );
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
  // `FLEURY_SYNC_OUTPUT=0` drops the DEC-2026 synchronized-update wrapper around
  // each frame. The wrapper is correct per spec (and verified by the renderer's
  // own equivalence tests), but a terminal whose 2026 implementation drops or
  // mis-applies updates under rapid frames (e.g. fast scrolling) can desync from
  // the renderer's model and show persistent stale cells; this is the escape
  // hatch to confirm/avoid that without touching the diff.
  final renderer = AnsiRenderer(
    colorMode: usedDriver.capabilities.colorMode,
    synchronizedOutput: Platform.environment['FLEURY_SYNC_OUTPUT'] != '0',
  );
  // When the driver wants structured presentation plans (the serve path,
  // rendering through the fleury web surface instead of a terminal
  // emulator), the render loop hands it plans instead of ANSI bytes. Null
  // for every ordinary terminal session — that path is byte-unchanged.
  // A driver may want structured presentation plans (the serve path) rather
  // than ANSI. Whether it does is negotiated during the handshake, so the
  // decision is finalized after enter() — see [surfaceSink] below.
  final maybeSurfaceSink = usedDriver is RemoteSurfaceSink
      ? usedDriver as RemoteSurfaceSink
      : null;
  RemoteSurfaceSink? surfaceSink;
  const presentationPlanner = FramePresentationPlanner();
  var disposed = false;
  // Constructed after the handshake (the presenter choice depends on the
  // negotiated path) and owns the frame program from then on.
  FrameDriver? frameDriver;
  // The shared semantics engine (structured path only): coverage fallback,
  // retained-leaf updates, and same-task wire flushes.
  FrameSemanticsPipeline? semanticsPipeline;

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
  StreamSubscription<TuiEvent>? eventSub;
  final exit = Completer<void>();

  final done = Completer<void>();
  var cleanedUp = false;

  // Captures stray output (see below). The buffer powers replay-on-exit; the
  // optional hook lets the caller route lines live (e.g. to a file).
  final logBuffer = LogBuffer();
  final capture = OutputCapture(
    buffer: logBuffer,
    onLine: onStrayOutput,
    sanitizeForTerminal: true,
  );

  // Uncaught runtime errors (a throwing event handler, a failed async callback)
  // are reported and surfaced on screen rather than killing the session — see
  // the zone guard and the event-dispatch try/catch below. The listener
  // repaints so the banner appears/auto-dismisses.
  final errorReporter = RuntimeErrorReporter(
    onLog: (message) => stderr.writeln(message),
  )..addListener(() => scheduleFrame('runtime-error'));

  // Single idempotent teardown, driven by either the normal exit path
  // (the finally below) or the zone's uncaught-error handler.
  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    disposed = true;
    // Synchronously, before the first await: a frame microtask scheduled
    // just before cleanup (e.g. by the error reporter's listener) must
    // find the driver disposed, or it re-renders a crashing tree outside
    // the guarded zone.
    frameDriver?.dispose();
    semanticsPipeline?.dispose();
    await eventSub?.cancel();
    eventSub = null;
    await hotReload?.dispose();
    hotReload = null;
    debugController.setSemanticTreeProvider(null);
    debugController.setTerminalDiagnosisProvider(null);
    DebugInvalidations.reset();
    dispatcher.dispose();
    errorReporter.dispose();
    runtime.dispose();
    runtimeMarkers?.mark('terminal.restore.start');
    await usedDriver.restore();
    runtimeMarkers?.mark('terminal.restore.end');

    // The terminal is back on the normal screen now. Unless the caller took
    // the lines live via onStrayOutput, replay everything captured during the
    // session so nothing a stray print() produced is lost.
    capture.flushPartials();
    if (onStrayOutput == null && !logBuffer.isEmpty) {
      for (final line in logBuffer.lines) {
        usedDriver.write('${line.text}\n');
      }
    }

    // Byte telemetry summary, after the terminal is restored.
    if (byteTelemetry != null) {
      stderr.write(_formatByteTelemetry(byteTelemetry));
    }
    runtimeMarkers?.mark('runApp.cleanup.complete');
    runtimeMarkers?.write();
  }

  // Intercept stray output so it can't corrupt the frame. `print()` is
  // caught by the zone spec; direct stdout/stderr writes (loggers, libraries)
  // by the IOOverrides below. The driver holds the real stdout, so the
  // framework's own frames are never captured.
  final captureSpec = ZoneSpecification(
    print: (self, parent, zone, line) =>
        capture.addLine(line, LogSource.stdout),
  );

  // runZonedGuarded is the safety net. A throw inside an async callback —
  // an event handler, a scheduled frame, a hot-reload hook — escapes the
  // try/finally below entirely and would otherwise leave the terminal in
  // alt-screen / raw mode. Routing every uncaught error (sync or async)
  // here lets us restore the terminal before surfacing the failure.
  IOOverrides.runZoned(
    () => runZonedGuarded(
      () async {
        runtimeMarkers?.mark('terminal.enter.start');
        await usedDriver.enter(mode);
        runtimeMarkers?.mark('terminal.enter.end');
        // The handshake has landed, so the driver now knows whether the
        // peer negotiated the structured (plan) path.
        if (maybeSurfaceSink != null &&
            maybeSurfaceSink.wantsPresentationPlans) {
          surfaceSink = maybeSurfaceSink;
          // The peer can activate a node in its accessible DOM; invoke the
          // action against the live tree and re-render, completing the
          // semantics round trip (presentSemantics ships the tree out, this
          // brings activations back). Mirrors the in-browser host.
          maybeSurfaceSink.onSemanticAction = (id, action, value) {
            final root = frameDriver?.rootElement;
            if (root == null) return;
            // Flush pending semantics first so the peer's view is current
            // when the action's result lands — the embed contract, now on
            // both paths.
            semanticsPipeline?.flushPendingNow('semantic-action');
            unawaited(() async {
              final result = await invokeSemanticActionFromElement(
                tree: SemanticTree.fromElement(root),
                id: id,
                action: action,
                value: value,
              );
              // Ship the outcome back so the peer (agent bridge, AT
              // mirror) gets a real status instead of guessing from
              // tree diffs — and surface a throwing onAction handler
              // like any other app error rather than swallowing it.
              maybeSurfaceSink.presentSemanticActionResult(
                id,
                action,
                result.status,
              );
              if (result.status == SemanticActionInvocationStatus.failed) {
                errorReporter.report(
                  result.error ??
                      StateError('semantic action ${action.name} failed'),
                  result.stackTrace ?? StackTrace.current,
                );
              }
            }());
            scheduleFrame('semantic-action:${action.name}');
          };
        }
        try {
          // Wrap the app in:
          //   - TuiBindingScope so animation (and future cross-cutting
          //     services) can reach the binding via TuiBinding.of(context).
          //   - FocusManagerScope so descendants can reach the manager
          //     via Focus.of(context).
          //   - Overlay as the floating-layer primitive (direct OverlayEntry
          //     use: tooltips, toasts).
          //   - Navigator as the app's root route stack, registering as the
          //     global root navigator. The user's widget is its home page, so
          //     `context.push` / `context.present` work app-wide out of the box.
          // The root entry is created once; rebuilding `buildRoot` only swaps
          // the ambient MediaQuery data when the terminal resizes, preserving
          // the Overlay/Navigator subtree (and all its state).
          final rootEntry = OverlayEntry(builder: (_) => Navigator(home: root));
          // A full-screen layer above the app that shows the uncaught-error
          // banner (and nothing otherwise). As its own entry it never touches
          // the app's layout — the app keeps rendering full-screen underneath.
          final errorEntry = OverlayEntry(
            builder: (_) => RuntimeErrorOverlay(reporter: errorReporter),
          );
          Widget buildRoot() => TuiBindingScope(
            binding: binding,
            child: MediaQuery(
              data: MediaQueryData(
                size: usedDriver.size,
                colorMode: usedDriver.capabilities.colorMode,
                glyphTier: usedDriver.capabilities.glyphTier,
                imageProtocol: usedDriver.capabilities.imageProtocol,
                tmuxPassthrough: usedDriver.capabilities.tmuxPassthrough,
              ),
              child: FocusManagerScope(
                manager: focusManager,
                child: PointerRouterScope(
                  router: pointerRouter,
                  // Host services sit above the Overlay so both the app
                  // and the floating console can reach them.
                  child: ClipboardScope(
                    clipboard: effectiveClipboard,
                    child: LogBufferScope(
                      buffer: logBuffer,
                      // DebugShell wraps the Overlay so docking it shrinks
                      // the user's app AND the floating console region —
                      // they share the available cells. When the shell's
                      // mode is off the shell is a pure pass-through and
                      // pays no layout cost.
                      child: DebugShell(
                        controller: debugController,
                        child: Overlay(
                          key: overlayKey,
                          initialEntries: [rootEntry, errorEntry],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final activeSurfaceSink = surfaceSink;
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
            presenter: activeSurfaceSink != null
                // Structured serve path: hand the frame's buffers and
                // damage plan to the driver instead of emitting ANSI.
                ? WireFramePresenter(activeSurfaceSink)
                : AnsiFramePresenter(
                    sink: sink,
                    renderer: renderer,
                    debug: debugController,
                  ),
            planner: presentationPlanner,
            onFramePresented: activeSurfaceSink == null
                ? null
                : (frame, plan) =>
                      semanticsPipeline?.onFramePresented(frame, plan),
            isDebugWatching: () =>
                // Capture per-phase timings only when the debug stream has
                // live listeners — when no one's watching this
                // short-circuits to zero per-frame debug cost. NOTE: do NOT
                // gate on `DebugEvents.stream.isBroadcast`.
                debugController.config.enabled && DebugEvents.hasListeners,
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
            hotReload = await HotReloadController.attach(
              onReassemble: () {
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
            );
          }

          eventSub = usedDriver.events.listen(
            (event) {
              try {
                DebugEvents.emitInput(event);
                if (event is ResizeEvent) {
                  // The driver detects the size change on its next viewport
                  // read and resets the diff base + rebuilds the root; the
                  // scheduled frame below is a full repaint at the new size.
                  DebugEvents.emitTerminalDiagnosis(currentTerminalDiagnosis());
                }

                // Debug-shell hotkeys (Ctrl+G, F11, Esc-in-fullscreen, F12,
                // 'p' when open): bypass the dispatcher so they fire inside
                // an active modal route's `suppressGlobals: true` scope.
                // Same escape-hatch tier as Ctrl+C.
                if (event is KeyEvent &&
                    tryConsumeDebugKey(debugController, event)) {
                  scheduleFrame('debug-key');
                  return;
                }

                // Route input through the InputDispatcher: chords walk the focus
                // chain (sequences, KeyBindings, Focus.onKey, globals), text +
                // paste go to the nearest TextInputClaimant, and mouse events go
                // to pointer regions + click-to-focus.
                KeyEventResult dispatchResult = KeyEventResult.ignored;
                if (event is KeyEvent ||
                    event is TextInputEvent ||
                    event is TextCompositionEvent ||
                    event is PasteEvent ||
                    event is MouseEvent) {
                  dispatchResult = dispatcher.dispatch(event);
                  // Conservative rule (shared with the embed host): a
                  // dispatched event may change state the dirty tracker
                  // can't see; the next flush re-walks and the encoder
                  // dedupes, so an unchanged tree still sends nothing.
                  semanticsPipeline?.markSemanticsDirty();
                }

                // Ctrl+C exits only when the app did not handle it first.
                // SelectionArea and focused text fields use Ctrl+C for copy and
                // bubble when no selection exists, preserving the escape hatch.
                //
                // Structured remote sessions (a browser peer) are exempt: the
                // browser key map folds macOS Cmd into Ctrl, so a reflexive
                // Cmd+C with nothing selected would otherwise kill the served
                // session. A browser user ends the session by closing the tab;
                // the v1 ANSI shell path (a real terminal on the far end)
                // keeps the escape hatch.
                if (event is KeyEvent &&
                    event.char == 'c' &&
                    event.hasCtrl &&
                    dispatchResult != KeyEventResult.handled &&
                    surfaceSink == null) {
                  if (!exit.isCompleted) exit.complete();
                  return;
                }

                if (onEvent != null) {
                  final result = onEvent(event);
                  if (result is ExitRequested) {
                    if (!exit.isCompleted) exit.complete();
                    return;
                  }
                }

                scheduleFrame(_frameReasonForEvent(event));
              } catch (error, stack) {
                // A throwing handler must not kill the input loop: report it
                // (it surfaces on screen) and keep processing events.
                errorReporter.report(error, stack);
                scheduleFrame('event-error');
              }
            },
            onDone: () {
              // The driver's event stream ended — stdin EOF on Posix, or a
              // remote peer (`fleury shell` / `fleury serve`) disconnected.
              // Exit cleanly instead of stranding the app waiting for an
              // input source that will never arrive.
              if (!exit.isCompleted) exit.complete();
            },
          );

          await exit.future;
        } finally {
          await cleanup();
        }
        if (!done.isCompleted) done.complete();
      },
      (error, stack) {
        // Report and keep running (Flutter's posture): an uncaught handler or
        // async error surfaces on screen instead of tearing the session down.
        // report() logs it and repaints the banner. Two cases stay fatal — an
        // error before the app has mounted (nothing to recover into), and a
        // storm of errors every frame (an unrecoverable loop) — both restore
        // the terminal and fail the run.
        errorReporter.report(error, stack);
        // Stay fatal (restore the terminal, fail the run) for the cases that
        // genuinely can't continue: a crash inside the render pipeline
        // (build/layout/paint can't be recovered per-frame), an error before
        // the app mounted (nothing to recover into), or a storm of errors every
        // frame (an unrecoverable loop). Everything else is reported and
        // survived.
        final driver = frameDriver;
        if ((driver?.inFrameRender ?? false) ||
            driver?.rootElement == null ||
            errorReporter.isStorming) {
          driver?.acknowledgeRenderCrash();
          cleanup().whenComplete(() {
            if (!done.isCompleted) done.completeError(error, stack);
          });
        }
      },
      zoneSpecification: captureSpec,
    ),
    stdout: () => capture.sinkFor(LogSource.stdout),
    stderr: () => capture.sinkFor(LogSource.stderr),
  );

  return done.future;
}

String _frameReasonForEvent(TuiEvent event) {
  return switch (event) {
    ResizeEvent() => 'resize',
    KeyEvent(:final keyCode, :final char) =>
      'key:${keyCode?.name ?? char ?? '?'}',
    TextInputEvent() => 'text-input',
    TextCompositionEvent(:final kind) => 'text-composition:${kind.name}',
    PasteEvent() => 'paste',
    MouseEvent() => 'mouse',
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
///   2. `.fleury/handle` in CWD — `fleury shell` or single-session
///      `fleury serve` is running locally; connect to it so the TUI
///      renders into the shell's terminal or browser, leaving the
///      IDE's stdout free for the debugger.
///   3. Fall back to the native platform driver (the normal path).
///
/// A handle that exists but points to a dead socket falls through to
/// the Posix driver with a one-line stderr warning rather than
/// hanging — the shell may have crashed and the user's app shouldn't
/// be held hostage.
Future<TerminalDriver> _resolveDefaultDriver() async {
  // Per-session env var wins outright — when `fleury serve --spawn`
  // started us, the env var is *intentional* and a missing or stale
  // socket here is a real bug, not a fallback case.
  final envHandle = Platform.environment['FLEURY_HANDLE'];
  if (envHandle != null && envHandle.isNotEmpty) {
    try {
      final transport = await UnixSocketFrameTransport.connect(envHandle);
      return RemoteTerminalDriver(transport);
    } on Object catch (e) {
      throw StateError(
        'FLEURY_HANDLE=$envHandle is set but the socket is unreachable: $e. '
        'This usually means `fleury serve --spawn` failed to set up the '
        'session socket before launching us.',
      );
    }
  }

  final handle = _findHandleUpward();
  if (handle == null) return createNativeTerminalDriver();
  final path = (await handle.readAsString()).trim();
  if (path.isEmpty) return createNativeTerminalDriver();
  try {
    final transport = await UnixSocketFrameTransport.connect(path);
    return RemoteTerminalDriver(transport);
  } on Object catch (e) {
    // ignore: avoid_print
    print(
      '[fleury] ${handle.path} present but socket unreachable ($e); '
      'falling back to local terminal.',
    );
    return createNativeTerminalDriver();
  }
}

/// Walks up from CWD looking for `.fleury/handle`, stopping at the
/// filesystem root. Closes the "I ran my app from a subdirectory"
/// footgun — git does the same for `.git/`, npm for `node_modules/`,
/// dart for `pubspec.yaml`. Bounded by tree depth so worst-case is a
/// dozen stat() calls.
File? _findHandleUpward() {
  var dir = File('.').absolute.parent;
  while (true) {
    final candidate = File('${dir.path}/.fleury/handle');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // hit filesystem root
    dir = parent;
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
