import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

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
}
