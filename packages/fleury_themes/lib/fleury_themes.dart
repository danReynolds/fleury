/// Ready-made themes for Fleury.
///
/// Each theme is a plain `const ThemeData` — hand one to `runApp` or wrap a
/// subtree in a `Theme`:
///
/// ```dart
/// import 'package:fleury_themes/fleury_themes.dart';
///
/// runApp(const MyApp(), theme: tokyoNight);
/// ```
///
/// Nothing here is special: a theme is data, and yours can sit alongside
/// these. See the package README for how to build one, and `fleuryThemes` for
/// the full list ready to drop into a picker.
library;

export 'src/catppuccin.dart';
export 'src/dracula.dart';
export 'src/gruvbox.dart';
export 'src/named_theme.dart';
export 'src/nord.dart';
export 'src/one_dark.dart';
export 'src/registry.dart';
export 'src/solarized_dark.dart';
export 'src/solarized_light.dart';
export 'src/tokyo_night.dart';
