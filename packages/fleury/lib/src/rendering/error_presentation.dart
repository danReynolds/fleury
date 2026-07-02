// The cell-space error presentation: what an errored boundary (or the
// frame driver's root backstop) paints in place of a subtree whose
// layout or paint threw. A paint helper, not a widget — no build can run
// at the point it's needed.
//
// Contract: EVERY cell in the region is written. The frame buffer is
// cleared at frame start, so writing the full rect both restores paint
// atomicity after a mid-paint throw (partial child writes are simply
// overwritten) and keeps the buffer's write-recorded damage truthful with
// no special-casing — the presenter diffs these cells like any others.
//
// Visual vocabulary matches ErrorWidget (the build-error panel): rounded
// red border, `⚠ <error>` text. Like ErrorWidget, no glyph-tier branch —
// tier policy for error surfaces is a single follow-up if ASCII terminals
// need it.

import '../foundation/geometry.dart';
import 'border.dart';
import 'cell.dart';
import 'cell_buffer.dart';

const _errorStyle = CellStyle(foreground: AnsiColor(1));

/// Paints the error presentation for [error] over the region at [offset]
/// with [size], clipped to [clipRect] (and the buffer bounds).
///
/// Regions at least 3×3 get a rounded red border with wrapped
/// `⚠ <error>` text inside; smaller regions are filled with red `!`.
void paintCellErrorPresentation(
  CellBuffer buffer,
  CellOffset offset,
  CellSize size,
  Object error, {
  CellRect? clipRect,
}) {
  if (size.isEmpty) return;
  final region = CellRect(offset: offset, size: size);
  final bufferRect = CellRect(offset: CellOffset.zero, size: buffer.size);
  var clipped = region.intersect(bufferRect);
  if (clipped != null && clipRect != null) {
    clipped = clipped.intersect(clipRect);
  }
  if (clipped == null || clipped.size.isEmpty) return;
  final visible = clipped;

  bool cellVisible(int col, int row) =>
      col >= visible.left &&
      col < visible.right &&
      row >= visible.top &&
      row < visible.bottom;

  void put(int col, int row, String grapheme, [CellStyle style = _errorStyle]) {
    if (!cellVisible(col, row)) return;
    buffer.writeText(CellOffset(col, row), grapheme, style: style);
  }

  if (size.cols < 3 || size.rows < 3) {
    // Too small for a panel: a red `!` fill keeps the failure visible even
    // as a one-cell badge.
    for (var row = region.top; row < region.bottom; row++) {
      for (var col = region.left; col < region.right; col++) {
        put(col, row, '!');
      }
    }
    return;
  }

  final glyphs = BorderGlyphs.forStyle(BorderStyle.rounded);
  final left = region.left;
  final top = region.top;
  final right = region.right - 1;
  final bottom = region.bottom - 1;

  // Border + interior fill: every cell in the rect is written.
  for (var row = top; row <= bottom; row++) {
    for (var col = left; col <= right; col++) {
      final String grapheme;
      if (row == top && col == left) {
        grapheme = glyphs.topLeft;
      } else if (row == top && col == right) {
        grapheme = glyphs.topRight;
      } else if (row == bottom && col == left) {
        grapheme = glyphs.bottomLeft;
      } else if (row == bottom && col == right) {
        grapheme = glyphs.bottomRight;
      } else if (row == top || row == bottom) {
        grapheme = glyphs.horizontal;
      } else if (col == left || col == right) {
        grapheme = glyphs.vertical;
      } else {
        grapheme = ' ';
      }
      put(col, row, grapheme);
    }
  }

  // Wrapped `⚠ <error>` text in the interior.
  final innerLeft = left + 1;
  final innerWidth = size.cols - 2;
  final innerTop = top + 1;
  final innerRows = size.rows - 2;
  final words = '⚠ $error'
      .replaceAll('\n', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  var row = innerTop;
  var line = StringBuffer();
  void flushLine() {
    if (line.isEmpty) return;
    var text = line.toString();
    if (row == innerTop + innerRows - 1 && words.isNotEmpty) {
      // Last visible row with content left over: ellipsize.
      if (text.length >= innerWidth) {
        text = '${text.substring(0, innerWidth - 1)}…';
      } else {
        text = '$text…';
      }
    }
    if (row >= visible.top && row < visible.bottom) {
      var run = text.length > innerWidth ? text.substring(0, innerWidth) : text;
      var startCol = innerLeft;
      // Clip the run to the visible column range (buffer bounds are
      // handled by writeText; clipRect is not).
      if (startCol < visible.left) {
        final skip = visible.left - startCol;
        run = skip >= run.length ? '' : run.substring(skip);
        startCol = visible.left;
      }
      final maxLen = visible.right - startCol;
      if (maxLen > 0 && run.isNotEmpty) {
        if (run.length > maxLen) run = run.substring(0, maxLen);
        buffer.writeText(CellOffset(startCol, row), run, style: _errorStyle);
      }
    }
    line = StringBuffer();
    row++;
  }

  while (words.isNotEmpty && row < innerTop + innerRows) {
    final word = words.first;
    final candidate = line.isEmpty ? word : '${line.toString()} $word';
    if (candidate.length <= innerWidth) {
      words.removeAt(0);
      line
        ..clear()
        ..write(candidate);
    } else if (line.isEmpty) {
      // A single word wider than the interior: hard-split it.
      words.removeAt(0);
      line.write(word.substring(0, innerWidth));
      final rest = word.substring(innerWidth);
      if (rest.isNotEmpty) words.insert(0, rest);
      flushLine();
    } else {
      flushLine();
    }
  }
  flushLine();
}
