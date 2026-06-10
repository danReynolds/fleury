# fleury benchmarks

Microbenchmarks driven by `package:benchmark_harness`. Run the whole
suite:

```sh
dart pub get
dart run benchmark/all.dart
```

Or run any sub-suite individually:

```sh
dart run benchmark/render_benchmarks.dart
dart run benchmark/paint_benchmarks.dart
dart run benchmark/build_benchmarks.dart
dart run benchmark/parser_benchmarks.dart
dart run benchmark/focus_traversal_benchmarks.dart
```

Each benchmark prints `<name>: <microseconds per run()>` on stdout.
The harness runs each `run()` many times within a ~2-second
measurement window and reports the average.

## Scenario Benchmarks

Scenario benchmarks measure app-shaped journeys and emit JSON records. They are
separate from the microbenchmarks above:

```sh
dart run benchmark/scenario_benchmarks.dart --list
dart run benchmark/scenario_benchmarks.dart --filter=SB.1 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.2 --text-chars=10000 --json
dart run benchmark/scenario_benchmarks.dart --filter=SB.12 --json
dart run benchmark/scenario_benchmarks.dart --filter=counter --save=benchmark/results/scenarios.json
```

Core scenarios:

- `SB.1 Time To Counter App` mounts a small `FleuryApp`, renders the first
  frame, invokes a command, renders the updated frame, and queries semantics.
- `SB.2 Text Editing Composer Stress` mounts a composer, longform editor, and
  secret field, then drives cursor movement, selection replacement, undo/redo,
  history, completion acceptance, chunked paste, redaction, and semantic
  queries over a mixed-width text fixture. Use `--text-chars=N` to adjust the
  editor fixture size.
- `SB.12 Layout Dirtiness Cache` mounts a static pane beside a changing counter
  pane, then records performed/skipped layout counts for first, update,
  paint-only style, paint-only text, child-list no-op, and idle frames. It also
  measures viewport paint culling over a 2,000-row `ScrollView` child, proving
  scroll paints visit visible non-selectable rows rather than every offscreen
  row.

Output includes p50/p95/p99/max timing for the journey and each
scenario-specific action path.

Widget scenarios that depend on `fleury_widgets` live in that package to avoid
making core `fleury` depend on its higher-level widget catalog:

```sh
cd ../fleury_widgets
dart run benchmark/scenario_benchmarks.dart --list
dart run benchmark/scenario_benchmarks.dart --filter=SB.3 --json
```

The integrated demo-app scenario lives in `fleury_example_console` because it
measures the app-shaped package rather than a reusable core or widget fixture:

```sh
cd ../fleury_example_console
dart run benchmark/scenario_benchmarks.dart --list
dart run benchmark/scenario_benchmarks.dart --filter=SB.10 --json
```

The cross-framework comparison contract is tracked from the workspace root:

```sh
dart tool/fleury_dev.dart benchmark-manifest
dart tool/fleury_dev.dart benchmark-manifest --json
dart tool/fleury_dev.dart benchmark-result --input=peer-run.json --output=manifest-with-peer.json
dart tool/fleury_dev.dart benchmark-variance --input=peer-run-directory --json
```

That manifest defines peer-equivalent scenario contracts and required metrics.
It does not contain peer results until matching peer fixtures have been built
and run. Peer results should be added through `benchmark-result`, which
validates the peer, scenario, required metrics, and claim gates before writing a
manifest copy with `peerRuns` populated.

Use `benchmark-variance` once a peer fixture has multiple comparable saved run
artifacts for the same peer, scenario, source version, terminal mode, terminal
size, fixture directory, and fixture command. It reports per-metric spread over
the artifact primary value, usually `p95`, and exposes `strictPass` for local
evidence readiness. It is still not a substitute for real-terminal or
cross-machine evidence.

Candidate thresholds in scenario JSON are informational until stable baselines
exist. Use them to spot regressions, not as hard CI gates yet.

Saved Phase 1 baseline:

- `benchmark/results/phase1-core-2026-05-31.json` — `SB.1 Time To Counter App`
  on Dart 3.12.1, 20 measured iterations, command-to-frame p95 254 us,
  first-frame p95 61 us, semantic-query p95 102 us.
- `benchmark/results/phase2-text-editing-2026-06-01.json` — `SB.2 Text Editing
  Composer Stress` on Dart 3.12.1, 10 measured iterations, 10k requested text
  chars, cursor-move p95 798 us, insertion/deletion p95 641 us, selection p95
  2191 us, paste-complete p95 18573 us, semantic-query p95 508 us.
- `benchmark/results/phase2-layout-dirtiness-2026-06-01.json` — `SB.12 Layout
  Dirtiness Cache` on Dart 3.12.1, 20 measured iterations, command-to-frame p95
  11799 us, idle-frame p95 692 us, paint-only-frame p95 1210 us,
  text-paint-only-frame p95 3251 us, update-frame layout p95 7 performed /
  3 skipped, paint-only-frame layout p95 0 performed / 1 skipped,
  text-paint-only-frame layout p95 0 performed / 1 skipped, and idle-frame
  layout p95 0 performed / 1 skipped.
- `benchmark/results/phase2-layout-dirtiness-child-list-2026-06-02.json` —
  refreshed `SB.12 Layout Dirtiness Cache` after child-list replacement
  hardening, 20 measured iterations, command-to-frame p95 3559 us,
  child-list no-op frame p95 4363 us, child-list no-op layout p95 0 performed /
  1 skipped, and the existing paint-only/text-paint-only/idle frames still at
  p95 0 performed / 1 skipped.
- `benchmark/results/phase2-layout-dirtiness-viewport-paint-2026-06-02.json` —
  refreshed `SB.12 Layout Dirtiness Cache` after viewport paint hardening,
  20 measured iterations, command-to-frame p95 7014 us, viewport-first-frame p95
  4773 us, viewport-scroll-frame p95 1245 us, viewport painted rows p95 24 on a
  24-row viewport over a 2,000-row child, and paint-only/text-paint-only/
  child-list/idle layout p95 0 performed / 1 skipped.

## Categories

- **render** — `AnsiRenderer.renderDiff` cost for no-change /
  single-cell / single-row / full-repaint cases at 80×24 and
  200×60. Drives H4 (cursor-move coalescing) and H5 (delta SGR)
  decisions.
- **paint** — `BuildOwner.renderFrame` end-to-end for single Text,
  dense Text column, typical chat layout. Drives H1 (packed Cell)
  and H2 (layout caching) decisions.
- **build** — `flushBuild` at varying dirty-element counts, plus
  `reassembleApplication`. Drives H6 (sort-once flush) decisions.
- **parser** — `InputParser.feed` throughput for ASCII / CSI / UTF-8
  / mixed input. Drives whether the parser is a bottleneck at all.
- **focus traversal** — directional focus target selection over mounted focus
  grids at reasonable and large candidate counts. Drives whether the default
  tree-aware spatial policy needs indexing beyond a linear scan.

## Capturing baselines

Run the full suite, save the output, and add a row to
`baseline_results.md` with the date, Dart SDK version, machine
description, and the per-benchmark microseconds. Compare against
previous rows when shipping a perf-impacting change.

```sh
dart run benchmark/all.dart 2>&1 | tee baseline_results_$(date +%Y%m%d).txt
```

## Adding a new benchmark

1. Extend `BenchmarkBase` from `package:benchmark_harness`.
2. Implement `setup()` (one-time, not measured) and `run()`
   (called many times, measured).
3. Add `MyBenchmark().report();` to the appropriate `main()` in
   the matching sub-suite file.
4. If the benchmark's `run()` is meaningfully short (sub-microsecond),
   the harness's reported number gets noisy; bundle multiple
   operations per `run()` to push it above ~10us.
