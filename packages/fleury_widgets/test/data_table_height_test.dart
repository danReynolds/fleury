import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

DataTable table({bool shrinkWrap = false, int rows = 2}) => DataTable(
  rowCount: rows,
  shrinkWrap: shrinkWrap,
  columns: const [
    DataTableColumn(id: 'name', title: 'Name', width: FixedColumnWidth(12)),
  ],
  cellBuilder: (row, _) => 'row $row',
);
void main() {
  testWidgets('unbounded table names its required parent layout', (tester) {
    expect(
      () => tester.pumpWidget(Column(children: [table()])),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message.toString(),
          'message',
          contains('Expanded'),
        ),
      ),
    );
  });
  testWidgets('small unbounded tables explicitly opt into shrink wrapping', (
    tester,
  ) {
    tester.pumpWidget(
      Column(children: [table(shrinkWrap: true), const Text('after')]),
    );
    final text = tester.renderToString(size: const CellSize(20, 8));
    expect(text, contains('row 1'));
    expect(text.split('\n')[4], startsWith('after'));
  });
  testWidgets('bounded large tables only read visible rows', (tester) {
    var reads = 0;
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 6,
        child: DataTable(
          rowCount: 100000,
          columns: const [DataTableColumn(id: 'name', title: 'Name')],
          cellBuilder: (row, _) {
            reads++;
            return '$row';
          },
        ),
      ),
    );
    tester.render(size: const CellSize(20, 6));
    expect(reads, lessThan(50));
  });
}
