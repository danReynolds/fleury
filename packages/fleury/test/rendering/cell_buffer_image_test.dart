import 'dart:typed_data';

import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/cell.dart';
import 'package:fleury/src/rendering/cell_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('CellBuffer.writeImage', () {
    test('stores bytes off-grid and marks the region as overlay cells', () {
      final buf = CellBuffer(const CellSize(6, 4));
      final bytes = Uint8List.fromList(List<int>.generate(20, (i) => i));
      buf.writeImage(const CellOffset(1, 1), bytes, width: 3, height: 2);

      expect(buf.images.length, 1);
      final image = buf.images.values.single;
      expect(image.bytes, bytes, reason: 'bytes preserved verbatim');

      // Geometry lives on the placement, not the (dedup'd) image bytes.
      final placement = buf.imagePlacements.single;
      expect(placement.id, image.id);
      expect(
        [placement.col, placement.row, placement.cols, placement.rows],
        [1, 1, 3, 2],
      );

      // Every cell in the 3×2 region is an overlay cell: no grapheme, no
      // escape bytes, no id — presenters resolve pixels via the placement
      // list, never via cell content.
      for (var r = 1; r <= 2; r++) {
        for (var c = 1; c <= 3; c++) {
          final cell = buf.atColRow(c, r);
          expect(cell.role, CellRole.overlay, reason: 'cell ($c,$r)');
          expect(cell.grapheme, isNull);
        }
      }
      // Outside the region stays untouched.
      expect(buf.atColRow(0, 1).role, CellRole.empty);
      expect(buf.atColRow(4, 1).role, CellRole.empty);
      expect(buf.atColRow(1, 3).role, CellRole.empty);
    });

    test('records source dimensions and the RGBA thunk on the content', () {
      final buf = CellBuffer(const CellSize(6, 2));
      final rgba = Uint8List(4 * 2 * 4);
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1, 2, 3]),
        width: 3,
        height: 1,
        sourceWidth: 4,
        sourceHeight: 2,
        pixels: () => rgba,
      );
      final image = buf.images.values.single;
      expect(image.sourceWidth, 4);
      expect(image.sourceHeight, 2);
      expect(image.pixels!(), same(rgba));
    });

    test('rect copies carry intersecting placements, translated', () {
      // RenderRepaintBoundary blits a cached sub-buffer into the frame;
      // placements live on the buffer, so the blit must carry them or an
      // image inside a repaint boundary vanishes on the first cached
      // frame.
      final cache = CellBuffer(const CellSize(6, 4));
      cache.writeImage(
        const CellOffset(1, 1),
        Uint8List.fromList([7, 7]),
        width: 3,
        height: 2,
        fit: InlineImageFit.cover,
      );
      final frame = CellBuffer(const CellSize(12, 8));
      frame.copyRectFrom(
        cache,
        CellRect.fromLTWH(0, 0, 6, 4),
        const CellOffset(4, 2),
      );

      final p = frame.imagePlacements.single;
      expect([p.col, p.row, p.cols, p.rows], [5, 3, 3, 2]);
      expect(p.fit, InlineImageFit.cover);
      expect(frame.images.containsKey(p.id), isTrue);
      expect(frame.atColRow(5, 3).role, CellRole.overlay);

      // A copy that misses the placement carries nothing.
      final other = CellBuffer(const CellSize(12, 8));
      other.copyRectFrom(
        cache,
        CellRect.fromLTWH(4, 0, 2, 4),
        const CellOffset(0, 0),
      );
      expect(other.imagePlacements, isEmpty);
      expect(other.images, isEmpty);
    });

    test('a region clipped by the buffer edge writes only in-bounds cells', () {
      final buf = CellBuffer(const CellSize(4, 2));
      buf.writeImage(
        const CellOffset(2, 1),
        Uint8List.fromList([1]),
        width: 5,
        height: 3,
      );
      expect(buf.atColRow(2, 1).role, CellRole.overlay);
      expect(buf.atColRow(3, 1).role, CellRole.overlay);
      // The placement itself keeps the full requested geometry (presenters
      // clip at the screen edge, matching terminal protocol behavior).
      expect(buf.imagePlacements.single.cols, 5);
    });

    test('fit defaults to contain and records an explicit fit', () {
      final buf = CellBuffer(const CellSize(8, 2));
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1, 2, 3]),
        width: 2,
        height: 1,
      );
      expect(
        buf.imagePlacements.single.fit,
        InlineImageFit.contain,
        reason: 'default preserves aspect ratio',
      );

      buf.clear();
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([4, 5, 6]),
        width: 2,
        height: 1,
        fit: InlineImageFit.cover,
      );
      expect(buf.imagePlacements.single.fit, InlineImageFit.cover);
    });

    test(
      'same bytes drawn twice: one image, two placements with own geometry',
      () {
        final buf = CellBuffer(const CellSize(12, 4));
        final bytes = Uint8List.fromList([7, 7, 7, 7]);
        buf.writeImage(const CellOffset(0, 0), bytes, width: 2, height: 2);
        buf.writeImage(
          const CellOffset(6, 1),
          bytes,
          width: 4,
          height: 1,
          fit: InlineImageFit.cover,
        );

        expect(buf.images.length, 1, reason: 'bytes dedup to one entry');
        expect(
          buf.imagePlacements.length,
          2,
          reason: 'two distinct rectangles',
        );
        final p0 = buf.imagePlacements[0];
        final p1 = buf.imagePlacements[1];
        expect(
          [p0.col, p0.row, p0.cols, p0.rows, p0.fit.name],
          [0, 0, 2, 2, 'contain'],
        );
        expect(
          [p1.col, p1.row, p1.cols, p1.rows, p1.fit.name],
          [6, 1, 4, 1, 'cover'],
          reason: 'the second placement keeps its own size/fit, not the first',
        );
        expect(p0.id, p1.id, reason: 'same content id');
      },
    );

    test('identical bytes hash to one id (ship-once dedup)', () {
      final buf = CellBuffer(const CellSize(10, 2));
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1, 2, 3, 4]),
        width: 2,
        height: 1,
      );
      buf.writeImage(
        const CellOffset(5, 0),
        Uint8List.fromList([1, 2, 3, 4]),
        width: 2,
        height: 1,
      );
      expect(buf.images.length, 1, reason: 'same content → same id');
    });

    test('different bytes get distinct ids', () {
      final buf = CellBuffer(const CellSize(10, 2));
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1, 2, 3]),
        width: 2,
        height: 1,
      );
      buf.writeImage(
        const CellOffset(5, 0),
        Uint8List.fromList([9, 8, 7]),
        width: 2,
        height: 1,
      );
      expect(buf.images.length, 2);
    });

    test('id is two delimited hash segments plus length', () {
      // The content hash combines two independent rolling hashes with the
      // byte length, delimited so distinct (h1,h2) pairs can never alias to
      // one string. Lock the shape so the delimiter is never dropped.
      final buf = CellBuffer(const CellSize(4, 1));
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1, 2, 3, 4, 5]),
        width: 2,
        height: 1,
      );
      final id = buf.images.keys.single;
      final parts = id.split('-');
      expect(parts.length, 3, reason: 'h1-h2-length');
      expect(int.parse(parts[2]), 5, reason: 'trailing segment is byte length');
    });

    test('clear() drops the image table', () {
      final buf = CellBuffer(const CellSize(4, 2));
      buf.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([9, 9]),
        width: 2,
        height: 1,
      );
      expect(buf.images, isNotEmpty);
      buf.clear();
      expect(buf.images, isEmpty);
    });
  });
}
