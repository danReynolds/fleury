// Regression guard for terminal scroll rendering. Drives the REAL StorybookApp
// through the actual double-buffered frame loop + AnsiRenderer, applies every
// emitted escape to a spec-faithful model terminal that ACCUMULATES across
// frames (like a real terminal), and asserts the model matches the rendered
// buffer after every step — scrolling the whole widget list down and back up.
// A divergence means the diff clipped/skipped a cell and left it stale; the
// renderer's model would then agree with the terminal's wrong state and never
// recover (persistent garble).
//
// Written to chase a scroll-garble report in Warp. The model terminal here runs
// with autowrap ON (`autowrap: true`) — the stricter case: it models a terminal
// like Warp that wraps the cursor immediately on a last-column write (and ignores
// our DECAWM-off `\x1B[?7l`). The renderer must stay correct anyway, which it does
// by repositioning the cursor absolutely after any last-column or ambiguous-width
// write and on every row change (see ansi_renderer.dart `_cursorMove`). The real
// root cause of the reported garble turned out to be the diff's CROSS-ROW cursor
// moves: it used row-relative encodings (`\r\n`/CNL/CUU/CUD) that desync once the
// tracked row drifts from the terminal's, stranding tails. The renderer now uses
// an absolute CUP for cross-row moves, so this harness holds whether the terminal
// wraps or not.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:test/test.dart';

class _ModelTerminal {
  _ModelTerminal(this.cols, this.rows, {this.autowrap = false})
    : grid = List.generate(rows, (_) => List.filled(cols, ' '));

  final int cols;
  final int rows;
  // Models a terminal WITHOUT the VT100 `xenl` pending-wrap quirk: writing the
  // last column moves to the next line immediately (as Warp does). The renderer
  // must not rely on the cursor staying put after a last-column write.
  final bool autowrap;
  final List<List<String>> grid;
  int cr = 0;
  int cc = 0;

  void _put(String g) {
    if (cr >= 0 && cr < rows && cc >= 0 && cc < cols) grid[cr][cc] = g;
    if (autowrap && cc >= cols - 1) {
      cr += 1;
      cc = 0;
    } else {
      cc += 1;
    }
  }

  void apply(String out) {
    var i = 0;
    final n = out.length;
    while (i < n) {
      final cu = out.codeUnitAt(i);
      if (cu == 0x08) {
        cc -= 1;
        i++;
        continue;
      }
      if (cu == 0x0A) {
        cr += 1;
        i++;
        continue;
      }
      if (cu == 0x0D) {
        cc = 0;
        i++;
        continue;
      }
      if (cu != 0x1B) {
        _put(out[i]);
        i++;
        continue;
      }
      i++;
      if (i >= n) break;
      if (out.codeUnitAt(i) != 0x5B) {
        i++;
        continue;
      }
      i++;
      var private = false;
      if (i < n && out.codeUnitAt(i) == 0x3F) {
        private = true;
        i++;
      }
      final params = StringBuffer();
      var finalByte = 0;
      while (i < n) {
        final c = out.codeUnitAt(i);
        i++;
        if (c >= 0x40 && c <= 0x7E) {
          finalByte = c;
          break;
        }
        params.write(String.fromCharCode(c));
      }
      if (private) continue;
      final ps = params.toString().split(';');
      int p(int idx, int dflt) =>
          idx < ps.length ? (int.tryParse(ps[idx]) ?? dflt) : dflt;
      switch (finalByte) {
        case 0x48:
        case 0x66:
          cr = p(0, 1) - 1;
          cc = p(1, 1) - 1;
        case 0x41:
          cr -= p(0, 1);
        case 0x42:
          cr += p(0, 1);
        case 0x43:
          cc += p(0, 1);
        case 0x44:
          cc -= p(0, 1);
        case 0x45:
          cr += p(0, 1);
          cc = 0;
        case 0x46:
          cr -= p(0, 1);
          cc = 0;
        case 0x53:
          final k = p(0, 1);
          for (var s = 0; s < k; s++) {
            grid.removeAt(0);
            grid.add(List.filled(cols, ' '));
          }
        case 0x4A:
          if (p(0, 0) == 2) {
            for (final row in grid) {
              for (var c = 0; c < cols; c++) row[c] = ' ';
            }
          }
        case 0x4B:
          if (p(0, 0) == 0 && cr >= 0 && cr < rows) {
            for (var c = cc; c < cols; c++) grid[cr][c] = ' ';
          }
        default:
          break;
      }
    }
  }

  String rowText(int r) => grid[r].join().replaceAll(RegExp(r'\s+$'), '');
}

String _expected(CellBuffer b, int col, int row) {
  final cell = b.atColRow(col, row);
  if (cell.role == CellRole.continuation) return ' ';
  return cell.grapheme ?? ' ';
}

void main() {
  testWidgets('widget-list scroll leaves no stale cells on the terminal', (
    tester,
  ) async {
    tester.pumpWidget(StorybookApp());
    const size = CellSize(72, 48);

    final loop = TuiFrameLoop(renderDamage: tester.owner.renderDamageTracker);
    final renderer = AnsiRenderer(colorMode: ColorMode.truecolor);
    final term = _ModelTerminal(size.cols, size.rows, autowrap: true);
    final sink = StringAnsiSink();

    void present(String label) {
      tester.owner.flushBuild();
      final frame = loop.render(
        size: size,
        paint: (buf) => tester.owner.renderFrame(tester.root!, buf),
      )!;
      sink.clear();
      if (frame.damage.fullRepaint) sink.write('\x1B[2J\x1B[H');
      renderer.renderDiff(
        frame.previous,
        frame.next,
        sink,
        dirtyBounds: frame.damage.diffBounds,
      );
      term.apply(sink.output);
      for (var r = 0; r < size.rows; r++) {
        final expectedRow = [
          for (var c = 0; c < size.cols; c++) _expected(frame.next, c, r),
        ].join().replaceAll(RegExp(r'\s+$'), '');
        expect(
          term.rowText(r),
          expectedRow,
          reason:
              'terminal diverged from the rendered frame at row $r '
              'after "$label"\n'
              '  terminal: "${term.rowText(r)}"\n'
              '  rendered: "$expectedRow"',
        );
      }
      loop.commit(frame);
    }

    present('initial');
    // Fast scrolling coalesces several key presses into one rendered frame, so
    // the diff spans a multi-row jump. Drive batches of keys per frame, all the
    // way to the bottom and back — each rendered frame must stay in sync.
    for (var batch = 0; batch < 26; batch++) {
      for (var k = 0; k < 5; k++) {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      }
      present('down batch $batch');
    }
    for (var batch = 0; batch < 26; batch++) {
      for (var k = 0; k < 5; k++) {
        tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      }
      present('up batch $batch');
    }
  });
}
