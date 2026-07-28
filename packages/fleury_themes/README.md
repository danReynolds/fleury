# fleury_themes

Ready-made themes for [Fleury](https://github.com/danReynolds/fleury) — Nord,
Dracula, Gruvbox, Solarized (dark + light), Catppuccin Mocha, Tokyo Night and
One Dark, mapped onto Fleury's `ColorScheme` roles.

```dart
import 'package:fleury_themes/fleury_themes.dart';

void main() => runApp(const MyApp(), theme: tokyoNight);
```

That's the whole API. Each theme is a plain `const ThemeData`, so it costs
nothing at runtime and works anywhere a theme is accepted — `runApp`, a
`Theme` around a subtree, a test.

## A picker in ten lines

`fleuryThemes` is every theme with its display name, ready for a menu:

```dart
Select<int>(
  options: [
    for (final (i, theme) in fleuryThemes.indexed)
      SelectOption(value: i, label: theme.name),
  ],
  value: _index,
  onChanged: (i) => setState(() => _index = i),
);

// ...then wrap your UI:
Theme(data: fleuryThemes[_index].data, child: child);
```

## Writing your own

A theme is data. There is no registration step and no base class — copy one of
these files, change the numbers, and you have one.

### The colour roles

`ColorScheme` is deliberately small: nine roles, not a 16-colour terminal
palette. Pick by **meaning**, not by hue.

| Role | What it means | Where it shows up |
|---|---|---|
| `foreground` | Default text | Everything unstyled |
| `background` | App background | Behind everything |
| `surface` | Raised, opaque fill | Dialogs, popups, menus |
| `primary` | The main accent | Primary buttons, progress, active pane chrome |
| `focus` | "Input goes here" | Focused pane borders and titles |
| `success` `warning` `error` `info` | Status | Badges, log marks, toasts, validation |

Two rules worth knowing:

- **`foreground`, `background` and `surface` are nullable.** Leaving them null
  means *use the terminal's own colours*, which is the right default for a
  theme meant to blend in. Every theme in this package sets them explicitly,
  because the point of choosing "Nord" is to get Nord's look rather than your
  terminal's.
- **`surface` must be opaque.** It backs dialogs and popups, so whatever is
  underneath must not show through. If you leave it null, Fleury derives a
  near-black or near-white fill from `brightness`.

### The text styles

Colour is only half a theme. `ThemeData` also carries three styles that widgets
reach for by name:

| Field | Default | Used for |
|---|---|---|
| `mutedStyle` | `dim: true` | Timestamps, hints, secondary labels |
| `selectionStyle` | `inverse: true` | The current row in a list or table |
| `focusedStyle` | `bold: true` | The focused control |
| `borderStyle` | `BorderStyle.rounded` | Every panel and box frame |

**Pair colour with an attribute.** Under `NO_COLOR` — or on a 2-colour
terminal — colour is dropped entirely, but attributes survive. A cue carried
only by colour disappears; `dim`, `bold` and `inverse` do not. That is why the
defaults above are attributes rather than greys.

### A minimal theme

```dart
const myTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x11, 0x14, 0x1A),
    surface: RgbColor(0x1B, 0x20, 0x28),
    foreground: RgbColor(0xD6, 0xDD, 0xE6),
    primary: RgbColor(0x7A, 0xD1, 0xB0),
    focus: RgbColor(0x8A, 0xB4, 0xF8),
    success: RgbColor(0x9E, 0xCE, 0x6A),
    warning: RgbColor(0xE0, 0xAF, 0x68),
    error: RgbColor(0xF7, 0x76, 0x8E),
    info: RgbColor(0x7D, 0xCF, 0xFF),
  ),
);
```

Want just an accent, not a full palette? `ColorScheme.fromSeed(myColor)` keeps
your seed verbatim as `primary` and leaves the status colours alone, so "error"
still reads as red.

### Light and dark from one definition

```dart
final surface = context.adaptive(
  light: const RgbColor(0xF2, 0xF2, 0xF4),
  dark: const RgbColor(0x12, 0x12, 0x14),
);
```

### Checking your work

Run the storybook and open **Themes** — it renders any theme on a mock app plus
a labelled reference showing every role and style field, which is the fastest
way to spot a role you left at its default:

```sh
dart tool/fleury_dev.dart storybook
```

Two things to look at while you're there. Contrast: `mutedStyle` on
`background` is the pairing that most often ends up unreadable. And truecolour:
`RgbColor` is downsampled automatically on 256- and 16-colour terminals, so
check yours somewhere limited before shipping.

## Attribution

These palettes are the work of their respective projects and are included with
attribution; see [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) for each
project's licence and homepage. Colour values are the projects' published
canonical hexes; the mapping onto Fleury's nine roles is this package's, and
any mismatch with upstream's intent is ours rather than theirs.
