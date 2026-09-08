import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../lib/datatable_rows.dart';
import '../lib/datatable_cells.dart';

void main() {
  testWidgets('row demo distinguishes browsing from choosing', (tester) async {
    tester.pumpWidget(const TableRows());
    tester.press(KeySequence.down);
    expect(tester.exists(text('Browsing: Row 2')), isTrue);
    expect(tester.exists(text('Chosen: None')), isTrue);
    tester.press(KeySequence.enter);
    expect(tester.exists(text('Chosen: Row 2')), isTrue);
    expect(
      tester.renderToString(size: const CellSize(30, 12)),
      contains('Chosen: Row 2'),
    );
    await tester.target(role: SemanticRole.tableRow, label: '3').select();
    expect(tester.exists(text('Chosen: Row 4')), isTrue);
  });

  testWidgets(
    'cell demo distinguishes range selection, navigation and commands',
    (tester) async {
      tester.pumpWidget(const TableCells());
      tester.press(KeySequence.shift.down);
      tester.press(KeySequence.shift.right);
      expect(tester.exists(text('Range: 2 × 2')), isTrue);
      tester.press(KeySequence.down);
      expect(tester.exists(text('Range: 2 × 2')), isTrue);
      expect(tester.exists(text('No row opened')), isTrue);
      tester.press(KeySequence.enter);
      expect(tester.exists(text('Opened row 3')), isTrue);
      expect(
        tester.renderToString(size: const CellSize(30, 12)),
        contains('Opened row 3'),
      );
      await tester.target(role: SemanticRole.table).copy();
      expect(tester.exists(text('Copied 2 × 2')), isTrue);
    },
  );
}
