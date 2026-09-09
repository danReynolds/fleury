// Lock test (audit 14.c follow-up): browser Alt+digit shortcuts now emit
// KeyEvent(Alt+digit) via usTwin, but the split DOM path still delivers the
// Option glyph as a later TextInputEvent. InputDispatcher only arms
// `_suppressNextText` for unmodified/Shift printables (`splitText`), so a
// handled Alt chord does not keep the glyph out of a focused text field.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  test(
    'handled Alt+digit suppresses a following Option glyph on split DOM path',
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

      // Browser: keydown Alt+Digit1 mapped to Alt+'1', then (when the Option
      // glyph still reaches the textarea/`input` channel) TextInputEvent('¡').
      final keyResult = dispatcher.dispatch(
        const KeyEvent(
          KeyCode.char('1'),
          modifiers: {KeyModifier.alt},
          position: KeyPosition.digit1,
        ),
      );
      expect(keyResult, KeyEventResult.handled);
      expect(jumped, 1);

      dispatcher.dispatch(const TextInputEvent('¡'));
      expect(
        controller.text,
        isEmpty,
        reason:
            'a handled Alt chord must keep the Option glyph out of text; '
            'split-path `_suppressNextText` only arms for shift/unmodified '
            'printables and matches the US twin ("1"), not the glyph ("¡")',
      );
    },
  );

  test(
    'InputBatch Alt+digit with Option glyph text is suppressed when key handled',
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

      final result = dispatcher.dispatch(
        const InputBatch(
          key: KeyEvent(
            KeyCode.char('1'),
            modifiers: {KeyModifier.alt},
            position: KeyPosition.digit1,
          ),
          committedText: '¡',
        ),
      );
      expect(result, KeyEventResult.handled);
      expect(jumped, 1);
      expect(
        controller.text,
        isEmpty,
        reason: 'correlated batch already suppresses text when key is handled',
      );
    },
  );

  test(
    'unhandled Alt+digit still allows Option glyph text (Option typing)',
    () {
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
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      final keyResult = dispatcher.dispatch(
        const KeyEvent(
          KeyCode.char('1'),
          modifiers: {KeyModifier.alt},
          position: KeyPosition.digit1,
        ),
      );
      expect(keyResult, KeyEventResult.ignored);
      dispatcher.dispatch(const TextInputEvent('¡'));
      expect(
        controller.text,
        '¡',
        reason:
            'unbound Option chords must still type; only a handled Alt '
            'shortcut should suppress the glyph',
      );
    },
  );

  test(
    'handled Ctrl+char suppresses a following text half on split DOM path',
    () {
      final controller = TextEditingController();
      var saved = 0;
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
              KeyBinding(KeySequence.ctrl.s, onTrigger: (_) => saved++),
            ],
            child: TextInput(controller: controller, autofocus: true),
          ),
        ),
      );

      expect(
        dispatcher.dispatch(
          const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
        ),
        KeyEventResult.handled,
      );
      expect(saved, 1);
      dispatcher.dispatch(const TextInputEvent('s'));
      expect(
        controller.text,
        isEmpty,
        reason:
            'Ctrl chords share the same split-path gap if a text half still '
            'arrives after preventDefault fails or is skipped',
      );
    },
  );
}
