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

    test('two distinct images on one frame yield two placements', () {
      final next = CellBuffer(const CellSize(12, 4))
        ..writeImage(const CellOffset(0, 0),
            Uint8List.fromList([1, 1, 1, 1]), width: 2, height: 2)
        ..writeImage(const CellOffset(6, 0),
            Uint8List.fromList([2, 2, 2, 2]), width: 3, height: 2);

      final plan =
          buildRemotePlan(CellBuffer(const CellSize(12, 4)), next, fullRepaint: true);

      expect(plan.placements.length, 2);
      expect(plan.placements.map((p) => p.id).toSet().length, 2,
          reason: 'distinct bytes → distinct ids');
      // Round-trips both.
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.placements.map((p) => '${p.col}:${p.cols}').toSet(),
          {'0:2', '6:3'});
    });

    test('a static (unchanged) image still emits its placement', () {
      final bytes = Uint8List.fromList([5, 6, 7, 8]);
      final prev = CellBuffer(const CellSize(6, 3))
        ..writeImage(const CellOffset(1, 0), bytes, width: 2, height: 2);
      final next = CellBuffer(const CellSize(6, 3))
        ..writeImage(const CellOffset(1, 0), bytes, width: 2, height: 2);

      final plan = buildRemotePlan(prev, next, fullRepaint: false);

      expect(plan.patches, isEmpty, reason: 'nothing changed in the grid');
      expect(plan.placements.length, 1,
          reason: 'placement persists every frame so the <img> is not dropped');
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

    test('a non-default fit round-trips through the plan wire', () {
      final next = CellBuffer(const CellSize(6, 3));
      next.writeImage(const CellOffset(0, 0),
          Uint8List.fromList([9, 8, 7, 6]),
          width: 3, height: 2, fit: InlineImageFit.cover);
      final plan = buildRemotePlan(
          CellBuffer(const CellSize(6, 3)), next, fullRepaint: true);

      // The scanned placement carries the image's fit...
      expect(plan.placements.single.fit, InlineImageFit.cover);
      // ...and it survives encode → decode (default would be contain).
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.placements.single.fit, InlineImageFit.cover);
    });

    test('an out-of-range fit index decodes to contain (forward-compat)', () {
      // A future sender could ship a fit ordinal this build doesn't know;
      // the decoder must not throw — it falls back to the safe default.
      final next = CellBuffer(const CellSize(6, 3))
        ..writeImage(const CellOffset(0, 0), Uint8List.fromList([1, 2, 3, 4]),
            width: 2, height: 2);
      final bytes = encodeRemotePlan(
          buildRemotePlan(CellBuffer(const CellSize(6, 3)), next, fullRepaint: true));
      // The final byte is the single placement's fit ordinal (0 = contain);
      // bump it past the known range and confirm graceful fallback.
      final tampered = Uint8List.fromList(bytes)..last = 0x7F;
      expect(decodeRemotePlan(tampered).placements.single.fit,
          InlineImageFit.contain);
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
