import 'dart:async';
import 'dart:io';

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

/// Lets the run loop's async body reach the point where it's listening for
/// events before the test pushes one (a broadcast stream drops events that
/// arrive with no listener).
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('runApp terminal restoration', () {
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
        final originalClipboard = Clipboard.instance;
        final clipboard = TestClipboard();
        Clipboard.instance = clipboard;
        final controller = TextEditingController(text: 'copyme')
          ..textSelection = const TextSelection(baseOffset: 0, extentOffset: 4);
        final driver = FakeTerminalDriver();
        try {
          final future = runApp(
            TextInput(controller: controller, autofocus: true),
            driver: driver,
            enableHotReload: false,
          );
          await _settle();
          expect(driver.isActive, isTrue);

          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await Future<void>.delayed(Duration.zero);

          expect(driver.isActive, isTrue);
          expect(clipboard.lastWritten, 'copy');

          driver.enqueue(const KeyEvent(keyCode: KeyCode.arrowRight));
          await Future<void>.delayed(Duration.zero);
          driver.enqueue(
            const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}),
          );
          await future;

          expect(driver.isActive, isFalse);
        } finally {
          Clipboard.instance = originalClipboard;
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

    test('an error during a scheduled frame restores the terminal and '
        'surfaces the error', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const _BoomWidget(),
        driver: driver,
        enableHotReload: false,
      );

      await expectLater(future, throwsA(isA<Error>()));
      expect(
        driver.isActive,
        isFalse,
        reason: 'a paint/layout crash must not leave the terminal wedged',
      );
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });

    test('the terminal is restored exactly once', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const _BoomWidget(),
        driver: driver,
        enableHotReload: false,
      );
      await expectLater(future, throwsA(isA<Error>()));
      // Push more events after the crash — cleanup must not run again.
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await _settle();
      expect(driver.restoreCallCount, 1);
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

  group('runApp stray-output capture', () {
    test('a stray print is captured and replayed once the terminal is '
        'restored', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('ui'),
        driver: driver,
        enableHotReload: false,
        onEvent: (_) {
          print('STRAY-LINE');
          return const ExitRequested();
        },
      );
      await _settle();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await future;

      // The line reaches the screen only as the post-session replay; it never
      // interleaved with the live frame.
      expect(driver.output.contains('STRAY-LINE'), isTrue);
      await driver.dispose();
    });

    test(
      'stray output is routed live to onStrayOutput and not replayed',
      () async {
        final driver = FakeTerminalDriver();
        final captured = <LogLine>[];
        final future = runApp(
          const Text('ui'),
          driver: driver,
          enableHotReload: false,
          onStrayOutput: captured.add,
          onEvent: (_) {
            print('HOOKED');
            return const ExitRequested();
          },
        );
        await _settle();
        driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
        await future;

        expect(captured.map((l) => l.text), contains('HOOKED'));
        expect(
          driver.output.contains('HOOKED'),
          isFalse,
          reason: 'a hook takes ownership of disposition — no replay',
        );
        await driver.dispose();
      },
    );

    test('direct stderr writes are captured and tagged as stderr', () async {
      final driver = FakeTerminalDriver();
      final captured = <LogLine>[];
      final future = runApp(
        const Text('ui'),
        driver: driver,
        enableHotReload: false,
        onStrayOutput: captured.add,
        onEvent: (_) {
          stderr.writeln('ERR-LINE');
          return const ExitRequested();
        },
      );
      await _settle();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await future;

      final line = captured.firstWhere((l) => l.text == 'ERR-LINE');
      expect(line.source, LogSource.stderr);
      await driver.dispose();
    });

    test('F12 opens debug-shell Logs tab showing captured output', () async {
      final driver = FakeTerminalDriver(size: const CellSize(30, 12));
      final future = runApp(
        const Text('app'),
        driver: driver,
        enableHotReload: false,
        onEvent: (e) {
          if (e is KeyEvent && e.keyCode == KeyCode.enter) print('CONSOLE-LOG');
          return null;
        },
      );
      await _settle();

      // Produce a captured line (lands in the buffer, not the live frame).
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await _settle();

      driver.clearOutput();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.f12)); // open Logs
      await _settle();
      expect(
        driver.output.contains('CONSOLE-LOG'),
        isTrue,
        reason: 'debug shell Logs tab renders the captured line',
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
      final driver = FakeTerminalDriver(size: const CellSize(30, 12));
      final future = runApp(
        const _ModalApp(),
        driver: driver,
        enableHotReload: false,
        onEvent: (e) {
          if (e is KeyEvent && e.keyCode == KeyCode.enter) print('OVER-MODAL');
          return null;
        },
      );
      await _settle();

      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter)); // capture a line
      await _settle();
      driver.clearOutput();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.f12)); // open Logs
      await _settle();
      expect(
        driver.output.contains('OVER-MODAL'),
        isTrue,
        reason: 'F12 must fire even inside a modal route — escape hatch',
      );

      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });

    test('partial writes are assembled into whole lines', () async {
      final driver = FakeTerminalDriver();
      final captured = <LogLine>[];
      final future = runApp(
        const Text('ui'),
        driver: driver,
        enableHotReload: false,
        onStrayOutput: captured.add,
        onEvent: (_) {
          stdout.write('par');
          stdout.write('tial\n');
          return const ExitRequested();
        },
      );
      await _settle();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await future;

      expect(captured.map((l) => l.text), contains('partial'));
      await driver.dispose();
    });
  });
}
