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
```

Each benchmark prints `<name>: <microseconds per run()>` on stdout.
The harness runs each `run()` many times within a ~2-second
measurement window and reports the average.

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
