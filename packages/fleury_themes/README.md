# fleury_themes

Ready-made themes for [Fleury](https://github.com/danReynolds/fleury), mapped
onto Fleury's `ColorScheme` roles.

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury_themes/fleury_themes.dart';

void main() =>
    runApp(const FleuryApp(title: 'My app', theme: tokyoNight, home: MyApp()));
```

That's the whole API. Each theme is a plain `const ThemeData`, so it costs
nothing at runtime and works anywhere a theme is accepted — `FleuryApp`, a
`Theme` around a subtree, a test.

## The themes

| Theme | Constant | Brightness | Upstream |
| --- | --- | --- | --- |
| Nord | `nord` | dark | [nordtheme/nord](https://github.com/nordtheme/nord) |
| Dracula | `dracula` | dark | [dracula/dracula-theme](https://github.com/dracula/dracula-theme) |
| Gruvbox Dark | `gruvboxDark` | dark | [morhetz/gruvbox](https://github.com/morhetz/gruvbox) |
| Tokyo Night | `tokyoNight` | dark | [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim) |
| Catppuccin Mocha | `catppuccinMocha` | dark | [catppuccin/catppuccin](https://github.com/catppuccin/catppuccin) |
| One Dark | `oneDark` | dark | [atom/one-dark-syntax](https://github.com/atom/one-dark-syntax) |
| Solarized Dark | `solarizedDark` | dark | [altercation/solarized](https://github.com/altercation/solarized) |
| Solarized Light | `solarizedLight` | light | [altercation/solarized](https://github.com/altercation/solarized) |

[See them applied, live in your browser →](https://danreynolds.github.io/fleury/guides/theming/)

`fleuryThemes` is every theme with its display name, ready for a picker:

```dart
Select<int>(
  options: [
    for (final (i, theme) in fleuryThemes.indexed)
      SelectOption(value: i, label: theme.name),
  ],
  value: _index,
  onChanged: (i) => setState(() => _index = i),
);
```

## Writing your own

A theme is just a `ThemeData`, so you don't need this package to make one — see
the [theming guide](https://danreynolds.github.io/fleury/guides/theming/) for
the roles, the text styles, and the one rule worth knowing (pair colour with an
attribute, so cues survive `NO_COLOR`).

## Attribution

These are community colour schemes, each the work of its authors and included
here with attribution — see
[THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt). No upstream source code is
vendored, only published colour values; the mapping onto Fleury's nine roles is
this package's own work.
