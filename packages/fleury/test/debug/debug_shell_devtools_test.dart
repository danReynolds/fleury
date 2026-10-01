import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Events implements TuiEventSink {
  final events = <TuiEvent>[];

  @override
  void add(TuiEvent event) => events.add(event);
}

/// The events the real terminal parser makes of [bytes].
List<TuiEvent> _parsed(String bytes) {
  final sink = _Events();
  InputParser()
    ..feed(bytes.codeUnits, sink)
    ..flush(sink);
  return sink.events;
}

/// How each kind of keyboard delivers one press of a printable key to runApp.
final _keyboards =
    <(String, KeyboardCapabilities, List<TuiEvent> Function(String key))>[
      // The character itself, parsed into text.
      ('a classic terminal', KeyboardCapabilities.legacy, _parsed),
      // A key report with text for the press, then one for the release.
      (
        'a Kitty-protocol terminal',
        KeyboardCapabilities.fromKittyFlags(0x0F),
        (key) =>
            _parsed('\x1b[${key.codeUnitAt(0)}u\x1b[${key.codeUnitAt(0)};1:3u'),
      ),
      // A served browser: keydown, the typed text, then keyup.
      (
        'a browser',
        KeyboardCapabilities.full,
        (key) => [
          KeyEvent(KeyCode.char(key)),
          TextInputEvent(key),
          KeyEvent(KeyCode.char(key), type: KeyEventType.up),
        ],
      ),
    ];

void main() {
  test('DebugConfig is public API', () {
    // Constructing via package:fleury/fleury.dart is itself the export
    // assertion — this file has no src/ imports. The enabled default is
    // decided per launch: test/debug/debug_default_test.dart.
    const config = DebugConfig(
      startMode: DebugMode.docked,
      side: DebugPanelSide.bottom,
      panelWidth: 40,
    );
    expect(config.startMode, DebugMode.docked);
    expect(config.side, DebugPanelSide.bottom);
  });

  test('Tab cycles the shell tabs; Shift+Tab cycles back', () async {
    final driver = FakeTerminalDriver(size: const CellSize(90, 18));
    final future = runApp(
      const Text('app'),
      driver: driver,
      enableHotReload: false,
    );
    await _settle();
    driver.enqueue(
      const KeyEvent(KeyCode.char('g'), modifiers: {KeyModifier.ctrl}),
    );
    await _settle();

    // Live -> Tree: the Tree tab renders semantic-tree content.
    driver.clearOutput();
    driver.enqueue(const KeyEvent(KeyCode.tab));
    await _settle();
    expect(driver.output, contains('Semantic nodes'));
    expect(driver.output, contains('select semantic node'));

    // Shift+Tab returns to Live (frame stats).
    driver.clearOutput();
    driver.enqueue(const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}));
    await _settle();
    expect(driver.output, contains('Frame'));

    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await future;
    await driver.dispose();
  });

  test(
    'Errors tab lists uncaught handler errors from the bounded history',
    () async {
      final driver = FakeTerminalDriver(size: const CellSize(90, 18));
      final future = runApp(
        const Text('app'),
        driver: driver,
        enableHotReload: false,
        onEvent: (e) {
          if (e is KeyEvent && e.code == KeyCode.enter) {
            throw StateError('handler-kaboom');
          }
          return null;
        },
      );
      await _settle();

      driver.enqueue(const KeyEvent(KeyCode.enter)); // throw + banner
      await _settle();
      driver.enqueue(
        const KeyEvent(KeyCode.char('g'), modifiers: {KeyModifier.ctrl}),
      );
      await _settle();
      // Live -> Tree -> Rebuilds -> Logs -> Errors.
      for (var i = 0; i < 4; i++) {
        driver.enqueue(const KeyEvent(KeyCode.tab));
        await _settle();
      }
      driver.clearOutput();
      driver.enqueue(const KeyEvent(KeyCode.tab)); // wrap to Live…
      driver.enqueue(
        const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
      ); // …and back, forcing an Errors repaint
      await _settle();
      expect(
        driver.output,
        contains('handler-kaboom'),
        reason: 'the Errors tab renders the recorded error summary',
      );

      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await future;
      await driver.dispose();
    },
  );

  test('Logs search opens via the real TextInputEvent path', () async {
    // The parser delivers printable keys as TextInputEvent, not KeyEvent, so
    // '/' and the typed query must be consumed on the *text* arm of the debug
    // escape-hatch (run_app → tryConsumeDebugText). This drives them the way a
    // real keyboard does — the KeyEvent-only unit tests can't catch a broken
    // text route, which is exactly how the first cut of this shipped inert.
    final driver = FakeTerminalDriver(size: const CellSize(90, 18));
    final future = runApp(
      const Text('app'),
      driver: driver,
      enableHotReload: false,
    );
    await _settle();

    // Open straight to Logs (F12), then drive the search with text events.
    driver.enqueue(const KeyEvent(KeyCode.f12));
    await _settle();
    driver.enqueue(const TextInputEvent('/'));
    driver.enqueue(const TextInputEvent('a'));
    driver.enqueue(const TextInputEvent('b'));
    await _settle();

    // Force a full Logs re-render (tab away + back) so the search field lands
    // contiguously in the diff, then assert the query is there.
    driver.enqueue(const KeyEvent(KeyCode.tab)); // → Errors
    await _settle();
    driver.clearOutput();
    driver.enqueue(
      const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
    ); // → back to Logs, full repaint
    await _settle();
    expect(
      driver.output,
      contains('/ab'),
      reason: 'TextInputEvent routed to the Logs search field',
    );

    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await future;
    await driver.dispose();
  });

  for (final (keyboard, capabilities, press) in _keyboards) {
    test('from $keyboard, f expands and docks the open panel; the app or an '
        'open search gets it otherwise', () async {
      final field = TextEditingController();
      addTearDown(field.dispose);
      final driver = FakeTerminalDriver(
        size: const CellSize(90, 18),
        keyboardCapabilities: capabilities,
      );
      final app = runApp(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('notes app'),
            TextInput(controller: field, autofocus: true, enableBlink: false),
          ],
        ),
        driver: driver,
        enableHotReload: false,
      );
      try {
        await _settle();

        Future<void> type(String key) async {
          press(key).forEach(driver.enqueue);
          await _settle();
        }

        Future<void> hotkey(KeyEvent event) async {
          driver.enqueue(event);
          await _settle();
        }

        // Repaints everything, so a check can't miss text the last frame's
        // diff left out.
        Future<String> screen() async {
          driver.clearOutput();
          driver.resize(driver.size);
          await _settle();
          return driver.output;
        }

        const ctrlG = KeyEvent(
          KeyCode.char('g'),
          modifiers: {KeyModifier.ctrl},
        );
        // The docked panel floats beside the app's text; expanded, it covers
        // the whole screen.
        final docked = allOf(contains('FLEURY DEBUG'), contains('notes app'));
        final expanded = allOf(
          contains('FLEURY DEBUG'),
          isNot(contains('notes app')),
        );

        await type('f');
        expect(
          field.text,
          'f',
          reason: 'closed, the panel leaves f to the app',
        );

        await hotkey(ctrlG);
        expect(await screen(), docked);
        await type('f');
        expect(await screen(), expanded, reason: 'f expanded the panel');
        await type('f');
        expect(await screen(), docked, reason: 'f docked it again');
        expect(field.text, 'f', reason: 'the open panel took both presses');

        await hotkey(const KeyEvent(KeyCode.f12)); // the Logs tab
        await type('/');
        await type('f');
        final searching = await screen();
        expect(searching, contains('/f'), reason: 'the search took f');
        expect(searching, docked, reason: 'and did not expand the panel');

        await hotkey(const KeyEvent(KeyCode.escape)); // clear the search
        await hotkey(ctrlG); // close the panel
        await type('f');
        expect(field.text, 'ff', reason: 'closed again, the app types f');
      } finally {
        exitApp();
        await app;
        await driver.dispose();
      }
    });
  }
}
