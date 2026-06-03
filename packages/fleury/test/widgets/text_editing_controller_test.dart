import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TextEditingController construction', () {
    test('default empty text and cursor at 0', () {
      final c = TextEditingController();
      expect(c.text, '');
      expect(c.selection, 0);
    });

    test('initial text puts cursor at end', () {
      final c = TextEditingController(text: 'hello');
      expect(c.text, 'hello');
      expect(c.selection, 5);
    });
  });

  group('text setter', () {
    test('updates and notifies', () {
      final c = TextEditingController();
      var fires = 0;
      c.addListener(() => fires += 1);

      c.text = 'hi';

      expect(c.text, 'hi');
      expect(fires, 1);
    });

    test('clamps selection to new length', () {
      final c = TextEditingController(text: 'hello');
      expect(c.selection, 5);
      c.text = 'hi';
      expect(c.selection, 2);
    });

    test('no-op on identical text', () {
      final c = TextEditingController(text: 'hi');
      var fires = 0;
      c.addListener(() => fires += 1);
      c.text = 'hi';
      expect(fires, 0);
    });
  });

  group('selection setter', () {
    test('clamps to text bounds', () {
      final c = TextEditingController(text: 'abc');
      c.selection = 99;
      expect(c.selection, 3);
      c.selection = -1;
      expect(c.selection, 0);
    });

    test('notifies on change', () {
      final c = TextEditingController(text: 'abc');
      c.selection = 0;
      var fires = 0;
      c.addListener(() => fires += 1);
      c.selection = 1;
      expect(fires, 1);
    });
  });

  group('insert', () {
    test('inserts at cursor and advances', () {
      final c = TextEditingController(text: 'hello');
      c.selection = 2; // h e | l l o
      c.insert('X');
      expect(c.text, 'heXllo');
      expect(c.selection, 3);
    });

    test('empty insert is a no-op', () {
      final c = TextEditingController(text: 'hi');
      var fires = 0;
      c.addListener(() => fires += 1);
      c.insert('');
      expect(c.text, 'hi');
      expect(fires, 0);
    });

    test('multi-char insert advances by length', () {
      final c = TextEditingController()..insert('hello');
      expect(c.text, 'hello');
      expect(c.selection, 5);
    });
  });

  group('backspace', () {
    test('deletes the character before the cursor', () {
      final c = TextEditingController(text: 'hello'); // cursor at 5
      c.backspace();
      expect(c.text, 'hell');
      expect(c.selection, 4);
    });

    test('no-op at the start', () {
      final c = TextEditingController(text: 'hi')..selection = 0;
      var fires = 0;
      c.addListener(() => fires += 1);
      c.backspace();
      expect(c.text, 'hi');
      expect(fires, 0);
    });

    test('deletes an emoji as one character', () {
      final c = TextEditingController(text: 'a🙂b')..selection = 3;
      c.backspace();
      expect(c.text, 'ab');
      expect(c.selection, 1);
    });
  });

  group('delete', () {
    test('deletes the character after the cursor', () {
      final c = TextEditingController(text: 'hello')..selection = 1;
      c.delete();
      expect(c.text, 'hllo');
      expect(c.selection, 1);
    });

    test('no-op at the end', () {
      final c = TextEditingController(text: 'hi');
      var fires = 0;
      c.addListener(() => fires += 1);
      c.delete();
      expect(c.text, 'hi');
      expect(fires, 0);
    });

    test('deletes a combining sequence as one character', () {
      final c = TextEditingController(text: 'e\u0301x')..selection = 0;
      c.delete();
      expect(c.text, 'x');
      expect(c.selection, 0);
    });
  });

  group('cursor movement', () {
    test('left / right / start / end', () {
      final c = TextEditingController(text: 'abc')..selection = 1;
      c.moveCursorLeft();
      expect(c.selection, 0);
      c.moveCursorRight();
      c.moveCursorRight();
      expect(c.selection, 2);
      c.moveCursorToEnd();
      expect(c.selection, 3);
      c.moveCursorToStart();
      expect(c.selection, 0);
    });

    test('movement at boundaries is a no-op', () {
      final c = TextEditingController(text: 'a')..selection = 0;
      var fires = 0;
      c.addListener(() => fires += 1);
      c.moveCursorLeft();
      expect(fires, 0);
      c.selection = 1;
      fires = 0;
      c.moveCursorRight();
      expect(fires, 0);
    });

    test('left and right movement snap across grapheme clusters', () {
      final c = TextEditingController(text: 'a🙂b')..selection = 3;
      c.moveCursorLeft();
      expect(c.selection, 1);
      c.moveCursorRight();
      expect(c.selection, 3);
    });

    test('extended movement creates a range selection', () {
      final c = TextEditingController(text: 'abcd')..selection = 1;
      c.moveCursorRight(extend: true);
      c.moveCursorRight(extend: true);
      expect(
        c.textSelection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );

      c.moveCursorLeft();
      expect(c.textSelection, const TextSelection.collapsed(1));
    });
  });

  group('range replacement', () {
    test('typing replaces selected text', () {
      final c = TextEditingController(text: 'abcd')
        ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 3);

      c.insert('X');

      expect(c.text, 'aXd');
      expect(c.textSelection, const TextSelection.collapsed(2));
    });

    test('backspace deletes selected text', () {
      final c = TextEditingController(text: 'abcd')
        ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 3);

      c.backspace();

      expect(c.text, 'ad');
      expect(c.textSelection, const TextSelection.collapsed(1));
    });

    test('selectedText returns a normalized range', () {
      final c = TextEditingController(text: 'abcd')
        ..textSelection = const TextSelection(baseOffset: 3, extentOffset: 1);

      expect(c.hasSelection, isTrue);
      expect(c.selectedText, 'bc');
    });

    test('deleteSelection deletes the selected range', () {
      final c = TextEditingController(text: 'abcd')
        ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 3);

      c.deleteSelection();

      expect(c.text, 'ad');
      expect(c.textSelection, const TextSelection.collapsed(1));
    });

    test('replaceRange is undoable', () {
      final c = TextEditingController(text: 'git che');

      c.replaceRange(const TextRange(start: 4, end: 7), 'checkout');

      expect(c.text, 'git checkout');
      expect(c.textSelection, const TextSelection.collapsed(12));

      c.undo();
      expect(c.text, 'git che');
      expect(c.textSelection, const TextSelection.collapsed(7));
    });
  });

  group('undo and redo', () {
    test('undo restores the previous editing value', () {
      final c = TextEditingController();
      c.insert('a');
      c.insert('b');

      expect(c.canUndo, isTrue);
      expect(c.canRedo, isFalse);

      c.undo();
      expect(c.text, 'a');
      expect(c.textSelection, const TextSelection.collapsed(1));
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.text, 'ab');
      expect(c.textSelection, const TextSelection.collapsed(2));
    });

    test('new edits clear the redo stack', () {
      final c = TextEditingController();
      c.insert('a');
      c.insert('b');
      c.undo();
      expect(c.canRedo, isTrue);

      c.insert('X');

      expect(c.text, 'aX');
      expect(c.canRedo, isFalse);
    });

    test('programmatic text resets history', () {
      final c = TextEditingController();
      c.insert('draft');
      expect(c.canUndo, isTrue);

      c.text = 'reset';

      expect(c.canUndo, isFalse);
      c.undo();
      expect(c.text, 'reset');
    });

    test('consecutive typed inserts coalesce into one undo step', () {
      final c = TextEditingController();
      c.insert('a', coalesce: true);
      c.insert('b', coalesce: true);
      c.insert('c', coalesce: true);

      c.undo();
      expect(c.text, '');
      expect(c.textSelection, const TextSelection.collapsed(0));

      c.redo();
      expect(c.text, 'abc');
      expect(c.textSelection, const TextSelection.collapsed(3));
    });

    test('cursor movement breaks typed insert coalescing', () {
      final c = TextEditingController();
      c.insert('a', coalesce: true);
      c.insert('b', coalesce: true);
      c.moveCursorLeft();
      c.insert('X', coalesce: true);

      expect(c.text, 'aXb');
      c.undo();
      expect(c.text, 'ab');
      expect(c.textSelection, const TextSelection.collapsed(1));

      c.undo();
      expect(c.text, '');
      expect(c.textSelection, const TextSelection.collapsed(0));
    });

    test('paste is one undo step and does not coalesce with typing', () {
      final c = TextEditingController();
      c.insert('a', coalesce: true);
      c.paste('b\nc', singleLine: true);

      expect(c.text, 'ab c');
      c.undo();
      expect(c.text, 'a');
      expect(c.textSelection, const TextSelection.collapsed(1));

      c.redo();
      expect(c.text, 'ab c');
      expect(c.textSelection, const TextSelection.collapsed(4));
    });

    test('coalesced paste chunks undo as one paste operation', () {
      final c = TextEditingController();
      c.paste('ab');
      c.paste('cd', coalesce: true);
      c.paste('ef', coalesce: true);

      expect(c.text, 'abcdef');

      c.undo();
      expect(c.text, '');
      expect(c.textSelection, const TextSelection.collapsed(0));
    });
  });

  group('composition', () {
    test('updateComposingText tracks the active composing range', () {
      final c = TextEditingController(text: 'git ');

      c.updateComposingText('che', singleLine: true);

      expect(c.text, 'git che');
      expect(c.textSelection, const TextSelection.collapsed(7));
      expect(c.composing, const TextRange(start: 4, end: 7));
      expect(c.hasComposingRange, isTrue);
      expect(c.canUndo, isFalse);

      c.updateComposingText('checkout', singleLine: true);

      expect(c.text, 'git checkout');
      expect(c.textSelection, const TextSelection.collapsed(12));
      expect(c.composing, const TextRange(start: 4, end: 12));
      expect(c.canUndo, isFalse);
    });

    test('commitComposing records the composition as one undo step', () {
      final c = TextEditingController(text: 'git ');

      c.updateComposingText('che', singleLine: true);
      c.updateComposingText('checkout', singleLine: true);
      c.commitComposing();

      expect(c.text, 'git checkout');
      expect(c.composing, TextRange.empty);
      expect(c.canUndo, isTrue);

      c.undo();
      expect(c.text, 'git ');
      expect(c.textSelection, const TextSelection.collapsed(4));
      expect(c.composing, TextRange.empty);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.text, 'git checkout');
      expect(c.textSelection, const TextSelection.collapsed(12));
      expect(c.composing, TextRange.empty);
    });

    test('commitComposing can replace and normalize final text', () {
      final c = TextEditingController();

      c.updateComposingText('one', singleLine: true);
      c.commitComposing(text: 'one\ntwo', singleLine: true);

      expect(c.text, 'one two');
      expect(c.composing, TextRange.empty);

      c.undo();
      expect(c.text, '');
      expect(c.textSelection, const TextSelection.collapsed(0));
    });

    test('cancelComposing restores the pre-composition value', () {
      final c = TextEditingController(text: 'git ');

      c.updateComposingText('checkout', singleLine: true);
      c.cancelComposing();

      expect(c.text, 'git ');
      expect(c.textSelection, const TextSelection.collapsed(4));
      expect(c.composing, TextRange.empty);
      expect(c.canUndo, isFalse);
    });

    test('clearComposing clears the range without changing text', () {
      final c = TextEditingController(text: 'run ');

      c.updateComposingText('deploy', singleLine: true);
      c.clearComposing();

      expect(c.text, 'run deploy');
      expect(c.textSelection, const TextSelection.collapsed(10));
      expect(c.composing, TextRange.empty);
      expect(c.canUndo, isFalse);
    });

    test('undo cancels an active uncommitted composition', () {
      final c = TextEditingController(text: 'run ');

      c.updateComposingText('deploy', singleLine: true);
      c.undo();

      expect(c.text, 'run ');
      expect(c.textSelection, const TextSelection.collapsed(4));
      expect(c.composing, TextRange.empty);
      expect(c.canRedo, isFalse);
    });

    test('setComposingRange marks existing text without an undo step', () {
      final c = TextEditingController(text: 'git checkout');

      c.setComposingRange(const TextRange(start: 4, end: 12));
      expect(c.composing, const TextRange(start: 4, end: 12));
      expect(c.canUndo, isFalse);

      c.commitComposing();
      expect(c.text, 'git checkout');
      expect(c.composing, TextRange.empty);
      expect(c.canUndo, isFalse);
    });
  });

  group('submission history', () {
    test('commits entries with limit and consecutive de-dupe', () {
      final history = TextHistoryController(maxEntries: 2);

      history.commit('one');
      history.commit('one');
      history.commit('two');
      history.commit('three');

      expect(history.entries, ['two', 'three']);
      expect(history.length, 2);
    });

    test('navigation walks entries and restores the captured draft', () {
      final history = TextHistoryController(entries: ['one', 'two']);

      final previous = history.navigatePrevious(
        TextEditingValue(
          text: 'draft',
          selection: const TextSelection.collapsed(2),
        ),
      );
      expect(previous?.text, 'two');
      expect(previous?.selection, const TextSelection.collapsed(3));
      expect(history.isBrowsing, isTrue);
      expect(history.selectedIndex, 1);
      expect(history.draft, 'draft');

      expect(
        history.navigatePrevious(TextEditingValue(text: 'two'))?.text,
        'one',
      );
      expect(history.selectedIndex, 0);

      expect(
        history.navigatePrevious(TextEditingValue(text: 'one'))?.text,
        'one',
      );
      expect(history.selectedIndex, 0);

      expect(history.navigateNext()?.text, 'two');
      expect(history.selectedIndex, 1);

      final restored = history.navigateNext();
      expect(restored?.text, 'draft');
      expect(restored?.selection, const TextSelection.collapsed(5));
      expect(history.isBrowsing, isFalse);
      expect(history.navigateNext(), isNull);
    });

    test('resetBrowsing keeps entries but drops draft state', () {
      final history = TextHistoryController(entries: ['one']);
      history.navigatePrevious(TextEditingValue(text: 'draft'));

      history.resetBrowsing();

      expect(history.entries, ['one']);
      expect(history.isBrowsing, isFalse);
      expect(history.draft, isNull);
    });

    test('clear removes entries and active draft state', () {
      final history = TextHistoryController(entries: ['one']);
      history.navigatePrevious(TextEditingValue(text: 'draft'));

      history.clear();

      expect(history.entries, isEmpty);
      expect(history.isBrowsing, isFalse);
      expect(history.draft, isNull);
    });

    test('dispose is idempotent and clears transient browsing state', () {
      final history = TextHistoryController(entries: ['one', 'two']);
      history.navigatePrevious(TextEditingValue(text: 'draft'));
      expect(history.isBrowsing, isTrue);
      expect(history.draft, 'draft');

      history.dispose();
      history.dispose();

      expect(history.entries, ['one', 'two']);
      expect(history.isBrowsing, isFalse);
      expect(history.selectedIndex, isNull);
      expect(history.draft, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final history = TextHistoryController(entries: ['one'])..dispose();

      const message = 'TextHistoryController has been disposed.';
      expect(() => history.commit('two'), _stateError(message));
      expect(() => history.clear(), _stateError(message));
      expect(() => history.replaceAll(['two']), _stateError(message));
      expect(
        () => history.navigatePrevious(TextEditingValue(text: 'draft')),
        _stateError(message),
      );
      expect(() => history.navigateNext(), _stateError(message));
      expect(() => history.resetBrowsing(), _stateError(message));
    });
  });

  group('clear', () {
    test('resets text and cursor and notifies', () {
      final c = TextEditingController(text: 'hello');
      var fires = 0;
      c.addListener(() => fires += 1);
      c.clear();
      expect(c.text, '');
      expect(c.selection, 0);
      expect(fires, 1);
    });

    test('no-op when already empty', () {
      final c = TextEditingController();
      var fires = 0;
      c.addListener(() => fires += 1);
      c.clear();
      expect(fires, 0);
    });
  });

  group('lifecycle', () {
    test('dispose is idempotent and keeps the last readable value', () {
      final c = TextEditingController(text: 'hello');
      c.insert('!');
      expect(c.canUndo, isTrue);

      c.dispose();
      c.dispose();

      expect(c.text, 'hello!');
      expect(c.value.text, 'hello!');
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final c = TextEditingController(text: 'hello');
      c.dispose();

      const message = 'TextEditingController has been disposed.';
      expect(
        () => c.value = TextEditingValue(text: 'reset'),
        _stateError(message),
      );
      expect(() => c.text = 'reset', _stateError(message));
      expect(() => c.selection = 1, _stateError(message));
      expect(
        () => c.textSelection = const TextSelection.collapsed(1),
        _stateError(message),
      );
      expect(() => c.insert('!'), _stateError(message));
      expect(() => c.paste('!'), _stateError(message));
      expect(() => c.backspace(), _stateError(message));
      expect(() => c.delete(), _stateError(message));
      expect(() => c.deleteSelection(), _stateError(message));
      expect(
        () => c.replaceRange(const TextRange(start: 0, end: 1), 'x'),
        _stateError(message),
      );
      expect(
        () => c.setComposingRange(const TextRange(start: 0, end: 1)),
        _stateError(message),
      );
      expect(() => c.clearComposing(), _stateError(message));
      expect(() => c.updateComposingText('x'), _stateError(message));
      expect(() => c.commitComposing(), _stateError(message));
      expect(() => c.cancelComposing(), _stateError(message));
      expect(() => c.moveCursorLeft(), _stateError(message));
      expect(() => c.moveCursorRight(), _stateError(message));
      expect(() => c.moveCursorWordLeft(), _stateError(message));
      expect(() => c.moveCursorWordRight(), _stateError(message));
      expect(() => c.moveCursorToStart(), _stateError(message));
      expect(() => c.moveCursorToEnd(), _stateError(message));
      expect(() => c.moveCursorToLineStart(), _stateError(message));
      expect(() => c.moveCursorToLineEnd(), _stateError(message));
      expect(() => c.moveCursorLineUp(), _stateError(message));
      expect(() => c.moveCursorLineDown(), _stateError(message));
      expect(() => c.undo(), _stateError(message));
      expect(() => c.redo(), _stateError(message));
      expect(() => c.clear(), _stateError(message));
    });
  });
}
