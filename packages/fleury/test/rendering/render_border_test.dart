import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// Renders a single buffer row as a string, using a `·` placeholder
/// for empty cells and skipping wide-grapheme continuation cells.
String _rowContent(CellBuffer buffer, int row) {
  final buf = StringBuffer();
  for (var col = 0; col < buffer.size.cols; col++) {
    final cell = buffer.atColRow(col, row);
    switch (cell.role) {
      case CellRole.empty:
        buf.write('·');
      case CellRole.leading:
        buf.write(cell.grapheme);
      case CellRole.continuation:
      case CellRole.overlay:
        break;
    }
  }
  return buf.toString();
}

void main() {
  group('RenderBorder layout', () {
    test('adds 1 cell on each side of the child', () {
      final child = RenderText(text: 'abc', softWrap: false);
      final border = RenderBorder(border: const BoxBorder(), child: child);
      final size = border.layout(
        const CellConstraints(maxCols: 10, maxRows: 10),
      );
      expect(size, const CellSize(5, 3)); // 3 + 2 wide, 1 + 2 tall
    });

    test('with no child collapses to 2x2 minimum', () {
      final border = RenderBorder(border: const BoxBorder());
      final size = border.layout(
        const CellConstraints(maxCols: 10, maxRows: 10),
      );
      expect(size, const CellSize(2, 2));
    });

    test('passes through tight constraints minus the frame', () {
      final child = RenderText(text: 'abc');
      RenderBorder(
        border: const BoxBorder(),
        child: child,
      ).layout(const CellConstraints(maxCols: 5));
      // Child gets maxCols=3 (5 - 2 frame). 'abc' fits, no wrap.
      expect(child.size, const CellSize(3, 1));
    });
  });

  group('RenderBorder paint', () {
    test('draws single-line glyphs around the child', () {
      final child = RenderText(text: 'hi');
      final border = RenderBorder(border: const BoxBorder(), child: child)
        ..layout(const CellConstraints(maxCols: 4, maxRows: 3));
      final buf = CellBuffer(const CellSize(4, 3));
      border.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), '┌──┐');
      expect(_rowContent(buf, 1), '│hi│');
      expect(_rowContent(buf, 2), '└──┘');
    });

    test('switches to rounded corners with BorderStyle.rounded', () {
      final border = RenderBorder(
        border: const BoxBorder(style: BorderStyle.rounded),
        child: RenderText(text: 'x'),
      )..layout(const CellConstraints(maxCols: 3, maxRows: 3));
      final buf = CellBuffer(const CellSize(3, 3));
      border.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), '╭─╮');
      expect(_rowContent(buf, 2), '╰─╯');
    });

    test('uses double-line glyphs for BorderStyle.double', () {
      final border = RenderBorder(
        border: const BoxBorder(style: BorderStyle.double),
        child: RenderText(text: 'x'),
      )..layout(const CellConstraints(maxCols: 3, maxRows: 3));
      final buf = CellBuffer(const CellSize(3, 3));
      border.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), '╔═╗');
      expect(_rowContent(buf, 1), '║x║');
      expect(_rowContent(buf, 2), '╚═╝');
    });

    test('uses ASCII fallback for BorderStyle.ascii', () {
      final border = RenderBorder(
        border: const BoxBorder(style: BorderStyle.ascii),
        child: RenderText(text: 'x'),
      )..layout(const CellConstraints(maxCols: 3, maxRows: 3));
      final buf = CellBuffer(const CellSize(3, 3));
      border.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), '+-+');
      expect(_rowContent(buf, 1), '|x|');
      expect(_rowContent(buf, 2), '+-+');
    });

    test('skips the frame when assigned size is too small', () {
      // With a 1x1 viewport, drawing a real border would be garbled —
      // we paint the child in place instead.
      final border = RenderBorder(
        border: const BoxBorder(),
        child: RenderText(text: 'x'),
      )..layout(const CellConstraints(maxCols: 1, maxRows: 1));
      final buf = CellBuffer(const CellSize(1, 1));
      border.paint(buf, CellOffset.zero);
      // Child is painted with no frame.
      expect(_rowContent(buf, 0), 'x');
    });

    test('paints at an offset within the parent buffer', () {
      final border = RenderBorder(
        border: const BoxBorder(),
        child: RenderText(text: 'a'),
      )..layout(const CellConstraints(maxCols: 3, maxRows: 3));
      final buf = CellBuffer(const CellSize(6, 4));
      border.paint(buf, const CellOffset(2, 1));
      expect(_rowContent(buf, 0), '······');
      expect(_rowContent(buf, 1), '··┌─┐·');
      expect(_rowContent(buf, 2), '··│a│·');
      expect(_rowContent(buf, 3), '··└─┘·');
    });
  });

  group('BoxBorder equality', () {
    test('equal borders compare equal', () {
      expect(
        const BoxBorder(style: BorderStyle.rounded),
        const BoxBorder(style: BorderStyle.rounded),
      );
    });

    test('different styles compare unequal', () {
      expect(
        const BoxBorder(style: BorderStyle.single) ==
            const BoxBorder(style: BorderStyle.double),
        isFalse,
      );
    });
  });
}
