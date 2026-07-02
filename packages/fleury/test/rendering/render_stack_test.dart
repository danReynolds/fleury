import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A render object used in tests to occupy a fixed cell rectangle with a
/// single character marker. Doesn't depend on Text.
class _Marker extends RenderObject {
  _Marker(this.intrinsic, this.marker);
  final CellSize intrinsic;
  final String marker;

  @override
  CellSize performLayout(CellConstraints constraints) {
    return constraints.constrain(intrinsic);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    for (var r = 0; r < size.rows; r++) {
      for (var c = 0; c < size.cols; c++) {
        if (offset.col + c >= buffer.size.cols) break;
        if (offset.row + r >= buffer.size.rows) break;
        buffer.writeGrapheme(
          CellOffset(offset.col + c, offset.row + r),
          marker,
        );
      }
    }
  }
}

String _flatten(CellBuffer buffer) {
  final out = StringBuffer();
  for (var row = 0; row < buffer.size.rows; row++) {
    for (var col = 0; col < buffer.size.cols; col++) {
      final c = buffer.atColRow(col, row);
      switch (c.role) {
        case CellRole.empty:
          out.write('·');
        case CellRole.leading:
          out.write(c.grapheme);
        case CellRole.continuation:
        case CellRole.overlay:
          break;
      }
    }
    if (row < buffer.size.rows - 1) out.write('\n');
  }
  return out.toString();
}

void main() {
  group('RenderStack — sizing', () {
    test('zero children: zero size', () {
      final stack = RenderStack();
      final size = stack.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(size, CellSize.zero);
    });

    test('non-positioned children: stack sizes to the largest', () {
      final stack = RenderStack();
      stack.replaceAllChildren([
        _Marker(const CellSize(3, 1), 'a'),
        _Marker(const CellSize(5, 2), 'b'),
        _Marker(const CellSize(2, 3), 'c'),
      ]);
      final size = stack.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(size, const CellSize(5, 3));
    });

    test('positioned children do not influence stack size', () {
      final stack = RenderStack();
      final base = _Marker(const CellSize(2, 1), 'a');
      final modal = RenderPositioned(left: 5, top: 3, width: 4, height: 2)
        ..child = _Marker(const CellSize(4, 2), 'm');
      stack.replaceAllChildren([base, modal]);
      final size = stack.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      // Stack's size comes from `base` only.
      expect(size, const CellSize(2, 1));
    });
  });

  group('RenderStack — paint order', () {
    test('later siblings overwrite earlier ones at the same cell', () {
      final stack = RenderStack();
      stack.replaceAllChildren([
        _Marker(const CellSize(3, 1), 'a'),
        _Marker(const CellSize(3, 1), 'b'),
      ]);
      stack.layout(const CellConstraints(maxCols: 5, maxRows: 1));
      final buf = CellBuffer(const CellSize(5, 1));
      stack.paint(buf, CellOffset.zero);
      // 'b' painted second wins over 'a'.
      expect(_flatten(buf), 'bbb··');
    });

    test('positioned overlay lands at its offset on top of the base', () {
      final stack = RenderStack();
      final base = _Marker(const CellSize(5, 1), '.');
      final overlay = RenderPositioned(left: 2, top: 0, width: 2, height: 1)
        ..child = _Marker(const CellSize(2, 1), 'X');
      stack.replaceAllChildren([base, overlay]);
      stack.layout(const CellConstraints(maxCols: 5, maxRows: 1));
      final buf = CellBuffer(const CellSize(5, 1));
      stack.paint(buf, CellOffset.zero);
      expect(_flatten(buf), '..XX.');
    });

    test('positioned overlay outside stack bounds shrinks to zero', () {
      final stack = RenderStack();
      final base = _Marker(const CellSize(3, 1), '.');
      // Position past the right edge — there's no room.
      final overlay = RenderPositioned(left: 10, top: 0, width: 5, height: 1)
        ..child = _Marker(const CellSize(5, 1), 'X');
      stack.replaceAllChildren([base, overlay]);
      stack.layout(const CellConstraints(maxCols: 3, maxRows: 1));
      final buf = CellBuffer(const CellSize(3, 1));
      stack.paint(buf, CellOffset.zero);
      // Base paints; overlay is layout-clamped to zero and writes
      // nothing meaningful, AND lands outside the buffer anyway.
      expect(_flatten(buf), '...');
    });
  });

  group('RenderStack — RFC P0 gate: wide-grapheme eviction across overlap', () {
    test(
      'overlay landing on a wide leading evicts the wide cell as expected',
      () {
        // Base writes a wide grapheme at column 0; overlay writes a
        // narrow grapheme at column 1 (the continuation). Per CellBuffer
        // eviction rules, the leading at column 0 must become empty.
        final stack = RenderStack();
        final base = _WideMarker(); // writes '中' at (0,0) — width 2.
        final overlay = RenderPositioned(left: 1, top: 0, width: 1, height: 1)
          ..child = _Marker(const CellSize(1, 1), '!');
        stack.replaceAllChildren([base, overlay]);
        stack.layout(const CellConstraints(maxCols: 4, maxRows: 1));

        final buf = CellBuffer(const CellSize(4, 1));
        stack.paint(buf, CellOffset.zero);

        // Expected: leading '中' at col 0 was evicted when col 1 (its
        // continuation) was overwritten by '!'. So col 0 is empty.
        expect(buf.atColRow(0, 0).role, CellRole.empty);
        expect(buf.atColRow(1, 0).grapheme, '!');
        expect(buf.atColRow(2, 0).role, CellRole.empty);
        expect(buf.atColRow(3, 0).role, CellRole.empty);
      },
    );

    test(
      'overlay landing on a wide continuation evicts the leading to its left',
      () {
        final stack = RenderStack();
        final base = _WideMarker();
        // Overlay writes '!' at col 0 — the leading. Continuation at
        // col 1 should be evicted.
        final overlay = RenderPositioned(left: 0, top: 0, width: 1, height: 1)
          ..child = _Marker(const CellSize(1, 1), '!');
        stack.replaceAllChildren([base, overlay]);
        stack.layout(const CellConstraints(maxCols: 4, maxRows: 1));

        final buf = CellBuffer(const CellSize(4, 1));
        stack.paint(buf, CellOffset.zero);

        expect(buf.atColRow(0, 0).grapheme, '!');
        expect(
          buf.atColRow(1, 0).role,
          CellRole.empty,
          reason:
              'Orphaned continuation must be cleared when its '
              'leading is overwritten by an overlay.',
        );
      },
    );
  });

  group('RenderStack — child replacement', () {
    test('replaceAllChildren adopts new children and drops old ones', () {
      final stack = RenderStack();
      final a = _Marker(const CellSize(1, 1), 'a');
      final b = _Marker(const CellSize(1, 1), 'b');
      final c = _Marker(const CellSize(1, 1), 'c');

      stack.replaceAllChildren([a, b]);
      expect(a.parent, same(stack));
      expect(b.parent, same(stack));

      stack.replaceAllChildren([b, c]);
      expect(a.parent, isNull);
      expect(b.parent, same(stack));
      expect(c.parent, same(stack));
    });
  });

  group('RenderIndexedStack', () {
    test('sizes to the largest child even though only one paints', () {
      final stack = RenderIndexedStack(index: 0);
      stack.replaceAllChildren([
        _Marker(const CellSize(2, 1), 'a'),
        _Marker(const CellSize(5, 3), 'b'),
      ]);
      final size = stack.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(size, const CellSize(5, 3));
    });

    test('paints only the child at index', () {
      final stack = RenderIndexedStack(index: 1);
      stack.replaceAllChildren([
        _Marker(const CellSize(3, 1), 'a'),
        _Marker(const CellSize(3, 1), 'b'),
      ]);
      stack.layout(const CellConstraints(maxCols: 5, maxRows: 1));
      final buf = CellBuffer(const CellSize(5, 1));
      stack.paint(buf, CellOffset.zero);
      expect(_flatten(buf), 'bbb··');
    });

    test('out-of-range index paints nothing', () {
      final stack = RenderIndexedStack(index: 9);
      stack.replaceAllChildren([_Marker(const CellSize(3, 1), 'a')]);
      stack.layout(const CellConstraints(maxCols: 5, maxRows: 1));
      final buf = CellBuffer(const CellSize(5, 1));
      stack.paint(buf, CellOffset.zero);
      expect(_flatten(buf), '·····');
    });

    test('changing index switches which child paints, all stay laid out', () {
      final stack = RenderIndexedStack(index: 0);
      final a = _Marker(const CellSize(3, 1), 'a');
      final b = _Marker(const CellSize(3, 1), 'b');
      stack.replaceAllChildren([a, b]);
      stack.layout(const CellConstraints(maxCols: 5, maxRows: 1));
      // Both children were laid out (size assigned), not just the painted one.
      expect(a.size, const CellSize(3, 1));
      expect(b.size, const CellSize(3, 1));

      stack.index = 1;
      stack.layout(const CellConstraints(maxCols: 5, maxRows: 1));
      final buf = CellBuffer(const CellSize(5, 1));
      stack.paint(buf, CellOffset.zero);
      expect(_flatten(buf), 'bbb··');
    });
  });
}

/// A marker that writes a single wide grapheme '中' at its origin and
/// reports width 2 in layout. Used to exercise wide-grapheme
/// eviction across overlapping Stack children.
class _WideMarker extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) {
    return constraints.constrain(const CellSize(2, 1));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.isEmpty) return;
    buffer.writeGrapheme(offset, '中');
  }
}
