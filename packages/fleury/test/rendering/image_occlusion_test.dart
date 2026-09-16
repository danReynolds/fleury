import 'dart:typed_data';
import 'package:fleury/fleury_core.dart';
import 'package:fleury/src/rendering/cell_span.dart';
import 'package:test/test.dart';

Set<(int, int)> covered(CellBuffer buffer) => {
  for (final p in buffer.visibleImagePlacements)
    for (var y = p.row; y < p.row + p.rows; y++)
      for (var x = p.col; x < p.col + p.cols; x++) (x, y),
};

void main() {
  test('changed image holes invalidate an otherwise identical cell grid', () {
    CellBuffer frame({required bool covered}) {
      final buffer = CellBuffer(const CellSize(6, 4));
      buffer.writeImage(
        CellOffset.zero,
        Uint8List.fromList([1]),
        width: 6,
        height: 4,
      );
      if (covered) {
        buffer.fillRect(CellRect.fromLTWH(1, 1, 2, 2));
      }
      // This later image may contain transparent pixels. Its cell roles hide
      // the earlier opaque cover, but the older image must retain that hole.
      buffer.writeImage(
        const CellOffset(1, 1),
        Uint8List.fromList([2]),
        width: 2,
        height: 2,
      );
      return buffer;
    }

    final before = frame(covered: true), after = frame(covered: false);
    expect(after.imagePlacements, before.imagePlacements);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 6; col++) {
        expect(after.atColRow(col, row), before.atColRow(col, row));
      }
    }
    expect(after.visibleImagePlacements, isNot(before.visibleImagePlacements));
    expect(after.diffAgainst(before).bounds, isNotNull);
    expect(before.diffAgainst(after).bounds, isNotNull);
    expect(after.diffAgainst(frame(covered: false)).bounds, isNull);
  });

  CellBuffer scene() {
    final buffer = CellBuffer(const CellSize(12, 8));
    buffer.writeImage(
      const CellOffset(1, 1),
      Uint8List.fromList([1, 2]),
      width: 10,
      height: 6,
    );
    for (var y = 2; y < 5; y++) {
      for (var x = 3; x < 8; x++) {
        buffer.writeGrapheme(CellOffset(x, y), ' ');
      }
    }
    buffer.writeText(const CellOffset(4, 3), 'Edit');
    return buffer;
  }

  test(
    'later popup text and spaces occlude images without changing image fit',
    () {
      final buffer = scene();
      final expected = {
        for (var y = 1; y < 7; y++)
          for (var x = 1; x < 11; x++)
            if (!(x >= 3 && x < 8 && y >= 2 && y < 5)) (x, y),
      };
      expect(covered(buffer), expected);
      expect(buffer.visibleImagePlacements.length, 4);
      for (final p in buffer.visibleImagePlacements) {
        expect((p.boxCols, p.boxRows), (10, 6));
        expect((p.boxOffsetCol, p.boxOffsetRow), (p.col - 1, p.row - 1));
      }
    },
  );
  test('scratch composition preserves the popup and its image holes', () {
    final source = scene(), destination = CellBuffer(const CellSize(12, 8));
    destination.copyRectFrom(
      source,
      CellRect.fromLTWH(0, 0, 12, 8),
      CellOffset.zero,
    );
    destination.compositeImagesFrom(source, CellOffset.zero);
    expect(covered(destination), covered(source));
    expect(destination.atColRow(4, 3).grapheme, 'E');
    expect(destination.atColRow(3, 2).role, isNot(CellRole.overlay));
  });
  test(
    'fully covered images disappear, repainting an image restores its placement',
    () {
      final buffer = scene();
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 12; x++) {
          buffer.writeGrapheme(CellOffset(x, y), ' ');
        }
      }
      expect(buffer.visibleImagePlacements, isEmpty);
      buffer.writeImage(
        const CellOffset(2, 2),
        Uint8List.fromList([3]),
        width: 2,
        height: 2,
      );
      expect(covered(buffer), {(2, 2), (3, 2), (2, 3), (3, 3)});
      expect(
        buffer.visibleImagePlacements,
        hasLength(1),
        reason: 'must not resurrect the old image behind the new one',
      );
    },
  );
  test(
    'image backgrounds survive letterboxing, scratch copies, and theme changes',
    () {
      CellBuffer image(Color background) {
        final buffer = CellBuffer(const CellSize(6, 4));
        buffer.fillRect(
          CellRect.fromLTWH(0, 0, 6, 4),
          style: CellStyle(background: background),
        );
        buffer.writeImage(
          CellOffset.zero,
          Uint8List.fromList([1]),
          width: 6,
          height: 4,
        );
        return buffer;
      }

      const dark = RgbColor(18, 24, 32), light = RgbColor(250, 250, 252);
      final before = image(dark), after = image(light);
      expect(after.atColRow(0, 0).style.background, light);
      final cropped = CellBuffer(const CellSize(3, 2));
      cropped.compositeImageRectFrom(
        after,
        CellRect.fromLTWH(1, 1, 3, 2),
        CellOffset.zero,
      );
      expect(cropped.atColRow(0, 0).style.background, light);
      final domRow = const CellSpanBuilder().buildRow(cropped, 0);
      expect(domRow.runs.single.style.background, light);
      final sink = StringAnsiSink();
      AnsiRenderer().renderDiff(before, after, sink);
      expect(sink.output, contains('48;2;250;250;252'));
    },
  );
  test(
    'a cached image without a background inherits the newly painted parent',
    () {
      final cache = CellBuffer(const CellSize(6, 4));
      cache.writeImage(
        CellOffset.zero,
        Uint8List.fromList([1]),
        width: 6,
        height: 4,
      );
      for (final background in [
        const RgbColor(18, 24, 32),
        const RgbColor(250, 250, 252),
      ]) {
        final parent = CellBuffer(const CellSize(6, 4));
        parent.fillRect(
          CellRect.fromLTWH(0, 0, 6, 4),
          style: CellStyle(background: background),
        );
        parent.compositeImagesFrom(cache, CellOffset.zero);
        expect(parent.atColRow(0, 0).style.background, background);
        final copied = CellBuffer(const CellSize(6, 4));
        copied.fillRect(
          CellRect.fromLTWH(0, 0, 6, 4),
          style: CellStyle(background: background),
        );
        copied.copyFrom(cache, CellOffset.zero);
        expect(copied.atColRow(0, 0).style.background, background);
      }
    },
  );
}
