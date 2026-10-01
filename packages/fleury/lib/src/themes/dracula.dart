import 'package:fleury/fleury_core.dart';

/// Dracula — Dark, with vivid purple and pink accents.
///
/// <https://draculatheme.com>
///
/// Sets an explicit opaque background/surface/foreground: the point of
/// picking Dracula is to get *Dracula's* look, not to blend with the
/// user's terminal. The 9-role mapping is curated — a full editor palette
/// onto Fleury's lean [ColorScheme] is a judgement call; the hexes are the
/// project's canonical values.
const ThemeData dracula = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x28, 0x2A, 0x36),
    surface: RgbColor(0x44, 0x47, 0x5A),
    foreground: RgbColor(0xF8, 0xF8, 0xF2),
    primary: RgbColor(0xBD, 0x93, 0xF9),
    focus: RgbColor(0xFF, 0x79, 0xC6),
    success: RgbColor(0x50, 0xFA, 0x7B),
    warning: RgbColor(0xF1, 0xFA, 0x8C),
    error: RgbColor(0xFF, 0x55, 0x55),
    info: RgbColor(0x8B, 0xE9, 0xFD),
  ),
);
