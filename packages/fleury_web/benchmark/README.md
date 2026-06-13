# fleury DomGridSurface vs xterm.js — render benchmark

Head-to-head per-frame **render cost**: fleury's retained `DomGridSurface` (the
surface the serve client renders through) versus xterm.js across **all three of
its renderer tiers** — DOM (default), canvas addon, WebGL addon — fed the **same
frame stream**. fleury renders from a presentation plan; xterm renders from the
equivalent ANSI produced by fleury's own `AnsiRenderer` (the exact bytes an
ANSI-relay peer would send to xterm). This is the one axis the wire/CPU
profilers don't cover: what it costs the browser to turn a received frame into
rendered output.

**Why three xterm tiers, and why not "more peers":** ttyd, gotty, textual-web,
and VS Code's web terminal all render through xterm.js (or hterm), so for
*render* cost the meaningful axis is xterm's renderer tier, not the product.
xterm's *parse* (write→buffer) is renderer-independent — the same core ANSI
parser for all three — so the tier only changes the deferred render. The WebGL
tier is the one that could beat a DOM surface. Native terminals (Alacritty,
Kitty, iTerm) are GPU desktop apps, not web, so they're out of scope for the
serve path.

## Run it

```sh
cd packages/fleury_web
./benchmark/fetch_xterm.sh            # vendors xterm.js + canvas/webgl addons into ./benchmark/vendor (gitignored)
dart test -p chrome -t benchmark benchmark/xterm_vs_fleury_bench_test.dart -r expanded
```

The benchmark lives outside `test/`, so a normal `dart test` never runs it; it
must be invoked by path. xterm.js and its addons are **not committed** (fleury
removed xterm from its own stack) — `fetch_xterm.sh` pins and vendors them on
demand.

## What it measures

Per-frame main-thread cost — the budget that decides whether a renderer drops
frames at 60 fps (16.7 ms/frame):

- **fleury apply+render** — `applyRemotePlan` (apply the wire patches) + `present`
  (DOM build) + a forced `getBoundingClientRect` (commit layout), all
  synchronous. fleury has no deferred render, so this is its full per-frame cost.
- **xterm parse** — the synchronous `write()` → buffer parse. Renderer-independent.
- **xterm parse→render** — wall time `write()` → `onRender`; xterm renders on its
  own `requestAnimationFrame`, so this includes ~one frame of scheduling latency
  on top of the (sub-frame) render compute.

The harness probes the WebGL backend and runs whichever xterm tiers the browser
supports. **In headless Chrome (`dart test`) there is no GL context**, and
xterm's canvas and WebGL renderers fail to initialize, so only the DOM tier is
measured there; the canvas/WebGL rows report `unavailable — needs a GPU browser`
and run automatically on a GPU-backed (non-headless) Chrome.

**Excluded:** GPU rasterization/compositing (not measurable from JS for either).

## Representative result (headless Chrome, M-series; medians)

rAF interval ≈ 8.3 ms; 60 fps budget 16.7 ms; WebGL backend: none (headless).

| workload | fleury apply+render | xterm DOM parse | xterm DOM parse→render | xterm canvas / WebGL |
| --- | --- | --- | --- | --- |
| typing 80×24 | ≤0.10 ms (p95 0.10) | 1.2 ms | 8.1 ms | needs GPU browser |
| dashboard 80×24 | 0.20 ms (p95 0.30) | 1.2 ms | 7.8 ms | needs GPU browser |
| churn 120×40 | 0.20 ms (p95 0.30) | 0.7 ms | 7.2 ms | needs GPU browser |
| churn 200×60 | 0.30 ms (p95 0.40) | 1.2 ms | 5.5 ms | needs GPU browser |

**Reading it.** fleury's full client decode+render+layout is **≤0.4 ms p95 even
at 200×60 (12 000 cells)** — under xterm's ANSI parse alone (~1 ms), because the
structured protocol diffs on the server so the client applies known patches
instead of re-parsing an escape stream each frame. Both are far under the 60 fps
budget, so neither is CPU-bound on terminal workloads; the bottleneck is the
display refresh. fleury also renders synchronously (DOM ready in ≤0.4 ms) where
xterm defers to its rAF, so fleury has lower frame-ready latency. Note xterm's
parse is renderer-independent, so its DOM/canvas/WebGL tiers share that ~1 ms;
the tier only changes the deferred render. The one regime where xterm's WebGL
renderer could pull ahead — very large / high-throughput grids — needs a
GPU-backed browser run, which this headless harness reports as unavailable rather
than faking. `performance.now()` is clamped to ~0.1 ms, so sub-0.1 ms fleury
readings are at the clock floor.
