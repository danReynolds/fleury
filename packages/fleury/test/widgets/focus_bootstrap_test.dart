// Keyboard bootstrap: a terminal is keyboard-primary, so key handling
// must work BEFORE anything is focused. These tests guard the
// architectural fix to FocusManager.activeChain() — when nothing is
// focused it falls back to a root chain of binding/handler-carrying
// nodes (deepest-first, modal-confined) instead of returning [].
//
// Without the fix: a top-level KeyBindings never fires, and the
// FocusTraversalGroup Tab binding that would let the user acquire focus
// is itself unreachable — a deadlock.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc, {bool shift = false}) =>
    KeyEvent(kc, modifiers: shift ? const {KeyModifier.shift} : const {});

void main() {
  group('keyboard bootstrap with nothing focused', () {
    testWidgets('a top-level KeyBindings fires before anything is focused', (
      tester,
    ) {
      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyCode.char('x'), onTrigger: () => fired++)],
          // Deliberately NO focusable descendant and no autofocus.
          child: const Text('no focus here'),
        ),
      );
      tester.render(size: const CellSize(20, 1));
      expect(
        tester.focusManager.focusedNode,
        isNull,
        reason: 'precondition: nothing is focused',
      );

      tester.sendKey(const KeyEvent(KeyCode.char('x')));
      expect(
        fired,
        1,
        reason: 'tree-level KeyBindings must fire with nothing focused',
      );
    });

    testWidgets('Tab bootstraps focus via FocusTraversalGroup', (tester) {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      tester.pumpWidget(
        FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: Focus(focusNode: a, child: const Text('a')),
              ),
              SizedBox(
                height: 1,
                child: Focus(focusNode: b, child: const Text('b')),
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(20, 2));
      expect(
        tester.focusManager.focusedNode,
        isNull,
        reason: 'precondition: nothing autofocused',
      );

      tester.sendKey(_code(KeyCode.tab));
      expect(
        a.hasFocus,
        isTrue,
        reason: 'Tab must be able to acquire focus from a cold start',
      );
    });

    testWidgets('deepest binding wins when several are in scope unfocused', (
      tester,
    ) {
      final order = <String>[];
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.char('x'), onTrigger: () => order.add('outer')),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(
                KeyCode.char('x'),
                onTrigger: () => order.add('inner'),
              ),
            ],
            child: const Text('nested'),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendKey(const KeyEvent(KeyCode.char('x')));
      expect(order, [
        'inner',
      ], reason: 'deepest binding consumes the event; outer never sees it');
    });
  });

  group('focusable widgets stay focus-gated (not ambient)', () {
    testWidgets('an unfocused Focus(onKey:) does NOT receive chords', (tester) {
      // A focusable interactive control (canRequestFocus: true) must only
      // handle chords while focused — the root fallback is for ambient
      // KeyBindings, not for waking up every Checkbox/Button on screen.
      var sawKey = 0;
      final node = FocusNode(debugLabel: 'control');
      tester.pumpWidget(
        Focus(
          focusNode: node,
          onKey: (_) {
            sawKey++;
            return KeyEventResult.handled;
          },
          child: const Text('control'),
        ),
      );
      tester.render(size: const CellSize(20, 1));
      expect(node.hasFocus, isFalse, reason: 'precondition: not focused');

      tester.sendKey(const KeyEvent(KeyCode.char(' ')));
      expect(
        sawKey,
        0,
        reason: 'a focusable control must stay silent until focused',
      );

      // Once focused, it handles chords as normal.
      node.requestFocus();
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.char(' ')));
      expect(sawKey, 1, reason: 'focused control handles chords');
    });
  });

  group('modal still confines unfocused key handling', () {
    testWidgets(
      'a binding outside an open modal does not fire when unfocused',
      (tester) {
        var outsideFired = 0;
        var insideFired = 0;
        tester.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 1,
                child: KeyBindings(
                  bindings: [
                    KeyBinding(
                      KeyCode.char('x'),
                      onTrigger: () => outsideFired++,
                    ),
                  ],
                  child: const Text('outside'),
                ),
              ),
              SizedBox(
                height: 1,
                child: FocusScope(
                  modal: true,
                  child: KeyBindings(
                    bindings: [
                      KeyBinding(
                        KeyCode.char('x'),
                        onTrigger: () => insideFired++,
                      ),
                    ],
                    child: const Text('inside modal'),
                  ),
                ),
              ),
            ],
          ),
        );
        tester.render(size: const CellSize(20, 2));

        tester.sendKey(const KeyEvent(KeyCode.char('x')));
        expect(insideFired, 1, reason: 'the in-modal binding fires');
        expect(
          outsideFired,
          0,
          reason: 'an open modal confines unfocused key handling too',
        );
      },
    );
  });
}
