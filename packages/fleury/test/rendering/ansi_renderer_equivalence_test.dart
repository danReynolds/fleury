// Output-equivalence proof for the cursor-move encoding in AnsiRenderer.
//
// The cursor optimization changes the BYTES emitted (absolute CSI…H ->
// relative CSI…C/D and omitted-default forms) but must not change the RENDERED
// RESULT. This test proves that property directly: it interprets the emitted
// diff with a minimal terminal model, applied to the `previous` frame, and
// asserts the result equals the `next` frame — across hundreds of randomized
// frame pairs plus the structural edge cases the encoder special-cases.
//
// Scope: graphemes and positions. SGR/style bytes are ignored because they do
// not place content; exact-byte golden tests in ansi_renderer_test.dart pin
// style encoding separately. Content is single-width ASCII here so the
// interpreter needs no width model; wide-grapheme cursor advance is covered by
// the golden tests.

import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A minimal terminal: tracks the cursor and writes single-width graphemes,
/// understanding exactly the escapes AnsiRenderer emits (CUP `H`, CUU/CUD
/// `A`/`B`, CUF/CUB `C`/`D`, CNL/CPL `E`/`F`, SU `S`; SGR `m` and private
/// modes `?…h/l` are ignored as they don't move the cursor or place content).
List<List<String>> _apply(List<List<String>> start, String output) {
  final grid = [
    for (final row in start) [...row],
  ];
  final rows = grid.length;
  final cols = rows == 0 ? 0 : grid[0].length;
  var cr = 0;
  var cc = 0;

  var i = 0;
  final n = output.length;
  while (i < n) {
    final cu = output.codeUnitAt(i);
    if (cu == 0x1B) {
      i++;
      if (i >= n || output.codeUnitAt(i) != 0x5B) {
        continue; // not a CSI; nothing this renderer emits
      }
      i++; // '['
      var private = false;
      if (i < n && output.codeUnitAt(i) == 0x3F) {
        private = true;
        i++;
      }
      final params = StringBuffer();
      var finalByte = 0;
      while (i < n) {
        final c = output.codeUnitAt(i);
        i++;
        if (c >= 0x40 && c <= 0x7E) {
          finalByte = c;
          break;
        }
        params.writeCharCode(c);
      }
      if (private) continue; // mode set/reset (e.g. synchronized output)
      final ps = params.toString();
      switch (finalByte) {
        case 0x48: // 'H' — CUP (1-indexed; omitted params default to 1)
          final parts = ps.isEmpty ? const <String>[] : ps.split(';');
          final r =
              (parts.isNotEmpty && parts[0].isNotEmpty
                  ? int.parse(parts[0])
                  : 1) -
              1;
          final c =
              (parts.length > 1 && parts[1].isNotEmpty
                  ? int.parse(parts[1])
                  : 1) -
              1;
          cr = r;
          cc = c;
        case 0x41: // 'A' — CUU (omitted -> 1)
          cr -= ps.isEmpty ? 1 : int.parse(ps);
        case 0x42: // 'B' — CUD (omitted -> 1)
          cr += ps.isEmpty ? 1 : int.parse(ps);
        case 0x43: // 'C' — CUF (omitted -> 1)
          cc += ps.isEmpty ? 1 : int.parse(ps);
        case 0x44: // 'D' — CUB (omitted -> 1)
          cc -= ps.isEmpty ? 1 : int.parse(ps);
        case 0x45: // 'E' — CNL (omitted -> 1)
          cr += ps.isEmpty ? 1 : int.parse(ps);
          cc = 0;
        case 0x46: // 'F' — CPL (omitted -> 1)
          cr -= ps.isEmpty ? 1 : int.parse(ps);
          cc = 0;
        case 0x53: // 'S' — SU/scroll up (omitted -> 1)
          final count = ps.isEmpty ? 1 : int.parse(ps);
          for (var r = 0; r < rows; r++) {
            if (r + count < rows) {
              grid[r] = [...grid[r + count]];
            } else {
              grid[r] = List<String>.filled(cols, ' ');
            }
          }
        case 0x6D: // 'm' — SGR, ignored
          break;
        default:
          break;
      }
      continue;
    }
    // Printable single-width grapheme.
    final g = String.fromCharCode(cu);
    if (cr >= 0 && cr < rows && cc >= 0 && cc < cols) {
      grid[cr][cc] = g;
    }
    cc++;
    i++;
  }
  return grid;
}

/// Grapheme grid for a buffer; empty cells read as a space (which is what the
/// renderer writes for a dirtied empty cell).
List<List<String>> _gridOf(CellBuffer buffer) {
  final size = buffer.size;
  return [
    for (var r = 0; r < size.rows; r++)
      [
        for (var c = 0; c < size.cols; c++)
          buffer.atColRow(c, r).grapheme ?? ' ',
      ],
  ];
}

CellBuffer _randomAsciiBuffer(Random rng, int cols, int rows) {
  final buffer = CellBuffer(CellSize(cols, rows));
  const alphabet = 'abcdefgh ';
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final ch = alphabet[rng.nextInt(alphabet.length)];
      if (ch != ' ') buffer.writeText(CellOffset(c, r), ch);
    }
  }
  return buffer;
}

void main() {
  group('AnsiRenderer cursor encoding — output equivalence', () {
    test('diff applied to previous reproduces next (300 random frames)', () {
      final rng = Random(0xC0FFEE);
      const cols = 14;
      const rows = 6;
      for (var trial = 0; trial < 300; trial++) {
        final prev = _randomAsciiBuffer(rng, cols, rows);
        final next = _randomAsciiBuffer(rng, cols, rows);
        final sink = StringAnsiSink();
        const AnsiRenderer().renderDiff(prev, next, sink);
        final result = _apply(_gridOf(prev), sink.output);
        expect(
          result,
          equals(_gridOf(next)),
          reason: 'trial $trial: diff did not reproduce next frame',
        );
      }
    });

    test('structural edge cases reproduce next exactly', () {
      // Same-row gaps (relative forward), multi-row jumps, backward moves,
      // full-row rewrites, and clears all land content correctly.
      final cases = <void Function(CellBuffer prev, CellBuffer next)>[
        // same-row gap -> CUF
        (p, n) {
          n.writeText(const CellOffset(0, 0), 'a');
          n.writeText(const CellOffset(5, 0), 'b');
          n.writeText(const CellOffset(9, 0), 'c');
        },
        // multi-row, varying columns
        (p, n) {
          n.writeText(const CellOffset(3, 0), 'x');
          n.writeText(const CellOffset(0, 2), 'y');
          n.writeText(const CellOffset(7, 4), 'z');
        },
        // overwrite + clear (prev has content next removes)
        (p, n) {
          p.writeText(const CellOffset(2, 1), 'old');
          n.writeText(const CellOffset(2, 1), 'n');
        },
        // full row
        (p, n) {
          n.writeText(const CellOffset(0, 3), 'full row content!!');
        },
      ];
      for (var i = 0; i < cases.length; i++) {
        final prev = CellBuffer(const CellSize(20, 6));
        final next = CellBuffer(const CellSize(20, 6));
        cases[i](prev, next);
        // The diff is computed against the actual prev, so seed prev's own
        // mutations into next's starting grid via a fresh render baseline.
        final sink = StringAnsiSink();
        const AnsiRenderer().renderDiff(prev, next, sink);
        final result = _apply(_gridOf(prev), sink.output);
        expect(result, equals(_gridOf(next)), reason: 'edge case $i');
      }
    });

    test('the interpreter itself is not trivially passing', () {
      // Guard: if the renderer mis-positioned content, _apply would catch it.
      // Prove _apply distinguishes a wrong frame.
      final prev = CellBuffer(const CellSize(6, 2));
      final next = CellBuffer(const CellSize(6, 2));
      next.writeText(const CellOffset(1, 0), 'hi');
      final sink = StringAnsiSink();
      const AnsiRenderer().renderDiff(prev, next, sink);
      final wrong = CellBuffer(const CellSize(6, 2));
      wrong.writeText(const CellOffset(0, 0), 'hi'); // different position
      expect(_apply(_gridOf(prev), sink.output), isNot(equals(_gridOf(wrong))));
    });
  });
}
