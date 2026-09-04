# fleury_example_console scenario benchmarks

Scenario benchmarks in this package measure the integrated demo app. They are
separate from core and widget-package scenarios because the goal is to test the
app-shaped workflow that combines Fleury's app shell, commands, widgets,
semantics, diagnostics, and debug capture.

```sh
dart run benchmark/scenario_benchmarks.dart --list
dart run benchmark/scenario_benchmarks.dart --filter=SB.10 --json
dart run benchmark/scenario_benchmarks.dart --filter=demo --save=benchmark/results/demo-app-journey.json
```

## SB.10 Demo-App Journey

`SB.10` starts the demo app, opens the command palette, navigates by command,
captures diagnostics, runs debounced global search, starts the fake worker,
builds and refreshes the retained-log search index,
filters and copies a DataTable row, submits a transcript composer message,
appends and pauses log streaming, captures a debug snapshot, and queries
semantics plus accessibility output. The Global Search path uses app-owned
timer-based debouncing plus
`SearchResultIndex` ranking before rendering through `SearchPanel`.

Output includes p50/p95/p99/max timing for the full journey, mount, first
render, command palette, debounced global search, table filter/copy, transcript
update, worker command, diagnostics, debug capture, and semantic query paths. It
also records ANSI bytes, semantic/accessibility node counts, debug-capture size,
command/status counts, selected run identity, global search result identity,
indexed-log row/filter identity, diagnostic capability rows, unsafe visible
frame count, and RSS delta.

The saved Phase 2 result files predate the simplified journey and are retained
only as historical measurements. Generate a fresh result before comparing the
current command, search, and indexed-log paths.
