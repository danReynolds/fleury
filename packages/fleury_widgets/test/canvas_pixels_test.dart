import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _CrossPainter implements CanvasPainter {
  const _CrossPainter();
  @override
  void paint(CanvasContext ctx) {
    ctx.drawLine(0, 0.5, 1, 0.5, color: const RgbColor(0, 255, 0), width: 2);
    ctx.drawLine(0.5, 0, 0.5, 1, color: const RgbColor(255, 0, 0), width: 2);
  }
}

class _FramePainter implements CanvasPainter {
  const _FramePainter(this.frame);
  final int frame;
  @override
  void paint(CanvasContext ctx) {
    final y = 0.2 + (frame % 5) * 0.15;
    ctx.drawLine(0, y, 1, y, color: const RgbColor(255, 255, 255), width: 2);
  }
}

const _rasterCaps = SurfaceCapabilities(
  images: InlineImageSupport.placements,
  liveRasters: true,
);

Widget _app(CanvasMarker marker, SurfaceCapabilities caps) => MediaQuery(
  data: MediaQueryData(size: const CellSize(12, 6), capabilities: caps),
  child: SizedBox(
    width: 12,
    height: 6,
    child: Canvas(marker: marker, painter: const _CrossPainter()),
  ),
);

void main() {
  group('Canvas pixels tier (RFC 0021)', () {
    testWidgets('pixels on a live-raster surface records a placement', (
      tester,
    ) {
      tester.pumpWidget(_app(CanvasMarker.pixels, _rasterCaps));
      final buffer = tester.render(size: const CellSize(12, 6));
      expect(buffer.imagePlacements, hasLength(1));
      final placement = buffer.imagePlacements.single;
      expect(placement.cols, 12);
      expect(placement.rows, 6);
      final image = buffer.images[placement.id]!;
      expect(image.isRaster, isTrue);
      expect(image.sourceWidth, 12 * 8);
      expect(image.sourceHeight, 6 * 16);
      final rgba = image.pixels!();
      expect(rgba.length, 12 * 8 * 6 * 16 * 4);
      // The horizontal stroke's green lands mid-raster.
      final midRow = (6 * 16) ~/ 2;
      final probe = (midRow * 12 * 8 + (12 * 8) ~/ 2) * 4;
      expect(rgba[probe + 1], greaterThan(0), reason: 'green channel inked');
    });

    testWidgets('pixels without live-raster support falls back to braille', (
      tester,
    ) {
      tester.pumpWidget(_app(CanvasMarker.pixels, const SurfaceCapabilities()));
      final buffer = tester.render(size: const CellSize(12, 6));
      expect(buffer.imagePlacements, isEmpty);
      final glyph = buffer.atColRow(6, 3).grapheme;
      expect(glyph, isNotNull);
      final code = glyph!.codeUnitAt(0);
      expect(
        code >= 0x2800 && code <= 0x28FF,
        isTrue,
        reason: 'expected braille, got U+${code.toRadixString(16)}',
      );
    });

    testWidgets('auto upgrades on live-raster surfaces only', (tester) {
      tester.pumpWidget(_app(CanvasMarker.auto, _rasterCaps));
      expect(
        tester.render(size: const CellSize(12, 6)).imagePlacements,
        hasLength(1),
      );
      tester.pumpWidget(_app(CanvasMarker.auto, const SurfaceCapabilities()));
      expect(
        tester.render(size: const CellSize(12, 6)).imagePlacements,
        isEmpty,
      );
    });

    testWidgets('identical pixels never bump the revision', (tester) {
      // A paused game or settled chart repaints the SAME raster; the hash
      // gate must keep the revision still, or 90KB/frame streams for
      // nothing on every surface.
      tester.pumpWidget(_app(CanvasMarker.pixels, _rasterCaps));
      final first = tester
          .render(size: const CellSize(12, 6))
          .imagePlacements
          .single
          .revision;
      // Same painter constant → identical pixels on repaint.
      tester.pumpWidget(_app(CanvasMarker.pixels, _rasterCaps));
      final second = tester
          .render(size: const CellSize(12, 6))
          .imagePlacements
          .single
          .revision;
      expect(second, first);
    });

    testWidgets('a budget-exceeding canvas drops one density rung', (tester) {
      // 200x40 cells at 8x16 would be 2.05M px — over the 480K budget, so
      // the ladder halves to 4x8 (still 2x braille density).
      tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: CellSize(200, 40),
            capabilities: SurfaceCapabilities(
              images: InlineImageSupport.placements,
              liveRasters: true,
            ),
          ),
          child: SizedBox(
            width: 200,
            height: 40,
            child: Canvas(
              marker: CanvasMarker.pixels,
              painter: const _CrossPainter(),
            ),
          ),
        ),
      );
      final buffer = tester.render(size: const CellSize(200, 40));
      final image = buffer.images[buffer.imagePlacements.single.id]!;
      expect(image.sourceWidth, 200 * 4);
      expect(image.sourceHeight, 40 * 8);
    });

    testWidgets('a repaint keeps the id STABLE and bumps the revision', (
      tester,
    ) {
      // The stable-id contract (RFC 0021 §2.5 revised): presenters replace
      // image data in place, so animation never churns placements and never
      // opens the deleted-old/undecoded-new gap that flickered on Warp. The
      // revision is what tells the diff and the presenters that the pixels
      // changed.
      Widget frameApp(int frame) => MediaQuery(
        data: const MediaQueryData(
          size: CellSize(12, 6),
          capabilities: _rasterCaps,
        ),
        child: SizedBox(
          width: 12,
          height: 6,
          child: Canvas(
            marker: CanvasMarker.pixels,
            painter: _FramePainter(frame),
          ),
        ),
      );
      tester.pumpWidget(frameApp(1));
      final first = tester
          .render(size: const CellSize(12, 6))
          .imagePlacements
          .single;
      tester.pumpWidget(frameApp(2));
      final second = tester
          .render(size: const CellSize(12, 6))
          .imagePlacements
          .single;
      expect(second.id, first.id, reason: 'the id must never churn');
      expect(
        second.revision,
        greaterThan(first.revision),
        reason: 'the revision is the animation signal',
      );
    });
  });
}
