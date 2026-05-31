import 'dart:async';

import 'package:fleury/fleury_core.dart';

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
  WebTerminalDriver? driver,
}) async {
  final usedDriver = driver ?? WebTerminalDriver();
  final owner = BuildOwner();
  final focusManager = FocusManager();
  final binding = TuiBinding();
  final pointerRouter = PointerRouter();
  Element.errorBuilder ??= (error, stack) => ErrorWidget.builder(error, stack);
  final dispatcher = InputDispatcher(
    focusManager: focusManager,
    pointerRouter: pointerRouter,
  );
  final sink = _DriverSink(usedDriver);
  final renderer = AnsiRenderer(colorMode: usedDriver.capabilities.colorMode);

  Element? root;
  CellBuffer? front;
  CellBuffer? back;
  var requireFullRepaint = true;
  var framePending = false;

  void renderFrame() {
    final r = root;
    if (r == null) return;
    final size = usedDriver.size;
    if (size.isEmpty) return;
    if (front == null || front!.size != size) {
      front = CellBuffer(size);
      back = CellBuffer(size);
      requireFullRepaint = true;
    }
    final next = back!;
    final prev = front!;
    next.clear();
    pointerRouter.beginFrame();
    owner.renderFrame(r, next);
    if (requireFullRepaint) {
      sink.write('\x1B[2J\x1B[H');
      requireFullRepaint = false;
    }
    renderer.renderDiff(prev, next, sink);
    back = prev;
    front = next;
    // Drain post-frame callbacks AFTER bytes are out. Same contract as
    // the native runtime — callers can now read painted geometry, and
    // a callback added from an idle Timer.run gets a frame via
    // `binding.onPostFrameCallback = scheduleFrame` below.
    binding.flushPostFrameCallbacks(binding.tickerScheduler.clock.now);
  }

  void scheduleFrame() {
    if (framePending) return;
    framePending = true;
    scheduleMicrotask(() {
      framePending = false;
      renderFrame();
    });
  }

  owner.onScheduleBuild = scheduleFrame;
  binding.onPostFrameCallback = scheduleFrame;

  await usedDriver.enter(const TerminalMode());
  sink.write('\x1B[?25l'); // hide the terminal's own cursor

  final rootEntry = OverlayEntry(
    builder: (_) => Navigator(home: rootFactory()),
  );
  Widget buildRoot() => TuiBindingScope(
    binding: binding,
    child: MediaQuery(
      data: MediaQueryData(size: usedDriver.size),
      child: FocusManagerScope(
        manager: focusManager,
        child: PointerRouterScope(
          router: pointerRouter,
          child: Overlay(initialEntries: [rootEntry]),
        ),
      ),
    ),
  );

  root = owner.mountRoot(buildRoot());
  scheduleFrame();

  usedDriver.events.listen((event) {
    if (event is ResizeEvent) {
      front = null;
      back = null;
      requireFullRepaint = true;
      final r = root;
      if (r != null) root = owner.updateRoot(r, buildRoot());
    }
    if (event is KeyEvent ||
        event is TextInputEvent ||
        event is PasteEvent ||
        event is MouseEvent) {
      dispatcher.dispatch(event);
    }
    scheduleFrame();
  });
}

class _DriverSink implements AnsiSink {
  _DriverSink(this._driver);
  final WebTerminalDriver _driver;

  @override
  void write(String data) => _driver.write(data);

  @override
  Future<void> flush() async {}
}
