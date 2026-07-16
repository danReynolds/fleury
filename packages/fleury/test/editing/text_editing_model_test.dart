import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('TextEditingValue', () {
    test('defaults selection to the end of the text', () {
      final value = TextEditingValue(text: 'hello');
      expect(value.selection, const TextSelection.collapsed(5));
    });

    test('snaps selection offsets to grapheme boundaries', () {
      final value = TextEditingValue(
        text: 'a🙂b',
        selection: const TextSelection.collapsed(2),
      );
      expect(value.selection, const TextSelection.collapsed(3));
    });
  });

  group('grapheme movement', () {
    test('moves across emoji as one editable character', () {
      var value = TextEditingValue(
        text: 'a🙂b',
        selection: const TextSelection.collapsed(3),
      );

      value = TextEditingModel.moveLeft(value);
      expect(value.selection.extentOffset, 1);

      value = TextEditingModel.moveRight(value);
      expect(value.selection.extentOffset, 3);
    });

    test('moves across combining sequences as one editable character', () {
      var value = TextEditingValue(
        text: 'e\u0301x',
        selection: const TextSelection.collapsed(2),
      );

      value = TextEditingModel.moveLeft(value);
      expect(value.selection.extentOffset, 0);

      value = TextEditingModel.moveRight(value);
      expect(value.selection.extentOffset, 2);
    });

    test('shift-style extension preserves the selection anchor', () {
      var value = TextEditingValue(
        text: 'a🙂b',
        selection: const TextSelection.collapsed(1),
      );

      value = TextEditingModel.moveRight(value, extend: true);
      expect(
        value.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );

      value = TextEditingModel.moveRight(value, extend: true);
      expect(
        value.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );

      value = TextEditingModel.moveLeft(value);
      expect(value.selection, const TextSelection.collapsed(1));
    });
  });

  group('editing operations', () {
    test('backspace deletes one grapheme before the cursor', () {
      final value = TextEditingModel.backspace(
        TextEditingValue(
          text: 'a🙂b',
          selection: const TextSelection.collapsed(3),
        ),
      );

      expect(value.text, 'ab');
      expect(value.selection, const TextSelection.collapsed(1));
    });

    test('delete removes one grapheme after the cursor', () {
      final value = TextEditingModel.delete(
        TextEditingValue(
          text: 'a🙂b',
          selection: const TextSelection.collapsed(1),
        ),
      );

      expect(value.text, 'ab');
      expect(value.selection, const TextSelection.collapsed(1));
    });

    test('insert replaces the selected range', () {
      final value = TextEditingModel.insert(
        TextEditingValue(
          text: 'abcd',
          selection: const TextSelection(baseOffset: 1, extentOffset: 3),
        ),
        'X',
      );

      expect(value.text, 'aXd');
      expect(value.selection, const TextSelection.collapsed(2));
    });

    test('replaceRange replaces an arbitrary range', () {
      final value = TextEditingModel.replaceRange(
        TextEditingValue(text: 'git che'),
        const TextRange(start: 4, end: 7),
        'checkout',
      );

      expect(value.text, 'git checkout');
      expect(value.selection, const TextSelection.collapsed(12));
    });

    test('single-line replaceRange collapses replacement newlines', () {
      final value = TextEditingModel.replaceRange(
        TextEditingValue(text: 'say word'),
        const TextRange(start: 4, end: 8),
        'one\ntwo',
        singleLine: true,
      );

      expect(value.text, 'say one two');
      expect(value.selection, const TextSelection.collapsed(11));
    });

    test('word movement skips whitespace-delimited grapheme runs', () {
      const text = 'run  deploy 🙂 now';
      var value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(text.length),
      );

      value = TextEditingModel.moveWordLeft(value);
      expect(value.selection, const TextSelection.collapsed(15));

      value = TextEditingModel.moveWordLeft(value);
      expect(value.selection, const TextSelection.collapsed(12));

      value = TextEditingModel.moveWordLeft(value);
      expect(value.selection, const TextSelection.collapsed(5));

      value = TextEditingModel.moveWordRight(value);
      expect(value.selection, const TextSelection.collapsed(11));

      value = TextEditingModel.moveWordRight(value);
      expect(value.selection, const TextSelection.collapsed(14));

      value = TextEditingValue(
        text: 'run deploy',
        selection: const TextSelection.collapsed(10),
      );
      value = TextEditingModel.moveWordLeft(value, extend: true);
      expect(
        value.selection,
        const TextSelection(baseOffset: 10, extentOffset: 4),
      );
    });

    test('single-line insert collapses pasted newlines to spaces', () {
      final value = TextEditingModel.insert(
        TextEditingValue.empty(),
        'one\ntwo\r\nthree',
        singleLine: true,
      );

      expect(value.text, 'one two three');
      expect(value.selection, TextSelection.collapsed(value.text.length));
    });

    test('multiline input canonicalizes clipboard line endings', () {
      expect(
        TextEditingModel.normalizeMultilineInput('one\r\ntwo\n\rthree\rfour'),
        'one\ntwo\nthree\nfour',
      );
      expect(
        TextEditingModel.normalizeMultilineInput('\r\n\r\n\r'),
        '\n\n\n',
        reason: 'adjacent separators must not be collapsed by a second pass',
      );
      expect(TextEditingModel.normalizeMultilineInput('\n\r\n'), '\n\n');
    });
  });

  group('composition operations', () {
    test(
      'updateComposing replaces the selection and marks composing range',
      () {
        final value = TextEditingModel.updateComposing(
          TextEditingValue(
            text: 'git che',
            selection: const TextSelection(baseOffset: 4, extentOffset: 7),
          ),
          'checkout',
        );

        expect(value.text, 'git checkout');
        expect(value.selection, const TextSelection.collapsed(12));
        expect(value.composing, const TextRange(start: 4, end: 12));
      },
    );

    test('updateComposing replaces the existing composing range', () {
      final first = TextEditingModel.updateComposing(
        TextEditingValue(text: 'say '),
        'に',
      );

      final second = TextEditingModel.updateComposing(first, '日本');

      expect(second.text, 'say 日本');
      expect(second.selection, const TextSelection.collapsed(6));
      expect(second.composing, const TextRange(start: 4, end: 6));
    });

    test('commitComposing clears composing state', () {
      final composing = TextEditingModel.updateComposing(
        TextEditingValue(text: 'run '),
        'deploy',
      );

      final committed = TextEditingModel.commitComposing(composing);

      expect(committed.text, 'run deploy');
      expect(committed.selection, const TextSelection.collapsed(10));
      expect(committed.composing, TextRange.empty);
    });

    test('commitComposing can replace the composing range', () {
      final composing = TextEditingModel.updateComposing(
        TextEditingValue(
          text: 'git che',
          selection: const TextSelection(baseOffset: 4, extentOffset: 7),
        ),
        'checkout',
      );

      final committed = TextEditingModel.commitComposing(
        composing,
        text: 'cherry-pick',
      );

      expect(committed.text, 'git cherry-pick');
      expect(committed.selection, const TextSelection.collapsed(15));
      expect(committed.composing, TextRange.empty);
    });

    test('single-line composing operations collapse newlines', () {
      final composing = TextEditingModel.updateComposing(
        TextEditingValue.empty(),
        'one\ntwo',
        singleLine: true,
      );

      expect(composing.text, 'one two');
      expect(composing.composing, const TextRange(start: 0, end: 7));

      final committed = TextEditingModel.commitComposing(
        composing,
        text: 'three\nfour',
        singleLine: true,
      );
      expect(committed.text, 'three four');
      expect(committed.composing, TextRange.empty);
    });

    test('setComposingRange snaps range edges to grapheme boundaries', () {
      final value = TextEditingModel.setComposingRange(
        TextEditingValue(text: 'a🙂b'),
        const TextRange(start: 2, end: 4),
      );

      expect(value.composing, const TextRange(start: 3, end: 4));
    });
  });

  group('line movement', () {
    test('moves up and down by grapheme column', () {
      var value = TextEditingValue(
        text: 'abcd\nxy\nw🙂z',
        selection: const TextSelection.collapsed(11),
      );

      value = TextEditingModel.moveLineUp(value);
      expect(value.selection, const TextSelection.collapsed(7));

      value = TextEditingModel.moveLineUp(value);
      expect(value.selection, const TextSelection.collapsed(2));

      value = TextEditingModel.moveLineDown(value);
      expect(value.selection, const TextSelection.collapsed(7));
    });

    test('line start and end stay on the current line', () {
      var value = TextEditingValue(
        text: 'hello\nworld',
        selection: const TextSelection.collapsed(8),
      );

      value = TextEditingModel.moveToLineStart(value);
      expect(value.selection, const TextSelection.collapsed(6));

      value = TextEditingModel.moveToLineEnd(value);
      expect(value.selection, const TextSelection.collapsed(11));
    });

    test('line movement can extend a range', () {
      final value = TextEditingModel.moveLineDown(
        TextEditingValue(
          text: 'ab\ncd',
          selection: const TextSelection.collapsed(0),
        ),
        extend: true,
      );

      expect(
        value.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
    });
  });
}
