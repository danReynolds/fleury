import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Bounds chosen so logical units == pixel units on a 4x1-cell canvas:
/// 8x4 pixels, x in [0,7], y in [0,3] (y=0 is the bottom pixel row).
const _pixelBounds = CanvasBounds(minX: 0, maxX: 7, minY: 0, maxY: 3);

class _Stroke implements CanvasPainter {
  const _Stroke(this.width);
  final double width;
  @override
  void paint(CanvasContext ctx) => ctx.drawLine(0, 1, 7, 1, width: width); // py = 3 - 1 = 2
}

class _DiagonalStroke implements CanvasPainter {
  const _DiagonalStroke(this.width);
  final double width;
  @override
  void paint(CanvasContext ctx) => ctx.drawLine(0, 0, 7, 3, width: width);
}

/// Decodes which of the 4 pixel rows have any lit dot in [col] of the
/// rendered cell row, via the braille codepoint's dot bits.
Set<int> _litPixelRows(FleuryTester tester, int col) {
  final cell = tester.render(size: const CellSize(4, 1)).atColRow(col, 0);
  final g = cell.grapheme;
  if (g == null) return const {};
  final mask = g.codeUnitAt(0) - 0x2800;
  final rows = <int>{};
  // Braille bits by (px, py): see BrailleBuffer._bitFor.
  const bitsByRow = [
    [0, 3], // py 0 → dots 1, 4
    [1, 4], // py 1 → dots 2, 5
    [2, 5], // py 2 → dots 3, 6
    [6, 7], // py 3 → dots 7, 8
  ];
  for (var py = 0; py < 4; py++) {
    if (bitsByRow[py].any((b) => mask & (1 << b) != 0)) rows.add(py);
  }
  return rows;
}

int _litCount(FleuryTester tester) {
  var count = 0;
  for (var col = 0; col < 4; col++) {
    final cell = tester.render(size: const CellSize(4, 1)).atColRow(col, 0);
    final g = cell.grapheme;
    if (g == null) continue;
    var mask = g.codeUnitAt(0) - 0x2800;
    while (mask != 0) {
      count += mask & 1;
      mask >>= 1;
    }
  }
  return count;
}

Widget _canvas(CanvasPainter painter) => SizedBox(
  width: 4,
  height: 1,
  child: Canvas(bounds: _pixelBounds, painter: painter),
);

void main() {
  group('Canvas stroke width', () {
    testWidgets('the default stays a hairline — one pixel row', (tester) {
      tester.pumpWidget(_canvas(const _Stroke(1)));
      for (var col = 0; col < 4; col++) {
        expect(_litPixelRows(tester, col), {2}, reason: 'col $col');
      }
    });

    testWidgets('width 3 spans three pixel rows along the whole line', (
      tester,
    ) {
      tester.pumpWidget(_canvas(const _Stroke(3)));
      for (var col = 0; col < 4; col++) {
        expect(_litPixelRows(tester, col), {1, 2, 3}, reason: 'col $col');
      }
    });

    testWidgets('a thick diagonal is denser than the hairline, no gaps', (
      tester,
    ) {
      tester.pumpWidget(_canvas(const _DiagonalStroke(1)));
      final thin = _litCount(tester);
      tester.pumpWidget(_canvas(const _DiagonalStroke(2)));
      final thick = _litCount(tester);
      expect(thick, greaterThanOrEqualTo(thin * 2), reason: '$thin → $thick');
      // Every pixel column along the diagonal has at least one lit dot.
      for (var col = 0; col < 4; col++) {
        expect(_litPixelRows(tester, col), isNotEmpty, reason: 'col $col');
      }
    });
  });
}
