# Fleury Example Console

Internal proof app for Fleury's Phase 1 reactive TUI foundations.

Run it from the workspace root:

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart proof
```

Or run it directly from this package:

```sh
dart pub get
dart run bin/fleury_example_console.dart
```

This app is the current-cycle pressure harness for app shell, commands,
screens, DataTable, indexed logs, diagnostics, text input, task state,
semantic snapshots, debug capture, and sanitized output. Dune/`dune_cli`
remains the later flagship after the core has been proven here.
