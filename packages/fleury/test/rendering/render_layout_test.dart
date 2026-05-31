import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('RenderSizedBox', () {
    test('fixed width and height override constraints', () {
      final r = RenderSizedBox(width: 5, height: 3);
      final size = r.layout(const CellConstraints(maxCols: 100, maxRows: 100));
      expect(size, const CellSize(5, 3));
    });

    test('null width/height defers to incoming constraints', () {
      final r = RenderSizedBox();
      final size = r.layout(const CellConstraints(maxCols: 10, maxRows: 4));
      // No child, no preferred size — collapses to constraints.min.
      expect(size, const CellSize(0, 0));
    });

    test('imposes its size on its child', () {
      final child = RenderText(text: 'long text here');
      final r = RenderSizedBox(width: 5, height: 1, child: child);
      r.layout(const CellConstraints(maxCols: 100, maxRows: 100));
      expect(r.size, const CellSize(5, 1));
      expect(child.size, const CellSize(5, 1));
    });

    test('paint forwards to the child', () {
      final child = RenderText(text: 'hi');
      final r = RenderSizedBox(width: 4, height: 1, child: child);
      r.layout(const CellConstraints());
      final buf = CellBuffer(const CellSize(4, 1));
      r.paint(buf, CellOffset.zero);
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(1, 0).grapheme, 'i');
    });

    test('replacing the child detaches the previous one', () {
      final a = RenderText(text: 'a');
      final b = RenderText(text: 'b');
      final r = RenderSizedBox(child: a);
      expect(a.parent, same(r));
      r.child = b;
      expect(a.parent, isNull);
      expect(b.parent, same(r));
    });
  });

  group('RenderPadding', () {
    test('expands child by the inset amount on each axis', () {
      final child = RenderText(text: 'abc');
      final r = RenderPadding(padding: const EdgeInsets.all(1), child: child);
      final size = r.layout(const CellConstraints());
      // child is 3x1; padding adds 2 to each axis → 5x3.
      expect(size, const CellSize(5, 3));
    });

    test('asymmetric padding shifts the child accordingly when painted', () {
      final child = RenderText(text: 'X');
      final r = RenderPadding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: child,
      );
      r.layout(const CellConstraints());
      final buf = CellBuffer(const CellSize(4, 3));
      r.paint(buf, CellOffset.zero);
      // 'X' should land at (col 2, row 1).
      expect(buf.atColRow(2, 1).grapheme, 'X');
      // Everywhere else is empty.
      expect(buf.atColRow(0, 0).role, CellRole.empty);
      expect(buf.atColRow(1, 0).role, CellRole.empty);
      expect(buf.atColRow(3, 1).role, CellRole.empty);
    });

    test('subtracts horizontal/vertical insets from child constraints', () {
      // The child should see maxCols = 10 - 2 = 8.
      final child = RenderText(text: 'abcdefghij');
      final r = RenderPadding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: child,
      );
      r.layout(const CellConstraints(maxCols: 10));
      expect(child.size.cols, 8);
      expect(r.size.cols, 10);
    });

    test('clamps to zero rather than passing negative constraints', () {
      final child = RenderText(text: 'a');
      final r = RenderPadding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: child,
      );
      // Available width 4 minus 20 horizontal padding would be negative.
      // We clamp to 0.
      r.layout(const CellConstraints(maxCols: 4));
      expect(child.size.cols, 0);
    });
  });

  group('RenderText + RenderPadding composition', () {
    test('padding wraps text without corrupting it', () {
      final r = RenderPadding(
        padding: const EdgeInsets.all(1),
        child: RenderText(text: 'hi'),
      );
      r.layout(const CellConstraints());
      final buf = CellBuffer(const CellSize(4, 3));
      r.paint(buf, CellOffset.zero);

      // Row 0: all empty.
      for (var col = 0; col < 4; col++) {
        expect(buf.atColRow(col, 0).role, CellRole.empty);
      }
      // Row 1: empty, 'h', 'i', empty.
      expect(buf.atColRow(0, 1).role, CellRole.empty);
      expect(buf.atColRow(1, 1).grapheme, 'h');
      expect(buf.atColRow(2, 1).grapheme, 'i');
      expect(buf.atColRow(3, 1).role, CellRole.empty);
      // Row 2: all empty.
      for (var col = 0; col < 4; col++) {
        expect(buf.atColRow(col, 2).role, CellRole.empty);
      }
    });
  });

  group('EdgeInsets', () {
    test('all() constructs symmetric insets', () {
      const e = EdgeInsets.all(3);
      expect(e.left, 3);
      expect(e.right, 3);
      expect(e.top, 3);
      expect(e.bottom, 3);
      expect(e.horizontal, 6);
      expect(e.vertical, 6);
    });

    test('symmetric() sets only the axes it names', () {
      const e = EdgeInsets.symmetric(horizontal: 2);
      expect(e.left, 2);
      expect(e.right, 2);
      expect(e.top, 0);
      expect(e.bottom, 0);
    });

    test('only() defaults to zero on omitted sides', () {
      const e = EdgeInsets.only(left: 1);
      expect(e.left, 1);
      expect(e.right, 0);
    });

    test('equality and hashCode', () {
      expect(const EdgeInsets.all(2), equals(const EdgeInsets.all(2)));
      expect(
        const EdgeInsets.all(2).hashCode,
        const EdgeInsets.all(2).hashCode,
      );
      expect(const EdgeInsets.all(2), isNot(equals(const EdgeInsets.all(3))));
    });
  });
}
