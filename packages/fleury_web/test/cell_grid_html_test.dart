import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/cell_grid_html.dart';
import 'package:test/test.dart';

/// Strips the span markup back to the visible glyphs, one `\n`-joined line
/// per row div — the inverse of the renderer, for the fidelity invariant.
String _visibleText(String html) {
  final rows = html
      .split('<div class="r">')
      .where((s) => s.contains('</div>'))
      .map((s) => s.substring(0, s.indexOf('</div>')));
  String strip(String row) => row
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  return rows.map(strip).join('\n');
}

/// Builds a buffer and paints [paint] into it with the *real* width resolver
/// and grapheme segmentation (via `writeText`), so these tests exercise the
/// genuine cell model — not a hand-mocked grid.
CellBuffer frame(int cols, int rows, void Function(CellBuffer b) paint) {
  final buffer = CellBuffer(CellSize(cols, rows));
  paint(buffer);
  return buffer;
}

void main() {
  group('stylesheet', () {
    test('locks terminal text shaping invariants', () {
      expect(cellGridCss, contains('white-space: pre;'));
      expect(cellGridCss, contains('tab-size: 1;'));
      expect(cellGridCss, contains('font-kerning: none;'));
      expect(cellGridCss, contains('font-variant-ligatures: none;'));
      expect(
        cellGridCss,
        contains('font-feature-settings: "liga" 0, "clig" 0;'),
      );
      expect(cellGridCss, contains('letter-spacing: 0;'));
    });
  });

  group('combining marks', () {
    test('é (e + U+0301) survives intact as one grapheme', () {
      const combining = 'café'; // 'café' with a combining acute accent
      final html = renderFrameHtml(
        frame(10, 1, (b) => b.writeText(const CellOffset(0, 0), combining)),
      );
      // The base letter and its combining mark must stay together and not be
      // dropped, reordered, or split across spans.
      expect(html, contains('é'));
      expect(html, contains('caf'));
    });
  });

  group('ZWJ emoji', () {
    test('family emoji stays a single contiguous cluster', () {
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';
      final html = renderFrameHtml(
        frame(12, 1, (b) => b.writeText(const CellOffset(0, 1 - 1), family)),
      );
      // The whole ZWJ sequence appears, unbroken, exactly once.
      expect(html, contains(family));
      expect(family.allMatches(html).length, 1);
    });
  });

  group('wide CJK', () {
    test('each wide glyph is one pinned-width span; no continuation echo', () {
      const cjk = '状態'; // two width-2 ideographs
      final html = renderFrameHtml(
        frame(10, 1, (b) => b.writeText(const CellOffset(0, 0), cjk)),
      );
      // Both ideographs render as dedicated 2ch spans.
      expect(html, contains('class="w2"'));
      expect(RegExp('class="w2"[^>]*>状<').hasMatch(html), isTrue);
      expect(RegExp('class="w2"[^>]*>態<').hasMatch(html), isTrue);
      // The continuation cell must not re-emit the glyph.
      expect('状'.allMatches(html).length, 1);
      expect('態'.allMatches(html).length, 1);
    });
  });

  group('box drawing', () {
    test('a bordered box draws its border with CSS lines, not font glyphs', () {
      // 5 cols wide, 3 rows tall.
      final html = renderFrameHtml(
        frame(5, 3, (b) {
          b.writeText(const CellOffset(0, 0), '┌───┐');
          b.writeText(const CellOffset(0, 1), '│   │');
          b.writeText(const CellOffset(0, 2), '└───┘');
        }),
      );
      // Box-drawing glyphs don't tile vertically as DOM text (the glyph ink is
      // shorter than the cell), so they're painted as CSS gradient lines and
      // the literal glyphs are gone from the markup.
      expect(html, contains('linear-gradient(currentColor,currentColor)'));
      for (final glyph in ['┌', '┐', '└', '┘', '─', '│']) {
        expect(
          html,
          isNot(contains(glyph)),
          reason: '$glyph should be CSS-drawn',
        );
      }
      // Three rows emitted.
      expect('<div class="r">'.allMatches(html).length, 3);
    });

    test('vertical and horizontal runs paint full-length lines', () {
      // A vertical bar and a horizontal run get a single full-length gradient
      // (no centre seam); a horizontal run coalesces into one span.
      final vertical = renderFrameHtml(
        frame(1, 1, (b) => b.writeText(const CellOffset(0, 0), '│')),
      );
      expect(vertical, contains('background-size:1px 100%'));
      expect(vertical, contains('display:inline-block'));

      final horizontal = renderFrameHtml(
        frame(4, 1, (b) => b.writeText(const CellOffset(0, 0), '────')),
      );
      expect(horizontal, contains('background-size:100% 1px'));
      // One coalesced span for the whole run (4 spaces, no glyphs).
      expect('linear-gradient'.allMatches(horizontal).length, 1);
    });

    test('a corner draws two half segments', () {
      final html = renderFrameHtml(
        frame(1, 1, (b) => b.writeText(const CellOffset(0, 0), '╭')),
      );
      // Rounded top-left = south + east half lines.
      expect(html, contains('1px 50%'));
      expect(html, contains('50% 1px'));
    });
  });

  group('styles', () {
    test('bold + green foreground map to CSS', () {
      final html = renderFrameHtml(
        frame(6, 1, (b) {
          b.writeText(
            const CellOffset(0, 0),
            'OK',
            style: const CellStyle(foreground: Colors.green, bold: true),
          );
        }),
      );
      expect(html, contains('font-weight:700'));
      expect(html, contains('color:rgb(0, 205, 0)')); // ANSI green → RGB
    });

    test('inverse swaps foreground into the background channel', () {
      final html = renderFrameHtml(
        frame(6, 1, (b) {
          b.writeText(
            const CellOffset(0, 0),
            'SEL',
            style: const CellStyle(foreground: Colors.red, inverse: true),
          );
        }),
      );
      // fg(red) becomes the background; the unset bg becomes the default fg.
      expect(html, contains('background-color:rgb(205, 0, 0)'));
      expect(
        html,
        contains(
          'color:rgb(${kDefaultBackground.r}, '
          '${kDefaultBackground.g}, ${kDefaultBackground.b})',
        ),
      );
    });

    test('underline and strikethrough combine in one decoration', () {
      final html = renderFrameHtml(
        frame(6, 1, (b) {
          b.writeText(
            const CellOffset(0, 0),
            'x',
            style: const CellStyle(underline: true, strikethrough: true),
          );
        }),
      );
      expect(html, contains('text-decoration:underline line-through'));
    });
  });

  group('run coalescing', () {
    test('same-style neighbours merge into a single span', () {
      final html = renderFrameHtml(
        frame(8, 1, (b) => b.writeText(const CellOffset(0, 0), 'abc')),
      );
      // The three default-style letters share one span rather than three.
      expect(html, contains('>abc'));
      expect(RegExp(r'<span[^>]*>a</span>').hasMatch(html), isFalse);
    });
  });

  group('protocol placeholders', () {
    test('mark unsupported inline images explicitly', () {
      final html = renderFrameHtml(
        frame(
          4,
          1,
          (b) => b.writeProtocol(
            const CellOffset(1, 0),
            'image-bytes',
            width: 2,
            height: 1,
          ),
        ),
      );

      expect(html, contains('class="proto"'));
      expect(html, contains('title="unsupported inline image"'));
      expect(html, contains('data-fleury-cell-kind="protocol-placeholder"'));
      expect(html, contains('data-fleury-unsupported="inline-image"'));
      expect(html, contains('>▩</span>'));
      expect(html, isNot(contains('image-bytes')));
    });
  });

  group('fidelity invariant', () {
    test('visible HTML text equals the buffer\'s own textInRange', () {
      // Box-drawing glyphs are intentionally excluded: they're painted as CSS
      // lines (rendered as spaces), so the visible text no longer mirrors them.
      // Real text content must still round-trip exactly.
      final buffer = frame(24, 4, (b) {
        b.writeText(const CellOffset(0, 0), 'café 状態');
        b.writeText(
          const CellOffset(2, 1),
          'naïve 日本語',
          style: const CellStyle(foreground: Colors.lime, bold: true),
        );
        b.writeText(const CellOffset(5, 3), 'résumé');
      });
      final visible = _visibleText(renderFrameHtml(buffer));
      final expected = buffer.textInRange(
        CellRect(offset: const CellOffset(0, 0), size: buffer.size),
      );
      expect(visible, expected);
    });
  });

  group('html safety', () {
    test('angle brackets and ampersands are escaped', () {
      final html = renderFrameHtml(
        frame(8, 1, (b) => b.writeText(const CellOffset(0, 0), '<a&b>')),
      );
      expect(html, contains('&lt;a&amp;b&gt;'));
      expect(html, isNot(contains('<a&b>')));
    });
  });
}
