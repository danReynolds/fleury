import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

DataTable _table({
  int rows = 8,
  int? currentRowIndex,
  DataTableController? controller,
  void Function(int)? onFocusedItemChanged,
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
  currentRowIndex: currentRowIndex,
  controller: controller,
  onFocusedItemChanged: onFocusedItemChanged,
  onSelect: onSelect,
  selectionMode: mode,
);

String? _currentKey(FleuryTester tester) {
  tester.render(size: const CellSize(20, 10));
  return tester.semantics().single(role: SemanticRole.table).state['currentKey']
      as String?;
}

void main() {
  test('controller and parent-owned cursor cannot be combined', () {
    expect(
      () => _table(controller: DataTableController(), currentRowIndex: 0),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('new rows and their cursor arrive in one widget update', (
    tester,
  ) {
    final requests = <int>[];
    tester.pumpWidget(
      _table(rows: 1, currentRowIndex: 0, onFocusedItemChanged: requests.add),
    );
    expect(_currentKey(tester), 'row-0');

    tester.pumpWidget(
      _table(rows: 8, currentRowIndex: 7, onFocusedItemChanged: requests.add),
    );

    expect(_currentKey(tester), 'row-7');
    expect(requests, isEmpty, reason: 'app updates must not echo as input');
  });

  testWidgets('clamping and empty data never echo cursor requests', (tester) {
    final requests = <int>[];
    Widget table(int rows, int selected) => _table(
      rows: rows,
      currentRowIndex: selected,
      onFocusedItemChanged: requests.add,
    );
    tester.pumpWidget(table(8, 7));
    tester.pumpWidget(table(2, 7));
    expect(_currentKey(tester), 'row-1');
    tester.pumpWidget(table(0, 7));
    expect(_currentKey(tester), isNull);
    tester.pumpWidget(table(8, 7));
    expect(_currentKey(tester), 'row-7');
    tester.pumpWidget(table(8, -1));
    expect(_currentKey(tester), 'row-0');
    expect(requests, isEmpty);
  });

  testWidgets('ignored keyboard requests retain the parent-owned cursor', (
    tester,
  ) {
    final requests = <int>[];
    tester.pumpWidget(
      _table(currentRowIndex: 2, onFocusedItemChanged: requests.add),
    );
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_currentKey(tester), 'row-2');
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_currentKey(tester), 'row-2');
    expect(requests, [3, 3]);
  });

  testWidgets(
    'confirmation and copy use the accepted row after a rejected request',
    (tester) async {
      final activations = <int>[];
      tester.pumpWidget(_table(currentRowIndex: 2, onSelect: activations.add));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(activations, [2]);
      expect(_currentKey(tester), 'row-2');
      await tester.target(role: SemanticRole.table).copy();
      expect(tester.clipboard.readInProcess(), contains('2,a\t2,b'));
      expect(tester.clipboard.readInProcess(), isNot(contains('3,a')));
    },
  );

  testWidgets(
    'accepted navigation updates the cursor and confirmation is separate',
    (tester) async {
      final selected = ValueNotifier(0);
      final requests = <int>[];
      final activations = <int>[];
      tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, child) => _table(
            currentRowIndex: value,
            onFocusedItemChanged: (row) {
              requests.add(row);
              selected.value = row;
            },
            onSelect: activations.add,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(_currentKey(tester), 'row-1');
      expect(requests, [1]);
      expect(activations, isEmpty);

      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(activations, [1]);
      expect(requests, [1]);

      await tester.target(role: SemanticRole.tableRow, label: 'row-3').select();
      expect(_currentKey(tester), 'row-3');
      expect(requests, [1, 3]);
      await tester.target(role: SemanticRole.tableRow, label: 'row-4').press();
      expect(_currentKey(tester), 'row-4');
      expect(requests, [1, 3, 4]);
      expect(activations, [1, 3, 4]);
    },
  );

  testWidgets(
    'completed pointer selection requests the cursor and confirms the row',
    (tester) {
      final selected = ValueNotifier(0);
      final requests = <int>[];
      final activations = <int>[];
      tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, child) => _table(
            currentRowIndex: value,
            onFocusedItemChanged: (row) {
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
      expect(_currentKey(tester), 'row-2');
      expect(requests, [2]);
      expect(activations, [2]);
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
            currentRowIndex: value,
            mode: DataTableSelectionMode.cell,
            onFocusedItemChanged: (row) {
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
    expect(_currentKey(tester), 'row-1');
    var state = tester.semantics().single(role: SemanticRole.table).state;
    expect(state.selectionStartRow, 0);
    expect(state.selectionEndRow, 1);
    expect(state.selectionStartColumn, 1);
    expect(state.selectionEndColumn, 1);

    // An app-initiated cursor jump preserves the independent selected range.
    selected.value = 5;
    tester.pump();
    expect(_currentKey(tester), 'row-5');
    state = tester.semantics().single(role: SemanticRole.table).state;
    expect(state.selectionStartRow, 0);
    expect(state.selectionEndRow, 1);
    expect(requests, [1]);
  });

  testWidgets('internal cursor reports row changes without a controller', (
    tester,
  ) {
    final requests = <int>[];
    tester.pumpWidget(_table(onFocusedItemChanged: requests.add));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_currentKey(tester), 'row-1');
    expect(requests, [1]);
    tester.pumpWidget(_table(rows: 1, onFocusedItemChanged: requests.add));
    expect(_currentKey(tester), 'row-0');
    expect(requests, [1]);
  });

  testWidgets(
    'interaction callback can redirect a cursor without echoing controller writes',
    (tester) {
      final controller = DataTableController();
      final requests = <int>[];
      tester.pumpWidget(
        _table(
          controller: controller,
          onFocusedItemChanged: (row) {
            requests.add(row);
            if (row == 1) controller.currentRowIndex = 2;
          },
        ),
      );
      tester.press(KeySequence.down);
      expect(_currentKey(tester), 'row-2');
      expect(requests, [1]);
      controller.currentColumnIndex = 1;
      expect(requests, [1]);
    },
  );

  testWidgets('switching cursor ownership detaches the old controller', (
    tester,
  ) {
    final controller = DataTableController(initialRowIndex: 4);
    final requests = <int>[];
    tester.pumpWidget(_table(controller: controller));
    tester.pumpWidget(
      _table(currentRowIndex: 2, onFocusedItemChanged: requests.add),
    );
    controller.currentRowIndex = 6;
    expect(_currentKey(tester), 'row-2');
    expect(requests, isEmpty);

    tester.pumpWidget(_table(onFocusedItemChanged: requests.add));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_currentKey(tester), 'row-3');
    expect(requests, [3]);

    tester.pumpWidget(
      _table(controller: controller, onFocusedItemChanged: requests.add),
    );
    expect(_currentKey(tester), 'row-6');
    expect(requests, [3]);
  });

  testWidgets('a browsing callback can replace the table with empty data', (
    tester,
  ) {
    final rows = ValueNotifier(8);
    final requests = <int>[];
    tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rows,
        builder: (context, value, child) => _table(
          rows: value,
          currentRowIndex: 0,
          onFocusedItemChanged: (row) {
            requests.add(row);
            rows.value = 0;
          },
        ),
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(_currentKey(tester), isNull);
    expect(requests, [1]);
  });
}
