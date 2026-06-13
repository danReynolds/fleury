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

To get the canvas/WebGL tiers, run against a real GPU Chrome with a temporary
`dart_test.yaml` next to `pubspec.yaml`:

```yaml
override_platforms:
  chrome:
    settings:
      headless: false
```

then `dart test -p chrome -t benchmark --timeout=600s benchmark/...` (a Chrome
window opens; every frame waits a real ~16.6 ms display refresh, so the run
takes ~75 s). Remove the file afterward — it must not be committed.

**Excluded:** GPU rasterization/compositing (not measurable from JS for either).

## Result A — headless Chrome (DOM tier only; clean, low-noise; medians)

rAF interval ≈ 8.3 ms; 60 fps budget 16.7 ms; WebGL backend: none (headless).

| workload | fleury apply+render | xterm DOM parse | xterm DOM parse→render |
| --- | --- | --- | --- |
| typing 80×24 | ≤0.10 ms (p95 0.10) | 1.2 ms | 8.1 ms |
| dashboard 80×24 | 0.20 ms (p95 0.30) | 1.2 ms | 7.8 ms |
| churn 120×40 | 0.20 ms (p95 0.30) | 0.7 ms | 7.2 ms |
| churn 200×60 | 0.30 ms (p95 0.40) | 1.2 ms | 5.5 ms |

## Result B — real GPU (Apple M1 Pro, ANGLE Metal; all three xterm tiers; medians)

Non-headless Chrome, 60 Hz (16.6 ms rAF), `xterm@5.5.0` + canvas 0.7.0 + webgl
0.18.0. **Synchronous main-thread cost** per frame (the `parse` step is what's
cleanly measurable; on a visible window the rAF-gated `render` is dominated by
the display refresh and very noisy, so it's omitted here):

| workload | fleury apply+render | xterm DOM | xterm canvas | xterm **WebGL** |
| --- | --- | --- | --- | --- |
| typing 80×24 | 0.30 ms | 1.3 ms | 1.4 ms | 1.1 ms |
| dashboard 80×24 | 0.50 ms | 1.8 ms | 1.4 ms | 0.9 ms |
| churn 120×40 | 0.70 ms | 2.8 ms | 9.4 ms | 0.8 ms |
| churn 200×60 | 0.70 ms | 2.8 ms | 6.5 ms | 0.8 ms |

**Reading it.** Two robust findings survive the noise (the visible-window run has
high p95 from compositor/GC jitter, so only medians are quoted):

1. **fleury's synchronous main-thread cost is the lowest at every size** (0.3–0.7
   ms) — under all three xterm tiers — because the structured protocol diffs on
   the server, so the client applies known patches instead of re-parsing an ANSI
   escape stream each frame.
2. **xterm's WebGL CPU stays flat as the grid grows** (~0.8 ms at 120×40 and
   200×60) where its DOM (→2.8 ms) and canvas (→9.4 ms) tiers climb — the GPU
   offload is real and is the flattest-scaling xterm tier. But it still does not
   pull ahead of fleury.

So even against GPU-accelerated WebGL on Apple Silicon, the DOM surface is
comparable-to-lower per-frame main-thread cost; WebGL's advantage is flat scaling
at large grids, not beating fleury. Both, and all xterm tiers, sit far under the
60 fps budget. `performance.now()` is clamped to ~0.1 ms, so sub-0.1 ms readings
are at the clock floor.
