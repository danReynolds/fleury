import 'package:fleury/fleury_core.dart';

/// Catppuccin Mocha — Soothing pastel — the darkest of the four Catppuccin flavours.
///
/// <https://catppuccin.com>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking Catppuccin Mocha is to get *Catppuccin Mocha's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData catppuccinMocha = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x1E, 0x1E, 0x2E),
    surface: RgbColor(0x31, 0x32, 0x44),
    foreground: RgbColor(0xCD, 0xD6, 0xF4),
    primary: RgbColor(0xCB, 0xA6, 0xF7),
    focus: RgbColor(0x89, 0xB4, 0xFA),
    success: RgbColor(0xA6, 0xE3, 0xA1),
    warning: RgbColor(0xF9, 0xE2, 0xAF),
    error: RgbColor(0xF3, 0x8B, 0xA8),
    info: RgbColor(0x89, 0xDC, 0xEB),
  ),
);
