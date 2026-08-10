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

    testWidgets('a repaint keeps the id STABLE and bumps the revision', (
      tester,
    ) {
      // The stable-id contract (RFC 0021 §2.5 revised): presenters replace
      // image data in place, so animation never churns placements and never
      // opens the deleted-old/undecoded-new gap that flickered on Warp. The
      // revision is what tells the diff and the presenters that the pixels
      // changed.
      tester.pumpWidget(_app(CanvasMarker.pixels, _rasterCaps));
      final first = tester
          .render(size: const CellSize(12, 6))
          .imagePlacements
          .single;
      tester.pumpWidget(_app(CanvasMarker.pixels, _rasterCaps));
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
