import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

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
      case CellRole.protocolAnchor:
      case CellRole.protocolCovered:
        break;
    }
  }
  return buf.toString();
}

void main() {
  group('RenderAlign', () {
    test('center puts child in the middle when constraints are bounded', () {
      final child = RenderText(text: 'hi', softWrap: false);
      final align = RenderAlign(alignment: Alignment.center, child: child);
      final size = align.layout(
        const CellConstraints(minCols: 10, maxCols: 10, minRows: 3, maxRows: 3),
      );
      expect(size, const CellSize(10, 3));

      final buffer = CellBuffer(const CellSize(10, 3));
      align.paint(buffer, CellOffset.zero);
      expect(_rowContent(buffer, 0), '··········');
      expect(_rowContent(buffer, 1), '····hi····');
      expect(_rowContent(buffer, 2), '··········');
    });

    test('topLeft is the no-offset case', () {
      final align =
          RenderAlign(
            alignment: Alignment.topLeft,
            child: RenderText(text: 'X', softWrap: false),
          )..layout(
            const CellConstraints(
              minCols: 5,
              maxCols: 5,
              minRows: 3,
              maxRows: 3,
            ),
          );
      final buffer = CellBuffer(const CellSize(5, 3));
      align.paint(buffer, CellOffset.zero);
      expect(_rowContent(buffer, 0), 'X····');
      expect(_rowContent(buffer, 1), '·····');
      expect(_rowContent(buffer, 2), '·····');
    });

    test('bottomRight pushes the child to the lower-right corner', () {
      final align =
          RenderAlign(
            alignment: Alignment.bottomRight,
            child: RenderText(text: 'X', softWrap: false),
          )..layout(
            const CellConstraints(
              minCols: 5,
              maxCols: 5,
              minRows: 3,
              maxRows: 3,
            ),
          );
      final buffer = CellBuffer(const CellSize(5, 3));
      align.paint(buffer, CellOffset.zero);
      expect(_rowContent(buffer, 2), '····X');
    });

    test('topCenter pins to the top edge but centers horizontally', () {
      final align =
          RenderAlign(
            alignment: Alignment.topCenter,
            child: RenderText(text: 'X', softWrap: false),
          )..layout(
            const CellConstraints(
              minCols: 5,
              maxCols: 5,
              minRows: 3,
              maxRows: 3,
            ),
          );
      final buffer = CellBuffer(const CellSize(5, 3));
      align.paint(buffer, CellOffset.zero);
      expect(_rowContent(buffer, 0), '··X··');
      expect(_rowContent(buffer, 1), '·····');
      expect(_rowContent(buffer, 2), '·····');
    });

    test('unbounded constraints collapse to child size', () {
      final align = RenderAlign(
        alignment: Alignment.center,
        child: RenderText(text: 'hello', softWrap: false),
      );
      final size = align.layout(const CellConstraints());
      expect(size, const CellSize(5, 1));
    });

    test('Center widget is a sugar for Alignment.center', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Center(child: Text('hi', softWrap: false)),
      );
      final buffer = CellBuffer(const CellSize(6, 3));
      owner.renderFrame(root, buffer);
      // BuildOwner.renderFrame uses CellConstraints.loose(buffer.size),
      // so Center fills the 6x3 region and centers 'hi' at (2, 1).
      expect(_rowContent(buffer, 0), '······');
      expect(_rowContent(buffer, 1), '··hi··');
      expect(_rowContent(buffer, 2), '······');
    });
  });
}
