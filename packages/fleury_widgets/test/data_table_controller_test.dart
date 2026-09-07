import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<DataTableColumn> _columns(int count) => [
  for (var i = 0; i < count; i++) DataTableColumn(id: '$i', title: '$i'),
];

DataTable _table(DataTableController controller, int rows, int columns) =>
    DataTable(
      controller: controller,
      rowCount: rows,
      columns: _columns(columns),
      cellBuilder: (row, column) => '$row,$column',
    );

({int rows, int columns, int row, int column}) _snapshot(
  DataTableController controller,
) => (
  rows: controller.rowCount,
  columns: controller.columnCount,
  row: controller.selectedIndex,
  column: controller.selectedColumnIndex,
);

void main() {
  testWidgets('mount publishes only the fully clamped dimensions and cell', (
    tester,
  ) {
    final controller = DataTableController(
      selectedIndex: 4,
      selectedColumnIndex: 2,
    );
    final observed = <Object>[];
    controller.addListener(() => observed.add(_snapshot(controller)));

    tester.pumpWidget(_table(controller, 1, 1));

    expect(observed, [(rows: 1, columns: 1, row: 0, column: 0)]);
  });

  testWidgets('shrinking rows and columns never exposes a removed cell', (
    tester,
  ) {
    final controller = DataTableController(
      selectedIndex: 4,
      selectedColumnIndex: 2,
    );
    var data = List.generate(5, (_) => ['a', 'b', 'c']);
    Widget table() => DataTable(
      controller: controller,
      rowCount: data.length,
      columns: _columns(data.first.length),
      cellBuilder: (row, column) => data[row][int.parse(column)],
    );
    tester.pumpWidget(table());
    final observedCells = <String>[];
    final observedStates = <Object>[];
    controller.addListener(() {
      observedStates.add(_snapshot(controller));
      observedCells.add(
        data[controller.selectedIndex][controller.selectedColumnIndex],
      );
    });

    data = [
      ['only cell'],
    ];
    tester.pumpWidget(table());

    expect(observedStates, [(rows: 1, columns: 1, row: 0, column: 0)]);
    expect(observedCells, ['only cell']);
  });

  testWidgets('replacement controller receives one coherent update', (tester) {
    final oldController = DataTableController();
    tester.pumpWidget(_table(oldController, 5, 3));
    final controller = DataTableController(
      selectedIndex: 4,
      selectedColumnIndex: 2,
    );
    final observed = <Object>[];
    controller.addListener(() => observed.add(_snapshot(controller)));

    tester.pumpWidget(_table(controller, 1, 1));

    expect(observed, [(rows: 1, columns: 1, row: 0, column: 0)]);
    expect(_snapshot(oldController), (rows: 5, columns: 3, row: 0, column: 0));
  });

  testWidgets(
    'dimension-only changes notify once and unchanged rebuilds do not',
    (tester) {
      final controller = DataTableController();
      tester.pumpWidget(_table(controller, 1, 1));
      final observed = <Object>[];
      controller.addListener(() => observed.add(_snapshot(controller)));

      tester.pumpWidget(_table(controller, 5, 3));
      tester.pumpWidget(_table(controller, 5, 3));

      expect(observed, [(rows: 5, columns: 3, row: 0, column: 0)]);
    },
  );

  testWidgets('a newly added row can be selected before the next build', (
    tester,
  ) {
    final controller = DataTableController();
    tester.pumpWidget(_table(controller, 1, 1));
    final observed = <Object>[];
    controller.addListener(() => observed.add(_snapshot(controller)));

    controller.update(rowCount: 5, selectedIndex: 4);
    expect(_snapshot(controller), (rows: 5, columns: 1, row: 4, column: 0));
    tester.pumpWidget(_table(controller, 5, 1));

    expect(observed, [(rows: 5, columns: 1, row: 4, column: 0)]);
    expect(controller.selectedIndex, 4);
  });

  test('dimension updates clamp both range endpoints before notifying', () {
    final controller = DataTableController()
      ..update(rowCount: 8, columnCount: 5)
      ..selectCell(7, 4)
      ..selectCell(1, 0, extend: true);
    final ranges = <DataTableSelectionRange>[];
    controller.addListener(() => ranges.add(controller.selectionRange));

    controller.update(rowCount: 3, columnCount: 2);

    expect(ranges, hasLength(1));
    expect(ranges.single.anchorRow, 2);
    expect(ranges.single.anchorColumn, 1);
    expect(ranges.single.focusRow, 1);
    expect(ranges.single.focusColumn, 0);
    // The stored anchor must also be clamped, not only the getter's result.
    controller.update(rowCount: 8, columnCount: 5);
    expect(controller.selectionRange.anchorRow, 2);
    expect(controller.selectionRange.anchorColumn, 1);
  });

  test('explicit selection collapses a range against the new dimensions', () {
    final controller = DataTableController()
      ..update(rowCount: 8, columnCount: 5)
      ..selectCell(7, 4)
      ..selectCell(1, 0, extend: true);
    final observed = <Object>[];
    controller.addListener(() => observed.add(_snapshot(controller)));

    controller.update(
      rowCount: 3,
      columnCount: 2,
      selectedIndex: 20,
      selectedColumnIndex: 20,
    );

    expect(observed, [(rows: 3, columns: 2, row: 2, column: 1)]);
    expect(controller.selectionRange.rowCount, 1);
    expect(controller.selectionRange.columnCount, 1);
  });

  test(
    'empty data clears the range and selection can be restored on growth',
    () {
      final controller = DataTableController()
        ..update(
          rowCount: 8,
          columnCount: 5,
          selectedIndex: 7,
          selectedColumnIndex: 4,
        );
      final observed = <Object>[];
      controller.addListener(() => observed.add(_snapshot(controller)));

      controller.update(rowCount: -1, columnCount: -1);
      controller.update(
        rowCount: 8,
        columnCount: 5,
        selectedIndex: 7,
        selectedColumnIndex: 4,
      );

      expect(observed, [
        (rows: 0, columns: 0, row: 0, column: 0),
        (rows: 8, columns: 5, row: 7, column: 4),
      ]);
    },
  );

  test(
    'a listener can replace the update without the outer call overwriting it',
    () {
      final controller = DataTableController()
        ..update(
          rowCount: 8,
          columnCount: 5,
          selectedIndex: 7,
          selectedColumnIndex: 4,
        );
      final observed = <Object>[];
      controller.addListener(() {
        observed.add(_snapshot(controller));
        if (controller.rowCount == 3) {
          controller.update(
            rowCount: 6,
            columnCount: 4,
            selectedIndex: 5,
            selectedColumnIndex: 3,
          );
        }
      });

      controller.update(rowCount: 3, columnCount: 2);

      expect(observed, [
        (rows: 3, columns: 2, row: 2, column: 1),
        (rows: 6, columns: 4, row: 5, column: 3),
      ]);
      expect(_snapshot(controller), observed.last);
      expect(controller.selectionRange.anchorRow, 5);
      expect(controller.selectionRange.anchorColumn, 3);
    },
  );

  test('an empty update preserves the initial selection before mounting', () {
    final controller = DataTableController(
      selectedIndex: 4,
      selectedColumnIndex: 2,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.update();

    expect(controller.selectedIndex, 4);
    expect(controller.selectedColumnIndex, 2);
    expect(notifications, 0);
  });

  test('no-op updates are silent and updates after disposal throw', () {
    final controller = DataTableController()
      ..update(rowCount: 5, columnCount: 3);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.update();
    controller.update(rowCount: 5, columnCount: 3);
    expect(notifications, 0);
    controller.dispose();
    expect(() => controller.update(rowCount: 2), throwsStateError);
  });
}
