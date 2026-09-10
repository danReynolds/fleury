import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode keyCode, [Set<KeyModifier> modifiers = const {}]) {
  return KeyEvent(keyCode, modifiers: modifiers);
}

KeyEvent _char(String char, [Set<KeyModifier> modifiers = const {}]) {
  return KeyEvent(KeyCode.char(char), modifiers: modifiers);
}

class _CollectingSink implements TuiEventSink {
  final events = <TuiEvent>[];

  @override
  void add(TuiEvent event) => events.add(event);
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

    test('chat map submits on Enter, newlines on Alt/Shift+Enter', () {
      const keymap = TextEditingKeymap.chat;

      // Plain Enter submits; the modifier chords insert a newline.
      expect(keymap.resolve(_code(KeyCode.enter)), TextEditingKeyAction.submit);
      expect(
        keymap.resolve(_code(KeyCode.enter, const {KeyModifier.alt})),
        TextEditingKeyAction.insertNewline,
      );
      expect(
        keymap.resolve(_code(KeyCode.enter, const {KeyModifier.shift})),
        TextEditingKeyAction.insertNewline,
      );
      // An unbound Enter chord (e.g. Ctrl+Enter) resolves to nothing rather
      // than falling through to the inherited plain-Enter newline.
      expect(
        keymap.resolve(_code(KeyCode.enter, const {KeyModifier.ctrl})),
        isNull,
      );
      // Everything else is the standard multiline map.
      expect(
        keymap.resolve(_code(KeyCode.arrowUp)),
        TextEditingKeyAction.moveUp,
      );
      expect(
        keymap.resolve(_code(KeyCode.home)),
        TextEditingKeyAction.moveLineStart,
      );
    });

    // Pins what the `chat` doc states outright. Alt+Enter on a legacy
    // (non-CSI-u) terminal — Terminal.app, xterm, gnome-terminal — is bare
    // ESC CR. The two bytes arriving in ONE read is the evidence that this is
    // a chord and not Escape-then-Enter: a human pressing Escape then Enter
    // is separated by the driver's ~30ms idle flush, which emits the lone ESC
    // as Escape first. Both halves are pinned below; if either changes, the
    // `chat` doc must be revisited rather than quietly going stale.
    test(
      'chat map inserts a newline on a legacy terminal Alt+Enter (ESC CR)',
      () {
        final sink = _CollectingSink();
        InputParser()
          ..feed(const <int>[0x1B, 0x0D], sink)
          ..flush(sink);

        expect(sink.events, hasLength(1));
        final event = sink.events.single as KeyEvent;
        expect(event.code, KeyCode.enter);
        expect(event.modifiers, {
          KeyModifier.alt,
        }, reason: 'one read means one chord, so the alt survives');
        expect(
          TextEditingKeymap.chat.resolve(event),
          TextEditingKeyAction.insertNewline,
          reason: 'so the chat preset inserts a newline, it does not submit',
        );
      },
    );

    test('a flushed Escape then Enter still submits, it is not Alt+Enter', () {
      final sink = _CollectingSink();
      final parser = InputParser();
      // Escape, then the idle flush a real keypress gap produces, then Enter.
      parser
        ..feed(const <int>[0x1B], sink)
        ..flush(sink)
        ..feed(const <int>[0x0D], sink)
        ..flush(sink);

      expect(sink.events, hasLength(2));
      expect((sink.events.first as KeyEvent).code, KeyCode.escape);
      final enter = sink.events.last as KeyEvent;
      expect(enter.code, KeyCode.enter);
      expect(
        enter.modifiers,
        isEmpty,
        reason: 'the flush separated them, so this is not a chord',
      );
      expect(
        TextEditingKeymap.chat.resolve(enter),
        TextEditingKeyAction.submit,
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
