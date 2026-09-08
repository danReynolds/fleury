import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const columns = [
  DataTableColumn(id: 'name', title: 'Name', width: FixedColumnWidth(8)),
  DataTableColumn(id: 'value', title: 'Value', width: FixedColumnWidth(8)),
];

String cell(int row, String column) => '$column-$row';

void pointer(
  FleuryTester tester,
  MouseEventKind kind, {
  int col = 1,
  int row = 3,
  bool shift = false,
}) => tester.sendMouse(
  MouseEvent(
    kind: kind,
    button: MouseButton.left,
    col: col,
    row: row,
    modifiers: shift ? {KeyModifier.shift} : {},
  ),
);

void click(
  FleuryTester tester, {
  int col = 1,
  int row = 3,
  bool shift = false,
}) {
  pointer(tester, MouseEventKind.down, col: col, row: row, shift: shift);
  pointer(tester, MouseEventKind.up, col: col, row: row, shift: shift);
}

void wheel(FleuryTester tester) => tester.sendMouse(
  const MouseEvent(
    kind: MouseEventKind.scrollDown,
    button: MouseButton.none,
    col: 1,
    row: 3,
  ),
);

void main() {
  testWidgets(
    'browsing reports focus; click, Enter and semantic select confirm',
    (tester) async {
      final events = <String>[];
      final controller = DataTableController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        DataTable(
          rowCount: 10,
          columns: columns,
          cellBuilder: cell,
          controller: controller,
          autofocus: true,
          onFocusedItemChanged: (row) => events.add('focus $row'),
          onSelect: (row) => events.add('select $row'),
        ),
      );
      tester.press(KeySequence.down);
      expect(events, ['focus 1']);
      tester.press(KeySequence.enter);
      tester.press(KeySequence.enter);
      expect(events, ['focus 1', 'select 1', 'select 1']);
      tester.render(size: const CellSize(20, 6));
      click(tester); // same row, still a choice
      expect(events.last, 'select 1');
      final row = tester.target(role: SemanticRole.tableRow, label: '2');
      await row.focus();
      expect(row, isFocused);
      expect(events.last, 'focus 2');
      await row.select();
      await row.press();
      expect(events.sublist(4), ['focus 2', 'select 2', 'select 2']);
      events.clear();
      controller.currentRowIndex = 4;
      tester.pump();
      wheel(tester);
      expect(events, isEmpty);
      expect(controller.currentRowIndex, 4);
    },
  );

  testWidgets('cell cursor, selected range and row command stay independent', (
    tester,
  ) async {
    final controller = DataTableController();
    addTearDown(controller.dispose);
    final ranges = <DataTableSelectionRange>[];
    final actions = <int>[];
    final focused = <int>[];
    DataTableCopyResult? copied;
    tester.pumpWidget(
      DataTable(
        rowCount: 20,
        columns: columns,
        cellBuilder: cell,
        controller: controller,
        autofocus: true,
        selectionMode: DataTableSelectionMode.cell,
        onFocusedItemChanged: focused.add,
        onRangeChanged: ranges.add,
        onAction: actions.add,
        onCopy: (result) => copied = result,
        copyOptions: const DataTableCopyOptions(
          clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
        ),
      ),
    );
    tester.render(size: const CellSize(20, 7));
    click(tester, col: 10, row: 3);
    click(tester, col: 10, row: 4, shift: true);
    final selection = controller.selectionRange;
    expect(selection.startRow, 1);
    expect(selection.endRow, 2);
    expect(selection.columnCount, 1);
    expect(ranges, hasLength(2));
    expect(actions, isEmpty);

    tester.press(KeySequence.down);
    tester.press(KeySequence.left);
    expect(controller.currentRowIndex, 3);
    expect(controller.currentColumnIndex, 0);
    expect(controller.selectionRange, selection);
    expect(ranges, hasLength(2));
    expect(focused, [1, 2, 3]);
    expect(
      tester.target(role: SemanticRole.tableCell, label: 'name-3'),
      isFocused,
    );
    expect(
      tester
          .target(role: SemanticRole.tableCell, label: 'name-3')
          .snapshot
          .selected,
      isFalse,
    );
    await tester.target(role: SemanticRole.table).copy();
    expect(copied?.text, 'Value\nvalue-1\nvalue-2');
    expect(copied?.rowIndex, 2);
    tester.press(KeySequence.enter);
    expect(actions, [3]);
    expect(controller.selectionRange, selection);

    // Space selects the current cell; repeating it is not a range change.
    tester.press(KeySequence.space);
    tester.press(KeySequence.space);
    expect(controller.selectionRange.startRow, 3);
    expect(controller.selectionRange.startColumn, 0);
    expect(controller.selectionRange.rowCount, 1);
    expect(ranges, hasLength(3));
    expect(actions, [3]);
    await tester
        .target(role: SemanticRole.tableCell, label: 'value-1')
        .select();
    expect(ranges, hasLength(4));
    expect(actions, [3]);
    await tester.target(role: SemanticRole.tableCell, label: 'name-2').press();
    expect(actions, [3, 2]);
    expect(controller.selectionRange.startRow, 1);
  });

  testWidgets(
    'cell commands require a completed double-click on the same cell',
    (tester) {
      final actions = <int>[];
      final ranges = <DataTableSelectionRange>[];
      Widget table() => DataTable(
        rowCount: 10,
        columns: [...columns],
        cellBuilder: cell,
        selectionMode: DataTableSelectionMode.cell,
        onAction: actions.add,
        onRangeChanged: ranges.add,
      );
      tester.pumpWidget(table());
      tester.render(size: const CellSize(20, 6));
      click(tester);
      expect(actions, isEmpty);
      tester.pumpWidget(table()); // ordinary rebuild recreates the column list
      click(tester);
      expect(actions, [1]);
      expect(ranges, hasLength(1));
      click(tester, row: 4);
      click(tester, row: 4, col: 10);
      expect(actions, [
        1,
      ], reason: 'different cells do not make a double-click');
      click(tester, row: 4, col: 10, shift: true);
      expect(actions, [1]);
      wheel(tester);
      click(tester, row: 4, col: 10);
      expect(actions, [1], reason: 'scrolling ends the click sequence');
    },
  );

  testWidgets(
    'dragging, releasing elsewhere and replacing a pressed row cancel',
    (tester) {
      final rows = ['a', 'b', 'c', 'd'];
      final actions = <int>[];
      tester.pumpWidget(
        DataTable(
          rowCount: rows.length,
          columns: columns,
          cellBuilder: cell,
          rowKeyBuilder: (row) => rows[row],
          onSelect: actions.add,
        ),
      );
      tester.render(size: const CellSize(20, 6));
      pointer(tester, MouseEventKind.down);
      expect(actions, isEmpty);
      pointer(tester, MouseEventKind.drag, col: 4);
      pointer(tester, MouseEventKind.up);
      pointer(tester, MouseEventKind.down);
      pointer(tester, MouseEventKind.up, row: 4);
      pointer(tester, MouseEventKind.down);
      rows[1] = 'replacement';
      pointer(tester, MouseEventKind.up);
      expect(actions, isEmpty);
      click(tester);
      expect(actions, [1]);
    },
  );

  testWidgets('a preview callback cannot redirect the pending row command', (
    tester,
  ) async {
    final controller = DataTableController();
    addTearDown(controller.dispose);
    final actions = <int>[];
    tester.pumpWidget(
      DataTable(
        rowCount: 5,
        columns: columns,
        cellBuilder: cell,
        controller: controller,
        onFocusedItemChanged: (_) => controller.currentRowIndex = 0,
        onSelect: actions.add,
      ),
    );
    tester.render(size: const CellSize(20, 6));
    click(tester);
    expect(controller.currentRowIndex, 0);
    expect(actions, isEmpty);
    await tester.target(role: SemanticRole.tableRow, label: '2').press();
    expect(actions, isEmpty);
  });

  testWidgets('unmounting during a preview does not call a row command', (
    tester,
  ) {
    final actions = <int>[];
    tester.pumpWidget(
      DataTable(
        rowCount: 5,
        columns: columns,
        cellBuilder: cell,
        onFocusedItemChanged: (_) => tester.pumpWidget(const SizedBox()),
        onSelect: actions.add,
      ),
    );
    tester.render(size: const CellSize(20, 6));
    click(tester);
    expect(actions, isEmpty);
  });

  testWidgets(
    'scrolling survives rebuilding and hit tests the displayed rows',
    (tester) {
      final controller = DataTableController();
      addTearDown(controller.dispose);
      final actions = <int>[];
      Widget table(int count) => DataTable(
        rowCount: count,
        columns: columns,
        cellBuilder: cell,
        controller: controller,
        onSelect: actions.add,
        autofocus: true,
      );
      tester.pumpWidget(table(100000));
      tester.render(size: const CellSize(20, 6));
      wheel(tester);
      wheel(tester);
      final range = controller.selectionRange;
      expect(controller.currentRowIndex, 0);
      tester.pumpWidget(table(100000));
      tester.render(size: const CellSize(20, 6));
      final target = tester.target(role: SemanticRole.table);
      expect(target.snapshot.state.visibleRangeStart, 2);
      expect(controller.selectionRange, range);
      expect(tester.semantics().byRole(SemanticRole.tableRow), hasLength(5));
      click(tester); // second displayed row is source row 3
      expect(actions, [3]);
      expect(controller.currentRowIndex, 3);
      wheel(tester);
      wheel(tester);
      expect(target.snapshot.state.visibleRangeStart, 4);
      controller.currentRowIndex = 3; // reveal even though cursor is unchanged
      tester.pump();
      expect(target.snapshot.state.visibleRangeStart, 3);
      tester.pumpWidget(table(2));
      expect(controller.currentRowIndex, 1);
      expect(target.snapshot.state.visibleRangeStart, 0);
      expect(actions, [3]);
    },
  );

  testWidgets('replacing the controller reveals its initial current row', (
    tester,
  ) {
    final first = DataTableController();
    final second = DataTableController(initialRowIndex: 50);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget table(DataTableController controller) => DataTable(
      rowCount: 100,
      columns: columns,
      cellBuilder: cell,
      controller: controller,
    );
    tester.pumpWidget(table(first));
    tester.render(size: const CellSize(20, 6));
    tester.pumpWidget(table(second));
    final state = tester.target(role: SemanticRole.table).snapshot.state;
    expect(state.currentRowIndex, 50);
    expect(state.visibleRangeEnd, 50);
  });

  test('callbacks reject an incompatible selection mode', () {
    expect(
      () => DataTable(
        rowCount: 1,
        columns: columns,
        cellBuilder: cell,
        onAction: (_) {},
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => DataTable(
        rowCount: 1,
        columns: columns,
        cellBuilder: cell,
        onRangeChanged: (_) {},
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => DataTable(
        rowCount: 1,
        columns: columns,
        cellBuilder: cell,
        selectionMode: DataTableSelectionMode.cell,
        onSelect: (_) {},
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
