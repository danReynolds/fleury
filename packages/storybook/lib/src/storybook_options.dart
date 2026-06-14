import 'package:fleury/fleury.dart';

enum StorybookThemeMode { cyber, terminal, dark, light, highContrast }

// Cyber palette — a dark, near-neutral background with a cool-green accent, for
// terminal devs. Greens lean cyan (cool), not warm/lime; status colors stay
// semantically obvious (amber warn, coral error, cyan info).
const _cyberBg = RgbColor(0x0E, 0x0F, 0x13); // near-black, faint cool tint
const _cyberFg = RgbColor(0xC8, 0xD3, 0xE0); // light cool grey
const _cyberGreen = Colors.mint; // cool mint-green accent (framework default primary)
const _cyberMuted = RgbColor(0x6B, 0x73, 0x84); // readable secondary grey

const ThemeData _cyberTheme = ThemeData(
  brightness: Brightness.dark,
  textStyle: CellStyle(foreground: _cyberFg),
  mutedStyle: CellStyle(foreground: _cyberMuted),
  // Selected rows read as a green bar; focused panels/controls glow green.
  selectionStyle: CellStyle(
    foreground: _cyberBg,
    background: _cyberGreen,
    bold: true,
  ),
  focusedStyle: CellStyle(bold: true, foreground: _cyberGreen),
  borderStyle: BorderStyle.rounded,
  colorScheme: ColorScheme(
    foreground: _cyberFg,
    background: _cyberBg,
    primary: _cyberGreen,
    success: RgbColor(0x3D, 0xDC, 0x97),
    warning: RgbColor(0xF5, 0xC2, 0x11),
    error: RgbColor(0xFF, 0x5C, 0x57),
    info: RgbColor(0x56, 0xC2, 0xFF),
  ),
);

enum StorybookViewportPreset {
  fit,
  compact80x24,
  standard100x30,
  wide120x40,
  narrow60x20,
}

ThemeData storybookThemeFor(StorybookThemeMode mode) {
  return switch (mode) {
    StorybookThemeMode.cyber => _cyberTheme,
    StorybookThemeMode.terminal => const ThemeData(),
    StorybookThemeMode.dark => ThemeData.dark(),
    StorybookThemeMode.light => ThemeData.light(),
    StorybookThemeMode.highContrast => ThemeData.dark().copyWith(
      selectionStyle: const CellStyle(inverse: true, bold: true),
      focusedStyle: const CellStyle(bold: true, underline: true),
      mutedStyle: const CellStyle(dim: false, foreground: AnsiColor(8)),
      borderStyle: BorderStyle.ascii,
      colorScheme: const ColorScheme(primary: AnsiColor(11)),
    ),
  };
}

String storybookThemeLabel(StorybookThemeMode mode) {
  return switch (mode) {
    StorybookThemeMode.cyber => 'Cyber',
    StorybookThemeMode.terminal => 'Terminal',
    StorybookThemeMode.dark => 'Dark',
    StorybookThemeMode.light => 'Light',
    StorybookThemeMode.highContrast => 'High contrast',
  };
}

String storybookViewportLabel(StorybookViewportPreset preset) {
  return switch (preset) {
    StorybookViewportPreset.fit => 'Fit',
    StorybookViewportPreset.compact80x24 => '80x24',
    StorybookViewportPreset.standard100x30 => '100x30',
    StorybookViewportPreset.wide120x40 => '120x40',
    StorybookViewportPreset.narrow60x20 => '60x20',
  };
}

CellSize? storybookViewportSize(StorybookViewportPreset preset) {
  return switch (preset) {
    StorybookViewportPreset.fit => null,
    StorybookViewportPreset.compact80x24 => const CellSize(80, 24),
    StorybookViewportPreset.standard100x30 => const CellSize(100, 30),
    StorybookViewportPreset.wide120x40 => const CellSize(120, 40),
    StorybookViewportPreset.narrow60x20 => const CellSize(60, 20),
  };
}
