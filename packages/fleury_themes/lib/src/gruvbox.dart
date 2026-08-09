import 'package:fleury/fleury_core.dart';

/// Gruvbox Dark — Retro groove — warm, high-contrast, low-saturation.
///
/// <https://github.com/morhetz/gruvbox>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking Gruvbox Dark is to get *Gruvbox Dark's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData gruvboxDark = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x28, 0x28, 0x28),
    surface: RgbColor(0x3C, 0x38, 0x36),
    foreground: RgbColor(0xEB, 0xDB, 0xB2),
    primary: RgbColor(0xFE, 0x80, 0x19),
    focus: RgbColor(0x83, 0xA5, 0x98),
    success: RgbColor(0xB8, 0xBB, 0x26),
    warning: RgbColor(0xFA, 0xBD, 0x2F),
    error: RgbColor(0xFB, 0x49, 0x34),
    info: RgbColor(0x83, 0xA5, 0x98),
  ),
);
