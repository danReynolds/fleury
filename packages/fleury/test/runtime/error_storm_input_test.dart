// runApp ends the session on a storm of uncaught errors: errors that recur
// with nothing to cause them, a loop that would otherwise spin forever. An
// error that follows input is one the user stops by letting go of the key —
// a held shortcut whose command fails, fast typing into a field whose async
// handler fails — so it is reported and the session keeps running.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

const _ctrlZ = KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl});
const _ctrlC = KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl});

const _body = Focus(autofocus: true, child: Text('body'));

/// Holds Ctrl+Z for 30 repeats in [app], then quits with Ctrl+C. Returns
/// whether the session was still running after the repeats.
Future<bool> _holdCtrlZ(Widget app) async {
  final driver = FakeTerminalDriver(size: const CellSize(40, 6));
  final errors = <Object>[];
  final run = runApp(
    app,
    driver: driver,
    enableHotReload: false,
  ).then<void>((_) {}, onError: (Object error) => errors.add(error));
  await _settle();
  for (var i = 0; i < 30; i++) {
    driver.enqueue(_ctrlZ);
  }
  await _settle();
  await _settle();
  final running = driver.isActive;
  if (running) driver.enqueue(_ctrlC);
  await run.timeout(const Duration(seconds: 5));
  await driver.dispose();
  expect(errors, running ? isEmpty : isNotEmpty);
  return running;
}

final class _Loop extends StatefulWidget {
  const _Loop();

  @override
  State<_Loop> createState() => _LoopState();
}

final class _LoopState extends State<_Loop> {
  late final Timer _timer = Timer.periodic(
    const Duration(milliseconds: 1),
    (_) => throw StateError('loop'),
  );

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('looping');
}

void main() {
  test('holding the shortcut of a failing command keeps the session', () async {
    final running = await _holdCtrlZ(
      FleuryApp(
        title: 'Editor',
        commands: [
          AppCommand(
            id: const CommandId('edit.undo'),
            title: 'Undo',
            shortcuts: [KeySequence.ctrl.z],
            run: (_) => throw StateError('nothing to undo'),
          ),
        ],
        home: _body,
      ),
    );
    expect(running, isTrue);
  });

  test('holding a key whose async handler fails keeps the session', () async {
    final running = await _holdCtrlZ(
      KeyBindings(
        bindings: [
          KeyBinding(
            KeySequence.ctrl.z,
            onTrigger: (_) async => throw StateError('offline'),
          ),
        ],
        child: _body,
      ),
    );
    expect(running, isTrue);
  });

  test('errors that recur with no input still end the session', () async {
    final driver = FakeTerminalDriver(size: const CellSize(40, 6));
    await expectLater(
      runApp(
        const _Loop(),
        driver: driver,
        enableHotReload: false,
      ).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>()),
    );
    expect(driver.restoreCallCount, 1);
    await driver.dispose();
  });
}
