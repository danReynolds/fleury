import 'package:fleury/fleury_core.dart';

/// One Dark — The Atom / VS Code "One Dark" palette.
///
/// <https://github.com/atom/one-dark-syntax>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking One Dark is to get *One Dark's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData oneDark = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x28,0x2C,0x34),
    surface: RgbColor(0x3B,0x40,0x48),
    foreground: RgbColor(0xAB,0xB2,0xBF),
    primary: RgbColor(0x61,0xAF,0xEF),
    focus: RgbColor(0xC6,0x78,0xDD),
    success: RgbColor(0x98,0xC3,0x79),
    warning: RgbColor(0xE5,0xC0,0x7B),
    error: RgbColor(0xE0,0x6C,0x75),
    info: RgbColor(0x56,0xB6,0xC2),
  ),
);
