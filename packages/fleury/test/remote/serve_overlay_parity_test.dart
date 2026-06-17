// Divergence-oracle coverage for the scenarios the dialog "screen clears"
// blank correlates with — an overlay box appearing/disappearing over content,
// a sub-region (single-pane) scroll while the rest of the screen stays put,
// and long randomized sequences mixing all three. Each frame's plan is built,
// round-tripped through the wire, applied to a tracked mirror, and the mirror
// must reproduce `next` exactly. If the retained diff has an edge case in any
// of these, the mirror diverges here deterministically.

import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:test/test.dart';

String _render(CellBuffer b) {
  final sb = StringBuffer();
  for (var r = 0; r < b.size.rows; r++) {
    for (var c = 0; c < b.size.cols; c++) {
      sb.write(b.atColRow(c, r).grapheme ?? ' ');
    }
    sb.write('|');
  }
  return sb.toString();
}

void _seed(CellBuffer from, CellBuffer to) {
  for (var r = 0; r < from.size.rows; r++) {
    for (var c = 0; c < from.size.cols; c++) {
      final cell = from.atColRow(c, r);
      if (cell.role == CellRole.leading && cell.grapheme != null) {
        to.writeText(CellOffset(c, r), cell.grapheme!, style: cell.style);
      }
    }
  }
}

/// Applies the wire round-trip of (prev → next) to [mirror] in place, the way
/// the client does across a session.
void _apply(CellBuffer prev, CellBuffer next, CellBuffer mirror,
    {bool full = false}) {
  final plan = buildRemotePlan(prev, next, fullRepaint: full);
  applyRemotePlanToBuffer(decodeRemotePlan(encodeRemotePlan(plan)), mirror);
}

/// A full-screen storybook-ish background: three bordered panes side by side,
/// each with rows of text, so a per-pane scroll moves only part of the screen.
CellBuffer _background(CellSize size, int phase) {
  final b = CellBuffer(size);
  for (var r = 0; r < size.rows; r++) {
    b.writeText(CellOffset(0, r), '│ left ${(r + phase) % 40} ');
    b.writeText(CellOffset(size.cols ~/ 2, r), '│ preview row $r static │');
  }
  return b;
}

/// Draws a centered box (a dialog/palette) over [base], returning a new buffer.
CellBuffer _withOverlay(CellBuffer base, {required int boxW, required int boxH}) {
  final out = CellBuffer(base.size);
  _seed(base, out);
  final left = (base.size.cols - boxW) ~/ 2;
  final top = (base.size.rows - boxH) ~/ 2;
  for (var r = 0; r < boxH; r++) {
    final row = top + r;
    if (row < 0 || row >= base.size.rows) continue;
    final isEdge = r == 0 || r == boxH - 1;
    final line = isEdge
        ? '+${'-' * (boxW - 2)}+'
        : '|${' command $r'.padRight(boxW - 2).substring(0, boxW - 2)}|';
    out.writeText(CellOffset(left, row), line,
        style: const CellStyle(bold: true));
  }
  return out;
}

void main() {
  group('overlay + region-scroll parity', () {
    const size = CellSize(80, 24);

    test('an overlay box appearing over content reproduces on the mirror', () {
      final prev = _background(size, 0);
      final next = _withOverlay(prev, boxW: 30, boxH: 8);
      final mirror = CellBuffer(size);
      _seed(prev, mirror);
      _apply(prev, next, mirror);
      expect(_render(mirror), _render(next), reason: 'overlay open');
    });

    test('an overlay box disappearing restores the content beneath', () {
      final base = _background(size, 0);
      final withBox = _withOverlay(base, boxW: 30, boxH: 8);
      final mirror = CellBuffer(size);
      _seed(base, mirror);
      _apply(base, withBox, mirror); // open
      expect(_render(mirror), _render(withBox));
      _apply(withBox, base, mirror); // close (pop) — content must come back
      expect(_render(mirror), _render(base), reason: 'overlay closed');
    });

    test('a single-pane scroll leaves the other panes intact', () {
      final prev = _background(size, 0);
      final next = _background(size, 1); // left pane "scrolled" one step
      final mirror = CellBuffer(size);
      _seed(prev, mirror);
      _apply(prev, next, mirror);
      expect(_render(mirror), _render(next), reason: 'region scroll');
    });

    test('a long randomized stream of scrolls + overlay toggles stays in sync',
        () {
      final rng = Random(0xD1A106);
      var prev = _background(size, 0);
      final mirror = CellBuffer(size);
      _seed(prev, mirror);
      var phase = 0;
      var overlayOpen = false;
      for (var frame = 0; frame < 400; frame++) {
        final action = rng.nextInt(3);
        CellBuffer next;
        switch (action) {
          case 0: // advance the scrolling pane
            phase += 1 + rng.nextInt(3);
            next = _background(size, phase);
            if (overlayOpen) {
              next = _withOverlay(next, boxW: 24 + rng.nextInt(20), boxH: 6);
            }
          case 1: // toggle the overlay
            overlayOpen = !overlayOpen;
            final bg = _background(size, phase);
            next = overlayOpen
                ? _withOverlay(bg, boxW: 24 + rng.nextInt(20), boxH: 6)
                : bg;
          default: // edit a few cells
            next = CellBuffer(size);
            _seed(prev, next);
            for (var e = 0; e < 1 + rng.nextInt(4); e++) {
              next.writeText(
                CellOffset(rng.nextInt(size.cols ~/ 2), rng.nextInt(size.rows)),
                'x${rng.nextInt(99)}',
              );
            }
        }
        _apply(prev, next, mirror, full: frame == 0);
        expect(_render(mirror), _render(next), reason: 'frame $frame');
        prev = next;
      }
    });
  });
}
