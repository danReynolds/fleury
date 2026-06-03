# Fleury Scenario Benchmark Lab

**Status:** Phase 0 definition complete
**Milestone:** M0.5 Scenario benchmark lab
**Owner:** Reactive render engine, with shared ownership from text editing,
data widgets, effects/workflow, terminal capability/security, and
replay/devtools.

## Purpose

This lab defines the app-shaped workloads Fleury must use before making
performance, robustness, or "best choice" claims.

Fleury already has useful microbenchmarks under
[packages/fleury/benchmark](../../packages/fleury/benchmark/README.md). Those
benchmarks are still valuable for isolating render, paint, build, parser,
widget, animation, and debug-shell costs. The scenario lab sits above them: it
measures user-visible behavior across real TUI workflows where retained UI,
semantics, terminal correctness, text editing, streaming output, data
virtualization, and async work interact.

The standard is not "fast in a synthetic loop." The standard is: a developer
can build a dense, keyboard-first terminal app and trust latency, frame
stability, correctness, diagnostics, and safe degradation under realistic load.

## Current Fleury Baseline

Existing benchmark assets:

- [Comparative benchmark manifest](comparative-benchmark-manifest.json) maps
  Fleury's scenario families to peer-equivalent contracts, required metrics,
  correctness gates, and primary peer targets. It is inspectable with
  `dart tool/fleury_dev.dart benchmark-manifest`. Peer-run artifacts are
  validated and merged into manifest copies with
  `dart tool/fleury_dev.dart benchmark-result`.
- [Nocterm SB.1 counter peer fixture](../../peer-fixtures/nocterm/sb1_counter)
  records the first real peer fixture and a saved local
  [Nocterm SB.1 run artifact](../../peer-fixtures/nocterm/sb1_counter/results/nocterm-sb1-counter-2026-06-01.json)
  for Nocterm `0.6.0` in `nocterm-test-harness` mode. The run validates
  against the manifest with `benchmark-result`; it is not repeated
  real-terminal evidence.
- [Nocterm SB.2 text editing peer fixture](../../peer-fixtures/nocterm/sb2_text_editing)
  records a saved local
  [Nocterm SB.2 run artifact](../../peer-fixtures/nocterm/sb2_text_editing/results/nocterm-sb2-text-editing-2026-06-01.json)
  for Nocterm `0.6.0` over a 10k-character mixed-width editor in
  `nocterm-test-harness` mode. It validates all `SB.2` manifest gates, while
  noting that undo/redo, history, and completion are fixture-owned adapters.
- [Textual SB.2 text editing peer fixture](../../peer-fixtures/textual/sb2_text_editing)
  records a saved local
  [Textual SB.2 run artifact](../../peer-fixtures/textual/sb2_text_editing/results/textual-sb2-text-editing-2026-06-02.json)
  for Textual `8.2.7` over a 10k-character mixed-width editor in
  `textual-run-test-harness` mode. It validates all `SB.2` manifest gates,
  while noting that Textual owns `TextArea`, password `Input`, cursor movement,
  selection, editing, paste, and undo/redo; history, completion, and the
  semantic-substitute widget/app-state query are fixture-owned app code.
- [Bubble Tea/Bubbles SB.2 text editing peer fixture](../../peer-fixtures/bubbletea/sb2_text_editing)
  records a saved local
  [Bubble Tea SB.2 run artifact](../../peer-fixtures/bubbletea/sb2_text_editing/results/bubbletea-sb2-text-editing-2026-06-02.json)
  for Bubble Tea `2.0.7` and Bubbles `2.1.0` over a 10k-character mixed-width
  editor in `bubbletea-textarea-model-harness` mode. It validates all `SB.2`
  manifest gates, while noting that Bubble Tea owns model/update/view
  structure and Bubbles owns textarea movement/edit/paste plus textinput
  password/suggestions; selection, undo/redo, history, and app-state query are
  fixture-owned app code.
- [Ink SB.2 text editing peer fixture](../../peer-fixtures/ink/sb2_text_editing)
  records a saved local
  [Ink SB.2 run artifact](../../peer-fixtures/ink/sb2_text_editing/results/ink-sb2-text-editing-2026-06-02.json)
  for Ink `7.0.5`, React `19.2.7`, `react-ink-textarea` `0.1.3`,
  `ink-text-input` `6.0.0`, and `ink-testing-library` `4.0.0` over a
  10k-character mixed-width editor in `ink-testing-library-memory` mode. It
  validates all `SB.2` manifest gates, while noting that Ink owns React
  terminal rendering and ecosystem input displays; selection, redo, history,
  completion, and app-state query are fixture-owned app code.
- [Textual SB.3 DataTable peer fixture](../../peer-fixtures/textual/sb3_datatable)
  records a saved local
  [Textual SB.3 run artifact](../../peer-fixtures/textual/sb3_datatable/results/textual-sb3-datatable-2026-06-01.json)
  for Textual `8.2.7` over 100k rows in `textual-run-test-harness` mode. It
  validates all `SB.3` manifest gates, while noting that jump-to-final-row and
  selected-row copy/export are fixture-owned app commands and Textual exposes
  widget-state test queries rather than a Fleury-style semantic graph.
- [Ratatui SB.3 DataTable peer fixture](../../peer-fixtures/ratatui/sb3_datatable)
  records a saved local
  [Ratatui SB.3 run artifact](../../peer-fixtures/ratatui/sb3_datatable/results/ratatui-sb3-datatable-2026-06-01.json)
  for Ratatui `0.30.0` over 100k rows in `ratatui-buffer-render-harness` mode.
  It validates all `SB.3` manifest gates, while noting that Ratatui owns
  immediate table/buffer rendering and the fixture owns retained app state,
  visible-window slicing, navigation policy, selected-row copy/export, and
  state/buffer query.
- [OpenTUI SB.3 DataTable peer fixture](../../peer-fixtures/opentui/sb3_datatable)
  records a saved local
  [OpenTUI SB.3 run artifact](../../peer-fixtures/opentui/sb3_datatable/results/opentui-sb3-datatable-2026-06-02.json)
  for OpenTUI `0.3.1` over 100k rows in
  `opentui-test-renderer-memory` mode. It validates all `SB.3` manifest gates,
  while noting that OpenTUI owns `TextTableRenderable`, styled text chunks, and
  the test renderer while the fixture owns retained app state,
  visible-window slicing, navigation policy, selected-row copy/export, and
  frame/app-state query.
- [Nocterm SB.3 DataTable peer fixture](../../peer-fixtures/nocterm/sb3_datatable)
  records a saved local
  [Nocterm SB.3 run artifact](../../peer-fixtures/nocterm/sb3_datatable/results/nocterm-sb3-datatable-2026-06-02.json)
  for Nocterm `0.6.0` over 100k table-shaped rows in
  `nocterm-test-harness` mode. It validates all `SB.3` manifest gates, while
  noting that Nocterm owns `ListView.builder`, `ScrollController`, `Text`, and
  terminal-state queries while the fixture owns table formatting, retained
  rows, visible-window policy, selection, selected-row copy/export, and
  terminal/app-state query.
- [Textual SB.4 LogRegion peer fixture](../../peer-fixtures/textual/sb4_log_region)
  records a saved local
  [Textual SB.4 run artifact](../../peer-fixtures/textual/sb4_log_region/results/textual-sb4-log-region-2026-06-01.json)
  for Textual `8.2.7` over 100k starting log lines plus 1000 appended rows in
  `textual-run-test-harness` mode. It validates all `SB.4` manifest gates, while
  noting that sanitization/redaction, filtering, selected-entry state, and
  copy/export are fixture-owned app code around Textual's `Log` widget.
- [Bubble Tea SB.4 LogRegion peer fixture](../../peer-fixtures/bubbletea/sb4_log_region)
  records a saved local
  [Bubble Tea SB.4 run artifact](../../peer-fixtures/bubbletea/sb4_log_region/results/bubbletea-sb4-log-region-2026-06-02.json)
  for Bubble Tea `2.0.7` and Bubbles `2.1.0` over 100k starting log lines plus
  1000 appended rows in `bubbletea-viewport-model-harness` mode. It validates
  all `SB.4` manifest gates, while noting that Bubbles owns viewport
  content/scroll primitives and the fixture owns sanitization/redaction,
  filtering, selected-entry state, copy/export, and app/model-state queries.
- [OpenTUI SB.4 LogRegion peer fixture](../../peer-fixtures/opentui/sb4_log_region)
  records a saved local
  [OpenTUI SB.4 run artifact](../../peer-fixtures/opentui/sb4_log_region/results/opentui-sb4-log-region-2026-06-02.json)
  for OpenTUI `0.3.1` over 100k starting log lines plus 1000 appended rows in
  `opentui-test-renderer-memory` mode. It validates all `SB.4` manifest gates,
  while noting that OpenTUI owns `TextRenderable` and the native-backed test
  renderer while the fixture owns retained logs, tail policy, scrollback
  selection, sanitization/redaction, filtering, selected-entry copy/export,
  and frame/app-state queries.
- [Nocterm SB.4 LogRegion peer fixture](../../peer-fixtures/nocterm/sb4_log_region)
  records a saved local
  [Nocterm SB.4 run artifact](../../peer-fixtures/nocterm/sb4_log_region/results/nocterm-sb4-log-region-2026-06-02.json)
  for Nocterm `0.6.0` over 100k starting log lines plus 1000 appended rows in
  `nocterm-test-harness` mode. It validates all `SB.4` manifest gates, while
  noting that Nocterm owns `ListView.builder`, `ScrollController`, and `Text`,
  while the fixture owns sanitization/redaction, filtering, selected-entry
  state, copy/export, and terminal/app-state queries.
- [Textual SB.5 Streaming Markdown peer fixture](../../peer-fixtures/textual/sb5_streaming_markdown)
  records a saved local
  [Textual SB.5 run artifact](../../peer-fixtures/textual/sb5_streaming_markdown/results/textual-sb5-streaming-markdown-2026-06-02.json)
  for Textual `8.2.7` over 100 streamed markdown chunks in
  `textual-run-test-harness` mode. It validates all `SB.5` manifest gates,
  while noting that Textual owns `Markdown`, append parsing/rendering, focus,
  scrolling, and the test harness; sanitization/redaction, visible URL
  fallback, selected-block copy, markdown metadata, and widget/app-state
  queries are fixture-owned app code.
- [Bubble Tea/Bubbles/Glamour SB.5 Streaming Markdown peer fixture](../../peer-fixtures/bubbletea/sb5_streaming_markdown)
  records a saved local
  [Bubble Tea SB.5 run artifact](../../peer-fixtures/bubbletea/sb5_streaming_markdown/results/bubbletea-sb5-streaming-markdown-2026-06-02.json)
  for Bubble Tea `2.0.7`, Bubbles `2.1.0`, and Glamour `2.0.0` over 100
  streamed markdown chunks in `bubbletea-glamour-viewport-model-harness` mode.
  It validates all `SB.5` manifest gates, while noting that Bubble Tea owns
  model/update/view, Bubbles owns viewport primitives, Glamour owns
  full-document terminal Markdown rendering, and sanitization/redaction,
  visible URL fallback, selected-block copy, markdown metadata, and
  app/model-state queries are fixture-owned app code.
- [Benchmark README](../../packages/fleury/benchmark/README.md) documents the
  current `package:benchmark_harness` microbenchmark workflow and the first
  scenario benchmark entry point.
- [Scenario benchmark runner](../../packages/fleury/benchmark/scenario_benchmarks.dart)
  adds the first app-shaped runner with JSON output, filtering, save support,
  and `SB.1 Time To Counter App`.
- [Core Phase 1 baseline](../../packages/fleury/benchmark/results/phase1-core-2026-05-31.json)
  records a 20-iteration `SB.1` run on Dart 3.12.1.
- [Text Editing Phase 2 baseline](../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json)
  records a 10-iteration `SB.2 Text Editing Composer Stress` run on Dart
  3.12.1.
- [Layout Dirtiness Phase 2 baseline](../../packages/fleury/benchmark/results/phase2-layout-dirtiness-2026-06-01.json)
  records a 20-iteration `SB.12 Layout Dirtiness Cache` run on Dart 3.12.1.
- [Layout Dirtiness child-list follow-up](../../packages/fleury/benchmark/results/phase2-layout-dirtiness-child-list-2026-06-02.json)
  records the refreshed `SB.12` run after same-identity child-list replacement
  hardening.
- [Widgets Phase 1 baseline](../../packages/fleury_widgets/benchmark/results/phase1-widgets-2026-05-31.json)
  records a 20-iteration `SB.3 DataTable 100k Rows` run on Dart 3.12.1.
- [LogRegion Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-logregion-2026-05-31.json)
  records a 20-iteration `SB.4 LogRegion Tailing And Scrollback` run on Dart
  3.12.1.
- [TreeTable Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-treetable-2026-06-01.json)
  records a 20-iteration `SB.11 TreeTable Hierarchy Filter And Copy` run on
  Dart 3.12.1.
- [Resize Storm Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-resize-storm-2026-06-01.json)
  records a 5-iteration `SB.7 Resize Storm` run with 500 resize events per
  iteration on Dart 3.12.1.
- [Overlay Command Palette Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-overlay-command-palette-2026-06-01.json)
  records a 20-iteration `SB.8 Overlay And Command Palette Churn` run over a
  1000-command registry and 40 open/filter/select/action/settle cycles per
  iteration on Dart 3.12.1.
- [Optimized Overlay Command Palette Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-overlay-command-palette-optimized-2026-06-01.json)
  records the follow-up `SB.8` run after lazy visible rows, cached search text,
  stable command-id search, and ranked exact/prefix/contains/fuzzy matching.
- [Proof-App Journey Phase 2 baseline](../../packages/fleury_example_console/benchmark/results/phase2-proof-app-journey-2026-06-01.json)
  records a 10-iteration `SB.10 Proof-App Journey` run on Dart 3.12.1.
- [Proof-App Journey Global Search Phase 2 baseline](../../packages/fleury_example_console/benchmark/results/phase2-proof-app-global-search-2026-06-01.json)
  records the refreshed `SB.10` run after adding a debounced Global Search
  screen backed by `DebouncedTaskController` and `SearchPanel`.
- [Proof-App Journey Indexed Logs Phase 2 baseline](../../packages/fleury_example_console/benchmark/results/phase2-proof-app-indexed-logs-2026-06-01.json)
  records the refreshed `SB.10` run after adding an Indexed Logs screen backed
  by `TaskController`, `TaskYieldPolicy`, `LogRegionSearchIndex`, and
  `LogRegion`.
- [Proof-App Journey Ranked Search Phase 2 baseline](../../packages/fleury_example_console/benchmark/results/phase2-proof-app-ranked-search-2026-06-01.json)
  records the refreshed `SB.10` run after routing `SearchPanel` and proof-app
  Global Search through reusable `SearchResultIndex` ranking.
- [Cooperative LogRegion Index Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-logregion-cooperative-index-2026-06-01.json)
  records the refreshed `SB.4` run after moving retained-log index build and
  append refresh through task-owned cooperative yield checkpoints.
- [Cooperative TreeTable Index Phase 2 baseline](../../packages/fleury_widgets/benchmark/results/phase2-treetable-cooperative-index-2026-06-01.json)
  records the refreshed `SB.11` run after moving hierarchy index build through
  task-owned cooperative yield checkpoints.
- [Baseline results](../../packages/fleury/benchmark/baseline_results.md)
  record 2026-05-17 and 2026-05-19 measurements.
- [RFC 0009: Performance and profiling](../rfcs/0009-performance-and-profiling.md)
  defines the profiling discipline: optimize from measured pressure, not
  plausible-sounding render ideas.

## Peer Run Artifact Shape

Use `benchmark-result` for peer evidence. Do not hand-edit `peerRuns` into the
checked-in manifest.

```sh
dart tool/fleury_dev.dart benchmark-result \
  --input=peer-fixtures/nocterm/sb1_counter/results/nocterm-sb1-counter-2026-06-01.json \
  --output=docs/implementation/comparative-benchmark-manifest.with-peer.json
```

Use `benchmark-variance` after collecting repeated comparable artifacts for the
same peer/scenario/mode before using local timings for any launch claim:

```sh
dart tool/fleury_dev.dart benchmark-variance \
  --input=peer-fixtures/ink/sb2_text_editing/results/variance \
  --min-runs=3 \
  --strict \
  --output=docs/implementation/benchmark-variance/ink-sb2-text-editing-2026-06-02.json
```

The first strict-passing variance artifact is
[Ink SB.2 repeated-run variance](benchmark-variance/ink-sb2-text-editing-2026-06-02.json):
three comparable local `ink-testing-library-memory` runs over the 10k-character
fixture. It reports cursor-move p95 median 2449 us with 59.004% relative
spread, paste p95 median 997 us with 90.171% relative spread, and
app-state/frame query p95 median 152763 us with 25.67% relative spread. This
is useful local variance evidence, not real-terminal or cross-machine evidence.

The next strict-passing variance artifact is
[Nocterm SB.2 repeated-run variance](benchmark-variance/nocterm-sb2-text-editing-2026-06-02.json):
three comparable local `nocterm-test-harness` runs over the 10k-character
fixture. It reports cursor-move p95 median 24555 us with 186.231% relative
spread, paste p95 median 45691 us with 438.988% relative spread, and
test-query p95 median 4042 us with 731.173% relative spread. This is a useful
warning that single local Nocterm harness timings can be highly noisy.

The next strict-passing variance artifact is
[Textual SB.2 repeated-run variance](benchmark-variance/textual-sb2-text-editing-2026-06-02.json):
three comparable local `textual-run-test-harness` runs over the 10k-character
fixture using Textual `8.2.7` on Python `3.12.13`. It reports cursor-move p95
median 217392 us with 50.857% relative spread, paste p95 median 147414 us with
29.885% spread, history-navigation p95 median 344880 us with 298.423% spread,
and test-query p95 median 225 us with 1426.222% spread. The older single
Textual artifact used Python `3.13.1`, so compare the repeated-run artifact
internally unless a matching runtime set is collected.

The fourth strict-passing text-editing variance artifact is
[Bubble Tea SB.2 repeated-run variance](benchmark-variance/bubbletea-sb2-text-editing-2026-06-02.json):
three comparable local `bubbletea-textarea-model-harness` runs over the
10k-character fixture using Bubble Tea `2.0.7` and Bubbles `2.1.0`. It reports
cursor-move p95 median 718298 us with 54.66% relative spread, paste p95 median
22525 us with 153.23% spread, completion-accept p95 median 68417 us with
132.227% spread, and app-state query p95 median 16321 us with 98.94% spread.
Together with Ink, Nocterm, and Textual, this completes the first local
repeated-run pass across the main `SB.2` text-editing peer set. It is still
local harness evidence, not real-terminal or cross-machine evidence.

The first strict-passing data-widget variance artifact is
[Ratatui SB.3 repeated-run variance](benchmark-variance/ratatui-sb3-datatable-2026-06-02.json):
three comparable local `ratatui-buffer-render-harness` runs over the 100k-row
table fixture using Ratatui `0.30.0` on Rust `1.93.1`. It reports mount p95
median 78320 us with 48.809% relative spread, page-move p95 median 908 us
with 388.326% spread, copy-selected-row p95 median 590 us with 130.847%
spread, app-state/buffer query p95 median 198 us with 159.091% spread, and
RSS delta median 36208640 bytes with 0.407% spread. This starts local
repeated-run coverage for `SB.3`; it is still buffer-harness evidence, not
real-terminal or cross-machine evidence.

The closest-Dart-peer data-widget variance artifact is
[Nocterm SB.3 repeated-run variance](benchmark-variance/nocterm-sb3-datatable-2026-06-02.json):
three comparable local `nocterm-test-harness` runs over the 100k-row
table-shaped fixture using Nocterm `0.6.0` on Dart `3.12.1`. It reports mount
p95 median 1170683 us with 41.409% relative spread, page-move p95 median
22230 us with 150.99% spread, copy-selected-row p95 median 3133 us with
74.433% spread, and terminal/app-state query p95 median 2751 us with 105.234%
spread. RSS delta has two zero samples and one 663552-byte sample, so its
relative spread is intentionally not reported. This is local test-harness
evidence, not real-terminal or terminal-safety evidence.

The native-core TypeScript data-widget variance artifact is
[OpenTUI SB.3 repeated-run variance](benchmark-variance/opentui-sb3-datatable-2026-06-02.json):
three comparable local `opentui-test-renderer-memory` runs over the 100k-row
table fixture using OpenTUI `0.3.1` on Bun `1.3.14`. It reports mount p95
median 107762 us with 42.953% relative spread, page-move p95 median 9039 us
with 135.69% spread, jump-to-end p95 median 12461 us with 146.409% spread,
copy-selected-row p95 median 33 us with 284.848% spread, frame/app-state query
p95 median 38 us with 171.053% spread, and RSS delta median 152289280 bytes
with 10.898% spread. This is local memory-renderer evidence, not
real-terminal or cross-machine evidence.

The mature Python app-framework data-widget variance artifact is
[Textual SB.3 repeated-run variance](benchmark-variance/textual-sb3-datatable-2026-06-02.json):
three comparable local `textual-run-test-harness` runs over the 100k-row
DataTable fixture using Textual `8.2.7` on Python `3.12.13`. It reports mount
p95 median 10503380 us with 32.667% relative spread, page-move p95 median
97347 us with 30.393% spread, jump-to-end p95 median 285626 us with 36.779%
spread, copy-selected-row p95 median 81377 us with 13.508% spread, and
widget-state query p95 median 230 us with 545.217% spread. RSS delta has one
10911744-byte sample and two zero samples, so its relative spread is
intentionally not reported. This completes local repeated-run coverage for the
main `SB.3` data-widget peer set; it is still test-harness evidence, not
real-terminal or cross-machine evidence.

The first strict-passing log/viewport variance artifact is
[Nocterm SB.4 repeated-run variance](benchmark-variance/nocterm-sb4-log-region-2026-06-02.json):
three comparable local `nocterm-test-harness` runs over the 100k starting log
lines plus 1000 appended entries fixture using Nocterm `0.6.0` on Dart
`3.12.1`. It reports append-burst p95 median 95014 us with 18.47% relative
spread, scrollback-jump p95 median 6099 us with 231.677% spread,
scroll-to-tail p95 median 5615 us with 101.603% spread, copy-selected-entry
p95 median 2469 us with 75.334% spread, filter-query p95 median 125479 us
with 148.463% spread, and terminal/app-state query p95 median 682 us with
49.56% spread. Unsafe artifact leak count stayed zero in all three runs. This
starts local repeated-run coverage for the `SB.4` log/viewport peer set; it is
still test-harness evidence, not real-terminal or cross-machine evidence.

The native-core TypeScript log/viewport variance artifact is
[OpenTUI SB.4 repeated-run variance](benchmark-variance/opentui-sb4-log-region-2026-06-02.json):
three comparable local `opentui-test-renderer-memory` runs over the 100k
starting log lines plus 1000 appended entries fixture using OpenTUI `0.3.1`
on Bun `1.3.14`. It reports append-burst p95 median 5018 us with 192.766%
relative spread, scrollback-jump p95 median 3587 us with 120.156% spread,
scroll-to-tail p95 median 3103 us with 42.217% spread, copy-selected-entry
p95 median 3 us with 333.333% spread, filter-query p95 median 40358 us with
266.879% spread, and frame/app-state query p95 median 45 us with 60% spread.
Unsafe artifact leak count stayed zero in all three runs. This expands local
repeated-run coverage for the `SB.4` log/viewport peer set; it is still
memory-renderer evidence, not real-terminal or cross-machine evidence.

The mature Python app-framework log/viewport variance artifact is
[Textual SB.4 repeated-run variance](benchmark-variance/textual-sb4-log-region-2026-06-02.json):
three comparable local `textual-run-test-harness` runs over the 100k starting
log lines plus 1000 appended entries fixture using Textual `8.2.7` on Python
`3.12.13`. It reports append-burst p95 median 92454 us with 23.275% relative
spread, scrollback-jump p95 median 43054 us with 9.363% spread,
scroll-to-tail p95 median 46689 us with 6.991% spread, copy-selected-entry
p95 median 73105 us with 23.747% spread, filter-query p95 median 108052 us
with 13.957% spread, and widget/app-state query p95 median 60 us with
68.333% spread. Unsafe artifact leak count stayed zero in all three runs.
This expands local repeated-run coverage for the `SB.4` log/viewport peer set;
it is still test-harness evidence, not real-terminal or cross-machine
evidence.

The Go model/update/viewport log/viewport variance artifact is
[Bubble Tea SB.4 repeated-run variance](benchmark-variance/bubbletea-sb4-log-region-2026-06-02.json):
three comparable local `bubbletea-viewport-model-harness` runs over the 100k
starting log lines plus 1000 appended entries fixture using Bubble Tea `2.0.7`
and Bubbles `2.1.0` on Go `1.25.0`. It reports append-burst p95 median
1346052 us with 67.347% relative spread, scrollback-jump p95 median 658370 us
with 63.013% spread, scroll-to-tail p95 median 649960 us with 20.058% spread,
copy-selected-entry p95 median 13 us with 23.077% spread, filter-query p95
median 437393 us with 35.305% spread, and app/model-state query p95 median
49 us with 75.51% spread. Unsafe artifact leak count stayed zero in all three
runs. This completes local repeated-run coverage for the main `SB.4`
log/viewport peer set; it is still model-harness evidence, not real-terminal
or cross-machine evidence.

The mature Python app-framework streaming Markdown variance artifact is
[Textual SB.5 repeated-run variance](benchmark-variance/textual-sb5-streaming-markdown-2026-06-02.json):
three comparable local `textual-run-test-harness` runs over the 100 streamed
chunk fixture using Textual `8.2.7` on Python `3.12.13`. It reports
chunk-update p95 median 159364 us with 40.515% relative spread,
chunk-frame p95 median 158718 us with 37.935% spread, final-render p95 median
45034 us with 151.392% spread, selected-block-copy p95 median 78141 us with
26.327% spread, and widget/app-state query p95 median 172 us with 92.442%
spread. Unsafe frame count stayed zero in all three runs. This starts local
repeated-run coverage for `SB.5`; it is still test-harness evidence, not
full-scale, real-terminal, or cross-machine evidence.

The Charm ecosystem streaming Markdown variance artifact is
[Bubble Tea SB.5 repeated-run variance](benchmark-variance/bubbletea-sb5-streaming-markdown-2026-06-02.json):
three comparable local `bubbletea-glamour-viewport-model-harness` runs over
the 100 streamed chunk fixture using Bubble Tea `2.0.7`, Bubbles `2.1.0`,
Glamour `2.0.0`, and Go `1.25.8`. It reports chunk-update p95 median
127299 us with 25.274% relative spread, chunk-frame p95 median 16422 us with
47.296% spread, final-render p95 median 4411 us with 181.909% spread,
selected-block-copy p95 median 95 us with 5723.158% spread due to one small
absolute outlier, and app/model-state query p95 median 25 us with 32% spread.
Unsafe frame count stayed zero in all three runs. Together with Textual, this
adds the first local repeated-run coverage for `SB.5`; it is still
model-harness evidence, not full-scale, real-terminal, or cross-machine
evidence. Treat this as the MVP-cycle stopping point for peer benchmark
expansion; additional peer fixtures, full-scale parity, cross-machine runs,
and public comparison claims are post-MVP work after API and core stability.

The input artifact must be a JSON object with this shape:

```json
{
  "schemaVersion": 1,
  "kind": "fleuryPeerBenchmarkRun",
  "runId": "nocterm-sb1-macos-2026-06-01",
  "peerId": "nocterm",
  "scenarioId": "SB.1",
  "capturedAt": "2026-06-01T00:00:00.000000Z",
  "source": {
    "name": "Nocterm",
    "version": "0.6.0",
    "url": "https://pub.dev/packages/nocterm"
  },
  "environment": {
    "machine": "macbook-pro-local",
    "operatingSystem": "macos",
    "runtime": "Dart 3.12.1",
    "terminalMode": "test-harness",
    "terminalSize": {"columns": 80, "rows": 24}
  },
  "fixture": {
    "workingDirectory": "peer-fixtures/nocterm/sb1_counter",
    "command": ["dart", "test", "test/counter_benchmark_test.dart"],
    "warmupIterations": 2,
    "measuredIterations": 20
  },
  "metrics": {
    "firstFrameUs": {"p95": 1000, "samples": 20},
    "commandToFrameUs": {"p95": 1500, "samples": 20},
    "semanticOrTestQueryUs": {"p95": 900, "samples": 20},
    "rssDeltaBytes": 4096,
    "lineOfCodeCount": 42,
    "testLineOfCodeCount": 24
  },
  "correctness": [
    {"gate": "counter text updates correctly", "pass": true},
    {"gate": "input/action path matches normal app use", "pass": true},
    {"gate": "test shape is documented", "pass": true}
  ]
}
```

The validator rejects unknown peers, unknown scenarios, peer/scenario pairs not
listed in the manifest, missing required metrics, and missing or failing claim
gates.

Useful lessons from the current baseline:

- The renderer already has low-byte-output diffing for normal UI updates.
- A mutable-cell optimization sounded plausible but regressed key benchmarks;
  benchmark evidence forced a revert.
- Dirty build dispatch improved when the O(n^2) shallowest-first scan was
  replaced with a sort-once pass.
- Text wrapping and eager large-list rebuilds are real pressure points.
- Large-list paint can be cheap when the visible region is bounded, but
  selection changes expose eager rebuild cost.
- The first Phase 1 scenario baselines are comfortably below candidate
  thresholds: `SB.1` command-to-frame p95 is 254 us, and `SB.3` page-move p95
  is 772 us with selected-row copy p95 310 us.
- The first text-input stress baseline gives concrete evidence for the
  strong-input launch claim: `SB.2` loads a 10k-character mixed-width editor,
  drives cursor movement, selection replacement, undo/redo, history,
  completion acceptance, chunked paste, secret redaction, and semantic queries.
  Cursor movement p95 is 798 us, insertion/deletion p95 is 641 us, selection
  p95 is 2191 us, full chunked paste completion p95 is 18573 us,
  semantic-query p95 is 508 us, and secret semantics stay redacted.
- The first Phase 2 log baseline gives a new streaming-output reference:
  `SB.4` append-burst p95 is 9591 us, scrollback-jump p95 is 3513 us,
  selected-entry copy p95 is 8608 us, filter-query p95 is 68785 us, and
  semantic-query p95 is 3630 us for 100k starting entries plus a 1000-line
  append burst.
- The indexed `SB.4` follow-up adds `LogRegionSearchIndex` pressure for large
  retained logs. It moves filter-query p95 to 35979 us while keeping
  append-burst p95 at 21859 us, copy-selected-entry p95 at 12068 us, and
  semantic-query p95 at 2874 us. Search-index construction is visible at
  319669 us p95, so worker/debounce policy remains the next question before
  making broad retained-log typeahead claims.
- The cooperative `SB.4` follow-up keeps the retained-log index explicit but
  moves build and append refresh through `TaskController` yield checkpoints.
  Search-index-build p95 is 375479 us, append-burst p95 is 17553 us,
  filter-query p95 is 21771 us, semantic-query p95 is 4505 us,
  `searchIndexProgressCurrent` is 100000, and `appendIndexProgressCurrent` is
  101000.
- The first Phase 2 hierarchy baseline now proves the indexed TreeTable path:
  `SB.11` builds a 100100-row `TreeTableSearchIndex` at 1851310 us p95, then
  filters a collapsed descendant by exact token at 4074 us p95. Selected-row
  copy is 8002 us p95, semantic-query is 1979 us p95, and page movement is
  11640 us p95. Fuzzy fallback scans and off-thread index construction remain
  future pressure points.
- The cooperative `SB.11` follow-up moves hierarchy index construction through
  `TaskController` yield checkpoints. Index-build p95 is 826676 us,
  filter-query p95 is 5706 us, semantic-query p95 is 1826 us,
  `indexProgressCurrent` is 100100, and `searchIndexRowCount` remains 100100.
- The first Phase 2 resize baseline gives terminal-dimension pressure across a
  table/log/editor surface: `SB.7` validates 500 resize events per iteration
  across eight sizes from 32x8 to 200x60, with resize-frame p95 488 us,
  semantic-query p95 593 us, and zero unsafe visible frames over 2500 measured
  resize frames.
- The integrated proof-app baseline now measures the actual example subpackage
  instead of isolated widgets. The refreshed `SB.10` run covers command
  palette, debounced Global Search, cooperative Indexed Logs, diagnostics,
  fake task, DataTable
  filter/copy, transcript composer/log stream, native process success, debug
  capture, semantics, and accessibility. The ranked-search refreshed run
  records full journey p95 296062 us, global-search p95 84221 us, indexed-logs
  p95 73452 us, command-palette p95 15076 us, process run-to-success p95
  58716 us, semantic-query p95 993 us, indexed log row count 195, filtered row
  count 49, progress current 195, and unsafe visible frames remain at zero.
- The first overlay baseline proved stale-action prevention and exposed the
  command-palette hot path. The optimized `SB.8` follow-up keeps correctness at
  zero stale palette semantics, zero route-depth mismatches, zero selected-row
  mismatches, and zero unexpected invocations over 800 measured cycles while
  bringing 1000-command filter p95 down to 1121 us and full-cycle p95 down to
  6429 us. Command palette latency is now launch-shaped on this fixture;
  repeated-machine and peer-equivalent evidence remain open.
- The first subprocess/output baseline closes the remaining benchmark-shaped
  process gap: `SB.9` runs a 1 MB target subprocess output path plus stderr
  failure, cancellation, external-editor handoff, and unsafe OSC/DCS/APC
  payloads. Saved 10-iteration results show process-run p95 647254 us,
  cancellation p95 11823 us, stream-frame p95 6230 us, process-panel-render
  p95 10649 us, semantic-query p95 1965 us, restored handoff state in every
  path, and zero unsafe visible/copy/semantic artifact leaks.

Scenario benchmarks should preserve this discipline: every optimization needs
to tie back to an app-shaped workload or a specific microbenchmark bottleneck
inside one.

## Peer Benchmark Lessons

These are the first benchmark practices to absorb from peers.

| Peer | Useful lesson | Source |
| --- | --- | --- |
| Nocterm | Direct Dart peer with benchmark filtering, baseline save/CI modes, median/min/max/sample reporting, and display-list benchmarks for cell width caching, changed-region percentages, direct painting, and full pipeline cost. | [benchmark.dart](https://github.com/Norbert515/nocterm/blob/main/benchmark/benchmark.dart), [display_list_benchmark.dart](https://github.com/Norbert515/nocterm/blob/main/benchmark/display_list_benchmark.dart) |
| Ratatui | Rust peer with Criterion benches per widget and explicit large table/paragraph workloads. Table benches cover 64, 2048, and 16384 rows; paragraph benches cover large line counts, wrapping, and scroll variants. | [benches](https://github.com/ratatui/ratatui/tree/main/ratatui/benches) |
| OpenTUI | Native-core/TypeScript peer with benchmark result objects that include scenario categories, timing stats, memory stats, content stats, and latest JSON result artifacts. It also has native Zig benches. | [benchmark package](https://github.com/anomalyco/opentui/tree/main/packages/core/src/benchmark), [native bench README](https://github.com/anomalyco/opentui/tree/main/packages/core/src/zig/bench) |
| Textual | Full app-framework peer. Use app-level comparison for screens, actions, workers, text areas, data tables, logs, devtools, and testing where benchmark harness parity is not direct. | [Textual docs](https://textual.textualize.io/) |
| Bubble Tea | Product-taste and CLI-workflow peer. Compare interaction shape, input behavior, synchronized output, component ergonomics, and production CLI feel where raw benchmark parity is not direct. | [Bubble Tea](https://github.com/charmbracelet/bubbletea) |
| Ink | React-style CLI peer. Compare reactive ergonomics, stdout behavior, component composition, and developer adoption shape rather than terminal-buffer internals. | [Ink](https://github.com/vadimdemedes/ink) |

Peer comparisons should use matching user-visible workloads where possible,
not internal architecture comparisons. Fleury wins only if developers can see
better latency, robustness, API ergonomics, testing, diagnostics, or app
coverage.

## Measurement Model

Every scenario benchmark should emit a machine-readable JSON record and a short
human summary. The JSON schema can evolve, but each record should include:

- `schemaVersion`
- `scenarioId`
- `scenarioName`
- `fleuryVersion`
- `gitSha`
- `dartVersion`
- `runMode`: `jit`, `aot`, or `test`
- `os`
- `cpu`
- `terminalProfile`
- `terminalSize`
- `seed`
- `warmupIterations`
- `measuredIterations`
- `startedAt`
- `durationMs`
- `metrics`
- `thresholds`
- `pass`
- `notes`

Metrics should be layered. Not every scenario can collect every signal on day
one, but the harness should be designed around these categories:

- Interaction latency: input-to-frame median, p95, p99, and max.
- Frame timing: build, layout, paint, diff, write, and total frame time when
  those phases can be separated.
- Output cost: bytes written, cells visited, cells changed, dirty regions, and
  render passes.
- Memory: heap delta, retained objects, peak RSS where available, and fixture
  size.
- Semantics: semantic node count, query latency, focused node, selected nodes,
  available actions, and capability fallback nodes.
- Correctness: golden/cell assertions, semantic assertions, ordering checks,
  terminal restore checks, and no-overlap layout assertions.
- Security/capability: sanitization events, redaction events, policy blocks,
  degraded capabilities, and unsafe escape suppression.
- Workload progress: rows processed, lines appended, markdown bytes parsed,
  subprocess bytes streamed, tasks completed, cancellations observed.

## Candidate Thresholds

These thresholds are initial targets. They should be refined after the first
baseline harness exists on known hardware. Until then, treat them as launch
quality budgets, not immutable CI gates.

| Workload class | Candidate pass threshold |
| --- | --- |
| Single-step interaction | p95 input-to-frame under 16 ms; max under 33 ms for normal terminal sizes. |
| Dense table navigation | p95 under 16 ms for row movement and page movement with 100k rows. |
| Text editing | p95 under 16 ms for cursor movement, insertion, deletion, selection, and paste handling after chunking. |
| Burst streaming | p95 frame time under 33 ms while preserving input responsiveness under 100 ms. |
| Long streaming | No unbounded memory growth during a 10-minute log or markdown stream soak. |
| Resize storm | No exceptions, no terminal corruption, no overlapping semantic regions, and p95 frame time under 50 ms. |
| Subprocess handoff | Terminal modes restored after success, error, cancellation, and external editor handoff. |
| Untrusted output | Unsafe escapes blocked or policy-gated; redaction runs before display, copy, debug capture, or benchmark artifact writing. |
| Semantic queries | Common tester queries by role/label/focus/action complete fast enough to be used in normal tests, with exact budget set after M1 semantic tree profiling. |

If a scenario misses a candidate threshold, the result is still useful. The
first job of the lab is signal. The second job is optimization.

## Shared Fixtures

All scenarios should use deterministic fixtures so changes are comparable
across commits and peer runs.

- Terminal sizes: `80x24`, `120x40`, and `200x60`.
- Seeds: fixed default seed plus optional explicit seed in JSON output.
- Text fixture: ASCII, emoji, CJK, combining marks, wide graphemes, long
  tokens, multiline content, markdown, and malformed UTF-8 replacement cases.
- Data fixture: 100k rows, 8 columns, stable row IDs, mixed-width content,
  sortable numeric/date/status fields, long text fields, and hidden columns.
- Log fixture: short lines, huge lines, ANSI-colored lines, malformed escape
  sequences, secrets for redaction, and high-frequency append chunks.
- Markdown fixture: headings, lists, tables, code fences, links, inline code,
  incremental chunks, and adversarial partial blocks.
- Process fixture: bounded subprocess output, cancellation, exit error, large
  stdout/stderr streams, and terminal suspension/restoration.
- Capability fixture: fake terminal profiles for plain ANSI, truecolor, mouse,
  bracketed paste, links, images, tmux/SSH constraints, and restricted
  clipboard.

## Scenario Catalog

### SB.1 Time To Counter App

- Intent: Keep the simple path honest while Fleury grows app-scale features.
- Fixture: Minimal counter app with `FleuryApp`, one command, one shortcut,
  one text node, and one button/action.
- Target metrics: startup time in test mode, first frame time, bytes emitted,
  semantic node count, command invocation latency, generated code size if AOT
  is measured.
- Peer targets: Nocterm counter app, Bubble Tea counter, Ink counter, Textual
  minimal app.
- Candidate threshold: First interactive frame and increment action should
  remain below visible latency on normal terminals; exact launch threshold set
  after first local baseline.
- Implementation notes: This is adoption signal, not a render stress test.

### SB.2 Text Editing Composer Stress

- Intent: Prove text input can carry developer tools, agent prompts, forms,
  search, and command palettes.
- Fixture: Single-line and multiline editor containing 10k characters with
  emoji, CJK, combining marks, long lines, paste chunks, undo/redo, history,
  selection, completion menu, validation error, and password/secret mode.
- Target metrics: cursor movement p95, insertion/deletion p95, selection p95,
  paste chunking latency, undo/redo latency, semantic query latency, heap
  delta, correctness across grapheme boundaries.
- Peer targets: Nocterm text-input behavior, Textual `TextArea`, Bubble Tea
  `textarea`, prompt-toolkit-style editing depth as an aspirational input
  benchmark.
- Candidate threshold: Common cursor/edit actions p95 under 16 ms; large paste
  may chunk but must keep input responsive under 100 ms.
- Implementation notes: Implemented in the core scenario runner because this
  measures `TextInput`, `TextArea`, `TextEditingController`, paste scheduling,
  history, completion state acceptance, redaction, and semantics without
  depending on `fleury_widgets`. Rendering should consume a pure editing model;
  do not bake terminal cell positions into editing correctness.
- Evidence:
  [scenario runner](../../packages/fleury/benchmark/scenario_benchmarks.dart),
  [baseline](../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json),
  [Nocterm peer fixture](../../peer-fixtures/nocterm/sb2_text_editing),
  [Nocterm peer run](../../peer-fixtures/nocterm/sb2_text_editing/results/nocterm-sb2-text-editing-2026-06-01.json).

### SB.3 DataTable 100k Rows

- Intent: Make data-heavy widgets a clear Fleury win.
- Fixture: 100k rows x 8 columns, stable keys, fixed header, selectable rows,
  sortable columns, filter/search box, copy selected row/cell, hidden columns,
  and mixed-width content.
- Target metrics: initial visible render, arrow movement, page movement,
  jump-to-row, sort latency, filter latency, selection/copy latency, semantic
  row/cell query latency, heap delta, bytes emitted.
- Peer targets: Ratatui table large-row benches, OpenTUI text-table
  replace/incremental/selection scenarios, Textual `DataTable`, Nocterm table
  or list equivalents where available.
- Candidate threshold: Row/page navigation p95 under 16 ms after initial
  setup; filter/sort targets set after first baseline but must not require
  mounting all 100k rows as widgets.
- Implementation notes: Treat DataTable as a semantic render island: optimized
  rendering is allowed only if semantics, focus, selection, copy, and tests
  remain first-class. Because `fleury_widgets` depends on `fleury`, this
  benchmark should live in a widgets-package runner or a root-level runner rather
  than the core `packages/fleury/benchmark/scenario_benchmarks.dart` entry point.
  Current implementation uses the package-local
  `packages/fleury_widgets/benchmark/scenario_benchmarks.dart` runner and
  includes selected-row copy latency in the JSON metrics.
- Evidence:
  [scenario runner](../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart),
  [baseline](../../packages/fleury_widgets/benchmark/results/phase1-widgets-2026-05-31.json),
  [Textual peer fixture](../../peer-fixtures/textual/sb3_datatable),
  [Textual peer run](../../peer-fixtures/textual/sb3_datatable/results/textual-sb3-datatable-2026-06-01.json),
  [Ratatui peer fixture](../../peer-fixtures/ratatui/sb3_datatable),
  [Ratatui peer run](../../peer-fixtures/ratatui/sb3_datatable/results/ratatui-sb3-datatable-2026-06-01.json),
  [OpenTUI peer fixture](../../peer-fixtures/opentui/sb3_datatable),
  [OpenTUI peer run](../../peer-fixtures/opentui/sb3_datatable/results/opentui-sb3-datatable-2026-06-02.json).

### SB.4 Log Tailing And Scrollback

- Intent: Prove Fleury can handle real process logs and observability panes.
- Fixture: Append 100k log lines in chunks; include ANSI colors, huge lines,
  malformed escapes, secrets, stderr markers, paused tail, scrollback, search,
  selection, and copy.
- Target metrics: append throughput, p95 frame time during stream, input
  responsiveness while appending, memory growth, sanitization events,
  redaction events, search latency, scroll anchor correctness.
- Peer targets: Textual `Log`, Bubble Tea viewport/list patterns, OpenTUI text
  buffer render benchmarks, Nocterm display-list changed-region scenarios.
- Candidate threshold: Sustain burst updates with p95 frame time under 33 ms
  and no input stall above 100 ms; memory must remain bounded by configured
  scrollback policy.
- Implementation notes: This scenario connects data widgets, effects,
  security policy, and terminal output capture. Current implementation uses
  the package-local `fleury_widgets` scenario runner and the app-facing
  `LogRegion` widget. The default filter path is optimized linear search over
  sanitized searchable fields, and large retained-log typeahead can opt into
  `LogRegionSearchIndex`. The indexed follow-up moves 100k-entry filter p95
  below the candidate 80 ms budget, while explicit index-build timing keeps
  debounce, incremental, and worker-backed policy decisions visible. Current
  cooperative follow-up runs index build and append refresh through
  `TaskController` progress/cancellation/yield checkpoints.
  Subprocess-specific streaming, handoff, and unsafe-output pressure are
  covered by `SB.9`.
- Evidence:
  [Textual peer fixture](../../peer-fixtures/textual/sb4_log_region),
  [Textual peer run](../../peer-fixtures/textual/sb4_log_region/results/textual-sb4-log-region-2026-06-01.json),
  [Bubble Tea peer fixture](../../peer-fixtures/bubbletea/sb4_log_region),
  [Bubble Tea peer run](../../peer-fixtures/bubbletea/sb4_log_region/results/bubbletea-sb4-log-region-2026-06-02.json),
  [Nocterm peer fixture](../../peer-fixtures/nocterm/sb4_log_region),
  [Nocterm peer run](../../peer-fixtures/nocterm/sb4_log_region/results/nocterm-sb4-log-region-2026-06-02.json).

### SB.11 TreeTable Hierarchy Filter And Copy

- Intent: Prove hierarchical data tables preserve tree meaning, table cells,
  copy, sanitization, and descendant discovery under large retained data.
- Fixture: Build a 100k-leaf hierarchy plus branch nodes, initially expand one
  branch, expand a second branch, page and jump through visible rows, filter
  for a collapsed descendant, copy the selected filtered leaf, and query
  semantics.
- Target metrics: fixture build, mount, first render, expand/collapse
  navigation, page/jump movement, filter query latency, selected-row copy,
  semantic query, ANSI bytes, visible range, node count, sanitizer fixture
  count, and RSS delta.
- Peer targets: Textual `Tree`/`DataTable`, Ratatui table/tree patterns,
  Nocterm large display-list/table benchmarks, and file/search-heavy developer
  tools where hidden descendants must be discoverable.
- Candidate threshold: Normal branch navigation and selected-row copy should
  stay under 16 ms p95; large hierarchy filtering should move toward sub-100 ms
  p95 before public launch claims.
- Implementation notes: `SB.11` intentionally avoids reusing the already
  reserved `SB.5` slot. The first unindexed baseline exposed 676896 us p95
  filtering over 100k leaves; `TreeTableSearchIndex` plus exact-token postings
  brought the saved baseline to 4074 us p95 query time. Current cooperative
  follow-up runs index construction through `TaskController` yield checkpoints
  while preserving the exact-token query path. Keep this scenario as pressure
  for fuzzy fallback scans, index-build cost, worker query, and any future
  TreeTable render-island decision.

### SB.12 Layout Dirtiness Cache

- Intent: Prove dirty-layout propagation is measurable and avoids unnecessary
  layout work in retained app frames.
- Fixture: Mount a static pane beside a changing counter pane, invoke the
  counter command, toggle a paint-only counter style, toggle same-width
  single-line text content, rebuild with the same child-list identities, render
  an idle frame with no changes, and measure a 2,000-row `ScrollView` child
  through a 24-row viewport.
- Target metrics: first-frame layout performed/skipped counts, update-frame
  performed/skipped counts, paint-only-frame performed/skipped counts,
  text-paint-only-frame performed/skipped counts, idle-frame performed/skipped
  counts, command-to-frame latency, paint-only-frame latency,
  text-paint-only-frame latency, idle-frame latency, viewport first/scroll
  frame latency, visible painted row counts, and semantic query latency.
- Peer targets: Flutter dirty-layout expectations, Textual widget refresh
  behavior, Nocterm display-list change propagation, and OpenTUI/Ratatui
  changed-region benchmark discipline.
- Candidate threshold: Update frames should skip at least the clean static
  subtree; paint-only style, paint-only text, and idle frames should perform
  zero layout work while returning the cached root layout.
- Implementation notes: Implemented in the core scenario runner because it
  measures `RenderObject` layout dirtiness directly. The refreshed baseline
  records command-to-frame p95 11799 us, paint-only-frame p95 1210 us,
  text-paint-only-frame p95 3251 us, update-frame layout p95 7 performed /
  3 skipped, paint-only-frame layout p95 0 performed / 1 skipped,
  text-paint-only-frame layout p95 0 performed / 1 skipped, and idle-frame
  layout p95 0 performed / 1 skipped.
  The child-list replacement follow-up records command-to-frame p95 3559 us,
  child-list no-op frame p95 4363 us, child-list no-op layout p95 0 performed /
  1 skipped, and preserves the paint-only/text-paint-only/idle p95 layout
  result of 0 performed / 1 skipped.
  The viewport paint follow-up records command-to-frame p95 7014 us,
  viewport-first-frame p95 4773 us, viewport-scroll-frame p95 1245 us, and
  p95 24 painted rows on a 24-row viewport over a 2,000-row child, while
  preserving paint-only/text-paint-only/child-list/idle p95 layout result of
  0 performed / 1 skipped.
- Evidence:
  [scenario runner](../../packages/fleury/benchmark/scenario_benchmarks.dart),
  [baseline](../../packages/fleury/benchmark/results/phase2-layout-dirtiness-2026-06-01.json),
  [child-list follow-up](../../packages/fleury/benchmark/results/phase2-layout-dirtiness-child-list-2026-06-02.json),
  [viewport paint follow-up](../../packages/fleury/benchmark/results/phase2-layout-dirtiness-viewport-paint-2026-06-02.json).

### SB.5 Streaming Markdown

- Intent: Make rich streamed content safe and smooth.
- Fixture: Incrementally append markdown chunks containing headings, lists,
  tables, code fences, links, inline code, partial blocks, long paragraphs,
  and unsafe link/output payloads.
- Target metrics: incremental parse/update latency, frame timing, wrap cost,
  memory growth, sanitized link events, semantic heading/link/code nodes, copy
  correctness.
- Peer targets: OpenTUI markdown parse/incremental/style benchmarks, Textual
  markdown widget behavior, Bubble Tea markdown renderers used in Charm apps.
- Candidate threshold: Streaming updates p95 under 33 ms for normal chunks;
  huge chunks can batch, but must preserve input responsiveness.
- Implementation notes: Do not parse the full document on every chunk unless
  the first baseline proves it is cheap enough.
- Current evidence: `SB.5` now runs in the `fleury_widgets` scenario runner.
  The first 5-iteration Dart 3.12.1 baseline over the default 100k-row scaled
  fixture streams 1000 chunks per iteration with chunk-update p95 13428 us,
  chunk-parse p95 12588 us, chunk-frame p95 926 us, semantic-query p95
  2155 us, and zero unsafe frames. Full-document parse-on-append is acceptable
  for this launch fixture; revisit incremental parsing when larger documents,
  wrapping pressure, or peer comparisons make it necessary.
- First peer evidence:
  [Textual SB.5 run artifact](../../peer-fixtures/textual/sb5_streaming_markdown/results/textual-sb5-streaming-markdown-2026-06-02.json)
  validates the same `SB.5` manifest gates at a 100-chunk scale in
  `textual-run-test-harness` mode. It records chunk-update p95 153495 us,
  chunk-frame p95 151148 us, final-render p95 58293 us,
  selected-block-copy p95 125601 us, widget/app-state query p95 423 us,
  41 sanitized chunks, 8 unsafe links with visible fallback, and zero unsafe
  frames. The full 1000-chunk Textual path was attempted locally but was too
  slow for routine validation in this run; keep full-scale Textual evidence as
  a separate long-run artifact before public streaming-markdown claims.
- Second peer evidence:
  [Bubble Tea SB.5 run artifact](../../peer-fixtures/bubbletea/sb5_streaming_markdown/results/bubbletea-sb5-streaming-markdown-2026-06-02.json)
  validates the same `SB.5` manifest gates at a 100-chunk scale in
  `bubbletea-glamour-viewport-model-harness` mode. It records chunk-update p95
  145270 us, chunk-parse p95 852 us, chunk-frame p95 16742 us,
  final-render p95 13567 us, selected-block-copy p95 72 us,
  app/model-state query p95 63 us, 41 sanitized chunks, 8 unsafe links with
  visible fallback, and zero unsafe frames. This path re-renders the full
  Markdown document through Glamour after each append, so treat it as Charm
  ecosystem Markdown evidence rather than a peer-owned incremental Markdown
  widget. Repeated 100-chunk variance now exists for both Textual and Bubble
  Tea/Bubbles/Glamour; full 1000-chunk peer parity, real-terminal evidence,
  and cross-machine evidence remain open and deferred until post-MVP.

### SB.6 Dashboard Update Pressure

- Intent: Validate retained reactive updates under many small changing
  surfaces.
- Fixture: 20 to 50 widgets updating at 10 Hz and 30 Hz: progress bars,
  gauges, counters, sparkline/chart cells, status rows, and notifications.
- Target metrics: coalesced frame count, p95 frame time, layout performed /
  skipped counts, dirty element count, cells changed, bytes emitted, animation
  scheduler overhead, semantic progress state.
- Peer targets: Ratatui gauge/sparkline/chart benches, Bubble Tea spinner and
  progress components, Nocterm full pipeline benchmark.
- Candidate threshold: Coalesce bursts into stable frames; p95 under 33 ms at
  30 Hz on normal terminal sizes.
- Implementation notes: This should reveal whether app status, animation, and
  render scheduling compose cleanly.
- Current evidence: `SB.6` now runs in the `fleury_widgets` scenario runner.
  The first 20-iteration Dart 3.12.1 baseline over the default 100k-row scaled
  fixture updates 23 dashboard surfaces for 400 ticks per iteration with
  update-total p95 267 us, update-frame p95 120 us, update-pump p95 97 us,
  semantic-query p95 439 us, update-frame layout p95 45 performed /
  29 skipped, and zero unsafe frames. The first fixture uses tester-driven
  updates rather than a wall-clock scheduler; future scheduler pressure should
  add animation/coalescing evidence when needed.

### SB.7 Resize Storm

- Intent: Prove terminal correctness under repeated dimension changes.
- Fixture: Alternate terminal sizes across `80x24`, `120x40`, `200x60`, narrow
  widths, and short heights for 500 resize events while a table/log/editor
  screen is active.
- Target metrics: resize-to-frame latency, layout time, paint/diff time,
  exceptions, terminal cleanup state, focus preservation, semantic region
  validity, no-overlap assertions.
- Peer targets: Nocterm terminal resize behavior, Textual resize/layout
  behavior, Ratatui layout examples under changed `Frame` size.
- Candidate threshold: No exceptions or corruption; p95 under 50 ms with valid
  semantics after every resize.
- Implementation notes: This catches bugs that isolated render benches miss.
  Current implementation lives in the `fleury_widgets` scenario runner because
  it composes DataTable, LogRegion, and TextInput. It validates every resize
  frame for safe visible output and semantic table/log/text-field nodes. The
  first saved baseline uses 100k table rows, 5k log entries, 500 resize events
  per iteration, and 5 measured iterations.

### SB.8 Overlay And Command Palette Churn

- Intent: Prove modals, dialogs, command palettes, focus scopes, semantics,
  and shortcuts remain predictable.
- Fixture: Repeatedly open/close command palette, dialogs, toasts, menus, help
  overlays, and search panel while background updates continue.
- Target metrics: open/close latency, focus transition correctness, command
  registry query latency, semantic active-modal state, dirty region size,
  memory churn.
- Peer targets: Textual command palette/actions/screens, Bubble Tea modal
  patterns, Ink prompt overlays where available.
- Candidate threshold: p95 open/close under 16 ms for lightweight overlays;
  no stale focus or stale semantic actions after close.
- Implementation notes: This scenario should be run early while building
  `FleuryApp`.
- Current evidence: `SB.8` now runs in the `fleury_widgets` scenario runner.
  The first 20-iteration Dart 3.12.1 baseline uses a 1000-command registry and
  40 cycles per iteration. It validates app-screen command discovery, fuzzy
  filter selection, Enter invocation, semantic submit, semantic row activate,
  Escape dismissal, semantic dismissal, disabled visible-but-inert commands,
  route-depth restoration, and stale semantic cleanup. The optimized follow-up
  switches palette rows to lazy visible mounting, caches command search text,
  makes stable command IDs searchable, and ranks exact/prefix/contains matches
  ahead of fuzzy subsequence matches. It passes with open p95 1615 us, filter
  p95 1121 us, selection p95 545 us, action p95 2316 us, settle p95 227 us,
  cycle p95 6429 us, semantic-query p95 618 us, zero stale palette semantics,
  and zero unexpected invocations.

### SB.9 Subprocess Handoff And Untrusted Output

- Intent: Make process workflows robust enough for real developer tools.
- Fixture: Run bounded subprocesses that stream 1 MB colored output, write
  stderr, exit non-zero, get cancelled, request external editor handoff, and
  emit unsafe OSC/DCS/APC/control sequences.
- Target metrics: throughput, frame timing while streaming, cancellation
  latency, terminal mode restoration, captured output size, sanitization and
  policy-block counts, redaction-before-artifact assertions.
- Peer targets: Textual workers/subprocess patterns, Bubble Tea command
  effects, Nocterm async examples where available.
- Candidate threshold: Terminal modes restored in every exit path; unsafe
  escapes never reach display/copy/debug artifacts unless explicitly
  policy-gated.
- Implementation notes: Implemented in
  [fleury_widgets scenario benchmarks](../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart)
  because the fixture composes `ProcessPanel`, `TerminalOutputRegion`,
  `LogRegion`, `ProcessTaskController`, terminal handoff, and external-editor
  handoff. The saved baseline is
  [phase2-subprocess-output-2026-06-01.json](../../packages/fleury_widgets/benchmark/results/phase2-subprocess-output-2026-06-01.json).
  Current results: 1,000,000 target process bytes, 4288 captured output
  records, process-run p95 647254 us, cancellation p95 11823 us,
  stream-frame p95 6230 us, semantic-query p95 1965 us, restored handoff state
  in all four paths, and zero unsafe artifact leaks. This is still a
  capability/security scenario as much as a performance scenario.

### SB.10 Proof-App Journey

- Intent: Measure the actual Phase 1 example subpackage instead of only
  component fixtures.
- Fixture: Start the proof app, navigate sidebar/screens, type in composer,
  stream content, run debounced global search, filter/select/copy table rows,
  open command palette, inspect diagnostics, pause/resume log tail, and trigger
  one worker success/failure.
- Target metrics: end-to-end scenario duration, per-action p95, frame timing,
  semantic checkpoints, command execution ordering, capability fallback state,
  debug capture size.
- Peer targets: App-level comparison against Nocterm, Textual, Bubble Tea,
  OpenTUI, Ratatui wrappers, and Ink where equivalent examples can be built or
  found.
- Candidate threshold: The proof app should remain responsive throughout the
  journey; no action should require brittle cell-only assertions when a
  semantic assertion would be natural.
- Implementation notes: This becomes the strongest launch evidence because it
  combines all core foundations. Current implementation lives in the
  `fleury_example_console` package because it measures the integrated proof
  app. It records per-action timings for command palette, debounced global
  search, table filter/copy, transcript updates, process run-to-success,
  diagnostics, debug capture, and semantic queries, plus debug-capture size,
  accessibility output size, command counts, status counts, selected search
  result state, diagnostic capability rows, process output count, and
  unsafe-frame count.

## Harness Implementation Path

M1.8 should implement the first repeatable harness in small slices:

1. Add a scenario runner under `packages/fleury/benchmark/scenarios/` or a
   single `packages/fleury/benchmark/scenario_benchmarks.dart` entry point.
2. Reuse existing fake-driver and benchmark support before adding new
   runtime machinery.
3. Emit JSON records plus human summaries.
4. Keep deterministic fixture generation in benchmark support code, not in
   individual scenario files.
5. Add a `--filter` option so slow scenarios do not block every local run.
6. Add a `--save` option for local baseline snapshots.
7. Add a `--ci` mode only after the first baseline is stable enough to avoid
   noisy failures.
8. Keep peer adapters optional. Peer comparison should be a separate command
   or documented manual workflow until parity is proven.

The first implementation order should be:

1. SB.1 Time To Counter App.
2. SB.3 DataTable 100k Rows.
3. SB.2 Text Editing Composer Stress.
4. SB.4 Log Tailing And Scrollback.
5. SB.5 Streaming Markdown.
6. SB.6 Dashboard Update Pressure.
7. SB.11 TreeTable Hierarchy Filter And Copy.
8. SB.7 Resize Storm.
9. SB.10 Proof-App Journey.
10. SB.8 Overlay And Command Palette Churn.
11. SB.9 Subprocess Handoff And Untrusted Output.
12. SB.12 Layout Dirtiness Cache.

The initial scenario set now covers every benchmark-shaped launch gap. Next
benchmark work should either repeat baselines across machines, build
peer-equivalent workloads, or come from a concrete product scenario that
exposes a new gap.

## Peer Comparison Method

Use three comparison levels:

1. Direct benchmark parity: when a peer has a comparable benchmark or example,
   port the fixture shape and record versions, commands, and hardware.
2. App-level parity: when internals differ too much, compare user-visible
   behavior such as table navigation, text editing, command palette, workers,
   diagnostics, testing, and terminal recovery.
3. Capability matrix: when timing comparison is not meaningful, compare
   support for semantics, tests, terminal protocols, degradation, security
   policy, and developer ergonomics.

Do not compare against a stale peer snapshot. Record the peer version,
source link, command, and date whenever a comparison is added to
[peer-scorecards.md](peer-scorecards.md).

## Risks And Open Questions

- The first Dart harness may not expose allocation data cleanly. If so, record
  heap deltas and VM-service snapshots separately.
- CI hardware variance can make p95 thresholds noisy. Use saved baselines
  before enforcing hard CI gates.
- AOT numbers may differ from JIT numbers. Record both when launch performance
  claims depend on standalone binaries.
- Peer frameworks may lack direct equivalents for Fleury semantics or app
  kernel features. Compare developer-visible outcomes instead of forcing fake
  parity.
- Large scenario fixtures can become slow enough to discourage local use. Keep
  filters and short smoke variants from the start.

## Acceptance Checklist

- [x] Scenarios have stable names and IDs.
- [x] Scenarios identify fixture shape.
- [x] Scenarios identify target metrics.
- [x] Scenarios identify peer comparison targets.
- [x] Scenarios define candidate pass/fail thresholds to refine during
  implementation.
- [x] Harness implementation path is scoped to Phase 1.
- [x] Scenario lab links back to existing Fleury benchmark and profiling docs.
