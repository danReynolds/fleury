import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_samples/samples.dart';
import 'package:test/test.dart';

const _size = CellSize(90, 20);

String _render(FleuryTester tester) => tester.renderToString(size: _size);

void main() {
  group('EditorModel', () {
    test('insert, newline, and backspace edit the buffer', () {
      final m = EditorModel('abc');
      m.insertText('X');
      expect(m.lines.single, 'Xabc');
      m.lineEnd();
      m.newline();
      expect(m.lines, ['Xabc', '']);
      m.insertText('y');
      m.backspace();
      expect(m.lines, ['Xabc', '']);
      m.backspace(); // join with previous line
      expect(m.lines.single, 'Xabc');
    });

    test('dd honours a pending count (3dd)', () {
      final m = EditorModel('one\ntwo\nthree\nfour');
      m.pushCountDigit(3);
      m.deleteLine();
      expect(m.lines, ['four']);
    });

    test('dw deletes to the next word; d\$ to end of line', () {
      final m = EditorModel('alpha beta gamma');
      m.deleteWord();
      expect(m.lines.single, 'beta gamma');
      m.lineEnd();
      m.lineStart();
      m.moveRight();
      m.moveRight();
      m.moveRight();
      m.moveRight();
      m.moveRight(); // after "beta "
      m.deleteToLineEnd();
      expect(m.lines.single, 'beta ');
    });

    test('gg / G jump to the first and last line', () {
      final m = EditorModel('a\nb\nc');
      m.gotoBottom();
      expect(m.row, 2);
      m.gotoTop();
      expect(m.row, 0);
    });

    test('toggling personality keeps the buffer and resets to NORMAL', () {
      final m = EditorModel('keep me');
      m.insertText('!');
      m.togglePersonality();
      expect(m.personality, EditorPersonality.vim);
      expect(m.vimMode, VimMode.normal);
      expect(m.lines.single, '!keep me');
    });
  });

  group('nano — modeless: text and Ctrl-chords coexist', () {
    testWidgets('the shortcut bar advertises the commands', (tester) {
      tester.pumpWidget(const EditorApp());
      final out = _render(tester);
      expect(out, contains('Write Out')); // ^O
      expect(out, contains('Cut')); // ^K
    });

    testWidgets('typing inserts, and ^K cuts a line (no mode)', (tester) {
      tester.pumpWidget(const EditorApp());
      tester.render(size: _size);

      tester.type('Z');
      expect(_render(tester), contains('ZThe quick'), reason: 'text inserts');

      tester.press(KeySequence.ctrl.k);
      expect(_render(tester), contains('cut 1 line'), reason: '^K cut');
      expect(
        _render(tester),
        isNot(contains('ZThe quick')),
        reason: 'the first line is gone',
      );
    });
  });

  group('vim — modal claimant flip', () {
    testWidgets('NORMAL declines text; commands route as keys', (tester) {
      tester.pumpWidget(const EditorApp());
      tester.render(size: _size);
      tester.press(KeySequence.ctrl.b); // → vim NORMAL
      expect(_render(tester), contains('NORMAL'));

      // A printable in NORMAL is a command, not text: an unbound letter does
      // nothing (it's declined and routed, matches no binding).
      final before = _render(tester);
      tester.press(KeyCode.z);
      expect(_render(tester), before, reason: 'z is not inserted in NORMAL');

      // dd deletes a line (the `.d.d` sequence).
      tester.press(KeySequence.d.d);
      expect(_render(tester), contains('cut 1 line'));
    });

    testWidgets('i enters INSERT where text is claimed; Esc returns', (tester) {
      tester.pumpWidget(const EditorApp());
      tester.render(size: _size);
      tester.press(KeySequence.ctrl.b); // → vim NORMAL
      tester.press(KeyCode.i); // → INSERT
      expect(_render(tester), contains('INSERT'));

      tester.type('HELLO ');
      expect(
        _render(tester),
        contains('HELLO The quick'),
        reason: 'text claimed',
      );

      tester.press(KeyCode.escape); // → NORMAL
      expect(_render(tester), isNot(contains('INSERT')));
    });

    testWidgets('the Space leader fires a sequenced command', (tester) {
      tester.pumpWidget(const EditorApp());
      tester.render(size: _size);
      tester.press(KeySequence.ctrl.b); // → vim NORMAL

      tester.press(KeySequence.space.w); // leader → write / save
      expect(_render(tester), contains('Saved'), reason: 'Space w saved');
    });

    testWidgets('A appends after the last character (end of line)', (tester) {
      tester.pumpWidget(const EditorApp());
      tester.render(size: _size);
      tester.press(KeySequence.ctrl.b); // → vim NORMAL
      tester.press(KeyCode.char('A')); // append at end of line 1
      tester.type('!');
      expect(
        _render(tester),
        contains('lazy dog.!'),
        reason: 'text lands after the last char, not before it',
      );
    });

    testWidgets('which-key reveals the d-prefix completions', (tester) async {
      tester.pumpWidget(const EditorApp());
      tester.render(size: _size);
      tester.press(KeySequence.ctrl.b); // → vim NORMAL

      tester.press(KeyCode.d); // start the `d` prefix — a pending sequence
      // Outlive WhichKey's reveal delay, then flush the reveal.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      tester.pump();

      final out = _render(tester);
      expect(out, contains('delete line'), reason: 'dd');
      expect(out, contains('delete word'), reason: 'dw');

      tester.press(KeyCode.escape); // cancel the pending sequence + its timer
    });
  });
}
