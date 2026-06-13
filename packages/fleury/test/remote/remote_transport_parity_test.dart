// Transport parity: a frame rendered server-side must survive the wire
// byte-exact. The server builds row span models from a CellBuffer (what
// the surface host does), encodes them as a PLAN frame, and the client
// decodes them back. This proves the structured serve path is lossless —
// the divergence-oracle pattern applied to the transport. The DOM
// rendering of those span models is covered by the surface's own
// Chrome tests; this proves the wire preserves exactly what the renderer
// produced.

import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:test/test.dart';

/// Flattens a row's spans back into a fixed-width line, the way the DOM
/// surface lays them out by column.
String _rowText(RowSpanModel row) {
  final cells = List<String>.filled(row.cols, ' ');
  for (final run in row.runs) {
    var col = run.startCol;
    // A run's text occupies widthCols columns; wide glyphs render in the
    // leading cell with the continuation cell empty (the surface pins width).
    final chars = run.text.runes.toList();
    if (run.widthCols == run.text.length || chars.length == run.widthCols) {
      for (final ch in chars) {
        if (col >= 0 && col < row.cols) cells[col] = String.fromCharCode(ch);
        col += 1;
      }
    } else {
      // Wide text: place the whole run at startCol.
      if (col >= 0 && col < row.cols) cells[col] = run.text;
    }
  }
  return cells.join();
}

List<RowSpanModel> _serverSpans(CellBuffer buffer) =>
    const CellSpanBuilder().buildFrame(buffer);

RemotePlan _roundTrip(RemotePlan plan) =>
    decodeRemotePlan(encodeRemotePlan(plan));

void main() {
  group('transport parity', () {
    test('ASCII content survives server spans -> wire -> client', () {
      final buffer = CellBuffer(const CellSize(20, 3));
      buffer.writeText(const CellOffset(0, 0), 'hello world');
      buffer.writeText(const CellOffset(2, 1), 'indented');

      final plan = RemotePlan(
        size: buffer.size,
        fullRepaint: true,
        rows: _serverSpans(buffer),
      );
      final decoded = _roundTrip(plan);

      for (var r = 0; r < buffer.size.rows; r++) {
        final wireRow = decoded.rows.firstWhere((row) => row.row == r);
        // Compare the wire-reconstructed row text against the buffer.
        final bufferRow = StringBuffer();
        for (var c = 0; c < buffer.size.cols; c++) {
          bufferRow.write(buffer.atColRow(c, r).grapheme ?? ' ');
        }
        expect(_rowText(wireRow), bufferRow.toString(), reason: 'row $r');
      }
    });

    test('styled content preserves style through the wire', () {
      final buffer = CellBuffer(const CellSize(10, 1));
      buffer.writeText(
        const CellOffset(0, 0),
        'red',
        style: const CellStyle(foreground: RgbColor(220, 40, 40), bold: true),
      );
      final plan = RemotePlan(
        size: buffer.size,
        fullRepaint: true,
        rows: _serverSpans(buffer),
      );
      final decoded = _roundTrip(plan);
      final firstRun = decoded.rows.single.runs.first;
      expect(firstRun.text, 'red');
      expect(firstRun.style.foreground, const RgbColor(220, 40, 40));
      expect(firstRun.style.bold, isTrue);
    });

    test('wide glyphs keep their cell width across the wire', () {
      final buffer = CellBuffer(const CellSize(10, 1));
      buffer.writeText(const CellOffset(0, 0), '世界'); // 2 wide glyphs
      final decoded = _roundTrip(
        RemotePlan(
          size: buffer.size,
          fullRepaint: true,
          rows: _serverSpans(buffer),
        ),
      );
      final wideRuns = decoded.rows.single.runs
          .where((r) => r.kind == CellRunKind.wideText)
          .toList();
      expect(wideRuns, hasLength(2));
      expect(wideRuns.every((r) => r.widthCols == 2), isTrue);
      expect(wideRuns.map((r) => r.text).join(), '世界');
    });

    test('randomized buffers round-trip with identical content (seeded)', () {
      final rng = Random(0x9A11);
      const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789 ./:-';
      for (var iter = 0; iter < 50; iter++) {
        final cols = 4 + rng.nextInt(40);
        final rows = 1 + rng.nextInt(12);
        final buffer = CellBuffer(CellSize(cols, rows));
        for (var r = 0; r < rows; r++) {
          final len = rng.nextInt(cols);
          final text = [
            for (var i = 0; i < len; i++)
              alphabet[rng.nextInt(alphabet.length)],
          ].join();
          buffer.writeText(CellOffset(0, r), text);
        }
        final decoded = _roundTrip(
          RemotePlan(
            size: buffer.size,
            fullRepaint: true,
            rows: _serverSpans(buffer),
          ),
        );
        for (var r = 0; r < rows; r++) {
          final wireRow = decoded.rows.firstWhere((row) => row.row == r);
          final bufferRow = StringBuffer();
          for (var c = 0; c < cols; c++) {
            bufferRow.write(buffer.atColRow(c, r).grapheme ?? ' ');
          }
          expect(
            _rowText(wireRow),
            bufferRow.toString(),
            reason: 'iter $iter row $r',
          );
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
