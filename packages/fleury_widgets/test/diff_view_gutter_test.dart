// DiffView's line-number gutter is as wide as the widest line number. It is
// measured once per document; each build used to walk every row for it, so
// an arrow key in a long diff cost O(rows).
import 'dart:collection';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// A document's rows, counting how often a row is read.
final class _CountingRows extends ListBase<DiffLine> {
  _CountingRows(this._rows);

  final List<DiffLine> _rows;
  var reads = 0;

  @override
  int get length => _rows.length;
  @override
  set length(int value) => throw UnsupportedError('fixed');
  @override
  DiffLine operator [](int index) {
    reads++;
    return _rows[index];
  }

  @override
  void operator []=(int index, DiffLine value) =>
      throw UnsupportedError('fixed');
}

DiffDocument _document(
  int lines, {
  List<DiffLine> Function(List<DiffLine>)? wrap,
}) {
  final source = StringBuffer('@@ -1,$lines +1,$lines @@\n');
  for (var i = 0; i < lines; i++) {
    source.writeln(' line $i');
  }
  final parsed = parseUnifiedDiff(source.toString());
  return DiffDocument(
    rows: wrap == null ? parsed.rows : wrap(parsed.rows),
    fileCount: parsed.fileCount,
    hunkCount: parsed.hunkCount,
    additionCount: parsed.additionCount,
    deletionCount: parsed.deletionCount,
  );
}

void main() {
  testWidgets('an arrow key does not walk every row for the gutter', (tester) {
    late _CountingRows rows;
    final document = _document(
      2000,
      wrap: (parsed) => rows = _CountingRows(parsed),
    );
    tester.pumpWidget(DiffView.document(document: document, autofocus: true));
    tester.render(size: const CellSize(40, 10));

    rows.reads = 0;
    for (var i = 0; i < 5; i++) {
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: const CellSize(40, 10));
    }

    expect(rows.reads, lessThan(500), reason: '${rows.reads} row reads');
  });

  testWidgets('a new document is measured for its own gutter', (tester) {
    String firstRow() => tester
        .renderToString(size: const CellSize(40, 4), emptyMark: ' ')
        .split('\n')
        .firstWhere((line) => line.contains('│'));

    tester.pumpWidget(DiffView.document(document: _document(5)));
    final narrow = firstRow().indexOf('│');

    tester.pumpWidget(DiffView.document(document: _document(1200)));
    final wide = firstRow().indexOf('│');

    // Two columns of line numbers, three digits wider each.
    expect(wide - narrow, 6);
  });
}
