// Pins the advertised 'q' quit key of the sample launcher.
//
// The terminal parser emits a typed `q` as a TextInputEvent — never as a
// bare KeyEvent — so quit must be the widget-level KeyBinding +
// requestExit() pattern (`withQuitKey` in bin/samples.dart), scoped by the
// dispatcher: a focused text field (the agent sample's prompt) claims the
// character first and keeps receiving it, while every other sample quits.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_samples/samples.dart';
import 'package:test/test.dart';

import '../bin/samples.dart' show withQuitKey;

void main() {
  Future<void> pump([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test("typed 'q' (a TextInputEvent, as the parser emits it) quits the "
      'dashboard sample', () async {
    final driver = FakeTerminalDriver();
    final future = runApp(
      FleuryApp(
        title: 'Fleury dashboard sample',
        home: withQuitKey(const DashboardApp()),
      ),
      driver: driver,
      enableHotReload: false,
    );
    await pump();
    expect(driver.isActive, isTrue);

    driver.enqueue(const TextInputEvent('q'));
    final exit = await future;
    expect(exit.signal, isNull, reason: 'q is an orderly requested exit');
    await driver.dispose();
  });

  test("typed 'q' quits the files sample (the focused Tree must not "
      'swallow it as type-ahead)', () async {
    final driver = FakeTerminalDriver();
    final future = runApp(
      FleuryApp(
        title: 'Fleury files sample',
        home: withQuitKey(const FileManagerApp()),
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

  test("typed 'q' quits the debug playground sample", () async {
    final driver = FakeTerminalDriver();
    final future = runApp(
      FleuryApp(
        title: 'Fleury debug sample',
        home: withQuitKey(const DebugPlaygroundApp()),
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

  test("the agent sample's focused prompt claims a typed 'q' — the app "
      'must not quit mid-typing', () async {
    final driver = FakeTerminalDriver();
    final future = runApp(
      FleuryApp(
        title: 'Fleury agent sample',
        home: withQuitKey(const AgentApp()),
      ),
      driver: driver,
      enableHotReload: false,
    );
    await pump();

    driver.enqueue(const TextInputEvent('q'));
    await pump();
    expect(
      driver.isActive,
      isTrue,
      reason: "typing 'q' into the prompt must not exit the app",
    );

    requestExit();
    final exit = await future;
    expect(exit.signal, isNull);
    await driver.dispose();
  });

  testWidgets("typed text lands in the agent prompt, not the quit binding", (
    tester,
  ) {
    tester.pumpWidget(withQuitKey(const AgentApp()));
    tester.render(size: const CellSize(120, 40));
    tester.type('qzq');
    final out = tester.renderToString(size: const CellSize(120, 40));
    expect(out, contains('qzq'), reason: 'the prompt received the characters');
  });
}
