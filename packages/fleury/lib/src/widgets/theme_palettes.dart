import '../rendering/cell.dart';
import 'theme.dart';

/// A built-in [ThemeData] with a display name, for theme pickers and galleries.
final class NamedTheme {
  const NamedTheme(this.name, this.data);

  /// Human-readable label (e.g. `'Nord'`).
  final String name;

  /// The theme itself.
  final ThemeData data;
}

/// Built-in named themes — the palettes you commonly see in terminals and
/// editors — mapped onto Fleury's lean [ColorScheme] roles.
///
/// Each is a plain `const` [ThemeData] you can hand to a [Theme] (or `runApp`):
///
/// ```dart
/// Theme(data: ThemePalettes.nord, child: app);
/// ```
///
/// Unlike the terminal-transparent default scheme, a named palette sets an
/// **explicit opaque** [ColorScheme.background]/[ColorScheme.surface]/
/// [ColorScheme.foreground] — the whole point of picking "Nord" is to get
/// *Nord's* look, not to blend with the user's terminal. Mappings are curated
/// (a 16-colour palette onto 9 semantic roles is a judgement call); hexes are
/// the projects' canonical values. Iterate [all] for a picker.
///
/// Sources: nordtheme.com · draculatheme.com · github.com/morhetz/gruvbox ·
/// ethanschoonover.com/solarized · catppuccin (Mocha) · folke/tokyonight ·
/// atom One Dark.
abstract final class ThemePalettes {
  const ThemePalettes._();

  /// Arctic, north-bluish. <https://www.nordtheme.com>
  static const ThemeData nord = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme(
      background: RgbColor(0x2E, 0x34, 0x40),
      surface: RgbColor(0x3B, 0x42, 0x52),
      foreground: RgbColor(0xD8, 0xDE, 0xE9),
      primary: RgbColor(0x88, 0xC0, 0xD0),
      focus: RgbColor(0x81, 0xA1, 0xC1),
      success: RgbColor(0xA3, 0xBE, 0x8C),
      warning: RgbColor(0xEB, 0xCB, 0x8B),
      error: RgbColor(0xBF, 0x61, 0x6A),
      info: RgbColor(0x5E, 0x81, 0xAC),
    ),
  );

  /// Dark with vivid purple/pink accents. <https://draculatheme.com>
  static const ThemeData dracula = ThemeData(
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

  /// Retro, warm, high-contrast. <https://github.com/morhetz/gruvbox>
  static const ThemeData gruvboxDark = ThemeData(
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

  /// Precision colours for the dark background.
  /// <https://ethanschoonover.com/solarized>
  static const ThemeData solarizedDark = ThemeData(
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

  /// Precision colours for the light background.
  /// <https://ethanschoonover.com/solarized>
  static const ThemeData solarizedLight = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme(
      background: RgbColor(0xFD, 0xF6, 0xE3),
      surface: RgbColor(0xEE, 0xE8, 0xD5),
      foreground: RgbColor(0x65, 0x7B, 0x83),
      primary: RgbColor(0x26, 0x8B, 0xD2),
      focus: RgbColor(0x2A, 0xA1, 0x98),
      success: RgbColor(0x85, 0x99, 0x00),
      warning: RgbColor(0xB5, 0x89, 0x00),
      error: RgbColor(0xDC, 0x32, 0x2F),
      info: RgbColor(0x26, 0x8B, 0xD2),
    ),
  );

  /// Soothing pastel, the "Mocha" flavour. <https://catppuccin.com>
  static const ThemeData catppuccinMocha = ThemeData(
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

  /// A clean, dark, blue-leaning editor theme.
  /// <https://github.com/folke/tokyonight.nvim>
  static const ThemeData tokyoNight = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme(
      background: RgbColor(0x1A, 0x1B, 0x26),
      surface: RgbColor(0x29, 0x2E, 0x42),
      foreground: RgbColor(0xC0, 0xCA, 0xF5),
      primary: RgbColor(0x7A, 0xA2, 0xF7),
      focus: RgbColor(0xBB, 0x9A, 0xF7),
      success: RgbColor(0x9E, 0xCE, 0x6A),
      warning: RgbColor(0xE0, 0xAF, 0x68),
      error: RgbColor(0xF7, 0x76, 0x8E),
      info: RgbColor(0x7D, 0xCF, 0xFF),
    ),
  );

  /// The Atom / VS Code "One Dark" palette (also Fleury's default dark accent).
  static const ThemeData oneDark = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme(
      background: RgbColor(0x28, 0x2C, 0x34),
      surface: RgbColor(0x3B, 0x40, 0x48),
      foreground: RgbColor(0xAB, 0xB2, 0xBF),
      primary: RgbColor(0x61, 0xAF, 0xEF),
      focus: RgbColor(0xC6, 0x78, 0xDD),
      success: RgbColor(0x98, 0xC3, 0x79),
      warning: RgbColor(0xE5, 0xC0, 0x7B),
      error: RgbColor(0xE0, 0x6C, 0x75),
      info: RgbColor(0x56, 0xB6, 0xC2),
    ),
  );

  /// Every built-in palette, in display order — for pickers and galleries.
  static const List<NamedTheme> all = [
    NamedTheme('Nord', nord),
    NamedTheme('Dracula', dracula),
    NamedTheme('Gruvbox Dark', gruvboxDark),
    NamedTheme('Tokyo Night', tokyoNight),
    NamedTheme('Catppuccin Mocha', catppuccinMocha),
    NamedTheme('One Dark', oneDark),
    NamedTheme('Solarized Dark', solarizedDark),
    NamedTheme('Solarized Light', solarizedLight),
  ];
}
