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
