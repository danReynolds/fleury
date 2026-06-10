import 'package:fleury/fleury.dart';

enum StorybookThemeMode { terminal, dark, light, highContrast }

enum StorybookViewportPreset {
  fit,
  compact80x24,
  standard100x30,
  wide120x40,
  narrow60x20,
}

ThemeData storybookThemeFor(StorybookThemeMode mode) {
  return switch (mode) {
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
