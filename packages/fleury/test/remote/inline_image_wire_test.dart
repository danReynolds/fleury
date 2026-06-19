import 'dart:typed_data';

import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/rendering/cell_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('inline image wire', () {
    test('buildRemotePlan emits a placement and blanks the image cells', () {
      final prev = CellBuffer(const CellSize(8, 4));
      final next = CellBuffer(const CellSize(8, 4));
      final bytes = Uint8List.fromList(List<int>.generate(30, (i) => i % 256));
      next.writeImage(const CellOffset(1, 1), bytes, width: 3, height: 2);

      final plan = buildRemotePlan(prev, next, fullRepaint: true);

      expect(plan.placements.length, 1);
      final p = plan.placements.single;
      expect([p.col, p.row, p.cols, p.rows], [1, 1, 3, 2]);
      expect(next.images.containsKey(p.id), isTrue);

      // The image id must never leak into the grid patch as text.
      final gridText =
          plan.patches.expand((pp) => pp.runs).map((r) => r.text).join();
      expect(gridText.contains(p.id), isFalse,
          reason: 'image region is blanked; bytes travel out of band');
    });

    test('placements round-trip through the plan wire', () {
      final next = CellBuffer(const CellSize(6, 3));
      next.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3, 4]), width: 2, height: 2);
      final plan =
          buildRemotePlan(CellBuffer(const CellSize(6, 3)), next, fullRepaint: true);

      final decoded = decodeRemotePlan(encodeRemotePlan(plan));

      expect(decoded.placements.length, 1);
      final p = decoded.placements.single;
      final original = plan.placements.single;
      expect([p.id, p.col, p.row, p.cols, p.rows],
          [original.id, 0, 0, 2, 2]);
    });

    test('a plan with no images round-trips with empty placements', () {
      final next = CellBuffer(const CellSize(4, 2))
        ..writeText(const CellOffset(0, 0), 'hi');
      final plan =
          buildRemotePlan(CellBuffer(const CellSize(4, 2)), next, fullRepaint: true);
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.placements, isEmpty);
    });

    test('InlineImageFrame round-trips id + bytes (incl. >256 bytes)', () {
      final bytes =
          Uint8List.fromList(List<int>.generate(257, (i) => (i * 7) % 256));
      final encoded = encodeFrame(InlineImageFrame('abc123-257', bytes));
      final decoder = FrameDecoder()..feed(encoded);
      final frame = decoder.drain().single;
      expect(frame, isA<InlineImageFrame>());
      final f = frame as InlineImageFrame;
      expect(f.id, 'abc123-257');
      expect(f.bytes, bytes);
    });
  });
}
