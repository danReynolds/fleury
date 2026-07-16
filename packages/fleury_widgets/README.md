# Fleury Widgets

> The widget catalog for [`fleury`](../fleury).

A batteries-included set of higher-level widgets built on the
`fleury` framework — inputs, data displays, overlays, charts, and
pixel-drawing surfaces. Everything here is a normal `Widget`: composable,
focusable where it makes sense, themeable via `Theme`, and testable with
`FleuryTester`.

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
```

The lower-level primitives — `Text`, `Row`/`Column`, `Spinner`,
`TextInput`, `ScrollView`, `Navigator`, focus, animation — live in
`fleury` itself. This package is the catalog you reach for once the
layout bones are in place.

## Catalog

### Inputs & forms

| Widget | What it is |
| --- | --- |
| `Button` | A pressable button: `[ Label ]`. Enter/Space or click activates. |
| `Checkbox` | A boolean checkbox: `[x]` / `[ ]`. Enter toggles. |
| `Toggle` | A boolean switch: `[ o]` / `[o ]` (the knob slides). |
| `Switch` | A wider, accent-tinted boolean switch. |
| `Radio` | A single choice in a group, selected when `value == groupValue`. |
| `NumberInput` | A numeric `TextInput` — digits, optional sign/decimals. |
| `PasswordInput` | A `TextInput` that masks every typed grapheme. |
| `Stepper` | A numeric stepper: `[ − 42 + ]`, arrows / `+` / `−`. |
| `RangeSlider` | A two-handle slider for a numeric `(low, high)` range. |
| `Select` | A dropdown picker showing the current value + options. |
| `Autocomplete` | A text field with an anchored, live-filtered suggestion list. |
| `ColorPicker` | A grid of color swatches; the selection is bordered. |
| `DatePicker` | A month-at-a-time calendar date picker. |
| `FilePicker` | A keyboard-driven directory browser / file picker. |

### Data display

| Widget | What it is |
| --- | --- |
| `Table` | A grid of cells with columns aligned across every row, negotiated widths, optional row selection (`TableController`). |
| `Tree` | A keyboard-navigable, collapsible tree (`TreeNode`). |
| `Tabs` | A tab strip over swappable content (`TabItem`, `TabController`). |
| `Digits` | Large-numeral display for clocks, timers, counters. |
| `MarkdownText` | Light-Markdown renderer: headings, **bold**, *italic*, ~~strike~~, `code`, links, lists, blockquotes, fenced code, horizontal rules. For help screens, agentic-LLM responses, in-app docs. |

### Overlays & feedback

| Widget | What it is |
| --- | --- |
| `Menu` | A dropdown menu with items, separators, and nested `SubMenu`s. |
| `CommandPalette` | A fuzzy command palette: filter input over a live-filtered list. |
| `Dialog` | Modal chrome — a bordered, padded panel with an optional title. |
| `Tooltip` | A hint anchored below its child while focus is inside it. |
| `Toaster` | Hosts transient toast notifications, with optional actions. |
| `ProgressBar` | A horizontal determinate progress bar. |
| `Gauge` | A single-value status bar with an optional label. |

### Charts & visualization

| Widget | What it is |
| --- | --- |
| `BarChart` | A vertical bar chart with category + value labels. |
| `LineChart` | A multi-series line chart with sub-cell braille resolution. |
| `Histogram` | A frequency-distribution chart over binned values. |
| `Sparkline` | A compact, single-row history graph. |
| `Heatmap` | A 2D grid of values rendered as density blocks. |
| `CalendarHeatmap` | A GitHub-contribution-graph-style calendar heatmap. |

Shared helpers: `Palettes` (prebuilt color palettes), `TickFormat`
(axis label formatters), `ReferenceLine` (target/limit markers).

### Images & drawing surfaces

| Widget | What it is |
| --- | --- |
| `Image` | Raster images in the terminal — auto-selects Kitty, iTerm2, or Sixel, with a dithered ANSI cell-art fallback. tmux, GNU Screen, and Zellij use cell art so redraw, resize, and pane lifecycle stay deterministic. Animated GIF/APNG/WebP supported. |
| `Canvas` | A retained drawing surface for lines, shapes, and points. |

## Testing

Every widget here is exercised with `FleuryTester` from
`package:fleury/fleury_test.dart` (443 tests in this package).
Use `renderToString()` for inline assertions or `matchesGolden(...)`
for whole-screen snapshot regression — see the
[`fleury` README](../fleury/README.md#testing).
