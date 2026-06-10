# fleury_example_console scenario benchmarks

Scenario benchmarks in this package measure the integrated demo app. They are
separate from core and widget-package scenarios because the goal is to test the
app-shaped workflow that combines Fleury's app shell, commands, widgets,
semantics, diagnostics, process model, and debug capture.

```sh
dart run benchmark/scenario_benchmarks.dart --list
dart run benchmark/scenario_benchmarks.dart --filter=SB.10 --json
dart run benchmark/scenario_benchmarks.dart --filter=demo --save=benchmark/results/demo-app-journey.json
```

## SB.10 Demo-App Journey

`SB.10` starts the demo app, opens the command palette, navigates by command,
captures diagnostics, runs debounced global search, starts the fake task,
filters and copies a DataTable row, submits a transcript composer message,
appends and pauses log streaming, runs the native Dart-version process task to
success, captures a debug snapshot, and queries semantics plus accessibility
output. The Global Search path uses app-owned debounced result production plus
`SearchResultIndex` ranking before rendering through `SearchPanel`.

Output includes p50/p95/p99/max timing for the full journey, mount, first
render, command palette, debounced global search, table filter/copy, transcript
update, process run-to-success, diagnostics, debug capture, and semantic query
paths. It also records ANSI bytes, semantic/accessibility node counts,
debug-capture size, command/status counts, selected run identity, global search
result identity, indexed-log row/filter/progress identity, process output
count, diagnostic capability rows, unsafe visible frame count, and RSS delta.

Saved Phase 2 baselines:

- `benchmark/results/phase2-demo-app-journey-2026-06-01.json` — `SB.10
  Demo-App Journey` on Dart 3.12.1, 10 measured iterations, full journey p95
  101284 us, command-palette p95 13979 us, runs-filter p95 6906 us, runs-copy
  p95 3260 us, transcript p95 6952 us, process run-to-success p95 53184 us,
  diagnostics p95 3761 us, debug-capture p95 8400 us, semantic-query p95
  754 us, and zero unsafe frames.
- `benchmark/results/phase2-demo-app-global-search-2026-06-01.json` —
  refreshed `SB.10 Demo-App Journey` after adding the Global Search screen
  backed by `DebouncedTaskController` and `SearchPanel`, 10 measured
  iterations, full journey p95 227678 us, global-search p95 89844 us,
  command-palette p95 15848 us, runs-filter p95 5481 us, process
  run-to-success p95 71441 us, semantic-query p95 1328 us, one selected search
  result `run.RUN-1002`, and zero unsafe frames.
- `benchmark/results/phase2-demo-app-indexed-logs-2026-06-01.json` —
  refreshed `SB.10 Demo-App Journey` after adding the Indexed Logs screen
  backed by `TaskController`, `TaskYieldPolicy`, `LogRegionSearchIndex`, and
  `LogRegion`, 10 measured iterations, full journey p95 301300 us,
  global-search p95 86040 us, indexed-logs p95 63013 us, command-palette p95
  15504 us, process run-to-success p95 60119 us, semantic-query p95 1093 us,
  indexed log row count 195, filtered row count 49, progress current 195,
  selected key `IDX-1000`, and zero unsafe frames.
- `benchmark/results/phase2-demo-app-ranked-search-2026-06-01.json` —
  refreshed `SB.10 Demo-App Journey` after adding reusable
  `SearchResultIndex` ranking to `SearchPanel` and demo-app Global Search, 10
  measured iterations, full journey p95 296062 us, global-search p95 84221 us,
  indexed-logs p95 73452 us, command-palette p95 15076 us, process
  run-to-success p95 58716 us, semantic-query p95 993 us, selected search key
  `run.RUN-1002`, indexed log selected key `IDX-1000`, and zero unsafe frames.
