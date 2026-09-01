import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _fruits = ['apple', 'apricot', 'banana', 'cherry'];

String _screen(FleuryTester tester, {int cols = 16, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

/// Column span of the dropdown's rounded frame on the row it opens, in real
/// terminal cells (`right - left + 1` is its display width).
({int top, int left, int right}) _frame(CellBuffer buf) {
  for (var r = 0; r < buf.size.rows; r++) {
    for (var c = 0; c < buf.size.cols; c++) {
      if (buf.atColRow(c, r).grapheme != '\u256d') continue;
      for (var c2 = c + 1; c2 < buf.size.cols; c2++) {
        if (buf.atColRow(c2, r).grapheme == '\u256e') {
          return (top: r, left: c, right: c2);
        }
      }
    }
  }
  fail('no dropdown frame in the rendered buffer');
}

/// The text painted inside the frame on [row], as written (continuation cells
/// of a wide grapheme contribute nothing — their leading cell already did).
String _inside(CellBuffer buf, ({int top, int left, int right}) frame, int row) {
  final sb = StringBuffer();
  for (var c = frame.left + 1; c < frame.right; c++) {
    final cell = buf.atColRow(c, frame.top + row);
    if (cell.role == CellRole.leading) sb.write(cell.grapheme);
    if (cell.role == CellRole.empty) sb.write(' ');
  }
  return sb.toString().trim();
}

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
        onSelect: (v) => selected = v,
      ),
    );
    tester.type('ap'); // apple, apricot
    tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → apricot
    tester.sendKey(const KeyEvent(KeyCode.enter));
    expect(selected, 'apricot');
    expect(_screen(tester).contains('apricot'), isTrue, reason: 'field filled');
    expect(tester.overlay.entries.length, 1, reason: 'dropdown closed');
  });

  testWidgets('Esc closes the dropdown but keeps the text', (tester) {
    tester.pumpWidget(const Autocomplete(options: _fruits, autofocus: true));
    tester.type('ba'); // banana
    expect(tester.overlay.entries.length, 2);
    tester.sendKey(const KeyEvent(KeyCode.escape));
    expect(tester.overlay.entries.length, 1, reason: 'dropdown closed');
    expect(_screen(tester).contains('ba'), isTrue, reason: 'typed text stays');

    tester.pumpWidget(const Autocomplete(options: _fruits, autofocus: true));
    expect(
      tester.overlay.entries.length,
      1,
      reason: 'an unrelated parent rebuild must preserve explicit dismissal',
    );
  });

  testWidgets('Enter after dismissal bubbles without picking a hidden row', (
    tester,
  ) {
    final controller = TextEditingController();
    String? selected;
    var ancestorSubmits = 0;
    tester.pumpWidget(
      KeyBindings(
        bindings: <KeyBinding>[
          KeyBinding(KeySequence.enter, onTrigger: (_) => ancestorSubmits += 1),
        ],
        child: Autocomplete(
          options: _fruits,
          controller: controller,
          autofocus: true,
          onSelect: (value) => selected = value,
        ),
      ),
    );
    tester.type('ap');
    tester.sendKey(const KeyEvent(KeyCode.escape));

    tester.sendKey(const KeyEvent(KeyCode.enter));

    expect(controller.text, 'ap');
    expect(selected, isNull);
    expect(ancestorSubmits, 1);
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
          onSelect: (p) => picked = p,
        ),
      );
      tester.type('al'); // matches Alice, Alan on name
      final out = _screen(tester);
      expect(out.contains('Alice'), isTrue);
      expect(out.contains('Alan'), isTrue);
      expect(out.contains('Bob'), isFalse);

      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → Alan
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(
        picked?.id,
        2,
        reason: 'the chosen object came back, not its label',
      );
    },
  );

  testWidgets('refreshes live options while a query is open', (tester) {
    final controller = TextEditingController(text: 'ap')..caretOffset = 2;
    final options = <String>['apple', 'apricot'];
    tester.pumpWidget(
      Autocomplete(options: options, controller: controller, autofocus: true),
    );

    expect(tester.overlay.entries.length, 2);
    _screen(tester);
    expect(
      tester
          .semantics()
          .byRole(SemanticRole.menuItem)
          .map((node) => node.label),
      ['apple', 'apricot'],
    );

    // A retained list may be mutated before its owner rebuilds. Autocomplete
    // must re-read it even though oldWidget.options is the same object.
    options
      ..clear()
      ..add('apex');
    tester.pumpWidget(
      Autocomplete(options: options, controller: controller, autofocus: true),
    );
    _screen(tester);
    expect(
      tester
          .semantics()
          .byRole(SemanticRole.menuItem)
          .map((node) => node.label),
      ['apex'],
    );

    options.clear();
    tester.pumpWidget(
      Autocomplete(options: options, controller: controller, autofocus: true),
    );
    expect(
      tester.overlay.entries.length,
      1,
      reason: 'empty source closes menu',
    );

    options.add('apogee');
    tester.pumpWidget(
      Autocomplete(options: options, controller: controller, autofocus: true),
    );
    expect(
      tester.overlay.entries.length,
      2,
      reason: 'new live matches reopen the focused menu',
    );
  });

  testWidgets('refreshes matches when the display mapping changes', (tester) {
    const people = [_Person('Alice', 1), _Person('Bob', 2)];
    final controller = TextEditingController(text: 'ali')..caretOffset = 3;
    tester.pumpWidget(
      Autocomplete<_Person>(
        options: people,
        controller: controller,
        autofocus: true,
        displayStringForOption: (person) => person.name,
      ),
    );
    expect(tester.overlay.entries.length, 2);
    _screen(tester);
    expect(
      tester.semantics().single(role: SemanticRole.menuItem).label,
      'Alice',
    );

    tester.pumpWidget(
      Autocomplete<_Person>(
        options: people,
        controller: controller,
        autofocus: true,
        displayStringForOption: (person) => 'person-${person.id}',
      ),
    );
    expect(
      tester.overlay.entries.length,
      1,
      reason: 'the old display mapping must not leave stale suggestions open',
    );
  });

  testWidgets('swaps controller and focus node without retaining ownership', (
    tester,
  ) {
    final firstController = TextEditingController(text: 'ap')..caretOffset = 2;
    final secondController = TextEditingController(text: 'ba')..caretOffset = 2;
    final firstFocus = FocusNode(debugLabel: 'first autocomplete');
    final secondFocus = FocusNode(debugLabel: 'second autocomplete');
    addTearDown(firstController.dispose);
    addTearDown(secondController.dispose);
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    tester.pumpWidget(
      Autocomplete(
        options: _fruits,
        controller: firstController,
        focusNode: firstFocus,
        autofocus: true,
      ),
    );
    expect(firstFocus.hasFocus, isTrue);
    expect(_screen(tester), contains('apricot'));

    tester.pumpWidget(
      Autocomplete(
        options: _fruits,
        controller: secondController,
        focusNode: firstFocus,
        autofocus: true,
      ),
    );
    expect(_screen(tester), contains('banana'));
    firstController.text = 'ch';
    tester.pump();
    expect(_screen(tester), contains('banana'));
    expect(_screen(tester), isNot(contains('cherry')));

    tester.pumpWidget(
      Autocomplete(
        options: _fruits,
        controller: secondController,
        focusNode: secondFocus,
      ),
    );
    expect(tester.overlay.entries.length, 1);

    secondFocus.requestFocus();
    tester.pump();
    expect(tester.overlay.entries.length, 2);
    expect(_screen(tester), contains('banana'));

    tester.pumpWidget(const Text('unmounted'));
    firstController.text = 'still owned by caller';
    secondController.text = 'still owned by caller';
    expect(firstController.text, 'still owned by caller');
    expect(secondController.text, 'still owned by caller');
  });

  testWidgets('forwards onChanged and text-field semantics', (tester) {
    final controller = TextEditingController();
    final changes = <String>[];
    tester.pumpWidget(
      Autocomplete(
        options: _fruits,
        controller: controller,
        autofocus: true,
        onChanged: changes.add,
        fieldSemanticLabel: 'Fruit field',
        semanticLabel: 'Fruit suggestions',
        semanticState: const SemanticState({'fieldKind': 'fruit'}),
      ),
    );

    controller.value = TextEditingValue(
      text: 'ap',
      selection: const TextSelection.collapsed(offset: 2),
    );
    tester.pump();
    controller.caretOffset = 1;
    tester.pump();
    expect(
      tester.semantics().single(role: SemanticRole.menu).label,
      'Fruit suggestions',
    );
    tester.sendKey(const KeyEvent(KeyCode.enter));

    expect(changes, ['ap', 'apple']);
    final field = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Fruit field',
    );
    expect(field.value, 'apple');
    expect(field.state['fieldKind'], 'fruit');
  });

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
          onSelect: (value) => selected = value,
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
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Fruit')
            .actions,
        isNot(contains(SemanticAction.submit)),
      );

      tester.pumpWidget(
        const Autocomplete(
          options: _fruits,
          autofocus: true,
          placeholder: 'Fruit',
          semanticLabel: 'Fruit suggestions',
        ),
      );
      expect(
        tester.semantics().where(role: SemanticRole.menu),
        isEmpty,
        reason: 'a rebuild must not undo semantic dismissal',
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

  // Dropdown geometry is display width, not code units: a BMP wide character
  // (CJK, Kana, Hangul, fullwidth) is one code unit but two cells. Sizing the
  // box by `String.length` under-measured it, so the first suggestion wrapped
  // into the second's row and the second was never rendered at all.
  group('option labels are measured by display width', () {
    // 9 code units / 18 cells, and 6 units / 12 cells.
    const wide = ['日本語のファイル名', '設定ファイル'];

    testWidgets('the box fits the widest label and each option owns a row', (
      tester,
    ) {
      tester.pumpWidget(const Autocomplete(options: wide, autofocus: true));
      tester.type('ファ'); // a substring of both

      final buf = tester.render(size: const CellSize(40, 8));
      final frame = _frame(buf);
      expect(
        frame.right - frame.left + 1,
        22,
        reason: '18 cells for the widest label + 2 for the marker + 2 border',
      );
      expect(_inside(buf, frame, 1), '› 日本語のファイル名');
      expect(_inside(buf, frame, 2), '設定ファイル');
    });

    testWidgets('a label wider than the surface elides instead of wrapping', (
      tester,
    ) {
      tester.pumpWidget(const Autocomplete(options: wide, autofocus: true));
      tester.type('ファ');

      final buf = tester.render(size: const CellSize(14, 8));
      final frame = _frame(buf);
      expect(frame.right, lessThan(14));
      expect(_inside(buf, frame, 1), startsWith('› 日本'));
      expect(_inside(buf, frame, 1), endsWith('…'));
      expect(
        _inside(buf, frame, 2),
        startsWith('設定'),
        reason: 'the second option still gets its own row',
      );
    });
  });
}

class _Person {
  const _Person(this.name, this.id);
  final String name;
  final int id;
}
