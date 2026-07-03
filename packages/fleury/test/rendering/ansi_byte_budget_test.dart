// Unit tests for the ANSI byte-budget categorizer. The harness draws
// conclusions ("SGR is N% of update bytes") from this, so the categorizer
// itself must be trustworthy — these pin its classification against the exact
// sequences AnsiRenderer emits.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('AnsiByteBreakdown.analyze', () {
    test('plain content counts as content (UTF-8 bytes)', () {
      final b = AnsiByteBreakdown.analyze('hello');
      expect(b.content, 5);
      expect(b.overhead, 0);
      expect(b.total, 5);
    });

    test('multi-byte graphemes count their UTF-8 length, not code units', () {
      // '日' is 3 UTF-8 bytes; '🙂' is 4. Code-unit length would undercount.
      final b = AnsiByteBreakdown.analyze('日🙂');
      expect(b.content, 7);
    });

    test('cursor positioning is categorized as cursor', () {
      final b = AnsiByteBreakdown.analyze('\x1B[3;5H');
      expect(b.cursor, '\x1B[3;5H'.length);
      expect(b.content, 0);
      expect(b.sgr, 0);
    });

    test('relative cursor movement is categorized as cursor', () {
      const sequence = '\x1B[2C\x1B[3D\x1B[1A\x1B[4B\x1B[E\x1B[2F';
      final b = AnsiByteBreakdown.analyze(sequence);
      expect(b.cursor, sequence.length);
      expect(b.other, 0);
      expect(b.content, 0);
    });

    test('C0 cursor controls are categorized as cursor', () {
      const sequence = '\b\n\r';
      final b = AnsiByteBreakdown.analyze(sequence);
      expect(b.cursor, sequence.length);
      expect(b.other, 0);
      expect(b.content, 0);
    });

    test('SGR set and reset are categorized as sgr', () {
      final b = AnsiByteBreakdown.analyze('\x1B[0m\x1B[1m\x1B[38;5;9m');
      expect(b.sgr, '\x1B[0m\x1B[1m\x1B[38;5;9m'.length);
      expect(b.content, 0);
    });

    test('synchronized-output private modes are categorized as sync', () {
      final b = AnsiByteBreakdown.analyze('\x1B[?2026h\x1B[?2026l');
      expect(b.sync, '\x1B[?2026h\x1B[?2026l'.length);
      expect(b.cursor, 0);
    });

    test('a realistic styled frame splits across categories', () {
      // begin-sync, cursor home, red SGR, content, reset, end-sync.
      const frame =
          '\x1B[?2026h' // sync (8)
          '\x1B[1;1H' // cursor (6)
          '\x1B[0m\x1B[31m' // sgr (4 + 5 = 9)
          'hi' // content (2)
          '\x1B[0m' // sgr (4)
          '\x1B[?2026l'; // sync (8)
      final b = AnsiByteBreakdown.analyze(frame);
      expect(b.sync, 16);
      expect(b.cursor, 6);
      expect(b.sgr, 13);
      expect(b.content, 2);
      expect(b.total, frame.length);
      // Every byte is accounted for exactly once.
      expect(
        b.total,
        b.content + b.sgr + b.cursor + b.sync + b.session + b.other,
      );
    });

    test('overheadFraction reflects control vs information split', () {
      final b = AnsiByteBreakdown.analyze('\x1B[1;1Hab');
      // 6 cursor bytes + 2 content bytes.
      expect(b.overhead, 6);
      expect(b.content, 2);
      expect(b.overheadFraction, closeTo(6 / 8, 1e-9));
    });

    test('lifecycle private modes are categorized as session, not sync', () {
      // The exact enter sequence runApp emits for an interactive session.
      const enter = '\x1B[?1049h\x1B[?25l\x1B[?2004h';
      final b = AnsiByteBreakdown.analyze(enter);
      expect(b.session, enter.length);
      expect(b.sync, 0);
    });

    test('mouse-mode resets on exit are categorized as session', () {
      const exit = '\x1B[?1006l\x1B[?1003l\x1B[?1002l\x1B[?1000l';
      final b = AnsiByteBreakdown.analyze(exit);
      expect(b.session, exit.length);
      expect(b.sync, 0);
    });

    test('Kitty keyboard push/pop is categorized as session', () {
      final b = AnsiByteBreakdown.analyze('\x1B[>1u\x1B[<u');
      expect(b.session, '\x1B[>1u\x1B[<u'.length);
      expect(b.other, 0);
    });

    test('synchronized output stays sync alongside session toggles', () {
      final b = AnsiByteBreakdown.analyze('\x1B[?1049h\x1B[?2026h\x1B[?2026l');
      expect(b.session, '\x1B[?1049h'.length);
      expect(b.sync, '\x1B[?2026h\x1B[?2026l'.length);
    });

    test('overheadFraction excludes session lifecycle bytes', () {
      // Session enter + one cursor move + content: the fraction is computed
      // over the steady-state bytes only.
      final b = AnsiByteBreakdown.analyze('\x1B[?1049h\x1B[1;1Hab');
      expect(b.session, 8);
      expect(b.overhead, 6);
      expect(b.overheadFraction, closeTo(6 / 8, 1e-9));
    });
  });

  group('TransportProfile', () {
    test('frameMs is fixed overhead plus serialization time', () {
      const p = TransportProfile('t', bytesPerSecond: 1000, fixedOverheadMs: 2);
      expect(p.frameMs(0), 2.0); // pure overhead
      expect(p.frameMs(1000), closeTo(2 + 1000, 1e-9)); // +1s for 1000 B
      expect(p.frameMs(500), closeTo(2 + 500, 1e-9));
    });

    test('byte savings matter on slow links, not on fast ones', () {
      // 250-byte saving (e.g. a scroll frame after cursor compression).
      const saved = 250;
      final onSlow =
          TransportProfile.slow9600.frameMs(1024) -
          TransportProfile.slow9600.frameMs(1024 - saved);
      final onWan =
          TransportProfile.sshWan.frameMs(1024) -
          TransportProfile.sshWan.frameMs(1024 - saved);
      expect(onSlow, greaterThan(150)); // ~208 ms saved on 9600 baud
      expect(onWan, lessThan(1)); // negligible on a fast WAN link
    });
  });

  group('CountingAnsiSink', () {
    test('aggregate mode keeps totals without retaining frames', () {
      final sink = CountingAnsiSink.aggregate();
      sink.write('\x1B[1;1Hab');
      sink.write('\x1B[2;1Hcd');
      expect(sink.frameCount, 2);
      expect(sink.total.content, 4);
      expect(sink.frames, isEmpty); // no per-frame list retained
    });

    test('accumulates per-frame and total, and forwards to inner sink', () {
      final inner = StringAnsiSink();
      final sink = CountingAnsiSink(inner);
      sink.write('\x1B[1;1Hab');
      sink.write('\x1B[2;1Hcd');
      expect(sink.frameCount, 2);
      expect(sink.frames[0].content, 2);
      expect(sink.total.content, 4);
      expect(sink.total.cursor, 12);
      // Bytes still reached the wrapped sink verbatim.
      expect(inner.output, '\x1B[1;1Hab\x1B[2;1Hcd');
    });

    test('integrates with AnsiRenderer.renderDiff: one write == one frame', () {
      const size = CellSize(4, 1);
      final empty = CellBuffer(size);
      final frame = CellBuffer(size);
      frame.writeText(const CellOffset(0, 0), 'hi');

      final sink = CountingAnsiSink();
      const AnsiRenderer().renderDiff(empty, frame, sink);

      expect(sink.frameCount, 1);
      // The frame carried real content plus cursor/sync overhead.
      expect(sink.total.content, greaterThan(0));
      expect(sink.total.total, greaterThan(sink.total.content));
    });
  });

  group('AnsiByteBreakdown image category', () {
    test('Kitty graphics (APC ESC _ … ST) count as image, not content', () {
      const seq = '\x1B_Ga=t,f=100,i=1;AAAABBBBCCCC\x1B\\';
      final b = AnsiByteBreakdown.analyze(seq);
      expect(b.image, seq.length);
      expect(b.content, 0);
      expect(b.other, 0);
    });

    test('iTerm2 inline image (OSC 1337, BEL-terminated) counts as image', () {
      const seq = '\x1B]1337;File=inline=1;size=9:QUJDREVG\x07';
      final b = AnsiByteBreakdown.analyze(seq);
      expect(b.image, seq.length);
      expect(b.content, 0);
      expect(b.other, 0);
    });

    test('Sixel (DCS ESC P … ST) counts as image', () {
      const seq = '\x1BPq#0;2;0;0;0#0~~~\x1B\\';
      final b = AnsiByteBreakdown.analyze(seq);
      expect(b.image, seq.length);
      expect(b.content, 0);
    });

    test('non-image OSC (clipboard 52) stays other, NOT image', () {
      const seq = '\x1B]52;c;U0VDUkVU\x07';
      final b = AnsiByteBreakdown.analyze(seq);
      expect(b.image, 0);
      expect(b.other, seq.length);
    });

    test('image is payload, not tunable overhead', () {
      const seq = '\x1B_Ga=t;AAAA\x1B\\';
      final b = AnsiByteBreakdown.analyze(seq);
      expect(b.image, greaterThan(0));
      expect(b.overhead, 0, reason: 'image is payload like content');
      expect(b.total, b.image);
    });

    test('image separates cleanly from surrounding content + cursor', () {
      const img = '\x1B_Ga=t;AAAA\x1B\\';
      const seq = 'ab${img}cd\x1B[2;1H';
      final b = AnsiByteBreakdown.analyze(seq);
      expect(b.image, img.length);
      expect(b.content, 4, reason: 'ab + cd');
      expect(b.cursor, '\x1B[2;1H'.length);
    });
  });
}
