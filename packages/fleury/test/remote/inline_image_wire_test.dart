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
      final gridText = plan.patches
          .expand((pp) => pp.runs)
          .map((r) => r.text)
          .join();
      expect(
        gridText.contains(p.id),
        isFalse,
        reason: 'image region is blanked; bytes travel out of band',
      );
    });

    test('wire placement geometry is clipped to the declared grid', () {
      final prev = CellBuffer(const CellSize(4, 3));
      final next = CellBuffer(const CellSize(4, 3))
        ..writeImage(
          const CellOffset(3, 2),
          Uint8List.fromList([1, 2, 3]),
          width: 20,
          height: 20,
        );

      final plan = buildRemotePlan(prev, next, fullRepaint: true);
      final placement = plan.placements.single;
      expect(
        [placement.col, placement.row, placement.cols, placement.rows],
        [3, 2, 1, 1],
      );
      expect(
        [
          placement.boxCols,
          placement.boxRows,
          placement.boxOffsetCol,
          placement.boxOffsetRow,
        ],
        [20, 20, 0, 0],
      );
      final decoded = decodeRemotePlan(
        encodeRemotePlan(plan),
      ).placements.single;
      expect(
        [
          decoded.cols,
          decoded.rows,
          decoded.boxCols,
          decoded.boxRows,
          decoded.boxOffsetCol,
          decoded.boxOffsetRow,
        ],
        [1, 1, 20, 20, 0, 0],
      );
    });

    test('an image box beyond the remote geometry cap degrades to blank', () {
      final next = CellBuffer(const CellSize(4, 3))
        ..writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3]),
          width: maxRemotePlanGridCols + 1,
          height: 1,
        );

      final plan = buildRemotePlan(
        CellBuffer(const CellSize(4, 3)),
        next,
        fullRepaint: true,
      );

      expect(plan.placements, isEmpty);
      expect(() => decodeRemotePlan(encodeRemotePlan(plan)), returnsNormally);
    });

    test('two distinct images on one frame yield two placements', () {
      final next = CellBuffer(const CellSize(12, 4))
        ..writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1, 1, 1, 1]),
          width: 2,
          height: 2,
        )
        ..writeImage(
          const CellOffset(6, 0),
          Uint8List.fromList([2, 2, 2, 2]),
          width: 3,
          height: 2,
        );

      final plan = buildRemotePlan(
        CellBuffer(const CellSize(12, 4)),
        next,
        fullRepaint: true,
      );

      expect(plan.placements.length, 2);
      expect(
        plan.placements.map((p) => p.id).toSet().length,
        2,
        reason: 'distinct bytes → distinct ids',
      );
      // Round-trips both.
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.placements.map((p) => '${p.col}:${p.cols}').toSet(), {
        '0:2',
        '6:3',
      });
    });

    test('a static (unchanged) image still emits its placement', () {
      final bytes = Uint8List.fromList([5, 6, 7, 8]);
      final prev = CellBuffer(const CellSize(6, 3))
        ..writeImage(const CellOffset(1, 0), bytes, width: 2, height: 2);
      final next = CellBuffer(const CellSize(6, 3))
        ..writeImage(const CellOffset(1, 0), bytes, width: 2, height: 2);

      final plan = buildRemotePlan(prev, next, fullRepaint: false);

      expect(plan.patches, isEmpty, reason: 'nothing changed in the grid');
      expect(
        plan.placements.length,
        1,
        reason: 'placement persists every frame so the <img> is not dropped',
      );
    });

    test('placements round-trip through the plan wire', () {
      final next = CellBuffer(const CellSize(6, 3));
      next.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1, 2, 3, 4]),
        width: 2,
        height: 2,
      );
      final plan = buildRemotePlan(
        CellBuffer(const CellSize(6, 3)),
        next,
        fullRepaint: true,
      );

      final decoded = decodeRemotePlan(encodeRemotePlan(plan));

      expect(decoded.placements.length, 1);
      final p = decoded.placements.single;
      final original = plan.placements.single;
      expect([p.id, p.col, p.row, p.cols, p.rows], [original.id, 0, 0, 2, 2]);
      expect(
        [p.boxCols, p.boxRows, p.boxOffsetCol, p.boxOffsetRow],
        [2, 2, 0, 0],
      );
    });

    test('v5 placement windows round-trip without losing original fit box', () {
      const plan = RemotePlan(
        size: CellSize(10, 6),
        fullRepaint: false,
        styleTable: [],
        patches: [],
        placements: [
          ImagePlacement(
            id: 'clipped',
            col: 0,
            row: 1,
            cols: 3,
            rows: 2,
            fit: InlineImageFit.cover,
            boxCols: 7,
            boxRows: 5,
            boxOffsetCol: 2,
            boxOffsetRow: 1,
          ),
        ],
      );

      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      final placement = decoded.placements.single;
      expect(decoded.includeImageWindows, isTrue);
      expect(
        [
          placement.col,
          placement.row,
          placement.cols,
          placement.rows,
          placement.boxCols,
          placement.boxRows,
          placement.boxOffsetCol,
          placement.boxOffsetRow,
        ],
        [0, 1, 3, 2, 7, 5, 2, 1],
      );
      expect(placement.fit, InlineImageFit.cover);
    });

    test('legacy placement wire defaults the original box to its window', () {
      const plan = RemotePlan(
        size: CellSize(10, 6),
        fullRepaint: false,
        styleTable: [],
        patches: [],
        includeImageWindows: false,
        placements: [
          ImagePlacement(
            id: 'legacy',
            col: 2,
            row: 1,
            cols: 3,
            rows: 2,
            boxCols: 7,
            boxRows: 5,
            boxOffsetCol: 2,
            boxOffsetRow: 1,
          ),
        ],
      );

      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      final placement = decoded.placements.single;
      expect(decoded.includeImageWindows, isFalse);
      expect(
        [
          placement.boxCols,
          placement.boxRows,
          placement.boxOffsetCol,
          placement.boxOffsetRow,
        ],
        [3, 2, 0, 0],
      );
    });

    test('a legacy peer gets blank instead of a mis-fitted clipped image', () {
      final next = CellBuffer(const CellSize(4, 3))
        ..writeImage(
          const CellOffset(3, 2),
          Uint8List.fromList([1, 2, 3]),
          width: 2,
          height: 2,
        );

      final plan = buildRemotePlan(
        CellBuffer(const CellSize(4, 3)),
        next,
        fullRepaint: true,
        includeImageWindows: false,
      );

      expect(plan.placements, isEmpty);
      expect(() => decodeRemotePlan(encodeRemotePlan(plan)), returnsNormally);
    });

    test('a v5 window extending outside its original box is rejected', () {
      const plan = RemotePlan(
        size: CellSize(10, 6),
        fullRepaint: false,
        styleTable: [],
        patches: [],
        placements: [
          ImagePlacement(
            id: 'invalid',
            col: 0,
            row: 0,
            cols: 4,
            rows: 2,
            boxCols: 5,
            boxRows: 2,
            boxOffsetCol: 2,
          ),
        ],
      );

      expect(
        () => decodeRemotePlan(encodeRemotePlan(plan)),
        throwsA(isA<RemoteCodecException>()),
      );
    });

    test('a non-default fit round-trips through the plan wire', () {
      final next = CellBuffer(const CellSize(6, 3));
      next.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([9, 8, 7, 6]),
        width: 3,
        height: 2,
        fit: InlineImageFit.cover,
      );
      final plan = buildRemotePlan(
        CellBuffer(const CellSize(6, 3)),
        next,
        fullRepaint: true,
      );

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
        ..writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1, 2, 3, 4]),
          width: 2,
          height: 2,
        );
      final bytes = encodeRemotePlan(
        buildRemotePlan(
          CellBuffer(const CellSize(6, 3)),
          next,
          fullRepaint: true,
          includeImageWindows: false,
        ),
      );
      // The final byte is the single placement's fit ordinal (0 = contain);
      // bump it past the known range and confirm graceful fallback.
      final tampered = Uint8List.fromList(bytes)..last = 0x7F;
      expect(
        decodeRemotePlan(tampered).placements.single.fit,
        InlineImageFit.contain,
      );
    });

    test('a plan with no images round-trips with empty placements', () {
      final next = CellBuffer(const CellSize(4, 2))
        ..writeText(const CellOffset(0, 0), 'hi');
      final plan = buildRemotePlan(
        CellBuffer(const CellSize(4, 2)),
        next,
        fullRepaint: true,
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.placements, isEmpty);
    });

    test('InlineImageFrame round-trips id + bytes (incl. >256 bytes)', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(257, (i) => (i * 7) % 256),
      );
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
