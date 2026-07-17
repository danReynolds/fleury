<p align="center">
  <img src="assets/fleury-icon.png" alt="Fleury" width="120" height="120">
</p>

<h1 align="center">Fleury</h1>

<p align="center">
  A retained-mode UI framework for the terminal — and the browser.<br>
  One widget tree, two surfaces.
</p>

---

Fleury brings Dart's Flutter-shaped widget model to cell-based interfaces:
compose widgets, keep state with `StatefulWidget`, rebuild with `setState`, and
let the framework diff the resulting cell grid. The same widget tree can run in
a native terminal or mount into a browser.

It also keeps a semantic graph alongside the visual tree, so tests and agents
can inspect and invoke stable application actions instead of relying on terminal
coordinates. The browser host mirrors that graph into a semantic DOM; native
terminal assistive-technology adapters remain future work.

**Start here:** [Getting started](https://fleury.dev/getting-started/) ·
[Widget catalog](https://fleury.dev/widgets/) ·
[Navigation and commands](https://fleury.dev/guides/navigation/) ·
[Architecture](https://fleury.dev/architecture/core-and-targets/) ·
[Performance](https://fleury.dev/architecture/performance/)

## Try it from this checkout

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart widget-demo app-shell
```

The app-shell demo is the shortest tour of a real multi-screen Fleury app:
route-local commands, keyboard shortcuts, a registry-backed command palette,
buttons, and semantic actions all invoke the same application operations.

At its smallest, an app is just a widget tree handed to `runApp`:

```dart
import 'package:fleury/fleury.dart';

void main() => runApp(
  const FleuryApp(
    title: 'My app',
    home: Center(child: Text('Hello, cells!')),
  ),
);
```

The [getting-started guide](https://fleury.dev/getting-started/) covers Git
dependencies, state, higher-level widgets, and running the same tree in a
browser.

## Repository development

The workspace is split into local Dart packages:

- `packages/fleury` — the platform-neutral retained core, app shell, native
  terminal host, and theme-free primitives.
- `packages/fleury_test` — deterministic widget tests, semantic assertions,
  and golden helpers, kept out of application dependency graphs.
- `packages/fleury_widgets` — higher-level, theme-driven widgets built on
  `fleury`.
- `packages/fleury_git` — a small Git integration package proving app-extension
  package seams.
- `packages/fleury_web` — the retained-DOM browser host, served client, and demo
  surface.
- `packages/fleury_example_console` — the internal integration demo app.
- `packages/storybook` — an interactive catalog for supported widgets.
- `docs/architecture.md`, `docs/core-and-targets.md`, and
  `docs/serving-and-embedding.md` — the core/host layering and browser paths.
- `docs/rfcs` and `docs/implementation` — design records and milestone notes.
- `peer-fixtures` — comparison-only peer framework fixtures and run artifacts.

The root launcher delegates to the package that owns each command, so the
workspace does not need a root `pubspec.yaml`:

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart check --quick
dart tool/fleury_dev.dart widget-demo app-shell
dart tool/fleury_dev.dart storybook
dart tool/fleury_dev.dart --help
```

Optional local CLI paths:

```sh
dart tool/fleury_dev.dart activate-cli
dart tool/fleury_dev.dart build-cli
```

After local activation, contributor commands are also available under
`fleury dev`; app-developer commands such as `fleury diagnose`, `fleury shell`,
and `fleury serve` remain top-level. Run `fleury dev --help` and
`fleury benchmark --help` for the full command surfaces.

## Performance and benchmarks

Fleury documents performance as an implementation model plus repeatable
scenario evidence. Read the public
[performance guide](https://fleury.dev/architecture/performance/) and the
detailed [benchmark matrix](benchmarks/README.md).

The suite covers startup and first paint, input latency, large-data navigation,
streaming logs and Markdown, dashboard cadence, layout invalidation, resize and
overlay churn, process output, wire bytes, CPU, and RSS. Peer-wire comparisons
record fixture shape, runtime floors, framework versions, machine context, and
variance alongside results.

```sh
fleury benchmark list
fleury benchmark local SB.6 --warmup=1 --iterations=3 --json
fleury benchmark wire sb6 --runs=3
fleury benchmark manifest --json
```

## Validate

For the normal local gate:

```sh
dart tool/fleury_dev.dart check --quick
```

Each package can also be checked independently with `dart analyze` and
`dart test` from its directory. Run `dart tool/fleury_dev.dart --help` for the
broader release, docs, terminal-matrix, and benchmark evidence commands.
