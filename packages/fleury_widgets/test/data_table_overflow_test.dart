import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Rows of the rendered grid — leading graphemes only, right-trimmed.
List<String> _lines(
  FleuryTester tester, {
  required int cols,
  required int rows,
}) {
  final buf = tester.render(size: CellSize(cols, rows));
  return [
    for (var r = 0; r < rows; r++)
      [
        for (var c = 0; c < cols; c++)
          buf.atColRow(c, r).role == CellRole.leading
              ? buf.atColRow(c, r).grapheme!
              : ' ',
      ].join().trimRight(),
  ];
}

void main() {
  testWidgets(
    'DataTable never paints past its own box, even when its fixed columns '
    'need more room than it was given',
    (tester) {
      // Two 8-cell fixed columns need 17 cells; the table gets 10. A cell
      // write that ran to the column's full width landed to the right of the
      // table — outside its own rect, past what damage tracking, repaint
      // caches and the serve wire's damage bounds account for, so the
      // corruption could outlive the frame that caused it.
      tester.pumpWidget(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 10,
              child: DataTable(
                rowCount: 3,
                columns: const [
                  DataTableColumn(
                    id: 'run',
                    title: 'Run',
                    width: FixedColumnWidth(8),
                  ),
                  DataTableColumn(
                    id: 'status',
                    title: 'Status',
                    width: FixedColumnWidth(8),
                  ),
                ],
                cellBuilder: (row, id) =>
                    id == 'run' ? 'run-$row' : 'status-$row',
              ),
            ),
            const Text('|SIBLING'),
          ],
        ),
      );
      final lines = _lines(tester, cols: 30, rows: 6);
      final grid = lines.join('\n');

      // The sibling on the header row is untouched.
      expect(lines[0].substring(10), '|SIBLING', reason: grid);
      // Every other row ends inside the table's 10 columns.
      for (var r = 1; r < lines.length; r++) {
        expect(
          lines[r].length,
          lessThanOrEqualTo(10),
          reason: 'row $r painted past the box:\n$grid',
        );
      }
      // What fits is still shown: column 0 in full, column 1 cut at the edge.
      expect(lines[0], startsWith('Run'));
      expect(lines[2], startsWith('run-0'));
      expect(
        lines[2].length,
        10,
        reason: 'the cut column still shows its first cell:\n$grid',
      );
    },
  );
}
