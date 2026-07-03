import 'dart:typed_data';

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
      // Cursor home (CSI H == CSI 1;1H); 'a' advances to col 2, 'b' to col 3,
      // 'c' to 4. No intermediate cursor move expected.
      expect(sink.output, '\x1B[Habc');
    });

    test(
      'a cheap plain gap between dirty cells is written instead of skipped',
      () {
        final prev = CellBuffer(const CellSize(5, 1));
        final next = CellBuffer(const CellSize(5, 1));
        next.writeGrapheme(const CellOffset(0, 0), 'a');
        next.writeGrapheme(const CellOffset(3, 0), 'd');
        final sink = StringAnsiSink();

        const AnsiRenderer(
          synchronizedOutput: false,
        ).renderDiff(prev, next, sink);
        // Home, 'a' (cursor now at col 1), then two unchanged plain cells are
        // cheaper to write than a same-row cursor move.
        expect(sink.output, '\x1B[Ha  d');
      },
    );

    test('a long plain gap still uses a cursor move when cheaper', () {
      final prev = CellBuffer(const CellSize(20, 1));
      final next = CellBuffer(const CellSize(20, 1));
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(const CellOffset(15, 0), 'p');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      expect(sink.output, '\x1B[Ha\x1B[14Cp');
    });

    test('a same-style gap is written through without a cursor move', () {
      const style = CellStyle(bold: true);
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      prev.writeGrapheme(const CellOffset(1, 0), 'b', style: style);
      prev.writeGrapheme(const CellOffset(2, 0), 'c', style: style);
      next.writeGrapheme(const CellOffset(0, 0), 'a', style: style);
      next.writeGrapheme(const CellOffset(1, 0), 'b', style: style);
      next.writeGrapheme(const CellOffset(2, 0), 'c', style: style);
      next.writeGrapheme(const CellOffset(3, 0), 'd', style: style);
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      // 'b' and 'c' are unchanged and carry exactly the emitted style:
      // rewriting them costs 2 bytes where a cursor move costs 4.
      expect(sink.output, '\x1B[H\x1B[1mabcd\x1B[0m');
    });

    test('a styled gap keeps the explicit cursor move', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      prev.writeGrapheme(
        const CellOffset(1, 0),
        'b',
        style: const CellStyle(bold: true),
      );
      next.writeGrapheme(
        const CellOffset(1, 0),
        'b',
        style: const CellStyle(bold: true),
      );
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(const CellOffset(3, 0), 'd');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      expect(sink.output, '\x1B[Ha\x1B[2Cd');
    });

    test('dirtyBounds limits the scanned diff region', () {
      final prev = CellBuffer(const CellSize(6, 2));
      final next = CellBuffer(const CellSize(6, 2));
      next.writeGrapheme(const CellOffset(4, 1), 'X');
      final dirty = <CellOffset>[];
      final sink = StringAnsiSink();

      const AnsiRenderer(synchronizedOutput: false).renderDiff(
        prev,
        next,
        sink,
        dirtyBounds: CellRect.fromLTWH(4, 1, 1, 1),
        onDirtyCell: (col, row) => dirty.add(CellOffset(col, row)),
      );

      expect(sink.output, '\x1B[2;5HX');
      expect(dirty, const [CellOffset(4, 1)]);
    });

    test('cross-row movement uses absolute CUP (not row-relative LF)', () {
      final prev = CellBuffer(const CellSize(3, 3));
      final next = CellBuffer(const CellSize(3, 3));
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(const CellOffset(1, 1), 'c');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Row changes use an absolute CUP, never LF/CRLF/CNL: those are row-
      // RELATIVE and desync if the tracked row ever drifts from the terminal's
      // (the fast-scroll "stale tail" garble). Absolute re-pins the row.
      expect(sink.output, '\x1B[Ha\x1B[2;2Hc');
    });

    test('cross-row movement to column 0 uses absolute CUP', () {
      final prev = CellBuffer(const CellSize(3, 3));
      final next = CellBuffer(const CellSize(3, 3));
      next.writeGrapheme(const CellOffset(0, 0), 'a');
      next.writeGrapheme(const CellOffset(0, 1), 'b');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Absolute CUP to (row 1, col 0) = CSI 2 H (column default omitted).
      expect(sink.output, '\x1B[Ha\x1B[2Hb');
    });

    test('indented cross-row movement uses absolute CUP', () {
      final prev = CellBuffer(const CellSize(8, 3));
      final next = CellBuffer(const CellSize(8, 3));
      next.writeText(const CellOffset(0, 0), 'aaaa');
      next.writeText(const CellOffset(1, 1), 'b');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // Absolute CUP to (row 1, col 1) instead of the old CRLF+CUF — drift-safe.
      expect(sink.output, '\x1B[Haaaa\x1B[2;2Hb');
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
      expect(sink.output, '\x1B[H中x');
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
      expect(sink.output, '\x1B[H中');
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
      expect(sink.output, '\x1B[H ');
    });
  });

  group('renderDiff — scroll-up row shifts', () {
    test('uses terminal scroll for whole-screen upward row shifts', () {
      final prev = CellBuffer(const CellSize(4, 4));
      final next = CellBuffer(const CellSize(4, 4));
      prev.writeText(const CellOffset(0, 0), 'aaaa');
      prev.writeText(const CellOffset(0, 1), 'bbbb');
      prev.writeText(const CellOffset(0, 2), 'cccc');
      prev.writeText(const CellOffset(0, 3), 'dddd');
      next.writeText(const CellOffset(0, 0), 'cccc');
      next.writeText(const CellOffset(0, 1), 'dddd');
      next.writeText(const CellOffset(0, 2), 'eeee');
      next.writeText(const CellOffset(0, 3), 'ffff');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      // 'eeee' fills the 4-wide row, so the write lands on the last column.
      // The cursor's post-write state is terminal-defined (terminals without
      // pending-wrap advance to the next line immediately), so the renderer
      // repositions absolutely (CUP) for the next row instead of '\r\n', which
      // would over-advance on such terminals. See ansi_renderer.dart.
      expect(sink.output, '\x1B[2S\x1B[3Heeee\x1B[4Hffff');
    });

    test('wraps scroll updates in synchronized-output markers', () {
      final prev = CellBuffer(const CellSize(4, 2));
      final next = CellBuffer(const CellSize(4, 2));
      prev.writeText(const CellOffset(0, 0), 'aaaa');
      prev.writeText(const CellOffset(0, 1), 'bbbb');
      next.writeText(const CellOffset(0, 0), 'bbbb');
      next.writeText(const CellOffset(0, 1), 'cccc');
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink);

      // The scroll payload here is tiny, so the small-diff sync skip
      // applies; the scroll escape itself is unchanged.
      expect(sink.output, '\x1B[S\x1B[2Hcccc');
    });

    test('large scroll updates keep the synchronized-output wrapper', () {
      final prev = CellBuffer(const CellSize(80, 2));
      final next = CellBuffer(const CellSize(80, 2));
      prev.writeText(const CellOffset(0, 0), 'a' * 70);
      prev.writeText(const CellOffset(0, 1), 'b' * 70);
      next.writeText(const CellOffset(0, 0), 'b' * 70);
      next.writeText(const CellOffset(0, 1), 'c' * 70);
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink);

      expect(sink.output.startsWith('\x1B[?2026h'), isTrue);
      expect(sink.output.endsWith('\x1B[?2026l'), isTrue);
      expect(sink.output, contains('\x1B[S'));
    });

    test('falls back to cell diff when overlay cells are present', () {
      final prev = CellBuffer(const CellSize(4, 3));
      final next = CellBuffer(const CellSize(4, 3));
      prev.writeText(const CellOffset(0, 1), 'bbbb');
      prev.writeText(const CellOffset(0, 2), 'cccc');
      next.writeText(const CellOffset(0, 0), 'bbbb');
      next.writeText(const CellOffset(0, 1), 'cccc');
      next.writeImage(
        const CellOffset(0, 2),
        Uint8List.fromList([1]),
        width: 1,
        height: 1,
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      // Overlay pixels are not row-relocatable, so no SU escape — the
      // moved text is repainted cell-by-cell instead.
      expect(sink.output.contains('\x1B[S'), isFalse);
      expect(sink.output.contains('bbbb'), isTrue);
    });
  });

  group('renderDiff — ambiguous-width glyphs', () {
    test('repositions absolutely after a box-drawing (ambiguous) glyph', () {
      // U+2500 (─) and the other box / bullet / arrow glyphs are East-Asian
      // "Ambiguous": a terminal or font that renders them two columns wide
      // advances the cursor further than fleury's one-column model, so a
      // following relative move desyncs. The renderer must reposition the next
      // cell absolutely so it stays pinned to its column on any terminal.
      final prev = CellBuffer(const CellSize(4, 1));
      final next = CellBuffer(const CellSize(4, 1))
        ..writeText(const CellOffset(0, 0), '─x');
      final sink = StringAnsiSink();
      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      expect(
        sink.output,
        contains('─\x1B[1;2Hx'),
        reason:
            'an absolute CUP separates the ambiguous glyph from the '
            'next cell',
      );
    });

    test('a pure-ASCII run is NOT broken up (stays compact)', () {
      final prev = CellBuffer(const CellSize(6, 1));
      final next = CellBuffer(const CellSize(6, 1))
        ..writeText(const CellOffset(0, 0), 'abcde');
      final sink = StringAnsiSink();
      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      // No interior cursor moves — ASCII width is unambiguous.
      expect(sink.output, '\x1B[Habcde');
    });

    test('the defensive path pins EVERY cell of an ambiguous run', () {
      // Default (ambiguousCharsAreWide: true): a run of box-drawing glyphs costs
      // one absolute CUP per cell — correct on a two-wide terminal, but the very
      // overhead the narrow path below removes. Guards the SB.6 regression: this
      // is what a whole sparkline/gauge fill looked like on every terminal.
      final prev = CellBuffer(const CellSize(4, 1));
      final next = CellBuffer(const CellSize(4, 1))
        ..writeText(const CellOffset(0, 0), '───x');
      final sink = StringAnsiSink();
      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, '\x1B[H─\x1B[1;2H─\x1B[1;3H─\x1B[1;4Hx');
    });

    test(
      'a confirmed-narrow terminal keeps an ambiguous run contiguous',
      () {
        // When the startup probe confirms the terminal renders ambiguous-width
        // glyphs one column wide (the common case), the defensive per-cell
        // repositioning is pure overhead. The same run must collapse to a single
        // contiguous write with no interior cursor moves — this is the SB.6 fix.
        final prev = CellBuffer(const CellSize(4, 1));
        final next = CellBuffer(const CellSize(4, 1))
          ..writeText(const CellOffset(0, 0), '───x');
        final sink = StringAnsiSink();
        const AnsiRenderer(
          synchronizedOutput: false,
          ambiguousCharsAreWide: false,
        ).renderDiff(prev, next, sink);
        expect(sink.output, '\x1B[H───x');
      },
    );

    test('the last-column guard still fires on a narrow terminal', () {
      // ambiguousCharsAreWide only gates the *width* invalidation; a write to
      // the final column must still invalidate (pending-wrap terminals), so the
      // next row repositions absolutely rather than riding an autowrap.
      final prev = CellBuffer(const CellSize(2, 2));
      final next = CellBuffer(const CellSize(2, 2))
        ..writeText(const CellOffset(0, 0), 'ab')
        ..writeText(const CellOffset(0, 1), 'cd');
      final sink = StringAnsiSink();
      const AnsiRenderer(
        synchronizedOutput: false,
        ambiguousCharsAreWide: false,
      ).renderDiff(prev, next, sink);
      // Row 0 fills to the last column; row 1 must start with an absolute CUP.
      expect(sink.output, contains('ab\x1B[2Hcd'));
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
      // Cursor + combined fg red (31) and bold (1) + 'A' + trailing reset.
      // No leading reset is needed because the renderer knows a frame starts
      // in default style.
      expect(sink.output, '\x1B[H\x1B[31;1mA\x1B[0m');
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
      expect(sink.output, '\x1B[Ha\x1B[1mb\x1B[0mc');
    });

    test('non-empty style transitions emit deltas without full reset', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeGrapheme(
        const CellOffset(0, 0),
        'a',
        style: const CellStyle(foreground: AnsiColor(1), bold: true),
      );
      next.writeGrapheme(
        const CellOffset(1, 0),
        'b',
        style: const CellStyle(foreground: AnsiColor(4), bold: true),
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      expect(sink.output, '\x1B[H\x1B[31;1ma\x1B[34mb\x1B[0m');
    });

    test('intensity delta preserves dim when bold turns off', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeGrapheme(
        const CellOffset(0, 0),
        'a',
        style: const CellStyle(bold: true, dim: true),
      );
      next.writeGrapheme(
        const CellOffset(1, 0),
        'b',
        style: const CellStyle(dim: true),
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      expect(sink.output, '\x1B[H\x1B[1;2ma\x1B[22;2mb\x1B[0m');
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
      expect(output.contains('\x1B[1;3;4m'), isTrue);
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
      // Wide enough that the payload exceeds the small-diff sync skip.
      final prev = CellBuffer(const CellSize(80, 1));
      final next = CellBuffer(const CellSize(80, 1));
      next.writeText(
        const CellOffset(0, 0),
        'a long enough line of content to exceed the sync threshold',
      );
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

    test('small diffs skip the synchronized-output wrapper', () {
      // A one-cell diff arrives in a single read; the 16-byte BSU/ESU
      // wrapper would be a third of the frame for nothing.
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(const CellOffset(0, 0), 'x');
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink);

      expect(sink.output.contains('\x1B[?2026'), isFalse);
      expect(sink.output, contains('x'));
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
      final firstCup = sink.output.indexOf('\x1B[H'); // home (CSI H == 1;1)
      expect(
        bsu,
        lessThan(firstCup),
        reason: 'BSU must come before the first cursor-position escape',
      );
    });
  });

  group('renderDiff — overlay regions', () {
    const renderer = AnsiRenderer(synchronizedOutput: false);

    test(
      'an overlay over a blank cell emits nothing (static image is free)',
      () {
        final prev = CellBuffer(const CellSize(3, 1));
        final next = CellBuffer(const CellSize(3, 1));
        next.writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1]),
          width: 3,
          height: 1,
        );
        final sink = StringAnsiSink();

        renderer.renderDiff(prev, next, sink);
        // The region was already blank and the encoder paints the pixels
        // out-of-band, so the text diff contributes zero bytes.
        expect(sink.output, isEmpty);
      },
    );

    test(
      'an overlay over prior content clears it (no stale letterbox bars)',
      () {
        // The image box marks the WHOLE region overlay, but the encoder only
        // paints the fitted sub-rect; the bar cells must be cleared here or
        // the old text shows through the image's letterbox on a terminal.
        final prev = CellBuffer(const CellSize(4, 1));
        prev.writeText(const CellOffset(0, 0), 'OLD!');
        final next = CellBuffer(const CellSize(4, 1));
        next.writeImage(
          const CellOffset(0, 0),
          Uint8List.fromList([1]),
          width: 4,
          height: 1,
        );
        final sink = StringAnsiSink();

        renderer.renderDiff(prev, next, sink);
        expect(
          sink.output,
          contains('    '),
          reason: 'the stale text is overwritten with blanks',
        );
        expect(sink.output, isNot(contains('OLD!')));
      },
    );

    test('a vacated overlay region is repainted (image removal clears)', () {
      final prev = CellBuffer(const CellSize(3, 1));
      prev.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1]),
        width: 3,
        height: 1,
      );
      final next = CellBuffer(const CellSize(3, 1));
      final sink = StringAnsiSink();

      renderer.renderDiff(prev, next, sink);
      // overlay → empty differs, so the diff paints spaces over the
      // region — this is what erases a cell-attached image (iTerm2,
      // Sixel) when the widget goes away.
      expect(sink.output, '\x1B[H   ');
    });

    test('text painted over a former overlay region re-emits', () {
      final prev = CellBuffer(const CellSize(3, 1));
      prev.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1]),
        width: 3,
        height: 1,
      );
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(const CellOffset(0, 0), 'abc');
      final sink = StringAnsiSink();

      renderer.renderDiff(prev, next, sink);
      expect(sink.output, contains('abc'));
    });
  });

  group('renderDiff — trailer', () {
    test('trailer bytes ride after the cell diff', () {
      final prev = CellBuffer(const CellSize(4, 1));
      final next = CellBuffer(const CellSize(4, 1));
      next.writeText(const CellOffset(0, 0), 'ab');
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink, trailer: '\x1B_GIMG\x1B\\');
      expect(sink.output, '\x1B[Hab\x1B_GIMG\x1B\\');
    });

    test('a non-empty trailer is written even when no cell changed', () {
      // An animation frame can swap image content without touching a
      // single cell (the region stays overlay); the escape bytes must
      // still reach the terminal.
      final prev = CellBuffer(const CellSize(3, 1));
      prev.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([1]),
        width: 3,
        height: 1,
      );
      final next = CellBuffer(const CellSize(3, 1));
      next.writeImage(
        const CellOffset(0, 0),
        Uint8List.fromList([2]),
        width: 3,
        height: 1,
      );
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink, trailer: 'TRAILER');
      expect(sink.output, 'TRAILER');
    });

    test('no bytes at all when nothing changed and the trailer is empty', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      final sink = StringAnsiSink();

      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);
      expect(sink.output, isEmpty);
    });

    test('the trailer lands inside the synchronized-output wrapper', () {
      final prev = CellBuffer(const CellSize(80, 1));
      final next = CellBuffer(const CellSize(80, 1));
      next.writeText(const CellOffset(0, 0), 'x' * 70);
      final sink = StringAnsiSink();

      const AnsiRenderer().renderDiff(prev, next, sink, trailer: 'IMGBYTES');
      expect(sink.output.startsWith('\x1B[?2026h'), isTrue);
      expect(sink.output.endsWith('IMGBYTES\x1B[?2026l'), isTrue);
    });

    test('trailer rides the bounded-diff path too', () {
      final prev = CellBuffer(const CellSize(4, 2));
      final next = CellBuffer(const CellSize(4, 2));
      next.writeText(const CellOffset(0, 0), 'ab');
      final sink = StringAnsiSink();

      const AnsiRenderer(synchronizedOutput: false).renderDiff(
        prev,
        next,
        sink,
        dirtyBounds: CellRect.fromLTWH(0, 0, 4, 1),
        trailer: 'T',
      );
      expect(sink.output.endsWith('T'), isTrue);
    });
  });
}
