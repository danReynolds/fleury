# Fleury Storybook

Interactive widget catalog for Fleury. It is a real TUI app: browse widgets,
search the catalog, switch themes, edit story controls, and inspect semantic
coverage while demos run.

Run from the repo root:

```sh
dart tool/fleury_dev.dart storybook
dart tool/fleury_dev.dart storybook list
dart tool/fleury_dev.dart storybook verify
dart tool/fleury_dev.dart storybook snapshot --story data.tables.data-table --variant cell-selection
dart tool/fleury_dev.dart storybook coverage --strict
dart tool/fleury_dev.dart storybook run --story visualization.charts.line-chart --control samples=16 --theme dark --size 80x24
```

Or directly:

```sh
cd packages/storybook
dart run bin/storybook.dart
dart run bin/storybook.dart list --json
dart run bin/storybook.dart verify --json
```

Commands:

- `run` opens the interactive storybook. It is the default command.
- `list` prints story ids, categories, controls, and variants.
- `verify` renders each selected story target and captures semantic summaries.
- `snapshot` writes text snapshots for selected story targets.
- `coverage` compares story coverage against exported widget-like symbols.

Common options:

- `--story <id>` opens a specific story.
- `--variant <id>` selects a story variant.
- `--control <id=value>` overrides a selected story control.
- `--theme <terminal|dark|light|high-contrast>` sets the initial theme.
- `--size <fit|80x24|100x30|120x40|60x20>` sets the preview viewport preset.
- `--default-only` limits `verify` and `snapshot` to default story states.
- `--json` emits machine-readable output for automation.

Shortcuts:

- `Ctrl+K` opens the command palette.
- `Ctrl+T` cycles the app theme.
- `Ctrl+S` toggles the semantic inspector panel.
- `Ctrl+D` toggles compact preview density.
- `Ctrl+V` cycles preview viewport presets.
- `Ctrl+R` resets controls for the selected story.
- `PageUp` and `PageDown` move between stories.
- `Alt+Left` and `Alt+Right` move between variants for the selected story.

The selector is a `SearchPanel`; use it to filter individual widget rows and
press Enter to activate the highlighted widget. Activating a widget opens the
storybook story that demonstrates it, with one catalog story per widget. Some
widgets share a backing scenario fixture, but each widget story owns its title,
description, default control values, and relevant starting view. Use Tab or
directional arrows to move focus into the preview pane and interact with
focusable widgets inside each demo. The details panel shows typed controls for
the selected story plus the most recent actions emitted by interactive widgets.
The inspector section summarizes focus, command shortcuts, story metadata,
variants, and widget coverage.
