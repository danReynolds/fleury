import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('StringAnsiSink', () {
    test('captures every write', () {
      final sink = StringAnsiSink();
      sink.write('a');
      sink.write('b');
      expect(sink.output, 'ab');
    });

    test('clear empties the captured output', () {
      final sink = StringAnsiSink();
      sink.write('content');
      sink.clear();
      expect(sink.output, '');
    });
  });

  group('renderDiff — identical buffers', () {
    test('emits nothing when previous and next are equal', () {
      final prev = CellBuffer(const CellSize(3, 2));
      final next = CellBuffer(const CellSize(3, 2));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, isEmpty);
    });

    test('emits nothing when both have identical content', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      prev.writeText(const CellOffset(0, 0), 'abc');
      next.writeText(const CellOffset(0, 0), 'abc');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, isEmpty);
    });
  });

  group('renderDiff — narrow content', () {
    test('single dirty cell emits cursor move + grapheme', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      next.writeGrapheme(const CellOffset(2, 0), 'X');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Cursor to row 1, col 3 (1-indexed); emit 'X'; no style emitted so
      // no trailing reset.
      expect(sink.output, '\x1B[1;3HX');
    });

    test('multiple consecutive dirty cells share one cursor move', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      next.writeText(const CellOffset(0, 0), 'abc');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Cursor to (1,1); 'a' advances to col 2, 'b' to col 3, 'c' to 4.
      // No intermediate CSI H expected.
      expect(sink.output, '\x1B[1;1Habc');
    });

    test('a gap between dirty cells causes a second cursor move', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(const CellOffset(3, 0), 'd');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, '\x1B[1;1Ha\x1B[1;4Hd');
    });

    test('dirty cells in multiple rows emit a cursor move per row', () {
      final prev = CellBuffer(const CellSize(3, 3));
      final next = CellBuffer(const CellSize(3, 3));
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(const CellOffset(0, 2), 'c');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, '\x1B[1;1Ha\x1B[3;1Hc');
    });
  });

  group('renderDiff — wide content', () {
    test('a wide grapheme advances the cursor by 2', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      next.writeGrapheme(const CellOffset(0, 0), '中');
      next.writeGrapheme(const CellOffset(2, 0), 'x');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // After the wide '中' the cursor is at col 3 (1-indexed); 'x' is at
      // col 3 (0-indexed col 2 → 1-indexed col 3). No second cursor move.
      expect(sink.output, '\x1B[1;1H中x');
    });

    test('continuation cells emit nothing themselves', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeGrapheme(const CellOffset(0, 0), '中');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Only one cursor move + one grapheme; no extra cell for col 1.
      expect(sink.output, '\x1B[1;1H中');
    });
  });

  group('renderDiff — clearing', () {
    test('clearing a cell emits a space', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      prev.writeGrapheme(const CellOffset(0, 0), 'X');
      // next has Cell.empty at (0,0).
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, '\x1B[1;1H ');
    });
  });

  group('renderDiff — styles', () {
    test('emits SGR change before the grapheme of a styled cell', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeGrapheme(
        const CellOffset(0, 0),
        'A',
        style: const CellStyle(foreground: AnsiColor(1), bold: true),
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Cursor + reset + fg red (31) + bold (1) + 'A' + trailing reset.
      expect(sink.output, '\x1B[1;1H\x1B[0m\x1B[31m\x1B[1mA\x1B[0m');
    });

    test('resets style at end of frame when any style was emitted', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeGrapheme(
        const CellOffset(0, 0),
        'A',
        style: const CellStyle(bold: true),
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.endsWith('\x1B[0m'), isTrue);
    });

    test('style transitions within a run emit a fresh SGR sequence', () {
      final prev = CellBuffer(const CellSize(4, 1));
      final next = CellBuffer(const CellSize(4, 1));
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(
        const CellOffset(1, 0),
        'b',
        style: const CellStyle(bold: true),
      );
      next.writeGrapheme(const CellOffset(2, 0), 'c');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // (1,1) → 'a' (no SGR needed for default style);
      // style flips: reset + bold → 'b';
      // style flips back: reset → 'c';
      // no final reset because we already reset back to default
      // before emitting 'c'.
      expect(sink.output, '\x1B[1;1Ha\x1B[0m\x1B[1mb\x1B[0mc');
    });
  });

  group('renderDiff — color encoding', () {
    void writeOneChar(CellBuffer buf, CellStyle style) {
      buf.writeGrapheme(const CellOffset(0, 0), 'A', style: style);
    }

    test('AnsiColor 0-7 foreground encodes to 30-37', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(foreground: AnsiColor(3)));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[33m'), isTrue);
    });

    test('AnsiColor 8-15 foreground encodes to 90-97', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(foreground: AnsiColor(10)));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[92m'), isTrue);
    });

    test('AnsiColor 0-7 background encodes to 40-47', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(background: AnsiColor(4)));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[44m'), isTrue);
    });

    test('IndexedColor foreground encodes to 38;5;N', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(foreground: IndexedColor(214)));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[38;5;214m'), isTrue);
    });

    test('RgbColor foreground encodes to 38;2;R;G;B', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(foreground: RgbColor(10, 20, 30)));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[38;2;10;20;30m'), isTrue);
    });

    test('RgbColor background encodes to 48;2;R;G;B', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(background: RgbColor(0, 255, 128)));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[48;2;0;255;128m'), isTrue);
    });

    test('multiple attributes appear together', () {
      final prev = CellBuffer(const CellSize(1, 1));
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(
        next,
        const CellStyle(bold: true, italic: true, underline: true),
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      final output = sink.output;
      expect(output.contains('\x1B[1m'), isTrue);
      expect(output.contains('\x1B[3m'), isTrue);
      expect(output.contains('\x1B[4m'), isTrue);
    });
  });

  group('renderFull', () {
    test('produces no output for an entirely empty buffer', () {
      final buf = CellBuffer(const CellSize(4, 2));
      final sink = StringAnsiSink();

      const AnsiRenderer().renderFull(buf, sink);
      expect(sink.output, isEmpty);
    });

    test('produces the same bytes as renderDiff(empty, buf)', () {
      final buf = CellBuffer(const CellSize(5, 1));
      buf.writeText(const CellOffset(0, 0), 'hi 中');

      final viaFull = StringAnsiSink();
      const AnsiRenderer().renderFull(buf, viaFull);

      final viaDiff = StringAnsiSink();
      const AnsiRenderer().renderDiff(CellBuffer(buf.size), buf, viaDiff);

      expect(viaFull.output, viaDiff.output);
    });
  });

  group('renderDiff — buffer-size mismatch', () {
    test('asserts when previous and next sizes differ', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(4, 1));
      final sink = StringAnsiSink();

      expect(
        () => const AnsiRenderer(
          synchronizedOutput: false,
        ).renderDiff(prev, next, sink),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('quantizeColor', () {
    test('truecolor passes everything through unchanged', () {
      const c = RgbColor(12, 34, 56);
      expect(quantizeColor(c, ColorMode.truecolor), c);
    });

    test('none drops the color entirely', () {
      expect(quantizeColor(const RgbColor(255, 0, 0), ColorMode.none), isNull);
      expect(quantizeColor(const AnsiColor(3), ColorMode.none), isNull);
    });

    test('rgb → 256 maps exact cube corners', () {
      // Pure black/white sit at the cube corners (16 and 231).
      expect(
        quantizeColor(const RgbColor(0, 0, 0), ColorMode.indexed256),
        const IndexedColor(16),
      );
      expect(
        quantizeColor(const RgbColor(255, 255, 255), ColorMode.indexed256),
        const IndexedColor(231),
      );
    });

    test('rgb → 256 prefers the grayscale ramp for neutral grays', () {
      // (128,128,128) is closer to gray index 244 than any cube step.
      expect(
        quantizeColor(const RgbColor(128, 128, 128), ColorMode.indexed256),
        const IndexedColor(244),
      );
    });

    test('rgb → 16 picks the nearest palette entry', () {
      expect(
        quantizeColor(const RgbColor(255, 0, 0), ColorMode.ansi16),
        const AnsiColor(9),
      ); // bright red, exact
      expect(
        quantizeColor(const RgbColor(0, 0, 0), ColorMode.ansi16),
        const AnsiColor(0),
      );
      expect(
        quantizeColor(const RgbColor(250, 250, 250), ColorMode.ansi16),
        const AnsiColor(15),
      );
    });

    test('256 → 16 collapses the low 16 indices directly', () {
      expect(
        quantizeColor(const IndexedColor(5), ColorMode.ansi16),
        const AnsiColor(5),
      );
    });

    test('a representable color is left alone', () {
      // 16-color and 256-color values already fit their or higher modes.
      expect(
        quantizeColor(const AnsiColor(2), ColorMode.ansi16),
        const AnsiColor(2),
      );
      expect(
        quantizeColor(const IndexedColor(200), ColorMode.indexed256),
        const IndexedColor(200),
      );
    });
  });

  group('renderDiff — color downsampling', () {
    void writeOneChar(CellBuffer buf, CellStyle style) {
      buf.writeGrapheme(const CellOffset(0, 0), 'A', style: style);
    }

    test('an ansi16 renderer emits a 16-color SGR for an RGB cell', () {
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(next, const CellStyle(foreground: RgbColor(255, 0, 0)));
      final sink = StringAnsiSink();
      const AnsiRenderer(
        colorMode: ColorMode.ansi16,
      ).renderDiff(CellBuffer(const CellSize(1, 1)), next, sink);
      // Bright red (index 9) → 90 + 9 - 8 = 91; never a truecolor 38;2.
      expect(sink.output.contains('\x1B[91m'), isTrue);
      expect(sink.output.contains('38;2'), isFalse);
    });

    test('a none renderer drops color but keeps attributes', () {
      final next = CellBuffer(const CellSize(1, 1));
      writeOneChar(
        next,
        const CellStyle(foreground: RgbColor(255, 0, 0), bold: true),
      );
      final sink = StringAnsiSink();
      const AnsiRenderer(
        colorMode: ColorMode.none,
      ).renderDiff(CellBuffer(const CellSize(1, 1)), next, sink);
      expect(sink.output.contains('\x1B[1m'), isTrue, reason: 'bold kept');
      expect(sink.output.contains('38;2'), isFalse, reason: 'no truecolor');
      expect(sink.output.contains('91m'), isFalse, reason: 'no color at all');
    });
  });

  group('renderDiff — Synchronized Output (DEC mode 2026)', () {
    test('wraps a dirty frame in BSU/ESU by default', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(const CellOffset(0, 0), 'x');
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink);
      expect(
        sink.output.startsWith('\x1B[?2026h'),
        isTrue,
        reason: 'frame opens with BSU',
      );
      expect(
        sink.output.endsWith('\x1B[?2026l'),
        isTrue,
        reason: 'frame closes with ESU',
      );
    });

    test('an empty diff still emits nothing (no wrapper)', () {
      // An empty frame doesn't need a sync wrapper — and emitting one
      // would still be a small wasted round-trip on terminals that
      // don't support 2026.
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink);
      expect(sink.output, isEmpty);
    });

    test('synchronizedOutput: false omits both markers', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(const CellOffset(0, 0), 'x');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output.contains('\x1B[?2026h'), isFalse);
      expect(sink.output.contains('\x1B[?2026l'), isFalse);
      // But the cell content still emits.
      expect(sink.output.contains('x'), isTrue);
    });

    test('BSU precedes the first cursor-position escape', () {
      // The order matters: BSU must arrive at the terminal before any
      // cell mutations so the terminal knows to buffer them.
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(const CellOffset(0, 0), 'x');
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink);
      final bsu = sink.output.indexOf('\x1B[?2026h');
      final firstCup = sink.output.indexOf('\x1B[1;1H');
      expect(
        bsu,
        lessThan(firstCup),
        reason: 'BSU must come before the first cursor-position escape',
      );
    });
  });

  group('renderDiff — protocol regions', () {
    const renderer = AnsiRenderer(synchronizedOutput: false);

    test('anchor grapheme is emitted verbatim after a cursor move', () {
      final prev = CellBuffer(const CellSize(4, 2));
      final next = CellBuffer(const CellSize(4, 2));
      const payload = '\x1B_GRAW\x1B\\';
      next.writeProtocol(const CellOffset(1, 1), payload, width: 3, height: 1);
      final sink = StringAnsiSink();

      renderer.renderDiff(prev, next, sink);
      // Cursor to (row 1, col 1) is "\x1B[2;2H" (1-indexed). Then the
      // raw escape payload, verbatim.
      expect(sink.output, contains('\x1B[2;2H$payload'));
    });

    test('covered cells emit no cursor move and no content', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeProtocol(const CellOffset(0, 0), 'P', width: 3, height: 1);
      final sink = StringAnsiSink();

      renderer.renderDiff(prev, next, sink);
      // Exactly one cursor move (for the anchor); no per-cell moves for
      // the two covered cells.
      expect('\x1B[1;1H'.allMatches(sink.output).length, 1);
      expect(sink.output.contains('\x1B[1;2H'), isFalse);
      expect(sink.output.contains('\x1B[1;3H'), isFalse);
    });

    test('style is invalidated after a protocol anchor', () {
      // After a protocol anchor the cursor and style cache are
      // unknown — the next dirty cell must re-emit its SGR.
      final prev = CellBuffer(const CellSize(4, 1));
      final next = CellBuffer(const CellSize(4, 1));
      next.writeProtocol(const CellOffset(0, 0), 'P', width: 2, height: 1);
      next.writeGrapheme(
        const CellOffset(2, 0),
        'a',
        style: const CellStyle(foreground: RgbColor(255, 0, 0)),
      );
      final sink = StringAnsiSink();

      renderer.renderDiff(prev, next, sink);
      // The cell at col 2 follows the anchor, so a fresh cursor move
      // and SGR must appear.
      final anchorIdx = sink.output.indexOf('P');
      final afterAnchor = sink.output.substring(anchorIdx + 1);
      expect(
        afterAnchor.contains('\x1B[1;3H'),
        isTrue,
        reason: 'cursor must be re-emitted after the anchor',
      );
      expect(
        afterAnchor.contains('\x1B[38;2;255;0;0m'),
        isTrue,
        reason: 'style cache invalidated — fg must be re-emitted',
      );
    });
  });
}
