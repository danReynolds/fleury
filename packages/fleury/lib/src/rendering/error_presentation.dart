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

import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import 'border.dart';
import 'cell.dart';
import 'cell_buffer.dart';
import 'width_resolver.dart';

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

  // Wrapped `⚠ <error>` text in the interior. All widths are measured in
  // CELLS (not UTF-16 code units), so wide graphemes (CJK, emoji) wrap at
  // the panel edge instead of overrunning the border, and splits land on
  // grapheme-cluster boundaries (never inside a surrogate pair).
  const resolver = DefaultWidthResolver();
  const profile = TerminalProfile.standard;
  final innerLeft = left + 1;
  final innerWidth = size.cols - 2;
  final innerTop = top + 1;
  final innerRows = size.rows - 2;
  if (innerWidth <= 0 || innerRows <= 0) return;

  final words = '⚠ $error'
      .replaceAll('\n', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  // Greedy word-wrap into at most innerRows lines. A word wider than the
  // interior is hard-split along grapheme boundaries.
  final lines = <String>[];
  var line = StringBuffer();
  var lineWidth = 0;
  while (words.isNotEmpty && lines.length < innerRows) {
    final word = words.first;
    final wordWidth = resolver.widthOfText(word, profile);
    final sep = lineWidth == 0 ? 0 : 1;
    if (lineWidth + sep + wordWidth <= innerWidth) {
      if (sep == 1) line.write(' ');
      line.write(word);
      lineWidth += sep + wordWidth;
      words.removeAt(0);
    } else if (lineWidth == 0) {
      // Word wider than the whole interior: take as many leading
      // graphemes as fit, defer the rest.
      final head = StringBuffer();
      final rest = StringBuffer();
      var headWidth = 0;
      var filling = true;
      for (final g in word.characters) {
        final gw = resolver.widthOfGrapheme(g, profile);
        if (filling && headWidth + gw <= innerWidth) {
          head.write(g);
          headWidth += gw;
        } else {
          filling = false;
          rest.write(g);
        }
      }
      words.removeAt(0);
      if (rest.isNotEmpty) words.insert(0, rest.toString());
      lines.add(head.toString());
    } else {
      lines.add(line.toString());
      line = StringBuffer();
      lineWidth = 0;
    }
  }
  if (line.isNotEmpty && lines.length < innerRows) lines.add(line.toString());

  final overflowed = words.isNotEmpty;
  for (var i = 0; i < lines.length; i++) {
    final row = innerTop + i;
    if (row < visible.top || row >= visible.bottom) continue;
    var text = lines[i];
    if (i == lines.length - 1 && overflowed) {
      text = _ellipsize(text, innerWidth, resolver, profile);
    }
    _paintClippedRun(buffer, row, innerLeft, text, visible, resolver, profile);
  }
}

/// Trims [text] along grapheme boundaries until it plus a trailing `…`
/// fits [maxCols] cells.
String _ellipsize(
  String text,
  int maxCols,
  WidthResolver resolver,
  TerminalProfile profile,
) {
  if (resolver.widthOfText(text, profile) < maxCols) return '$text…';
  final kept = StringBuffer();
  var width = 0;
  for (final g in text.characters) {
    final gw = resolver.widthOfGrapheme(g, profile);
    if (width + gw > maxCols - 1) break; // leave a cell for the ellipsis
    kept.write(g);
    width += gw;
  }
  return '$kept…';
}

/// Writes [text] starting at column [startCol], clipped (width-aware) to the
/// [visible] column window — buffer bounds are handled by writeText; a
/// tighter ancestor clipRect is handled here so wide graphemes are dropped,
/// never split.
void _paintClippedRun(
  CellBuffer buffer,
  int row,
  int startCol,
  String text,
  CellRect visible,
  WidthResolver resolver,
  TerminalProfile profile,
) {
  var col = startCol;
  final out = StringBuffer();
  var outCol = startCol;
  var started = false;
  for (final g in text.characters) {
    final gw = resolver.widthOfGrapheme(g, profile);
    if (col >= visible.left && col + gw <= visible.right) {
      if (!started) {
        outCol = col;
        started = true;
      }
      out.write(g);
    } else if (started) {
      break; // left the visible window
    }
    col += gw;
  }
  if (started && out.isNotEmpty) {
    buffer.writeText(
      CellOffset(outCol, row),
      out.toString(),
      style: _errorStyle,
    );
  }
}
