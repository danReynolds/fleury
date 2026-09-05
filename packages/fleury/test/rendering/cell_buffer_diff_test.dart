import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  test(
    'exact diff matches cell equality across repeated and changing runs',
    () {
      const size = CellSize(48, 8);
      const rect = CellRect(offset: CellOffset.zero, size: size);
      CellBuffer paint(int seed) {
        final random = Random(seed);
        // Separate allocations in each buffer deliberately compare by value.
        final styles = [
          CellStyle(background: RgbColor(10, 20, 30)),
          CellStyle(background: RgbColor(10, 20, 30), bold: false),
          CellStyle(foreground: AnsiColor(3), bold: true, underline: true),
          CellStyle(linkUri: 'https://example.test/a'),
          CellStyle(linkUri: 'https://example.test/b'),
          CellStyle(
            dim: true,
            italic: true,
            inverse: false,
            strikethrough: true,
          ),
        ];
        final buffer = CellBuffer(size)..fillRect(rect, style: styles.first);
        for (var i = 0; i < 30; i++) {
          final col = random.nextInt(size.cols);
          final row = random.nextInt(size.rows);
          final style = styles[random.nextInt(styles.length)];
          if (i.isEven) {
            buffer.fillRect(
              CellRect.fromLTWH(col, row, random.nextInt(30), 1),
              style: style,
            );
          } else {
            buffer.writeText(CellOffset(col, row), 'a界b🙂', style: style);
          }
        }
        return buffer;
      }

      void check(CellBuffer next, CellBuffer previous, String reason) {
        final expectedRows = <int>{};
        var count = 0;
        var left = size.cols;
        var right = 0;
        var top = size.rows;
        var bottom = 0;
        for (var row = 0; row < size.rows; row++) {
          for (var col = 0; col < size.cols; col++) {
            if (next.atColRow(col, row) == previous.atColRow(col, row)) {
              continue;
            }
            count++;
            expectedRows.add(row);
            left = min(left, col);
            right = max(right, col + 1);
            top = min(top, row);
            bottom = max(bottom, row + 1);
          }
        }
        final actual = next.diffAgainst(previous);
        expect(actual.isComparable, isTrue, reason: reason);
        expect(actual.dirtyCells, count, reason: reason);
        expect(actual.rows, expectedRows, reason: reason);
        expect(
          actual.bounds,
          count == 0
              ? null
              : CellRect.fromLTWH(left, top, right - left, bottom - top),
          reason: reason,
        );
      }

      for (var seed = 0; seed < 1000; seed++) {
        final previous = paint(seed);
        final next = seed.isEven
            ? paint(seed)
            : (CellBuffer(size)..copyRectFrom(previous, rect, CellOffset.zero));
        check(next, previous, 'seed $seed, unchanged');
        final random = Random(seed + 1000);
        for (var mutation = 0; mutation < 5; mutation++) {
          final col = random.nextInt(size.cols);
          final row = random.nextInt(size.rows);
          next.writeText(
            CellOffset(col, row),
            mutation.isEven ? '界' : 'x',
            style: CellStyle(linkUri: 'https://example.test/$mutation'),
          );
          check(next, previous, 'seed $seed, mutation $mutation');
          check(previous, next, 'seed $seed, reverse $mutation');
        }
      }
    },
  );

  test(
    'an equal run cannot hide later role, style, or hyperlink differences',
    () {
      const size = CellSize(12, 2);
      const rect = CellRect(offset: CellOffset.zero, size: size);
      final before = CellBuffer(size)
        ..fillRect(rect, style: CellStyle(bold: false));
      final after = CellBuffer(size)
        ..fillRect(rect, style: CellStyle(bold: false));
      expect(after.diffAgainst(before).isUnchanged, isTrue);
      after.restyleCell(
        3,
        0,
        const CellStyle(),
      ); // Explicit false versus absent.
      after.restyleCell(
        5,
        0,
        const CellStyle(bold: false, linkUri: 'https://a.test'),
      );
      after.writeGrapheme(const CellOffset(9, 1), '界');
      final diff = after.diffAgainst(before);
      expect(diff.dirtyCells, 4);
      expect(diff.rows, {0, 1});
      expect(diff.bounds, CellRect.fromLTWH(3, 0, 8, 2));
      after.clear();
      before.clear();
      expect(after.diffAgainst(before).isUnchanged, isTrue);
    },
  );
}
