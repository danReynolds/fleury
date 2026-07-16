import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// A leaf whose layout throws — stands in for a render/paint bug that
/// surfaces during a scheduled frame (i.e. inside a microtask, where the
/// run loop's try/finally can't see it).
class _BoomWidget extends LeafRenderObjectWidget {
  const _BoomWidget();
  @override
  RenderObject createRenderObject(BuildContext context) => _BoomRender();
}

class _BoomRender extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) =>
      throw StateError('layout-boom');
  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}

/// An app that, once mounted, inserts a full-screen "modal" overlay entry —
/// to verify the debug console opens above overlays added after startup.
class _ModalApp extends StatefulWidget {
  const _ModalApp();
  @override
  State<_ModalApp> createState() => _ModalAppState();
}

class _ModalAppState extends State<_ModalApp> {
  var _inserted = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inserted) return;
    _inserted = true;
    // Fill with '#' (a char that can't appear in the log line we assert on,
    // so the diff renderer can't skip a coincidentally-matching cell).
    Overlay.of(context).insert(
      OverlayEntry(
        builder: (_) => LayoutBuilder(
          builder: (context, c) => Column(
            children: [
              for (var i = 0; i < (c.maxRows ?? 0); i++)
                Text('#' * (c.maxCols ?? 0)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Text('base');
}

class _CounterApp extends StatefulWidget {
  const _CounterApp({super.key});

  @override
  State<_CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<_CounterApp> {
  var _count = 0;

  void increment() {
    setState(() {
      _count += 1;
    });
  }

  @override
  Widget build(BuildContext context) => Text('count:$_count');
}

class _ShrinkTextApp extends StatefulWidget {
  const _ShrinkTextApp({super.key});

  @override
  State<_ShrinkTextApp> createState() => _ShrinkTextAppState();
}

class _ShrinkTextAppState extends State<_ShrinkTextApp> {
  var _short = false;

  void shrink() {
    setState(() {
      _short = true;
    });
  }

  @override
  Widget build(BuildContext context) => Text(_short ? 'hi' : 'hello');
}

class _NavigationProbe extends StatelessWidget {
  const _NavigationProbe({required this.onBuild, required this.child});

  final void Function(BuildContext context) onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return child;
  }
}

/// A stateful widget whose [State.dispose] throws — stands in for a faulty
/// user teardown. runtime.dispose() unmounts the tree and this throw bubbles
/// out of the framework-disposal block; the terminal must still be restored.
class _ThrowingDisposeApp extends StatefulWidget {
  const _ThrowingDisposeApp();
  @override
  State<_ThrowingDisposeApp> createState() => _ThrowingDisposeState();
}

class _ThrowingDisposeState extends State<_ThrowingDisposeApp> {
  @override
  Widget build(BuildContext context) => const Text('x');
  @override
  void dispose() {
    super.dispose();
    // A faulty resource-release after the base dispose — models a user
    // dispose() bug; the throw propagates out of runtime.dispose() during
    // teardown.
    throw StateError('dispose-boom');
  }
}

class _DisposeProbeApp extends StatefulWidget {
  const _DisposeProbeApp({required this.onDispose});

  final void Function() onDispose;

  @override
  State<_DisposeProbeApp> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbeApp> {
  @override
  Widget build(BuildContext context) => const Text('dispose probe');

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

class _CancelFaultStream<T> extends Stream<T> {
  const _CancelFaultStream(
    this.delegate, {
    required this.cancelThrows,
    required this.cancelNeverCompletes,
  });

  final Stream<T> delegate;
  final bool cancelThrows;
  final bool cancelNeverCompletes;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _CancelFaultSubscription<T>(
      delegate.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      cancelThrows: cancelThrows,
      cancelNeverCompletes: cancelNeverCompletes,
    );
  }
}

class _CancelFaultSubscription<T> implements StreamSubscription<T> {
  const _CancelFaultSubscription(
    this.delegate, {
    required this.cancelThrows,
    required this.cancelNeverCompletes,
  });

  final StreamSubscription<T> delegate;
  final bool cancelThrows;
  final bool cancelNeverCompletes;

  @override
  Future<void> cancel() async {
    await delegate.cancel();
    if (cancelThrows) throw StateError('cancel-boom');
    if (cancelNeverCompletes) await Completer<void>().future;
  }

  @override
  void onData(void Function(T data)? handleData) => delegate.onData(handleData);

  @override
  void onError(Function? handleError) => delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => delegate.pause(resumeSignal);

  @override
  void resume() => delegate.resume();

  @override
  bool get isPaused => delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => delegate.asFuture(futureValue);
}

/// A synchronous driver that can exercise events emitted inside enter() and
/// independent teardown failures without depending on OS terminal timing.
class _LifecycleFaultDriver implements TerminalDriver {
  _LifecycleFaultDriver({
    this.enterEvent,
    this.onEnter,
    this.closeDuringEnter = false,
    this.cancelThrows = false,
    this.cancelNeverCompletes = false,
    this.restoreThrows = false,
  }) {
    _events = StreamController<TuiEvent>.broadcast(sync: true);
  }

  final TuiEvent? enterEvent;
  final void Function(StreamController<TuiEvent> events)? onEnter;
  final bool closeDuringEnter;
  final bool cancelThrows;
  final bool cancelNeverCompletes;
  final bool restoreThrows;

  late final StreamController<TuiEvent> _events;
  var _active = false;
  var restoreCallCount = 0;
  final StringBuffer output = StringBuffer();

  @override
  CellSize get size => const CellSize(40, 6);

  @override
  TerminalCapabilities get capabilities =>
      TerminalCapabilities.defaultCapabilities;

  @override
  Stream<TuiEvent> get events => cancelThrows || cancelNeverCompletes
      ? _CancelFaultStream<TuiEvent>(
          _events.stream,
          cancelThrows: cancelThrows,
          cancelNeverCompletes: cancelNeverCompletes,
        )
      : _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => true;

  @override
  RemoteSurfaceSink? get surfaceSink => null;

  @override
  Future<void> enter(TerminalMode mode) async {
    _active = true;
    onEnter?.call(_events);
    final event = enterEvent;
    if (event != null) _events.add(event);
    if (closeDuringEnter) await _events.close();
  }

  void enqueue(TuiEvent event) => _events.add(event);

  @override
  Future<void> restore() async {
    restoreCallCount += 1;
    _active = false;
    if (restoreThrows) throw StateError('restore-boom');
  }

  @override
  void write(String data) => output.write(data);

  Future<void> dispose() async {
    if (!_events.isClosed) {
      try {
        await _events.close();
      } catch (_) {}
    }
  }
}

/// Lets the run loop's async body reach the point where it's listening for
/// events before the test pushes one (a broadcast stream drops events that
/// arrive with no listener).
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('runApp terminal restoration', () {
    test('replays text emitted synchronously during driver.enter', () async {
      final controller = TextEditingController();
      final driver = _LifecycleFaultDriver(
        enterEvent: const TextInputEvent('startup'),
      );
      try {
        final future = runApp(
          TextInput(
            controller: controller,
            autofocus: true,
            enableBlink: false,
          ),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();
        expect(controller.text, 'startup');

        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future.timeout(const Duration(seconds: 2));
      } finally {
        controller.dispose();
        await driver.dispose();
      }
    });

    test('drains enter-time text before a buffered input EOF exits', () async {
      final controller = TextEditingController();
      final driver = _LifecycleFaultDriver(
        enterEvent: const TextInputEvent('piped'),
        closeDuringEnter: true,
      );
      try {
        await runApp(
          TextInput(
            controller: controller,
            autofocus: true,
            enableBlink: false,
          ),
          driver: driver,
          enableHotReload: false,
        ).timeout(const Duration(seconds: 2));

        expect(controller.text, 'piped');
        expect(driver.restoreCallCount, 1);
      } finally {
        controller.dispose();
        await driver.dispose();
      }
    });

    test('ignores startup data emitted after a stream error', () async {
      final controller = TextEditingController();
      final driver = _LifecycleFaultDriver(
        onEnter: (events) {
          events.add(const TextInputEvent('before'));
          events.addError(StateError('startup-stream-boom'));
          events.add(const TextInputEvent('after'));
        },
      );
      try {
        await runApp(
          TextInput(
            controller: controller,
            autofocus: true,
            enableBlink: false,
          ),
          driver: driver,
          enableHotReload: false,
        ).timeout(const Duration(seconds: 2));

        expect(controller.text, 'before');
        expect(driver.restoreCallCount, 1);
      } finally {
        controller.dispose();
        await driver.dispose();
      }
    });

    test('event-count startup overflow fails closed and restores', () async {
      final driver = _LifecycleFaultDriver(
        onEnter: (events) {
          for (var i = 0; i < 4097; i += 1) {
            events.add(const KeyEvent(char: 'x'));
          }
        },
      );
      try {
        await expectLater(
          runApp(
            const Text('overflow'),
            driver: driver,
            enableHotReload: false,
          ).timeout(const Duration(seconds: 2)),
          throwsA(isA<StateError>()),
        );
        expect(driver.restoreCallCount, 1);
      } finally {
        await driver.dispose();
      }
    });

    test('payload startup overflow fails closed and restores', () async {
      final driver = _LifecycleFaultDriver(
        onEnter: (events) {
          events.add(TextInputEvent('x' * (1024 * 1024 + 1)));
        },
      );
      try {
        await expectLater(
          runApp(
            const Text('overflow'),
            driver: driver,
            enableHotReload: false,
          ).timeout(const Duration(seconds: 2)),
          throwsA(isA<StateError>()),
        );
        expect(driver.restoreCallCount, 1);
      } finally {
        await driver.dispose();
      }
    });

    test('a normal Ctrl+C exit restores the terminal', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();
      expect(driver.isActive, isTrue);

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;

      expect(driver.isActive, isFalse);
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });

    test(
      'Ctrl+C copies a focused text selection before falling back to exit',
      () async {
        final clipboard = InProcessClipboard();
        final controller = TextEditingController(text: 'copyme')
          ..selection = const TextSelection(baseOffset: 0, extentOffset: 4);
        final driver = FakeTerminalDriver();
        try {
          final future = runApp(
            TextInput(controller: controller, autofocus: true),
            driver: driver,
            clipboard: clipboard,
            enableHotReload: false,
          );
          await _settle();
          expect(driver.isActive, isTrue);

          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await Future<void>.delayed(Duration.zero);

          expect(driver.isActive, isTrue);
          expect(clipboard.readInProcess(), 'copy');

          driver.enqueue(const KeyEvent(keyCode: KeyCode.arrowRight));
          await Future<void>.delayed(Duration.zero);
          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await future;

          expect(driver.isActive, isFalse);
        } finally {
          await driver.dispose();
        }
      },
    );

    test(
      'an uncaught error in an event handler is reported, not fatal',
      () async {
        final driver = FakeTerminalDriver();
        var sessionFailed = false;
        final future = runApp(
          const Text('hi'),
          driver: driver,
          enableHotReload: false,
          onEvent: (_) => throw StateError('handler-boom'),
        ).then((_) {}, onError: (_) => sessionFailed = true);
        await _settle();

        driver.clearOutput();
        driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
        await _settle();

        // The throw is reported on screen and the session keeps running — a
        // single bad handler can't take the app down (Flutter's posture).
        expect(
          sessionFailed,
          isFalse,
          reason: 'a throwing handler must not kill the session',
        );
        expect(driver.isActive, isTrue, reason: 'session still live');
        expect(
          driver.output.contains('⚠'),
          isTrue,
          reason: 'the error is surfaced as a banner',
        );
        expect(driver.output.contains('handler-boom'), isTrue);

        // Clean shutdown via Ctrl+C restores the terminal exactly once.
        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
        expect(sessionFailed, isFalse);
        expect(driver.restoreCallCount, 1);
        await driver.dispose();
      },
    );

    test('a burst of reports in one frame mounts the banner entry '
        'once', () async {
      final driver = FakeTerminalDriver(size: const CellSize(40, 6));
      final future = runApp(
        const Text('app body'),
        driver: driver,
        enableHotReload: false,
        onEvent: (event) {
          if (event is KeyEvent && event.keyCode == KeyCode.enter) {
            // Three uncaught async failures land as three reports in the
            // same microtask window — all before the banner entry's lazy
            // insert microtask runs. The insert must be idempotent.
            scheduleMicrotask(() => throw StateError('storm-a'));
            scheduleMicrotask(() => throw StateError('storm-b'));
            scheduleMicrotask(() => throw StateError('storm-c'));
          }
          return null;
        },
      );
      await _settle();

      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await _settle();

      // A double insert would trip OverlayState.insert's already-inserted
      // assert, which would surface as a FOURTH report; instead the banner
      // stacks all three behind one mounted entry.
      expect(driver.isActive, isTrue);
      expect(driver.output, contains('3 errors'));
      expect(driver.output, isNot(contains('4 errors')));

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });

    // DELIBERATE INVERSION (pipeline-program PR6): these two tests used to
    // assert that a layout/paint crash tears the session down. Containment
    // overturns that posture — the host OverlayEntry boundary renders the
    // error presentation, the session survives, and Ctrl+C still exits with
    // exactly one terminal restore.
    test('a render crash is contained; the session survives', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const _BoomWidget(),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();

      expect(
        driver.isActive,
        isTrue,
        reason: 'the crash is contained per-boundary, not fatal',
      );
      expect(
        driver.output,
        contains('layout-boom'),
        reason: 'the error presentation (or banner) is on screen',
      );

      // The session is still interactive: Ctrl+C exits cleanly.
      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      expect(driver.isActive, isFalse);
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });

    test('the terminal is restored exactly once after a contained crash '
        'and exit', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const _BoomWidget(),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();
      // Events after the contained crash still dispatch (the session is
      // alive); then exit.
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await _settle();
      expect(driver.isActive, isTrue);
      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });

    test('the terminal is restored and runApp still completes when a '
        'State.dispose() throws during teardown', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const _ThrowingDisposeApp(),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();
      expect(driver.isActive, isTrue);

      // Exit: runtime.dispose() runs the throwing State.dispose(). Teardown must
      // neither skip restore nor hang — the fault is captured and logged, the
      // terminal restored, and runApp completes normally. Without the fix this
      // future never completes (30s timeout) and restoreCallCount stays 0; the
      // 5s timeout here makes a regression fail loudly instead of hanging.
      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future.timeout(const Duration(seconds: 5));
      expect(
        driver.restoreCallCount,
        1,
        reason: 'restore ran despite the throwing State.dispose()',
      );
      expect(driver.isActive, isFalse);
      await driver.dispose();
    });

    test(
      'subscription cancellation failure cannot skip State.dispose',
      () async {
        final driver = _LifecycleFaultDriver(cancelThrows: true);
        var disposeCount = 0;
        try {
          final future = runApp(
            _DisposeProbeApp(onDispose: () => disposeCount += 1),
            driver: driver,
            enableHotReload: false,
          );
          await _settle();
          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );

          await future.timeout(const Duration(seconds: 2));
          expect(disposeCount, 1);
          expect(driver.restoreCallCount, 1);
        } finally {
          await driver.dispose();
        }
      },
    );

    test('subscription cancellation timeout cannot strand teardown', () async {
      final driver = _LifecycleFaultDriver(cancelNeverCompletes: true);
      var disposeCount = 0;
      try {
        final future = runApp(
          _DisposeProbeApp(onDispose: () => disposeCount += 1),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();
        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );

        await future.timeout(const Duration(seconds: 3));
        expect(disposeCount, 1);
        expect(driver.restoreCallCount, 1);
      } finally {
        await driver.dispose();
      }
    });

    test('multiple teardown failures still run every resource once', () async {
      final driver = _LifecycleFaultDriver(
        cancelThrows: true,
        restoreThrows: true,
      );
      var disposeCount = 0;
      try {
        final future = runApp(
          _DisposeProbeApp(
            onDispose: () {
              disposeCount += 1;
              throw StateError('dispose-boom');
            },
          ),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();
        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );

        await future.timeout(const Duration(seconds: 2));
        expect(disposeCount, 1);
        expect(driver.restoreCallCount, 1);
      } finally {
        await driver.dispose();
      }
    });

    test('restore failure is reported but runApp still settles', () async {
      final driver = _LifecycleFaultDriver(restoreThrows: true);
      var disposeCount = 0;
      try {
        final future = runApp(
          _DisposeProbeApp(onDispose: () => disposeCount += 1),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();
        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );

        await future.timeout(const Duration(seconds: 2));
        expect(disposeCount, 1);
        expect(driver.restoreCallCount, 1);
      } finally {
        await driver.dispose();
      }
    });
  });

  group('runApp application-shell ownership', () {
    test('mounts a bare root without installing a Navigator', () async {
      final driver = FakeTerminalDriver();
      BuildContext? context;
      try {
        final future = runApp(
          _NavigationProbe(
            onBuild: (value) => context = value,
            child: const Text('bare root'),
          ),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();

        expect(driver.output, contains('bare root'));
        expect(context, isNotNull);
        expect(Navigator.maybeOf(context!), isNull);
        expect(TuiBinding.of(context!).rootNavigator, isNull);

        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
      } finally {
        await driver.dispose();
      }
    });

    test(
      'FleuryApp installs the app-owned root Navigator and traversal',
      () async {
        final driver = FakeTerminalDriver();
        final nodeA = FocusNode();
        final nodeB = FocusNode();
        BuildContext? routeContext;
        try {
          final future = runApp(
            FleuryApp(
              title: 'Runtime shell',
              home: _NavigationProbe(
                onBuild: (value) => routeContext = value,
                child: Column(
                  children: [
                    Focus(
                      focusNode: nodeA,
                      autofocus: true,
                      child: const Text('A'),
                    ),
                    Focus(focusNode: nodeB, child: const Text('B')),
                  ],
                ),
              ),
            ),
            driver: driver,
            enableHotReload: false,
          );
          await _settle();
          expect(routeContext, isNotNull);
          expect(FleuryApp.of(routeContext!).title, 'Runtime shell');
          final navigator = Navigator.of(routeContext!);
          expect(TuiBinding.of(routeContext!).rootNavigator, same(navigator));
          expect(nodeA.hasFocus, isTrue, reason: 'autofocus lands on A');

          driver.enqueue(const KeyEvent(keyCode: KeyCode.arrowDown));
          await _settle();
          expect(
            nodeB.hasFocus,
            isTrue,
            reason:
                'arrowDown moves focus A→B via the traversal group owned by '
                'the app-supplied Navigator',
          );

          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await future;
        } finally {
          nodeA.dispose();
          nodeB.dispose();
          await driver.dispose();
        }
      },
    );
  });

  group('runApp full-repaint recovery', () {
    // A SIGCONT (`fg`) / terminal-handoff resume re-enters a blanked
    // alt-screen and signals it with a SAME-SIZE ResizeEvent. The diff
    // base must be reset so the next frame re-emits the whole screen;
    // otherwise the diff sees "nothing changed" and the screen stays
    // blank. (Regression: the FrameDriver's own size-change detection
    // can't see a same-size resize.)
    test('a same-size ResizeEvent forces a full repaint', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('SIGCONT-MARKER'),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();
      expect(driver.output, contains('SIGCONT-MARKER'));

      // The terminal was blanked and re-entered at the same size.
      driver.clearOutput();
      driver.enqueue(ResizeEvent(driver.size));
      await _settle();

      expect(
        driver.output,
        contains('\x1B[2J'),
        reason: 'a full repaint clears the screen first',
      );
      expect(
        driver.output,
        contains('SIGCONT-MARKER'),
        reason: 'the whole screen is re-emitted, not diffed away as unchanged',
      );

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });

    test('a terminal handoff repaints on resume', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('HANDOFF-MARKER'),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();
      driver.clearOutput();

      // The handoff hook restores the terminal, runs an operation, then
      // re-enters and fires a same-size ResizeEvent (fake_driver does this
      // in its finally) to force a repaint of the screen the operation
      // scribbled over.
      await driver.runWithTerminalHandoff(() async {});
      await _settle();

      expect(driver.output, contains('\x1B[2J'));
      expect(driver.output, contains('HANDOFF-MARKER'));

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });
  });

  group('runApp non-interactive terminals', () {
    test('refuses to run when output is not a terminal', () async {
      final driver = FakeTerminalDriver(isInteractive: false);
      await expectLater(
        runApp(const Text('x'), driver: driver, enableHotReload: false),
        throwsA(isA<Error>()),
      );
      expect(
        driver.enterCallCount,
        0,
        reason: 'must fail before touching the terminal',
      );
      await driver.dispose();
    });

    test('runs without a terminal when explicitly allowed', () async {
      final driver = FakeTerminalDriver(isInteractive: false);
      final future = runApp(
        const Text('x'),
        driver: driver,
        enableHotReload: false,
        requireInteractiveTerminal: false,
      );
      await _settle();
      expect(driver.enterCallCount, 1);

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });
  });

  group('runApp debug shell and frame diagnostics', () {
    test('F12 opens the debug-shell Logs tab', () async {
      // Content of the Logs tab is covered by output_capture_view_test (the
      // view) and the PTY stray-output integration test (the real capture);
      // stray output only exists with the fd-level capture, which needs a
      // real TTY — a FakeTerminalDriver session has no capture source.
      final driver = FakeTerminalDriver(size: const CellSize(40, 12));
      final future = runApp(
        const Text('app'),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();

      driver.clearOutput();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.f12)); // open Logs
      await _settle();
      expect(
        driver.output.contains('Logs'),
        isTrue,
        reason: 'debug shell opens on its Logs tab',
      );

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });

    test(
      'debug frame events include dirty bounds without paint flash',
      () async {
        final frames = <FrameEvent>[];
        final sub = DebugEvents.stream.listen((event) {
          if (event is FrameDebugEvent) frames.add(event.frame);
        });
        final driver = FakeTerminalDriver(size: const CellSize(20, 4));
        try {
          final future = runApp(
            const Text('dirty'),
            driver: driver,
            enableHotReload: false,
          );
          await _settle();

          expect(frames, isNotEmpty);
          final first = frames.first;
          expect(first.reason, contains('initial'));
          expect(first.dirtyCells, greaterThan(0));
          expect(first.dirtyBounds, isNotNull);
          expect(first.dirtyBounds!.left, 0);
          expect(first.dirtyBounds!.top, 0);
          expect(first.dirtySpans.hasDirtySpans, isTrue);
          expect(first.dirtySpans.spanCount, greaterThan(0));
          expect(first.dirtySpans.coveredCellCount, first.dirtyCells);

          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await future;
        } finally {
          await sub.cancel();
          await driver.dispose();
        }
      },
    );

    test('debug frame events include repaint boundary cache metrics', () async {
      final frames = <FrameEvent>[];
      final sub = DebugEvents.stream.listen((event) {
        if (event is FrameDebugEvent) frames.add(event.frame);
      });
      final driver = FakeTerminalDriver(size: const CellSize(20, 4));
      final counterKey = GlobalKey<_CounterAppState>();
      try {
        final future = runApp(
          Column(
            children: [
              const RepaintBoundary(child: Text('cached')),
              _CounterApp(key: counterKey),
            ],
          ),
          driver: driver,
          enableHotReload: false,
        );
        await _settle();

        expect(frames, isNotEmpty);
        final firstFrame = frames.first;
        expect(firstFrame.layoutStats.performedCount, greaterThan(0));
        expect(firstFrame.layoutStats.skippedCount, 0);
        // Exactly the ONE explicit boundary around 'cached': the error
        // banner entry mounts lazily, so an idle app's root overlay is
        // single-entry and its adaptive per-entry boundary stays
        // pass-through — it must not show up in the stats.
        final firstBoundaries = firstFrame.repaintBoundaries;
        expect(firstBoundaries.boundaryCount, 1);
        expect(firstBoundaries.repaintedCount, 1);
        expect(firstBoundaries.cachedCount, 0);
        expect(firstBoundaries.copiedCellCount, greaterThan(0));

        frames.clear();
        // Dirty a sibling OUTSIDE the boundary: the frame must render (a
        // clean frame is now skipped entirely) and the boundary replays
        // its cache instead of repainting.
        counterKey.currentState!.increment();
        await _settle();

        expect(frames, isNotEmpty);
        final secondFrame = frames.last;
        expect(secondFrame.layoutStats.skippedCount, greaterThan(0));
        final secondBoundaries = secondFrame.repaintBoundaries;
        expect(secondBoundaries.boundaryCount, 1);
        expect(secondBoundaries.repaintedCount, 0);
        expect(secondBoundaries.cachedCount, 1);
        expect(secondBoundaries.copiedCellCount, greaterThan(0));

        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
      } finally {
        await sub.cancel();
        await driver.dispose();
      }
    });

    test('the error banner entry mounts on report and unmounts on '
        'dismiss', () async {
      final frames = <FrameEvent>[];
      final sub = DebugEvents.stream.listen((event) {
        if (event is FrameDebugEvent) frames.add(event.frame);
      });
      final driver = FakeTerminalDriver(size: const CellSize(40, 6));
      try {
        final future = runApp(
          const Text('app body'),
          driver: driver,
          enableHotReload: false,
          onEvent: (event) {
            if (event is KeyEvent && event.keyCode == KeyCode.enter) {
              throw StateError('banner-boom');
            }
            return null;
          },
        );
        await _settle();

        // Idle: the banner entry is not mounted, so the root overlay is
        // single-entry and its adaptive boundary stays pass-through.
        expect(frames, isNotEmpty);
        expect(frames.last.repaintBoundaries.boundaryCount, 0);

        driver.clearOutput();
        driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
        await _settle();

        // The report mounted the banner entry (a microtask later): two
        // visible entries, so both entry boundaries engage — the app entry
        // is now the protected sibling under banner churn.
        expect(driver.output, contains('banner-boom'));
        expect(frames.last.repaintBoundaries.boundaryCount, 2);

        // Dismiss by clicking the banner (bottom-center of the viewport):
        // the reporter empties and the entry unmounts symmetrically —
        // an idle-again session returns to single-entry pass-through.
        driver.enqueue(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 20,
            row: 4,
          ),
        );
        driver.enqueue(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 20,
            row: 4,
          ),
        );
        await _settle();
        expect(frames.last.repaintBoundaries.boundaryCount, 0);
        expect(driver.isActive, isTrue);

        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
      } finally {
        await sub.cancel();
        await driver.dispose();
      }
    });

    test('layout-affecting shrink clears trailing cells', () async {
      final key = GlobalKey<_ShrinkTextAppState>();
      final driver = FakeTerminalDriver(size: const CellSize(12, 2));
      try {
        final future = runApp(
          _ShrinkTextApp(key: key),
          driver: driver,
          enableHotReload: false,
          onEvent: (event) {
            if (event is KeyEvent && event.keyCode == KeyCode.enter) {
              key.currentState!.shrink();
            }
            return null;
          },
        );
        await _settle();

        driver.clearOutput();
        driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
        await _settle();

        expect(
          driver.output.contains('i   '),
          isTrue,
          reason: 'shrinking text must clear old trailing cells via full diff',
        );

        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
      } finally {
        await driver.dispose();
      }
    });

    test('debug frame events include build invalidation sources', () async {
      final key = GlobalKey<_CounterAppState>();
      final frames = <FrameEvent>[];
      final sub = DebugEvents.stream.listen((event) {
        if (event is FrameDebugEvent) frames.add(event.frame);
      });
      final driver = FakeTerminalDriver(size: const CellSize(24, 4));
      try {
        final future = runApp(
          _CounterApp(key: key),
          driver: driver,
          enableHotReload: false,
          onEvent: (event) {
            if (event is KeyEvent && event.keyCode == KeyCode.enter) {
              key.currentState!.increment();
            }
            return null;
          },
        );
        await _settle();
        frames.clear();

        driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
        await _settle();

        expect(frames, isNotEmpty);
        final frame = frames.last;
        expect(frame.reason, contains('key:enter'));
        expect(
          frame.dirtySources,
          contains(contains('_CounterApp/_CounterAppState')),
        );

        driver.enqueue(
          const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
        );
        await future;
      } finally {
        await sub.cancel();
        await driver.dispose();
      }
    });

    test(
      'debug capture recorder observes terminal, input, resize, and frames',
      () async {
        final recorder = DebugCaptureRecorder()..attach();
        final driver = FakeTerminalDriver(size: const CellSize(20, 4));
        try {
          final future = runApp(
            const Text('capture'),
            driver: driver,
            enableHotReload: false,
          );
          await _settle();

          driver.resize(const CellSize(30, 6));
          await _settle();
          driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
          await _settle();
          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await future;

          final snapshot = recorder.snapshot();
          expect(snapshot.terminalDiagnosis, isNotNull);
          expect(
            snapshot.terminalDiagnosis!.terminal.size,
            const CellSize(30, 6),
          );
          expect(snapshot.frames, isNotEmpty);
          expect(
            snapshot.inputs.map((input) => input.kind),
            containsAll(<String>['resize', 'key']),
          );

          final json = snapshot.toJson();
          final terminal = json['terminal'] as Map<String, Object?>;
          final terminalProfile = terminal['terminal'] as Map<String, Object?>;
          expect(terminalProfile['columns'], 30);
          expect(terminalProfile['rows'], 6);
          final inputs = json['inputs'] as List<Object?>;
          expect(
            inputs.where(
              (input) =>
                  input is Map<String, Object?> && input['kind'] == 'resize',
            ),
            isNotEmpty,
          );
          final frames = json['frames'] as List<Object?>;
          expect(frames, isNotEmpty);
        } finally {
          await recorder.dispose();
          await driver.dispose();
        }
      },
    );

    test('F12 reaches Logs even inside a Navigator modal route', () async {
      // The Navigator's active route sets `suppressGlobals: true`,
      // which previously would have prevented a tree-level KeyBindings
      // from firing. The debug-shell hotkeys are escape-hatches routed
      // through runApp BEFORE the dispatcher, so they bypass the modal
      // scope — this test locks that contract.
      final driver = FakeTerminalDriver(size: const CellSize(40, 12));
      final future = runApp(
        const _ModalApp(),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();

      driver.clearOutput();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.f12)); // open Logs
      await _settle();
      expect(
        driver.output.contains('Logs'),
        isTrue,
        reason: 'F12 must fire even inside a modal route — escape hatch',
      );

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });
  });

  group('runApp clipboard wiring', () {
    test('OSC 52 rides the DRIVER write path, not process stdout', () async {
      // Under fd-capture (the POSIX TTY default) process stdout is redirected
      // into the stray-output pipe — an OSC 52 written there is swallowed as a
      // "log line" and the copy silently never reaches the terminal (the only
      // clipboard path that works over SSH). runApp must construct the
      // clipboard against the driver's terminal handle; this locks that
      // wiring: the escape lands in the driver's output.
      final driver = FakeTerminalDriver(size: const CellSize(40, 6));
      final future = runApp(
        const _ClipboardCopyApp(),
        driver: driver,
        enableHotReload: false,
      );
      await _settle();

      driver.clearOutput();
      driver.enqueue(const KeyEvent(char: 'y', modifiers: {KeyModifier.ctrl}));
      await _settle();
      await _settle();
      expect(
        driver.output,
        contains(']52;c;'),
        reason:
            'OSC 52 must go through driver.write — a bare stdout.write is '
            'captured as stray output under fd-capture and never reaches the '
            'terminal',
      );

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });
  });
}

/// Ctrl+Y copies through the ambient ClipboardScope — the seam under test is
/// runApp's SystemClipboard construction, so the policy skips platform tools
/// to force the OSC 52 path deterministically.
class _ClipboardCopyApp extends StatelessWidget {
  const _ClipboardCopyApp();

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.ctrl.y,
          label: 'copy',
          onEvent: (_) {
            unawaited(
              ClipboardScope.of(context).writeWithReport(
                'clip-me',
                policy: const ClipboardWritePolicy(allowPlatformTool: false),
              ),
            );
          },
        ),
      ],
      child: const Text('clipboard app'),
    );
  }
}
