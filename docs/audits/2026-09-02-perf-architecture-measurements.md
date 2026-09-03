# Perf architecture measurements — 2026-09-02

Three questions the perf-architecture review could not answer from the
gates alone, measured on the shipped code (branch
`danreynolds/perf-arch-followups`, Apple Silicon, Dart 3.x). Every number
below is reproducible with the command under its table. None of these are
gates; they are the facts the follow-up decisions rest on.

## 1. The retained-tree tax (what a frame costs when little changed)

`dart run bin/retained_tax_probe.dart` (in `profiling/`) mounts each sample
app under the tester's production-shaped root and times four kinds of
frame, median of 40, at 120x40:

| app | render objects | repaint boundaries | idle paint | one leaf dirty | everything dirty | idle / full |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| dashboard | 143 | 0 | 458 µs | 499 µs | 488 µs | 0.94 |
| agent | 66 | 2 | 207 µs | 230 µs | 243 µs | 0.85 |
| files | 151 | 20 | 235 µs | 250 µs | 380 µs | 0.62 |
| editor | 41 | 0 | 178 µs | 176 µs | 180 µs | 0.99 |
| finance | 282 | 0 | 452 µs | 459 µs | 439 µs | 1.03 |

At 80x24 the same shape holds at roughly half the cost (dashboard 286 µs
idle vs 335 µs full; files 131 µs vs 275 µs).

What this says:

- **The tax is not the walk.** `paint_walk_probe` puts the walk at ~35 µs
  for 40 rows behind boundaries versus ~565 µs without them (16x). The
  walk over 150–280 objects is a rounding error.
- **The tax is that nothing is cached unless a `RepaintBoundary` is in the
  tree.** `BuildOwner.renderFrame` calls `rootRender.paint` unconditionally;
  only boundary subtrees replay from cache. Three of the five sample apps
  have zero boundaries, so any frame that renders repaints the whole
  viewport: ~0.45 ms at 120x40, ~0.29 ms at 80x24. The files app, whose
  list items are boundaries, paints a leaf change for 0.66 of a full paint.
- **A truly idle app pays nothing.** The frame driver's no-change skip
  means no frame is rendered when nothing requested one; the AOT counter
  app used 70 ms of CPU over 6 s of sitting still (all of it startup).
- **`markNeedsPaint` is conservative on purpose**: it also marks layout up
  the ancestor chain, so a leaf paint invalidation costs a short relayout
  walk (33 µs, 23 performed / 21 skipped on the dashboard). Paint-only
  changes go through `markNeedsPaintOnly`.

Verdict: per-frame cost is fine in absolute terms (half a millisecond at
120x40 against a 16 ms frame), and the wire never sees the redundant
repaints because damage is derived by buffer diff. The cost is CPU on apps
that animate continuously (spinners, live charts) with no boundaries. The
lever, if one is wanted later, is placing boundaries at natural seams
(panels, list rows, chart bodies) rather than any change to the walk.

## 2. Serve encode cost on the app isolate

`dart run bin/serve_wire_profile.dart` now times plan build + encode per
frame next to the byte columns:

| scenario | plan build+encode p50 | p95 | max |
| --- | ---: | ---: | ---: |
| counter (1 field) | 0.04 ms | 0.13 ms | 7.17 ms (first-frame JIT) |
| typing (1 row) | 0.10 ms | 0.14 ms | 0.53 ms |
| log tail (scroll) | 0.17 ms | 0.30 ms | 0.65 ms |
| dashboard (10 rows) | 0.11 ms | 0.15 ms | 0.20 ms |
| big churn 200x60 | 0.93 ms | 1.51 ms | 3.56 ms |

Against the end-to-end serve-wire-live input→paint p50 1.5 ms / p95 1.8 ms,
encoding is a tenth of the pipeline on realistic frames and under 2 ms at
p95 even when every cell of a 200x60 surface changes.

Verdict: no worker isolate. The threshold that would justify one (encode
p95 above ~8 ms, where it would steal half a frame from the app) is five
times away on the worst synthetic case.

## 3. Time to first paint

`FLEURY_RUNTIME_MARKERS=<file>` stamps the runtime's startup; `capture_pty`
(`--answer-probes` for a terminal that answers every capability query at
once, without it for one that never answers) gives the process view.
Counter example app:

| build | terminal | spawn → runApp entry | terminal enter | mount + first render | spawn → first frame bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| AOT (`dart compile exe`) | answers probes | 77 ms | 14 ms | 0.3 ms | ~95 ms |
| AOT | silent (never answers) | 77 ms | 502 ms | 0.4 ms | 579 ms |
| `dart run` (dev, hot-reload supervisor) | answers probes | 4010 ms | 27 ms | 36 ms | 4108 ms |
| `dart run` | silent | ~4000 ms | 510 ms | 55 ms | ~4600 ms |

What this says:

- **The framework's own startup floor is ~15 ms** (AOT, cooperative
  terminal): mount and first render are sub-millisecond; the rest is the
  probe conversation. The 77 ms before `runApp` is Dart VM boot, not
  Fleury.
- **The probe conversation is sequential.** The driver sends five stages
  (kitty push+query+DA1, kitty second stage, synchronized-output DECRQM +
  image query, eleven width-probe glyphs), each waiting for the DA1
  sentinel before the next. Locally each round trip is ~1–3 ms; over a
  50 ms SSH link that is ~250 ms where a pipelined query batch would be
  ~50 ms. Pipelining the stages is the one startup improvement with a
  real user-visible payoff.
- **A silent terminal costs the 500 ms probe budget** (first probe 400 ms,
  adaptive after). That is the designed ceiling and it held.
- **In `dart run` dev mode, 98% of the wait is JIT**: ~2.7 s for the
  supervisor, ~1.3 s for the child it respawns with the VM service. The
  runtime's share is ~100 ms (JIT-cold framework code); the stdio
  fd-capture start is ~12 ms of it. Nothing in the framework moves that
  needle; `dart compile exe` does.

### Follow-up: `fleury run`, measured

The double compile above is structural: the transparent `dart run` start can
only decide to supervise from inside `runApp`, after compiling the whole app,
and then compiles it again in the child that gets the VM service. `fleury run
<script>` is a launcher that supervises the same child without ever compiling
the app. `dart run bin/dev_startup_profile.dart` (cooperative PTY, medians of
3, counter example):

| start | spawn → VM banner | spawn → runApp entry | spawn → first frame |
| --- | ---: | ---: | ---: |
| `dart run app.dart` (transparent supervisor) | 2131 ms | 3518 ms | 3620 ms |
| `dart run --enable-vm-service=0 app.dart` (one compile, no supervisor) | 569 ms | 1949 ms | 2037 ms |
| `dart run fleury run app.dart` (launcher from pub's cached snapshot; `fleury run` after a global activate is the same path) | 796 ms | 2125 ms | 2219 ms |
| `dart run bin/fleury.dart run app.dart` (launcher compiled from source) | 2050 ms | 3365 ms | 3463 ms |

The launcher lands within ~180 ms of the one-compile floor; that remainder is
`dart run` resolving the package plus the launcher's own start. The last row
is the design constraint made visible: a launcher that has to compile itself
saves nothing, so it must start from a snapshot — which `dart run
<package>:<executable>` and `dart pub global activate` both provide.

Reproduce:

```sh
cd profiling
dart run bin/retained_tax_probe.dart            # add --cols 80 --rows 24
dart run bin/paint_walk_probe.dart
dart run bin/serve_wire_profile.dart
dart compile exe ../packages/fleury/example/counter_quickstart.dart -o /tmp/counter
dart run capture_pty.dart --answer-probes --out /tmp/cap --timeout 3 -- \
  /bin/sh -c 'FLEURY_RUNTIME_MARKERS=/tmp/marks.json exec /tmp/counter'
dart run bin/dev_startup_profile.dart --cwd ../packages/fleury -- \
  dart run fleury run example/counter_quickstart.dart
```
