import 'package:fleury/fleury_host.dart';

/// Default foreground/background used when a cell leaves them unset (and as
/// the swap targets for `inverse`). Match these to the host page's theme.
const RgbColor kDefaultForeground = RgbColor(208, 208, 208);
const RgbColor kDefaultBackground = RgbColor(30, 30, 30);

/// Declarations that make a span cover its whole cell box.
///
/// **The rule: anything that paints a background must fill the cell box.**
///
/// An `inline` box paints its background over the font's *content* area —
/// ascent + descent — not the line box. A grid row is a line box, and cell
/// height is line-height, which is almost always taller than the content area
/// (14px text in a 17.5px row leaves 0.5px bare at each edge). Every row then
/// shows a sliver of whatever is behind the grid, and stacked rows read as
/// horizontal scan lines through any filled region.
///
/// This was previously rediscovered and patched per glyph class — first for
/// box-drawing, then for block elements — each time as a local fix. It is a
/// property of CSS inline layout, not of any glyph, so it belongs here, once,
/// applied wherever a background is painted.
///
/// `height` is declared twice on purpose. `100%` resolves against the row,
/// which the live DOM grid sizes explicitly; `1lh` is the line box itself and
/// needs no help from the parent, so it also covers the static-HTML renderer
/// whose rows are auto-height. A browser too old for `lh` (pre-2023) ignores
/// that declaration and keeps the `100%` behaviour.
const String kFillsCellBoxCss =
    'display:inline-block;height:100%;height:1lh;vertical-align:top';

/// Converts Fleury cell style into a compact inline CSS declaration.
String cellStyleToCss(CellStyle style) {
  Color? fg = style.foreground;
  Color? bg = style.background;
  if (style.inverse) {
    final swappedFg = bg ?? kDefaultBackground;
    final swappedBg = fg ?? kDefaultForeground;
    fg = swappedFg;
    bg = swappedBg;
  }

  final parts = <String>[];
  if (fg != null) {
    parts.add('color:${rgbCss(fg)}');
  } else if (style.linkUri != null && isSafeLinkScheme(style.linkUri!)) {
    // A safe link renders as an <a>, whose UA color (#0000EE blue) would
    // otherwise win over the row's inherited foreground. Pin it to the default
    // foreground so a link reads as default-fg + underline, never browser blue.
    // Link-free runs (and links with an explicit fg) are unaffected.
    parts.add('color:${rgbCss(kDefaultForeground)}');
  }
  if (bg != null) {
    parts
      ..add('background-color:${rgbCss(bg)}')
      // A painted background must cover the whole cell (see [kFillsCellBoxCss]).
      // Gated on there being one: a span with nothing to paint gains nothing
      // from becoming an inline-block, and staying on the plain inline path
      // keeps the common case cheap.
      ..add(kFillsCellBoxCss);
  }
  if (style.bold) parts.add('font-weight:700');
  if (style.dim) parts.add('opacity:.6');
  if (style.italic) parts.add('font-style:italic');
  final decorations = <String>[
    if (style.underline) 'underline',
    if (style.strikethrough) 'line-through',
  ];
  if (decorations.isNotEmpty) {
    parts.add('text-decoration:${decorations.join(' ')}');
  }
  return parts.join(';');
}

String rgbCss(Color color) {
  final c = color.toRgb();
  return 'rgb(${c.r}, ${c.g}, ${c.b})';
}

/// Inline CSS that paints a block-element glyph as solid rectangles instead of
/// relying on the font glyph.
///
/// A font glyph cannot fill its cell in a browser, in either axis. Vertically,
/// the row is a line box and the ink is only the font's content area — `█` in
/// a 17.5px row measures 16.45px tall, so a bar chart shows a scan line at
/// every row boundary. Horizontally, the grid carries a sub-pixel
/// `letter-spacing` so text flows on the device-pixel-snapped pitch (see
/// `DomGridSurface._rootStyle`), and that space lands *between* glyphs rather
/// than widening them — so two adjacent `█` no longer touch and a `barWidth: 2`
/// bar gets a hairline straight down its middle. Painting the ink as a CSS
/// rectangle sized from the cell box is exact in both axes and independent of
/// the font entirely.
///
/// [rects] is a [blockElementRects] result; the span's text should be spaces so
/// no glyph is drawn over the rectangles. Rectangles use the cell foreground;
/// the cell background sits behind them.
///
/// The span may cover several cells, in which case the rectangles are sized as
/// a percentage of the whole run — correct only for full-width ink, which is
/// exactly what [blockRectsSpanFullWidth] gates coalescing on.
String blockElementCss(CellStyle style, List<BlockRect> rects) {
  Color? fg = style.foreground;
  Color? bg = style.background;
  if (style.inverse) {
    final swappedFg = bg ?? kDefaultBackground;
    bg = fg ?? kDefaultForeground;
    fg = swappedFg;
  }

  final positions = <String>[];
  final sizes = <String>[];
  for (final rect in rects) {
    // Every rectangle is edge-anchored on both axes (asserted by BlockRect), so
    // a keyword pair places it exactly — no percentage-position arithmetic,
    // whose reference is the *leftover* space rather than the box.
    positions.add(
      '${rect.left == 0 ? 'left' : 'right'} '
      '${rect.top == 0 ? 'top' : 'bottom'}',
    );
    sizes.add('${_eighths[rect.width]} ${_eighths[rect.height]}');
  }

  final images = List.filled(
    positions.length,
    'linear-gradient(currentColor,currentColor)',
  );
  final parts = <String>[
    // Solid ink must reach the row edges and meet its neighbours above and
    // below with no seam — the same rule as any painted cell.
    kFillsCellBoxCss,
    'color:${rgbCss(fg ?? kDefaultForeground)}',
    if (bg != null) 'background-color:${rgbCss(bg)}',
    'background-image:${images.join(',')}',
    'background-position:${positions.join(',')}',
    'background-size:${sizes.join(',')}',
    'background-repeat:no-repeat',
  ];
  if (style.dim) parts.add('opacity:.6');
  return parts.join(';');
}

/// `n/8` as an exact CSS percentage — indexed by eighths, so no float
/// formatting runs on the per-frame path.
const List<String> _eighths = [
  '0%',
  '12.5%',
  '25%',
  '37.5%',
  '50%',
  '62.5%',
  '75%',
  '87.5%',
  '100%',
];

/// Inline CSS that paints a box-drawing glyph as crisp gradient lines instead
/// of relying on the font glyph (which does not tile vertically in a browser).
/// [mask] is a [boxDrawingMask] result; the span's text should be spaces so no
/// glyph is drawn over the lines. The lines use the cell foreground; the cell
/// background sits behind them.
String boxDrawingCss(CellStyle style, int mask) {
  Color? fg = style.foreground;
  Color? bg = style.background;
  if (style.inverse) {
    final swappedFg = bg ?? kDefaultBackground;
    bg = fg ?? kDefaultForeground;
    fg = swappedFg;
  }

  final positions = <String>[];
  final sizes = <String>[];
  void seg(String pos, String size) {
    positions.add(pos);
    sizes.add(size);
  }

  final hasN = (mask & boxSegmentNorth) != 0;
  final hasS = (mask & boxSegmentSouth) != 0;
  final hasE = (mask & boxSegmentEast) != 0;
  final hasW = (mask & boxSegmentWest) != 0;

  // A through-line ('│', '─', and the bars of junctions) is one full-length
  // gradient — no centre seam. A corner or T-stub is a half from the centre.
  // Thickness is 1px.
  if (hasN && hasS) {
    seg('center', '1px 100%');
  } else if (hasN) {
    seg('center top', '1px 50%');
  } else if (hasS) {
    seg('center bottom', '1px 50%');
  }
  if (hasE && hasW) {
    seg('center', '100% 1px');
  } else if (hasE) {
    seg('right center', '50% 1px');
  } else if (hasW) {
    seg('left center', '50% 1px');
  }

  final images = List.filled(
    positions.length,
    'linear-gradient(currentColor,currentColor)',
  );
  final parts = <String>[
    // A box-drawing line must reach the row edges and meet its neighbours
    // above and below with no seam — the same rule as any painted cell.
    kFillsCellBoxCss,
    'color:${rgbCss(fg ?? kDefaultForeground)}',
    if (bg != null) 'background-color:${rgbCss(bg)}',
    'background-image:${images.join(',')}',
    'background-position:${positions.join(',')}',
    'background-size:${sizes.join(',')}',
    'background-repeat:no-repeat',
  ];
  if (style.dim) parts.add('opacity:.6');
  return parts.join(';');
}
