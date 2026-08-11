import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

CellBuffer frame(int cols, int rows, void Function(CellBuffer b) paint) {
  final buffer = CellBuffer(CellSize(cols, rows));
  paint(buffer);
  return buffer;
}

void main() {
  const builder = CellSpanBuilder();

  group('CellSpanBuilder', () {
    test('tracks cell width separately from string length', () {
      const combining = 'é';
      final row = builder.buildRow(
        frame(4, 1, (b) => b.writeText(const CellOffset(0, 0), combining)),
        0,
      );

      expect(row.cols, 4);
      expect(row.runs.single.kind, CellRunKind.text);
      expect(row.runs.single.text, '$combining   ');
      expect(row.runs.single.widthCols, 4);
      expect(
        row.runs.single.text.length,
        greaterThan(row.runs.single.widthCols),
      );
    });

    test('emits wide cells as pinned-width runs without continuation echo', () {
      final row = builder.buildRow(
        frame(5, 1, (b) => b.writeText(const CellOffset(0, 0), '状')),
        0,
      );

      final wide = row.runs.first;
      expect(wide.kind, CellRunKind.wideText);
      expect(wide.startCol, 0);
      expect(wide.widthCols, 2);
      expect(wide.text, '状');
      expect(wide.correction, WidthCorrection.pinToCellWidth);
      expect('状'.allMatches(row.runs.map((r) => r.text).join()).length, 1);
    });

    test('preserves style boundaries while coalescing compatible runs', () {
      final row = builder.buildRow(
        frame(6, 1, (b) {
          b.writeText(const CellOffset(0, 0), 'ab');
          b.writeText(
            const CellOffset(2, 0),
            'cd',
            style: const CellStyle(foreground: Colors.green),
          );
        }),
        0,
      );

      expect(row.runs, hasLength(3));
      expect(row.runs[0].text, 'ab');
      expect(row.runs[0].style, CellStyle.empty);
      expect(row.runs[1].text, 'cd');
      expect(row.runs[1].style.foreground, Colors.green);
      expect(row.runs[2].kind, CellRunKind.emptyText);
      expect(row.runs[2].text, '  ');
    });

    test('overlay (inline-image) cells become blank runs, nothing leaks', () {
      final buffer = frame(4, 1, (b) {
        b.writeImage(
          const CellOffset(1, 0),
          Uint8List.fromList([1, 2, 3]),
          width: 2,
          height: 1,
        );
      });
      final row = builder.buildRow(buffer, 0);

      // The whole row coalesces into one blank run — the <img> overlay
      // renders the pixels; the grid carries no id and no bytes.
      final run = row.runs.single;
      expect(run.kind, CellRunKind.emptyText);
      expect(run.text, '    ');
      expect(run.text, isNot(contains(buffer.imagePlacements.single.id)));
    });

    test('full-width block glyphs coalesce into one run', () {
      // A bar chart's `barWidth: 2` column: two `█` cells in one style. They
      // must arrive as a single run carrying the grapheme once — the DOM
      // adapters paint the run as one rectangle, so the seam a per-cell glyph
      // would leave between them cannot exist.
      final row = builder.buildRow(
        frame(4, 1, (b) {
          b.writeText(
            const CellOffset(0, 0),
            '██',
            style: const CellStyle(foreground: Colors.green),
          );
        }),
        0,
      );

      final block = row.runs.first;
      expect(block.kind, CellRunKind.blockElement);
      expect(block.startCol, 0);
      expect(block.widthCols, 2);
      expect(block.text, '█', reason: 'the grapheme is carried once');
    });

    test('a differing block glyph or style breaks the run', () {
      // A bar's partial top cell (`▅`) sits on top of full cells, and a stacked
      // bar changes color at a segment boundary. Neither may merge.
      final row = builder.buildRow(
        frame(4, 1, (b) {
          b.writeText(const CellOffset(0, 0), '█▅');
          b.writeText(
            const CellOffset(2, 0),
            '█',
            style: const CellStyle(foreground: Colors.red),
          );
        }),
        0,
      );

      expect(
        row.runs.take(3).map((r) => (r.kind, r.text, r.widthCols)),
        [
          (CellRunKind.blockElement, '█', 1),
          (CellRunKind.blockElement, '▅', 1),
          (CellRunKind.blockElement, '█', 1),
        ],
      );
      expect(row.runs[2].style.foreground, Colors.red);
    });

    test('partial-width block glyphs stay one cell per run', () {
      // `▌` is half a cell wide. Coalescing would stretch one half-width
      // rectangle across both cells, so each keeps its own run.
      final row = builder.buildRow(
        frame(3, 1, (b) => b.writeText(const CellOffset(0, 0), '▌▌')),
        0,
      );

      expect(row.runs[0].kind, CellRunKind.blockElement);
      expect(row.runs[0].widthCols, 1);
      expect(row.runs[1].kind, CellRunKind.blockElement);
      expect(row.runs[1].widthCols, 1);
      // ...and the run after them is ordinary text, not an absorbed cell.
      expect(row.runs[2].kind, CellRunKind.emptyText);
    });

    test('shade and braille glyphs stay on the text path', () {
      // Stipple textures are not solid rectangles; flattening them to a tint
      // would change how they read, so they keep the font glyph.
      final row = builder.buildRow(
        frame(4, 1, (b) => b.writeText(const CellOffset(0, 0), '░▒⠿⣿')),
        0,
      );

      expect(row.runs.single.kind, CellRunKind.text);
      expect(row.runs.single.text, '░▒⠿⣿');
    });

    test('buildDirtyRows builds only requested row models', () {
      final buffer = frame(4, 3, (b) {
        b.writeText(const CellOffset(0, 0), 'zero');
        b.writeText(const CellOffset(0, 1), 'one');
        b.writeText(const CellOffset(0, 2), 'two');
      });

      final rows = builder.buildDirtyRows(
        buffer,
        TuiDirtyRows.range(1, 3, rowCount: buffer.size.rows),
      );

      expect(rows.map((row) => row.row), [1, 2]);
      expect(rows.first.runs.first.text, 'one ');
      expect(rows.last.runs.first.text, 'two ');
    });
  });
}
