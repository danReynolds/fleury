import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {int cols = 16, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

/// First (col,row) where [needle] appears in the rendered buffer, or null.
({int col, int row})? _find(
  FleuryTester tester,
  String needle, {
  int cols = 16,
  int rows = 8,
}) {
  final buf = tester.render(size: CellSize(cols, rows));
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < cols; c++) {
      sb.write(buf.atColRow(c, r).grapheme ?? ' ');
    }
    final idx = sb.toString().indexOf(needle);
    if (idx >= 0) return (col: idx, row: r);
  }
  return null;
}

const _options = <SelectOption<String>>[
  SelectOption(value: 'red', label: 'Red'),
  SelectOption(value: 'green', label: 'Green'),
  SelectOption(value: 'blue', label: 'Blue'),
];

/// Controlled host: holds the value and reports picks.
class _Host extends StatefulWidget {
  const _Host({this.initial, this.onPick, this.options = _options});
  final String? initial;
  final void Function(String)? onPick;
  final List<SelectOption<String>> options;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? value;
  @override
  void initState() {
    super.initState();
    value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Select<String>(
      autofocus: true,
      value: value,
      options: widget.options,
      semanticLabel: 'Color',
      onChanged: (v) {
        setState(() => value = v);
        widget.onPick?.call(v);
      },
    );
  }
}

class _MultiHost extends StatefulWidget {
  const _MultiHost({this.initial = const <String>{}});
  final Set<String> initial;
  @override
  State<_MultiHost> createState() => _MultiHostState();
}

class _MultiHostState extends State<_MultiHost> {
  late Set<String> values;
  @override
  void initState() {
    super.initState();
    values = Set<String>.of(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return MultiSelect<String>(
      autofocus: true,
      values: values,
      options: _options,
      semanticLabel: 'Colors',
      onChanged: (next) {
        setState(() => values = next);
      },
    );
  }
}

void main() {
  group('Select', () {
    testWidgets('collapsed shows the placeholder when no value', (tester) {
      tester.pumpWidget(const _Host());
      expect(_screen(tester).contains('Select…'), isTrue);
      expect(_screen(tester).contains('Red'), isFalse, reason: 'closed');
    });

    testWidgets('collapsed shows the current value label', (tester) {
      tester.pumpWidget(const _Host(initial: 'green'));
      final out = _screen(tester);
      expect(out.contains('Green'), isTrue);
      expect(out.contains('▾'), isTrue);
    });

    testWidgets('semantic setValue picks an option without opening (B4)',
        (tester) async {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));
      final node =
          tester.semantics().single(role: SemanticRole.button, label: 'Color');
      expect(node.actions, contains(SemanticAction.setValue));

      // Exact label match, and the dropdown never opens.
      await tester.invokeSemanticAction(SemanticAction.setValue,
          node: node, payload: 'Blue');
      expect(picked, 'blue');
      expect(tester.semantics().byRole(SemanticRole.menuItem), isEmpty,
          reason: 'no open/read/select dance — the list never mounts');
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Color')
            .state['selectedKey'],
        'blue',
      );

      // Case-insensitive match (label 'Green', payload 'GREEN').
      await tester.invokeSemanticAction(SemanticAction.setValue,
          role: SemanticRole.button, label: 'Color', payload: 'GREEN');
      expect(picked, 'green');

      // An unknown option is a no-op, not a wrong pick.
      picked = null;
      await tester.invokeSemanticAction(SemanticAction.setValue,
          role: SemanticRole.button, label: 'Color', payload: 'purple');
      expect(picked, isNull);
    });

    testWidgets('null onChanged disables the trigger', (tester) async {
      tester.pumpWidget(
        const Select<String>(
          value: 'red',
          options: _options,
          semanticLabel: 'Color',
          autofocus: true,
          onChanged: null,
        ),
      );

      final trigger = tester.semantics().single(
        role: SemanticRole.button,
        label: 'Color',
        enabled: false,
      );
      expect(trigger.actions, isEmpty);
      expect(trigger.value, 'Red');
      expect(trigger.expanded, isFalse);
      expect(
        tester.render(size: const CellSize(16, 1)).atColRow(0, 0).style.dim,
        isTrue,
      );

      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);

      final result = await tester.invokeSemanticAction(
        SemanticAction.open,
        node: trigger,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });

    testWidgets('Enter opens the list anchored below the trigger', (tester) {
      tester.pumpWidget(const _Host());
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      final out = _screen(tester);
      expect(out.contains('Red'), isTrue);
      expect(out.contains('Green'), isTrue);
      expect(out.contains('Blue'), isTrue);
    });

    testWidgets('Down then Enter picks the next option and closes', (tester) {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // -> Green
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // pick
      expect(picked, 'green');
      final out = _screen(tester);
      expect(out.contains('Green'), isTrue, reason: 'trigger shows new value');
      // List is closed: Blue (an unselected option) is gone.
      expect(out.contains('Blue'), isFalse);
    });

    testWidgets('Esc closes without changing the value', (tester) {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      expect(picked, isNull);
      final out = _screen(tester);
      expect(out.contains('Red'), isTrue, reason: 'value unchanged');
      expect(out.contains('Blue'), isFalse, reason: 'list closed');
    });

    testWidgets('the open list marks the currently-selected option', (tester) {
      tester.pumpWidget(const _Host(initial: 'green'));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(_screen(tester).contains('• Green'), isTrue);
    });

    testWidgets('navigation skips a disabled option', (tester) {
      String? picked;
      tester.pumpWidget(
        _Host(
          initial: 'red',
          onPick: (v) => picked = v,
          options: const [
            SelectOption(value: 'red', label: 'Red'),
            SelectOption(value: 'green', label: 'Green', enabled: false),
            SelectOption(value: 'blue', label: 'Blue'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open at Red
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // skip Green
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, 'blue');
    });

    testWidgets('a click opens the list and a click picks an option', (tester) {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));

      // Click the trigger (row 0) to open.
      final trigger = _find(tester, 'Red')!;
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: trigger.col,
          row: trigger.row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: trigger.col,
          row: trigger.row,
        ),
      );
      expect(_screen(tester).contains('Blue'), isTrue, reason: 'opened');

      // Click the Blue option.
      final blue = _find(tester, 'Blue')!;
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: blue.col,
          row: blue.row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: blue.col,
          row: blue.row,
        ),
      );
      expect(picked, 'blue');
    });

    group('semantics', () {
      testWidgets('trigger semantic action opens the option menu', (
        tester,
      ) async {
        tester.pumpWidget(const _Host(initial: 'green'));

        final trigger = tester.semantics().single(
          role: SemanticRole.button,
          label: 'Color',
          action: SemanticAction.open,
        );

        expect(trigger.focused, isTrue);
        expect(trigger.value, 'Green');
        expect(trigger.expanded, isFalse);
        expect(trigger.state.menuItemCount, 3);
        expect(trigger.state.selectedKey, 'green');
        expect(trigger.state['selectedOptionLabel'], 'Green');

        // WS-9: the settable domain is published as {label, value} pairs so an
        // agent (and the MCP valueSchema) sees exactly what set_value accepts.
        final options = trigger.state['options']! as List;
        expect(options, hasLength(3));
        for (final option in options) {
          expect(option, isA<Map<Object?, Object?>>());
          expect((option as Map).keys, containsAll(<String>['label', 'value']));
        }
        expect(
          options.map((o) => (o as Map)['value']),
          contains('green'),
        );

        final result = await tester.invokeSemanticAction(
          SemanticAction.open,
          node: trigger,
        );

        expect(result.completed, isTrue);
        tester.render(size: const CellSize(30, 8));
        final tree = tester.semantics();
        final menu = tree.single(role: SemanticRole.menu, label: 'Color');
        expect(menu.focused, isTrue);
        expect(menu.state.menuItemCount, 3);
        expect(menu.state['appliedIndex'], 1);
        final green = tree.single(role: SemanticRole.menuItem, label: 'Green');
        expect(green.checked, isTrue);
        expect(green.selected, isTrue);
        expect(green.state.menuItemPosition, 2);
      });

      testWidgets('option semantic select picks the value and closes', (
        tester,
      ) async {
        String? picked;
        tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));

        await tester.invokeSemanticAction(
          SemanticAction.open,
          role: SemanticRole.button,
          label: 'Color',
        );
        tester.render(size: const CellSize(30, 8));
        final result = await tester.invokeSemanticAction(
          SemanticAction.select,
          role: SemanticRole.menuItem,
          label: 'Blue',
        );

        expect(result.completed, isTrue);
        expect(picked, 'blue');
        expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
        final trigger = tester.semantics().single(
          role: SemanticRole.button,
          label: 'Color',
        );
        expect(trigger.value, 'Blue');
        expect(trigger.expanded, isFalse);
        expect(trigger.state.selectedKey, 'blue');
      });

      testWidgets(
        'disabled options are visible but not semantically selectable',
        (tester) async {
          tester.pumpWidget(
            const _Host(
              initial: 'red',
              options: [
                SelectOption(value: 'red', label: 'Red'),
                SelectOption(value: 'green', label: 'Green', enabled: false),
                SelectOption(value: 'blue', label: 'Blue'),
              ],
            ),
          );

          await tester.invokeSemanticAction(
            SemanticAction.open,
            role: SemanticRole.button,
            label: 'Color',
          );
          tester.render(size: const CellSize(30, 8));

          final disabled = tester.semantics().single(
            role: SemanticRole.menuItem,
            label: 'Green',
            enabled: false,
          );

          expect(disabled.actions, isEmpty);
          expect(disabled.state.menuItemPosition, 2);
        },
      );

      testWidgets('accessibility fallback summarizes option positions', (
        tester,
      ) async {
        tester.pumpWidget(const _Host(initial: 'red'));
        await tester.invokeSemanticAction(
          SemanticAction.open,
          role: SemanticRole.button,
          label: 'Color',
        );
        tester.render(size: const CellSize(30, 8));

        final snapshot = tester.accessibilitySnapshot();
        final menu = snapshot.single(
          role: SemanticRole.menu,
          label: 'Color',
          state: 'menu 3 items',
        );
        final red = snapshot.single(
          role: SemanticRole.menuItem,
          label: 'Red',
          checked: true,
          state: 'menu item 1 of 3',
        );

        expect(menu.announcement, contains('focused'));
        expect(red.announcement, contains('checked'));
        expect(red.announcement, contains('actions: activate, select'));
      });
    });
  });

  group('MultiSelect', () {
    testWidgets('renders checked values', (tester) {
      tester.pumpWidget(const _MultiHost(initial: {'red'}));

      final out = _screen(tester, cols: 18, rows: 3);
      expect(out.contains('[x] Red'), isTrue);
      expect(out.contains('[ ] Green'), isTrue);
      expect(out.contains('[ ] Blue'), isTrue);
    });

    testWidgets('Enter toggles the highlighted option', (tester) {
      tester.pumpWidget(const _MultiHost());

      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

      final out = _screen(tester, cols: 18, rows: 3);
      expect(out.contains('[x] Red'), isTrue);
    });

    testWidgets('Ctrl+A selects all, then deselects all', (tester) {
      tester.pumpWidget(const _MultiHost());

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      var out = _screen(tester, cols: 18, rows: 3);
      expect(out.contains('[x] Red'), isTrue);
      expect(out.contains('[x] Green'), isTrue);
      expect(out.contains('[x] Blue'), isTrue);

      tester.sendKey(const KeyEvent(char: 'a', modifiers: {KeyModifier.ctrl}));
      out = _screen(tester, cols: 18, rows: 3);
      expect(out.contains('[ ] Red'), isTrue);
      expect(out.contains('[ ] Blue'), isTrue);
    });

    testWidgets('navigation skips disabled options', (tester) {
      Set<String>? picked;
      tester.pumpWidget(
        MultiSelect<String>(
          autofocus: true,
          values: const {'red'},
          semanticLabel: 'Colors',
          options: const [
            SelectOption(value: 'red', label: 'Red'),
            SelectOption(value: 'green', label: 'Green', enabled: false),
            SelectOption(value: 'blue', label: 'Blue'),
          ],
          onChanged: (values) => picked = values,
        ),
      );

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

      expect(picked, {'red', 'blue'});
    });

    testWidgets('semantic activate toggles an option', (tester) async {
      tester.pumpWidget(const _MultiHost(initial: {'red'}));

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.checkbox,
        label: 'Blue',
      );

      expect(result.completed, isTrue);
      final blue = tester.semantics().single(
        role: SemanticRole.checkbox,
        label: 'Blue',
      );
      expect(blue.checked, isTrue);
      expect(blue.state['itemPosition'], 3);
    });

    testWidgets('null onChanged disables the list and options', (tester) async {
      tester.pumpWidget(
        const MultiSelect<String>(
          values: {'red'},
          options: _options,
          semanticLabel: 'Colors',
          autofocus: true,
          onChanged: null,
        ),
      );

      final list = tester.semantics().single(
        role: SemanticRole.list,
        label: 'Colors',
        enabled: false,
      );
      expect(list.actions, isEmpty);
      expect(list.state['selectedCount'], 1);

      final red = tester.semantics().single(
        role: SemanticRole.checkbox,
        label: 'Red',
        enabled: false,
      );
      expect(red.checked, isTrue);
      expect(red.actions, isEmpty);
      expect(
        tester.render(size: const CellSize(18, 3)).atColRow(0, 0).style.dim,
        isTrue,
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        node: red,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });
  });

  testWidgets('sanitizes unsafe option labels in trigger, list, and '
      'semantics', (tester) {
    const unsafe = <SelectOption<String>>[
      SelectOption(value: 'x', label: 'Bad\x1b]52;c;secret\x07ge'),
    ];
    tester.pumpWidget(const _Host(initial: 'x', options: unsafe));
    final closed = _screen(tester, cols: 32);
    expect(closed, isNot(contains('secret')), reason: 'trigger label');
    expect(closed, contains(replacementCharacter));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
    final open = _screen(tester, cols: 32);
    expect(open, isNot(contains('secret')), reason: 'list row label');
    final rows = tester.semantics().byRole(SemanticRole.menuItem);
    for (final row in rows) {
      expect(row.label, isNot(contains('secret')));
    }
  });
}
