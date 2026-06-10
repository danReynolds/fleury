import 'dart:async';

import 'package:fleury/fleury_host.dart';

import 'browser_frame_flush_scheduler.dart';
import 'web_terminal_driver.dart';

/// Runs an fleury app against a browser terminal — the web counterpart of
/// `runTui`.
///
/// A trimmed loop: no signal handling, raw-mode dance, hot reload, or
/// stray-output capture (none of which exist on the web). It mounts the same
/// scope stack the native runtime uses (binding / media query / focus /
/// pointer / overlay / navigator), renders on demand (first frame, then after
/// events and `setState`), and diffs each frame to the [WebTerminalDriver].
Future<void> runTuiWeb(
  Widget Function() rootFactory, {
  TerminalDriver? driver,
  Duration frameInterval = Duration.zero,
  FrameFlushScheduler? flushScheduler,
}) async {
  final usedDriver = driver ?? WebTerminalDriver();
  final runtime = TuiRuntime();
  final owner = runtime.owner;
  final focusManager = runtime.focusManager;
  final binding = runtime.binding;
  Element.errorBuilder ??= (error, stack) => ErrorWidget.builder(error, stack);
  final dispatcher = InputDispatcher(
    focusManager: focusManager,
    pointerRouter: runtime.pointerRouter,
  );
  final sink = _DriverSink(usedDriver);
  final renderer = AnsiRenderer(colorMode: usedDriver.capabilities.colorMode);

  Element? root;
  final frameLoop = TuiFrameLoop(renderDamage: runtime.renderDamageTracker);
  final pendingEvents = <TuiEvent>[];
  StreamSubscription<TuiEvent>? eventSub;
  var disposed = false;
  late FrameScheduler frameScheduler;
  late Widget Function() buildRoot;

  Future<void> cleanup({bool cancelEventSub = true}) async {
    if (disposed) return;
    disposed = true;
    frameScheduler.dispose();
    dispatcher.dispose();
    runtime.dispose();
    if (cancelEventSub) {
      await eventSub?.cancel();
    }
    eventSub = null;
    await usedDriver.restore();
  }

  void drainPendingEvents() {
    if (pendingEvents.isEmpty) return;
    final events = List<TuiEvent>.of(pendingEvents);
    pendingEvents.clear();
    for (final event in events) {
      if (event is ResizeEvent) {
        frameLoop.resetBuffers();
        final r = root;
        if (r != null) root = runtime.updateRoot(buildRoot());
      }
      if (event is KeyEvent ||
          event is TextInputEvent ||
          event is TextCompositionEvent ||
          event is PasteEvent ||
          event is MouseEvent) {
        dispatcher.dispatch(event);
      }
    }
  }

  void renderFrame(String reason) {
    if (disposed) return;
    drainPendingEvents();
    final r = root;
    if (r == null) return;
    final size = usedDriver.size;
    if (size.isEmpty) return;
    final frame = frameLoop.render(
      size: size,
      paint: (next) {
        runtime.renderFrame(next);
      },
    );
    if (frame == null) return;
    final prev = frame.previous;
    final next = frame.next;
    if (frame.damage.fullRepaint) {
      sink.write('\x1B[2J\x1B[H');
    }
    renderer.renderDiff(prev, next, sink, dirtyBounds: frame.damage.diffBounds);
    frameLoop.commit(frame);
    // Drain post-frame callbacks AFTER bytes are out. Same contract as
    // the native runtime — callers can now read painted geometry, and
    // a callback added from an idle Timer.run gets a frame via
    // `binding.onPostFrameCallback = scheduleFrame` below.
    runtime.flushPostFrameCallbacks();
  }

  frameScheduler = FrameScheduler(
    clock: binding.tickerScheduler.clock,
    minFrameInterval: frameInterval,
    onRender: renderFrame,
    flushScheduler: flushScheduler ?? browserFrameFlushScheduler,
  );

  void scheduleFrame([String reason = 'scheduled']) {
    if (disposed) return;
    frameScheduler.requestFrame(reason);
  }

  owner.onScheduleBuild = () => scheduleFrame('build');
  binding.onPostFrameCallback = () => scheduleFrame('post-frame');

  try {
    await usedDriver.enter(const TerminalMode());
    sink.write('\x1B[?25l'); // hide the terminal's own cursor

    final rootEntry = OverlayEntry(
      builder: (_) => Navigator(home: rootFactory()),
    );
    buildRoot = () => TuiBindingScope(
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
            router: runtime.pointerRouter,
            child: Overlay(initialEntries: [rootEntry]),
          ),
        ),
      ),
    );

    root = runtime.mountRoot(buildRoot());
    scheduleFrame('initial');

    eventSub = usedDriver.events.listen(
      (event) {
        if (disposed) return;
        pendingEvents.add(event);
        scheduleFrame(_frameReasonForEvent(event));
      },
      onDone: () {
        unawaited(cleanup(cancelEventSub: false));
      },
    );
  } catch (_) {
    await cleanup();
    rethrow;
  }
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

class _DriverSink implements AnsiSink {
  _DriverSink(this._driver);
  final TerminalDriver _driver;

  @override
  void write(String data) => _driver.write(data);

  @override
  Future<void> flush() async {}
}
