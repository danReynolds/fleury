import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  test('deferred tails survive many independent undo snapshots', () {
    final c = TextEditingController(text: 'Z')..caretOffset = 0;
    addTearDown(c.dispose);
    final paste = c.beginPaste()..append('A');
    for (var i = 0; i < 50; i++) {
      c.caretOffset = 0;
      c.insert('x');
      paste.append('B');
    }
    paste.close();
    for (var remaining = 50; remaining >= 0; remaining--) {
      expect(c.text, '${'x' * remaining}A${'B' * 50}Z');
      c.undo();
    }
    expect(c.text, 'Z');
    c.redo();
    expect(c.text, 'A${'B' * 50}Z');
    for (var i = 0; i < 50; i++) {
      c.redo();
    }
    expect(c.text, '${'x' * 50}A${'B' * 50}Z');
  });

  test('repeated characters preserve the actual edit position', () {
    final c = TextEditingController(text: 'AA')..caretOffset = 0;
    addTearDown(c.dispose);
    final paste = c.beginPaste()..append('A');
    c.caretOffset = 0;
    c.insert('A');
    paste.append('B');
    expect(c.text, 'AABAA');
  });

  for (final intervening in [false, true]) {
    test(
      'unchanged first segment still has one paste undo, edit=$intervening',
      () {
        final c = TextEditingController(text: 'A');
        addTearDown(c.dispose);
        c.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
        final paste = c.beginPaste()..append('A');
        if (intervening) c.insert('x');
        paste.append('B');
        paste.close();
        expect(c.text, intervening ? 'ABx' : 'AB');
        if (intervening) {
          c.undo();
          expect(c.text, 'AB');
        }
        c.undo();
        expect(c.text, 'A');
      },
    );
  }

  test('caret movement does not move the paste tail or split undo', () {
    final c = TextEditingController(text: 'Z')..caretOffset = 0;
    addTearDown(c.dispose);
    final paste = c.beginPaste();
    paste.append('A');
    c.caretOffset = 0;
    paste.append('B');
    paste.close();
    expect(c.text, 'ABZ');
    expect(c.caretOffset, 0);
    c.undo();
    expect(c.text, 'Z');
    c.redo();
    expect(c.text, 'ABZ');
  });

  test('typing keeps its own undo after later paste segments', () {
    final c = TextEditingController();
    addTearDown(c.dispose);
    final paste = c.beginPaste();
    paste.append('A');
    c.insert('x', coalesce: true);
    paste.append('B');
    expect(c.text, 'ABx');
    expect(c.caretOffset, 3);
    c.undo();
    expect(c.text, 'AB');
    expect(c.caretOffset, 2);
    paste.append('C');
    expect(c.text, 'ABC');
    c.redo();
    expect(c.text, 'ABCx');
    paste.close();
    c.undo();
    expect(c.text, 'ABC');
    c.undo();
    expect(c.text, '');
    c.redo();
    expect(c.text, 'ABC');
    c.redo();
    expect(c.text, 'ABCx');
  });

  test('deleting an arriving prefix transforms the insertion anchor', () {
    final c = TextEditingController(text: 'Z')..caretOffset = 0;
    addTearDown(c.dispose);
    final paste = c.beginPaste();
    paste.append('A');
    c.backspace();
    paste.append('B');
    expect(c.text, 'BZ');
    paste.close();
    c.undo();
    expect(c.text, 'ABZ');
    c.undo();
    expect(c.text, 'Z');
  });

  test('undoing the paste or resetting the model closes the stream', () {
    final c = TextEditingController();
    addTearDown(c.dispose);
    final first = c.beginPaste()..append('A');
    c.undo();
    first.append('discarded');
    expect(first.isActive, isFalse);
    expect(c.text, '');
    final second = c.beginPaste()..append('B');
    c.text = 'replacement';
    second.append('discarded');
    expect(second.isActive, isFalse);
    expect(c.text, 'replacement');
  });

  test('reentrant controller edits transform the published anchor', () {
    final c = TextEditingController();
    addTearDown(c.dispose);
    var edited = false;
    c.addListener(() {
      if (edited) return;
      edited = true;
      c.caretOffset = 0;
      c.insert('x');
    });
    final paste = c.beginPaste();
    paste.append('A');
    paste.append('B');
    expect(c.text, 'xAB');
    expect(c.caretOffset, 1);
    paste.close();
    c.undo();
    expect(c.text, 'AB');
    c.undo();
    expect(c.text, '');
  });
}
