<p align="center">
  <img src="assets/fleury-icon.png" alt="Fleury" width="120" height="120">
</p>

<h1 align="center">Fleury</h1>

<p align="center">
  A retained-mode UI framework for the terminal — and the browser.<br>
  One widget tree, two surfaces.
</p>

---

The standalone Fleury workspace is split into local Dart packages:

- `packages/fleury` - the core Flutter-shaped terminal UI framework.
- `packages/fleury_widgets` - higher-level widgets built on `fleury`.
- `packages/fleury_git` - small Git integration package proving app-extension
  package seams.
- `packages/fleury_web` - retained-DOM browser host, served client, and demo
  surface.
- `packages/fleury_example_console` - internal demo app for the current
  implementation cycle.
- `packages/storybook` - interactive widget storybook for browsing and
  exercising supported Fleury widgets.
- `docs/architecture.md`, `docs/core-and-targets.md`,
  `docs/serving-and-embedding.md` - how Fleury is layered (a platform-neutral
  core + pluggable targets) and the two ways to run it in a browser (serve vs.
  embed).
- `docs/rfcs` - design notes and implementation RFCs from the original work.
- `docs/implementation` - active milestone trackers, workstream notes, and the
  execution journal.
- `peer-fixtures` - comparison-only peer framework fixtures and run artifacts.

## Local Launcher

From the workspace root:

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart list
dart tool/fleury_dev.dart demo
dart tool/fleury_dev.dart storybook
dart tool/fleury_dev.dart storybook list
dart tool/fleury_dev.dart storybook verify
dart tool/fleury_dev.dart storybook coverage --strict
dart tool/fleury_dev.dart storybook run --story visualization.charts --theme dark --size 80x24
dart tool/fleury_dev.dart core-demo counter
dart tool/fleury_dev.dart widget-demo dashboard
dart tool/fleury_dev.dart cli diagnose --json
dart tool/fleury_dev.dart benchmark list
dart tool/fleury_dev.dart benchmark manifest --json
dart tool/fleury_dev.dart benchmark result --input=peer-run.json --json
dart tool/fleury_dev.dart check --quick
```

The launcher is intentionally small. It shells into the package that owns each
command, so the repo does not need a root `pubspec.yaml` yet.

Optional local CLI paths:

```sh
dart tool/fleury_dev.dart activate-cli
dart tool/fleury_dev.dart build-cli
```

After local activation, contributor commands can also be run through the
public CLI namespace:

```sh
fleury dev check --quick
fleury dev demo
fleury dev storybook
fleury dev storybook verify
fleury dev core-demo counter
fleury benchmark list
fleury benchmark wire sb6 --help
fleury benchmark manifest --json
```

`fleury dev` requires a Fleury framework checkout and delegates to
`tool/fleury_dev.dart`; public app-developer commands remain top-level
commands such as `fleury diagnose`, `fleury shell`, and `fleury serve`.
`fleury benchmark` is the canonical namespace for local scenario runners,
peer-wire comparisons, profiling, scoreboards, and manifest/result/variance
tools. Release and evidence commands such as terminal matrix capture and MVP
readiness remain available through `fleury dev --help`.

## Performance and Benchmarks

Fleury documents performance as an implementation model plus repeatable scenario
evidence. The public docs page is
[Performance](https://fleury.dev/architecture/performance/); the detailed
scenario matrix and runner commands live in [benchmarks/README.md](benchmarks/README.md).

The suite tracks the pressure points that usually matter for terminal apps:
startup and first paint, input latency, large data navigation, streaming logs
and Markdown, dashboard update cadence, layout invalidation, resize churn,
command-palette churn, process output, wire bytes, CPU, and RSS. Peer-wire
comparisons use source fixtures and repeated captures to answer regression,
fixture-shape, runtime-floor, and terminal-boundary cost questions. Results are
most useful when the fixture, terminal, machine, framework versions, and variance
are recorded beside the captures.

Quick entry points:

```sh
fleury benchmark list
fleury benchmark local SB.6 --warmup=1 --iterations=3 --json
fleury benchmark wire sb6 --runs=3
fleury benchmark manifest --json
```

## Validate

Run the packages independently:

```sh
cd packages/fleury
dart pub get
dart analyze
dart test -x integration

cd ../fleury_widgets
dart pub get
dart analyze
dart test

cd ../fleury_git
dart pub get
dart analyze
dart test

cd ../fleury_web
dart pub get
dart analyze
```

## Try The Core Demo

```sh
cd packages/fleury
dart run example/counter_quickstart.dart
```

Or from the workspace root:

```sh
dart tool/fleury_dev.dart core-demo counter
```
