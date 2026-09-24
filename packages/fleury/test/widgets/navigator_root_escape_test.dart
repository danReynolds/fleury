// A route's Esc binding pops the navigator. At the root there is nothing to
// pop, so the key is not the route's: it bubbles to whatever binds Esc above
// the navigator. It used to be consumed there, silencing every app-level
// Esc command (FleuryApp wraps `home` in a Navigator), the Toaster's Esc
// dismiss, and Esc out of a nested navigator.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

const _esc = KeyEvent(KeyCode.escape);
const _transition = Duration(milliseconds: 300);

Widget _screen(String label) => Focus(autofocus: true, child: Text(label));

Widget _withEscBinding(void Function() onEsc, Widget child) => KeyBindings(
  bindings: [KeyBinding(KeySequence.escape, onTrigger: (_) => onEsc())],
  child: child,
);

void main() {
  testWidgets('Esc at the root reaches a binding above the navigator', (
    tester,
  ) {
    var hits = 0;
    tester.pumpWidget(
      _withEscBinding(() => hits++, Navigator(home: _screen('home'))),
    );
    tester.pump();

    tester.sendKey(_esc);

    expect(hits, 1);
  });

  testWidgets('a pushed route still pops on Esc, and keeps the key', (
    tester,
  ) {
    var hits = 0;
    tester.pumpWidget(
      _withEscBinding(() => hits++, Navigator(home: _screen('home'))),
    );
    final navigator = tester.binding.rootNavigator!;
    navigator.push<void>(_screen('page'));
    tester.pump(_transition);

    tester.sendKey(_esc);
    tester.pump(_transition);

    expect(navigator.depth, 1);
    expect(hits, 0);
  });

  testWidgets('a blocking PopScope at the root still takes Esc', (tester) {
    var hits = 0;
    var blocked = 0;
    tester.pumpWidget(
      _withEscBinding(
        () => hits++,
        Navigator(
          home: PopScope(
            canPop: false,
            onBlocked: () => blocked++,
            child: _screen('home'),
          ),
        ),
      ),
    );
    tester.pump();

    tester.sendKey(_esc);

    expect(blocked, 1, reason: 'the guard intercepts a would-be exit');
    expect(hits, 0);
  });

  testWidgets('Esc at a nested navigator root pops the outer navigator', (
    tester,
  ) {
    tester.pumpWidget(Navigator(home: _screen('home')));
    final outer = tester.binding.rootNavigator!;
    outer.push<void>(Navigator(home: _screen('inner')));
    tester.pump(_transition);
    expect(outer.depth, 2);

    tester.sendKey(_esc);
    tester.pump(_transition);

    expect(outer.depth, 1);
  });

  testWidgets('a FleuryApp Esc command fires from the home screen', (tester) {
    var ran = 0;
    tester.pumpWidget(
      FleuryApp(
        title: 'Test',
        commands: [
          AppCommand(
            id: const CommandId('app.back-out'),
            title: 'Back out',
            shortcuts: [KeySequence.escape],
            run: (_) => ran++,
          ),
        ],
        home: _screen('home'),
      ),
    );
    tester.pump();

    tester.sendKey(_esc);

    expect(ran, 1);
  });
}
