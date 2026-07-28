// The cell-box fill rule: anything that paints a background must cover the
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
  });
}
