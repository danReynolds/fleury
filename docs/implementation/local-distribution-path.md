# Local Distribution Path

## Purpose

Define the smallest credible way for a developer to try Fleury from this
workspace before public package/distribution polish begins.

This is an M1.12 execution artifact, not a public launch plan. It should make
the demo app, examples, and local CLI easy to run while keeping pub.dev,
Homebrew, npm wrappers, and app scaffolding deferred until the APIs stabilize.

## Current Local Path

Use the repo-local launcher from the workspace root:

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart list
dart tool/fleury_dev.dart demo
dart tool/fleury_dev.dart core-demo counter
dart tool/fleury_dev.dart widget-demo dashboard
dart tool/fleury_dev.dart cli diagnose --json
dart tool/fleury_dev.dart check --quick
```

The launcher does not require a root `pubspec.yaml`; it shells into the
package that owns each command.

After `dart tool/fleury_dev.dart activate-cli` or `build-cli`, the public
`fleury` CLI also exposes the repo launcher under the contributor namespace:

```sh
fleury dev check --quick
fleury dev demo
fleury dev core-demo counter
fleury benchmark list
fleury benchmark manifest --json
```

`fleury dev` searches upward from the current directory for a Fleury framework
checkout and then delegates to `tool/fleury_dev.dart`. It is intentionally
checkout-scoped; public app-developer commands stay at top level.

## Command Contract

| Command | Purpose | Notes |
| --- | --- | --- |
| `bootstrap` | Runs `dart pub get` in local packages. | Keeps the workspace ready without introducing a monorepo tool. |
| `list` | Shows runnable examples and demo-app names. | Use this before adding more demos. |
| `demo` | Runs `packages/fleury_example_console`. | This is the current-cycle pressure app, not a marketing demo. |
| `core-demo <name>` | Runs a `packages/fleury/example` entrypoint. | Starts with `counter`, `chat`, `showcase`, animation, selection, and hot reload demos. |
| `widget-demo <name>` | Runs a `packages/fleury_widgets/example` entrypoint. | Starts with dashboard, snapshot, and image demos. |
| `cli <args...>` | Runs `packages/fleury/bin/fleury.dart`. | Example: `cli diagnose --json`. |
| `check --quick` | Runs a fast local analyze/test pass. | Full `check` is available but may be slower. |
| `activate-cli` | Runs path activation for the local `fleury` CLI. | Intended for developer machines, not CI. |
| `build-cli` | Compiles `build/fleury` from the local CLI. | Proves the standalone binary route without shipping artifacts. |
| `fleury dev <command>` | Runs the same repo-local launcher through the installed CLI. | Requires a Fleury checkout; convenience alias for contributors. |

## Deferred Public Distribution Plan

| Track | Launch Direction | Deferred Until |
| --- | --- | --- |
| pub.dev packages | Publish `fleury`, `fleury_widgets`, and focused integration packages separately, with `fleury_acp` as fast-follow. | API freeze and release hygiene. |
| Standalone CLI binary | Build `fleury` with `dart compile exe` for release assets. | CLI surface stabilizes beyond diagnose/shell/serve. |
| Homebrew | Tap formula that installs the standalone CLI. | Binary release cadence exists. |
| npm wrapper | Thin package that downloads or invokes the standalone CLI for JS-heavy teams. | Real demand from CLI developers appears. |
| `create-fleury-app` | Scaffold a minimal app with tests and a first screen. | App-kernel APIs and example conventions stabilize. |
| Docs site | Public docs, tutorials, and comparisons. | Core examples, benchmark evidence, and package metadata are ready. |
| Dune/`dune_cli` | Later flagship evidence for real product pressure. | The example subpackage proves the core widgets and runtime first. |

## Acceptance Checklist

- [x] Workspace root documents how to bootstrap, run examples, run the demo
  app, and invoke the local CLI.
- [x] A repo-local launcher provides stable command names for local trying.
- [x] Local package checks include `fleury_git`, the first reusable
  non-example integration package proving app-extension package seams.
- [x] Demo app package documents its direct command and launcher command.
- [x] Local CLI activation and standalone binary paths are documented without
  requiring public release packaging.
- [~] Public distribution polish remains out of scope until launch APIs are
  credible.

## Notes

- Keep this path boring. The launcher should reduce command-memory overhead,
  not become a package manager.
- Do not introduce a root workspace format until package boundaries are stable
  enough to justify it.
- Future public docs can copy the successful commands from here once the
  example suite and release metadata are ready.
