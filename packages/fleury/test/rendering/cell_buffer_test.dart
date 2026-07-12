import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('Construction and access', () {
    test('new buffer is filled with Cell.empty', () {
      final buf = CellBuffer(const CellSize(3, 2));
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 3; col++) {
          expect(buf.atColRow(col, row), const Cell.empty());
        }
      }
    });

    test('out-of-bounds reads throw RangeError', () {
      final buf = CellBuffer(const CellSize(2, 2));
      expect(() => buf.atColRow(2, 0), throwsA(isA<RangeError>()));
      expect(() => buf.atColRow(0, 2), throwsA(isA<RangeError>()));
      expect(() => buf.atColRow(-1, 0), throwsA(isA<RangeError>()));
    });

    test('clear restores every cell to empty', () {
      final buf = CellBuffer(const CellSize(3, 1));
      buf.writeGrapheme(const CellOffset(0, 0), 'A');
      buf.writeGrapheme(const CellOffset(1, 0), 'B');
      buf.clear();
      for (var col = 0; col < 3; col++) {
        expect(buf.atColRow(col, 0), const Cell.empty());
      }
    });

    test('resize discards content', () {
      final buf = CellBuffer(const CellSize(3, 1));
      buf.writeGrapheme(const CellOffset(0, 0), 'A');
      buf.resize(const CellSize(2, 2));
      expect(buf.size, const CellSize(2, 2));
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 2; col++) {
          expect(buf.atColRow(col, row), const Cell.empty());
        }
      }
    });
  });

  group('Damage tracking', () {
    test('is disabled until resetDamageTracking starts it', () {
      final buf = CellBuffer(const CellSize(3, 1));

      buf.writeGrapheme(const CellOffset(0, 0), 'X');

      expect(buf.damageBounds, isNull);
    });

    test('records conservative bounds for grapheme writes', () {
      final buf = CellBuffer(const CellSize(5, 2));
      buf.resetDamageTracking();

      buf.writeGrapheme(const CellOffset(2, 1), 'X');

      expect(buf.damageBounds, CellRect.fromLTWH(1, 1, 3, 1));
      expect(buf.takeDamageBounds(), CellRect.fromLTWH(1, 1, 3, 1));
      expect(buf.damageBounds, isNull);
    });

    test('records full buffer damage for clear', () {
      final buf = CellBuffer(const CellSize(3, 2));
      buf.resetDamageTracking();

      buf.clear();

      expect(buf.damageBounds, CellRect.fromLTWH(0, 0, 3, 2));
    });

    test('records clipped destination bounds for rect copies', () {
      final source = CellBuffer(const CellSize(4, 2))
        ..writeText(const CellOffset(0, 0), 'abcd')
        ..writeText(const CellOffset(0, 1), 'efgh');
      final dest = CellBuffer(const CellSize(5, 2));
      dest.resetDamageTracking();

      dest.copyRectFrom(
        source,
        CellRect.fromLTWH(1, 0, 3, 2),
        const CellOffset(3, 0),
      );

      expect(dest.damageBounds, CellRect.fromLTWH(3, 0, 2, 2));
    });

    test('suppresses damage inside withoutDamageTracking', () {
      final source = CellBuffer(const CellSize(2, 1))
        ..writeText(const CellOffset(0, 0), 'ab');
      final dest = CellBuffer(const CellSize(2, 1));
      dest.resetDamageTracking();

      dest.withoutDamageTracking(() {
        dest.copyFrom(source, CellOffset.zero);
      });

      expect(dest.damageBounds, isNull);
      expect(dest.atColRow(0, 0).grapheme, 'a');
      expect(dest.atColRow(1, 0).grapheme, 'b');
    });
  });

  group('Narrow graphemes', () {
    test('writes a single-column ASCII grapheme as a leading cell', () {
      final buf = CellBuffer(const CellSize(3, 1));
      final advanced = buf.writeGrapheme(const CellOffset(0, 0), 'X');
      expect(advanced, 1);
      expect(buf.atColRow(0, 0), const Cell.leading(grapheme: 'X'));
      expect(buf.atColRow(1, 0), const Cell.empty());
    });

    test('writeText advances through narrow ASCII clusters', () {
      final buf = CellBuffer(const CellSize(5, 1));
      final advanced = buf.writeText(const CellOffset(0, 0), 'hello');
      expect(advanced, 5);
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(4, 0).grapheme, 'o');
    });

    test('writeText stops at the right edge instead of overflowing', () {
      final buf = CellBuffer(const CellSize(3, 1));
      final advanced = buf.writeText(const CellOffset(0, 0), 'hello');
      expect(advanced, 3);
      expect(buf.atColRow(2, 0).grapheme, 'l');
    });

    test('out-of-bounds grapheme writes are clipped', () {
      final buf = CellBuffer(const CellSize(3, 1));
      expect(buf.writeGrapheme(const CellOffset(-1, 0), 'A'), 0);
      expect(buf.writeGrapheme(const CellOffset(0, -1), 'B'), 0);
      expect(buf.writeGrapheme(const CellOffset(3, 0), 'C'), 0);
      expect(buf.writeGrapheme(const CellOffset(0, 1), 'D'), 0);
      expect(buf.atColRow(0, 0), const Cell.empty());
      expect(buf.atColRow(2, 0), const Cell.empty());
    });

    test('writeText clips a negative starting column', () {
      final buf = CellBuffer(const CellSize(3, 1));
      final advanced = buf.writeText(const CellOffset(-2, 0), 'abcde');
      expect(advanced, 5);
      expect(buf.atColRow(0, 0).grapheme, 'c');
      expect(buf.atColRow(1, 0).grapheme, 'd');
      expect(buf.atColRow(2, 0).grapheme, 'e');
    });

    test('writeText clips rows outside the buffer', () {
      final buf = CellBuffer(const CellSize(3, 1));
      expect(buf.writeText(const CellOffset(0, -1), 'abc'), 0);
      expect(buf.writeText(const CellOffset(0, 1), 'abc'), 0);
      expect(buf.atColRow(0, 0), const Cell.empty());
    });
  });

  group('Wide graphemes', () {
    test('writes a CJK leading + continuation pair', () {
      final buf = CellBuffer(const CellSize(4, 1));
      final advanced = buf.writeGrapheme(const CellOffset(0, 0), '中');
      expect(advanced, 2);
      expect(buf.atColRow(0, 0), const Cell.leading(grapheme: '中'));
      expect(buf.atColRow(1, 0), const Cell.continuation());
    });

    test(
      'wide grapheme at the right edge collapses to a single-cell marker',
      () {
        final buf = CellBuffer(const CellSize(2, 1));
        // (col 1, row 0) — wide would need col 2 which doesn't exist.
        final advanced = buf.writeGrapheme(const CellOffset(1, 0), '中');
        expect(advanced, 1);
        expect(buf.atColRow(1, 0), const Cell.leading(grapheme: '?'));
      },
    );

    test('overwriting a wide leading clears its continuation', () {
      final buf = CellBuffer(const CellSize(3, 1));
      buf.writeGrapheme(
        const CellOffset(0, 0),
        '中',
      ); // leading@0, continuation@1
      buf.writeGrapheme(const CellOffset(0, 0), 'A'); // overwrite leading

      expect(buf.atColRow(0, 0), const Cell.leading(grapheme: 'A'));
      expect(
        buf.atColRow(1, 0),
        const Cell.empty(),
        reason: 'Orphaned continuation must be cleared.',
      );
    });

    test('writing over a continuation clears the leading to its left', () {
      final buf = CellBuffer(const CellSize(3, 1));
      buf.writeGrapheme(
        const CellOffset(0, 0),
        '中',
      ); // leading@0, continuation@1
      buf.writeGrapheme(const CellOffset(1, 0), 'A'); // overwrite continuation

      expect(
        buf.atColRow(0, 0),
        const Cell.empty(),
        reason:
            'Orphaned leading must be cleared when continuation is overwritten.',
      );
      expect(buf.atColRow(1, 0), const Cell.leading(grapheme: 'A'));
    });

    test('placing a wide grapheme over an adjacent wide one evicts both '
        'neighbors', () {
      final buf = CellBuffer(const CellSize(4, 1));
      buf.writeGrapheme(const CellOffset(0, 0), '中'); // L@0, C@1
      buf.writeGrapheme(const CellOffset(2, 0), '文'); // L@2, C@3
      // Place a wide grapheme starting at col 1 — it should replace
      // (col 1, col 2) with leading+continuation, evicting both wide
      // neighbors.
      buf.writeGrapheme(const CellOffset(1, 0), '日');

      expect(
        buf.atColRow(0, 0),
        const Cell.empty(),
        reason: '中 leading at col 0 lost its continuation; should be cleared.',
      );
      expect(buf.atColRow(1, 0), const Cell.leading(grapheme: '日'));
      expect(buf.atColRow(2, 0), const Cell.continuation());
      expect(
        buf.atColRow(3, 0),
        const Cell.empty(),
        reason: '文 continuation at col 3 lost its leading; should be cleared.',
      );
    });
  });

  group('Zero-width graphemes', () {
    test('combining mark alone advances zero columns', () {
      final buf = CellBuffer(const CellSize(3, 1));
      // U+0301 alone has width 0 per the resolver.
      final advanced = buf.writeGrapheme(const CellOffset(0, 0), '́');
      expect(advanced, 0);
      expect(
        buf.atColRow(0, 0),
        const Cell.empty(),
        reason: 'Zero-width clusters must not leave a leading cell.',
      );
    });
  });

  group('Mixed-width text', () {
    test('writeText interleaves narrow and wide correctly', () {
      final buf = CellBuffer(const CellSize(8, 1));
      final advanced = buf.writeText(const CellOffset(0, 0), 'hi 中文');
      // h(1) + i(1) + space(1) + 中(2) + 文(2) = 7
      expect(advanced, 7);
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(1, 0).grapheme, 'i');
      expect(buf.atColRow(2, 0).grapheme, ' ');
      expect(buf.atColRow(3, 0).grapheme, '中');
      expect(buf.atColRow(4, 0).role, CellRole.continuation);
      expect(buf.atColRow(5, 0).grapheme, '文');
      expect(buf.atColRow(6, 0).role, CellRole.continuation);
    });
  });

  group('Styles', () {
    test('style attaches to leading and continuation cells', () {
      final buf = CellBuffer(const CellSize(3, 1));
      const style = CellStyle(foreground: AnsiColor(2), bold: true);
      buf.writeGrapheme(const CellOffset(0, 0), '中', style: style);
      expect(buf.atColRow(0, 0).style, style);
      expect(
        buf.atColRow(1, 0).style,
        style,
        reason: 'Continuation cells inherit the leading cell\'s style.',
      );
    });
  });

  group('boundingBoxOfNonEmptyWithin', () {
    test('trims a padded damage hint to the tight non-empty bounds', () {
      // The repaint-boundary use: damage over a cleared buffer is a
      // conservative superset (grapheme writes pad the wide-cell guard
      // columns); the trim must converge on the same rect as the full scan.
      final buf = CellBuffer(const CellSize(10, 3));
      buf.resetDamageTracking();
      buf.writeText(const CellOffset(3, 1), 'ab');

      final damage = buf.takeDamageBounds();
      expect(damage, CellRect.fromLTWH(2, 1, 4, 1), reason: 'padded ±1 col');
      expect(
        buf.boundingBoxOfNonEmptyWithin(damage!),
        CellRect.fromLTWH(3, 1, 2, 1),
      );
      expect(
        buf.boundingBoxOfNonEmptyWithin(damage),
        buf.boundingBoxOfNonEmpty(),
        reason: 'same result as the full-grid scan',
      );
    });

    test('returns null for an all-empty hint region', () {
      final buf = CellBuffer(const CellSize(4, 2));
      buf.writeGrapheme(const CellOffset(3, 1), 'X');
      expect(
        buf.boundingBoxOfNonEmptyWithin(CellRect.fromLTWH(0, 0, 2, 2)),
        isNull,
      );
    });

    test('clamps an out-of-bounds hint to the grid', () {
      final buf = CellBuffer(const CellSize(4, 2));
      buf.writeGrapheme(const CellOffset(0, 0), 'X');
      expect(
        buf.boundingBoxOfNonEmptyWithin(CellRect.fromLTWH(-2, -2, 20, 20)),
        CellRect.fromLTWH(0, 0, 1, 1),
      );
    });
  });

  group('Overlay regions', () {
    test('an image whose top-left is out of bounds is dropped', () {
      final buf = CellBuffer(const CellSize(3, 1));
      final bytes = Uint8List.fromList([1]);
      buf.writeImage(const CellOffset(-1, 0), bytes, width: 2, height: 1);
      buf.writeImage(const CellOffset(0, -1), bytes, width: 2, height: 1);
      buf.writeImage(const CellOffset(3, 0), bytes, width: 2, height: 1);
      buf.writeImage(const CellOffset(0, 1), bytes, width: 2, height: 1);

      expect(buf.atColRow(0, 0), const Cell.empty());
      expect(buf.atColRow(2, 0), const Cell.empty());
      expect(buf.imagePlacements, isEmpty);
      expect(buf.images, isEmpty);
    });

    test('an in-bounds image covers its region with overlay cells', () {
      final buf = CellBuffer(const CellSize(3, 1));
      buf.writeImage(
        const CellOffset(1, 0),
        Uint8List.fromList([1]),
        width: 2,
        height: 1,
      );

      expect(buf.atColRow(0, 0), const Cell.empty());
      expect(buf.atColRow(1, 0), const Cell.overlay());
      expect(buf.atColRow(2, 0), const Cell.overlay());
    });
  });
}
