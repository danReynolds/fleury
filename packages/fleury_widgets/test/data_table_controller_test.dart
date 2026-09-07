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

  testWidgets('dimension updates clamp both range endpoints before notifying', (
    tester,
  ) {
    final controller = DataTableController();
    tester.pumpWidget(_table(controller, 8, 5));
    controller
      ..selectCell(7, 4)
      ..selectCell(1, 0, extend: true);
    final ranges = <DataTableSelectionRange>[];
    controller.addListener(() => ranges.add(controller.selectionRange));

    tester.pumpWidget(_table(controller, 3, 2));

    expect(ranges, hasLength(1));
    expect(ranges.single.anchorRow, 2);
    expect(ranges.single.anchorColumn, 1);
    expect(ranges.single.focusRow, 1);
    expect(ranges.single.focusColumn, 0);
    // Regrowth must not restore a stale stored anchor.
    tester.pumpWidget(_table(controller, 8, 5));
    expect(controller.selectionRange.anchorRow, 2);
    expect(controller.selectionRange.anchorColumn, 1);
  });

  testWidgets('empty data clears the stored range before regrowth', (tester) {
    final controller = DataTableController(
      selectedIndex: 7,
      selectedColumnIndex: 4,
    );
    tester.pumpWidget(_table(controller, 8, 5));
    final observed = <Object>[];
    controller.addListener(() => observed.add(_snapshot(controller)));

    tester.pumpWidget(_table(controller, -1, 0));
    tester.pumpWidget(_table(controller, 8, 5));

    expect(observed, [
      (rows: 0, columns: 0, row: 0, column: 0),
      (rows: 8, columns: 5, row: 0, column: 0),
    ]);
    expect(controller.selectionRange.anchorRow, 0);
    expect(controller.selectionRange.anchorColumn, 0);
  });

  testWidgets('a listener selection is not overwritten by dimension updates', (
    tester,
  ) {
    final controller = DataTableController(
      selectedIndex: 7,
      selectedColumnIndex: 4,
    );
    tester.pumpWidget(_table(controller, 8, 5));
    final observed = <Object>[];
    controller.addListener(() {
      observed.add(_snapshot(controller));
      if (controller.selectedIndex == 2) controller.selectCell(1, 0);
    });

    tester.pumpWidget(_table(controller, 3, 2));

    expect(observed, [
      (rows: 3, columns: 2, row: 2, column: 1),
      (rows: 3, columns: 2, row: 1, column: 0),
    ]);
    expect(_snapshot(controller), observed.last);
    expect(controller.selectionRange.anchorRow, 1);
    expect(controller.selectionRange.anchorColumn, 0);
  });
}
