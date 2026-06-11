import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _fruits = ['apple', 'apricot', 'banana', 'cherry'];

String _screen(FleuryTester tester, {int cols = 16, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  testWidgets('no dropdown until typing matches', (tester) {
    tester.pumpWidget(const Autocomplete(options: _fruits, autofocus: true));
    expect(tester.overlay.entries.length, 1, reason: 'just the field');
    final out = _screen(tester);
    expect(out.contains('apple'), isFalse);
  });

  testWidgets('typing opens a filtered dropdown below the field', (tester) {
    tester.pumpWidget(const Autocomplete(options: _fruits, autofocus: true));
    tester.type('ap'); // matches apple, apricot
    final out = _screen(tester);
    expect(out.contains('apple'), isTrue);
    expect(out.contains('apricot'), isTrue);
    expect(out.contains('banana'), isFalse);
    expect(tester.overlay.entries.length, 2, reason: 'dropdown is open');
  });

  testWidgets('Down + Enter fills the field with the highlighted option', (
    tester,
  ) {
    String? selected;
    tester.pumpWidget(
      Autocomplete(
        options: _fruits,
        autofocus: true,
        onSelected: (v) => selected = v,
      ),
    );
    tester.type('ap'); // apple, apricot
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → apricot
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(selected, 'apricot');
    expect(_screen(tester).contains('apricot'), isTrue, reason: 'field filled');
    expect(tester.overlay.entries.length, 1, reason: 'dropdown closed');
  });

  testWidgets('Esc closes the dropdown but keeps the text', (tester) {
    tester.pumpWidget(const Autocomplete(options: _fruits, autofocus: true));
    tester.type('ba'); // banana
    expect(tester.overlay.entries.length, 2);
    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    expect(tester.overlay.entries.length, 1, reason: 'dropdown closed');
    expect(_screen(tester).contains('ba'), isTrue, reason: 'typed text stays');
  });

  testWidgets('a non-matching query shows no dropdown', (tester) {
    tester.pumpWidget(const Autocomplete(options: _fruits, autofocus: true));
    tester.type('zzz');
    expect(tester.overlay.entries.length, 1);
  });

  testWidgets(
    'typed options filter on the display string and return the object',
    (tester) {
      const people = [
        _Person('Alice', 1),
        _Person('Alan', 2),
        _Person('Bob', 3),
      ];
      _Person? picked;
      tester.pumpWidget(
        Autocomplete<_Person>(
          options: people,
          autofocus: true,
          displayStringForOption: (p) => p.name,
          onSelected: (p) => picked = p,
        ),
      );
      tester.type('al'); // matches Alice, Alan on name
      final out = _screen(tester);
      expect(out.contains('Alice'), isTrue);
      expect(out.contains('Alan'), isTrue);
      expect(out.contains('Bob'), isFalse);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Alan
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(
        picked?.id,
        2,
        reason: 'the chosen object came back, not its label',
      );
    },
  );

  group('semantics', () {
    testWidgets('suggestion menu exposes filtered option semantics', (tester) {
      tester.pumpWidget(
        const Autocomplete(
          options: _fruits,
          autofocus: true,
          placeholder: 'Fruit',
          semanticLabel: 'Fruit suggestions',
        ),
      );
      tester.type('ap');
      tester.render(size: const CellSize(30, 8));

      final tree = tester.semantics();
      final field = tree.single(
        role: SemanticRole.textField,
        label: 'Fruit',
        focused: true,
      );
      expect(field.value, 'ap');

      final menu = tree.single(
        role: SemanticRole.menu,
        label: 'Fruit suggestions',
      );
      expect(menu.focused, isTrue);
      expect(menu.state.menuItemCount, 2);
      expect(menu.state.completionQuery, 'ap');
      expect(tree.byRole(SemanticRole.menuItem).map((node) => node.label), [
        'apple',
        'apricot',
      ]);

      final apple = tree.single(
        role: SemanticRole.menuItem,
        label: 'apple',
        selected: true,
      );
      expect(apple.actions, contains(SemanticAction.activate));
      expect(apple.actions, contains(SemanticAction.select));
      expect(apple.state.menuItemPosition, 1);
      expect(apple.state.completionQuery, 'ap');
    });

    testWidgets('semantic activation picks a suggestion and closes the menu', (
      tester,
    ) async {
      String? selected;
      tester.pumpWidget(
        Autocomplete(
          options: _fruits,
          autofocus: true,
          placeholder: 'Fruit',
          semanticLabel: 'Fruit suggestions',
          onSelected: (value) => selected = value,
        ),
      );
      tester.type('ap');
      tester.render(size: const CellSize(30, 8));

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.menuItem,
        label: 'apricot',
      );

      expect(result.completed, isTrue);
      expect(selected, 'apricot');
      expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Fruit')
            .value,
        'apricot',
      );
    });

    testWidgets('semantic close hides suggestions without clearing query', (
      tester,
    ) async {
      tester.pumpWidget(
        const Autocomplete(
          options: _fruits,
          autofocus: true,
          placeholder: 'Fruit',
          semanticLabel: 'Fruit suggestions',
        ),
      );
      tester.type('ba');
      tester.render(size: const CellSize(30, 8));

      final result = await tester.invokeSemanticAction(
        SemanticAction.close,
        role: SemanticRole.menu,
        label: 'Fruit suggestions',
      );

      expect(result.completed, isTrue);
      expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Fruit')
            .value,
        'ba',
      );
    });

    testWidgets('accessibility fallback summarizes suggestion positions', (
      tester,
    ) {
      tester.pumpWidget(
        const Autocomplete(
          options: _fruits,
          autofocus: true,
          placeholder: 'Fruit',
          semanticLabel: 'Fruit suggestions',
        ),
      );
      tester.type('ap');
      tester.render(size: const CellSize(30, 8));

      final snapshot = tester.accessibilitySnapshot();
      final menu = snapshot.single(
        role: SemanticRole.menu,
        label: 'Fruit suggestions',
        state: 'menu 2 items',
      );
      final apple = snapshot.single(
        role: SemanticRole.menuItem,
        label: 'apple',
        selected: true,
        state: 'menu item 1 of 2',
      );

      expect(menu.announcement, contains('focused'));
      expect(apple.announcement, contains('actions: activate, select'));
    });
  });

  testWidgets('sanitizes unsafe option labels for display and semantics', (
    tester,
  ) {
    const unsafe = ['bad\x1b]52;c;secret\x07ge\nname'];
    tester.pumpWidget(const Autocomplete(options: unsafe, autofocus: true));
    tester.type('bad');
    final out = _screen(tester, cols: 32);
    expect(out, isNot(contains('secret')));
    expect(out, isNot(contains('\x1b]52')));
    expect(out, contains(replacementCharacter));
    final row = tester.semantics().single(role: SemanticRole.menuItem);
    expect(row.label, contains(replacementCharacter));
    expect(row.label, isNot(contains('secret')));
  });
}

class _Person {
  const _Person(this.name, this.id);
  final String name;
  final int id;
}
