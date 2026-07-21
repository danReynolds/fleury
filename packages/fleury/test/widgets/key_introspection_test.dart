import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Reads [KeyBindings.pendingOf] on every build and reports it.
class _PendingProbe extends StatelessWidget {
  const _PendingProbe({required this.onBuild, required this.child});
  final void Function(PendingKeySequenceMatch?) onBuild;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onBuild(KeyBindings.pendingOf(context));
    return child;
  }
}

/// Reads [KeyBindings.activeOf] on every build and reports it.
class _ActiveProbe extends StatelessWidget {
  const _ActiveProbe({required this.onBuild, required this.child});
  final void Function(List<ActiveKeyBinding>) onBuild;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    onBuild(KeyBindings.activeOf(context));
    return child;
  }
}

void main() {
  group('KeyBindings.pendingOf', () {
    testWidgets('tracks a leader sequence: start → complete', (tester) {
      PendingKeySequenceMatch? pending;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.f,
              label: 'Find file',
              onTrigger: () {},
            ),
            KeyBinding(KeySequence.space.b, label: 'Buffers', onTrigger: () {}),
          ],
          child: _PendingProbe(
            onBuild: (p) => pending = p,
            child: const Focus(autofocus: true, child: Text('x')),
          ),
        ),
      );
      tester.render();
      expect(pending, isNull, reason: 'nothing pending at rest');

      tester.press(KeySequence.space); // leader
      expect(pending, isNotNull);
      expect(pending!.prefix, KeySequence.space);
      expect(pending!.prefix.hintLabel, 'Space');
      expect(
        pending!.completions.map((c) => c.next),
        containsAll(<String>['f', 'b']),
      );
      expect(
        pending!.completions.map((c) => c.binding.displayLabel),
        containsAll(<String>['Find file', 'Buffers']),
      );

      tester.press(KeySequence.f); // completes .space.f
      expect(pending, isNull, reason: 'cleared once the sequence fires');
    });

    testWidgets('a non-matching key cancels the pending sequence', (tester) {
      PendingKeySequenceMatch? pending;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.f,
              label: 'Find file',
              onTrigger: () {},
            ),
          ],
          child: _PendingProbe(
            onBuild: (p) => pending = p,
            child: const Focus(autofocus: true, child: Text('x')),
          ),
        ),
      );
      tester.render();

      tester.press(KeySequence.space);
      expect(pending, isNotNull);
      tester.press(KeySequence.x); // no .space.x → cancel
      expect(pending, isNull);
    });

    testWidgets('advances through a multi-step chord', (tester) {
      PendingKeySequenceMatch? pending;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.x.ctrl.s,
              label: 'Save',
              onTrigger: () {},
            ),
          ],
          child: _PendingProbe(
            onBuild: (p) => pending = p,
            child: const Focus(autofocus: true, child: Text('x')),
          ),
        ),
      );
      tester.render();

      tester.sendKey(
        const KeyEvent(KeyCode.char('x'), modifiers: {KeyModifier.ctrl}),
      );
      expect(pending, isNotNull);
      expect(pending!.prefix.hintLabel, 'Ctrl+X');
      expect(pending!.completions.single.next, 'Ctrl+S');

      tester.sendKey(
        const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
      );
      expect(pending, isNull);
    });
  });

  group('KeyBindings.activeOf', () {
    testWidgets('lists the labeled bindings active in context', (tester) {
      List<ActiveKeyBinding> active = const [];
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.s, label: 'Save', onTrigger: () {}),
            KeyBinding(KeyCode.enter, label: 'Open', onTrigger: () {}),
            KeyBinding(
              KeyCode.char('z'),
              onTrigger: () {},
            ), // unlabeled — hidden
          ],
          child: _ActiveProbe(
            onBuild: (a) => active = a,
            child: const Focus(autofocus: true, child: Text('x')),
          ),
        ),
      );
      tester.render();

      final labels = active.map((a) => a.binding.displayLabel).toList();
      expect(labels, containsAll(<String>['Save', 'Open']));
      expect(labels, isNot(contains(anyOf('z', 'Z'))));
    });
  });

  group('tester.press speaks the DSL', () {
    testWidgets('fires single, chord, and multi-step bindings', (tester) {
      final fired = <String>[];
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.enter,
              label: 'e',
              onTrigger: () => fired.add('enter'),
            ),
            KeyBinding(
              KeySequence.ctrl.s,
              label: 's',
              onTrigger: () => fired.add('save'),
            ),
            KeyBinding(
              KeySequence.g.g,
              label: 'gg',
              onTrigger: () => fired.add('gg'),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('x')),
        ),
      );
      tester.render();

      tester.press(KeyCode.enter);
      tester.press(KeySequence.ctrl.s);
      tester.press(KeySequence.g.g);
      expect(fired, <String>['enter', 'save', 'gg']);
    });

    testWidgets('a bare printable step routes as text into a field', (tester) {
      final controller = TextEditingController();
      var bindingFired = false;
      tester.pumpWidget(
        KeyBindings(
          // A bare `a` binding must NOT fire while the field is focused — the
          // press routes as text, exactly as a terminal delivers it.
          bindings: [
            KeyBinding(KeyCode.char('a'), onTrigger: () => bindingFired = true),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );
      tester.render();

      tester.press(KeyCode.char('a'));
      expect(controller.text, 'a');
      expect(bindingFired, isFalse);
    });
  });
}
