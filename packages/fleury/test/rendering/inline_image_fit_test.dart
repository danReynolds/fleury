// The single fit resolver every surface derives geometry from: the
// terminal image encoder (protocol cell boxes), the glyph painters
// (sub-pixel densities), and — by documented equivalence — the browser's
// CSS object-fit. These assertions are the ported behavioral goldens from
// the old per-protocol widget tests (letterbox band position, cover crop,
// native centering), now pinned once at the shared source of truth.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('resolveInlineImageFit — fill', () {
    test('whole box, whole source, any aspect', () {
      final f = resolveInlineImageFit(
        sourceWidth: 8,
        sourceHeight: 8,
        cols: 4,
        rows: 3,
        fit: InlineImageFit.fill,
      );
      expect([f.col, f.row, f.cols, f.rows], [0, 0, 4, 3]);
      expect([f.cropX, f.cropY, f.cropW, f.cropH], [0, 0, 8, 8]);
      expect(f.cropsSource, isFalse);
    });
  });

  group('resolveInlineImageFit — contain', () {
    test('a 4:1 source in a square box occupies one centered row band', () {
      // The old Kitty widget test's letterbox oracle: 16×4 px in an 8×8
      // cell box (8×16 half-pixel target) scales to 8 cols × 1 row,
      // vertically centered — NOT the whole box (that would distort).
      final f = resolveInlineImageFit(
        sourceWidth: 16,
        sourceHeight: 4,
        cols: 8,
        rows: 8,
        fit: InlineImageFit.contain,
      );
      expect(f.cols, 8);
      expect(f.rows, 1, reason: 'a 4:1 image in a square box is one row');
      expect(f.col, 0);
      expect(
        f.row,
        greaterThan(0),
        reason: 'the band is vertically centered, not top-aligned',
      );
      expect(f.cropsSource, isFalse, reason: 'contain shows the whole source');
    });

    test('a tall source pillarboxes horizontally', () {
      // 4×32 px in an 8×8 box: height-limited (16 half-pixels), so
      // 2 cols centered at col 3.
      final f = resolveInlineImageFit(
        sourceWidth: 4,
        sourceHeight: 32,
        cols: 8,
        rows: 8,
        fit: InlineImageFit.contain,
      );
      expect(f.rows, 8);
      expect(f.cols, 2);
      expect(f.col, 3);
    });

    test('a box matching the source aspect degenerates to the full box', () {
      // 8×16 px in a 4×4 cell box: at 1×2 px per cell the box target is
      // 4×8 px — exactly the source aspect.
      final f = resolveInlineImageFit(
        sourceWidth: 8,
        sourceHeight: 16,
        cols: 4,
        rows: 4,
        fit: InlineImageFit.contain,
      );
      expect([f.col, f.row, f.cols, f.rows], [0, 0, 4, 4]);
    });
  });

  group('resolveInlineImageFit — cover', () {
    test('fills the whole box with a centered source crop', () {
      // 16×4 px covering a 6×6 box (6×12 half-pixel target): height
      // dominates (scale 3), so the source is cropped to a centered
      // 2×4 px window.
      final f = resolveInlineImageFit(
        sourceWidth: 16,
        sourceHeight: 4,
        cols: 6,
        rows: 6,
        fit: InlineImageFit.cover,
      );
      expect([f.col, f.row, f.cols, f.rows], [0, 0, 6, 6]);
      expect(f.cropW, 2);
      expect(f.cropH, 4);
      expect(f.cropX, 7, reason: 'crop window is horizontally centered');
      expect(f.cropY, 0);
      expect(f.cropsSource, isTrue);
    });

    test('a box matching the source aspect needs no crop', () {
      final f = resolveInlineImageFit(
        sourceWidth: 8,
        sourceHeight: 16,
        cols: 4,
        rows: 4,
        fit: InlineImageFit.cover,
      );
      expect(f.cropsSource, isFalse);
    });
  });

  group('resolveInlineImageFit — none', () {
    test('small source renders at native scale, centered', () {
      // 3×4 px in an 8×4 box (8×8 half-pixels): 3 cols × 2 rows centered.
      final f = resolveInlineImageFit(
        sourceWidth: 3,
        sourceHeight: 4,
        cols: 8,
        rows: 4,
        fit: InlineImageFit.none,
      );
      expect(f.cols, 3);
      expect(f.rows, 2);
      expect(f.col, 3, reason: 'centered: (8-3)/2 rounds to 3');
      expect(f.row, 1);
      expect(f.cropsSource, isFalse);
    });

    test('oversized source is center-cropped to the box', () {
      final f = resolveInlineImageFit(
        sourceWidth: 100,
        sourceHeight: 100,
        cols: 4,
        rows: 4,
        fit: InlineImageFit.none,
      );
      expect([f.col, f.row, f.cols, f.rows], [0, 0, 4, 4]);
      expect(f.cropW, 4, reason: '1 source px per target px: 4 cols wide');
      expect(f.cropH, 8, reason: '8 half-pixel rows tall');
      expect(f.cropX, 48, reason: 'crop window centered in the source');
      expect(f.cropY, 46);
      expect(f.cropsSource, isTrue);
    });
  });

  group('resolveInlineImageFit — cell pixel density', () {
    test('the same contain resolves consistently across densities', () {
      // A 2:1 source in a 4×4 box. At glyph density (1×2) the target is
      // 4×8 px; at sixel density (10×20) it is 40×80 px. Both must land
      // the same CELL geometry — that is the whole point of the shared
      // resolver.
      final glyph = resolveInlineImageFit(
        sourceWidth: 20,
        sourceHeight: 10,
        cols: 4,
        rows: 4,
        fit: InlineImageFit.contain,
      );
      final sixel = resolveInlineImageFit(
        sourceWidth: 20,
        sourceHeight: 10,
        cols: 4,
        rows: 4,
        fit: InlineImageFit.contain,
        pixelsPerCellX: 10,
        pixelsPerCellY: 20,
      );
      expect(
        [glyph.col, glyph.row, glyph.cols, glyph.rows],
        [sixel.col, sixel.row, sixel.cols, sixel.rows],
      );
      expect([glyph.cols, glyph.rows], [4, 1]);
    });
  });
}
