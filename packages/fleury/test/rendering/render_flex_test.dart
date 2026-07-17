import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A render object used to test layout decisions without depending on the
/// Text widget. Reports a fixed `intrinsic` size when given unbounded
/// constraints, otherwise constrains to the bounds.
class _FixedSize extends RenderObject {
  _FixedSize(this.intrinsic);
  final CellSize intrinsic;

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
    // Tests inspect `size` / offsets, not painted output.
  }
}

class _PaintCountingBox extends RenderObject {
  _PaintCountingBox(this.intrinsic, this.marker);

  final CellSize intrinsic;
  final String marker;
  int paintCount = 0;
  CellOffset? lastOffset;
  CellOffset? lastScreenOffset;

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
    paintCount += 1;
    lastOffset = offset;
    lastScreenOffset = screenOffset;
    buffer.writeGrapheme(offset, marker);
  }
}

/// A leaf that lays out to a fixed box and paints [text] (possibly wide
/// graphemes) at its offset — for exercising the overflow-clip blit.
class _CjkLeaf extends RenderObject {
  _CjkLeaf(this.text, this.intrinsic);
  final String text;
  final CellSize intrinsic;

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(intrinsic);

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    buffer.writeText(offset, text);
  }
}

void main() {
  group('RenderFlex — overflow clip', () {
    test('drops a wide glyph straddling the clip edge instead of spilling its '
        'continuation past the box into a sibling', () {
      final previous = RenderFlex.debugShowOverflow;
      RenderFlex.debugShowOverflow = false;
      addTearDown(() => RenderFlex.debugShowOverflow = previous);

      // '你你你' is 6 columns; the box clips to 3, so the third glyph begins at
      // clipped column 2 and cannot fit — its continuation would land at
      // column 3, one past the flex box, evicting the sibling there.
      final flex = RenderFlex(direction: Axis.horizontal);
      flex.replaceAllChildren([_CjkLeaf('你你你', const CellSize(6, 1))]);
      flex.layout(const CellConstraints(maxCols: 3, maxRows: 1));
      expect(flex.size, const CellSize(3, 1));

      final buffer = CellBuffer(const CellSize(20, 1));
      buffer.writeGrapheme(const CellOffset(3, 0), 'X'); // sibling past the box

      flex.paint(
        buffer,
        CellOffset.zero,
        screenOffset: CellOffset.zero,
        clipRect: const CellRect(
          offset: CellOffset.zero,
          size: CellSize(20, 1),
        ),
      );

      expect(buffer.atColRow(0, 0).grapheme, '你');
      expect(buffer.atColRow(1, 0).role, CellRole.continuation);
      expect(
        buffer.atColRow(3, 0).grapheme,
        'X',
        reason: 'a clipped wide glyph must not spill past the flex box',
      );
    });
  });

  group('RenderFlex — empty', () {
    test('zero children: zero size', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      final size = flex.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(size, CellSize.zero);
    });
  });

  group('RenderFlex — inflexible children only', () {
    test('horizontal: main axis = sum of widths, cross = max of heights', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      flex.replaceAllChildren([
        _FixedSize(const CellSize(3, 1)),
        _FixedSize(const CellSize(4, 2)),
      ]);
      final size = flex.layout(const CellConstraints(maxCols: 20, maxRows: 5));
      // mainAxisSize.max + horizontal + maxCols 20 → main = 20.
      expect(size.cols, 20);
      expect(size.rows, 2);
    });

    test('MainAxisSize.min: shrinks to children\'s used main extent', () {
      final flex = RenderFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
      );
      flex.replaceAllChildren([
        _FixedSize(const CellSize(3, 1)),
        _FixedSize(const CellSize(4, 1)),
      ]);
      final size = flex.layout(const CellConstraints(maxCols: 20, maxRows: 5));
      expect(size.cols, 7);
    });
  });

  group('RenderFlex — flex distribution', () {
    test('two Expanded(1) split equal space', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      final a = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(0, 1));
      final b = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(0, 1));
      flex.replaceAllChildren([a, b]);
      flex.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(a.size.cols, 5);
      expect(b.size.cols, 5);
    });

    test('Expanded(1) + Expanded(4) split 1:4', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      final a = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(0, 1));
      final b = RenderFlexible(flex: 4, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(0, 1));
      flex.replaceAllChildren([a, b]);
      flex.layout(const CellConstraints(maxCols: 120, maxRows: 5));
      // 120 / 5 = 24 / 96
      expect(a.size.cols, 24);
      expect(b.size.cols, 96);
    });

    test('odd remainder is given to leftmost flex children in order', () {
      // 10 cells / 3 flex = floor 3 each, 1 leftover.
      // The leftover goes to the first child.
      final flex = RenderFlex(direction: Axis.horizontal);
      final children = [
        RenderFlexible(flex: 1, fit: FlexFit.tight)
          ..child = _FixedSize(const CellSize(0, 1)),
        RenderFlexible(flex: 1, fit: FlexFit.tight)
          ..child = _FixedSize(const CellSize(0, 1)),
        RenderFlexible(flex: 1, fit: FlexFit.tight)
          ..child = _FixedSize(const CellSize(0, 1)),
      ];
      flex.replaceAllChildren(children);
      flex.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(children[0].size.cols, 4);
      expect(children[1].size.cols, 3);
      expect(children[2].size.cols, 3);
    });

    test('mixed inflexible + flexible: flexible gets remaining space', () {
      // 20 total. Sidebar = 5 (inflexible). Expanded gets 15.
      final flex = RenderFlex(direction: Axis.horizontal);
      final sidebar = _FixedSize(const CellSize(5, 1));
      final pane = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(0, 1));
      flex.replaceAllChildren([sidebar, pane]);
      flex.layout(const CellConstraints(maxCols: 20, maxRows: 5));
      expect(sidebar.size.cols, 5);
      expect(pane.size.cols, 15);
    });

    test('overconstrained inflexible children leave zero for flex', () {
      // Two inflexible children totalling 25 in a 20-wide flex; flex
      // child gets clamped to zero.
      final flex = RenderFlex(direction: Axis.horizontal);
      final a = _FixedSize(const CellSize(15, 1));
      final b = _FixedSize(const CellSize(10, 1));
      final c = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(0, 1));
      flex.replaceAllChildren([a, b, c]);
      flex.layout(const CellConstraints(maxCols: 20, maxRows: 5));
      expect(c.size.cols, 0);
    });
  });

  group('RenderFlex — cross-axis alignment', () {
    test('stretch: children fill the cross axis', () {
      final flex = RenderFlex(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      );
      final a = _FixedSize(const CellSize(3, 1));
      final b = _FixedSize(const CellSize(2, 1));
      flex.replaceAllChildren([a, b]);
      flex.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      // Both children should be 5 cells tall (the cross-axis max).
      expect(a.size.rows, 5);
      expect(b.size.rows, 5);
    });

    test('start (default): children keep their own cross extent', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      final a = _FixedSize(const CellSize(3, 2));
      final b = _FixedSize(const CellSize(2, 1));
      flex.replaceAllChildren([a, b]);
      flex.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(a.size.rows, 2);
      expect(b.size.rows, 1);
    });
  });

  group('RenderFlex — vertical direction', () {
    test('column splits height between two Expandeds', () {
      final flex = RenderFlex(direction: Axis.vertical);
      final a = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(1, 0));
      final b = RenderFlexible(flex: 1, fit: FlexFit.tight)
        ..child = _FixedSize(const CellSize(1, 0));
      flex.replaceAllChildren([a, b]);
      flex.layout(const CellConstraints(maxCols: 5, maxRows: 10));
      expect(a.size.rows, 5);
      expect(b.size.rows, 5);
    });
  });

  group('RenderFlex — paint culling', () {
    test('skips vertical children outside the paint buffer', () {
      final flex = RenderFlex(
        direction: Axis.vertical,
        mainAxisSize: MainAxisSize.min,
      );
      final children = [
        for (var i = 0; i < 20; i++)
          _PaintCountingBox(const CellSize(1, 1), String.fromCharCode(65 + i)),
      ];
      flex.replaceAllChildren(children);
      flex.layout(const CellConstraints(maxCols: 1));

      final buffer = CellBuffer(const CellSize(1, 3));
      flex.paint(
        buffer,
        const CellOffset(0, -10),
        screenOffset: const CellOffset(5, -10),
      );

      expect(
        [
          for (var i = 0; i < children.length; i++)
            if (children[i].paintCount > 0) i,
        ],
        [10, 11, 12],
      );
      expect(children[10].lastOffset, const CellOffset(0, 0));
      expect(children[10].lastScreenOffset, const CellOffset(5, 0));
      expect(buffer.atColRow(0, 0).grapheme, 'K');
      expect(buffer.atColRow(0, 1).grapheme, 'L');
      expect(buffer.atColRow(0, 2).grapheme, 'M');
    });

    test('skips horizontal children outside the paint buffer', () {
      final flex = RenderFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
      );
      final children = [
        for (var i = 0; i < 8; i++)
          _PaintCountingBox(const CellSize(1, 1), '$i'),
      ];
      flex.replaceAllChildren(children);
      flex.layout(const CellConstraints(maxRows: 1));

      final buffer = CellBuffer(const CellSize(3, 1));
      flex.paint(
        buffer,
        const CellOffset(-2, 0),
        screenOffset: const CellOffset(-2, 7),
      );

      expect(
        [
          for (var i = 0; i < children.length; i++)
            if (children[i].paintCount > 0) i,
        ],
        [2, 3, 4],
      );
      expect(children[2].lastOffset, const CellOffset(0, 0));
      expect(children[2].lastScreenOffset, const CellOffset(0, 7));
      expect(buffer.atColRow(0, 0).grapheme, '2');
      expect(buffer.atColRow(1, 0).grapheme, '3');
      expect(buffer.atColRow(2, 0).grapheme, '4');
    });
  });

  group('RenderFlex — child replacement', () {
    test('replaceAllChildren adopts new children and drops old ones', () {
      final flex = RenderFlex(direction: Axis.horizontal);
      final a = _FixedSize(const CellSize(1, 1));
      final b = _FixedSize(const CellSize(1, 1));
      final c = _FixedSize(const CellSize(1, 1));

      flex.replaceAllChildren([a, b]);
      expect(a.parent, same(flex));
      expect(b.parent, same(flex));

      flex.replaceAllChildren([b, c]);
      expect(a.parent, isNull, reason: 'a was removed; should be detached.');
      expect(
        b.parent,
        same(flex),
        reason: 'b was kept; should still be attached.',
      );
      expect(c.parent, same(flex));
    });
  });
}
