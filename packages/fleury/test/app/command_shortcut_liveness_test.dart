// A command's shortcut asks its `visible`/`enabled` predicates when its key
// is pressed, as the palette, semantics and invoke do. The predicates read
// app state that the command's scope does not rebuild for (FleuryApp is
// usually the never-rebuilt root), so a snapshot taken at build left a dead
// shortcut on a command that became enabled, and a key-swallowing one on a
// command that became disabled. The hint bar asks the same predicates, and
// follows them without a rebuild of the scope.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

const _undo = CommandId('edit.undo');

final class _History with Notifier {
  bool _canUndo = false;
  bool get canUndo => _canUndo;
  set canUndo(bool value) {
    _canUndo = value;
    notify();
  }

  bool _canSee = true;
  bool get canSee => _canSee;
  set canSee(bool value) {
    _canSee = value;
    notify();
  }

  var undos = 0;
}

AppCommand _undoCommand(_History history) => AppCommand(
  id: _undo,
  title: 'Undo',
  shortcuts: [KeySequence.ctrl.z],
  visible: (_) => history.canSee,
  enabled: (_) => history.canUndo,
  run: (_) => history.undos++,
);

/// The state lives below the command's scope, so nothing rebuilds the scope
/// when it changes.
Widget _body(_History history) => NotifierBuilder(
  notifier: history,
  builder: (_, history) =>
      Focus(autofocus: true, child: Text('canUndo=${history.canUndo}')),
);

const _ctrlZ = KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl});

final class _Capture extends StatelessWidget {
  const _Capture(this.onBuild);

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const Text('');
  }
}

/// Reads the active bindings as a hint bar does.
final class _Hints extends StatelessWidget {
  const _Hints();

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final hint in KeyBindings.activeOf(context)) hint.binding.label,
    ];
    return Text('hints: ${labels.join(', ')}');
  }
}

String _hintLine(FleuryTester tester) => tester
    .renderToString(size: const CellSize(40, 4))
    .split('\n')
    .firstWhere((line) => line.startsWith('hints:'));

void main() {
  testWidgets(
    'observable command availability refreshes without idle polling',
    (tester) {
      final history = _History();
      var reads = 0;
      tester.pumpWidget(
        FleuryApp(
          title: 'Observable',
          commands: [
            AppCommand(
              id: _undo,
              title: 'Undo',
              shortcuts: [KeySequence.ctrl.z],
              availability: history,
              enabled: (_) {
                reads++;
                return history.canUndo;
              },
              run: (_) => history.undos++,
            ),
          ],
          home: Column(children: [_body(history), const _Hints()]),
        ),
      );
      tester.pump();
      reads = 0;
      for (var i = 0; i < 20; i++) {
        tester.pump();
      }
      expect(
        reads,
        0,
        reason: 'unchanged frames do not poll observable predicates',
      );
      history.canUndo = true;
      tester.pump();
      expect(_hintLine(tester), contains('Undo'));
      history.canUndo = false;
      tester.sendKey(
        _ctrlZ,
      ); // Dispatch before a frame still reads current state.
      expect(history.undos, 0);
      tester.pump();
      expect(_hintLine(tester), isNot(contains('Undo')));
    },
  );

  testWidgets('an app command enabled after build fires on its shortcut', (
    tester,
  ) {
    final history = _History();
    tester.pumpWidget(
      FleuryApp(
        title: 'Test',
        commands: [_undoCommand(history)],
        home: _body(history),
      ),
    );
    tester.pump();

    history.canUndo = true;
    tester.pump();
    tester.sendKey(_ctrlZ);

    expect(history.undos, 1);
  });

  testWidgets('a scoped command enabled after build fires on its shortcut', (
    tester,
  ) {
    final history = _History();
    tester.pumpWidget(
      CommandScope(commands: [_undoCommand(history)], child: _body(history)),
    );
    tester.pump();

    history.canUndo = true;
    tester.pump();
    tester.sendKey(_ctrlZ);

    expect(history.undos, 1);
  });

  testWidgets('a command disabled after build lets its key bubble', (tester) {
    final history = _History()..canUndo = true;
    var outer = 0;
    tester.pumpWidget(
      KeyBindings(
        bindings: [KeyBinding(KeySequence.ctrl.z, onTrigger: (_) => outer++)],
        child: CommandScope(
          commands: [_undoCommand(history)],
          child: _body(history),
        ),
      ),
    );
    tester.pump();

    history.canUndo = false;
    tester.pump();
    tester.sendKey(_ctrlZ);

    expect(history.undos, 0);
    expect(outer, 1, reason: 'the outer binding gets the key');
  });

  testWidgets('an app command hidden after build lets its key bubble', (
    tester,
  ) {
    final history = _History()..canUndo = true;
    var outer = 0;
    tester.pumpWidget(
      KeyBindings(
        bindings: [KeyBinding(KeySequence.ctrl.z, onTrigger: (_) => outer++)],
        child: FleuryApp(
          title: 'Test',
          commands: [_undoCommand(history)],
          home: _body(history),
        ),
      ),
    );
    tester.pump();

    history.canSee = false;
    tester.pump();
    tester.sendKey(_ctrlZ);

    expect(history.undos, 0);
    expect(outer, 1, reason: 'the outer binding gets the key');
  });

  testWidgets('a command made visible after build gets its shortcut', (tester) {
    final history = _History()
      ..canSee = false
      ..canUndo = true;
    tester.pumpWidget(
      CommandScope(commands: [_undoCommand(history)], child: _body(history)),
    );
    tester.pump();
    tester.sendKey(_ctrlZ);
    expect(history.undos, 0, reason: 'hidden');

    history.canSee = true;
    tester.pump();
    tester.sendKey(_ctrlZ);

    expect(history.undos, 1);
  });

  testWidgets('the hint bar shows an app command while it is enabled', (
    tester,
  ) {
    final history = _History();
    tester.pumpWidget(
      FleuryApp(
        title: 'Test',
        commands: [_undoCommand(history)],
        home: Column(children: [_body(history), const _Hints()]),
      ),
    );
    tester.pump();
    expect(_hintLine(tester), isNot(contains('Undo')));

    history.canUndo = true;
    tester.pump();
    expect(_hintLine(tester), contains('Undo'));

    history.canUndo = false;
    tester.pump();
    expect(_hintLine(tester), isNot(contains('Undo')));
  });

  testWidgets('the hint bar shows a scoped command while it is visible', (
    tester,
  ) {
    final history = _History()
      ..canSee = false
      ..canUndo = true;
    tester.pumpWidget(
      CommandScope(
        commands: [_undoCommand(history)],
        child: Column(children: [_body(history), const _Hints()]),
      ),
    );
    tester.pump();
    expect(_hintLine(tester), isNot(contains('Undo')));

    history.canSee = true;
    tester.pump();
    expect(_hintLine(tester), contains('Undo'));

    history.canSee = false;
    tester.pump();
    expect(_hintLine(tester), isNot(contains('Undo')));
  });

  testWidgets('the hint bar follows a scope rebuilt with the state', (tester) {
    final history = _History();
    tester.pumpWidget(
      NotifierBuilder(
        notifier: history,
        builder: (_, history) => CommandScope(
          commands: [_undoCommand(history)],
          child: const Column(
            children: [
              Focus(autofocus: true, child: Text('doc')),
              _Hints(),
            ],
          ),
        ),
      ),
    );
    tester.pump();
    expect(_hintLine(tester), isNot(contains('Undo')));

    history.canUndo = true;
    tester.pump();
    expect(_hintLine(tester), contains('Undo'));
  });

  test(
    'in a running app, a hint follows a change nothing rebuilt for',
    () async {
      // runApp skips a frame with no work; the recheck runs before that skip,
      // so an unrelated key's frame shows the command becoming available.
      final history = _History();
      final driver = FakeTerminalDriver(size: const CellSize(40, 4));
      final run = runApp(
        FleuryApp(
          title: 'Test',
          commands: [_undoCommand(history)],
          home: const Column(
            children: [
              Focus(autofocus: true, child: Text('doc')),
              _Hints(),
            ],
          ),
        ),
        driver: driver,
        enableHotReload: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(driver.output, isNot(contains('Undo')));

      history._canUndo = true; // no notify: nothing rebuilds for it
      driver.clearOutput();
      driver.enqueue(const KeyEvent(KeyCode.f7));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(driver.output, contains('Undo'));
      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await run.timeout(const Duration(seconds: 5));
      await driver.dispose();
    },
  );

  testWidgets('a resolution outside a build does not absorb a change', (
    tester,
  ) {
    final history = _History();
    tester.pumpWidget(
      FleuryApp(
        title: 'Test',
        commands: [_undoCommand(history)],
        home: Column(children: [_body(history), const _Hints()]),
      ),
    );
    tester.pump();
    expect(_hintLine(tester), isNot(contains('Undo')));

    history._canUndo = true;
    // A key's dispatch or a test reading the bindings resolves them too.
    expect([
      for (final hint in resolveActiveKeyBindings(tester.focusManager))
        hint.binding.label,
    ], contains('Undo'));
    tester.pump();

    expect(_hintLine(tester), contains('Undo'));
  });

  testWidgets('a removed hint surface stops asking the predicates', (tester) {
    var asks = 0;
    final shown = ValueNotifier(true);
    tester.pumpWidget(
      CommandScope(
        commands: [
          AppCommand(
            id: _undo,
            title: 'Undo',
            shortcuts: [KeySequence.ctrl.z],
            enabled: (_) {
              asks++;
              return true;
            },
            run: (_) {},
          ),
        ],
        child: Column(
          children: [
            const Focus(autofocus: true, child: Text('doc')),
            NotifierBuilder(
              notifier: shown,
              builder: (_, shown) =>
                  shown.value ? const _Hints() : const Text('no hints'),
            ),
          ],
        ),
      ),
    );
    tester.pump();
    shown.value = false;
    tester.pump();

    asks = 0;
    for (var i = 0; i < 5; i++) {
      tester.pump();
    }

    expect(asks, 0);
  });

  testWidgets('a key sequence step asks only the commands still in play', (
    tester,
  ) {
    var asks = 0;
    var jumps = 0;
    bool counted(CommandContext _) {
      asks++;
      return true;
    }

    tester.pumpWidget(
      CommandScope(
        commands: [
          for (var i = 0; i < 20; i++)
            AppCommand(
              id: CommandId('c$i'),
              title: 'C$i',
              shortcuts: [
                KeySequence.fromEvent(
                  KeyEvent(
                    KeyCode.char(String.fromCharCode(97 + i)),
                    modifiers: const {KeyModifier.alt},
                  ),
                ),
              ],
              enabled: counted,
              run: (_) {},
            ),
          AppCommand(
            id: const CommandId('top'),
            title: 'Top',
            shortcuts: [KeySequence.g.g],
            enabled: counted,
            run: (_) => jumps++,
          ),
        ],
        child: const Focus(autofocus: true, child: Text('doc')),
      ),
    );
    tester.pump();

    tester.sendKey(const KeyEvent(KeyCode.g));
    asks = 0;
    tester.sendKey(const KeyEvent(KeyCode.g));

    expect(jumps, 1);
    expect(asks, lessThan(4), reason: '$asks predicate asks');
  });

  testWidgets('focus a command was asked about does not follow the app', (
    tester,
  ) {
    // The hint bar asks each command's predicates with the focused element
    // as their context. That must not subscribe every element that held
    // focus to the app, which notifies on every command result and status.
    late BuildContext context;
    tester.pumpWidget(
      FleuryApp(
        title: 'Test',
        commands: [_undoCommand(_History()..canUndo = true)],
        home: Column(
          children: [
            for (var i = 0; i < 10; i++)
              Button(text: 'B$i', autofocus: i == 0, onPressed: () {}),
            const _Hints(),
            _Capture((c) => context = c),
            const AppStatusBar(emptyText: 'Idle'),
          ],
        ),
      ),
    );
    tester.pump();
    for (var i = 0; i < 9; i++) {
      tester.focusManager.focusNext();
      tester.pump();
    }
    tester.owner.flushBuild();

    FleuryApp.of(context).status.put(StatusItem.text('Build', value: 'ok'));
    final rebuilt = tester.owner.flushBuild().rebuiltElementCount;

    expect(rebuilt, lessThan(5), reason: 'rebuilt $rebuilt elements');
  });

  testWidgets('a predicate that throws on recheck is left to the surface', (
    tester,
  ) {
    var fail = false;
    tester.pumpWidget(
      CommandScope(
        commands: [
          AppCommand(
            id: _undo,
            title: 'Undo',
            shortcuts: [KeySequence.ctrl.z],
            enabled: (_) {
              if (fail) throw StateError('predicate boom');
              return true;
            },
            run: (_) {},
          ),
        ],
        child: const Column(
          children: [
            Focus(autofocus: true, child: Text('doc')),
            _Hints(),
          ],
        ),
      ),
    );
    tester.pump();
    var notified = 0;
    tester.focusManager.addListener(() => notified++);

    fail = true;
    // Returns normally: the surface's own rebuild reports the throw.
    tester.focusManager.recheckLiveAnswers();
    expect(notified, 1);
    tester.focusManager.recheckLiveAnswers();
    expect(notified, 1, reason: 'the surface records afresh when it rebuilds');
  });

  for (final scoped in [false, true]) {
    testWidgets('a held ${scoped ? 'scoped' : 'app'} shortcut runs once', (
      tester,
    ) {
      final history = _History()..canUndo = true;
      final commands = [_undoCommand(history)];
      tester.pumpWidget(
        scoped
            ? CommandScope(commands: commands, child: _body(history))
            : FleuryApp(
                title: 'Test',
                commands: commands,
                home: _body(history),
              ),
      );
      tester.pump();

      tester.sendKey(_ctrlZ);
      for (var i = 0; i < 3; i++) {
        tester.sendKey(
          const KeyEvent(
            KeyCode.z,
            modifiers: {KeyModifier.ctrl},
            type: KeyEventType.repeat,
          ),
        );
      }

      expect(history.undos, 1);
    });
  }

  testWidgets('every shortcut of a command runs it', (tester) {
    final history = _History()..canUndo = true;
    tester.pumpWidget(
      CommandScope(
        commands: [
          AppCommand(
            id: _undo,
            title: 'Undo',
            shortcuts: [KeySequence.ctrl.z, KeySequence.ctrl.u],
            enabled: (_) => history.canUndo,
            run: (_) => history.undos++,
          ),
        ],
        child: _body(history),
      ),
    );
    tester.pump();

    tester.sendKey(_ctrlZ);
    tester.sendKey(const KeyEvent(KeyCode.u, modifiers: {KeyModifier.ctrl}));

    expect(history.undos, 2);
  });
}
