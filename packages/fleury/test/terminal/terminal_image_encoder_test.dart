// TerminalImageEncoder contract: placements in a CellBuffer → protocol
// escapes, diffed frame-over-frame. These tests own the byte-level
// assertions the old per-protocol widget tests carried (header fields,
// chunking, geometry) plus the lifecycle the presenter-owned model adds
// (kitty placement deletes, data frees, repaint resets).

import 'dart:convert';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_image_encoder.dart';
import 'package:test/test.dart';

/// A buffer with one image placed over [cols]×[rows] at [col],[row].
CellBuffer bufferWith({
  required Uint8List bytes,
  int col = 0,
  int row = 0,
  int cols = 4,
  int rows = 2,
  InlineImageFit fit = InlineImageFit.fill,
  int? sourceWidth = 8,
  int? sourceHeight = 8,
  Uint8List Function()? pixels,
  Uint8List Function(int x, int y, int width, int height)? croppedBytes,
  CellSize size = const CellSize(20, 10),
}) {
  final buf = CellBuffer(size);
  buf.writeImage(
    CellOffset(col, row),
    bytes,
    width: cols,
    height: rows,
    fit: fit,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    pixels: pixels,
    croppedBytes: croppedBytes,
  );
  return buf;
}

final png = Uint8List.fromList(List<int>.generate(64, (i) => i * 3 & 0xFF));

void main() {
  group('kitty', () {
    TerminalImageEncoder encoder() =>
        TerminalImageEncoder(protocol: ImageProtocol.kitty);

    test('first frame transmits (a=t, f=100) then places (a=p, C=1)', () {
      final out = encoder().encodeFrame(
        bufferWith(bytes: png, col: 1, row: 1, cols: 4, rows: 2),
        fullRepaint: true,
      );
      expect(out, contains('a=t,f=100,i=1'));
      expect(out, contains('a=p,i=1,p=1,c=4,r=2'));
      expect(out, contains('C=1'), reason: 'placement must not move cursor');
      expect(
        out,
        contains('\x1B[2;2H\x1B_Ga=p'),
        reason: 'cursor moves to the placement anchor before a=p',
      );
      expect(out, contains('q=2'), reason: 'terminal responses suppressed');
      expect(out.endsWith('\x1B\\'), isTrue);
    });

    test('payloads over 4KiB chunk with m=1 continuations, one m=0', () {
      final big = Uint8List.fromList(
        List<int>.generate(9000, (i) => (i * 31) & 0xFF),
      );
      final out = encoder().encodeFrame(
        bufferWith(bytes: big),
        fullRepaint: true,
      );
      final continuations = 'm=1'.allMatches(out).length;
      final finals = 'm=0'.allMatches(out).length;
      expect(continuations, greaterThanOrEqualTo(1));
      expect(finals, 1);
    });

    test('an unchanged frame costs zero bytes', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      final second = e.encodeFrame(bufferWith(bytes: png), fullRepaint: false);
      expect(second, isEmpty);
    });

    test('cover emits the protocol source-crop keys (x,y,w,h)', () {
      // 16×4 source covering a 6×6 box → centered 2×4 px crop at x=7.
      final buf = bufferWith(
        bytes: png,
        cols: 6,
        rows: 6,
        fit: InlineImageFit.cover,
        sourceWidth: 16,
        sourceHeight: 4,
      );
      final out = encoder().encodeFrame(buf, fullRepaint: true);
      expect(out, contains('x=7,y=0,w=2,h=4'));
      expect(out, contains('c=6,r=6'));
    });

    test('contain places the centered sub-rect, no crop keys', () {
      // 4:1 source in an 8×8 box → 8×1 band, vertically centered.
      final buf = bufferWith(
        bytes: png,
        cols: 8,
        rows: 8,
        fit: InlineImageFit.contain,
        sourceWidth: 16,
        sourceHeight: 4,
      );
      final out = encoder().encodeFrame(buf, fullRepaint: true);
      expect(out, contains('c=8,r=1'));
      expect(out, isNot(contains('x=')));
      expect(
        out,
        contains('\x1B[5;1H\x1B_Ga=p'),
        reason: 'anchor at the centered band row (row 4, 1-based 5)',
      );
    });

    test('a clipped placement keeps original fit geometry and source crop', () {
      // An 80px-wide fill in an 8-column box is clipped by two columns on
      // the left. The visible 6 columns must show source x=20..80, not a
      // freshly-rescaled copy of the whole source.
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          col: -2,
          cols: 8,
          rows: 4,
          fit: InlineImageFit.fill,
          sourceWidth: 80,
          sourceHeight: 40,
        ),
        fullRepaint: true,
      );
      expect(out, contains('c=6,r=4'));
      expect(out, contains('x=20,y=0,w=60,h=40'));
      expect(out, contains('\x1B[1;1H'));
    });

    test('a clipped window containing only a letterbox emits no image', () {
      // The 4:1 source resolves to a one-row band at original row 4. A
      // four-row viewport showing original rows 0..3 contains only blank
      // letterbox space.
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          cols: 8,
          rows: 8,
          fit: InlineImageFit.contain,
          sourceWidth: 16,
          sourceHeight: 4,
          size: const CellSize(8, 4),
        ),
        fullRepaint: true,
      );
      expect(out, isEmpty);
    });

    test('a moved image deletes the old placement and places anew '
        '(no transmit — the terminal holds the data)', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png, col: 0), fullRepaint: true);
      final out = e.encodeFrame(
        bufferWith(bytes: png, col: 5),
        fullRepaint: false,
      );
      expect(out, contains('a=d,d=i,i=1,p=1'));
      expect(out, contains('a=p,i=1,p=2'));
      expect(out, isNot(contains('a=t')), reason: 'content already resident');
      expect(
        out,
        isNot(contains('d=I')),
        reason: 'content still referenced — data stays resident',
      );
    });

    test('a removed image deletes its placement and frees its data', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      final out = e.encodeFrame(
        CellBuffer(const CellSize(20, 10)),
        fullRepaint: false,
      );
      expect(out, contains('a=d,d=i,i=1,p=1'));
      expect(out, contains('a=d,d=I,i=1'));
    });

    test('an animation frame (content swap in place) transmits the new '
        'frame, places it, and frees the old one', () {
      final e = encoder();
      final frame2 = Uint8List.fromList([9, 9, 9, 9]);
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      final out = e.encodeFrame(bufferWith(bytes: frame2), fullRepaint: false);
      expect(out, contains('a=t,f=100,i=2'));
      expect(out, contains('a=p,i=2'));
      expect(out, contains('a=d,d=i,i=1'), reason: 'old placement deleted');
      expect(out, contains('a=d,d=I,i=1'), reason: 'old frame data freed');
    });

    test('a full repaint clears placements and retransmits what remains', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      final out = e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      expect(
        out,
        contains('a=d,d=A'),
        reason: 'delete-all placements and stored data on repaint reset',
      );
      expect(
        out,
        contains('a=t,f=100,i=1'),
        reason: 'data conservatively retransmitted after a clear',
      );
      expect(out, contains('a=p,i=1'));
    });

    test('same content at two spots transmits once, places twice', () {
      final buf = CellBuffer(const CellSize(20, 10));
      buf.writeImage(const CellOffset(0, 0), png, width: 2, height: 1);
      buf.writeImage(const CellOffset(5, 0), png, width: 2, height: 1);
      final out = encoder().encodeFrame(buf, fullRepaint: true);
      expect('a=t'.allMatches(out).length, 1);
      expect('a=p'.allMatches(out).length, 2);
      expect(out, contains('z=0'));
      expect(out, contains('z=1'));
    });

    test('duplicate same-content placements get distinct z layers', () {
      final buf = CellBuffer(const CellSize(8, 4));
      buf.writeImage(const CellOffset(0, 0), png, width: 4, height: 2);
      buf.writeImage(const CellOffset(0, 0), png, width: 4, height: 2);
      final out = encoder().encodeFrame(buf, fullRepaint: true);
      expect('a=t'.allMatches(out), hasLength(1));
      expect(out, contains('a=p,i=1,p=1,c=4,r=2,z=0'));
      expect(out, contains('a=p,i=1,p=2,c=4,r=2,z=1'));
    });

    test('a large stable duplicate-content stack stays zero-byte', () {
      const placementCount = 256;
      CellBuffer frame() {
        final buffer = CellBuffer(const CellSize(8, 4));
        for (var i = 0; i < placementCount; i++) {
          buffer.writeImage(const CellOffset(0, 0), png, width: 4, height: 2);
        }
        return buffer;
      }

      final e = encoder();
      final first = e.encodeFrame(frame(), fullRepaint: true);
      expect('a=t'.allMatches(first), hasLength(1));
      expect('a=p'.allMatches(first), hasLength(placementCount));
      expect(
        e.encodeFrame(frame(), fullRepaint: false),
        isEmpty,
        reason: 'stable reconciliation must preserve all live placement ids',
      );
    });

    test(
      'paint-order changes replace placements with authoritative z order',
      () {
        final first = Uint8List.fromList([1, 2, 3, 4]);
        final second = Uint8List.fromList([5, 6, 7, 8]);

        CellBuffer stack(Uint8List bottom, Uint8List top) {
          final buffer = CellBuffer(const CellSize(8, 4));
          buffer.writeImage(
            const CellOffset(0, 0),
            bottom,
            width: 4,
            height: 2,
          );
          buffer.writeImage(const CellOffset(0, 0), top, width: 4, height: 2);
          return buffer;
        }

        final e = encoder();
        final initial = e.encodeFrame(stack(first, second), fullRepaint: true);
        expect(initial, contains('a=p,i=1,p=1,c=4,r=2,z=0'));
        expect(initial, contains('a=p,i=2,p=2,c=4,r=2,z=1'));

        final reordered = e.encodeFrame(
          stack(second, first),
          fullRepaint: false,
        );
        expect(reordered, contains('a=d,d=i,i=1,p=1'));
        expect(reordered, contains('a=d,d=i,i=2,p=2'));
        expect(reordered, isNot(contains('a=t')));
        final newBottom = reordered.indexOf('a=p,i=2,p=3,c=4,r=2,z=0');
        final newTop = reordered.indexOf('a=p,i=1,p=4,c=4,r=2,z=1');
        expect(newBottom, greaterThanOrEqualTo(0));
        expect(newTop, greaterThan(newBottom));
      },
    );

    test('full-repaint removal releases the content-to-id mapping', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      final cleared = e.encodeFrame(
        CellBuffer(const CellSize(20, 10)),
        fullRepaint: true,
      );
      expect(cleared, contains('a=d,d=A'));

      final returned = e.encodeFrame(
        bufferWith(bytes: png),
        fullRepaint: false,
      );
      expect(returned, contains('a=t,f=100,i=2'));
      expect(returned, contains('a=p,i=2'));
    });

    test('unknown source dimensions fall back to whole-box fill geometry', () {
      final buf = bufferWith(
        bytes: png,
        cols: 5,
        rows: 3,
        fit: InlineImageFit.contain,
        sourceWidth: null,
        sourceHeight: null,
      );
      final out = encoder().encodeFrame(buf, fullRepaint: true);
      expect(out, contains('c=5,r=3'));
      expect(out, isNot(contains('x=')));
    });
  });

  group('iTerm2', () {
    TerminalImageEncoder encoder() =>
        TerminalImageEncoder(protocol: ImageProtocol.iterm2);

    test('emits OSC 1337 with cell dimensions and pAR=0 at the anchor', () {
      final out = encoder().encodeFrame(
        bufferWith(bytes: png, col: 2, row: 1, cols: 4, rows: 2),
        fullRepaint: true,
      );
      expect(out, contains('\x1B[2;3H'));
      expect(out, contains('\x1B]1337;File=inline=1;size=${png.length};'));
      expect(out, contains('width=4;height=2;preserveAspectRatio=0:'));
      expect(out.endsWith('\x07'), isTrue, reason: 'BEL-terminated OSC');
    });

    test('contain letterboxes into the centered sub-rect', () {
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          cols: 8,
          rows: 8,
          fit: InlineImageFit.contain,
          sourceWidth: 16,
          sourceHeight: 4,
        ),
        fullRepaint: true,
      );
      expect(out, contains('width=8;height=1'));
      expect(out, contains('\x1B[5;1H'), reason: 'centered band row');
    });

    test('cover degrades to contain (no source crop in the protocol)', () {
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          cols: 8,
          rows: 8,
          fit: InlineImageFit.cover,
          sourceWidth: 16,
          sourceHeight: 4,
        ),
        fullRepaint: true,
      );
      // Exact cover needs a source crop iTerm2 cannot express; the
      // encoder falls back to aspect-true contain geometry rather than
      // distorting.
      expect(out, contains('width=8;height=1'));
    });

    test('a lazy cropped PNG makes cover exact and stays lazy when stable', () {
      final calls = <(int, int, int, int)>[];
      final cropped = Uint8List.fromList([201, 202, 203]);
      Uint8List crop(int x, int y, int width, int height) {
        calls.add((x, y, width, height));
        return cropped;
      }

      final e = encoder();
      final first = e.encodeFrame(
        bufferWith(
          bytes: png,
          cols: 8,
          rows: 8,
          fit: InlineImageFit.cover,
          sourceWidth: 16,
          sourceHeight: 4,
          croppedBytes: crop,
        ),
        fullRepaint: true,
      );
      expect(calls, [(7, 0, 2, 4)]);
      expect(first, contains('size=${cropped.length};width=8;height=8'));
      expect(first, contains(base64.encode(cropped)));

      final stable = e.encodeFrame(
        bufferWith(
          bytes: png,
          cols: 8,
          rows: 8,
          fit: InlineImageFit.cover,
          sourceWidth: 16,
          sourceHeight: 4,
          croppedBytes: crop,
        ),
        fullRepaint: false,
      );
      expect(stable, isEmpty);
      expect(calls, hasLength(1), reason: 'stable frames do not encode crops');
    });

    test('partial clipping requests only the visible source window', () {
      final calls = <(int, int, int, int)>[];
      final cropped = Uint8List.fromList([91, 92]);
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          col: -2,
          cols: 8,
          rows: 2,
          fit: InlineImageFit.fill,
          sourceWidth: 8,
          sourceHeight: 2,
          croppedBytes: (x, y, width, height) {
            calls.add((x, y, width, height));
            return cropped;
          },
        ),
        fullRepaint: true,
      );
      expect(calls, [(2, 0, 6, 2)]);
      expect(out, contains('width=6;height=2'));
      expect(out, contains(base64.encode(cropped)));
    });

    test('a full-source placement preserves original bytes and skips crop', () {
      var calls = 0;
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          fit: InlineImageFit.fill,
          croppedBytes: (x, y, width, height) {
            calls++;
            return Uint8List(0);
          },
        ),
        fullRepaint: true,
      );
      expect(calls, 0);
      expect(out, contains('size=${png.length};'));
      expect(out, contains(base64.encode(png)));
    });

    test('an unchanged frame costs zero bytes; removal costs zero bytes '
        '(the text diff clears the cells)', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      expect(
        e.encodeFrame(bufferWith(bytes: png), fullRepaint: false),
        isEmpty,
      );
      expect(
        e.encodeFrame(CellBuffer(const CellSize(20, 10)), fullRepaint: false),
        isEmpty,
      );
    });

    test('a moved image re-emits at the new anchor', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png, col: 0), fullRepaint: true);
      final out = e.encodeFrame(
        bufferWith(bytes: png, col: 6),
        fullRepaint: false,
      );
      expect(out, contains('\x1B[1;7H'));
      expect(out, contains('1337'));
    });

    test('a disjoint addition emits only the new placement', () {
      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6]);
      final initial = CellBuffer(const CellSize(12, 4))
        ..writeImage(const CellOffset(0, 0), first, width: 2, height: 1);
      final next = CellBuffer(const CellSize(12, 4))
        ..writeImage(const CellOffset(0, 0), first, width: 2, height: 1)
        ..writeImage(const CellOffset(6, 0), second, width: 2, height: 1);
      final e = encoder();
      e.encodeFrame(initial, fullRepaint: true);
      final out = e.encodeFrame(next, fullRepaint: false);
      expect('1337'.allMatches(out), hasLength(1));
      expect(out, contains(base64.encode(second)));
      expect(out, isNot(contains(base64.encode(first))));
      expect(out, isNot(contains('\x1B[0m')), reason: 'no overlap to clear');
    });

    test('duplicate occurrence matching preserves both stable rasters', () {
      final added = Uint8List.fromList([4, 5, 6]);
      CellBuffer frame({required bool includeAddition}) {
        final buffer = CellBuffer(const CellSize(12, 4));
        buffer.writeImage(const CellOffset(0, 0), png, width: 2, height: 1);
        buffer.writeImage(const CellOffset(0, 0), png, width: 2, height: 1);
        if (includeAddition) {
          buffer.writeImage(const CellOffset(6, 0), added, width: 2, height: 1);
        }
        return buffer;
      }

      final e = encoder();
      e.encodeFrame(frame(includeAddition: false), fullRepaint: true);
      final out = e.encodeFrame(
        frame(includeAddition: true),
        fullRepaint: false,
      );
      expect('1337'.allMatches(out), hasLength(1));
      expect(out, contains(base64.encode(added)));
      expect(out, isNot(contains(base64.encode(png))));
      expect(out, isNot(contains('\x1B[0m')), reason: 'duplicates survived');
    });

    test('a disjoint move emits only the new placement', () {
      final first = CellBuffer(const CellSize(12, 4))
        ..writeImage(const CellOffset(0, 0), png, width: 2, height: 1);
      final moved = CellBuffer(const CellSize(12, 4))
        ..writeImage(const CellOffset(6, 0), png, width: 2, height: 1);
      final e = encoder();
      e.encodeFrame(first, fullRepaint: true);
      final out = e.encodeFrame(moved, fullRepaint: false);
      expect('1337'.allMatches(out), hasLength(1));
      expect(out, contains('\x1B[1;7H'));
      expect(out, isNot(contains('\x1B[0m')), reason: 'no overlap to clear');
    });

    test('reordering adjacent placements emits no image bytes', () {
      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6]);
      CellBuffer adjacent({required bool reversed}) {
        final buffer = CellBuffer(const CellSize(8, 4));
        void paintFirst() => buffer.writeImage(
          const CellOffset(0, 0),
          first,
          width: 2,
          height: 1,
        );
        void paintSecond() => buffer.writeImage(
          const CellOffset(2, 0),
          second,
          width: 2,
          height: 1,
        );
        if (reversed) {
          paintSecond();
          paintFirst();
        } else {
          paintFirst();
          paintSecond();
        }
        return buffer;
      }

      final e = encoder();
      e.encodeFrame(adjacent(reversed: false), fullRepaint: true);
      expect(
        e.encodeFrame(adjacent(reversed: true), fullRepaint: false),
        isEmpty,
      );
      expect(
        e.encodeFrame(adjacent(reversed: false), fullRepaint: false),
        isEmpty,
        reason: 'the zero-byte reorder still updates logical paint order',
      );
    });

    test('an in-place replacement clears stale pixels before replay', () {
      final e = encoder();
      e.encodeFrame(bufferWith(bytes: png), fullRepaint: true);
      final replacement = Uint8List.fromList([9, 8, 7, 6]);
      final out = e.encodeFrame(
        bufferWith(bytes: replacement),
        fullRepaint: false,
      );
      final clear = out.indexOf('\x1B[0m\x1B[1;1H    ');
      final replay = out.indexOf('\x1B]1337;');
      expect(clear, greaterThanOrEqualTo(0));
      expect(replay, greaterThan(clear));
      expect(out, contains(base64.encode(replacement)));
    });

    test('overlap reordering replays only its connected component', () {
      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6]);
      final isolated = Uint8List.fromList([7, 8, 9]);
      CellBuffer stack(Uint8List bottom, Uint8List top) {
        final buffer = CellBuffer(const CellSize(12, 4));
        buffer.writeImage(const CellOffset(0, 0), bottom, width: 4, height: 2);
        buffer.writeImage(const CellOffset(0, 0), top, width: 4, height: 2);
        buffer.writeImage(
          const CellOffset(8, 0),
          isolated,
          width: 2,
          height: 1,
        );
        return buffer;
      }

      final e = encoder();
      e.encodeFrame(stack(first, second), fullRepaint: true);
      final out = e.encodeFrame(stack(second, first), fullRepaint: false);
      expect(out, contains('\x1B[0m\x1B[1;1H    '));
      expect('1337'.allMatches(out), hasLength(2));
      final bottom = out.indexOf(base64.encode(second));
      final top = out.indexOf(base64.encode(first));
      expect(bottom, greaterThanOrEqualTo(0));
      expect(top, greaterThan(bottom));
      expect(
        out,
        isNot(contains(base64.encode(isolated))),
        reason: 'the non-overlapping survivor must not resend',
      );
    });
  });

  group('sixel', () {
    TerminalImageEncoder encoder() =>
        TerminalImageEncoder(protocol: ImageProtocol.sixel);

    Uint8List redBluePixels() {
      // 2×2: red, red / blue, blue.
      return Uint8List.fromList([
        255, 0, 0, 255, 255, 0, 0, 255, //
        0, 0, 255, 255, 0, 0, 255, 255,
      ]);
    }

    test('rasterizes the RGBA sidecar into a DCS sixel stream', () {
      final out = encoder().encodeFrame(
        bufferWith(
          bytes: png,
          cols: 2,
          rows: 1,
          sourceWidth: 2,
          sourceHeight: 2,
          pixels: redBluePixels,
        ),
        fullRepaint: true,
      );
      expect(out, contains('\x1BPq'), reason: 'DCS sixel introducer');
      // fill of a 2×1 cell box at 10×20 px/cell → 20×20 raster.
      expect(out, contains('"1;1;20;20'), reason: 'raster attributes');
      expect(out, contains('#0;2;'), reason: 'palette definition');
      expect(out.endsWith('\x1B\\'), isTrue, reason: 'ST terminator');
    });

    test('a placement without the pixels sidecar is skipped', () {
      final out = encoder().encodeFrame(
        bufferWith(bytes: png, pixels: null),
        fullRepaint: true,
      );
      expect(out, isEmpty);
    });

    test('an unchanged frame costs zero bytes', () {
      final e = encoder();
      final buf1 = bufferWith(
        bytes: png,
        sourceWidth: 2,
        sourceHeight: 2,
        pixels: redBluePixels,
      );
      e.encodeFrame(buf1, fullRepaint: true);
      final buf2 = bufferWith(
        bytes: png,
        sourceWidth: 2,
        sourceHeight: 2,
        pixels: redBluePixels,
      );
      expect(e.encodeFrame(buf2, fullRepaint: false), isEmpty);
    });

    test('partial clipping samples only the visible source window', () {
      // Four horizontal source pixels: red, green, blue, white. Clipping two
      // columns from the left must leave only blue and white in the palette.
      final source = Uint8List.fromList([
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
      ]);
      final out =
          TerminalImageEncoder(
            protocol: ImageProtocol.sixel,
            cellPixelWidth: 1,
            cellPixelHeight: 1,
          ).encodeFrame(
            bufferWith(
              bytes: png,
              col: -2,
              cols: 4,
              rows: 1,
              fit: InlineImageFit.fill,
              sourceWidth: 4,
              sourceHeight: 1,
              pixels: () => source,
            ),
            fullRepaint: true,
          );
      expect(out, contains('"1;1;2;1'));
      expect(out, contains(';2;0;0;100'));
      expect(out, contains(';2;100;100;100'));
      expect(out, isNot(contains(';2;100;0;0')));
      expect(out, isNot(contains(';2;0;100;0')));
    });

    test('an in-place replacement clears stale pixels before replay', () {
      final e = TerminalImageEncoder(
        protocol: ImageProtocol.sixel,
        cellPixelWidth: 1,
        cellPixelHeight: 1,
      );
      final first = bufferWith(
        bytes: Uint8List.fromList([1]),
        cols: 2,
        rows: 1,
        sourceWidth: 2,
        sourceHeight: 1,
        pixels: () => Uint8List.fromList([255, 0, 0, 255, 255, 0, 0, 255]),
      );
      final second = bufferWith(
        bytes: Uint8List.fromList([2]),
        cols: 2,
        rows: 1,
        sourceWidth: 2,
        sourceHeight: 1,
        pixels: () => Uint8List.fromList([0, 0, 255, 255, 0, 0, 255, 255]),
      );
      e.encodeFrame(first, fullRepaint: true);
      final out = e.encodeFrame(second, fullRepaint: false);
      final clear = out.indexOf('\x1B[0m\x1B[1;1H  ');
      final replay = out.indexOf('\x1BPq');
      expect(clear, greaterThanOrEqualTo(0));
      expect(replay, greaterThan(clear));
      expect(out, contains(';2;0;0;100'));
    });

    test('a non-overlapping addition preserves the existing raster', () {
      final red = Uint8List.fromList([255, 0, 0, 255]);
      final blue = Uint8List.fromList([0, 0, 255, 255]);
      CellBuffer frame({required bool includeBlue}) {
        final buffer = CellBuffer(const CellSize(8, 2));
        buffer.writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1]),
          width: 1,
          height: 1,
          fit: InlineImageFit.fill,
          sourceWidth: 1,
          sourceHeight: 1,
          pixels: () => red,
        );
        if (includeBlue) {
          buffer.writeImage(
            const CellOffset(4, 0),
            Uint8List.fromList([2]),
            width: 1,
            height: 1,
            fit: InlineImageFit.fill,
            sourceWidth: 1,
            sourceHeight: 1,
            pixels: () => blue,
          );
        }
        return buffer;
      }

      final e = TerminalImageEncoder(
        protocol: ImageProtocol.sixel,
        cellPixelWidth: 1,
        cellPixelHeight: 1,
      );
      e.encodeFrame(frame(includeBlue: false), fullRepaint: true);
      final out = e.encodeFrame(frame(includeBlue: true), fullRepaint: false);
      expect('\x1BPq'.allMatches(out), hasLength(1));
      expect(out, contains(';2;0;0;100'));
      expect(out, isNot(contains(';2;100;0;0')));
      expect(out, isNot(contains('\x1B[0m')), reason: 'no overlap to clear');
    });

    test('reordering adjacent rasters emits zero bytes', () {
      final red = Uint8List.fromList([255, 0, 0, 255]);
      final blue = Uint8List.fromList([0, 0, 255, 255]);
      CellBuffer adjacent({required bool reversed}) {
        final buffer = CellBuffer(const CellSize(4, 2));
        void paint(int col, int id, Uint8List pixels) => buffer.writeImage(
          CellOffset(col, 0),
          Uint8List.fromList([id]),
          width: 1,
          height: 1,
          fit: InlineImageFit.fill,
          sourceWidth: 1,
          sourceHeight: 1,
          pixels: () => pixels,
        );
        if (reversed) {
          paint(1, 2, blue);
          paint(0, 1, red);
        } else {
          paint(0, 1, red);
          paint(1, 2, blue);
        }
        return buffer;
      }

      final e = TerminalImageEncoder(
        protocol: ImageProtocol.sixel,
        cellPixelWidth: 1,
        cellPixelHeight: 1,
      );
      e.encodeFrame(adjacent(reversed: false), fullRepaint: true);
      expect(
        e.encodeFrame(adjacent(reversed: true), fullRepaint: false),
        isEmpty,
      );
    });

    test('encodeSixel output is deterministic and RLE-compressed', () {
      final rgba = Uint8List(16 * 6 * 4);
      for (var i = 0; i < 16 * 6; i++) {
        rgba[i * 4] = 200; // solid-ish red
        rgba[i * 4 + 3] = 255;
      }
      final a = encodeSixel(rgba, 16, 6);
      final b = encodeSixel(rgba, 16, 6);
      expect(a, b);
      expect(
        a,
        contains('!16'),
        reason: 'a 16-column solid band RLE-compresses to one !16 run',
      );
    });

    test('quantization caps the palette at 128 colors', () {
      // 512 distinct colors in a 32×16 raster.
      const w = 32, h = 16;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = (i * 7) & 0xFF;
        rgba[i * 4 + 1] = (i * 13) & 0xFF;
        rgba[i * 4 + 2] = (i * 29) & 0xFF;
        rgba[i * 4 + 3] = 255;
      }
      final out = encodeSixel(rgba, w, h);
      final paletteDefs = RegExp(
        '#(\\d+);2;',
      ).allMatches(out).map((m) => int.parse(m.group(1)!)).toSet();
      expect(paletteDefs.length, lessThanOrEqualTo(128));
    });
  });

  group('tmux passthrough', () {
    test('escapes are wrapped and ESC-doubled; cursor moves stay outside', () {
      final out = TerminalImageEncoder(
        protocol: ImageProtocol.kitty,
        tmuxPassthrough: true,
      ).encodeFrame(bufferWith(bytes: png, col: 1, row: 1), fullRepaint: true);
      expect(out, contains('\x1BPtmux;'));
      expect(
        out,
        contains('\x1B\x1B_G'),
        reason: 'embedded ESC doubled inside the envelope',
      );
      expect(
        out,
        contains('H\x1BPtmux;'),
        reason:
            'the CUP ends (H) right before the envelope opens — cursor '
            'moves must stay visible to tmux',
      );
    });

    test('a large kitty transmit gets one passthrough envelope per chunk', () {
      // >4 KiB of incompressible base64 forces multiple transmit chunks.
      // Under tmux each MUST get its own envelope, or tmux drops the
      // oversized single one and the image never arrives.
      final noisy = Uint8List.fromList(
        List<int>.generate(9000, (i) => (i * 31 + 7) & 0xFF),
      );
      final out = TerminalImageEncoder(
        protocol: ImageProtocol.kitty,
        tmuxPassthrough: true,
      ).encodeFrame(bufferWith(bytes: noisy), fullRepaint: true);

      final envelopes = '\x1BPtmux;'.allMatches(out).length;
      final chunks = 'm=1'.allMatches(out).length; // continuation chunks
      expect(chunks, greaterThanOrEqualTo(1), reason: 'multi-chunk transmit');
      expect(
        envelopes,
        greaterThan(chunks),
        reason:
            'every transmit chunk (plus the a=p placement) is its own '
            'envelope — not one envelope around the whole stream',
      );
    });
  });

  group('presenter integration', () {
    test('the encoder is inert for a frame with no images', () {
      final e = TerminalImageEncoder(protocol: ImageProtocol.kitty);
      expect(
        e.encodeFrame(CellBuffer(const CellSize(10, 4)), fullRepaint: true),
        isEmpty,
      );
    });
  });

  group('zero-image fast path', () {
    const empty = CellSize(20, 10);

    test('an image-free session stays inert across steady frames', () {
      // The encoder exists whenever the terminal has a protocol, so an
      // image-free app still calls encodeFrame every frame. The first
      // (full-repaint) frame and every steady frame after it emit nothing.
      final e = TerminalImageEncoder(protocol: ImageProtocol.kitty);
      expect(e.encodeFrame(CellBuffer(empty), fullRepaint: true), isEmpty);
      expect(e.encodeFrame(CellBuffer(empty), fullRepaint: false), isEmpty);
      expect(e.encodeFrame(CellBuffer(empty), fullRepaint: false), isEmpty);
    });

    test('the fast path does not strand a later image', () {
      // Skipping empty frames must not corrupt state: an image appearing
      // after image-free frames still transmits and places normally.
      final e = TerminalImageEncoder(protocol: ImageProtocol.kitty);
      e.encodeFrame(CellBuffer(empty), fullRepaint: true);
      e.encodeFrame(CellBuffer(empty), fullRepaint: false);
      final out = e.encodeFrame(bufferWith(bytes: png), fullRepaint: false);
      expect(out, contains('a=t,f=100,i=1'), reason: 'transmits the new image');
      expect(out, contains('a=p,i=1,p=1'), reason: 'and places it');
    });

    test('iTerm2: empty frames after a placement go inert', () {
      // Exercises the _emittedKeys arm of the guard: the first empty frame
      // clears the emitted keys (the region is repainted by the text diff),
      // and the next one takes the fast path.
      final e = TerminalImageEncoder(protocol: ImageProtocol.iterm2);
      expect(
        e.encodeFrame(bufferWith(bytes: png), fullRepaint: true),
        isNotEmpty,
      );
      e.encodeFrame(CellBuffer(empty), fullRepaint: false);
      expect(e.encodeFrame(CellBuffer(empty), fullRepaint: false), isEmpty);
    });
  });
}
