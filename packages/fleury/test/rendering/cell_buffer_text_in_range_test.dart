// CellBuffer.textInRange — the Notcurses-style primitive that backs
// both the public "read painted UTF-8 from a region" API and the
// fallback path of the selection system.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

CellBuffer _bufferWith(String src) {
  // Build a buffer by painting each row of src as a single row of cells.
  // 'src' rows separated by '\n'. Each character becomes one cell (no
  // wide-grapheme handling — those tests construct the buffer manually).
  final rows = src.split('\n');
  final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  final buf = CellBuffer(CellSize(cols, rows.length));
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final ch = rows[r][c];
      if (ch == ' ') continue;
      buf.writeGrapheme(CellOffset(c, r), ch);
    }
  }
  return buf;
}

void main() {
  group('textInRange — basic cases', () {
    test('extracts a single row', () {
      final buf = _bufferWith('hello');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
      );
      expect(out, 'hello');
    });

    test('extracts a column slice across multiple rows', () {
      final buf = _bufferWith('hello\nworld');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(1, 0), size: CellSize(3, 2)),
      );
      expect(out, 'ell\norl');
    });

    test('empty cells render as space', () {
      final buf = _bufferWith('a b');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(0, 0), size: CellSize(3, 1)),
      );
      expect(out, 'a b');
    });

    test('preserves trailing whitespace within the rect', () {
      final buf = _bufferWith('hi   ');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
      );
      expect(out, 'hi   ');
    });

    test('joins rows with a single newline', () {
      final buf = _bufferWith('ab\ncd\nef');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(0, 0), size: CellSize(2, 3)),
      );
      expect(out, 'ab\ncd\nef');
    });
  });

  group('textInRange — clipping', () {
    test('a rect extending past the right edge clips silently', () {
      final buf = _bufferWith('abc');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(1, 0), size: CellSize(10, 1)),
      );
      expect(out, 'bc');
    });

    test('a rect extending past the bottom clips silently', () {
      final buf = _bufferWith('a\nb');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(0, 0), size: CellSize(1, 10)),
      );
      expect(out, 'a\nb');
    });

    test('a rect with a negative offset clips to the buffer origin', () {
      final buf = _bufferWith('abc');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(-5, -5), size: CellSize(8, 6)),
      );
      expect(out, 'abc');
    });

    test('a rect entirely outside the buffer returns empty', () {
      final buf = _bufferWith('abc');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(100, 100), size: CellSize(5, 5)),
      );
      expect(out, isEmpty);
    });

    test('a zero-area rect returns empty', () {
      final buf = _bufferWith('abc');
      final out = buf.textInRange(
        const CellRect(offset: CellOffset(0, 0), size: CellSize(0, 5)),
      );
      expect(out, isEmpty);
    });
  });

  group('textInRange — wide-grapheme handling', () {
    test(
      'a wide grapheme contributes its grapheme at the leading cell only',
      () {
        // '中' is width 2 — leading at col 0, continuation at col 1.
        final buf = CellBuffer(const CellSize(4, 1));
        buf.writeGrapheme(const CellOffset(0, 0), '中');
        buf.writeGrapheme(const CellOffset(2, 0), 'x');
        final out = buf.textInRange(
          const CellRect(offset: CellOffset(0, 0), size: CellSize(4, 1)),
        );
        // Continuation cell at col 1 contributes nothing; col 3 is empty.
        expect(out, '中x ');
      },
    );

    test(
      'a rect starting at a continuation cell does NOT emit the lead grapheme',
      () {
        final buf = CellBuffer(const CellSize(4, 1));
        buf.writeGrapheme(const CellOffset(0, 0), '中');
        buf.writeGrapheme(const CellOffset(2, 0), 'x');
        // Start at col 1 — that's the continuation, which contributes nothing,
        // so only 'x' and the trailing empty come back.
        final out = buf.textInRange(
          const CellRect(offset: CellOffset(1, 0), size: CellSize(3, 1)),
        );
        expect(out, 'x ');
      },
    );
  });
}
