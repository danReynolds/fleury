import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
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

/// Lets the run loop's async body reach the point where it's listening for
/// events before the test pushes one (a broadcast stream drops events that
/// arrive with no listener).
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('runTui terminal restoration', () {
    test('a normal Ctrl+C exit restores the terminal', () async {
      final driver = FakeTerminalDriver();
      final future = runTui(
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

    test('an uncaught error in an event handler restores the terminal and '
        'surfaces the error', () async {
      final driver = FakeTerminalDriver();
      final future = runTui(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
        onEvent: (_) => throw StateError('handler-boom'),
      );
      await _settle();

      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await expectLater(future, throwsA(isA<Error>()));

      expect(
        driver.isActive,
        isFalse,
        reason: 'terminal restored even though a callback threw',
      );
      expect(driver.restoreCallCount, 1);
      await driver.dispose();
    });

    test('an error during a scheduled frame restores the terminal and '
        'surfaces the error', () async {
      final driver = FakeTerminalDriver();
      final future = runTui(
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
      final future = runTui(
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

  group('runTui non-interactive terminals', () {
    test('refuses to run when output is not a terminal', () async {
      final driver = FakeTerminalDriver(isInteractive: false);
      await expectLater(
        runTui(const Text('x'), driver: driver, enableHotReload: false),
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
      final future = runTui(
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

  group('runTui stray-output capture', () {
    test('a stray print is captured and replayed once the terminal is '
        'restored', () async {
      final driver = FakeTerminalDriver();
      final future = runTui(
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
        final future = runTui(
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
      final future = runTui(
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
      final future = runTui(
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

    test('F12 reaches Logs even inside a Navigator modal route', () async {
      // The Navigator's active route sets `suppressGlobals: true`,
      // which previously would have prevented a tree-level KeyBindings
      // from firing. The debug-shell hotkeys are escape-hatches routed
      // through runTui BEFORE the dispatcher, so they bypass the modal
      // scope — this test locks that contract.
      final driver = FakeTerminalDriver(size: const CellSize(30, 12));
      final future = runTui(
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
      final future = runTui(
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
