# Fleury

Standalone home for the Dart terminal UI framework incubated in
`dune_core` on `origin/claude/research-dune-cli-client-Ctoob`.

The standalone Fleury workspace is split into three Dart packages:

- `packages/fleury` - the core Flutter-shaped terminal UI framework.
- `packages/fleury_widgets` - higher-level widgets built on `fleury`.
- `packages/fleury_web` - browser/xterm.js driver and demo surface.
- `docs/rfcs` - design notes and implementation RFCs from the original work.

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

cd ../fleury_web
dart pub get
dart analyze
```

## Try The Core Demo

```sh
cd packages/fleury
dart run example/counter_quickstart.dart
```
