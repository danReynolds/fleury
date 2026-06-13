// Transport parity: a frame rendered server-side must survive the wire
// and reproduce exactly on the client's mirror. The server builds a
// cell-patch plan from prev/next, it round-trips through encode/decode,
// and applying it to a mirror seeded with prev must reproduce next. This
// is the divergence-oracle pattern applied to the transport: the wire is
// lossless. The DOM rendering of the mirror is covered by the surface's
// own Chrome tests.

import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
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

/// Full pipeline: build plan from prev/next, encode, decode, apply to a
/// mirror seeded with prev. Returns the mirror.
CellBuffer _through(CellBuffer prev, CellBuffer next, {bool full = false}) {
  final plan = buildRemotePlan(prev, next, fullRepaint: full);
  final decoded = decodeRemotePlan(encodeRemotePlan(plan));
  final mirror = CellBuffer(next.size);
  _seed(prev, mirror);
  applyRemotePlanToBuffer(decoded, mirror);
  return mirror;
}

void main() {
  group('transport parity', () {
    test('ASCII edits reproduce on the mirror', () {
      final prev = CellBuffer(const CellSize(20, 3));
      prev.writeText(const CellOffset(0, 0), 'hello world');
      final next = CellBuffer(const CellSize(20, 3));
      _seed(prev, next);
      next.writeText(const CellOffset(0, 0), 'HELLO');
      next.writeText(const CellOffset(2, 1), 'indented');
      expect(_render(_through(prev, next)), _render(next));
    });

    test('shrinking text blanks the freed cells', () {
      final prev = CellBuffer(const CellSize(20, 1));
      prev.writeText(const CellOffset(0, 0), 'a long line of text');
      final next = CellBuffer(const CellSize(20, 1));
      next.writeText(const CellOffset(0, 0), 'short');
      expect(_render(_through(prev, next)), _render(next));
    });

    test('styled runs preserve style through the wire', () {
      final prev = CellBuffer(const CellSize(10, 1));
      final next = CellBuffer(const CellSize(10, 1));
      next.writeText(
        const CellOffset(0, 0),
        'red',
        style: const CellStyle(foreground: RgbColor(220, 40, 40), bold: true),
      );
      final plan = buildRemotePlan(prev, next, fullRepaint: false);
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      final mirror = CellBuffer(const CellSize(10, 1));
      applyRemotePlanToBuffer(decoded, mirror);
      expect(mirror.atColRow(0, 0).style.bold, isTrue);
      expect(mirror.atColRow(0, 0).style.foreground, const RgbColor(220, 40, 40));
    });

    test('wide glyphs reproduce with correct width', () {
      final prev = CellBuffer(const CellSize(10, 1));
      final next = CellBuffer(const CellSize(10, 1));
      next.writeText(const CellOffset(0, 0), '世界');
      final mirror = _through(prev, next);
      expect(mirror.atColRow(0, 0).grapheme, '世');
      expect(mirror.atColRow(1, 0).role, CellRole.continuation);
      expect(mirror.atColRow(2, 0).grapheme, '界');
    });

    test('randomized frame sequences reproduce exactly (seeded)', () {
      final rng = Random(0x9A11);
      const alphabet = 'abcdefghij 0123#@世界';
      for (var iter = 0; iter < 80; iter++) {
        final cols = 4 + rng.nextInt(40);
        final rows = 1 + rng.nextInt(12);
        var prev = CellBuffer(CellSize(cols, rows));
        // Play a short sequence of frames; the mirror tracks it.
        final mirror = CellBuffer(CellSize(cols, rows));
        for (var f = 0; f < 5; f++) {
          final next = CellBuffer(CellSize(cols, rows));
          _seed(prev, next);
          for (var m = 0; m < rng.nextInt(rows + 1); m++) {
            final r = rng.nextInt(rows);
            final n = rng.nextInt(cols);
            final text = [
              for (var i = 0; i < n; i++) alphabet[rng.nextInt(alphabet.length)],
            ].join();
            next.writeText(CellOffset(0, r), text, style: _style(rng));
          }
          final full = f == 0;
          final plan = buildRemotePlan(prev, next, fullRepaint: full);
          applyRemotePlanToBuffer(
            decodeRemotePlan(encodeRemotePlan(plan)),
            mirror,
          );
          expect(_render(mirror), _render(next), reason: 'iter $iter frame $f');
          prev = next;
        }
      }
    });

    test('input round-trips through the full framing layer', () {
      const events = <TuiEvent>[
        KeyEvent(keyCode: KeyCode.arrowUp, modifiers: {KeyModifier.ctrl}),
        TextInputEvent('hi'),
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 3,
          row: 5,
        ),
        PasteEvent('clip'),
        ResizeEvent(CellSize(120, 40)),
      ];
      for (final event in events) {
        final wire = encodeFrame(InputEventFrame(event));
        final out = (FrameDecoder()..feed(wire)).drain().toList();
        expect((out.single as InputEventFrame).event, event);
      }
    });
  });
}

CellStyle _style(Random rng) => switch (rng.nextInt(3)) {
  0 => CellStyle.empty,
  1 => const CellStyle(bold: true),
  _ => CellStyle(foreground: RgbColor(rng.nextInt(256), 0, 0)),
};
