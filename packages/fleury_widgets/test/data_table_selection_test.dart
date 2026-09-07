import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

DataTable _table({
  int rows = 8,
  int? selectedIndex,
  DataTableController? controller,
  void Function(int)? onSelectionChanged,
  void Function(int)? onSelect,
  DataTableSelectionMode mode = DataTableSelectionMode.row,
}) => DataTable(
  rowCount: rows,
  columns: const [
    DataTableColumn(id: 'a', title: 'A', width: FixedColumnWidth(8)),
    DataTableColumn(id: 'b', title: 'B', width: FixedColumnWidth(8)),
  ],
  cellBuilder: (row, column) => '$row,$column',
  rowKeyBuilder: (row) => 'row-$row',
  autofocus: true,
  selectedIndex: selectedIndex,
  controller: controller,
  onSelectionChanged: onSelectionChanged,
  onSelect: onSelect,
  selectionMode: mode,
);

String? _selectedKey(FleuryTester tester) {
  tester.render(size: const CellSize(20, 10));
  return tester
          .semantics()
          .single(role: SemanticRole.table)
          .state['selectedKey']
      as String?;
}

void main() {
  test('controller and app-owned selection cannot be combined', () {
    expect(
      () => _table(controller: DataTableController(), selectedIndex: 0),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('new rows and their selection arrive in one widget update', (
    tester,
  ) {
    final requests = <int>[];
    tester.pumpWidget(
      _table(rows: 1, selectedIndex: 0, onSelectionChanged: requests.add),
    );
    expect(_selectedKey(tester), 'row-0');

    tester.pumpWidget(
      _table(rows: 8, selectedIndex: 7, onSelectionChanged: requests.add),
    );

    expect(_selectedKey(tester), 'row-7');
    expect(requests, isEmpty, reason: 'app updates must not echo as input');
  });

  testWidgets('clamping and empty data never echo selection requests', (
    tester,
  ) {
    final requests = <int>[];
    Widget table(int rows, int selected) => _table(
      rows: rows,
      selectedIndex: selected,
      onSelectionChanged: requests.add,
    );
    tester.pumpWidget(table(8, 7));
    tester.pumpWidget(table(2, 7));
    expect(_selectedKey(tester), 'row-1');
    tester.pumpWidget(table(0, 7));
    expect(_selectedKey(tester), isNull);
    tester.pumpWidget(table(8, 7));
    expect(_selectedKey(tester), 'row-7');
    tester.pumpWidget(table(8, -1));
    expect(_selectedKey(tester), 'row-0');
    expect(requests, isEmpty);
  });

  testWidgets('ignored keyboard requests retain the app-owned selection', (
    tester,
  ) {
    final requests = <int>[];
    tester.pumpWidget(
      _table(selectedIndex: 2, onSelectionChanged: requests.add),
    );
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_selectedKey(tester), 'row-2');
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_selectedKey(tester), 'row-2');
    expect(requests, [3, 3]);
  });

  testWidgets(
    'activation and copy use the accepted row after a rejected request',
    (tester) async {
      final activations = <int>[];
      tester.pumpWidget(_table(selectedIndex: 2, onSelect: activations.add));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(activations, [2]);
      expect(_selectedKey(tester), 'row-2');
      await tester.target(role: SemanticRole.table).copy();
      expect(tester.clipboard.readInProcess(), contains('2,a\t2,b'));
      expect(tester.clipboard.readInProcess(), isNot(contains('3,a')));
    },
  );

  testWidgets(
    'accepted navigation updates selection and activation is separate',
    (tester) async {
      final selected = ValueNotifier(0);
      final requests = <int>[];
      final activations = <int>[];
      tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, child) => _table(
            selectedIndex: value,
            onSelectionChanged: (row) {
              requests.add(row);
              selected.value = row;
            },
            onSelect: activations.add,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(_selectedKey(tester), 'row-1');
      expect(requests, [1]);
      expect(activations, isEmpty);

      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(activations, [1]);
      expect(requests, [1]);

      await tester.target(role: SemanticRole.tableRow, label: 'row-3').select();
      expect(_selectedKey(tester), 'row-3');
      expect(requests, [1, 3]);
      await tester.target(role: SemanticRole.tableRow, label: 'row-4').press();
      expect(_selectedKey(tester), 'row-4');
      expect(requests, [1, 3, 4]);
      expect(activations, [1, 4]);
    },
  );

  testWidgets(
    'pointer selection reports a request without activating the row',
    (tester) {
      final selected = ValueNotifier(0);
      final requests = <int>[];
      final activations = <int>[];
      tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, child) => _table(
            selectedIndex: value,
            onSelectionChanged: (row) {
              requests.add(row);
              selected.value = row;
            },
            onSelect: activations.add,
          ),
        ),
      );
      tester.render(size: const CellSize(20, 10));
      for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
        tester.sendMouse(
          MouseEvent(kind: kind, button: MouseButton.left, col: 1, row: 4),
        );
      }
      expect(_selectedKey(tester), 'row-2');
      expect(requests, [2]);
      expect(activations, isEmpty);
    },
  );

  testWidgets('layout-time acceptance preserves an extended cell range', (
    tester,
  ) {
    final selected = ValueNotifier(0);
    final requests = <int>[];
    tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (context, value, child) => LayoutBuilder(
          builder: (context, constraints) => _table(
            selectedIndex: value,
            mode: DataTableSelectionMode.cell,
            onSelectionChanged: (row) {
              requests.add(row);
              selected.value = row;
            },
          ),
        ),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.arrowRight));
    expect(requests, isEmpty, reason: 'column changes are not row changes');
    tester.sendKey(
      const KeyEvent(KeyCode.arrowDown, modifiers: {KeyModifier.shift}),
    );
    expect(_selectedKey(tester), 'row-1');
    var state = tester.semantics().single(role: SemanticRole.table).state;
    expect(state.selectionStartRow, 0);
    expect(state.selectionEndRow, 1);
    expect(state.selectionStartColumn, 1);
    expect(state.selectionEndColumn, 1);

    // An app-initiated jump starts a new range at the destination.
    selected.value = 5;
    tester.pump();
    expect(_selectedKey(tester), 'row-5');
    state = tester.semantics().single(role: SemanticRole.table).state;
    expect(state.selectionStartRow, 5);
    expect(state.selectionEndRow, 5);
    expect(requests, [1]);
  });

  testWidgets(
    'uncontrolled selection reports row changes without a controller',
    (tester) {
      final requests = <int>[];
      tester.pumpWidget(_table(onSelectionChanged: requests.add));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(_selectedKey(tester), 'row-1');
      expect(requests, [1]);
      tester.pumpWidget(_table(rows: 1, onSelectionChanged: requests.add));
      expect(_selectedKey(tester), 'row-0');
      expect(requests, [1]);
    },
  );

  testWidgets('controller callbacks tolerate a reentrant selection change', (
    tester,
  ) {
    final controller = DataTableController();
    final requests = <int>[];
    tester.pumpWidget(
      _table(
        controller: controller,
        onSelectionChanged: (row) {
          requests.add(row);
          if (row == 1) controller.selectedIndex = 2;
        },
      ),
    );
    controller.selectedIndex = 1;
    tester.pump();
    expect(_selectedKey(tester), 'row-2');
    expect(requests, [1, 2]);
    controller.selectedColumnIndex = 1;
    expect(requests, [1, 2]);
  });

  testWidgets('switching selection ownership detaches the old controller', (
    tester,
  ) {
    final controller = DataTableController(selectedIndex: 4);
    final requests = <int>[];
    tester.pumpWidget(_table(controller: controller));
    tester.pumpWidget(
      _table(selectedIndex: 2, onSelectionChanged: requests.add),
    );
    controller.selectedIndex = 6;
    expect(_selectedKey(tester), 'row-2');
    expect(requests, isEmpty);

    tester.pumpWidget(_table(onSelectionChanged: requests.add));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_selectedKey(tester), 'row-3');
    expect(requests, [3]);

    tester.pumpWidget(
      _table(controller: controller, onSelectionChanged: requests.add),
    );
    expect(_selectedKey(tester), 'row-6');
    expect(requests, [3]);
  });

  testWidgets('a selection callback can replace the table with empty data', (
    tester,
  ) {
    final rows = ValueNotifier(8);
    final requests = <int>[];
    tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rows,
        builder: (context, value, child) => _table(
          rows: value,
          selectedIndex: 0,
          onSelectionChanged: (row) {
            requests.add(row);
            rows.value = 0;
          },
        ),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_selectedKey(tester), isNull);
    expect(requests, [1]);
  });
}
