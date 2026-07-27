import 'package:fleury/fleury_core.dart';

/// Tokyo Night — A clean, dark, blue-leaning editor theme.
///
/// <https://github.com/folke/tokyonight.nvim>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking Tokyo Night is to get *Tokyo Night's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData tokyoNight = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x1A,0x1B,0x26),
    surface: RgbColor(0x29,0x2E,0x42),
    foreground: RgbColor(0xC0,0xCA,0xF5),
    primary: RgbColor(0x7A,0xA2,0xF7),
    focus: RgbColor(0xBB,0x9A,0xF7),
    success: RgbColor(0x9E,0xCE,0x6A),
    warning: RgbColor(0xE0,0xAF,0x68),
    error: RgbColor(0xF7,0x76,0x8E),
    info: RgbColor(0x7D,0xCF,0xFF),
  ),
);
