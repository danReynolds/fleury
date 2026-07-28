import 'catppuccin.dart';
import 'dracula.dart';
import 'gruvbox.dart';
import 'named_theme.dart';
import 'nord.dart';
import 'one_dark.dart';
import 'solarized_dark.dart';
import 'solarized_light.dart';
import 'tokyo_night.dart';

/// Every theme this package ships, in display order — hand this straight to a
/// picker:
///
/// ```dart
/// Select<int>(
///   options: [
///     for (final (i, t) in fleuryThemes.indexed)
///       SelectOption(value: i, label: t.name),
///   ],
///   value: index,
///   onChanged: (i) => setState(() => index = i),
/// );
/// ```
///
/// Dark themes first, then light, because the overwhelming majority of
/// terminal users are on a dark background.
const List<NamedTheme> fleuryThemes = <NamedTheme>[
  NamedTheme('Nord', nord),
  NamedTheme('Dracula', dracula),
  NamedTheme('Gruvbox Dark', gruvboxDark),
  NamedTheme('Tokyo Night', tokyoNight),
  NamedTheme('Catppuccin Mocha', catppuccinMocha),
  NamedTheme('One Dark', oneDark),
  NamedTheme('Solarized Dark', solarizedDark),
  NamedTheme('Solarized Light', solarizedLight),
];
