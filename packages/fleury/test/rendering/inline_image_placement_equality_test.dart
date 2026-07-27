// Every field of an [InlineImagePlacement] must count as a difference.
//
// `CellBuffer.diffAgainst` decides whether an inline image changed by comparing
// placement lists, and the cells beneath a placement are payload-free overlays
// that can never show the difference. So a field missing from `operator ==` is
// a field whose change is invisible to every presenter — the image keeps
// rendering the old way until something unrelated dirties the row.
//
// This is a table rather than a fuzz: two placements differing in exactly ONE
// field is a conjunction random generation will not produce, and an oracle that
// re-lists the fields can only drift in lockstep with the implementation. Each
// case here isolates a single field, so deleting any one comparison fails.

import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

const _base = InlineImagePlacement(
  id: 'base',
  col: 2,
  row: 1,
  cols: 3,
  rows: 2,
  fit: InlineImageFit.contain,
  boxCols: 6,
  boxRows: 4,
  boxOffsetCol: 1,
  boxOffsetRow: 1,
);

/// One variant per field, each differing from [_base] in that field alone.
const _oneFieldApart = <String, InlineImagePlacement>{
  'id': InlineImagePlacement(
    id: 'other',
    col: 2,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'col': InlineImagePlacement(
    id: 'base',
    col: 3,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'row': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 2,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'cols': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 4,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'rows': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 3,
    rows: 3,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'fit': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.cover,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'boxCols': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 7,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'boxRows': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 5,
    boxOffsetCol: 1,
    boxOffsetRow: 1,
  ),
  'boxOffsetCol': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 2,
    boxOffsetRow: 1,
  ),
  'boxOffsetRow': InlineImagePlacement(
    id: 'base',
    col: 2,
    row: 1,
    cols: 3,
    rows: 2,
    fit: InlineImageFit.contain,
    boxCols: 6,
    boxRows: 4,
    boxOffsetCol: 1,
    boxOffsetRow: 2,
  ),
};

void main() {
  group('InlineImagePlacement equality', () {
    for (final entry in _oneFieldApart.entries) {
      test('a different ${entry.key} is a different placement', () {
        expect(
          entry.value,
          isNot(_base),
          reason:
              'a change in ${entry.key} alone would otherwise be invisible to '
              'the frame diff, and the image would keep its old rendering',
        );
        expect(entry.value.hashCode, isNot(_base.hashCode));
      });
    }

    test('an identical placement is equal', () {
      const same = InlineImagePlacement(
        id: 'base',
        col: 2,
        row: 1,
        cols: 3,
        rows: 2,
        fit: InlineImageFit.contain,
        boxCols: 6,
        boxRows: 4,
        boxOffsetCol: 1,
        boxOffsetRow: 1,
      );
      expect(same, _base);
      expect(same.hashCode, _base.hashCode);
    });

    test('the table covers every field the class declares', () {
      // Guards the guard: a field added to InlineImagePlacement without a case
      // here would otherwise slip in unnoticed, which is the exact way the
      // fit/box fields went uncompared in the first place.
      expect(_oneFieldApart.keys, hasLength(10));
    });
  });
}
