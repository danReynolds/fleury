// Render-level guards for the scratch-blit effect render objects.
//
// RenderClip (expand/collapse) paints its child into a scratch buffer and
// copies the clipped rectangle into the frame. A wide glyph landing on the
// last clipped column must be DROPPED, never split: re-deriving its width and
// writing the continuation would land one column past the reported size and
// evict whatever sibling content sits there.

import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/cell.dart';
import 'package:fleury/src/rendering/cell_buffer.dart';
import 'package:fleury/src/rendering/layout.dart';
import 'package:fleury/src/rendering/render_effect.dart';
import 'package:fleury/src/rendering/render_object.dart';
import 'package:test/test.dart';

/// A leaf render object that lays out to a fixed cell box and paints [text]
/// at its offset. Keeps the test independent of Text/RichText wiring.
class _TextLeaf extends RenderObject {
  _TextLeaf(this.text, this.intrinsic);
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
  group('RenderClip', () {
    test('drops a wide glyph straddling the clip edge instead of spilling its '
        'continuation past the reported box', () {
      // '你你你' is 6 columns; a 0.5 width factor clips to 3 columns (0..2).
      // The third '你' begins at clipped column 2 and cannot fit — its
      // continuation would land at column 3, one past the box.
      final clip = RenderClip(
        widthFactor: 0.5,
        child: _TextLeaf('你你你', const CellSize(6, 1)),
      );
      clip.layout(const CellConstraints(maxCols: 20, maxRows: 1));
      expect(clip.size, const CellSize(3, 1));

      final buffer = CellBuffer(const CellSize(20, 1));
      // A sibling sits one column past the clip box.
      buffer.writeGrapheme(const CellOffset(3, 0), 'X');

      clip.paint(
        buffer,
        CellOffset.zero,
        screenOffset: CellOffset.zero,
        clipRect: const CellRect(
          offset: CellOffset.zero,
          size: CellSize(20, 1),
        ),
      );

      // The first '你' fits within the clip (cols 0..1).
      expect(buffer.atColRow(0, 0).grapheme, '你');
      expect(buffer.atColRow(1, 0).role, CellRole.continuation);
      // Column 2 held the straddling glyph; it must be dropped, not painted.
      expect(
        buffer.atColRow(2, 0).grapheme,
        isNot('你'),
        reason: 'the straddling wide glyph must not paint its leading either',
      );
      // The sibling one column past the clip must survive intact.
      expect(
        buffer.atColRow(3, 0).grapheme,
        'X',
        reason: 'a wide glyph must not spill its continuation past the clip',
      );
    });

    test('keeps a wide glyph that fits exactly at the clip edge', () {
      // '你你' is 4 columns; a 0.5 width factor clips to 2 columns — exactly
      // the first glyph. It fits (cols 0..1), so it must still paint.
      final clip = RenderClip(
        widthFactor: 0.5,
        child: _TextLeaf('你你', const CellSize(4, 1)),
      );
      clip.layout(const CellConstraints(maxCols: 20, maxRows: 1));
      expect(clip.size, const CellSize(2, 1));

      final buffer = CellBuffer(const CellSize(20, 1));
      buffer.writeGrapheme(const CellOffset(2, 0), 'X');
      clip.paint(
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
      expect(buffer.atColRow(2, 0).grapheme, 'X', reason: 'sibling intact');
    });
  });
}
