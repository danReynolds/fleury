/// Optional ready-made themes for Fleury.
///
/// Each theme is a plain `const ThemeData` — hand one to `FleuryApp` or wrap
/// a subtree in a `Theme`:
///
/// ```dart
/// import 'package:fleury/fleury_core.dart';
/// import 'package:fleury/themes.dart';
///
/// // Hand this root to `runApp` on a terminal or `mountApp` in a browser —
/// // the theme is the same object either way. (The web-safe `fleury_core`
/// // barrel is deliberate: this package must stay dart2js-compilable.)
/// const app = FleuryApp(
///   title: 'My app',
///   theme: tokyoNight,
///   home: MyApp(),
/// );
/// ```
///
/// Nothing here is special: a theme is data, and yours can sit alongside
/// these. See `doc/themes.md` for how to build one, and `fleuryThemes` for
/// the full list ready to drop into a picker.
library;

export 'src/themes/catppuccin.dart';
export 'src/themes/dracula.dart';
export 'src/themes/gruvbox.dart';
export 'src/themes/named_theme.dart';
export 'src/themes/nord.dart';
export 'src/themes/one_dark.dart';
export 'src/themes/registry.dart';
export 'src/themes/solarized_dark.dart';
export 'src/themes/solarized_light.dart';
export 'src/themes/tokyo_night.dart';
