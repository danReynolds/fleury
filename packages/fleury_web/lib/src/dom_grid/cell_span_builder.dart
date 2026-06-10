import 'package:fleury/fleury_host.dart';

const String protocolPlaceholderGlyph = '▩';
const String protocolPlaceholderTitle = 'unsupported inline image';
const String protocolPlaceholderKindAttribute = 'data-fleury-cell-kind';
const String protocolPlaceholderKind = 'protocol-placeholder';
const String protocolPlaceholderUnsupportedAttribute =
    'data-fleury-unsupported';
const String protocolPlaceholderUnsupported = 'inline-image';

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
      if (current != null && current.style == style && current.endCol == col) {
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
            appendText(
              col: col,
              text: cell.grapheme!,
              widthCols: 1,
              style: cell.style,
              kind: CellRunKind.text,
            );
            col += 1;
          }

        case CellRole.protocolAnchor:
          flushPending();
          runs.add(
            CellSpanRun(
              startCol: col,
              widthCols: 1,
              text: protocolPlaceholderGlyph,
              style: CellStyle.empty,
              kind: CellRunKind.protocolPlaceholder,
              correction: WidthCorrection.none,
            ),
          );
          col += 1;

        case CellRole.protocolCovered:
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
enum CellRunKind { text, wideText, emptyText, protocolPlaceholder }

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
