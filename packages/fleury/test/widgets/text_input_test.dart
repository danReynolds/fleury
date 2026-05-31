// TextInput integration tests. Driven by FleuryTester so input
// dispatch + focus + scheduler are wired uniformly with every other
// widget test in the suite.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc) => KeyEvent(keyCode: kc);
KeyEvent _ctrlChar(String c) =>
    KeyEvent(char: c, modifiers: const {KeyModifier.ctrl});

void main() {
  group('TextInput receives insertable text', () {
    testWidgets('typing letters accumulates into the controller', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.type('h');
      tester.type('i');
      expect(controller.text, 'hi');
      expect(controller.selection, 2);
    });

    testWidgets('cursor advances with every character', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.type('a');
      expect(controller.selection, 1);
      tester.type('b');
      expect(controller.selection, 2);
    });
  });

  group('special chords', () {
    testWidgets('backspace deletes the previous character', (tester) {
      final controller = TextEditingController(text: 'hello');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.sendKey(_code(KeyCode.backspace));
      expect(controller.text, 'hell');
      expect(controller.selection, 4);
    });

    testWidgets('arrow chords move the cursor', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));
      expect(controller.selection, 3);

      tester.sendKey(_code(KeyCode.arrowLeft));
      expect(controller.selection, 2);
      tester.sendKey(_code(KeyCode.home));
      expect(controller.selection, 0);
      tester.sendKey(_code(KeyCode.end));
      expect(controller.selection, 3);
    });

    testWidgets('Enter fires onSubmit with the current text', (tester) {
      String? submitted;
      final controller = TextEditingController(text: 'send me');
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          onSubmit: (t) => submitted = t,
        ),
      );

      tester.sendKey(_code(KeyCode.enter));
      expect(submitted, 'send me');
    });

    testWidgets('Escape calls onEscape when provided', (tester) {
      var escapes = 0;
      tester.pumpWidget(
        TextInput(autofocus: true, onEscape: () => escapes += 1),
      );

      tester.sendKey(_code(KeyCode.escape));
      expect(escapes, 1);
    });

    testWidgets('Escape with no onEscape bubbles up to ancestor '
        'bindings', (tester) {
      var escapes = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.key(KeyCode.escape),
              onEvent: (_) => escapes += 1,
            ),
          ],
          child: const TextInput(autofocus: true),
        ),
      );

      tester.sendKey(_code(KeyCode.escape));
      expect(escapes, 1);
    });
  });

  group('modifier chord bypass', () {
    testWidgets('Ctrl+S reaches ancestor KeyBindings, NOT the text '
        'input', (tester) {
      // Per RFC 0008 §6.7: modifier chords are KeyEvents and travel
      // through the focus chain. They do NOT get claimed by the
      // text input.
      var saves = 0;
      final controller = TextEditingController();
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyChord.ctrl.s, onEvent: (_) => saves += 1)],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      tester.sendKey(_ctrlChar('s'));
      expect(saves, 1);
      // Text input did NOT receive 's' as a character.
      expect(controller.text, '');
    });
  });

  group('external focusNode', () {
    testWidgets('uses the supplied node and still claims text input', (tester) {
      final focusNode = FocusNode(debugLabel: 'external');
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(controller: controller, focusNode: focusNode),
      );
      focusNode.requestFocus();

      tester.type('x');
      expect(controller.text, 'x');
    });
  });

  group('text input precedence over leader sequences', () {
    testWidgets('typing space when a Space-leader sequence is bound '
        'elsewhere goes into the text input', (tester) {
      // Acceptance test #16 from RFC 0008 §9 — text input wins over
      // ancestor sequences.
      var paletteOpens = 0;
      final controller = TextEditingController();
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.space.p, onEvent: (_) => paletteOpens += 1),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      // Space arrives as a TextInputEvent (parser converts printable
      // ASCII this way). Text input claims it first; the ancestor
      // sequence binding never starts pending state.
      tester.type(' ');
      expect(controller.text, ' ');
      expect(paletteOpens, 0);
      expect(tester.dispatcher.hasPendingSequence, isFalse);
    });
  });

  group('bracketed paste', () {
    testWidgets(
      'a multi-line paste collapses to one line and does not submit',
      (tester) {
        final controller = TextEditingController();
        var submits = 0;
        tester.pumpWidget(
          TextInput(
            controller: controller,
            autofocus: true,
            onSubmit: (_) => submits++,
          ),
        );
        tester.paste('one\ntwo\nthree');
        expect(controller.text, 'one two three', reason: 'newlines → spaces');
        expect(submits, 0, reason: 'paste must never submit');
      },
    );
  });

  group('placeholder', () {
    testWidgets('shows the placeholder while empty, dimmed', (tester) {
      tester.pumpWidget(const TextInput(placeholder: 'search…'));
      final out = tester.renderToString(
        size: const CellSize(10, 1),
        emptyMark: ' ',
      );
      expect(out.trimRight(), 'search…');
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(1, 0).style.dim, isTrue, reason: 'placeholder dim');
    });

    testWidgets('typing replaces the placeholder with the text', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, placeholder: 'name'),
      );
      tester.type('A');
      final out = tester.renderToString(
        size: const CellSize(10, 1),
        emptyMark: ' ',
      );
      expect(out.contains('name'), isFalse, reason: 'placeholder gone');
      expect(out.trimRight(), 'A');
    });

    testWidgets('the cursor sits over the placeholder when focused', (tester) {
      tester.pumpWidget(
        const TextInput(autofocus: true, enableBlink: false, placeholder: 'go'),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      // First placeholder cell carries the cursor (inverse) merged onto dim.
      expect(buf.atColRow(0, 0).grapheme, 'g');
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
      expect(buf.atColRow(1, 0).style.inverse, isFalse);
    });
  });
}
