import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode keyCode, [Set<KeyModifier> modifiers = const {}]) {
  return KeyEvent(keyCode: keyCode, modifiers: modifiers);
}

KeyEvent _char(String char, [Set<KeyModifier> modifiers = const {}]) {
  return KeyEvent(char: char, modifiers: modifiers);
}

void main() {
  group('TextEditingKeymap', () {
    test('default single-line map resolves common editing chords', () {
      const keymap = TextEditingKeymap.defaultSingleLine;

      expect(
        keymap.resolve(_char('c', const {KeyModifier.ctrl})),
        TextEditingKeyAction.copy,
      );
      expect(
        keymap.resolve(_char('z', const {KeyModifier.ctrl})),
        TextEditingKeyAction.undo,
      );
      expect(
        keymap.resolve(_char('z', const {KeyModifier.ctrl, KeyModifier.shift})),
        TextEditingKeyAction.redo,
      );
      expect(
        keymap.resolve(_code(KeyCode.arrowLeft, const {KeyModifier.ctrl})),
        TextEditingKeyAction.moveWordLeft,
      );
      expect(
        keymap.resolve(_code(KeyCode.arrowRight, const {KeyModifier.alt})),
        TextEditingKeyAction.moveWordRight,
      );
      expect(
        keymap.resolve(_code(KeyCode.arrowLeft, const {KeyModifier.shift})),
        TextEditingKeyAction.moveLeft,
      );
      expect(
        keymap.resolve(_code(KeyCode.arrowUp, const {KeyModifier.shift})),
        isNull,
      );
    });

    test('default multiline map separates line and document movement', () {
      const keymap = TextEditingKeymap.defaultMultiline;

      expect(
        keymap.resolve(_code(KeyCode.home)),
        TextEditingKeyAction.moveLineStart,
      );
      expect(
        keymap.resolve(_code(KeyCode.home, const {KeyModifier.ctrl})),
        TextEditingKeyAction.moveDocumentStart,
      );
      expect(
        keymap.resolve(_code(KeyCode.enter)),
        TextEditingKeyAction.insertNewline,
      );
    });

    test(
      'Emacs presets add Ctrl-based movement without replacing defaults',
      () {
        const keymap = TextEditingKeymap.emacsSingleLine;

        expect(
          keymap.resolve(_char('a', const {KeyModifier.ctrl})),
          TextEditingKeyAction.moveDocumentStart,
        );
        expect(
          keymap.resolve(_char('e', const {KeyModifier.ctrl})),
          TextEditingKeyAction.moveDocumentEnd,
        );
        expect(
          keymap.resolve(_char('f', const {KeyModifier.alt})),
          TextEditingKeyAction.moveWordRight,
        );
        expect(
          keymap.resolve(_code(KeyCode.arrowRight)),
          TextEditingKeyAction.moveRight,
        );
      },
    );
  });
}
