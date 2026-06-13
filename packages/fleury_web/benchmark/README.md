# fleury DomGridSurface vs xterm.js — render benchmark

Head-to-head per-frame **render cost** in headless Chrome: fleury's retained
`DomGridSurface` (the surface the serve client renders through) versus xterm.js,
fed the **same frame stream**. fleury renders from a presentation plan; xterm
renders from the equivalent ANSI produced by fleury's own `AnsiRenderer` (the
exact bytes an ANSI-relay peer would send to xterm). This is the one axis the
wire/CPU profilers don't cover: what it costs the browser to turn a received
frame into rendered output.

## Run it

```sh
cd packages/fleury_web
./benchmark/fetch_xterm.sh            # vendors xterm.js into ./benchmark/vendor (gitignored)
dart test -p chrome -t benchmark benchmark/xterm_vs_fleury_bench_test.dart -r expanded
```

The benchmark lives outside `test/`, so a normal `dart test` never runs it; it
must be invoked by path. xterm.js is **not committed** (fleury removed xterm
from its own stack) — `fetch_xterm.sh` pins and vendors it on demand.

## What it measures

Per-frame main-thread cost — the budget that decides whether a renderer drops
frames at 60 fps (16.7 ms/frame):

- **fleury apply+render** — `applyRemotePlan` (apply the wire patches) + `present`
  (DOM build) + a forced `getBoundingClientRect` (commit layout), all
  synchronous. fleury has no deferred render, so this is its full per-frame cost.
- **xterm parse** — the synchronous `write()` → buffer parse.
- **xterm parse→render** — wall time `write()` → `onRender`; xterm renders on its
  own `requestAnimationFrame`, so this includes ~one frame of scheduling latency
  on top of the (sub-frame) render compute.

**Excluded:** GPU rasterization/compositing (not measurable from JS for either).
xterm runs its **default DOM renderer** (no canvas/WebGL addon — that addon would
change raw-glyph throughput on very large grids but is not the default and is
typically unavailable headless).

## Representative result (headless Chrome, M-series; medians)

rAF interval ≈ 8.3 ms; 60 fps budget 16.7 ms.

| workload | fleury apply+render | xterm parse | xterm parse→render |
| --- | --- | --- | --- |
| typing 80×24 | ≤0.10 ms (p95 0.10) | 0.90 ms | 8.1 ms (p95 10.3) |
| dashboard 80×24 | 0.30 ms (p95 0.40) | 1.00 ms | 7.9 ms (p95 9.8) |
| big churn 120×40 | 0.20 ms (p95 0.30) | 1.00 ms | 7.0 ms (p95 8.8) |

**Reading it.** fleury's full client decode+render+layout is **≤0.4 ms p95** —
under xterm's ANSI parse alone (~1 ms), because the structured protocol diffs on
the server so the client applies known patches instead of re-parsing an escape
stream each frame. Both are far under the 60 fps budget, so neither is CPU-bound
on terminal workloads; the bottleneck is the display refresh. fleury also renders
synchronously (DOM ready in ≤0.4 ms) where xterm defers to its rAF, so fleury has
lower frame-ready latency. The place xterm could pull ahead — its optional WebGL
renderer on very large / high-throughput grids — is not the default and is not
measured here. `performance.now()` is clamped to ~0.1 ms, so sub-0.1 ms fleury
readings are at the clock floor.
