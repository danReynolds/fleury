# Fleury Peer Fixtures

This directory contains comparison-only fixtures for M3.9 cross-framework
benchmarks. These packages are not part of Fleury's runtime or public API.

Peer fixture outputs should be validated with:

```sh
dart tool/fleury_dev.dart benchmark result --input=<peer-run.json>
```

Do not hand-edit `peerRuns` into
`docs/implementation/comparative-benchmark-manifest.json`.

## Fixtures

- `nocterm/sb1_counter` - Nocterm `SB.1 Time To Counter App` fixture using
  Nocterm `0.6.0` and `NoctermTester`.
- `bubbletea/sb1_counter`, `textual/sb1_counter`, and `ink/sb1_counter` -
  wire-only `SB.1 Counter/Startup` fixtures for first-paint and runtime-floor
  comparisons across Go, Python, and React/Node full-UI app paths.
- `nocterm/sb2_text_editing` - Nocterm `SB.2 Text Editing Composer Stress`
  fixture using Nocterm `0.6.0` `TextField` plus fixture-owned adapters for
  undo/redo, history, and completion.
- `textual/sb2_text_editing` - Textual `SB.2 Text Editing Composer Stress`
  fixture using Textual `8.2.7` `TextArea`, password `Input`, built-in
  cursor/selection/edit/undo-redo behavior, and fixture-owned history and
  completion adapters.
- `bubbletea/sb2_text_editing` - Bubble Tea/Bubbles `SB.2 Text Editing
  Composer Stress` fixture using Bubble Tea `2.0.7`, Bubbles `2.1.0`
  `textarea`/`textinput`, peer-owned editor movement/edit/paste/password/
  suggestion behavior, and fixture-owned selection, undo/redo, and history
  adapters.
- `ink/sb2_text_editing` - Ink `SB.2 Text Editing Composer Stress` fixture
  using Ink `7.0.5`, React `19.2.7`, `react-ink-textarea` `0.1.3`,
  `ink-text-input` `6.0.0`, and `ink-testing-library` `4.0.0`. Ink owns the
  React renderer and ecosystem input components; selection, redo, history,
  completion, and app-state query adapters are fixture-owned.
- `nocterm/sb3_datatable` - Nocterm `SB.3 DataTable 100k Rows` fixture using
  Nocterm `0.6.0` `ListView.builder`, `ScrollController`, and `Text` plus
  fixture-owned table formatting, retained rows, visible-window policy,
  selection, copy/export, and terminal/app-state queries.
- `textual/sb3_datatable` - Textual `SB.3 DataTable 100k Rows` fixture using
  Textual `8.2.7` `DataTable` plus fixture-owned jump-to-end and selected-row
  copy commands.
- `ratatui/sb3_datatable` - Ratatui `SB.3 DataTable 100k Rows` fixture using
  Ratatui `0.30.0` `Table`, `TableState`, and `Buffer` rendering plus
  fixture-owned retained rows, visible-window slicing, navigation, copy/export,
  and buffer/state queries.
- `opentui/sb3_datatable` - OpenTUI `SB.3 DataTable 100k Rows` fixture using
  OpenTUI `0.3.1` `TextTableRenderable`, styled text chunks, and the test
  renderer plus fixture-owned retained rows, visible-window slicing,
  navigation, copy/export, and frame/app-state queries.
- `opentui/sb4_log_region` - OpenTUI `SB.4 LogRegion Tailing And Scrollback`
  fixture using OpenTUI `0.3.1` `TextRenderable` and the test renderer plus
  fixture-owned retained logs, tail policy, scrollback selection,
  sanitization, filtering, selected-entry copy, and frame/app-state queries.
- `textual/sb4_log_region` - Textual `SB.4 LogRegion Tailing And Scrollback`
  fixture using Textual `8.2.7` `Log` plus fixture-owned sanitization,
  filtering, selected-entry state, and copy commands.
- `textual/sb5_streaming_markdown` - Textual `SB.5 Streaming Markdown`
  fixture using Textual `8.2.7` `Markdown.append` plus fixture-owned
  sanitization, visible URL fallback, selected-block copy, and app-state
  metadata queries.
- `bubbletea/sb5_streaming_markdown` - Bubble Tea/Bubbles/Glamour
  `SB.5 Streaming Markdown` fixture using Bubble Tea `2.0.7`, Bubbles `2.1.0`
  viewport primitives, and Glamour `2.0.0` full-document terminal Markdown
  rendering plus fixture-owned sanitization, visible URL fallback,
  selected-block copy, and app/model-state metadata queries.
- `bubbletea/sb4_log_region` - Bubble Tea `SB.4 LogRegion Tailing And
  Scrollback` fixture using Bubble Tea `2.0.7` model/update/view and Bubbles
  `2.1.0` viewport primitives plus fixture-owned sanitization, filtering,
  selected-entry state, copy, and app/model-state queries.
- `nocterm/sb4_log_region` - Nocterm `SB.4 LogRegion Tailing And Scrollback`
  fixture using Nocterm `0.6.0` `ListView.builder`, `ScrollController`, and
  `Text` plus fixture-owned sanitization, filtering, selected-entry state, copy,
  and terminal/app-state queries.
- `bubbletea/sb6_dashboard`, `ratatui/sb6_dashboard`, and
  `opentui/sb6_dashboard` - wire-only `SB.6 Dashboard Updates` fixtures using
  the peers' normal terminal render loops for sustained dashboard update
  pressure.
- `nocterm/sb12_layout_dirtiness`, `ratatui/sb12_layout_dirtiness`, and
  `opentui/sb12_layout_dirtiness` - wire-only `SB.12 Layout Dirtiness Cache`
  fixtures for layout/paint dirtiness and minimal redraw comparisons.
- `textual/sb7_resize_storm`, `ratatui/sb7_resize_storm`, and
  `opentui/sb7_resize_storm` - wire-only `SB.7 Resize Storm` fixtures for
  repeated PTY resize events across table, log, and text-input state.
- `textual/sb8_overlay_palette`, `ink/sb8_overlay_palette`, and
  `bubbletea/sb8_overlay_palette` - wire-only `SB.8 Overlay/Palette Churn`
  fixtures for transient command palette open/filter/close work.
- `textual/sb9_subprocess_output`, `bubbletea/sb9_subprocess_output`, and
  `opentui/sb9_subprocess_output` - wire-only `SB.9 Subprocess/Untrusted
  Output` fixtures for streaming process-output ingestion.
- `textual/sb10_demo_app`, `bubbletea/sb10_demo_app`, and
  `ink/sb10_demo_app` - wire-only `SB.10 Demo-App Journey` fixtures for a
  compact full-app navigation/action/status flow.
- `textual/sb11_treetable_filter_copy`,
  `ratatui/sb11_treetable_filter_copy`, and
  `opentui/sb11_treetable_filter_copy` - wire-only `SB.11
  TreeTable/filter/copy` fixtures for hierarchical expansion, movement,
  filter-to-target, and selected-row copy output.

Run from the fixture package:

```sh
dart pub get
dart analyze
dart test
dart run bin/sb1_counter_benchmark.dart \
  --warmup=2 \
  --iterations=20 \
  --json \
  --output=results/nocterm-sb1-counter-2026-06-01.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/nocterm/sb1_counter/results/nocterm-sb1-counter-2026-06-01.json \
  --output=/tmp/fleury-nocterm-sb1-manifest.json \
  --json
```

For `SB.2`, run from `peer-fixtures/nocterm/sb2_text_editing`:

```sh
dart pub get
dart analyze
dart test
dart run bin/sb2_text_editing_benchmark.dart \
  --warmup=2 \
  --iterations=10 \
  --text-chars=10000 \
  --json \
  --output=results/nocterm-sb2-text-editing-2026-06-01.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/nocterm/sb2_text_editing/results/nocterm-sb2-text-editing-2026-06-01.json \
  --output=/tmp/fleury-nocterm-sb2-manifest.json \
  --json
```

For repeated local Nocterm `SB.2` evidence, save comparable runs under
`peer-fixtures/nocterm/sb2_text_editing/results/variance` and summarize them
from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/nocterm/sb2_text_editing/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/nocterm-sb2-text-editing-2026-06-02.json \
  --json
```

For Textual `SB.2`, run from `peer-fixtures/textual/sb2_text_editing`:

```sh
python3 -m pip install --target=.python -r requirements.txt
PYTHONPATH=.python python3 test_sb2_text_editing.py
PYTHONPATH=.python python3 sb2_text_editing_benchmark.py \
  --warmup=1 \
  --iterations=5 \
  --text-chars=10000 \
  --json \
  --output=results/textual-sb2-text-editing-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/textual/sb2_text_editing/results/textual-sb2-text-editing-2026-06-02.json \
  --output=/tmp/fleury-textual-sb2-manifest.json \
  --json
```

For repeated local Textual `SB.2` evidence, save comparable runs under
`peer-fixtures/textual/sb2_text_editing/results/variance` and summarize them
from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/textual/sb2_text_editing/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/textual-sb2-text-editing-2026-06-02.json \
  --json
```

For Bubble Tea/Bubbles `SB.2`, run from
`peer-fixtures/bubbletea/sb2_text_editing`:

```sh
go test ./...
go run . \
  --warmup=1 \
  --iterations=5 \
  --text-chars=10000 \
  --json \
  --output=results/bubbletea-sb2-text-editing-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/bubbletea/sb2_text_editing/results/bubbletea-sb2-text-editing-2026-06-02.json \
  --output=/tmp/fleury-bubbletea-sb2-manifest.json \
  --json
```

For repeated local Bubble Tea/Bubbles `SB.2` evidence, save comparable runs
under `peer-fixtures/bubbletea/sb2_text_editing/results/variance` and
summarize them from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/bubbletea/sb2_text_editing/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/bubbletea-sb2-text-editing-2026-06-02.json \
  --json
```

For Ink `SB.2`, run from `peer-fixtures/ink/sb2_text_editing` with Node 22+
or the bundled workspace Node runtime:

```sh
npm install
npm test
npm run benchmark -- \
  --warmup=1 \
  --iterations=5 \
  --text-chars=10000 \
  --json \
  --output=results/ink-sb2-text-editing-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/ink/sb2_text_editing/results/ink-sb2-text-editing-2026-06-02.json \
  --output=/tmp/fleury-ink-sb2-manifest.json \
  --json
```

For repeated local Ink `SB.2` evidence, save comparable runs under
`peer-fixtures/ink/sb2_text_editing/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/ink/sb2_text_editing/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/ink-sb2-text-editing-2026-06-02.json \
  --json
```

For Nocterm `SB.3`, run from `peer-fixtures/nocterm/sb3_datatable`:

```sh
dart pub get
dart analyze
dart test
dart run bin/sb3_datatable_benchmark.dart \
  --warmup=2 \
  --iterations=5 \
  --rows=100000 \
  --json \
  --output=results/nocterm-sb3-datatable-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/nocterm/sb3_datatable/results/nocterm-sb3-datatable-2026-06-02.json \
  --output=/tmp/fleury-nocterm-sb3-manifest.json \
  --json
```

For repeated local Nocterm `SB.3` evidence, save comparable runs under
`peer-fixtures/nocterm/sb3_datatable/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/nocterm/sb3_datatable/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/nocterm-sb3-datatable-2026-06-02.json \
  --json
```

For `SB.3`, run from `peer-fixtures/textual/sb3_datatable`:

```sh
python -m pip install --target=.python -r requirements.txt
PYTHONPATH=.python python test_sb3_datatable.py
PYTHONPATH=.python python sb3_datatable_benchmark.py \
  --warmup=1 \
  --iterations=3 \
  --rows=100000 \
  --json \
  --output=results/textual-sb3-datatable-2026-06-01.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/textual/sb3_datatable/results/textual-sb3-datatable-2026-06-01.json \
  --output=/tmp/fleury-textual-sb3-manifest.json \
  --json
```

For repeated local Textual `SB.3` evidence, save comparable runs under
`peer-fixtures/textual/sb3_datatable/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/textual/sb3_datatable/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/textual-sb3-datatable-2026-06-02.json \
  --json
```

For Ratatui `SB.3`, run from `peer-fixtures/ratatui/sb3_datatable`:

```sh
cargo test
cargo run --release -- \
  --warmup=2 \
  --iterations=20 \
  --rows=100000 \
  --json \
  --output=results/ratatui-sb3-datatable-2026-06-01.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/ratatui/sb3_datatable/results/ratatui-sb3-datatable-2026-06-01.json \
  --output=/tmp/fleury-ratatui-sb3-manifest.json \
  --json
```

For repeated local Ratatui `SB.3` evidence, save comparable runs under
`peer-fixtures/ratatui/sb3_datatable/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/ratatui/sb3_datatable/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/ratatui-sb3-datatable-2026-06-02.json \
  --json
```

For OpenTUI `SB.3`, run from `peer-fixtures/opentui/sb3_datatable`:

```sh
npm install
npm test
npm run benchmark -- \
  --warmup=2 \
  --iterations=5 \
  --rows=100000 \
  --json \
  --output=results/opentui-sb3-datatable-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/opentui/sb3_datatable/results/opentui-sb3-datatable-2026-06-02.json \
  --output=/tmp/fleury-opentui-sb3-manifest.json \
  --json
```

For repeated local OpenTUI `SB.3` evidence, save comparable runs under
`peer-fixtures/opentui/sb3_datatable/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/opentui/sb3_datatable/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/opentui-sb3-datatable-2026-06-02.json \
  --json
```

For OpenTUI `SB.4`, run from `peer-fixtures/opentui/sb4_log_region`:

```sh
npm install
npm test
npm run benchmark -- \
  --warmup=2 \
  --iterations=5 \
  --rows=100000 \
  --append=1000 \
  --json \
  --output=results/opentui-sb4-log-region-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/opentui/sb4_log_region/results/opentui-sb4-log-region-2026-06-02.json \
  --output=/tmp/fleury-opentui-sb4-manifest.json \
  --json
```

For repeated local OpenTUI `SB.4` evidence, save comparable runs under
`peer-fixtures/opentui/sb4_log_region/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/opentui/sb4_log_region/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/opentui-sb4-log-region-2026-06-02.json \
  --json
```

For `SB.4`, run from `peer-fixtures/textual/sb4_log_region`:

```sh
python -m pip install --target=.python -r requirements.txt
PYTHONPATH=.python python test_sb4_log_region.py
PYTHONPATH=.python python sb4_log_benchmark.py \
  --warmup=1 \
  --iterations=3 \
  --rows=100000 \
  --append=1000 \
  --json \
  --output=results/textual-sb4-log-region-2026-06-01.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/textual/sb4_log_region/results/textual-sb4-log-region-2026-06-01.json \
  --output=/tmp/fleury-textual-sb4-manifest.json \
  --json
```

For repeated local Textual `SB.4` evidence, save comparable runs under
`peer-fixtures/textual/sb4_log_region/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/textual/sb4_log_region/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/textual-sb4-log-region-2026-06-02.json \
  --json
```

For Bubble Tea `SB.4`, run from
`peer-fixtures/bubbletea/sb4_log_region`:

```sh
go test ./...
go run . \
  --warmup=1 \
  --iterations=5 \
  --rows=100000 \
  --append=1000 \
  --json \
  --output=results/bubbletea-sb4-log-region-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/bubbletea/sb4_log_region/results/bubbletea-sb4-log-region-2026-06-02.json \
  --output=/tmp/fleury-bubbletea-sb4-manifest.json \
  --json
```

For repeated local Bubble Tea/Bubbles `SB.4` evidence, save comparable runs
under `peer-fixtures/bubbletea/sb4_log_region/results/variance` and summarize
them from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/bubbletea/sb4_log_region/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/bubbletea-sb4-log-region-2026-06-02.json \
  --json
```

For Nocterm `SB.4`, run from `peer-fixtures/nocterm/sb4_log_region`:

```sh
dart pub get
dart analyze
dart test
dart run bin/sb4_log_region_benchmark.dart \
  --warmup=2 \
  --iterations=5 \
  --rows=100000 \
  --append=1000 \
  --json \
  --output=results/nocterm-sb4-log-region-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/nocterm/sb4_log_region/results/nocterm-sb4-log-region-2026-06-02.json \
  --output=/tmp/fleury-nocterm-sb4-manifest.json \
  --json
```

For repeated local Nocterm `SB.4` evidence, save comparable runs under
`peer-fixtures/nocterm/sb4_log_region/results/variance` and summarize them from
the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/nocterm/sb4_log_region/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/nocterm-sb4-log-region-2026-06-02.json \
  --json
```

For Textual `SB.5`, run from
`peer-fixtures/textual/sb5_streaming_markdown`:

```sh
python -m pip install --target=.python -r requirements.txt
PYTHONPATH=.python python test_sb5_markdown.py
PYTHONPATH=.python python sb5_markdown_benchmark.py \
  --warmup=1 \
  --iterations=3 \
  --rows=10000 \
  --json \
  --output=results/textual-sb5-streaming-markdown-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/textual/sb5_streaming_markdown/results/textual-sb5-streaming-markdown-2026-06-02.json \
  --output=/tmp/fleury-textual-sb5-manifest.json \
  --json
```

The first saved Textual `SB.5` artifact uses `--rows=10000`, which maps to
100 streamed chunks. The full Fleury baseline uses `--rows=100000`, mapping to
1000 chunks; collect that as a separate long-run artifact before making
full-scale streaming-markdown claims.

For repeated local Textual `SB.5` evidence, save comparable runs under
`peer-fixtures/textual/sb5_streaming_markdown/results/variance` and summarize
them from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/textual/sb5_streaming_markdown/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/textual-sb5-streaming-markdown-2026-06-02.json \
  --json
```

For Bubble Tea/Bubbles/Glamour `SB.5`, run from
`peer-fixtures/bubbletea/sb5_streaming_markdown`:

```sh
go test ./...
go run . \
  --warmup=1 \
  --iterations=3 \
  --rows=10000 \
  --json \
  --output=results/bubbletea-sb5-streaming-markdown-2026-06-02.json
```

Then validate from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark result \
  --input=peer-fixtures/bubbletea/sb5_streaming_markdown/results/bubbletea-sb5-streaming-markdown-2026-06-02.json \
  --output=/tmp/fleury-bubbletea-sb5-manifest.json \
  --json
```

The first saved Bubble Tea/Bubbles/Glamour `SB.5` artifact also uses
`--rows=10000`, which maps to 100 streamed chunks. It exercises Bubble Tea
model/update/view, a Bubbles viewport, and Glamour full-document Markdown
rendering; it does not prove an incremental Markdown widget, real-terminal
behavior, repeated variance, or full 1000-chunk parity.

For repeated local Bubble Tea/Bubbles/Glamour `SB.5` evidence, save comparable
runs under `peer-fixtures/bubbletea/sb5_streaming_markdown/results/variance`
and summarize them from the Fleury workspace root:

```sh
dart tool/fleury_dev.dart benchmark variance \
  --input=peer-fixtures/bubbletea/sb5_streaming_markdown/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/bubbletea-sb5-streaming-markdown-2026-06-02.json \
  --json
```

The first repeated-run summaries prove local 100-chunk strict variance for
Textual and Bubble Tea/Bubbles/Glamour. Full 1000-chunk peer parity,
real-terminal variance, and cross-machine variance remain open.
