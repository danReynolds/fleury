// TerminalImageEncoder contract: placements in a CellBuffer → protocol
// escapes, diffed frame-over-frame. These tests own the byte-level
// assertions the old per-protocol widget tests carried (header fields,
// chunking, geometry) plus the lifecycle the presenter-owned model adds
// (kitty placement deletes, data frees, repaint resets).

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
        contains('a=d,d=a'),
        reason: 'delete-all placements on repaint (belt and braces vs ED)',
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
}
