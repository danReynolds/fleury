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

    test('emits protocol placeholders and skips covered cells', () {
      final row = builder.buildRow(
        frame(4, 1, (b) {
          b.writeProtocol(
            const CellOffset(1, 0),
            'image-bytes',
            width: 2,
            height: 1,
          );
        }),
        0,
      );

      final protocol = row.runs.singleWhere(
        (run) => run.kind == CellRunKind.protocolPlaceholder,
      );
      expect(protocol.startCol, 1);
      expect(protocol.widthCols, 1);
      expect(protocol.text, protocolPlaceholderGlyph);
      expect(
        row.runs.map((run) => run.text).join(),
        isNot(contains('image-bytes')),
      );
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
