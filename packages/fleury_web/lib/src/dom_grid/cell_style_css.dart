import 'package:fleury/fleury_host.dart';

/// Default foreground/background used when a cell leaves them unset (and as
/// the swap targets for `inverse`). Match these to the host page's theme.
const RgbColor kDefaultForeground = RgbColor(208, 208, 208);
const RgbColor kDefaultBackground = RgbColor(30, 30, 30);

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
  if (fg != null) parts.add('color:${rgbCss(fg)}');
  if (bg != null) parts.add('background-color:${rgbCss(bg)}');
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
    // Fill the whole cell box (not just the inline content area), so the line
    // reaches the row edges and meets the cells above/below with no gap.
    'display:inline-block',
    'height:100%',
    'vertical-align:top',
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
