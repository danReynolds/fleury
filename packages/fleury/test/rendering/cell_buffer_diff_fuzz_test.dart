// Property test for `CellBuffer.diffAgainst` against a naive reference.
//
// The whole damage architecture rests on this one method: presenters re-apply
// exactly what it reports and assume everything else still matches the screen.
// Example-based tests cover the cases we thought of — and the case we did NOT
// think of (a placement whose fit/offset changed while its cells stayed
// byte-identical) shipped as a real gap. A reference comparison catches that
// class without anyone having to imagine it first.
//
// The reference is deliberately dumb: compare every cell, compare the placement
// lists field by field. Any disagreement is a bug in the fast path.

import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

/// Everything a presenter can observe about how a frame renders.
///
/// All four fields of [CellBufferDiff], not just the two a presenter reads
/// directly: `dirtyCells` gates whether scroll detection runs at all, and
/// `hasOverlayCells` is the ONLY thing disqualifying an image frame from
/// scrolling. A wrong value in either is invisible in the rows and bounds yet
/// changes what the terminal emits.
typedef _Reference = ({
  Set<int> rows,
  CellRect? bounds,
  int dirtyCells,
  bool hasOverlayCells,
});

/// The obvious, slow answer: scan every cell, then every placement.
_Reference _referenceDiff(CellBuffer previous, CellBuffer next) {
  final size = next.size;
  final rows = <int>{};
  var dirtyCells = 0;
  var left = size.cols;
  var right = 0;
  var top = size.rows;
  var bottom = 0;

  // Derived by LOOKING AT CELLS, deliberately unlike the implementation, which
  // takes the O(1) shortcut of asking whether either buffer holds placements.
  // Transcribing that shortcut here would make the two agree by construction
  // and prove nothing about whether the shortcut is sound.
  var hasOverlayCells = false;
  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      if (previous.atColRow(col, row).role == CellRole.overlay ||
          next.atColRow(col, row).role == CellRole.overlay) {
        hasOverlayCells = true;
      }
    }
  }

  void mark(int row, int firstCol, int lastCol) {
    rows.add(row);
    if (firstCol < left) left = firstCol;
    if (lastCol + 1 > right) right = lastCol + 1;
    if (row < top) top = row;
    if (row + 1 > bottom) bottom = row + 1;
  }

  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      if (previous.atColRow(col, row) != next.atColRow(col, row)) {
        dirtyCells++;
        mark(row, col, col);
      }
    }
  }

  // Cells under an image are payload-free overlays, so a placement change can
  // be invisible above. Compare the lists on every field that reaches the fit
  // resolver or the overlay's geometry.
  // Whole-value comparison: listing fields here would be a transcription of
  // the implementation's list, so a field missing from BOTH would be
  // structurally invisible — which is how the fit/box fields went uncompared.
  final samePlacements = const ListEquality<InlineImagePlacement>().equals(
    next.imagePlacements,
    previous.imagePlacements,
  );

  if (!samePlacements) {
    for (final list in [next.imagePlacements, previous.imagePlacements]) {
      for (final p in list) {
        // Placements are always recorded on-grid (writeImageWithId clips), so
        // this mirrors the implementation's intent without its dead clamps.
        final firstCol = p.col;
        final lastCol = p.col + p.cols - 1;
        final firstRow = p.row;
        final lastRow = p.row + p.rows - 1;
        for (var row = firstRow; row <= lastRow; row++) {
          mark(row, firstCol, lastCol);
        }
      }
    }
  }

  if (rows.isEmpty) {
    return (
      rows: rows,
      bounds: null,
      dirtyCells: dirtyCells,
      hasOverlayCells: hasOverlayCells,
    );
  }
  return (
    rows: rows,
    bounds: CellRect.fromLTWH(left, top, right - left, bottom - top),
    dirtyCells: dirtyCells,
    hasOverlayCells: hasOverlayCells,
  );
}

/// Paints pseudo-random but reproducible content: narrow and wide graphemes,
/// varied styles, occasional inline images, and blank gaps.
void _paintRandom(CellBuffer buffer, Random random) {
  final size = buffer.size;
  for (var row = 0; row < size.rows; row++) {
    var col = 0;
    while (col < size.cols) {
      switch (random.nextInt(6)) {
        case 0: // gap
          col += 1 + random.nextInt(3);
        case 1: // wide grapheme — leading + continuation pair
          buffer.writeText(CellOffset(col, row), '漢');
          col += 2;
        case 2: // styled run
          buffer.writeText(
            CellOffset(col, row),
            String.fromCharCode(0x61 + random.nextInt(26)) *
                (1 + random.nextInt(3)),
            style: CellStyle(
              foreground: RgbColor(
                random.nextInt(256),
                random.nextInt(256),
                random.nextInt(256),
              ),
              bold: random.nextBool(),
              underline: random.nextBool(),
            ),
          );
          col += 3;
        case 3: // linked cell — non-visual state the diff must still see
          buffer.writeText(
            CellOffset(col, row),
            'l',
            style: CellStyle(linkUri: 'https://e/${random.nextInt(3)}'),
          );
          col += 1;
        default:
          buffer.writeText(
            CellOffset(col, row),
            String.fromCharCode(0x41 + random.nextInt(26)),
          );
          col += 1;
      }
    }
  }
  if (random.nextInt(3) == 0 && size.rows >= 2 && size.cols >= 4) {
    _placeImage(buffer, random, size);
  }
}

/// Places an image, sometimes CLIPPED off the top-left edge.
///
/// A clipped placement is the case that matters: clipping puts the offset into
/// `boxOffsetCol`/`boxOffsetRow` while the visible rect stays clamped to the
/// grid, so the same image scrolled under a viewport keeps its id AND its
/// visible rect and changes only those fields — and the cells beneath it are
/// payload-free overlays either way. Nothing else in the buffer records that a
/// change happened, which is exactly how the fields went uncompared once.
void _placeImage(CellBuffer buffer, Random random, CellSize size) {
  const fits = InlineImageFit.values;
  // A negative origin clips: the visible rect clamps to 0 while the box offset
  // absorbs the difference.
  final clipped = random.nextBool();
  buffer.writeImage(
    CellOffset(
      clipped ? -1 - random.nextInt(2) : random.nextInt(size.cols - 3),
      clipped ? -1 - random.nextInt(2) : random.nextInt(size.rows - 1),
    ),
    Uint8List.fromList([random.nextInt(4)]),
    width: 3 + random.nextInt(2),
    height: 2 + random.nextInt(2),
    fit: fits[random.nextInt(fits.length)],
  );
}

void main() {
  group('diffAgainst matches a naive reference', () {
    // Fixed seeds: reproducible, and a failure names the seed that broke it.
    for (final seed in [1, 7, 42, 99, 1234, 20260727]) {
      test('seed $seed', () {
        final random = Random(seed);
        for (var round = 0; round < 40; round++) {
          final size = CellSize(4 + random.nextInt(12), 2 + random.nextInt(8));
          final previous = CellBuffer(size);
          final next = CellBuffer(size);
          _paintRandom(previous, random);
          // Half the rounds start from a copy, so small edits and pure
          // vacates are exercised as often as wholesale repaints.
          if (random.nextBool()) {
            next.copyRectFrom(
              previous,
              CellRect(offset: CellOffset.zero, size: size),
              CellOffset.zero,
            );
            final edits = random.nextInt(4);
            for (var i = 0; i < edits; i++) {
              buffered(next, random, size);
            }
          } else {
            _paintRandom(next, random);
          }

          final actual = next.diffAgainst(previous);
          final expected = _referenceDiff(previous, next);

          expect(
            actual.rows,
            expected.rows,
            reason: 'seed $seed round $round: dirty rows disagree',
          );
          expect(
            actual.bounds,
            expected.bounds,
            reason: 'seed $seed round $round: bounds disagree',
          );
          expect(
            actual.isUnchanged,
            expected.rows.isEmpty,
            reason: 'seed $seed round $round: isUnchanged disagrees',
          );
          expect(
            actual.dirtyCells,
            expected.dirtyCells,
            reason:
                'seed $seed round $round: dirty cell COUNT disagrees — '
                'this gates whether scroll detection runs at all',
          );
          expect(
            actual.hasOverlayCells,
            expected.hasOverlayCells,
            reason:
                'seed $seed round $round: overlay presence disagrees — '
                'this is what keeps image frames from being scrolled',
          );
        }
      });
    }

    test('a clipped placement that only moved under its viewport is dirty', () {
      // Directed, because random generation will not hit this conjunction:
      // SAME image id, SAME visible rect, all cells byte-identical, and only
      // the box offset/extent differing. That is an image scrolling under a
      // clipping viewport — and it is the exact shape whose fields went
      // uncompared once. Fuzzing covers the broad property; a narrow
      // conjunction still needs to be named.
      const size = CellSize(6, 4);
      final bytes = Uint8List.fromList([7, 7, 7]);
      final earlier = CellBuffer(size)
        ..writeImage(const CellOffset(-1, -1), bytes, width: 4, height: 3);
      final later = CellBuffer(size)
        ..writeImage(const CellOffset(-2, -2), bytes, width: 5, height: 4);

      // Precondition: identical id and visible rect, so only the box moved.
      final a = earlier.imagePlacements.single;
      final b = later.imagePlacements.single;
      expect(b.id, a.id);
      expect([b.col, b.row, b.cols, b.rows], [a.col, a.row, a.cols, a.rows]);
      expect(b.boxOffsetRow, isNot(a.boxOffsetRow));

      final diff = later.diffAgainst(earlier);
      expect(diff.dirtyCells, 0, reason: 'the cells really are identical');
      expect(
        diff.isUnchanged,
        isFalse,
        reason: 'the image moved under its viewport — the frame changed',
      );
      expect(diff.rows, isNotEmpty);
    });

    test('an unpainted pair is unchanged, and comparable', () {
      const size = CellSize(6, 3);
      final diff = CellBuffer(size).diffAgainst(CellBuffer(size));
      expect(diff.isComparable, isTrue);
      expect(diff.isUnchanged, isTrue);
      expect(diff.bounds, isNull);
    });
  });
}

/// One small mutation: overwrite a cell, blank a cell, or move an image.
void buffered(CellBuffer buffer, Random random, CellSize size) {
  final col = random.nextInt(size.cols);
  final row = random.nextInt(size.rows);
  switch (random.nextInt(3)) {
    case 0:
      buffer.writeText(
        CellOffset(col, row),
        String.fromCharCode(0x41 + random.nextInt(26)),
      );
    case 1:
      buffer.writeText(CellOffset(col, row), ' ');
    default:
      if (size.cols >= 4 && size.rows >= 2) _placeImage(buffer, random, size);
  }
}
