# Fleury

Flutter-shaped terminal UI for Dart.

The standalone Fleury workspace is split into local Dart packages:

- `packages/fleury` - the core Flutter-shaped terminal UI framework.
- `packages/fleury_widgets` - higher-level widgets built on `fleury`.
- `packages/fleury_git` - small Git integration package proving app-extension
  package seams.
- `packages/fleury_web` - browser/xterm.js driver and demo surface.
- `packages/fleury_example_console` - internal proof app for the current
  implementation cycle.
- `docs/rfcs` - design notes and implementation RFCs from the original work.
- `docs/implementation` - active milestone trackers, workstream notes, and the
  execution journal.
- `peer-fixtures` - comparison-only peer framework fixtures and run artifacts.

## Local Launcher

From the workspace root:

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart list
dart tool/fleury_dev.dart proof
dart tool/fleury_dev.dart core-demo counter
dart tool/fleury_dev.dart widget-demo dashboard
dart tool/fleury_dev.dart cli diagnose --json
dart tool/fleury_dev.dart terminal-matrix --label=local-terminal
dart tool/fleury_dev.dart benchmark-manifest --json
dart tool/fleury_dev.dart benchmark-result --input=peer-run.json --json
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
fleury dev proof
fleury dev core-demo counter
fleury dev mvp-readiness
```

`fleury dev` requires a Fleury framework checkout and delegates to
`tool/fleury_dev.dart`; public app-developer commands remain top-level
commands such as `fleury diagnose`, `fleury shell`, and `fleury serve`.

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
