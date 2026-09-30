import 'package:fleury/fleury_core.dart';

/// Solarized Dark — Precision colours for machines and people, dark background.
///
/// <https://ethanschoonover.com/solarized>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking Solarized Dark is to get *Solarized Dark's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData solarizedDark = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x00, 0x2B, 0x36),
    surface: RgbColor(0x07, 0x36, 0x42),
    foreground: RgbColor(0x83, 0x94, 0x96),
    primary: RgbColor(0x26, 0x8B, 0xD2),
    focus: RgbColor(0x2A, 0xA1, 0x98),
    success: RgbColor(0x85, 0x99, 0x00),
    warning: RgbColor(0xB5, 0x89, 0x00),
    error: RgbColor(0xDC, 0x32, 0x2F),
    info: RgbColor(0x26, 0x8B, 0xD2),
  ),
);
