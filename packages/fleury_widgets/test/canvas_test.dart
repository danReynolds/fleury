import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _DotAt implements CanvasPainter {
  const _DotAt(this.x, this.y, [this.color]);
  final double x;
  final double y;
  final Color? color;
  @override
  void paint(CanvasContext ctx) => ctx.drawDot(x, y, color: color);
}

class _LineFromTo implements CanvasPainter {
  const _LineFromTo(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
  @override
  void paint(CanvasContext ctx) => ctx.drawLine(x1, y1, x2, y2);
}

int _codepointAt(
  FleuryTester tester,
  int col,
  int row, {
  required int cols,
  required int rows,
}) {
  final cell = tester.render(size: CellSize(cols, rows)).atColRow(col, row);
  final g = cell.grapheme;
  return g == null ? -1 : g.codeUnitAt(0);
}

void main() {
  group('Canvas', () {
    testWidgets('a dot at logical (0, 0) lights the bottom-left pixel', (
      tester,
    ) {
      // 1x1 canvas = 2x4 pixels. (0, 0) → bottom-left → dot 7 (bit 6).
      // Glyph: 0x2800 + (1 << 6) = 0x2840 (⡀).
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Canvas(painter: _DotAt(0, 0)),
        ),
      );
      expect(_codepointAt(tester, 0, 0, cols: 1, rows: 1), 0x2840);
    });

    testWidgets('a dot at logical (1, 1) lights the top-right pixel', (tester) {
      // 1x1 canvas = 2x4 pixels. (1, 1) → top-right → dot 4 (bit 3).
      // Glyph: 0x2800 + (1 << 3) = 0x2808 (⠈).
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Canvas(painter: _DotAt(1, 1)),
        ),
      );
      expect(_codepointAt(tester, 0, 0, cols: 1, rows: 1), 0x2808);
    });

    testWidgets('a horizontal line fills every cell in the row', (tester) {
      // 4x1 canvas; line across the bottom (y=0). Every cell should have at
      // least one dot lit (codepoint > 0x2800).
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 1,
          child: Canvas(painter: _LineFromTo(0, 0, 1, 0)),
        ),
      );
      for (var c = 0; c < 4; c++) {
        expect(
          _codepointAt(tester, c, 0, cols: 4, rows: 1),
          greaterThan(0x2800),
          reason: 'cell $c should hold a braille glyph',
        );
      }
    });

    testWidgets('uses the painter-supplied color', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 1,
          height: 1,
          child: Canvas(painter: _DotAt(0, 0, AnsiColor(1))),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const AnsiColor(1));
    });
  });
}
