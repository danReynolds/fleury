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
          } else if (boxDrawingMask(cell.grapheme!) != null) {
            appendBox(col: col, grapheme: cell.grapheme!, style: cell.style);
            col += 1;
          } else {
            appendText(
              col: col,
              text: cell.grapheme!,
              widthCols: 1,
              style: cell.style,
              kind: CellRunKind.text,
            );
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
/// [boxDrawing] runs carry a single box-drawing grapheme (repeated across
/// [CellSpanRun.widthCols] cells); the DOM renderer paints them as crisp CSS
/// lines rather than the font glyph, which in a browser does not tile
/// vertically (the glyph ink is shorter than the cell, so stacked borders
/// dash). See [boxDrawingMask].
enum CellRunKind { text, wideText, emptyText, boxDrawing }

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
