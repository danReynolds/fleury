// A command's shortcut asks its `visible`/`enabled` predicates when its key
// is pressed, as the palette, semantics and invoke do. The predicates read
// app state that the command's scope does not rebuild for (FleuryApp is
// usually the never-rebuilt root), so a snapshot taken at build left a dead
// shortcut on a command that became enabled, and a key-swallowing one on a
// command that became disabled. The hint bar asks the same predicates, and
// follows them without a rebuild of the scope.
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
}
