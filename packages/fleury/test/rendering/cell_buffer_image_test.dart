import 'dart:typed_data';

import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/cell.dart';
import 'package:fleury/src/rendering/cell_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('CellBuffer.writeImage', () {
    test('stores bytes off-grid and anchors the region by id', () {
      final buf = CellBuffer(const CellSize(6, 4));
      final bytes = Uint8List.fromList(List<int>.generate(20, (i) => i));
      buf.writeImage(const CellOffset(1, 1), bytes, width: 3, height: 2);

      expect(buf.images.length, 1);
      final image = buf.images.values.single;
      expect(image.bytes, bytes, reason: 'bytes preserved verbatim');

      // Geometry lives on the placement, not the (dedup'd) image bytes.
      final placement = buf.imagePlacements.single;
      expect(placement.id, image.id);
      expect([placement.col, placement.row, placement.cols, placement.rows],
          [1, 1, 3, 2]);

      // The anchor carries only the id; covered cells fill the 3×2 region.
      final anchor = buf.atColRow(1, 1);
      expect(anchor.role, CellRole.protocolAnchor);
      expect(anchor.grapheme, image.id);
      expect(buf.images.containsKey(anchor.grapheme), isTrue,
          reason: 'grapheme is a key in the image table → it is an image, '
              'not a terminal escape');
      expect(buf.atColRow(2, 1).role, CellRole.protocolCovered);
      expect(buf.atColRow(3, 1).role, CellRole.protocolCovered);
      expect(buf.atColRow(1, 2).role, CellRole.protocolCovered);
    });

    test('fit defaults to contain and records an explicit fit', () {
      final buf = CellBuffer(const CellSize(8, 2));
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3]), width: 2, height: 1);
      expect(buf.imagePlacements.single.fit, InlineImageFit.contain,
          reason: 'default preserves aspect ratio');

      buf.clear();
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([4, 5, 6]), width: 2, height: 1,
          fit: InlineImageFit.cover);
      expect(buf.imagePlacements.single.fit, InlineImageFit.cover);
    });

    test('same bytes drawn twice: one image, two placements with own geometry',
        () {
      final buf = CellBuffer(const CellSize(12, 4));
      final bytes = Uint8List.fromList([7, 7, 7, 7]);
      buf.writeImage(const CellOffset(0, 0), bytes, width: 2, height: 2);
      buf.writeImage(const CellOffset(6, 1), bytes,
          width: 4, height: 1, fit: InlineImageFit.cover);

      expect(buf.images.length, 1, reason: 'bytes dedup to one entry');
      expect(buf.imagePlacements.length, 2, reason: 'two distinct rectangles');
      final p0 = buf.imagePlacements[0];
      final p1 = buf.imagePlacements[1];
      expect([p0.col, p0.row, p0.cols, p0.rows, p0.fit.name],
          [0, 0, 2, 2, 'contain']);
      expect([p1.col, p1.row, p1.cols, p1.rows, p1.fit.name],
          [6, 1, 4, 1, 'cover'],
          reason: 'the second placement keeps its own size/fit, not the first');
      expect(p0.id, p1.id, reason: 'same content id');
    });

    test('identical bytes hash to one id (ship-once dedup)', () {
      final buf = CellBuffer(const CellSize(10, 2));
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3, 4]), width: 2, height: 1);
      buf.writeImage(const CellOffset(5, 0),
          Uint8List.fromList([1, 2, 3, 4]), width: 2, height: 1);
      expect(buf.images.length, 1, reason: 'same content → same id');
    });

    test('different bytes get distinct ids', () {
      final buf = CellBuffer(const CellSize(10, 2));
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3]), width: 2, height: 1);
      buf.writeImage(const CellOffset(5, 0),
          Uint8List.fromList([9, 8, 7]), width: 2, height: 1);
      expect(buf.images.length, 2);
    });

    test('id is two delimited hash segments plus length', () {
      // The content hash combines two independent rolling hashes with the
      // byte length, delimited so distinct (h1,h2) pairs can never alias to
      // one string. Lock the shape so the delimiter is never dropped.
      final buf = CellBuffer(const CellSize(4, 1));
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3, 4, 5]), width: 2, height: 1);
      final id = buf.images.keys.single;
      final parts = id.split('-');
      expect(parts.length, 3, reason: 'h1-h2-length');
      expect(int.parse(parts[2]), 5, reason: 'trailing segment is byte length');
    });

    test('clear() drops the image table', () {
      final buf = CellBuffer(const CellSize(4, 2));
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([9, 9]), width: 2, height: 1);
      expect(buf.images, isNotEmpty);
      buf.clear();
      expect(buf.images, isEmpty);
    });
  });
}
