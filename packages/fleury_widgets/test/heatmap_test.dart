import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String? _graphemeAt(
  FleuryTester tester,
  int col,
  int row, {
  required int cols,
  required int rows,
}) => tester.render(size: CellSize(cols, rows)).atColRow(col, row).grapheme;

void main() {
  group('Heatmap', () {
    testWidgets('maps values to the quartile block glyphs', (tester) {
      // Single-row heatmap: values 0..1 mapped at 4 quartiles → ░ ▒ ▓ █.
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 1,
          child: Heatmap(
            values: [
              [0.25, 0.5, 0.75, 1.0],
            ],
            cellWidth: 1,
            min: 0,
            max: 1,
          ),
        ),
      );
      expect(_graphemeAt(tester, 0, 0, cols: 4, rows: 1), '░');
      expect(_graphemeAt(tester, 1, 0, cols: 4, rows: 1), '▒');
      expect(_graphemeAt(tester, 2, 0, cols: 4, rows: 1), '▓');
      expect(_graphemeAt(tester, 3, 0, cols: 4, rows: 1), '█');
    });

    testWidgets('leaves zero-value cells empty', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 2,
          height: 1,
          child: Heatmap(
            values: [
              [0, 1],
            ],
            cellWidth: 1,
            min: 0,
            max: 1,
          ),
        ),
      );
      expect(_graphemeAt(tester, 0, 0, cols: 2, rows: 1), isNull);
      expect(_graphemeAt(tester, 1, 0, cols: 2, rows: 1), '█');
    });

    testWidgets('renders non-finite cells as gaps instead of throwing', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 1,
          child: Heatmap(
            values: [
              [1.0, double.nan, 0.5],
            ],
            cellWidth: 1,
            min: 0,
            max: 1,
          ),
        ),
      );
      expect(_graphemeAt(tester, 0, 0, cols: 3, rows: 1), '█');
      expect(_graphemeAt(tester, 1, 0, cols: 3, rows: 1), isNull);
      expect(_graphemeAt(tester, 2, 0, cols: 3, rows: 1), '▒');
    });

    testWidgets('autoscale ignores non-finite cells', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 1,
          child: Heatmap(
            values: [
              [double.nan, 2.0, 4.0],
            ],
            cellWidth: 1,
            min: 0,
          ),
        ),
      );
      // The autoscaled max comes from the finite cells (4): 2 → ▒, 4 → █.
      expect(_graphemeAt(tester, 0, 0, cols: 3, rows: 1), isNull);
      expect(_graphemeAt(tester, 1, 0, cols: 3, rows: 1), '▒');
      expect(_graphemeAt(tester, 2, 0, cols: 3, rows: 1), '█');
    });

    testWidgets('renders column labels above and row labels to the left', (
      tester,
    ) {
      tester.pumpWidget(
        const SizedBox(
          width: 10,
          height: 3,
          child: Heatmap(
            values: [
              [1, 1],
              [1, 1],
            ],
            cellWidth: 1,
            min: 0,
            max: 1,
            colLabels: ['x', 'y'],
            rowLabels: ['A', 'B'],
          ),
        ),
      );
      // Row 0: column labels above the grid.
      // Layout: row labels take 'A' = 1 char + 1 space = 2 cols → grid starts at col 2.
      expect(_graphemeAt(tester, 2, 0, cols: 10, rows: 3), 'x');
      expect(_graphemeAt(tester, 3, 0, cols: 10, rows: 3), 'y');
      // Row 1: 'A' at col 0, then grid.
      expect(_graphemeAt(tester, 0, 1, cols: 10, rows: 3), 'A');
      expect(_graphemeAt(tester, 2, 1, cols: 10, rows: 3), '█');
      // Row 2: 'B' at col 0.
      expect(_graphemeAt(tester, 0, 2, cols: 10, rows: 3), 'B');
    });

    testWidgets('empty values renders nothing and does not crash', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Heatmap(values: [], cellWidth: 1, min: 0, max: 1),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 2));
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c < 4; c++) {
          expect(buf.atColRow(c, r).grapheme, isNull);
        }
      }
    });

    testWidgets('all-equal values do not crash (min == max guard)', (tester) {
      // A degenerate range would be a div-by-zero in the value→glyph map.
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 1,
          child: Heatmap(
            values: [
              [5, 5, 5],
            ],
            cellWidth: 1,
          ),
        ),
      );
      // Just no crash — content can be empty or all-filled.
      tester.render(size: const CellSize(3, 1));
    });

    testWidgets('uses the supplied color for filled cells', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Heatmap(
            values: [
              [1],
            ],
            cellWidth: 1,
            min: 0,
            max: 1,
            color: AnsiColor(2),
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const AnsiColor(2));
    });

    testWidgets('exposes chart semantics and text-first fallback', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 2,
          child: Heatmap(
            semanticLabel: 'Weekly activity',
            values: [
              [0, 2],
              [3, 5],
            ],
            cellWidth: 1,
            rowLabels: ['A', 'B'],
            colLabels: ['x', 'y'],
          ),
        ),
      );

      final chart = tester.semantics().single(
        role: SemanticRole.chart,
        label: 'Weekly activity',
      );
      expect(chart.state.chartType, 'heatmap');
      expect(chart.state.chartRowCount, 2);
      expect(chart.state.chartColumnCount, 2);
      expect(chart.state.chartPointCount, 4);
      expect(chart.state.chartMinValue, 0);
      expect(chart.state.chartMaxValue, 5);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.chart,
        label: 'Weekly activity',
      );
      expect(
        fallback.states,
        contains('chart heatmap, 2 rows, 2 columns, 4 points, min 0, max 5'),
      );
    });
  });
}
