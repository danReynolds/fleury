import 'package:fleury/fleury_core.dart';

/// Nord — Arctic, north-bluish — a cool six-hue palette.
///
/// <https://www.nordtheme.com>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking Nord is to get *Nord's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData nord = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x2E,0x34,0x40),
    surface: RgbColor(0x3B,0x42,0x52),
    foreground: RgbColor(0xD8,0xDE,0xE9),
    primary: RgbColor(0x88,0xC0,0xD0),
    focus: RgbColor(0x81,0xA1,0xC1),
    success: RgbColor(0xA3,0xBE,0x8C),
    warning: RgbColor(0xEB,0xCB,0x8B),
    error: RgbColor(0xBF,0x61,0x6A),
    info: RgbColor(0x5E,0x81,0xAC),
  ),
);
