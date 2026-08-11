import '../runtime/tui_frame_loop.dart' show TuiDirtyRows;
import 'cell.dart';
import 'cell_buffer.dart';

/// Builds row span models from a [CellBuffer].
///
/// This is the shared role-walking core for Fleury's DOM renderer. The static
/// HTML artifact path and the future live DOM surface should both consume this
/// model instead of independently interpreting [CellRole].
final class CellSpanBuilder {
  const CellSpanBuilder();

  /// Builds every row in [buffer].
  List<RowSpanModel> buildFrame(CellBuffer buffer) {
    return [
      for (var row = 0; row < buffer.size.rows; row++) buildRow(buffer, row),
    ];
  }

  /// Builds rows selected by [dirtyRows].
  List<RowSpanModel> buildDirtyRows(CellBuffer buffer, TuiDirtyRows dirtyRows) {
    return [
      for (final row in dirtyRows.rows)
        if (row >= 0 && row < buffer.size.rows) buildRow(buffer, row),
    ];
  }

  /// Builds one row in [buffer].
  RowSpanModel buildRow(CellBuffer buffer, int row) {
    RangeError.checkValueInInterval(row, 0, buffer.size.rows - 1, 'row');
    final cols = buffer.size.cols;
    final runs = <CellSpanRun>[];
    _PendingTextRun? pending;

    void flushPending() {
      final run = pending;
      if (run == null) return;
      runs.add(run.toSpanRun());
      pending = null;
    }

    void appendText({
      required int col,
      required String text,
      required int widthCols,
      required CellStyle style,
      required CellRunKind kind,
    }) {
      final current = pending;
      if (current != null &&
          current.kind != CellRunKind.boxDrawing &&
          current.style == style &&
          current.endCol == col) {
        current
          ..text.write(text)
          ..widthCols += widthCols
          ..kind = current.kind == CellRunKind.emptyText ? kind : current.kind;
        return;
      }
      flushPending();
      pending = _PendingTextRun(
        startCol: col,
        widthCols: widthCols,
        style: style,
        kind: kind,
      )..text.write(text);
    }

    // Box-drawing cells coalesce only with an adjacent cell carrying the *same*
    // grapheme and style (so a horizontal `────` run is one span, but `╭` and
    // `╮` stay distinct). The run's text holds the single grapheme; widthCols
    // counts the cells.
    void appendBox({
      required int col,
      required String grapheme,
      required CellStyle style,
    }) {
      final current = pending;
      if (current != null &&
          current.kind == CellRunKind.boxDrawing &&
          current.style == style &&
          current.endCol == col &&
          current.text.toString() == grapheme) {
        current.widthCols += 1;
        return;
      }
      flushPending();
      pending = _PendingTextRun(
        startCol: col,
        widthCols: 1,
        style: style,
        kind: CellRunKind.boxDrawing,
      )..text.write(grapheme);
    }

    // Block-element cells carry a single grapheme like box-drawing runs, but
    // coalesce only when the glyph is *full-width* ink (`█`, the `▁▂▃▄▅▆▇`
    // ramp, `▀`, `▔`). The DOM adapters size the run's rectangles as a
    // percentage of the whole span, which only equals a per-cell rectangle when
    // the ink spans the full cell width — so a partial-width glyph (`▌`, a
    // quadrant) stays one cell per run and keeps its geometry exact.
    void appendBlock({
      required int col,
      required String grapheme,
      required CellStyle style,
      required bool coalesces,
    }) {
      final current = pending;
      if (coalesces &&
          current != null &&
          current.kind == CellRunKind.blockElement &&
          current.style == style &&
          current.endCol == col &&
          current.text.toString() == grapheme) {
        current.widthCols += 1;
        return;
      }
      flushPending();
      pending = _PendingTextRun(
        startCol: col,
        widthCols: 1,
        style: style,
        kind: CellRunKind.blockElement,
      )..text.write(grapheme);
      // A non-coalescing glyph must not absorb the next cell either.
      if (!coalesces) flushPending();
    }

    var col = 0;
    while (col < cols) {
      final cell = buffer.atColRow(col, row);
      switch (cell.role) {
        case CellRole.empty:
          appendText(
            col: col,
            text: ' ',
            widthCols: 1,
            style: CellStyle.empty,
            kind: CellRunKind.emptyText,
          );
          col += 1;

        case CellRole.continuation:
          col += 1;

        case CellRole.leading:
          final wide =
              col + 1 < cols &&
              buffer.atColRow(col + 1, row).role == CellRole.continuation;
          if (wide) {
            flushPending();
            runs.add(
              CellSpanRun(
                startCol: col,
                widthCols: 2,
                text: cell.grapheme!,
                style: cell.style,
                kind: CellRunKind.wideText,
                correction: WidthCorrection.pinToCellWidth,
              ),
            );
            col += 2;
          } else {
            final grapheme = cell.grapheme!;
            // Cheap range gate before the two string switches: box-drawing
            // (U+2500–257F) and block elements (U+2580–259F) are the only
            // graphemes with a CSS-painted form, so ordinary text pays one
            // integer compare per cell instead of a switch it can never match.
            final cp = grapheme.length == 1 ? grapheme.codeUnitAt(0) : 0;
            final cssPainted = cp >= 0x2500 && cp <= 0x259F;
            final rects = cssPainted ? blockElementRects(grapheme) : null;
            if (cssPainted && boxDrawingMask(grapheme) != null) {
              appendBox(col: col, grapheme: grapheme, style: cell.style);
            } else if (rects != null) {
              appendBlock(
                col: col,
                grapheme: grapheme,
                style: cell.style,
                coalesces: blockRectsSpanFullWidth(rects),
              );
            } else {
              appendText(
                col: col,
                text: grapheme,
                widthCols: 1,
                style: cell.style,
                kind: CellRunKind.text,
              );
            }
            col += 1;
          }

        case CellRole.overlay:
          // Inline-image region: the DOM surface renders the pixels as an
          // absolutely-positioned <img>; the grid underneath stays blank.
          appendText(
            col: col,
            text: ' ',
            widthCols: 1,
            style: CellStyle.empty,
            kind: CellRunKind.emptyText,
          );
          col += 1;
      }
    }
    flushPending();
    return RowSpanModel(row: row, cols: cols, runs: List.unmodifiable(runs));
  }
}

/// Pure span model for one visible row.
final class RowSpanModel {
  const RowSpanModel({
    required this.row,
    required this.cols,
    required this.runs,
  });

  /// Row index in the frame buffer.
  final int row;

  /// Number of columns in the row.
  final int cols;

  /// Visual runs in ascending column order.
  final List<CellSpanRun> runs;
}

/// One contiguous visual run in a row.
final class CellSpanRun {
  const CellSpanRun({
    required this.startCol,
    required this.widthCols,
    required this.text,
    required this.style,
    required this.kind,
    required this.correction,
  }) : assert(startCol >= 0, 'startCol must be non-negative'),
       assert(widthCols >= 0, 'widthCols must be non-negative');

  /// First grid column occupied by this run.
  final int startCol;

  /// Logical grid width occupied by this run.
  final int widthCols;

  /// Text content to render.
  final String text;

  /// Resolved Fleury cell style for this run.
  final CellStyle style;

  /// Semantic kind of this run.
  final CellRunKind kind;

  /// Width handling needed by DOM nodes for this run.
  final WidthCorrection correction;
}

/// Span run categories understood by the DOM adapters.
///
/// [boxDrawing] and [blockElement] runs carry a single grapheme (repeated
/// across [CellSpanRun.widthCols] cells); the DOM renderer paints them as CSS
/// rectangles rather than font glyphs. A browser lays text out in a line box
/// that is taller than the glyph's ink and advances it by the font's natural
/// width plus letter-spacing, so neither class tiles: borders dash, and solid
/// fills (bars, sparklines, image cells) show a seam at every cell edge. A CSS
/// rectangle is sized from the cell box itself, so it is exact in both axes.
/// See [boxDrawingMask] and [blockElementRects].
enum CellRunKind { text, wideText, emptyText, boxDrawing, blockElement }

/// Directional segment bits for a box-drawing grapheme.
const int boxSegmentNorth = 1;
const int boxSegmentSouth = 2;
const int boxSegmentEast = 4;
const int boxSegmentWest = 8;

/// The line segments [grapheme] draws, as an OR of [boxSegmentNorth] etc., or
/// null if it is not a box-drawing line/corner/junction. Double-line glyphs are
/// mapped to their single-weight segment set (good enough for crisp borders).
int? boxDrawingMask(String grapheme) {
  switch (grapheme) {
    case '│':
    case '║':
      return boxSegmentNorth | boxSegmentSouth;
    case '─':
    case '═':
      return boxSegmentEast | boxSegmentWest;
    case '╭':
    case '┌':
    case '╔':
      return boxSegmentSouth | boxSegmentEast;
    case '╮':
    case '┐':
    case '╗':
      return boxSegmentSouth | boxSegmentWest;
    case '╰':
    case '└':
    case '╚':
      return boxSegmentNorth | boxSegmentEast;
    case '╯':
    case '┘':
    case '╝':
      return boxSegmentNorth | boxSegmentWest;
    case '├':
    case '╠':
      return boxSegmentNorth | boxSegmentSouth | boxSegmentEast;
    case '┤':
    case '╣':
      return boxSegmentNorth | boxSegmentSouth | boxSegmentWest;
    case '┬':
    case '╦':
      return boxSegmentSouth | boxSegmentEast | boxSegmentWest;
    case '┴':
    case '╩':
      return boxSegmentNorth | boxSegmentEast | boxSegmentWest;
    case '┼':
    case '╬':
      return boxSegmentNorth |
          boxSegmentSouth |
          boxSegmentEast |
          boxSegmentWest;
    default:
      return null;
  }
}

/// One axis-aligned rectangle of ink inside a single cell, in eighths of the
/// cell box, with the origin at the cell's top-left.
///
/// Every rectangle in [blockElementRects] is anchored to a cell edge on both
/// axes ([left] is 0 or [left] + [width] is 8, and likewise vertically), which
/// is what lets a DOM adapter place it with CSS background keywords alone.
final class BlockRect {
  const BlockRect(this.left, this.top, this.width, this.height)
    : assert(left >= 0 && width > 0 && left + width <= 8, 'x out of cell'),
      assert(top >= 0 && height > 0 && top + height <= 8, 'y out of cell'),
      assert(left == 0 || left + width == 8, 'must be anchored horizontally'),
      assert(top == 0 || top + height == 8, 'must be anchored vertically');

  /// Distance from the cell's left edge, in eighths.
  final int left;

  /// Distance from the cell's top edge, in eighths.
  final int top;

  /// Rectangle width in eighths of the cell (1..8).
  final int width;

  /// Rectangle height in eighths of the cell (1..8).
  final int height;
}

/// The solid rectangles [grapheme] fills, or null if it is not a block element
/// that decomposes into whole rectangles.
///
/// Covers the halves, the eighth ramps and the quadrant set (U+2580–U+2590,
/// U+2594–U+259F). Deliberately excluded:
///
/// * the shades `░▒▓` (U+2591–2593) — a stipple texture, not a solid fill;
///   flattening them to a tint would change how they read.
/// * sextants, octants and braille — sub-cell *patterns* whose cell-filling is
///   already handled by giving a background-carrying run the full cell box.
///
/// Results are `const`, so a lookup allocates nothing on the per-frame path.
List<BlockRect>? blockElementRects(String grapheme) {
  switch (grapheme) {
    // Vertical eighth ramp, growing up from the bottom edge (`▁`..`▇`), and the
    // two halves — the glyphs bar charts, sparklines and area fills paint with.
    case '▁':
      return const [BlockRect(0, 7, 8, 1)];
    case '▂':
      return const [BlockRect(0, 6, 8, 2)];
    case '▃':
      return const [BlockRect(0, 5, 8, 3)];
    case '▄':
      return const [BlockRect(0, 4, 8, 4)];
    case '▅':
      return const [BlockRect(0, 3, 8, 5)];
    case '▆':
      return const [BlockRect(0, 2, 8, 6)];
    case '▇':
      return const [BlockRect(0, 1, 8, 7)];
    case '█':
      return const [BlockRect(0, 0, 8, 8)];
    case '▀':
      return const [BlockRect(0, 0, 8, 4)];
    case '▔':
      return const [BlockRect(0, 0, 8, 1)];
    // Horizontal eighth ramp, growing right from the left edge (`▏`..`▉`) —
    // gauges and progress bars.
    case '▏':
      return const [BlockRect(0, 0, 1, 8)];
    case '▎':
      return const [BlockRect(0, 0, 2, 8)];
    case '▍':
      return const [BlockRect(0, 0, 3, 8)];
    case '▌':
      return const [BlockRect(0, 0, 4, 8)];
    case '▋':
      return const [BlockRect(0, 0, 5, 8)];
    case '▊':
      return const [BlockRect(0, 0, 6, 8)];
    case '▉':
      return const [BlockRect(0, 0, 7, 8)];
    case '▐':
      return const [BlockRect(4, 0, 4, 8)];
    case '▕':
      return const [BlockRect(7, 0, 1, 8)];
    // Quadrants. The three-quadrant glyphs are expressed as two overlapping
    // halves rather than three squares — same ink, one fewer layer, and no
    // interior seam between the two squares that share an edge.
    case '▖':
      return const [BlockRect(0, 4, 4, 4)];
    case '▗':
      return const [BlockRect(4, 4, 4, 4)];
    case '▘':
      return const [BlockRect(0, 0, 4, 4)];
    case '▝':
      return const [BlockRect(4, 0, 4, 4)];
    case '▚':
      return const [BlockRect(0, 0, 4, 4), BlockRect(4, 4, 4, 4)];
    case '▞':
      return const [BlockRect(4, 0, 4, 4), BlockRect(0, 4, 4, 4)];
    case '▙':
      return const [BlockRect(0, 0, 4, 8), BlockRect(0, 4, 8, 4)];
    case '▛':
      return const [BlockRect(0, 0, 8, 4), BlockRect(0, 0, 4, 8)];
    case '▜':
      return const [BlockRect(0, 0, 8, 4), BlockRect(4, 0, 4, 8)];
    case '▟':
      return const [BlockRect(4, 0, 4, 8), BlockRect(0, 4, 8, 4)];
    default:
      return null;
  }
}

/// Whether every rectangle in [rects] spans the cell's full width.
///
/// Such a glyph is identical to itself stretched across N cells, so a run of
/// them can coalesce into one span whose rectangles are sized as a percentage
/// of the whole run. Anything narrower must stay one cell per run.
bool blockRectsSpanFullWidth(List<BlockRect> rects) {
  for (final rect in rects) {
    if (rect.left != 0 || rect.width != 8) return false;
  }
  return true;
}

/// DOM width correction needed for a span.
enum WidthCorrection { none, pinToCellWidth }

final class _PendingTextRun {
  _PendingTextRun({
    required this.startCol,
    required this.widthCols,
    required this.style,
    required this.kind,
  });

  final int startCol;
  int widthCols;
  final CellStyle style;
  CellRunKind kind;
  final StringBuffer text = StringBuffer();

  int get endCol => startCol + widthCols;

  CellSpanRun toSpanRun() {
    return CellSpanRun(
      startCol: startCol,
      widthCols: widthCols,
      text: text.toString(),
      style: style,
      kind: kind,
      correction: WidthCorrection.none,
    );
  }
}
