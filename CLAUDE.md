# Fleury — agent guide

Fleury is a Dart reactive TUI framework (Flutter-like) that renders to two
surfaces: the terminal and the browser (`fleury serve`). Core lives in
`packages/fleury/`; profiling/gates in `profiling/`; the dev tool orchestrates
everything.

## Build & validate

```sh
dart tool/fleury_dev.dart bootstrap   # pub get across packages
dart tool/fleury_dev.dart check       # analyze + test + dart2js smoke (what CI runs)
```

Run `dart tool/fleury_dev.dart --help` and `... benchmark --help` for the rest.

## Performance gates — run after perf-sensitive changes

Fleury's hot paths are covered by regression gates. **After a change that
touches a gated path, run that gate and confirm it passes before landing.** If
the change intends to move the number, re-baseline in the same PR with
`--update-baseline` (so the new number shows up in review) — do not loosen a
tolerance to clear red.

| Touched | Run |
| --- | --- |
| `lib/src/rendering/**`, `ansi_renderer.dart`, cell paint | `benchmark wire-gate` **and** `benchmark alloc-gate --gate` |
| `lib/src/widgets/framework.dart`, reconcile/build/layout, per-frame path | `benchmark alloc-gate --gate` |
| `lib/src/terminal/terminal_image_encoder.dart` | `benchmark image-bench --gate` |
| `lib/src/remote/**`, `lib/src/serve/**`, plan/semantics wire | `benchmark serve-wire-live` **and** `benchmark serve-semantics-gate` |
| `web/remote_client.dart` and its imports | `benchmark bundle-size --gate` |

All via `dart tool/fleury_dev.dart benchmark <gate> --gate`; each exits non-zero
on regression. Run the whole fast suite at once with
`dart tool/fleury_dev.dart benchmark gates` (~10s, pass/fail summary);
`benchmark --help` lists every gate. Full manifest — what each protects, speed,
baseline & SDK caveats:
**[docs/implementation/perf-gates.md](docs/implementation/perf-gates.md)**.
