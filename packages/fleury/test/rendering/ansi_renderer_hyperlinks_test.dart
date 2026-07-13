// OSC 8 hyperlink emission (Stage 1). Golden byte-level tests for
// AnsiRenderer(hyperlinks: true): open before a run + close after, mid-row
// link changes, the frame-end close obligation, the gap-rewrite link bail, and
// cursor-jump link safety — plus proof that hyperlinks:false is byte-identical
// to a link-free buffer.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// OSC 8 open with empty params (Stage 1). `\x1B\\` is ESC + backslash (ST).
String osc8Open(String uri) => '\x1B]8;;$uri\x1B\\';

/// OSC 8 close: empty URI ends the link.
const osc8Close = '\x1B]8;;\x1B\\';

void main() {
  // hyperlinks: true; no sync wrapper so goldens are the raw diff.
  const linker = AnsiRenderer(synchronizedOutput: false, hyperlinks: true);

  group('OSC 8 emission (hyperlinks: true)', () {
    test('a linked run emits open before it and close after', () {
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));
      next.writeText(
        const CellOffset(0, 0),
        'ab',
        style: const CellStyle(linkUri: 'https://x'),
      );
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      // Home; open link; 'a','b' (one shared style, no SGR — link-only style
      // is visually empty); close at frame end.
      expect(
        sink.output,
        '\x1B[H${osc8Open('https://x')}ab$osc8Close',
      );
    });

    test('a link change mid-row closes the old link and opens the new', () {
      final prev = CellBuffer(const CellSize(4, 1));
      final next = CellBuffer(const CellSize(4, 1));
      next.writeGrapheme(
        const CellOffset(0, 0),
        'a',
        style: const CellStyle(linkUri: 'https://a'),
      );
      next.writeGrapheme(
        const CellOffset(1, 0),
        'b',
        style: const CellStyle(linkUri: 'https://b'),
      );
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      expect(
        sink.output,
        '\x1B[H${osc8Open('https://a')}a'
        '$osc8Close${osc8Open('https://b')}b$osc8Close',
      );
    });

    test('an open link at frame end is closed (close obligation)', () {
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(
        const CellOffset(0, 0),
        'abc',
        style: const CellStyle(linkUri: 'https://x'),
      );
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      expect(sink.output, '\x1B[H${osc8Open('https://x')}abc$osc8Close');
      expect(
        sink.output,
        endsWith(osc8Close),
        reason: 'a dangling link must not survive the frame',
      );
    });

    test('a styled linked run resets SGR AND closes the link at frame end', () {
      // A visible style (bold) means the frame-end SGR reset fires too — the
      // link close is a SEPARATE sequence (ESC[0m does not close OSC 8).
      final prev = CellBuffer(const CellSize(3, 1));
      final next = CellBuffer(const CellSize(3, 1));
      next.writeText(
        const CellOffset(0, 0),
        'hi',
        style: const CellStyle(bold: true, linkUri: 'https://x'),
      );
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      // Order: cursor, SGR set, OSC 8 open, glyphs, SGR reset, OSC 8 close.
      // SGR and the link open both precede the grapheme; the frame-end reset
      // and close are independent sequences.
      expect(
        sink.output,
        '\x1B[H\x1B[1m${osc8Open('https://x')}hi\x1B[0m$osc8Close',
      );
    });
  });

  group('OSC 8 link safety', () {
    test('gap rewrite bails rather than leak the open link onto plain cells',
        () {
      // Dirty linked 'a' at col 0, unchanged plain 'b','c' at 1-2, dirty 'd' at
      // col 3. Without the bail the gap rewrite would print 'bc' while link x
      // is open — leaking it. With the bail it falls back to a cursor move, so
      // 'b'/'c' are never re-emitted and the link is closed before 'd'.
      final prev = CellBuffer(const CellSize(8, 1));
      final next = CellBuffer(const CellSize(8, 1));
      prev.writeText(const CellOffset(1, 0), 'bc');
      next.writeGrapheme(
        const CellOffset(0, 0),
        'a',
        style: const CellStyle(linkUri: 'https://x'),
      );
      next.writeText(const CellOffset(1, 0), 'bc');
      next.writeGrapheme(const CellOffset(3, 0), 'd');
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      expect(
        sink.output,
        '\x1B[H${osc8Open('https://x')}a\x1B[2C${osc8Close}d',
      );
      expect(
        sink.output,
        isNot(contains('b')),
        reason: 'gap cells must not be rewritten under the open link',
      );
    });

    test('a cursor jump keeps a same-link run open without painting the gap',
        () {
      // Linked 'a' at 0 and linked 'p' at 15 (same URI); cells 1-14 unchanged.
      // The link stays open across the jump (one open, one close), and the
      // skipped cells are never written — so they cannot be linked.
      final prev = CellBuffer(const CellSize(20, 1));
      final next = CellBuffer(const CellSize(20, 1));
      const style = CellStyle(linkUri: 'https://x');
      next.writeGrapheme(const CellOffset(0, 0), 'a', style: style);
      next.writeGrapheme(const CellOffset(15, 0), 'p', style: style);
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      expect(sink.output, '\x1B[H${osc8Open('https://x')}a\x1B[14Cp$osc8Close');
      expect('\x1B]8'.allMatches(sink.output).length, 2,
          reason: 'exactly one open + one close across the whole jump');
    });

    test('a cursor jump to an unlinked cell closes before the destination', () {
      // Linked 'a' at 0, plain 'p' at 15. The close lands before 'p', and the
      // 14 skipped cells are not painted.
      final prev = CellBuffer(const CellSize(20, 1));
      final next = CellBuffer(const CellSize(20, 1));
      next.writeGrapheme(
        const CellOffset(0, 0),
        'a',
        style: const CellStyle(linkUri: 'https://x'),
      );
      next.writeGrapheme(const CellOffset(15, 0), 'p');
      final sink = StringAnsiSink();

      linker.renderDiff(prev, next, sink);

      expect(
        sink.output,
        '\x1B[H${osc8Open('https://x')}a\x1B[14C${osc8Close}p',
      );
    });
  });

  group('hyperlinks: false is byte-identical to a link-free buffer', () {
    test('links emit zero bytes and match the link-stripped render', () {
      // Covers the decoupling corners: a colored linked run, a link-ONLY cell
      // (no visible style — the case that could spuriously reset), and a
      // trailing empty. Rendered with the default renderer (hyperlinks: false).
      const renderer = AnsiRenderer(synchronizedOutput: false);

      CellBuffer build({required bool withLinks}) {
        final buf = CellBuffer(const CellSize(6, 1));
        buf.writeText(
          const CellOffset(0, 0),
          'ab',
          style: CellStyle(
            foreground: const AnsiColor(4),
            linkUri: withLinks ? 'https://x' : null,
          ),
        );
        buf.writeGrapheme(
          const CellOffset(2, 0),
          'c',
          style: CellStyle(linkUri: withLinks ? 'https://y' : null),
        );
        return buf;
      }

      final prev = CellBuffer(const CellSize(6, 1));
      final linkedSink = StringAnsiSink();
      final plainSink = StringAnsiSink();
      renderer.renderDiff(prev, build(withLinks: true), linkedSink);
      renderer.renderDiff(prev, build(withLinks: false), plainSink);

      expect(linkedSink.output, isNot(contains('\x1B]8')),
          reason: 'no OSC 8 bytes when hyperlinks is disabled');
      expect(
        linkedSink.output,
        plainSink.output,
        reason: 'a link must not perturb the byte stream when disabled',
      );
    });
  });
}
