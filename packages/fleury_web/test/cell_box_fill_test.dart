// The cell-box fill rule: anything that paints a solid area must cover the
// whole cell box.
//
// An `inline` box paints its background over the font's content area, not the
// line box. A grid row IS a line box, so an inline background leaves the
// leading bare at both edges and stacked rows show the page through as
// horizontal scan lines. That was rediscovered twice — once for box-drawing
// glyphs, once for block elements — and patched locally each time, which left
// ordinary text carrying a background still broken. It only became obvious
// when a light theme put a pale fill against a dark page.
//
// A background is not the only thing that paints solid: so does the *ink* of a
// block-element glyph, and a glyph cannot be made to fill its cell in either
// axis. `█` in a 17.5px row measures 16.45px tall, and the grid's sub-pixel
// letter-spacing lands between glyphs instead of widening them — so a bar chart
// showed a scan line at every row edge plus a hairline down the middle of every
// two-cell-wide bar. Those glyphs are therefore painted as CSS rectangles
// rather than text, the same treatment box drawing already gets.
//
// These tests pin the RULE rather than any one glyph class, so a future run
// type cannot quietly reintroduce the seam.

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/cell_grid_html.dart';
import 'package:fleury_web/src/dom_grid/cell_style_css.dart';
import 'package:test/test.dart';

/// Every declaration the fill rule must contribute.
void _expectFillsCellBox(String css, {required String reason}) {
  expect(css, contains('display:inline-block'), reason: reason);
  expect(css, contains('vertical-align:top'), reason: reason);
  // Both height declarations: `100%` for the live grid's explicitly-sized
  // rows, `1lh` for auto-height rows and as the exact line-box answer.
  expect(css, contains('height:100%'), reason: reason);
  expect(css, contains('height:1lh'), reason: reason);
}

void main() {
  group('cellStyleToCss — the fill rule', () {
    test('a background makes the span cover the cell box', () {
      _expectFillsCellBox(
        cellStyleToCss(const CellStyle(background: RgbColor(253, 246, 227))),
        reason: 'a painted background must reach the row edges',
      );
    });

    test('inverse counts: the swapped background fills too', () {
      // `inverse` synthesises a background from the foreground. It paints, so
      // it fills — gating on the *effective* background, not the declared one.
      final css = cellStyleToCss(
        const CellStyle(foreground: RgbColor(10, 20, 30), inverse: true),
      );
      expect(css, contains('background-color:rgb(10, 20, 30)'));
      _expectFillsCellBox(css, reason: 'inverse paints a background');
    });

    test('a selection-style cell fills (the visible regression)', () {
      // selectionStyle is inverse in every shipped theme; this is the row that
      // showed seams in the theme styleguide.
      _expectFillsCellBox(
        cellStyleToCss(const CellStyle(inverse: true)),
        reason: 'selected rows paint a full-width background',
      );
    });

    test('no background stays on the cheap inline path', () {
      // Nothing is painted behind the glyph, so there is no seam to close and
      // no reason to pay for an inline-block box.
      final css = cellStyleToCss(
        const CellStyle(foreground: RgbColor(200, 200, 200), bold: true),
      );
      expect(css, contains('color:'));
      expect(css, isNot(contains('display:inline-block')));
      expect(css, isNot(contains('height:')));
    });

    test('an unstyled cell emits nothing at all', () {
      expect(cellStyleToCss(const CellStyle()), isEmpty);
    });

    test('the fill rule has one definition, reused', () {
      // Box drawing must not carry its own copy of the declarations — that
      // divergence is what let ordinary text fall behind.
      expect(boxDrawingCss(const CellStyle(), 0x1), contains(kFillsCellBoxCss));
      expect(
        cellStyleToCss(const CellStyle(background: RgbColor(1, 2, 3))),
        contains(kFillsCellBoxCss),
      );
    });
  });

  group('blockElementCss — solid ink fills too', () {
    String cssFor(String glyph, [CellStyle style = const CellStyle()]) =>
        blockElementCss(style, blockElementRects(glyph)!);

    test('a full block fills the entire cell box', () {
      final css = cssFor('█');
      _expectFillsCellBox(css, reason: '█ is a solid cell');
      expect(css, contains('background-size:100% 100%'));
      expect(css, contains('linear-gradient(currentColor,currentColor)'));
    });

    test('the eighth ramps are exact fractions anchored to their edge', () {
      // Vertical ramp grows up from the bottom; horizontal ramp from the left.
      expect(cssFor('▅'), contains('background-size:100% 62.5%'));
      expect(cssFor('▅'), contains('background-position:left bottom'));
      expect(cssFor('▏'), contains('background-size:12.5% 100%'));
      expect(cssFor('▏'), contains('background-position:left top'));
      expect(cssFor('▀'), contains('background-position:left top'));
      expect(cssFor('▐'), contains('background-position:right top'));
      expect(cssFor('▐'), contains('background-size:50% 100%'));
    });

    test('a multi-rectangle quadrant emits one layer per rectangle', () {
      // `▟` = right half + lower half, so two gradients in matching order.
      final css = cssFor('▟');
      expect(css, contains('background-position:right top,left bottom'));
      expect(css, contains('background-size:50% 100%,100% 50%'));
      expect('linear-gradient'.allMatches(css).length, 2);
    });

    test('an image cell keeps its background behind the ink', () {
      // The half-block image tier is two colors per cell: background behind,
      // foreground rectangle over half of it.
      final css = cssFor(
        '▀',
        const CellStyle(
          foreground: RgbColor(10, 20, 30),
          background: RgbColor(40, 50, 60),
        ),
      );
      expect(css, contains('color:rgb(10, 20, 30)'));
      expect(css, contains('background-color:rgb(40, 50, 60)'));
      expect(css, contains('background-size:100% 50%'));
      _expectFillsCellBox(css, reason: 'an image cell paints edge to edge');
    });

    test('the fill rule has one definition here too', () {
      expect(cssFor('█'), contains(kFillsCellBoxCss));
    });

    test('stipple textures are not claimed as rectangles', () {
      // Shades and braille are patterns, not solid fills — flattening them to
      // a tint would change how they read.
      for (final glyph in ['░', '▒', '▓', '⠿', '⣿']) {
        expect(blockElementRects(glyph), isNull, reason: glyph);
      }
    });
  });

  group('rendered markup', () {
    test('a filled row emits no bare inline background anywhere', () {
      // End to end through the static renderer: every background-carrying span
      // in real output must also fill. Catches a run type that bypasses
      // cellStyleToCss.
      final buffer = CellBuffer(const CellSize(12, 2));
      buffer.writeText(
        const CellOffset(0, 0),
        'filled row',
        style: const CellStyle(
          foreground: RgbColor(0, 0, 0),
          background: RgbColor(253, 246, 227),
        ),
      );
      buffer.writeText(
        const CellOffset(0, 1),
        'selected',
        style: const CellStyle(inverse: true),
      );
      final html = renderScreenHtml(buffer);

      final spans = RegExp(r'style="([^"]*)"')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .where((css) => css.contains('background-color:'));
      expect(spans, isNotEmpty, reason: 'fixture should produce filled spans');
      for (final css in spans) {
        _expectFillsCellBox(
          css,
          reason: 'a background in rendered markup that does not fill: $css',
        );
      }
    });

    test('a bar column is CSS rectangles, not block glyphs', () {
      // Two columns of a `barWidth: 2` bar chart: full cells below, a partial
      // `▅` cap on top. No literal block glyph may survive into the markup —
      // one would bring the font's ink-vs-cell mismatch back with it.
      final buffer = CellBuffer(const CellSize(2, 2));
      const green = CellStyle(foreground: RgbColor(61, 220, 151));
      buffer.writeText(const CellOffset(0, 0), '▅▅', style: green);
      buffer.writeText(const CellOffset(0, 1), '██', style: green);
      final html = renderScreenHtml(buffer);

      for (final glyph in ['█', '▅']) {
        expect(html, isNot(contains(glyph)), reason: '$glyph should be CSS');
      }
      // One span per row — the two cells of each row coalesce, so the rectangle
      // spans the whole bar and there is no interior edge to show a seam.
      expect('linear-gradient'.allMatches(html).length, 2);
      expect(html, contains('background-size:100% 100%'));
      expect(html, contains('background-size:100% 62.5%'));
    });

    test('a half-width glyph keeps one span per cell', () {
      // Coalescing `▌▌` would stretch a single half-width rectangle over both
      // cells and paint the wrong shape.
      final buffer = CellBuffer(const CellSize(2, 1));
      buffer.writeText(const CellOffset(0, 0), '▌▌');
      final html = renderScreenHtml(buffer);

      expect('linear-gradient'.allMatches(html).length, 2);
      expect(html, isNot(contains('▌')));
    });
  });
}
