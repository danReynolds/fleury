import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// App-owned shutdown (RFC: signals as events).
///
/// SIGINT/SIGTERM reach the app as [SignalEvent]s through the normal event
/// stream. An unclaimed signal keeps its POSIX meaning (terminate — runApp
/// resolves with [AppExit.signal]); a handler that returns [EventHandled]
/// claims it and finishes via [requestExit]. All orderly exits resolve
/// runApp's future so the caller's cleanup actually runs.
void main() {
  Future<void> pump([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('SignalEvent through runApp', () {
    test('an unclaimed signal terminates with AppExit.signal', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
      );
      await pump();
      expect(driver.isActive, isTrue);

      driver.enqueue(const SignalEvent(AppSignal.terminate));
      final exit = await future;

      expect(exit.signal, AppSignal.terminate);
      expect(driver.isActive, isFalse, reason: 'cleanup restored the driver');
      await driver.dispose();
    });

    test(
      'a claimed signal hands shutdown to the app; requestExit finishes it',
      () async {
        final driver = FakeTerminalDriver();
        final seen = <AppSignal>[];
        final future = runApp(
          const Text('hi'),
          driver: driver,
          enableHotReload: false,
          onEvent: (event) {
            if (event is SignalEvent) {
              seen.add(event.signal);
              return const EventHandled();
            }
            return null;
          },
        );
        await pump();

        driver.enqueue(const SignalEvent(AppSignal.terminate));
        await pump();
        expect(seen, [AppSignal.terminate]);
        expect(
          driver.isActive,
          isTrue,
          reason: 'claimed signal must NOT exit the loop',
        );

        expect(requestExit(), isTrue);
        final exit = await future;
        expect(exit.signal, isNull, reason: 'app-owned shutdown = requested');

        expect(
          requestExit(),
          isFalse,
          reason: 'no app running once cleanup has cleared the seam',
        );
        await driver.dispose();
      },
    );

    test('ExitRequested from onEvent still exits (regression)', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
        // A typed printable reaches onEvent as the parser emits it — a
        // TextInputEvent, never a bare KeyEvent(char). (Quit keys should
        // use a widget-level KeyBinding + requestExit, which respects a
        // focused text field; this test pins the raw onEvent mechanism.)
        onEvent: (event) => event is TextInputEvent && event.text == 'q'
            ? const ExitRequested()
            : null,
      );
      await pump();

      driver.enqueue(const TextInputEvent('q'));
      final exit = await future;
      expect(exit.signal, isNull);
      await driver.dispose();
    });

    for (final mode in [
      TerminalMode.interactive,
      const TerminalMode.inline(rows: 10),
    ]) {
      test(
        'unhandled Ctrl+C preserves interrupt in '
        '${mode.inlineRows == null ? 'full-screen' : 'inline'} mode',
        () async {
          final driver = FakeTerminalDriver();
          final future = runApp(
            const Text('hi'),
            driver: driver,
            mode: mode,
            enableHotReload: false,
          );
          await pump();

          driver.enqueue(
            const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
          );
          final exit = await future;
          expect(exit.signal, AppSignal.interrupt);
          expect(driver.isActive, isFalse);
          await driver.dispose();
        },
      );
    }

    test(
      'a widget can claim Ctrl+C without interrupting the command',
      () async {
        final driver = FakeTerminalDriver();
        var claimed = 0;
        final future = runApp(
          KeyBindings(
            bindings: [
              KeyBinding(KeySequence.ctrl.c, onTrigger: (_) => claimed++),
            ],
            child: const Focus(autofocus: true, child: Text('working')),
          ),
          driver: driver,
          enableHotReload: false,
        );
        try {
          await pump();
          driver.enqueue(
            const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
          );
          driver.enqueue(
            const KeyEvent(
              KeyCode.char('c'),
              modifiers: {KeyModifier.ctrl},
              type: KeyEventType.up,
            ),
          );
          await pump();
          expect(claimed, 1);
          expect(driver.isActive, isTrue);

          requestExit();
          expect((await future).signal, isNull);
        } finally {
          requestExit();
          await future;
          await driver.dispose();
        }
      },
    );

    test("the documented quit pattern: a widget-level 'q' binding + "
        'requestExit exits on typed text', () async {
      // run_app.dart documents requestExit as "the programmatic quit for
      // `q` keys". The parser emits a typed q as a TextInputEvent; the
      // dispatcher's synthesized-KeyEvent fallback carries it to the
      // binding when no text claimant consumes it.
      final driver = FakeTerminalDriver();
      final future = runApp(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.q,
              onTrigger: (_) => requestExit(),
              label: 'Quit',
            ),
          ],
          child: const Text('hi'),
        ),
        driver: driver,
        enableHotReload: false,
      );
      await pump();

      driver.enqueue(const TextInputEvent('q'));
      final exit = await future;
      expect(exit.signal, isNull);
      await driver.dispose();
    });

    test(
      "a focused text field claims the typed 'q' before the quit binding",
      () async {
        final driver = FakeTerminalDriver();
        final controller = TextEditingController();
        final future = runApp(
          KeyBindings(
            bindings: [
              KeyBinding(
                KeySequence.q,
                onTrigger: (_) => requestExit(),
                label: 'Quit',
              ),
            ],
            child: TextInput(controller: controller, autofocus: true),
          ),
          driver: driver,
          enableHotReload: false,
        );
        await pump();

        driver.enqueue(const TextInputEvent('q'));
        await pump();
        expect(controller.text, 'q', reason: 'typing wins over the quit key');
        expect(driver.isActive, isTrue, reason: 'the app must not exit');

        requestExit();
        final exit = await future;
        expect(exit.signal, isNull);
        await driver.dispose();
      },
    );

    test(
      'a claimed signal leaves the loop alive (shutdown UI can render)',
      () async {
        final driver = FakeTerminalDriver();
        final future = runApp(
          const Text('hi'),
          driver: driver,
          enableHotReload: false,
          onEvent: (event) =>
              event is SignalEvent ? const EventHandled() : null,
        );
        await pump();

        // A claimed signal falls through to frame scheduling (unlike an
        // unclaimed one, which exits before scheduling) — the loop stays
        // alive so the app's "disconnecting…" state can paint.
        driver.enqueue(const SignalEvent(AppSignal.interrupt));
        await pump();
        expect(driver.isActive, isTrue);

        requestExit();
        await future;
        await driver.dispose();
      },
    );
  });
}
