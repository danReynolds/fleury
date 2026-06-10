import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// Const-friendly 1×2 solid-color image wrapper for tests. Const so
/// we can use it inside `const SizedBox(child: _Image1x2(...))`.
class _Image1x2 extends StatelessWidget {
  const _Image1x2({required this.r, required this.g, required this.b});
  final int r;
  final int g;
  final int b;
  @override
  Widget build(BuildContext context) {
    final image = img.Image(width: 1, height: 2);
    img.fill(image, color: img.ColorRgb8(r, g, b));
    return Image(source: ImageSource.decoded(image), fit: ImageFit.fill);
  }
}

/// Builds a tiny solid-color image: [width] × [height], one RGB color.
img.Image _solid(int width, int height, int r, int g, int b) {
  final i = img.Image(width: width, height: height);
  img.fill(i, color: img.ColorRgb8(r, g, b));
  return i;
}

/// Builds a checkerboard: even rows red, odd rows blue. Used to verify
/// per-cell half-block top/bottom color separation.
img.Image _rowStripes(int width, int height) {
  final i = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    final c = (y % 2 == 0)
        ? img.ColorRgb8(255, 0, 0)
        : img.ColorRgb8(0, 0, 255);
    for (var x = 0; x < width; x++) {
      i.setPixel(x, y, c);
    }
  }
  return i;
}

void main() {
  group('Image — half-block rendering', () {
    testWidgets('a 1×2 solid image fills one cell with ▀', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(1, 2, 100, 150, 200)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      final cell = buf.atColRow(0, 0);
      expect(cell.grapheme, '▀');
      expect(cell.style.foreground, const RgbColor(100, 150, 200));
      expect(cell.style.background, const RgbColor(100, 150, 200));
    });

    testWidgets('a 2-row stripe image puts top-row color in fg, bottom in bg', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_rowStripes(1, 2)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      final cell = buf.atColRow(0, 0);
      expect(cell.grapheme, '▀');
      expect(
        cell.style.foreground,
        const RgbColor(255, 0, 0),
        reason: 'top-row pixel (row 0, red) drives foreground',
      );
      expect(
        cell.style.background,
        const RgbColor(0, 0, 255),
        reason: 'bottom-row pixel (row 1, blue) drives background',
      );
    });

    testWidgets('fit: contain letterboxes a wide image', (tester) {
      // Source 4×2, target 4×4 (which is 4 cells × 8 vertical pixels):
      // contain scales to 4×2 source pixels and centers vertically. Top
      // and bottom rows of the box should be empty (no pixel mapped),
      // middle should be lit.
      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 4,
          child: Image(
            source: ImageSource.decoded(_solid(4, 2, 50, 50, 50)),
            fit: ImageFit.contain,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 4));
      // Top row (row 0): both halves outside the centered image — empty.
      for (var c = 0; c < 4; c++) {
        expect(
          buf.atColRow(c, 0).grapheme,
          isNull,
          reason: 'row 0 letterboxed',
        );
      }
      // Bottom row: also empty.
      for (var c = 0; c < 4; c++) {
        expect(
          buf.atColRow(c, 3).grapheme,
          isNull,
          reason: 'row 3 letterboxed',
        );
      }
    });

    testWidgets('fully-transparent pixels render as empty cells (no glyph)', (
      tester,
    ) {
      // 2-pixel-tall image where both rows are fully transparent.
      // numChannels: 4 → RGBA; otherwise the alpha bit is dropped.
      final image = img.Image(width: 1, height: 2, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(source: ImageSource.decoded(image), fit: ImageFit.fill),
        ),
      );
      final buf = tester.render(size: const CellSize(1, 1));
      expect(
        buf.atColRow(0, 0).grapheme,
        isNull,
        reason: 'transparent image leaves cells empty',
      );
    });

    testWidgets(
      'half-transparent (top opaque, bottom transparent) uses fg only',
      (tester) {
        final image = img.Image(width: 1, height: 2, numChannels: 4);
        image.setPixel(0, 0, img.ColorRgba8(255, 128, 64, 255));
        image.setPixel(0, 1, img.ColorRgba8(0, 0, 0, 0));
        tester.pumpWidget(
          SizedBox(
            width: 1,
            height: 1,
            child: Image(
              source: ImageSource.decoded(image),
              fit: ImageFit.fill,
            ),
          ),
        );
        final buf = tester.render(size: const CellSize(1, 1));
        final cell = buf.atColRow(0, 0);
        expect(cell.grapheme, '▀');
        expect(cell.style.foreground, const RgbColor(255, 128, 64));
        expect(
          cell.style.background,
          isNull,
          reason: 'transparent bottom leaves background absent',
        );
      },
    );
  });

  group('Image — alpha compositing against background', () {
    testWidgets('fully-transparent pixel composites to the bg color', (tester) {
      final image = img.Image(width: 1, height: 2, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(image),
            fit: ImageFit.fill,
            backgroundColor: const RgbColor(50, 100, 150),
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      // Crisp edges against the supplied bg — both halves get the bg
      // color and the cell paints, unlike the null-bg case where it
      // would be empty.
      expect(cell.grapheme, '▀');
      expect(cell.style.foreground, const RgbColor(50, 100, 150));
      expect(cell.style.background, const RgbColor(50, 100, 150));
    });

    testWidgets('50%-alpha pixel composites to (src + bg) / 2', (tester) {
      // Source: pure red at α=128; bg: pure black. Expected composite:
      //   r = (128/255)·255 + (1 − 128/255)·0 ≈ 128
      final image = img.Image(width: 1, height: 2, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(255, 0, 0, 128));
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(image),
            fit: ImageFit.fill,
            backgroundColor: const RgbColor(0, 0, 0),
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      final fg = cell.style.foreground! as RgbColor;
      // Allow ±2 tolerance: alpha math + rounding.
      expect(fg.r, inInclusiveRange(126, 130));
      expect(fg.g, 0);
      expect(fg.b, 0);
    });

    testWidgets('opaque pixels are unaffected by the bg knob', (tester) {
      // Setting backgroundColor on a fully-opaque image must be a
      // no-op — no surprise color drift on regular PNGs.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(1, 2, 200, 100, 50)),
            fit: ImageFit.fill,
            backgroundColor: const RgbColor(0, 255, 0),
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const RgbColor(200, 100, 50));
      expect(cell.style.background, const RgbColor(200, 100, 50));
    });

    testWidgets('semitransparent pixel without bg uses alpha-weighted mean', (
      tester,
    ) {
      // Two side-by-side pixels averaged into one half-cell: one is
      // fully-opaque red, the other is 50%-alpha red. Without a bg the
      // OLD code would average both at full weight (still red). The new
      // alpha-weighted path keeps the same red — there's no other color
      // contributing — but verifies non-null + non-zero output and that
      // we don't accidentally drop the half-transparent pixel.
      final image = img.Image(width: 2, height: 2, numChannels: 4);
      image.setPixel(0, 0, img.ColorRgba8(255, 0, 0, 255));
      image.setPixel(1, 0, img.ColorRgba8(255, 0, 0, 128));
      image.setPixel(0, 1, img.ColorRgba8(255, 0, 0, 255));
      image.setPixel(1, 1, img.ColorRgba8(255, 0, 0, 128));
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(source: ImageSource.decoded(image), fit: ImageFit.fill),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const RgbColor(255, 0, 0));
      expect(cell.style.background, const RgbColor(255, 0, 0));
    });
  });

  group('Image — ImageSource', () {
    test('ImageSource.decoded returns the passed image verbatim', () {
      final image = _solid(2, 2, 10, 20, 30);
      final source = ImageSource.decoded(image);
      expect(identical(source.decode(), image), isTrue);
    });

    test('ImageSource.bytes decodes PNG bytes once and caches', () {
      final png = img.encodePng(_solid(2, 2, 10, 20, 30));
      final source = ImageSource.bytes(png);
      final first = source.decode();
      final second = source.decode();
      expect(
        identical(first, second),
        isTrue,
        reason: 'decoded image is cached',
      );
    });

    test('ImageSource.bytes throws on garbage input', () {
      final source = ImageSource.bytes(
        Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
      );
      expect(source.decode, throwsArgumentError);
    });

    test('ImageSource.file shares decoded images across instances', () {
      final dir = Directory.systemTemp.createTempSync('fleury_image_cache_');
      addTearDown(() {
        ImageSource.evictAll();
        dir.deleteSync(recursive: true);
      });
      final path = '${dir.path}/shared.png';
      File(path).writeAsBytesSync(img.encodePng(_solid(2, 2, 5, 10, 15)));

      final a = ImageSource.file(path);
      final b = ImageSource.file(path);
      expect(
        identical(a.decode(), b.decode()),
        isTrue,
        reason: 'two ImageSource.file for the same path decode once',
      );
    });

    test('ImageSource.evictFile forces a fresh decode on next call', () {
      final dir = Directory.systemTemp.createTempSync('fleury_image_evict_');
      addTearDown(() {
        ImageSource.evictAll();
        dir.deleteSync(recursive: true);
      });
      final path = '${dir.path}/evicting.png';
      File(path).writeAsBytesSync(img.encodePng(_solid(2, 2, 5, 10, 15)));

      final firstDecode = ImageSource.file(path).decode();
      ImageSource.evictFile(path);
      // Overwrite the file with different pixels so we can prove the
      // second decode actually re-read from disk.
      File(path).writeAsBytesSync(img.encodePng(_solid(2, 2, 99, 99, 99)));
      final secondDecode = ImageSource.file(path).decode();

      expect(
        identical(firstDecode, secondDecode),
        isFalse,
        reason: 'eviction forces a re-decode',
      );
      expect(
        secondDecode.getPixel(0, 0).r.toInt(),
        99,
        reason: 're-decode reflects the new file contents',
      );
    });
  });

  group('Image — factory constructors (Flutter-shaped)', () {
    testWidgets('Image.decoded wires through directly', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image.decoded(_solid(1, 2, 100, 150, 200), fit: ImageFit.fill),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const RgbColor(100, 150, 200));
    });

    test('Image.bytes constructs an ImageSource.bytes internally', () {
      final png = img.encodePng(_solid(2, 2, 10, 20, 30));
      final widget = Image.bytes(png);
      expect(widget.source, isNotNull);
      // Decoding through the source path works.
      expect(widget.source.decode().width, 2);
    });

    test('Image.file is the shorthand for ImageSource.file', () {
      final dir = Directory.systemTemp.createTempSync('fleury_image_factory_');
      addTearDown(() {
        ImageSource.evictAll();
        dir.deleteSync(recursive: true);
      });
      final path = '${dir.path}/factory.png';
      File(path).writeAsBytesSync(img.encodePng(_solid(2, 2, 5, 10, 15)));

      final widget = Image.file(path);
      expect(widget.source.decode().width, 2);
    });
  });

  group('Image — area sampling on downscale', () {
    testWidgets('a 2×2 source averaged into one cell yields the mean color', (
      tester,
    ) {
      // Source: 2×2 image with four distinct corner colors. Downscale
      // to 1×1 cell (= 1×2 vertical pixels) with fit: fill.
      //   top half maps to the top row of source (10,20,30) and
      //   (40,50,60), averaged → ((10+40)/2, (20+50)/2, (30+60)/2)
      //   = (25, 35, 45).
      //   bottom half maps to the bottom row → ((70+100)/2, (80+110)/2,
      //   (90+120)/2) = (85, 95, 105).
      final image = img.Image(width: 2, height: 2);
      image.setPixel(0, 0, img.ColorRgb8(10, 20, 30));
      image.setPixel(1, 0, img.ColorRgb8(40, 50, 60));
      image.setPixel(0, 1, img.ColorRgb8(70, 80, 90));
      image.setPixel(1, 1, img.ColorRgb8(100, 110, 120));
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(source: ImageSource.decoded(image), fit: ImageFit.fill),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.style.foreground,
        const RgbColor(25, 35, 45),
        reason: 'top half = average of source row 0 (not just one pixel)',
      );
      expect(
        cell.style.background,
        const RgbColor(85, 95, 105),
        reason: 'bottom half = average of source row 1',
      );
    });

    testWidgets('a 4×4 checkerboard averaged into one cell yields mid-gray', (
      tester,
    ) {
      // Classic anti-alias test: a checkerboard sampled at half the
      // input frequency should collapse to flat gray. With nearest-
      // neighbor it produces an arbitrary corner color.
      final image = img.Image(width: 4, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final on = ((x + y) & 1) == 0;
          image.setPixel(
            x,
            y,
            on ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
          );
        }
      }
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(source: ImageSource.decoded(image), fit: ImageFit.fill),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      final fg = cell.style.foreground as RgbColor;
      final bg = cell.style.background as RgbColor;
      // Average of 4 checkerboard pixels = 127.5; rounds to 127 or 128.
      for (final ch in [fg.r, fg.g, fg.b, bg.r, bg.g, bg.b]) {
        expect(
          ch,
          anyOf(127, 128),
          reason: 'area-sampled checkerboard should collapse to mid-gray',
        );
      }
    });

    testWidgets('partial-cell letterbox edges weight the average correctly', (
      tester,
    ) {
      // Image is 4 wide, mapped via fit: contain into a 3-cell-wide
      // box (so source-width-per-cell is 4/3 ≈ 1.33). Each cell covers
      // a non-integer source rect, so area-weighted averaging matters.
      // We just verify no crash + non-null result at the center cell.
      final image = img.Image(width: 4, height: 2);
      for (var x = 0; x < 4; x++) {
        image.setPixel(x, 0, img.ColorRgb8(x * 64, x * 64, x * 64));
        image.setPixel(x, 1, img.ColorRgb8(x * 64, x * 64, x * 64));
      }
      tester.pumpWidget(
        SizedBox(
          width: 3,
          height: 1,
          child: Image(source: ImageSource.decoded(image), fit: ImageFit.fill),
        ),
      );
      final buf = tester.render(size: const CellSize(3, 1));
      for (var c = 0; c < 3; c++) {
        expect(buf.atColRow(c, 0).grapheme, '▀');
        // Center cell should be near-gray since it averages across the
        // gradient; not a hard exact match, but must not be black or
        // white.
      }
      final mid = buf.atColRow(1, 0).style.foreground! as RgbColor;
      expect(mid.r, greaterThan(20));
      expect(mid.r, lessThan(235));
    });

    testWidgets('upscale (target larger than source) still uses nearest', (
      tester,
    ) {
      // Source: 1×2 solid red. Target: 4×4 cells = 4×8 vertical pixels.
      // The whole target shows red (the rect per target pixel is small,
      // covers <1 source pixel; we nearest-neighbor without averaging
      // garbage).
      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 4,
          child: Image(
            source: ImageSource.decoded(_solid(1, 2, 200, 0, 0)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 4));
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          expect(
            buf.atColRow(c, r).style.foreground,
            const RgbColor(200, 0, 0),
          );
        }
      }
    });
  });

  group('Image — capability semantics', () {
    testWidgets('reports glyph fallback when native images are unavailable', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 2,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(4, 2, 20, 40, 80)),
            fit: ImageFit.fill,
            glyph: ImageGlyph.quarterBlock,
            semanticLabel: 'Preview',
          ),
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.image,
        label: 'Preview',
      );

      expect(node.value, 'halfBlock');
      expect(node.state.terminalCapability, 'inlineImages');
      expect(node.state.capabilityRequirement, 'preferred');
      expect(node.state.capabilityResolution, 'degraded');
      expect(node.state.activeFallback, 'quarterBlock glyph image');
      expect(node.state.values['imageProtocol'], 'halfBlock');
      expect(node.state.values['imageGlyph'], 'quarterBlock');
      expect(node.state.values['frameIndex'], 0);
      expect(node.state.values['frameCount'], 1);
    });

    testWidgets('reports native image capability when a protocol is active', (
      tester,
    ) {
      tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: CellSize(10, 10),
            imageProtocol: ImageProtocol.kitty,
            tmuxPassthrough: true,
          ),
          child: SizedBox(
            width: 2,
            height: 1,
            child: Image(
              source: ImageSource.decoded(_solid(4, 2, 20, 40, 80)),
              fit: ImageFit.fill,
              semanticLabel: 'Logo',
            ),
          ),
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.image,
        label: 'Logo',
      );

      expect(node.value, 'kitty');
      expect(node.state.terminalCapability, 'inlineImages');
      expect(node.state.capabilityRequirement, 'preferred');
      expect(node.state.capabilityResolution, 'available');
      expect(node.state.activeFallback, isNull);
      expect(node.state.values['imageProtocol'], 'kitty');
      expect(node.state.values['tmuxPassthrough'], isTrue);
    });
  });

  group('Image — color-mode quantization', () {
    Widget hosted(Widget child, ColorMode mode) {
      return MediaQuery(
        data: MediaQueryData(size: const CellSize(10, 10), colorMode: mode),
        child: child,
      );
    }

    testWidgets('truecolor mode emits RgbColor verbatim (no quantization)', (
      tester,
    ) {
      tester.pumpWidget(
        hosted(
          const SizedBox(
            width: 1,
            height: 1,
            child: _Image1x2(r: 200, g: 100, b: 50),
          ),
          ColorMode.truecolor,
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const RgbColor(200, 100, 50));
    });

    testWidgets('indexed256 mode emits IndexedColor from the 6×6×6 cube', (
      tester,
    ) {
      tester.pumpWidget(
        hosted(
          const SizedBox(
            width: 1,
            height: 1,
            child: _Image1x2(r: 215, g: 0, b: 0),
          ),
          ColorMode.indexed256,
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      // 215 is cube level 4 (levels = [0, 95, 135, 175, 215, 255]);
      // RGB index (4, 0, 0) → 16 + 36*4 + 6*0 + 0 = 160.
      expect(cell.style.foreground, const IndexedColor(160));
    });

    testWidgets('ansi16 mode emits AnsiColor from the standard 16', (tester) {
      tester.pumpWidget(
        hosted(
          const SizedBox(
            width: 1,
            height: 1,
            child: _Image1x2(r: 255, g: 0, b: 0),
          ),
          ColorMode.ansi16,
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      // Pure red → AnsiColor(9) (bright red) — closest match in the
      // 16-color table.
      expect(cell.style.foreground, isA<AnsiColor>());
      expect(
        (cell.style.foreground as AnsiColor).index,
        anyOf(1, 9),
        reason: 'pure red maps to ANSI red or bright red',
      );
    });

    testWidgets('none mode strips color (foreground null)', (tester) {
      tester.pumpWidget(
        hosted(
          const SizedBox(
            width: 1,
            height: 1,
            child: _Image1x2(r: 200, g: 100, b: 50),
          ),
          ColorMode.none,
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, isNull);
      expect(cell.style.background, isNull);
      // The glyph still emits — without color, ▀ reads as a half-block
      // in the terminal's default fg, which is the right fallback.
      expect(cell.grapheme, '▀');
    });

    testWidgets('ansi16 dithering: a mid-gray gradient produces ≥ 2 colors', (
      tester,
    ) {
      // 8-wide horizontal gradient. Without dithering, the entire row
      // quantizes to the nearest single ansi color (probably black or
      // white) producing a flat band. With Floyd-Steinberg, the error
      // distribution should produce alternating colors that AVERAGE
      // to the gradient — the test asserts at least two distinct
      // colors appear in the row.
      final image = img.Image(width: 8, height: 2);
      for (var x = 0; x < 8; x++) {
        final v = (x * 255 / 7).round();
        for (var y = 0; y < 2; y++) {
          image.setPixel(x, y, img.ColorRgb8(v, v, v));
        }
      }
      tester.pumpWidget(
        hosted(
          SizedBox(
            width: 8,
            height: 1,
            child: Image(
              source: ImageSource.decoded(image),
              fit: ImageFit.fill,
            ),
          ),
          ColorMode.ansi16,
        ),
      );
      final buf = tester.render(size: const CellSize(8, 1));
      final distinct = <Color>{};
      for (var c = 0; c < 8; c++) {
        final fg = buf.atColRow(c, 0).style.foreground;
        if (fg != null) distinct.add(fg);
      }
      expect(
        distinct.length,
        greaterThanOrEqualTo(2),
        reason: 'dithering should produce more than one color across the row',
      );
    });
  });

  group('Image — Kitty graphics protocol', () {
    Widget kittyHosted(Widget child) {
      return MediaQuery(
        data: const MediaQueryData(
          size: CellSize(10, 10),
          imageProtocol: ImageProtocol.kitty,
        ),
        child: child,
      );
    }

    testWidgets('emits a protocolAnchor at the top-left of the image box', (
      tester,
    ) {
      tester.pumpWidget(
        kittyHosted(
          SizedBox(
            width: 4,
            height: 3,
            child: Image(
              source: ImageSource.decoded(_solid(8, 8, 10, 20, 30)),
              fit: ImageFit.contain,
            ),
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 3));
      final anchor = buf.atColRow(0, 0);
      expect(
        anchor.role,
        CellRole.protocolAnchor,
        reason: 'top-left cell holds the raw Kitty escape sequence',
      );
      // No half-block content should appear under Kitty.
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 4; c++) {
          if (r == 0 && c == 0) continue;
          expect(
            buf.atColRow(c, r).role,
            CellRole.protocolCovered,
            reason: 'cells inside the image region are protocol-covered',
          );
        }
      }
    });

    testWidgets('anchor grapheme contains the Kitty f=100,a=T,c=,r= header', (
      tester,
    ) {
      tester.pumpWidget(
        kittyHosted(
          SizedBox(
            width: 5,
            height: 2,
            child: Image(
              source: ImageSource.decoded(_solid(4, 4, 0, 0, 0)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final anchor = tester.render(size: const CellSize(5, 2)).atColRow(0, 0);
      final escape = anchor.grapheme!;
      expect(
        escape.startsWith('\x1B_G'),
        isTrue,
        reason: 'first chunk opens with the Kitty APC prefix',
      );
      expect(escape.contains('f=100'), isTrue, reason: 'PNG transfer format');
      expect(escape.contains('a=T'), isTrue, reason: 'transmit + display now');
      expect(escape.contains('c=5'), isTrue, reason: 'display width in cells');
      expect(escape.contains('r=2'), isTrue, reason: 'display height in rows');
      expect(
        escape.endsWith('\x1B\\'),
        isTrue,
        reason: 'last chunk closes with ST',
      );
    });

    testWidgets(
      'large payloads chunk: multiple m=1 fragments terminated by m=0',
      (tester) {
        // PNG compresses solid colors aggressively, so a flat 200×200
        // image fits in one chunk. Use a deterministic noise pattern that
        // doesn't compress — guarantees the encoder hits its 4KiB chunk
        // boundary.
        final noisy = img.Image(width: 200, height: 200);
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 200; x++) {
            final r = (x * 17 + y * 23) & 0xFF;
            final g = (x * 41 + y * 7) & 0xFF;
            final b = (x * 53 + y * 31) & 0xFF;
            noisy.setPixel(x, y, img.ColorRgb8(r, g, b));
          }
        }
        tester.pumpWidget(
          kittyHosted(
            SizedBox(
              width: 8,
              height: 4,
              child: Image(
                source: ImageSource.decoded(noisy),
                fit: ImageFit.fill,
              ),
            ),
          ),
        );
        final escape = tester
            .render(size: const CellSize(8, 4))
            .atColRow(0, 0)
            .grapheme!;
        final continuations = 'm=1'.allMatches(escape).length;
        final finals = 'm=0'.allMatches(escape).length;
        expect(
          continuations,
          greaterThanOrEqualTo(1),
          reason: 'a >4KiB payload should produce at least one m=1 chunk',
        );
        expect(finals, 1, reason: 'exactly one final m=0 closes the stream');
        // Every chunk is wrapped in its own ESC_G…ESC\ envelope.
        expect(
          '\x1B_G'.allMatches(escape).length,
          equals(continuations + finals),
        );
        expect(
          '\x1B\\'.allMatches(escape).length,
          equals(continuations + finals),
        );
      },
    );

    testWidgets('halfBlock mode keeps painting ▀ (no protocol regression)', (
      tester,
    ) {
      // Default protocol is halfBlock — sanity-check the kitty path is
      // strictly opt-in.
      tester.pumpWidget(
        SizedBox(
          width: 2,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(2, 2, 10, 20, 30)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(2, 1)).atColRow(0, 0);
      expect(cell.role, CellRole.leading);
      expect(cell.grapheme, '▀');
    });
  });

  group('Image — iTerm2 inline-image protocol', () {
    Widget itermHosted(Widget child) {
      return MediaQuery(
        data: const MediaQueryData(
          size: CellSize(10, 10),
          imageProtocol: ImageProtocol.iterm2,
        ),
        child: child,
      );
    }

    testWidgets('emits a protocolAnchor at the top-left of the image box', (
      tester,
    ) {
      tester.pumpWidget(
        itermHosted(
          SizedBox(
            width: 4,
            height: 3,
            child: Image(
              source: ImageSource.decoded(_solid(8, 8, 10, 20, 30)),
              fit: ImageFit.contain,
            ),
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 3));
      expect(buf.atColRow(0, 0).role, CellRole.protocolAnchor);
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 4; c++) {
          if (r == 0 && c == 0) continue;
          expect(buf.atColRow(c, r).role, CellRole.protocolCovered);
        }
      }
    });

    testWidgets('anchor grapheme is OSC 1337 + base64 PNG + BEL', (tester) {
      tester.pumpWidget(
        itermHosted(
          SizedBox(
            width: 6,
            height: 4,
            child: Image(
              source: ImageSource.decoded(_solid(8, 8, 0, 128, 255)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final escape = tester
          .render(size: const CellSize(6, 4))
          .atColRow(0, 0)
          .grapheme!;
      expect(
        escape.startsWith('\x1B]1337;File='),
        isTrue,
        reason: 'OSC 1337 introducer with File argument list',
      );
      expect(escape.contains('inline=1'), isTrue, reason: 'display inline');
      expect(
        escape.contains('width=6'),
        isTrue,
        reason: 'display width in cells',
      );
      expect(
        escape.contains('height=4'),
        isTrue,
        reason: 'display height in rows',
      );
      expect(
        escape.contains('preserveAspectRatio=0'),
        isTrue,
        reason: 'caller (us) already laid out the fit',
      );
      expect(escape.endsWith('\x07'), isTrue, reason: 'BEL terminator');
      // The payload separator ':' precedes the base64 body. Body must be
      // non-empty and consist of valid base64 chars only.
      final colon = escape.indexOf(':');
      expect(colon, greaterThan(0));
      final body = escape.substring(colon + 1, escape.length - 1);
      expect(body, isNotEmpty);
      expect(
        RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(body),
        isTrue,
        reason: 'base64 payload between : and BEL',
      );
    });

    testWidgets('size= header reports the PNG byte length', (tester) {
      tester.pumpWidget(
        itermHosted(
          SizedBox(
            width: 3,
            height: 2,
            child: Image(
              source: ImageSource.decoded(_solid(2, 2, 50, 60, 70)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final escape = tester
          .render(size: const CellSize(3, 2))
          .atColRow(0, 0)
          .grapheme!;
      final sizeMatch = RegExp(r'size=(\d+)').firstMatch(escape);
      expect(sizeMatch, isNotNull);
      final declared = int.parse(sizeMatch!.group(1)!);
      final colon = escape.indexOf(':');
      final b64 = escape.substring(colon + 1, escape.length - 1);
      // base64 expansion: 4 chars per 3 bytes (with padding). Decoded
      // length must match the declared size.
      final decodedLen = base64.decode(b64).length;
      expect(
        decodedLen,
        declared,
        reason: 'size= must match the decoded PNG byte length exactly',
      );
    });
  });

  group('Image — quarter-block glyph palette', () {
    // 2×2 image where each quadrant is a single distinct pixel.
    // Mapped 1:1 onto a 1×1 cell (cell covers 2 horizontal × 2
    // vertical sub-pixels), so each cell quadrant gets exactly one
    // sample — perfect for asserting on which 16-pattern glyph fires.
    img.Image quadCell({
      required (int, int, int) tl,
      required (int, int, int) tr,
      required (int, int, int) bl,
      required (int, int, int) br,
    }) {
      final image = img.Image(width: 2, height: 2);
      image.setPixel(0, 0, img.ColorRgb8(tl.$1, tl.$2, tl.$3));
      image.setPixel(1, 0, img.ColorRgb8(tr.$1, tr.$2, tr.$3));
      image.setPixel(0, 1, img.ColorRgb8(bl.$1, bl.$2, bl.$3));
      image.setPixel(1, 1, img.ColorRgb8(br.$1, br.$2, br.$3));
      return image;
    }

    testWidgets('top-half stripe picks ▀ (TL+TR fg, BL+BR bg)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              quadCell(
                tl: (255, 0, 0),
                tr: (255, 0, 0),
                bl: (0, 0, 255),
                br: (0, 0, 255),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.quarterBlock,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        '▀',
        reason: 'top-half source matches the half-block pattern',
      );
      expect(cell.style.foreground, const RgbColor(255, 0, 0));
      expect(cell.style.background, const RgbColor(0, 0, 255));
    });

    testWidgets('left-half stripe picks ▌ (TL+BL fg, TR+BR bg)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              quadCell(
                tl: (255, 255, 0),
                tr: (0, 128, 255),
                bl: (255, 255, 0),
                br: (0, 128, 255),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.quarterBlock,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        '▌',
        reason:
            'left-column source picks the vertical-half glyph — '
            'something half-block CANNOT represent',
      );
      expect(cell.style.foreground, const RgbColor(255, 255, 0));
      expect(cell.style.background, const RgbColor(0, 128, 255));
    });

    testWidgets('diagonal picks ▚ (TL+BR fg, TR+BL bg)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              quadCell(
                tl: (255, 0, 0),
                tr: (0, 0, 0),
                bl: (0, 0, 0),
                br: (255, 0, 0),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.quarterBlock,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        '▚',
        reason: 'TL+BR diagonal lit, TR+BL dark — diagonal glyph',
      );
    });

    testWidgets('single-quadrant TL fires ▘', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              quadCell(
                tl: (200, 200, 200),
                tr: (0, 0, 0),
                bl: (0, 0, 0),
                br: (0, 0, 0),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.quarterBlock,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.grapheme, '▘');
    });

    testWidgets('uniform cell still emits exactly one solid fill', (tester) {
      // All-equal quadrants should produce a degenerate full-block
      // (or space) — both render visually identical. Just assert the
      // glyph is one of the trivial all-on / all-off ones, NOT a
      // partial pattern.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              quadCell(
                tl: (50, 60, 70),
                tr: (50, 60, 70),
                bl: (50, 60, 70),
                br: (50, 60, 70),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.quarterBlock,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        anyOf(' ', '█'),
        reason: 'uniform sample → trivial glyph',
      );
    });

    testWidgets('default glyph stays halfBlock (no API surprise)', (tester) {
      // The new palette must be strictly opt-in. The classic
      // 1×2-into-one-cell test should still emit ▀.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(1, 2, 100, 150, 200)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.grapheme, '▀');
    });
  });

  group('Image — sextant glyph palette', () {
    // 2×3 image where each sub-cell holds one distinct pixel — maps
    // 1:1 onto a 1-cell box (2 cols × 3 rows of sub-pixels per cell).
    img.Image sextCell({
      required (int, int, int) tl,
      required (int, int, int) tr,
      required (int, int, int) ml,
      required (int, int, int) mr,
      required (int, int, int) bl,
      required (int, int, int) br,
    }) {
      final image = img.Image(width: 2, height: 3);
      image.setPixel(0, 0, img.ColorRgb8(tl.$1, tl.$2, tl.$3));
      image.setPixel(1, 0, img.ColorRgb8(tr.$1, tr.$2, tr.$3));
      image.setPixel(0, 1, img.ColorRgb8(ml.$1, ml.$2, ml.$3));
      image.setPixel(1, 1, img.ColorRgb8(mr.$1, mr.$2, mr.$3));
      image.setPixel(0, 2, img.ColorRgb8(bl.$1, bl.$2, bl.$3));
      image.setPixel(1, 2, img.ColorRgb8(br.$1, br.$2, br.$3));
      return image;
    }

    testWidgets('left column lit → ▌ (pattern 21 reuses LEFT HALF BLOCK)', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              sextCell(
                tl: (255, 0, 0),
                tr: (0, 0, 255),
                ml: (255, 0, 0),
                mr: (0, 0, 255),
                bl: (255, 0, 0),
                br: (0, 0, 255),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.sextant,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        '▌',
        reason: 'pattern 21 reuses U+258C LEFT HALF BLOCK',
      );
      expect(cell.style.foreground, const RgbColor(255, 0, 0));
      expect(cell.style.background, const RgbColor(0, 0, 255));
    });

    testWidgets('top-left-only lit → U+1FB00 (sextant-1, pattern 1)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              sextCell(
                tl: (255, 255, 255),
                tr: (0, 0, 0),
                ml: (0, 0, 0),
                mr: (0, 0, 0),
                bl: (0, 0, 0),
                br: (0, 0, 0),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.sextant,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme!.codeUnits,
        '\u{1FB00}'.codeUnits,
        reason:
            'single-TL sextant lands on the first codepoint of the '
            'Unicode 13 block',
      );
    });

    testWidgets('middle row lit → a sextant codepoint, not a quadrant', (
      tester,
    ) {
      // Pattern 12 (binary 001100 = ML + MR) is something quarterBlock
      // physically can't represent (no 2-pixel middle row in a 2×2
      // grid). This proves sextant unlocks real new resolution.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              sextCell(
                tl: (0, 0, 0),
                tr: (0, 0, 0),
                ml: (255, 255, 255),
                mr: (255, 255, 255),
                bl: (0, 0, 0),
                br: (0, 0, 0),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.sextant,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      // Pattern 12, mapped through the skip table: offset = 12 - 1 = 11,
      // → U+1FB0B.
      expect(
        cell.grapheme,
        '\u{1FB0B}',
        reason: 'middle-row sextant lives in the U+1FB block',
      );
    });

    testWidgets('all-on → █ (pattern 63 reuses FULL BLOCK)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              sextCell(
                tl: (200, 200, 200),
                tr: (200, 200, 200),
                ml: (200, 200, 200),
                mr: (200, 200, 200),
                bl: (200, 200, 200),
                br: (200, 200, 200),
              ),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.sextant,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        anyOf(' ', '█'),
        reason: 'uniform sample → trivial glyph (space or full block)',
      );
    });

    testWidgets('default glyph stays halfBlock (no API surprise)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(1, 2, 100, 150, 200)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.grapheme, '▀');
    });
  });

  group('Image — braille glyph palette', () {
    // 2×4 sub-pixel grid per cell; bit layout (per Unicode 6429):
    //   col 0          col 1
    //   row 0: bit 0   bit 3
    //   row 1: bit 1   bit 4
    //   row 2: bit 2   bit 5
    //   row 3: bit 6   bit 7
    // Codepoint = U+2800 + pattern.

    /// Builds a 2-wide × 4-tall image where each sub-pixel is white or
    /// black, controlled by [bits] (a list of 8 booleans in bit-index
    /// order — bit 0 first).
    img.Image dotCell(List<bool> bits) {
      final image = img.Image(width: 2, height: 4);
      // Map from bit index → (col, row).
      const pos = [
        (0, 0), // bit 0
        (0, 1), // bit 1
        (0, 2), // bit 2
        (1, 0), // bit 3
        (1, 1), // bit 4
        (1, 2), // bit 5
        (0, 3), // bit 6
        (1, 3), // bit 7
      ];
      for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 4; y++) {
          image.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
      for (var i = 0; i < bits.length; i++) {
        if (!bits[i]) continue;
        final (c, r) = pos[i];
        image.setPixel(c, r, img.ColorRgb8(255, 255, 255));
      }
      return image;
    }

    testWidgets('only bit 0 lit → U+2801', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              dotCell([true, false, false, false, false, false, false, false]),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.braille,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.grapheme!.codeUnits, '\u{2801}'.codeUnits);
    });

    testWidgets('only bit 7 (bottom-right) lit → U+2880', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(
              dotCell([false, false, false, false, false, false, false, true]),
            ),
            fit: ImageFit.fill,
            glyph: ImageGlyph.braille,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.grapheme, '\u{2880}');
    });

    testWidgets('all 8 dots lit → U+28FF (full braille cell)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(dotCell(List.filled(8, true))),
            fit: ImageFit.fill,
            glyph: ImageGlyph.braille,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.grapheme, '\u{28FF}');
    });

    testWidgets('fully dark cell emits nothing (no glyph)', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(dotCell(List.filled(8, false))),
            fit: ImageFit.fill,
            glyph: ImageGlyph.braille,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.grapheme,
        isNull,
        reason: 'pattern 0 — fully dark — leaves the cell empty',
      );
    });

    testWidgets('lit-pixel color drives the foreground', (tester) {
      // Fill bit 0 with red; rest black. Foreground should be near-red.
      final image = img.Image(width: 2, height: 4);
      for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 4; y++) {
          image.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
      image.setPixel(0, 0, img.ColorRgb8(255, 0, 0));
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(image),
            fit: ImageFit.fill,
            glyph: ImageGlyph.braille,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(cell.style.foreground, const RgbColor(255, 0, 0));
    });
  });

  group('Image — Sixel protocol', () {
    Widget sixelHosted(Widget child) {
      return MediaQuery(
        data: const MediaQueryData(
          size: CellSize(20, 20),
          imageProtocol: ImageProtocol.sixel,
        ),
        child: child,
      );
    }

    testWidgets('emits a protocolAnchor + protocolCovered region', (tester) {
      tester.pumpWidget(
        sixelHosted(
          SizedBox(
            width: 3,
            height: 2,
            child: Image(
              source: ImageSource.decoded(_solid(8, 8, 100, 50, 200)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(3, 2));
      expect(buf.atColRow(0, 0).role, CellRole.protocolAnchor);
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c < 3; c++) {
          if (r == 0 && c == 0) continue;
          expect(buf.atColRow(c, r).role, CellRole.protocolCovered);
        }
      }
    });

    testWidgets('anchor grapheme is a well-formed Sixel DCS envelope', (
      tester,
    ) {
      tester.pumpWidget(
        sixelHosted(
          SizedBox(
            width: 2,
            height: 1,
            child: Image(
              source: ImageSource.decoded(_solid(4, 4, 255, 128, 0)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final escape = tester
          .render(size: const CellSize(2, 1))
          .atColRow(0, 0)
          .grapheme!;
      expect(
        escape.startsWith('\x1BPq'),
        isTrue,
        reason: 'DCS introducer + Sixel selector',
      );
      expect(
        escape.endsWith('\x1B\\'),
        isTrue,
        reason: 'ST terminator closes the DCS',
      );
      // Raster attribute must be present immediately after 'q' with
      // 1:1 pan/pad. Width/height of (cols·10, rows·20) for the
      // default 10×20 cell-pixel target.
      expect(
        escape.contains('"1;1;20;20'),
        isTrue,
        reason: 'raster attrs declare image extent',
      );
      // At least one color-register definition (`#N;2;R;G;B`).
      expect(
        RegExp(r'#\d+;2;\d+;\d+;\d+').hasMatch(escape),
        isTrue,
        reason: 'palette emission produces at least one RGB register',
      );
    });

    testWidgets('sixel data bytes stay inside the legal `?`..`~` range '
        '(plus control chars)', (tester) {
      // Sixel data bytes are ASCII 63 ('?') to 126 ('~'). The only
      // allowed control chars in the payload are `$` (CR), `-` (NL),
      // and `!` (RLE introducer). Plus digits / `;` for palette and
      // RLE counts, plus `#`, `"`, `\x1B`, `P`, `q`, `\\`.
      tester.pumpWidget(
        sixelHosted(
          SizedBox(
            width: 2,
            height: 2,
            child: Image(
              source: ImageSource.decoded(_solid(8, 8, 50, 200, 100)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final escape = tester
          .render(size: const CellSize(2, 2))
          .atColRow(0, 0)
          .grapheme!;
      // Strip the envelope to focus on the payload.
      final payload = escape
          .substring(3, escape.length - 2) // drop \x1BPq … \x1B\
          .replaceAll(RegExp(r'"[\d;]+'), '') // drop raster attrs
          .replaceAll(RegExp(r'#\d+(;\d+;\d+;\d+;\d+)?'), '');
      for (final code in payload.codeUnits) {
        final ok =
            (code >= 0x3F && code <= 0x7E) || // sixel chars
            code == 0x24 || // $  CR within band
            code == 0x2D || // -  NL between bands
            code == 0x21 || // !  RLE
            (code >= 0x30 && code <= 0x39) || // 0-9 (RLE counts)
            code == 0x3B; // ;  separator (unlikely here, safety)
        expect(
          ok,
          isTrue,
          reason:
              'unexpected code point 0x${code.toRadixString(16)} '
              'in sixel payload',
        );
      }
    });

    testWidgets('halfBlock-mode rendering unaffected by sixel encoder', (
      tester,
    ) {
      // Default protocol stays halfBlock — the sixel encoder must be
      // strictly opt-in.
      tester.pumpWidget(
        SizedBox(
          width: 2,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(2, 2, 10, 20, 30)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(2, 1)).atColRow(0, 0);
      expect(cell.role, CellRole.leading);
      expect(cell.grapheme, '▀');
    });
  });

  group('Image — animated frames', () {
    // Build a 2-frame animation: frame 0 red, frame 1 blue, each
    // [durationMs] apart. `package:image` exposes the multi-frame
    // model via Image.frames + addFrame; we keep both frames as
    // 1×2 solid blocks so a 1-cell render reads back the exact
    // color and we can assert which frame is on screen.
    img.Image twoFrameAnim(int durationMs) {
      final frame0 = img.Image(width: 1, height: 2);
      img.fill(frame0, color: img.ColorRgb8(255, 0, 0));
      frame0.frameDuration = durationMs;

      final frame1 = img.Image(width: 1, height: 2);
      img.fill(frame1, color: img.ColorRgb8(0, 0, 255));
      frame1.frameDuration = durationMs;

      frame0.addFrame(frame1);
      return frame0;
    }

    testWidgets('first frame shows on initial render', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(twoFrameAnim(100)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.style.foreground,
        const RgbColor(255, 0, 0),
        reason: 'frame 0 should be on screen first',
      );
    });

    testWidgets('advances to the next frame after the frame duration', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(twoFrameAnim(100)),
            fit: ImageFit.fill,
          ),
        ),
      );
      // First render kicks off the ticker.
      tester.render(size: const CellSize(1, 1));
      // Advance past frame 0's duration.
      tester.pump(const Duration(milliseconds: 150));
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.style.foreground,
        const RgbColor(0, 0, 255),
        reason: 'after 150 ms (>100 ms) we should see frame 1',
      );
    });

    testWidgets('loops back to frame 0 after the last frame', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(twoFrameAnim(50)),
            fit: ImageFit.fill,
          ),
        ),
      );
      tester.render(size: const CellSize(1, 1));
      // 2 frames × 50 ms = 100 ms full cycle. Pump 120 ms → we should
      // be back on frame 0 (with 20 ms accumulated into its budget).
      tester.pump(const Duration(milliseconds: 120));
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.style.foreground,
        const RgbColor(255, 0, 0),
        reason: 'after one full cycle we loop back to frame 0',
      );
    });

    testWidgets('0 ms frame duration clamps to the default interval', (tester) {
      // A maliciously fast GIF (duration=0) should not busy-loop the
      // host. We clamp to the default ~100 ms tick, so a 50 ms pump
      // stays on frame 0.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(twoFrameAnim(0)),
            fit: ImageFit.fill,
          ),
        ),
      );
      tester.render(size: const CellSize(1, 1));
      tester.pump(const Duration(milliseconds: 50));
      final cell = tester.render(size: const CellSize(1, 1)).atColRow(0, 0);
      expect(
        cell.style.foreground,
        const RgbColor(255, 0, 0),
        reason: 'clamped to default 100 ms — still on frame 0 at 50 ms',
      );
    });

    testWidgets('static images do not start a ticker', (tester) {
      // Regression guard: a 1-frame image must not register a
      // periodic ticker that wastes work.
      tester.pumpWidget(
        SizedBox(
          width: 1,
          height: 1,
          child: Image(
            source: ImageSource.decoded(_solid(1, 2, 0, 200, 0)),
            fit: ImageFit.fill,
          ),
        ),
      );
      tester.render(size: const CellSize(1, 1));
      expect(
        tester.scheduler.activeTickerCount,
        0,
        reason: 'no animation means no ticker',
      );
    });
  });

  group('Image — tmux passthrough', () {
    Widget tmuxKittyHosted(Widget child) {
      return MediaQuery(
        data: const MediaQueryData(
          size: CellSize(10, 10),
          imageProtocol: ImageProtocol.kitty,
          tmuxPassthrough: true,
        ),
        child: child,
      );
    }

    testWidgets('wraps a Kitty payload in the tmux passthrough envelope', (
      tester,
    ) {
      tester.pumpWidget(
        tmuxKittyHosted(
          SizedBox(
            width: 3,
            height: 2,
            child: Image(
              source: ImageSource.decoded(_solid(4, 4, 50, 60, 70)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final anchor = tester.render(size: const CellSize(3, 2)).atColRow(0, 0);
      final bytes = anchor.grapheme!;
      expect(
        bytes.startsWith('\x1BPtmux;'),
        isTrue,
        reason: 'opens with tmux DCS introducer',
      );
      expect(bytes.endsWith('\x1B\\'), isTrue, reason: 'closes with ST');
      // Every embedded ESC inside the payload must be doubled. The
      // Kitty APC opener `\x1B_G` should therefore become `\x1B\x1B_G`
      // at the start of the body.
      final body = bytes.substring(7, bytes.length - 2);
      expect(
        body.startsWith('\x1B\x1B_G'),
        isTrue,
        reason: 'doubled-ESC form is what tmux unwraps',
      );
      // And no lone (un-doubled) ESC bytes should remain — i.e. every
      // ESC has another ESC adjacent.
      for (var i = 0; i < body.length; i++) {
        if (body.codeUnitAt(i) != 0x1B) continue;
        final paired =
            (i + 1 < body.length && body.codeUnitAt(i + 1) == 0x1B) ||
            (i > 0 && body.codeUnitAt(i - 1) == 0x1B);
        expect(paired, isTrue, reason: 'lone ESC at body offset $i');
      }
    });

    testWidgets('passthrough off → payload is emitted bare', (tester) {
      tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: CellSize(10, 10),
            imageProtocol: ImageProtocol.kitty,
          ),
          child: SizedBox(
            width: 3,
            height: 2,
            child: Image(
              source: ImageSource.decoded(_solid(4, 4, 50, 60, 70)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final bytes = tester
          .render(size: const CellSize(3, 2))
          .atColRow(0, 0)
          .grapheme!;
      expect(
        bytes.startsWith('\x1B_G'),
        isTrue,
        reason: 'no tmux wrapper, native Kitty APC opener',
      );
    });

    testWidgets('Sixel and iTerm2 also flow through the same wrapper', (
      tester,
    ) {
      // Sixel payload contains DCS \x1BP; the wrapper must double it.
      tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: CellSize(10, 10),
            imageProtocol: ImageProtocol.sixel,
            tmuxPassthrough: true,
          ),
          child: SizedBox(
            width: 2,
            height: 1,
            child: Image(
              source: ImageSource.decoded(_solid(20, 20, 200, 0, 0)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final sixelBytes = tester
          .render(size: const CellSize(2, 1))
          .atColRow(0, 0)
          .grapheme!;
      expect(sixelBytes.startsWith('\x1BPtmux;'), isTrue);
      expect(
        sixelBytes.contains('\x1B\x1BP'),
        isTrue,
        reason: 'the inner Sixel DCS must be doubled',
      );

      tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: CellSize(10, 10),
            imageProtocol: ImageProtocol.iterm2,
            tmuxPassthrough: true,
          ),
          child: SizedBox(
            width: 2,
            height: 1,
            child: Image(
              source: ImageSource.decoded(_solid(4, 4, 0, 200, 0)),
              fit: ImageFit.fill,
            ),
          ),
        ),
      );
      final itermBytes = tester
          .render(size: const CellSize(2, 1))
          .atColRow(0, 0)
          .grapheme!;
      expect(itermBytes.startsWith('\x1BPtmux;'), isTrue);
      expect(
        itermBytes.contains('\x1B\x1B]1337;'),
        isTrue,
        reason: 'the inner iTerm2 OSC must be doubled',
      );
    });
  });

  group('Image — sizing', () {
    testWidgets('fills its bounded cell box', (tester) {
      // 2×4-pixel source bounded to a 2×2 cell box (which is 2×4
      // pixels). With fit: fill that's a 1:1 mapping.
      tester.pumpWidget(
        SizedBox(
          width: 2,
          height: 2,
          child: Image(
            source: ImageSource.decoded(_solid(2, 4, 80, 90, 100)),
            fit: ImageFit.fill,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(2, 2));
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c < 2; c++) {
          expect(
            buf.atColRow(c, r).grapheme,
            '▀',
            reason: 'every cell within the box should be painted',
          );
        }
      }
    });
  });
}
