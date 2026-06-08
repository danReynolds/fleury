// runTui: the application entry point that ties everything together.
//
// Mounts a root widget, owns a terminal driver, runs a frame loop
// (event -> setState -> flushBuild -> renderFrame -> ANSI diff -> stdout),
// attaches hot-reload handlers, and cleans up on exit even when an
// exception bubbles up.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, IOOverrides, Platform, stderr;

import '../debug/debug_events.dart';
import '../debug/debug_invalidation.dart';
import '../debug/debug_shell.dart';
import '../debug/debug_state.dart';
import '../foundation/fleury_error.dart';
import '../foundation/geometry.dart';
import '../remote/remote_driver.dart';
import '../remote/unix_socket_transport.dart';
import '../rendering/ansi_byte_budget.dart';
import '../rendering/ansi_renderer.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/render_layout_stats.dart';
import '../rendering/render_repaint_boundary.dart';
import '../semantics/semantics.dart';
import '../terminal/diagnostics.dart';
import '../terminal/events.dart';
import '../terminal/native_driver.dart';
import '../terminal/terminal_driver.dart';
import '../widgets/focus.dart';
import '../widgets/basic.dart' show ErrorWidget;
import '../widgets/framework.dart';
import '../widgets/key_bindings.dart';
import '../widgets/log_view.dart';
import '../widgets/media_query.dart';
import '../widgets/navigator.dart';
import '../widgets/overlay.dart';
import '../widgets/pointer.dart';
import '../widgets/tui_binding.dart';
import 'frame_scheduler.dart';
import 'hot_reload.dart';
import 'input_dispatcher.dart';
import 'output_capture.dart';

/// A signal returned by an event handler in [runTui] to ask the loop to
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
Future<void> runTui(
  Widget root, {
  TerminalDriver? driver,
  TerminalMode mode = TerminalMode.interactive,
  bool enableHotReload = true,
  bool requireInteractiveTerminal = true,
  void Function(LogLine line)? onStrayOutput,
  bool debugConsole = false,
  KeyChord debugConsoleKey = const KeyChord.key(KeyCode.f12),
  TuiEventHandler? onEvent,
  List<KeyBinding> globalBindings = const [],
  Duration sequenceTimeout = const Duration(milliseconds: 500),
  DebugConfig debug = const DebugConfig(),
  Duration frameInterval = Duration.zero,
}) async {
  final runtimeMarkers = _RuntimeMarkerRecorder.fromEnvironment();
  runtimeMarkers?.mark('runTui.entry');
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
          'runTui needs an interactive terminal, but standard output '
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

  final owner = BuildOwner();
  final focusManager = FocusManager();
  final binding = TuiBinding();
  final pointerRouter = PointerRouter();
  // Install the build-error boundary: a thrown build() renders an error
  // panel for that subtree instead of crashing the app.
  Element.errorBuilder ??= (error, stack) => ErrorWidget.builder(error, stack);
  // Floating LogConsole is migrating into the unified DebugShell —
  // F12 is now a binding on DebugShell that opens the docked panel
  // with the Logs tab focused (rather than a separate Overlay entry).
  // The deprecated `debugConsole` / `debugConsoleKey` parameters are
  // kept for backward compatibility but are no-ops; new code should
  // rely on the always-available `debug` config.
  final overlayKey = GlobalKey<OverlayState>();
  bool maybeToggleDebugConsole(KeyEvent event) => false;

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
  final AnsiSink sink = byteTelemetry ?? driverSink;
  // Downsample colors to whatever the terminal actually supports.
  final renderer = AnsiRenderer(colorMode: usedDriver.capabilities.colorMode);
  Element? rootElement;
  var disposed = false;

  // Double-buffered rendering: front (just-painted, for next-frame
  // diff) and back (cleared and re-painted). The pair is allocated
  // once per terminal size; resize triggers re-allocation and a full
  // repaint via a clear-screen + diff-against-empty pass.
  CellBuffer? frontBuffer;
  CellBuffer? backBuffer;
  var requireFullRepaint = true;
  var frameCounter = 0;
  // Cells we tinted green in the previous frame's paint-flash pass.
  // Empty when paint-flash is off; populated each frame the flash is
  // active. Kept as flat indices (row * cols + col) to avoid per-cell
  // tuple allocation.
  List<int> lastFlashedCells = const [];

  void renderFrame(String reason) {
    if (disposed) {
      // Late frame after cleanup started: drain any callbacks that
      // arrived between `disposed = true` and the scheduled microtask
      // firing so their side effects (a final log line, releasing a
      // captured resource) aren't silently dropped. `binding.dispose()`
      // also drains, but only the FIRST cleanup branch reaches it.
      binding.flushPostFrameCallbacks(binding.tickerScheduler.clock.now);
      return;
    }
    final r = rootElement;
    if (r == null) return;
    final size = usedDriver.size;
    if (size.isEmpty) return;
    runtimeMarkers?.markOnce('first.render.start');

    // (Re)allocate the buffer pool on first frame or after a resize.
    if (frontBuffer == null || frontBuffer!.size != size) {
      frontBuffer = CellBuffer(size);
      backBuffer = CellBuffer(size);
      requireFullRepaint = true;
    }

    // The back buffer becomes "next"; we swap roles after the diff.
    final next = backBuffer!;
    final prev = frontBuffer!;
    next.clear();
    // Pointer regions re-register as they paint, so reset the registry
    // first — only what's on screen this frame is hit-testable.
    pointerRouter.beginFrame();

    // Capture per-phase timings only when the debug stream has live
    // listeners — when no one's watching, we skip the Stopwatch
    // allocation entirely. In production (no DebugPanel subscribed)
    // this short-circuits to zero per-frame debug cost. NOTE: do NOT
    // gate on `DebugEvents.stream.isBroadcast` — that's always true
    // for a broadcast controller and would defeat the optimisation.
    final debugWatching =
        debugController.config.enabled && DebugEvents.hasListeners;
    Duration phaseBuild = Duration.zero;
    Duration phaseLayout = Duration.zero;
    Duration phasePaint = Duration.zero;
    RenderLayoutDebugStats.beginFrame(enabled: debugWatching);
    RepaintBoundaryDebugStats.beginFrame(enabled: debugWatching);
    owner.renderFrame(
      r,
      next,
      onPhaseTiming: debugWatching
          ? (b, l, p) {
              phaseBuild = b;
              phaseLayout = l;
              phasePaint = p;
            }
          : null,
    );
    final layoutStats = RenderLayoutDebugStats.takeFrameStats();
    final repaintBoundaryStats = RepaintBoundaryDebugStats.takeFrameStats();

    if (requireFullRepaint) {
      // Clear screen + home so any stale content (from the alt-screen
      // switch, terminal scrollback, or a previous size) doesn't leak.
      sink.write('\x1B[2J\x1B[H');
      requireFullRepaint = false;
    }
    // renderDiff against an all-empty prev (post-clear) produces the
    // same byte output as renderFull, so the same path handles first
    // frame and resize without a separate branch.
    final diffSw = debugWatching ? (Stopwatch()..start()) : null;
    // Debug mode captures every cell the diff emits. Paint flash uses the same
    // stream to overlay a tint, while captures/panels use it for dirty-shape
    // diagnostics.
    final currentDirty = debugWatching ? <int>[] : null;
    var dirtyCellCount = 0;
    int? dirtyMinCol;
    int? dirtyMinRow;
    int? dirtyMaxCol;
    int? dirtyMaxRow;

    void recordDirtyCell(int col, int row) {
      dirtyCellCount += 1;
      if (dirtyMinCol == null || col < dirtyMinCol!) dirtyMinCol = col;
      if (dirtyMaxCol == null || col > dirtyMaxCol!) dirtyMaxCol = col;
      if (dirtyMinRow == null || row < dirtyMinRow!) dirtyMinRow = row;
      if (dirtyMaxRow == null || row > dirtyMaxRow!) dirtyMaxRow = row;
      currentDirty?.add(row * next.size.cols + col);
    }

    renderer.renderDiff(
      prev,
      next,
      sink,
      onDirtyCell: debugWatching ? recordDirtyCell : null,
    );
    final phaseDiff = diffSw?.elapsed ?? Duration.zero;
    final dirtyBounds = dirtyCellCount == 0
        ? null
        : CellRect.fromLTWH(
            dirtyMinCol!,
            dirtyMinRow!,
            dirtyMaxCol! - dirtyMinCol! + 1,
            dirtyMaxRow! - dirtyMinRow! + 1,
          );
    final dirtySpanStats = debugWatching
        ? DirtySpanFrameStats.fromFlatCells(
            currentDirty ?? const [],
            columns: next.size.cols,
          )
        : DirtySpanFrameStats.empty;

    // Paint-flash overlay: emit ANSI directly to the sink (not into
    // the buffer) so the buffer state stays "the app's truth" and the
    // diff doesn't get confused next frame. Two phases:
    //   1. UN-tint cells from last frame's flash that didn't re-emit
    //      this frame — restores them to their real style.
    //   2. Tint this frame's dirty cells green.
    if (debugController.paintFlash) {
      _emitPaintFlash(
        sink: sink,
        next: next,
        currentDirty: currentDirty ?? const [],
        lastFlashed: lastFlashedCells,
      );
      lastFlashedCells = currentDirty ?? const [];
    } else if (lastFlashedCells.isNotEmpty) {
      // Flash got toggled off — clear any lingering tints from the
      // last on-frame so the terminal doesn't carry stale highlights.
      _emitPaintFlash(
        sink: sink,
        next: next,
        currentDirty: const [],
        lastFlashed: lastFlashedCells,
      );
      lastFlashedCells = const [];
    }
    runtimeMarkers?.markOnce('first.render.end');

    // Roles swap: the just-painted "next" becomes the "front" we'll
    // diff against on the next frame.
    backBuffer = prev;
    frontBuffer = next;

    if (debugWatching) {
      frameCounter++;
      final dirtySources = DebugInvalidations.drain();
      DebugEvents.emitFrame(
        FrameEvent(
          frameNumber: frameCounter,
          reason: reason,
          build: phaseBuild,
          layout: phaseLayout,
          paint: phasePaint,
          diff: phaseDiff,
          dirtyCells: dirtyCellCount,
          dirtyBounds: dirtyBounds,
          dirtySpans: dirtySpanStats,
          dirtySources: dirtySources,
          layoutStats: layoutStats,
          repaintBoundaries: repaintBoundaryStats,
          bufferSize: next.size,
        ),
      );
    } else {
      DebugInvalidations.reset();
    }

    // Drain post-frame callbacks AFTER bytes are out. Callers can now
    // safely read render-object geometry (sizes / offsets reflect the
    // frame the user is seeing). A callback that schedules another frame goes
    // through scheduleFrame; the FrameScheduler has already cleared its pending
    // flag before invoking us, so the new request schedules a fresh flush.
    binding.flushPostFrameCallbacks(binding.tickerScheduler.clock.now);
  }

  // Coalesces frame requests and, when [frameInterval] > 0, caps the render
  // rate so bursts (high-rate streams, rapid setState) collapse to one frame
  // per interval. The default (Duration.zero) is uncapped — identical to the
  // historical microtask-per-turn behaviour.
  final frameScheduler = FrameScheduler(
    clock: binding.tickerScheduler.clock,
    minFrameInterval: frameInterval,
    onRender: renderFrame,
  );
  void scheduleFrame([String reason = 'scheduled']) {
    if (disposed) return;
    frameScheduler.requestFrame(reason);
  }

  owner.onScheduleBuild = () => scheduleFrame('build');
  // Pump the next frame whenever a post-frame callback is enqueued —
  // a Timer.run that adds one while the app is idle would otherwise
  // queue indefinitely (no setState, no event).
  binding.onPostFrameCallback = () => scheduleFrame('post-frame');

  HotReloadController? hotReload;
  StreamSubscription<TuiEvent>? eventSub;
  final exit = Completer<void>();

  final done = Completer<void>();
  var cleanedUp = false;

  // Captures stray output (see below). The buffer powers replay-on-exit; the
  // optional hook lets the caller route lines live (e.g. to a file).
  final logBuffer = LogBuffer();
  final capture = OutputCapture(buffer: logBuffer, onLine: onStrayOutput);

  // Single idempotent teardown, driven by either the normal exit path
  // (the finally below) or the zone's uncaught-error handler.
  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    disposed = true;
    await eventSub?.cancel();
    eventSub = null;
    await hotReload?.dispose();
    hotReload = null;
    debugController.setSemanticTreeProvider(null);
    debugController.setTerminalDiagnosisProvider(null);
    DebugInvalidations.reset();
    // Unmount the root before restoring the terminal so State.dispose
    // runs on every stateful widget — cancelling stream subscriptions
    // they registered in initState and releasing anything else that
    // would otherwise keep the isolate alive after restore().
    rootElement?.unmount();
    frameScheduler.dispose();
    dispatcher.dispose();
    focusManager.dispose();
    binding.dispose();
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
    runtimeMarkers?.mark('runTui.cleanup.complete');
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
          Widget buildRoot() => TuiBindingScope(
            binding: binding,
            child: MediaQuery(
              data: MediaQueryData(
                size: usedDriver.size,
                colorMode: usedDriver.capabilities.colorMode,
                imageProtocol: usedDriver.capabilities.imageProtocol,
                tmuxPassthrough: usedDriver.capabilities.tmuxPassthrough,
              ),
              child: FocusManagerScope(
                manager: focusManager,
                child: PointerRouterScope(
                  router: pointerRouter,
                  // LogBufferScope sits above the Overlay so both the app and
                  // the floating console can read the captured output.
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
                        initialEntries: [rootEntry],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          rootElement = owner.mountRoot(buildRoot());
          runtimeMarkers?.mark('root.mounted');
          debugController.setSemanticTreeProvider(() {
            final root = rootElement;
            return root == null ? null : SemanticTree.fromElement(root);
          });
          scheduleFrame('initial');

          if (enableHotReload) {
            hotReload = await HotReloadController.attach(
              onReassemble: () {
                owner.reassembleApplication();
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
              DebugEvents.emitInput(event);
              if (event is ResizeEvent) {
                // Force buffer-pool reallocation and a full repaint on the
                // next frame; the existing buffers are the wrong size.
                frontBuffer = null;
                backBuffer = null;
                requireFullRepaint = true;
                // Propagate the new size through MediaQuery (layout already
                // re-runs against the new buffer constraints).
                final r = rootElement;
                if (r != null) rootElement = owner.updateRoot(r, buildRoot());
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
              if (event is KeyEvent && maybeToggleDebugConsole(event)) {
                scheduleFrame('debug-console');
                return;
              }

              // Route input through the InputDispatcher: chords walk the focus
              // chain (sequences, KeyBindings, Focus.onKey, globals), text +
              // paste go to the nearest TextInputClaimant, and mouse events go
              // to pointer regions + click-to-focus.
              KeyEventResult dispatchResult = KeyEventResult.ignored;
              if (event is KeyEvent ||
                  event is TextInputEvent ||
                  event is PasteEvent ||
                  event is MouseEvent) {
                dispatchResult = dispatcher.dispatch(event);
              }

              // Ctrl+C exits only when the app did not handle it first.
              // SelectionArea and focused text fields use Ctrl+C for copy and
              // bubble when no selection exists, preserving the escape hatch.
              if (event is KeyEvent &&
                  event.char == 'c' &&
                  event.hasCtrl &&
                  dispatchResult != KeyEventResult.handled) {
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
        cleanup().whenComplete(() {
          if (!done.isCompleted) done.completeError(error, stack);
        });
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
    PasteEvent() => 'paste',
    MouseEvent() => 'mouse',
  };
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
void _emitPaintFlash({
  required AnsiSink sink,
  required CellBuffer next,
  required List<int> currentDirty,
  required List<int> lastFlashed,
}) {
  if (lastFlashed.isEmpty && currentDirty.isEmpty) return;
  final cols = next.size.cols;
  final dirtySet = currentDirty.toSet();
  final buf = StringBuffer();

  // Untint pass — restore underlying cell for previously-flashed cells
  // that the diff didn't re-emit (and so we couldn't re-tint cleanly).
  for (final idx in lastFlashed) {
    if (dirtySet.contains(idx)) continue;
    final col = idx % cols;
    final row = idx ~/ cols;
    if (row >= next.size.rows) continue;
    final cell = next.atColRow(col, row);
    if (cell.role == CellRole.continuation ||
        cell.role == CellRole.protocolCovered ||
        cell.role == CellRole.protocolAnchor) {
      continue;
    }
    buf.write('\x1B[${row + 1};${col + 1}H');
    // Reset to clear any lingering bg, then emit the cell's real style.
    buf.write('\x1B[0m');
    final fg = cell.style.foreground;
    if (fg != null) {
      if (fg is RgbColor) {
        buf.write('\x1B[38;2;${fg.r};${fg.g};${fg.b}m');
      }
    }
    final bg = cell.style.background;
    if (bg != null) {
      if (bg is RgbColor) {
        buf.write('\x1B[48;2;${bg.r};${bg.g};${bg.b}m');
      }
    }
    buf.write(cell.role == CellRole.empty ? ' ' : cell.grapheme!);
  }

  // Tint pass — overlay green-bg on this frame's dirty cells.
  for (final idx in currentDirty) {
    final col = idx % cols;
    final row = idx ~/ cols;
    if (row >= next.size.rows) continue;
    final cell = next.atColRow(col, row);
    if (cell.role == CellRole.continuation ||
        cell.role == CellRole.protocolCovered ||
        cell.role == CellRole.protocolAnchor) {
      continue;
    }
    buf.write('\x1B[${row + 1};${col + 1}H');
    buf.write('\x1B[42m'); // green background
    buf.write(cell.role == CellRole.empty ? ' ' : cell.grapheme!);
  }

  if (buf.isNotEmpty) {
    buf.write('\x1B[0m'); // leave terminal in a known style
    sink.write(buf.toString());
  }
}
