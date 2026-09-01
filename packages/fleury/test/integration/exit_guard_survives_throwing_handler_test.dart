// The framework's Ctrl+C quit guard survives a throwing handler.
//
// runApp dispatches the event and THEN consults the result for the quit
// guard. A handler that threw unwound past the guard into the loop's catch,
// so the app kept running — and with a handler that threw on every press
// (a stale selection's copy did exactly this), the keyboard could never quit
// it. A throw is reported like any other handler error; the dispatch result
// stays `ignored`, and an unhandled Ctrl+C exits as it always should.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  test('Ctrl+C still quits when the app handler for it throws', () async {
    final driver = FakeTerminalDriver();
    final app = runApp(
      FleuryApp(
        title: 'boom',
        home: KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.c,
              onTrigger: (_) => throw StateError('handler boom'),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      ),
      driver: driver,
      requireInteractiveTerminal: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );

    final exit = await app.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the app did not exit on Ctrl+C'),
    );
    expect(exit.signal, isNull, reason: "exit was the quit guard, not a signal");
  }, timeout: const Timeout(Duration(seconds: 20)));
}
