import 'dart:math';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/cell_buffer.dart' show applyCellBackground;
import 'package:test/test.dart';

void main() {
  test('bulk background matches per-cell composition and damage', () {
    final random = Random(905);
    const foreground = CellStyle(foreground: AnsiColor(6), bold: true);
    const explicit = CellStyle(background: AnsiColor(2), inverse: true);
    CellBuffer populated() => CellBuffer(const CellSize(8, 3))
      ..writeText(CellOffset.zero, 'a漢bc字', style: foreground)
      ..writeText(const CellOffset(0, 1), 'q界─ZZ', style: foreground)
      ..writeText(const CellOffset(0, 2), 'A字', style: explicit)
      ..writeText(const CellOffset(4, 2), 'xy', style: foreground)
      ..restyleCell(4, 0, explicit)
      ..writeImage(
        const CellOffset(4, 1),
        Uint8List.fromList([1]),
        width: 2,
        height: 1,
      )
      ..resetDamageTracking();
    for (var sample = 0; sample < 500; sample++) {
      final rect = CellRect.fromLTWH(
        random.nextInt(13) - 3,
        random.nextInt(7) - 2,
        random.nextInt(12),
        random.nextInt(7),
      );
      final color = AnsiColor(sample % 16);
      final actual = populated();
      final placements = actual.imagePlacements.toList();
      final images = Map.of(actual.images);
      final expected = populated();
      applyCellBackground(actual, rect, color);
      final fill = CellStyle(background: color);
      for (var row = rect.top; row < rect.bottom; row++) {
        for (var col = rect.left; col < rect.right; col++) {
          if (col < 0 || col >= 8 || row < 0 || row >= 3) continue;
          final cell = expected.atColRow(col, row);
          if (cell.role == CellRole.leading && cell.style.background == null) {
            expected.restyleCell(col, row, cell.style.merge(fill));
          }
        }
      }
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 8; col++) {
          expect(
            actual.atColRow(col, row),
            expected.atColRow(col, row),
            reason: '$rect, cell ($col, $row)',
          );
        }
      }
      expect(actual.damageBounds, expected.damageBounds, reason: '$rect');
      expect(actual.imagePlacements, placements);
      expect(actual.images, images);
    }
  });

  test('right-edge continuation receives the background and damage', () {
    final buffer = CellBuffer(const CellSize(4, 1))
      ..writeText(CellOffset.zero, 'a界')
      ..resetDamageTracking();
    applyCellBackground(
      buffer,
      CellRect.fromLTWH(1, 0, 1, 1),
      const AnsiColor(4),
    );
    expect(
      buffer.atColRow(1, 0).style,
      const CellStyle(background: AnsiColor(4)),
    );
    expect(buffer.atColRow(2, 0).style, buffer.atColRow(1, 0).style);
    expect(buffer.damageBounds, CellRect.fromLTWH(1, 0, 2, 1));
  });

  test('continuation-only clips and explicit backgrounds cause no damage', () {
    final buffer = CellBuffer(const CellSize(4, 1))
      ..writeText(CellOffset.zero, '界')
      ..writeText(
        const CellOffset(2, 0),
        'x',
        style: const CellStyle(background: AnsiColor(3)),
      )
      ..resetDamageTracking();
    applyCellBackground(
      buffer,
      CellRect.fromLTWH(1, 0, 3, 1),
      const AnsiColor(4),
    );
    expect(buffer.damageBounds, isNull);
    expect(buffer.atColRow(2, 0).style.background, const AnsiColor(3));
  });

  test('composition observes damage suppression', () {
    final buffer = CellBuffer(const CellSize(4, 1))
      ..writeText(CellOffset.zero, 'abc')
      ..resetDamageTracking();
    buffer.withoutDamageTracking(() {
      applyCellBackground(
        buffer,
        CellRect.fromLTWH(0, 0, 4, 1),
        const AnsiColor(4),
      );
    });
    expect(buffer.damageBounds, isNull);
    expect(buffer.atColRow(0, 0).style.background, const AnsiColor(4));
  });
}
