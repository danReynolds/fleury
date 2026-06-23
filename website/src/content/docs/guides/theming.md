---
title: Theming
description: Style a Fleury app with ThemeData, ColorScheme, and CellStyle.
---

Every Fleury app renders through a `ThemeData`. Widgets read it with
`Theme.of(context)` and style their cells from it, so a single theme drives the
whole tree.

## Apply a theme

`runTui` doesn't install a `Theme` for you — until you add one, widgets fall back
to sensible built-in defaults (`Theme.of(context)` always returns *something*).
To customize, wrap a subtree in a `Theme`:

```dart
import 'package:fleury/fleury.dart';

Theme(
  data: ThemeData(
    brightness: Brightness.dark,
    borderStyle: BorderStyle.rounded,
    colorScheme: const ColorScheme(
      foreground: RgbColor(0xC8, 0xD3, 0xE0),
      primary: RgbColor(0x3D, 0xDC, 0x97),
      warning: RgbColor(0xF5, 0xC2, 0x11),
      error: RgbColor(0xFF, 0x5C, 0x57),
    ),
  ),
  child: myApp,
);
```

`ThemeData.dark()` and `ThemeData.light()` give you sensible defaults to start
from, and `copyWith(...)` overrides individual fields.

## ColorScheme

The semantic palette. `foreground`/`background` are the defaults; `primary`,
`success`, `warning`, `error`, and `info` are the accents widgets reach for
(gauges, validation, status):

```dart
final scheme = Theme.of(context).colorScheme;
Text('ok',   style: CellStyle(foreground: scheme.success));
Text('uh oh', style: CellStyle(foreground: scheme.error));
```

Colors can be `RgbColor(r, g, b)` for truecolor, `AnsiColor(n)` for a palette
index, or one of the named `Colors.*` constants.

## CellStyle

A cell's appearance: foreground/background plus terminal attributes.

```dart
const CellStyle(
  foreground: RgbColor(0x3D, 0xDC, 0x97),
  bold: true,
  // also: dim, italic, underline, inverse
);
```

`ThemeData` also carries a few ready-made styles widgets use for consistency:
`textStyle` (the default), `mutedStyle` (secondary text), `selectionStyle`
(highlighted rows), and `focusedStyle` (the focused control).

## Multiple styles in one line: RichText

A `Text` carries a single `CellStyle`. To mix styles within one run — a bold word
in a sentence, a colored token in a log line — use `RichText` with a tree of
`TextSpan`s, where each span's style cascades to its children:

```dart
RichText(
  text: TextSpan(
    children: [
      TextSpan(text: 'deploy '),
      TextSpan(text: 'ok', style: CellStyle(foreground: scheme.success, bold: true)),
      TextSpan(text: ' in 1.2s'),
    ],
  ),
)
```

## Reading the theme

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Text('hello', style: theme.textStyle);
}
```

`context.theme` and `context.colors` are shorthands for `Theme.of(context)` and
`Theme.of(context).colorScheme` — both establish the same dependency, so the
widget rebuilds if the theme changes.

Backgrounds aren't auto-painted: to fill a region with the theme background,
wrap it in a `Container(color: theme.colorScheme.background, child: …)`.
