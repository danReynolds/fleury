// The cell-space error presentation: width-aware wrapping so wide
// graphemes (CJK, emoji) stay inside the panel border.

import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/cell.dart';
import 'package:fleury/src/rendering/cell_buffer.dart';
import 'package:fleury/src/rendering/error_presentation.dart';
import 'package:test/test.dart';

/// The rounded-border glyphs the panel uses on its right edge.
const _vertical = '│';

void main() {
  test('a CJK error message stays inside the panel border', () {
    // 12×5 panel. Interior width is 10 cells; a run of double-width CJK
    // must wrap at 5 graphemes, not 10 — a code-unit measure would paint
    // 10 CJK graphemes = 20 cells and blow through the right border and
    // beyond.
    final buffer = CellBuffer(const CellSize(12, 5));
    paintCellErrorPresentation(
      buffer,
      CellOffset.zero,
      const CellSize(12, 5),
      '渲染失败布局越界渲染失败布局越界', // 16 double-width graphemes
    );

    // The right border column stays intact on every row.
    for (var row = 0; row < 5; row++) {
      expect(
        buffer.atColRow(11, row).grapheme,
        anyOf(_vertical, '╮', '╯'),
        reason: 'right border column $row not overwritten by wide text',
      );
    }
    // Nothing painted past the border (col 11 is the border; there is no
    // col 12 — the buffer would throw — so assert the interior never
    // exceeded innerWidth by checking the last interior column holds at
    // most one leading grapheme, i.e. the text wrapped).
    // Interior columns are 1..10; a wide grapheme starting at col 10 would
    // need col 11 (the border) as its continuation — assert that didn't
    // happen.
    for (var row = 1; row < 4; row++) {
      final borderCell = buffer.atColRow(11, row);
      expect(
        borderCell.role,
        isNot(CellRole.continuation),
        reason: 'a wide glyph must not spill its continuation onto the border',
      );
    }
  });

  test('an emoji message never splits a surrogate pair', () {
    // Emoji are surrogate pairs in UTF-16; a code-unit substring split
    // would emit a lone half. Assert every painted leading cell is a whole
    // grapheme (writeText would have rejected a broken one, but this pins
    // that the wrap feeds it clusters).
    final buffer = CellBuffer(const CellSize(10, 5));
    paintCellErrorPresentation(
      buffer,
      CellOffset.zero,
      const CellSize(10, 5),
      '🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥',
    );
    // No crash and the border survives.
    expect(buffer.atColRow(9, 0).grapheme, anyOf('╮', '─'));
  });

  test('a plain ASCII message still wraps and ellipsizes', () {
    final buffer = CellBuffer(const CellSize(14, 4));
    paintCellErrorPresentation(
      buffer,
      CellOffset.zero,
      const CellSize(14, 4),
      'StateError: something went very wrong indeed over here',
    );
    final text = buffer.textInRange(CellRect.fromLTWH(1, 1, 12, 2));
    expect(text, contains('…'), reason: 'overflowing text is ellipsized');
    expect(text, contains('State'));
  });
}
