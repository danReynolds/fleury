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
      expect(image.cols, 3);
      expect(image.rows, 2);
      expect(image.bytes, bytes, reason: 'bytes preserved verbatim');

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
      expect(buf.images.values.single.fit, InlineImageFit.contain,
          reason: 'default preserves aspect ratio');

      buf.clear();
      buf.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([4, 5, 6]), width: 2, height: 1,
          fit: InlineImageFit.cover);
      expect(buf.images.values.single.fit, InlineImageFit.cover);
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
