# fleury_widgets scenario benchmarks

Scenario benchmarks measure app-shaped widget journeys and emit JSON records.
They live in `fleury_widgets` when the scenario depends on high-level widgets
that core `fleury` must not import.

```sh
dart run benchmark/scenario_benchmarks.dart --list
dart run benchmark/scenario_benchmarks.dart --filter=SB.3 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.4 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.5 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.6 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.7 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.8 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.9 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.11 --json
dart run benchmark/scenario_benchmarks.dart --filter=datatable --save=benchmark/results/widgets-scenarios.json
```

## SB.3 DataTable 100k Rows

`SB.3` mounts a 100k-row `DataTable`, renders the first frame, moves selection
with Arrow Down and Page Down, jumps to the final row, copies the selected row,
and queries semantics. Output includes p50/p95/p99/max timing for mount, first
render, navigation, jump-to-end, selected-row copy, semantic query, ANSI bytes,
semantic node count, visible range, selected key, RSS delta, and cell-builder
call counts.

Candidate thresholds are informational until stable baselines exist.

Saved Phase 1 baseline:

- `benchmark/results/phase1-widgets-2026-05-31.json` — `SB.3 DataTable 100k
  Rows` on Dart 3.12.1, 20 measured iterations, page-move p95 772 us,
  selected-row copy p95 310 us, semantic-query p95 2497 us.

## SB.4 LogRegion Tailing And Scrollback

`SB.4` mounts a 100k-entry `LogRegion`, renders the initial tail, appends a
burst of log entries containing unsafe terminal payloads, verifies sanitized
tail-follow rendering, jumps into scrollback, returns to the tail, copies the
selected entry, and queries semantics. Output includes p50/p95/p99/max timing
for fixture build, optional search-index build, mount, first render, append
burst, scrollback jump, scroll-to-tail, selected-entry copy, filter query,
semantic query, ANSI bytes, semantic node count, visible range, selected key,
sanitizing fixture row count, copied byte count, and RSS delta.

Saved Phase 2 baselines:

- `benchmark/results/phase2-logregion-2026-05-31.json` — `SB.4 LogRegion
  Tailing And Scrollback` on Dart 3.12.1, 20 measured iterations, append-burst
  p95 9591 us, scrollback-jump p95 3513 us, copy-selected-entry p95 8608 us,
  filter-query p95 68785 us, semantic-query p95 3630 us.
- `benchmark/results/phase2-logregion-indexed-2026-06-01.json` — indexed
  `SB.4 LogRegion Tailing And Scrollback` on Dart 3.12.1, 20 measured
  iterations, search-index-build p95 319669 us, append-burst p95 21859 us,
  scrollback-jump p95 4988 us, copy-selected-entry p95 12068 us, filter-query
  p95 35979 us, semantic-query p95 2874 us. This moves retained-log typeahead
  below the 80 ms candidate query budget, but index construction remains a
  worker/debounce candidate for launch polish.
- `benchmark/results/phase2-logregion-cooperative-index-2026-06-01.json` —
  cooperative indexed `SB.4` on Dart 3.12.1, 5 measured iterations,
  search-index-build p95 375479 us, append-burst p95 17553 us, filter-query
  p95 21771 us, semantic-query p95 4505 us, `searchIndexProgressCurrent`
  100000, and `appendIndexProgressCurrent` 101000. The index build and append
  refresh now run through `TaskController` with cooperative progress/yield
  checkpoints.

## SB.5 Streaming Markdown

`SB.5` incrementally appends markdown chunks containing headings, lists,
table-like rows, code fences, links, inline code, partial paragraph chunks,
long paragraphs, unsafe OSC payloads, and unsafe link schemes. It renders after
each append, then copies the selected final block and queries semantics. Output
includes p50/p95/p99/max timing for per-chunk parse cost, per-chunk frame
cost, combined chunk update cost, final render, selected-block copy, semantic
query, ANSI bytes, markdown document counts, unsafe-link count, sanitized block
count, unsafe frame count, copied byte count, and RSS delta.

Saved Phase 2 baseline:

- `benchmark/results/phase2-streaming-markdown-2026-06-01.json` —
  `SB.5 Streaming Markdown` on Dart 3.12.1, 5 measured iterations over the
  default 100k-row scaled fixture, 1000 markdown chunks per iteration,
  chunk-update p95 13428 us, chunk-parse p95 12588 us, chunk-frame p95 926 us,
  semantic-query p95 2155 us, and no unsafe frames.

## SB.6 Dashboard Update Pressure

`SB.6` keeps a compact dashboard mounted while repeatedly updating progress
bars, gauges, sparklines, a bar chart, counters, and status rows. It measures
per-update pump cost, frame cost, combined update cost, first render, semantic
query, layout performed/skipped counts, ANSI bytes, progress semantic count,
unsafe frame count, and RSS delta.

Saved Phase 2 baseline:

- `benchmark/results/phase2-dashboard-update-2026-06-01.json` —
  `SB.6 Dashboard Update Pressure` on Dart 3.12.1, 20 measured iterations over
  the default 100k-row scaled fixture, 400 dashboard ticks per iteration,
  update-total p95 267 us, update-frame p95 120 us, update-pump p95 97 us,
  semantic-query p95 439 us, update-frame layout p95 45 performed /
  29 skipped, and no unsafe frames.

## SB.7 Resize Storm

`SB.7` keeps a table/log/editor surface mounted while alternating normal,
wide, narrow, and short terminal sizes. It validates every resize frame for
safe visible output and semantic table/log/text-field nodes. Output includes
p50/p95/p99/max timing for resize frames and semantic queries, distinct size
coverage, ANSI bytes, table/log visible ranges, selected keys, unsafe frame
count, and RSS delta.

Use `--resize-events=N` to change the storm length. The default is 500 events.

Saved Phase 2 baseline:

- `benchmark/results/phase2-resize-storm-2026-06-01.json` — `SB.7 Resize
  Storm` on Dart 3.12.1, 5 measured iterations, 500 resize events per
  iteration over a 100k-row DataTable plus a 5k-entry LogRegion, resize-frame
  p95 488 us, semantic-query p95 593 us, and no unsafe frames.

## SB.8 Overlay And Command Palette Churn

`SB.8` mounts a `FleuryApp` with an active screen command and a 1000-command
registry, then repeatedly presents `AppCommandPalette`, filters fuzzy results,
keyboard-selects the intended command when fuzzy matches are ambiguous, invokes
commands through Enter, semantic submit, and semantic activate, dismisses with
Escape and semantic dismiss, and probes a visible disabled command. Output
includes p50/p95/p99/max timing for open, filter, selection, action, settle,
full cycle, semantic query, disabled-command actions, command count, semantic
node counts, stale palette count, route-depth mismatches, selected-row
mismatches, unexpected invocations, ANSI bytes, and RSS delta.

Saved Phase 2 baselines:

- `benchmark/results/phase2-overlay-command-palette-2026-06-01.json` —
  first correctness baseline before lazy result rows and ranked command-id
  search. It preserved correctness but exposed the performance gap: filter p95
  98705 us and cycle p95 247544 us.
- `benchmark/results/phase2-overlay-command-palette-optimized-2026-06-01.json`
  — optimized `SB.8 Overlay And Command Palette Churn` on Dart 3.12.1, 20
  measured iterations over a 1000-command registry and 40 cycles per
  iteration, open p95 1615 us, filter p95 1121 us, selection p95 545 us,
  action p95 2316 us, settle p95 227 us, cycle p95 6429 us, semantic-query p95
  618 us, zero stale palette semantics, zero route-depth mismatches, and zero
  unexpected invocations.

## SB.9 Subprocess Handoff And Untrusted Output

`SB.9` runs real Dart subprocesses through `ProcessTaskController` and
`TerminalHandoffDriver` for a 1 MB colored-output success path, a stderr
non-zero exit, cancellation, and external editor handoff. It also streams
unsafe stdout/stderr-like lines through `TerminalOutputRegion` to measure frame
timing while asserting that OSC/DCS/APC/control payloads do not leak into
visible output, copied text, or semantic artifacts. Output includes
p50/p95/p99/max timing for process run, failure run, cancellation latency,
editor handoff, streaming frames, panel render, copy, semantic query, captured
output size, sanitizer counts, handoff counts, unsafe-frame count, and unsafe
artifact leak count.

Saved Phase 2 baseline:

- `benchmark/results/phase2-subprocess-output-2026-06-01.json` — `SB.9
  Subprocess Handoff And Untrusted Output` on Dart 3.12.1, 10 measured
  iterations over the default 100k-row scaled fixture, 1,000,000 target process
  bytes, 4288 captured output records, process-run p95 647254 us,
  cancellation-latency p95 11823 us, stream-frame p95 6230 us,
  process-panel-render p95 10649 us, semantic-query p95 1965 us, terminal
  handoff restored in every path, and zero unsafe visible/copy/semantic
  artifact leaks.

## SB.11 TreeTable Hierarchy Filter And Copy

`SB.11` mounts a 100k-leaf `TreeTable` hierarchy with branch rows, renders one
expanded branch, expands a second branch, pages and jumps through the visible
hierarchy, filters for a collapsed descendant, copies the selected filtered
row, and queries semantics. Output includes p50/p95/p99/max timing for fixture
build, search-index build, mount, first render, branch expansion, navigation,
filter query, selected-row copy, semantic query, ANSI bytes, visible ranges,
tree node count, cell-builder call counts, sanitizing fixture rows, copied byte
count, cooperative index task event/progress counts, and RSS delta.
The indexed search path covers exact-token and prefix-token lookup for durable
IDs, paths, and symbols; fuzzy contains/subsequence filtering remains a
separate scan-oriented mode.

Saved Phase 2 baseline:

- `benchmark/results/phase2-treetable-2026-06-01.json` — `SB.11 TreeTable
  Hierarchy Filter And Copy` on Dart 3.12.1, 20 measured iterations over
  100k leaves plus 100 branch nodes using `TreeTableSearchIndex`, index-build
  p95 1851310 us, filter-query p95 4074 us, expand-branch p95 16698 us,
  page-move p95 11640 us, selected-row copy p95 8002 us, semantic-query p95
  1979 us.
- `benchmark/results/phase2-treetable-index-2026-06-01.json` — index
  hardening baseline after reducing private per-row allocations and replacing
  regex tokenization with a scanner, 5 measured iterations over the same
  100k-leaf fixture, index-build p95 1040888 us, filter-query p95 8564 us,
  selected-row copy p95 13886 us, semantic-query p95 4767 us.
- `benchmark/results/phase2-treetable-cooperative-index-2026-06-01.json` —
  cooperative indexed `SB.11` on Dart 3.12.1, 5 measured iterations over the
  same 100k-leaf fixture, index-build p95 826676 us, filter-query p95 5706 us,
  semantic-query p95 1826 us, `indexProgressCurrent` 100100, and
  `searchIndexRowCount` 100100. The hierarchy index build now runs through
  `TaskController` with cooperative progress/yield checkpoints.
