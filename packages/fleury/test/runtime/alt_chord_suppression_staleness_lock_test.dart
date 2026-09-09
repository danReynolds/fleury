// Lock test: the one-shot suppression armed by a handled Alt/Ctrl printable
// belongs to THAT press only. Off macOS the browser emits no `input` event for
// Alt+digit, so the armed suppression must not survive to eat the next
// character the user types.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  test(
    'an unpaid Alt-chord suppression does not eat the next typed character',
    () {
      final controller = TextEditingController();
      var jumped = 0;
      final manager = FocusManager();
      final dispatcher = InputDispatcher(
        focusManager: manager,
        sequenceTimeout: const Duration(milliseconds: 50),
      );
      dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.full);
      final owner = BuildOwner();
      owner.mountRoot(
        FocusManagerScope(
          manager: manager,
          child: KeyBindings(
            bindings: [
              KeyBinding(KeySequence.alt.char('1'), onTrigger: (_) => jumped++),
            ],
            child: TextInput(controller: controller, autofocus: true),
          ),
        ),
      );

      // Handled Alt+1 arms the any-next suppression for the Option glyph...
      expect(
        dispatcher.dispatch(
          const KeyEvent(
            KeyCode.char('1'),
            modifiers: {KeyModifier.alt},
            position: KeyPosition.digit1,
          ),
        ),
        KeyEventResult.handled,
      );
      expect(jumped, 1);

      // ...but Chrome/Firefox off macOS never send one. The next press is the
      // proof that the pairing window closed.
      dispatcher.dispatch(
        const KeyEvent(KeyCode.char('a'), position: KeyPosition.a),
      );
      dispatcher.dispatch(const TextInputEvent('a'));

      expect(
        controller.text,
        'a',
        reason:
            'the suppression was armed for the Alt+1 press; a later, unrelated '
            'insertion must still reach the field',
      );
    },
  );

  test('the paired Option glyph is still suppressed when it does arrive', () {
    final controller = TextEditingController();
    final manager = FocusManager();
    final dispatcher = InputDispatcher(
      focusManager: manager,
      sequenceTimeout: const Duration(milliseconds: 50),
    );
    dispatcher.updateKeyboardCapabilities(KeyboardCapabilities.full);
    final owner = BuildOwner();
    owner.mountRoot(
      FocusManagerScope(
        manager: manager,
        child: KeyBindings(
          bindings: [KeyBinding(KeySequence.alt.char('1'), onTrigger: (_) {})],
          child: TextInput(controller: controller, autofocus: true),
        ),
      ),
    );

    dispatcher.dispatch(
      const KeyEvent(
        KeyCode.char('1'),
        modifiers: {KeyModifier.alt},
        position: KeyPosition.digit1,
      ),
    );
    dispatcher.dispatch(const TextInputEvent('¡'));
    dispatcher.dispatch(
      const KeyEvent(KeyCode.char('a'), position: KeyPosition.a),
    );
    dispatcher.dispatch(const TextInputEvent('a'));

    expect(controller.text, 'a');
  });
}
