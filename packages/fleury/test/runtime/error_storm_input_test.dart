// runApp ends the session on a storm of uncaught errors: errors that recur
// with nothing to cause them, a loop that would otherwise spin forever. An
// error that follows input is one the user stops by stopping — a held
// shortcut whose command fails, fast typing into a field whose async handler
// fails — so it is reported and the session keeps running. Bare pointer
// motion is not such input: it must not keep a genuine loop alive.
import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

const _ctrlZ = KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl});
const _ctrlC = KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl});

const _body = Focus(autofocus: true, child: Text('body'));

/// Sends 30 events from [input] to [app], then quits with Ctrl+C. Returns
/// whether the session was still running after them, and how many errors
/// it reported (runApp logs each to stderr).
Future<({bool running, int reported})> _burst(
  Widget app,
  TuiEvent Function(int i) input,
) async {
  final logged = _StderrCapture();
  late bool running;
  await IOOverrides.runZoned(() async {
    final driver = FakeTerminalDriver(size: const CellSize(40, 6));
    final errors = <Object>[];
    final run = runApp(
      app,
      driver: driver,
      enableHotReload: false,
    ).then<void>((_) {}, onError: (Object error) => errors.add(error));
    await _settle();
    for (var i = 0; i < 30; i++) {
      driver.enqueue(input(i));
    }
    await _settle();
    await _settle();
    running = driver.isActive;
    if (running) driver.enqueue(_ctrlC);
    await run.timeout(const Duration(seconds: 5));
    await driver.dispose();
    expect(errors, running ? isEmpty : isNotEmpty);
  }, stderr: () => logged);
  return (
    running: running,
    reported: 'Uncaught runtime error'.allMatches(logged.text).length,
  );
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

/// Runs the error loop with [input] arriving meanwhile; expects the storm
/// rule to end the session.
Future<void> _expectLoopEnds({TuiEvent Function(int tick)? input}) async {
  final logged = _StderrCapture();
  await IOOverrides.runZoned(() async {
    final driver = FakeTerminalDriver(size: const CellSize(40, 6));
    final run = runApp(
      const _Loop(),
      driver: driver,
      enableHotReload: false,
    ).timeout(const Duration(seconds: 5));
    final ticker = input == null
        ? null
        : Timer.periodic(
            const Duration(milliseconds: 2),
            (timer) => driver.enqueue(input(timer.tick)),
          );
    try {
      await expectLater(run, throwsA(isA<StateError>()));
    } finally {
      ticker?.cancel();
    }
    expect(driver.restoreCallCount, 1);
    await driver.dispose();
  }, stderr: () => logged);
}

void main() {
  test('holding the shortcut of a failing command keeps the session', () async {
    final result = await _burst(
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
      (_) => _ctrlZ,
    );

    expect(result.running, isTrue);
    expect(result.reported, 30, reason: 'each failure is reported');
  });

  test('holding a key whose async handler fails keeps the session', () async {
    final result = await _burst(
      KeyBindings(
        bindings: [
          KeyBinding(
            KeySequence.ctrl.z,
            onTrigger: (_) async => throw StateError('offline'),
          ),
        ],
        child: _body,
      ),
      (_) => _ctrlZ,
    );

    expect(result.running, isTrue);
    expect(result.reported, 30);
  });

  test(
    'typing fast into a field whose handler fails keeps the session',
    () async {
      final result = await _burst(
        TextInput(
          autofocus: true,
          onChanged: (_) async => throw StateError('search is offline'),
        ),
        (i) => TextInputEvent(String.fromCharCode(0x61 + i % 26)),
      );

      expect(result.running, isTrue);
      expect(result.reported, 30);
    },
  );

  test('errors that recur with no input still end the session', () async {
    await _expectLoopEnds();
  });

  test('pointer motion does not keep an error loop alive', () async {
    await _expectLoopEnds(
      input: (tick) => MouseEvent(
        kind: MouseEventKind.moved,
        button: MouseButton.none,
        col: tick % 40,
        row: 1,
      ),
    );
  });
}

class _StderrCapture implements Stdout {
  final StringBuffer _buffer = StringBuffer();
  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
  @override
  void write(Object? object) => _buffer.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
