# Performance Architecture Recommendations

Status: 2026-06-08, updated after the DataTable cache revert, analyzer
classification, ANSI style deltas, gap-fill cursor cleanup, expanded
cursor-move encoder, SB.1 runtime-floor wire coverage, SB.7/SB.11 wire
coverage, SB.6 dirty-span diagnostics, local SB.6/SB.12 RSS phase profiling,
and SB.6/SB.12 VM
CPU/allocation profiling. Both a style-aware same-row gap model and a
buffer-level dirty-row/span handoff were tested and reverted: the gap model was
neutral on real wire scenarios, and the span handoff added local frame cost
without improving the peer-facing CPU axis.

## Executive Read

The current architecture does not need a broad rewrite. Fleury is already
competitive or leading on the implemented wire-output scenarios, and local
Fleury-only benchmarks show layout caching and list virtualization are working.
The best performance work is narrower:

1. stop broad cursor/gap encoder work for now: the measured style-aware gap
   pass did not materially improve SB.6 or SB.9;
2. do not add a public dirty-row/span buffer API yet: the measured probe made
   local SB.6 slower and did not move SB.6/SB.12 peer CPU;
3. treat peer RSS/TTFB as runtime-floor-confounded unless marker data says
   otherwise;
4. keep SB.6 improvement work private to the renderer/output path: VM profiling
   exposed an over-broad scroll-up detector and a redundant full-screen scan;
   both were fixed without adding public buffer metadata;
5. treat SB.12 as healthy on dirtiness caching. Phase-specific profiling isolated
   the remaining cost to constructing the 2,000-child viewport fixture, and a
   private `RenderFlex` mount fast path brought the local viewport path back into
   the low-millisecond/sub-millisecond band.

## Evidence

Fresh peer scorecard, using the regenerated aggregate scoreboard at
`profiling/caps/scoreboard.md`:

- P0/P1 mostly lands in `push leading`: Fleury is leading or competitive on
  bytes, bytes/frame, CPU, and FPS. Control overhead remains the weak axis.
- SB.6 dashboard is leading/near-leading on bytes and FPS, but still spends
  roughly 24-25 KiB per capture on cursor movement and uses more CPU/RSS than
  Ratatui. Local CPU is healthy after the renderer fixes; the remaining
  peer-facing opportunity is cursor/control byte shape.
- SB.12 layout dirtiness is healthy: Fleury leads on bytes and overhead in the
  fresh run, and the phase split shows the retained layout/paint invalidation
  thesis is holding there.
- SB.9 subprocess output is competitive on total bytes/FPS, but Bubble Tea is
  still much tighter on cursor/control overhead.
- SB.11 TreeTable/filter/copy now has Textual/Ratatui/OpenTUI wire coverage.
  Fleury is byte-ballpark at 10.8 KiB median, but lands in `catch up` on the
  scorecard. The latest marker and fixture audit shows this is not a render
  hot path: Fleury's fixture builds the real retained 100k-node `TreeTable`
  plus search index, while the peer fixtures compute visible rows from row IDs.
  Treat SB.11 RSS/CPU as data/index attribution until fixture parity improves
  or Fleury gets a lazy TreeTable data source.
- SB.7 Resize storm now has Textual/Ratatui/OpenTUI wire coverage with dynamic
  PTY resize events. Fleury leads bytes, bytes/frame, overhead, and FPS in the
  aggregate scorecard, but remains `catch up` because Ratatui is much lower on
  RSS/CPU and raw TTFB.

Local Fleury-only checks:

- `fleury benchmark local SB.6 --warmup=1 --iterations=3 --json`
  reported update total p95 around 0.45 ms, update frame p95 around 0.21 ms,
  and update layout skip ratio around 67% after reverting the row-span handoff.
- `fleury benchmark local SB.6 --warmup=1 --iterations=3 --profile-memory --json --save=profiling/caps/2026-06-08-local-memory-sb6.json`
  reported update-total p95 312 us, update-frame p95 160 us, semantic-query p95
  221 us, and no sustained retained-RSS growth during the update loop. The update
  RSS step-delta median and p95 were both 0 B.
- `fleury benchmark profile SB.6 --warmup=1 --iterations=5 --save=profiling/caps/2026-06-08-vm-profile-sb6.json`
  identified `_detectBeneficialScrollUp` as the top project CPU function
  (1413 exclusive ticks, 3377 inclusive ticks). After gating scroll detection to
  plausible non-empty row-shift candidates,
  `profiling/caps/2026-06-08-vm-profile-sb6-scroll-gate-content.json` no longer
  has that function in the top project CPU list; the remaining top rows are
  ordinary diff/write work (`appendCell`, bounds checks, and `_screenDiffStats`).
- `fleury benchmark local SB.6 --warmup=2 --iterations=10 --json --save=profiling/caps/2026-06-08-local-sb6-scroll-gate-content-10x.json`
  reported update-total p95 498 us, update-frame p95 288 us, update pump p95
  243 us, and the same 67% update-layout skip ratio. This keeps SB.6 in the
  sub-millisecond local update band after the private scroll-detector fix.
- `fleury benchmark profile SB.6 --warmup=1 --iterations=5 --save=profiling/caps/2026-06-08-vm-profile-sb6-single-scan.json`
  kept `_detectBeneficialScrollUp` out of the top rows and reduced
  `_screenDiffStats` from roughly 100 to 75 exclusive ticks by avoiding the
  equality-then-stats double scan on full-buffer diffs.
- `fleury benchmark local SB.6 --warmup=2 --iterations=10 --json --save=profiling/caps/2026-06-08-local-sb6-final-10x-solo.json`
  reported update-total p95 493 us, update-frame p95 282 us, update-pump p95
  231 us, semantic-query p95 180 us, and the same 67% update-layout skip ratio.
- `fleury benchmark local SB.12 --warmup=1 --iterations=3 --json`
  showed idle and paint-only frames skip layout fully, while update frames
  perform a small amount of layout; the same post-revert run had
  command-to-frame p95 around 1.0 ms and paint-only p95 around 0.34 ms.
- `fleury benchmark local SB.12 --warmup=1 --iterations=3 --profile-memory --json --save=profiling/caps/2026-06-08-local-memory-sb12.json`
  reported command-to-frame p95 1.145 ms, idle p95 139 us, viewport-scroll p95
  531 us, and about 2.0 MiB median RSS growth over the full journey, mostly
  after the viewport path.
- `fleury benchmark profile SB.12 --warmup=1 --iterations=20 --save=profiling/caps/2026-06-08-vm-profile-sb12.json`
  did not show retained project growth after GC. CPU was dominated by
  `RenderFlex.replaceAllChildren` and descendant removal/replacement work during
  the long `ScrollView + Column` viewport fixture, not by the paint-only or idle
  dirtiness path.
- `fleury benchmark local SB.12 --warmup=2 --iterations=10 --json --save=profiling/caps/2026-06-08-local-sb12-reassessment-10x.json`
  passed with healthy medians but noisy p95 outliers: command-to-frame p95
  2.952 ms, child-list no-op p95 8.724 ms, viewport-scroll p95 9.375 ms, and
  exactly 24 painted viewport rows before and after scroll. Interpret this as a
  phase-specific child-list/fixture investigation, not evidence that layout
  dirtiness caching is failing.
- Added `--sb12-phase=all|dirtiness|viewport` for local and VM-profile runs.
  `fleury benchmark profile SB.12 --sb12-phase=dirtiness --warmup=1 --iterations=10 --save=profiling/caps/2026-06-08-vm-profile-sb12-dirtiness.json`
  produced only 75 samples and no meaningful project CPU concentration; retained
  project data after GC stayed tiny.
- `fleury benchmark profile SB.12 --sb12-phase=viewport --warmup=1 --iterations=10 --save=profiling/caps/2026-06-08-vm-profile-sb12-viewport.json`
  isolated the hotspot to `RenderFlex.replaceAllChildren` while allocating the
  2,000 row elements/render objects for the `ScrollView + Column` fixture.
- After adding a private empty-old/new-children fast path in `RenderFlex`,
  `fleury benchmark profile SB.12 --sb12-phase=viewport --warmup=1 --iterations=10 --save=profiling/caps/2026-06-08-vm-profile-sb12-viewport-flex-fastpath.json`
  improved the profiled viewport-scroll p95 from 1492 us to 812 us. The
  remaining top CPU is still `replaceAllChildren`, which reflects adopting 2,000
  render children in this intentionally large eager fixture.
- `fleury benchmark local SB.12 --warmup=2 --iterations=10 --json --save=profiling/caps/2026-06-08-local-sb12-final-10x-solo.json`
  reported command-to-frame p95 450 us, idle p95 136 us, child-list no-op p95
  253 us, viewport-first p95 1.488 ms, viewport-scroll p95 1.241 ms, and exactly
  24 painted viewport rows before and after scroll.
- `fleury benchmark local SB.3 --warmup=1 --iterations=5 --json` after
  reverting the public cell-text cache API reports low-millisecond p95
  interactions and `cellBuilderCalls=1208`, while still requesting only 62
  unique rows from 100k rows.
- `fleury benchmark wire sb3 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb3`
  reports Fleury at 8292 B, 34% overhead, split `5439/116/2565/156/16`.
- `fleury benchmark wire sb4 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb4`
  reports Fleury at 2906 B, 16% overhead, split `2430/117/154/172/33`.
- `fleury benchmark wire sb5 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb5`
  reports Fleury at 2367 B, 37% overhead, split `1503/446/164/236/18`.
- `fleury benchmark wire sb2 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb2`
  reports Fleury at 2074 B, 19% overhead, split `1677/60/131/188/18`.
- `fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb6`
  reports Fleury at 100613-104562 B, 29% overhead, with cursor bytes around
  24-25 KiB per capture.
- `fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-final-sb6-wire`
  keeps the same peer-facing shape after the local renderer fixes: Fleury is
  leading on bytes at a 100.4 KiB median and leading on FPS at 60.8 fps, while
  control overhead remains ballpark at 29% versus Bubble Tea's 15%. Runtime-
  confounded RSS/CPU still classify as catch-up against Ratatui's floor.
- `fleury benchmark wire sb12 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb12`
  reports Fleury at 2389 B, 23% overhead, split `1830/36/290/220/13`.
- `fleury benchmark wire sb12 --runs=3 --out-dir=profiling/caps/2026-06-08-final-sb12-wire`
  confirms the final SB.12 position: Fleury leads bytes at 2.3 KiB, bytes/frame
  at 265, control overhead at 23%, and FPS at 15.0 fps. TTFB is ballpark versus
  Ratatui, and runtime-confounded RSS/CPU remain the only catch-up rows. One
  Nocterm run emitted only 8 bytes after a long startup, but the median scoreboard
  still gives Fleury the byte lead.
- `fleury benchmark wire sb9 --runs=3 --out-dir=profiling/caps/2026-06-08-cursor-v2-sb9`
  reports Fleury at 4458 B, 28% overhead, split `3203/4/978/252/21`.
- `fleury benchmark wire sb1 --runs=3 --out-dir=profiling/caps/2026-06-08-sb1-runtime-floor`
  adds the runtime-floor control. Fleury reports 149 B, 94% overhead because
  the app is tiny and sync/mode bytes dominate, 17.0 MiB RSS, and leading local
  TTFB/FPS on the median run. Bubble Tea is the memory floor at about 8.4 MiB;
  Ink is the byte floor at 119 B but has a high Node RSS floor; Textual emits
  about 10 KiB on startup.
- `fleury benchmark wire sb1 --peer=bubbletea --runs=1 --runtime-markers --out-dir=profiling/caps/2026-06-08-runtime-markers-smoke2`
  verifies the runtime marker path. Fleury raw TTFB was 464.0 ms; marker
  offsets were `runTui.entry` 459.7 ms, `first.output.write` 460.3 ms, and
  `first.render.end` 462.1 ms. On this smoke run, the framework/render portion
  before first output is sub-millisecond and the first render completes about
  2.4 ms after `runTui.entry`; the startup floor is mostly before Fleury
  framework entry.
- `fleury benchmark wire sb6 --peer=ratatui --runs=3 --runtime-markers --out-dir=profiling/caps/2026-06-08-runtime-markers-sb6`
  and `fleury benchmark wire sb12 --peer=ratatui --runs=3 --runtime-markers --out-dir=profiling/caps/2026-06-08-runtime-markers-sb12`
  extend that decomposition to the catch-up rows. The median-marker SB.6 run
  entered `runTui` at 22.3 ms, wrote first output at 22.8 ms, and ended first
  render at 25.0 ms. SB.12 entered `runTui` at 19.1 ms, wrote first output at
  19.6 ms, and ended first render at 21.8 ms. Cold run 1s can still be hundreds
  of milliseconds before `runTui.entry`, but warm framework first-render work is
  only a few milliseconds.
- `fleury benchmark wire sb11 --peer=ratatui --runs=1 --runtime-markers --out-dir=profiling/caps/2026-06-08-sb11-runtime-markers`
  shows SB.11 enters `runTui` at 461.8 ms and reaches `root.mounted` at
  956.3 ms; `first.render.start` is also 956.3 ms and `first.render.end` is
  957.5 ms. The framework render work is therefore about 1.2 ms after the
  100k-tree/index mount completes; the catch-up cost is data/index setup plus
  runtime/startup, not first render.
- `fleury benchmark local SB.11 --warmup=1 --iterations=3 --json --save=profiling/caps/2026-06-08-local-sb11-index-text-dedupe.json`
  keeps the scenario passing after removing duplicate retained lowercase/original
  aggregate strings from `TreeTableSearchIndex` entries. The measured index build
  median is 558.7 ms, filter-query p95 is 3.9 ms, and first-render p95 is 3.1 ms.
- `fleury benchmark wire sb6 --peer=bubbletea --runs=1 --debug-capture --out-dir=profiling/caps/2026-06-08-sb6-span-diagnostic`
  reports Fleury at 106185 B versus Bubble Tea at 108352 B, with Fleury cursor
  bytes at 25263 B versus Bubble Tea at 15690 B. The debug capture has 119
  frames; median dirty frame shape is 456 dirty cells across 19 dirty rows and
  51 row spans, with average span length about 8.6 cells. Repaint-boundary
  copied/repainted/cached counts are zero for this wire scenario, so the SB.6
  cursor cost is real fragmented dashboard output, not a missing repaint-boundary
  blit optimization.
- A style-aware same-row gap model passed renderer equivalence tests but was
  reverted after `fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-style-gap-v2-sb6`
  and `fleury benchmark wire sb9 --runs=3 --out-dir=profiling/caps/2026-06-08-style-gap-v2-sb9`.
  SB.6 stayed at roughly 102.7 KiB median with about 24.3 KiB cursor bytes and
  28% overhead; SB.9 stayed at 4458 B with 978 cursor bytes and 28% overhead.
  The model was correct but did not hit the real dashboard/subprocess shapes.
- A buffer-level dirty-row/span handoff was also tried after the SB.6 dirty
  capture. It added public `CellDamageRegion`/`CellDamageSpan` types, tracked
  merged row spans in `CellBuffer`, and let `AnsiRenderer.renderDiff` scan those
  spans. The renderer/runtime tests passed, but `fleury benchmark wire sb6
  --runs=3 --out-dir=profiling/caps/2026-06-08-dirty-spans-sb6` still showed
  Fleury around 15% CPU against Ratatui's 1-2%, and SB.12 stayed a runtime-floor
  catch-up case. Local SB.6 made the cost clearer: update-total p95 was about
  1.2 ms with span tracking and about 0.45 ms after removing it. The probe was
  reverted; only emitted-cell dirty-span diagnostics remain.

Relevant code facts:

- `BuildOwner.renderFrame` clears/builds/layouts/paints into a full
  `CellBuffer`, then `runTui` diffs the full previous/current buffers.
- `RenderObject.layout` already has same-constraint layout caching, and
  audited setters can call `markNeedsPaintOnly`.
- `RenderRepaintBoundary` caches paint, but it still blits into the full
  next-frame buffer and the ANSI renderer still scans the frame.
- `ListView.builder` mounts only the visible item subtrees.
- `DataTable` is already a render island and asks `cellBuilder` only for
  visible body rows. A temporary caller-supplied cache-version probe reduced
  `cellBuilderCalls`, but the API was unintuitive and the remaining SB.3
  peer-scorecard weakness is cursor/control overhead, not table data access.

## Recommendations

### Done: ANSI Classification, Style Delta, And Cursor Encoder Cleanup

What changed:

- `AnsiByteBreakdown` classifies cursor moves broadly enough for diagnosis.
- The scoreboard includes a per-scenario byte split table.
- Non-empty style transitions now use deltas instead of unconditional full
  reset/reapply.
- Same-row gaps can be filled with unchanged plain ASCII content when that is
  cheaper than a cursor move.
- The cursor encoder now chooses among absolute position, same-row relative,
  same-column vertical relative, line-start vertical, and combined vertical +
  horizontal moves.
- One-row-down same-column, line-start, and indented-next-row moves can use
  byte-shorter C0 row controls when they are cursor-position equivalent to CSI
  moves.

Measured effect:

- SB.3 improved from the 2026-06-05 baseline of 8755 B / 43% overhead to a
  fresh C0-control capture of 8279 B. Cursor bytes dropped to 2679 B in that
  run, down from the aggregate scorecard's previous 3.4 KiB split.
- SB.4 improved from 2980 B / 18% after gap-fill to 2906 B / 16% after the
  expanded cursor encoder. The C0-control capture kept total bytes at 2906 B
  and reduced that run's cursor split to 154 B.
- SB.6's fresh C0-next-row capture removed `ESC[E` from Fleury output and
  dropped the best-run cursor split to 23,950 B, but the aggregate scorecard
  still lands around 24.3 KiB cursor and 29% overhead.
- SB.5 improved from 2409 B to 2367 B.
- SB.2 improved from 2099 B to 2074 B.
- SB.12 is already leading on byte and overhead axes in the fresh run.

### Closed: Dense Dashboard Cursor/Gap Cost Model

Problem:

Control overhead is the repeated scorecard weakness: SB.4, SB.5, SB.2, SB.3,
SB.6, and SB.9 are all good on bytes but still spend too much on control
overhead. The simple encoder cleanup is validated, but SB.6 still spends
roughly 24-25 KiB on cursor movement per capture.

What changed:

- Added `DirtySpanFrameStats` to frame diagnostics and JSON debug captures.
- Added `fleury benchmark wire ... --debug-capture` and an opt-in SB.6
  `FLEURY_DEBUG_CAPTURE` path to write the frame diagnostics beside wire
  captures.
- Ran SB.6 with debug capture and confirmed the cursor churn comes from
  fragmented row output across many dashboard widgets, not absent dirty bounds
  or repaint-boundary cached blits.
- Tried a style-aware same-row gap cost model that compared cursor jumps with
  encoded gap content and target style transitions. It passed renderer
  equivalence tests, but SB.6/SB.9 showed no meaningful real-scenario win, so
  it was reverted.

Decision:

- Keep the current plain-ASCII gap fill and expanded cursor encoder.
- Do not pursue broader cursor/gap filling unless a new benchmark shape shows a
  material byte win in diagnostics before implementation.
- Treat SB.6 cursor overhead as a dashboard span-shape/layout problem, not a
  missing generic cursor encoder trick.

Validation:

```sh
fleury benchmark wire sb3 --runs=3 --out-dir=profiling/caps/2026-06-08-c0-cursor-sb3
fleury benchmark wire sb4 --runs=3 --out-dir=profiling/caps/2026-06-08-c0-cursor-sb4
fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-c0-cursor-sb6
fleury benchmark wire sb9 --runs=3 --out-dir=profiling/caps/2026-06-08-c0-cursor-sb9
fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-c0-nextrow-sb6
fleury benchmark wire sb9 --runs=3 --out-dir=profiling/caps/2026-06-08-c0-nextrow-sb9
fleury benchmark wire sb6 --peer=bubbletea --runs=1 --debug-capture --out-dir=profiling/caps/sb6-span-diagnostic
fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-style-gap-v2-sb6
fleury benchmark wire sb9 --runs=3 --out-dir=profiling/caps/2026-06-08-style-gap-v2-sb9
```

Observed result:

- SB.6 stayed bytes/FPS leading but still had about 28% overhead and 24-25 KiB
  cursor bytes. The C0-next-row cleanup removed a repeated `ESC[E` pattern but
  did not change the scorecard category.
- SB.9 stayed competitive on bytes against Bubble Tea and leading on FPS, but
  cursor/control overhead remains meaningfully behind Bubble Tea.
- The reverted broad gap-fill experiment is not worth carrying. The C0
  row-control cleanup is worth keeping because it is small, equivalence-tested,
  and improves SB.3/SB.4 byte splits without changing public API.

### Closed: Buffer-Level Dirty Row/Span Handoff Probe

Problem:

Repaint boundaries cache subtree paint, but the terminal presenter still gets
only two buffers plus conservative bounds. SB.12 says the basic layout
dirtiness mechanism is working, but SB.6 says a stable dashboard can still pay
too much CPU and cursor churn across many independently updating widgets.

What changed:

- Added a temporary `CellDamageRegion`/`CellDamageSpan` path in `CellBuffer`.
- Taught `AnsiRenderer.renderDiff` to scan dirty spans instead of a rectangle.
- Wired `runTui` to pass the span region on paint-safe frames.
- Verified the renderer/runtime tests and SB.6/SB.12 wire scenarios.

Decision:

- Reverted the public row/span buffer API and presenter handoff.
- Keep the existing rectangular dirty bounds plus emitted-cell dirty-span
  diagnostics.
- Revisit row/span presentation only if the spans can come from a cheaper
  render-tree or presenter-side source. Tracking and merging spans on every
  buffer write is too expensive for the current hot path.

Validation:

```sh
fleury benchmark local SB.6 --warmup=1 --iterations=3 --json
fleury benchmark local SB.12 --warmup=1 --iterations=3 --json
fleury benchmark wire sb6 --runs=3 --out-dir=profiling/caps/2026-06-08-dirty-spans-sb6
fleury benchmark wire sb12 --runs=3 --out-dir=profiling/caps/2026-06-08-dirty-spans-sb12
```

Observed result:

- SB.6 kept the bytes/FPS lead but peer-facing CPU stayed in the same catch-up
  band.
- SB.12 kept byte and overhead leadership but remained a runtime-floor catch-up
  row on CPU/RSS/TTFB.
- Local SB.6 was slower with span tracking, so the implementation should not
  ship.

### Deferred: DataTable Hot Visible-Row Cache

Problem:

SB.3 is competitive, not leading, on bytes. A short opt-in cache probe reduced
visible-cell builder calls, but it required a public caller-supplied cache
version knob. That API exposes internal cache invalidation to users and does
not address the dominant scorecard weakness: cursor/control overhead.

What to change:

- Do not add a standalone public cache/version knob.
- Reconsider table text caching only if Fleury grows a more natural data-source
  API that owns row keys, row/cell versions, sorting, filtering, export, and
  semantic state together.
- Keep `RenderDataTable` direct and simple until cursor/control overhead is
  fixed.

Validation:

```sh
fleury benchmark local SB.3 --warmup=1 --iterations=5 --json
fleury benchmark wire sb3 --runs=3 --out-dir=profiling/caps/cursor-control
```

Success bar:

- A future data-source design must preserve the current simple `cellBuilder`
  ergonomics for small/custom tables.
- SB.3 should move closer to Textual on bytes through cursor/control overhead
  improvements before reopening table-specific data caching.

### P2: Runtime Floor And Startup Decomposition

Problem:

The catch-up rows are dominated by Ratatui's runtime floor. Fleury's local
layout/render timings are already low, but Dart AOT process startup, RSS, and
per-frame allocation are still visible in peer comparisons. Optimizing the
widget architecture based only on RSS/TTFB would be the wrong move.

What changed:

- Implemented SB.1 startup/counter wire coverage for Bubble Tea, Textual, and
  Ink through `fleury benchmark wire sb1`.
- Promoted SB.1 to the P2 scorecard because runtime floor is needed to
  interpret SB.6/SB.12 RSS and TTFB.
- Added `fleury benchmark wire ... --runtime-markers`, which writes a
  Fleury-only runtime marker sidecar and folds marker offsets into the capture
  JSON and scoreboard without changing the PTY byte stream.
- Added local `fleury benchmark local ... --profile-memory` support for
  Fleury-only RSS phase profiles in SB.6 and SB.12. The wrapper resolves
  relative `--save` paths from the repository root before forwarding to package
  runners.
- Ran marker captures for SB.1, SB.6, and SB.12. The markers consistently show
  that warm first-output latency is dominated by process/runtime entry before
  `runTui`, while Fleury's mount/first-render-to-output path is sub-millisecond
  to low-single-digit milliseconds.
- The generated scoreboard now reports marker deltas directly: `pre-runTui`,
  `entry->first output`, `entry->first render end`, and `entry->cleanup`.
- Ran local RSS phase profiles for SB.6 and SB.12. SB.6 does not show retained
  RSS growth during sustained dashboard updates, while SB.12 shows a small
  full-journey RSS increase concentrated after the viewport path.
- Added `fleury benchmark profile <SB.id>` for repeatable VM service CPU and
  allocation profiles over local benchmark scenarios.
- Used that profiler to close the SB.6 first implementation loop: the broad
  scroll-up detector was the clearest CPU issue and is now gated privately inside
  `AnsiRenderer`.
- Added phase-specific SB.12 profiling. Dirtiness-only is clean; viewport-only
  isolates the large eager child-list fixture.
- Added a private empty-old/new-children fast path to `RenderFlex`, improving the
  SB.12 viewport profile without changing widget APIs.

What remains:

- For SB.6, the next implementation target is still peer-facing cursor/control
  output shape. Local CPU is now sub-millisecond; the peer catch-up issue is
  bytes/control overhead, not table caching or public buffer metadata.
- For SB.12, no further immediate framework work is indicated. A lazy child
  model for `ScrollView + Column` would be a larger API/design project; use
  `ListView.builder` or an equivalent virtualized widget for real large lists.

Validation:

```sh
fleury benchmark wire sb1 --runs=5 --runtime-markers --out-dir=profiling/caps/startup-floor
fleury benchmark wire sb6 --peer=ratatui --runs=3 --runtime-markers --out-dir=profiling/caps/2026-06-08-runtime-markers-sb6
fleury benchmark wire sb12 --peer=ratatui --runs=3 --runtime-markers --out-dir=profiling/caps/2026-06-08-runtime-markers-sb12
fleury benchmark local SB.6 --warmup=1 --iterations=3 --profile-memory --json --save=profiling/caps/2026-06-08-local-memory-sb6.json
fleury benchmark local SB.12 --warmup=1 --iterations=3 --profile-memory --json --save=profiling/caps/2026-06-08-local-memory-sb12.json
fleury benchmark profile SB.6 --warmup=1 --iterations=5 --save=profiling/caps/2026-06-08-vm-profile-sb6.json
fleury benchmark profile SB.12 --warmup=1 --iterations=20 --save=profiling/caps/2026-06-08-vm-profile-sb12.json
fleury benchmark profile SB.12 --sb12-phase=viewport --warmup=1 --iterations=10 --save=profiling/caps/2026-06-08-vm-profile-sb12-viewport-flex-fastpath.json
fleury benchmark local SB.6 --warmup=2 --iterations=10 --json --save=profiling/caps/2026-06-08-local-sb6-final-10x-solo.json
fleury benchmark local SB.12 --warmup=2 --iterations=10 --json --save=profiling/caps/2026-06-08-local-sb12-final-10x-solo.json
```

Success bar:

- The scorecard directly reports framework-over-runtime deltas, so catch-up
  rows do not overstate Fleury framework first-render cost. This is now true
  for the current SB.1/SB.6/SB.12 marker captures.
- SB.6/SB.12 recommendations stop treating Ratatui's 2 MiB RSS as an
  architecture target for a Dart framework.
- Local RSS phase profiles are repeatable from the benchmark CLI and provide
  enough signal to decide whether RSS is retained growth or process/GC noise.

### Done: Benchmark And Analyzer Hygiene

What changed:

- Classify CUF/CUB/CUU/CUD/CNL/CPL cursor moves as cursor overhead in
  `AnsiByteBreakdown`.
- Keep `other` for terminal mode entry/exit, non-cursor control, and unknown
  escapes.
- Add a per-scenario median byte split table to the scoreboard so the next
  optimization target is visible without rerunning `analyze.dart` by hand.

Validation:

```sh
dart analyze profiling packages/fleury/lib/src/rendering
fleury benchmark scoreboard \
  --input=profiling/caps/2026-06-05-decision-baseline-153641Z \
  --output=/tmp/fleury-scoreboard.md
```

## Recommended Order

1. Keep the validated ANSI cleanup.
2. Keep the dirty-span diagnostic capture path, but do not ship buffer-level
   span tracking.
3. Keep the SB.6 renderer fixes. Future SB.6 work should target peer-facing
   cursor/control bytes, not local CPU or public buffer APIs.
4. Leave SB.12 framework architecture alone for now. The phase split shows
   dirtiness caching is working; the remaining eager `ScrollView + Column`
   construction cost is a larger lazy-child-model design question, not a perf
   bug in the current invalidation path.
5. Keep SB.7 in the catch-up watchlist for runtime-floor/Tier-C validation; it
   is already strong on bytes and FPS.
6. Treat SB.11 as a data/index and benchmark-shape issue, not a renderer issue.
   The next real implementation step is a lazy TreeTable data source or aligned
   peer fixtures. Small renderer cursor work will not address the measured
   RSS/CPU result.

The main decision: continue product/framework work in parallel. The benchmark
data does not justify a framework rewrite or a new DataTable cache API. The
remaining high-value implementation work is now narrower: peer-facing SB.6
cursor/control bytes are optional cleanup rather than a blocker; SB.11 needs a
larger lazy-tree/fixture-parity decision before more implementation; defer SB.12
architecture unless product work calls for a general lazy `ScrollView` child
model. Broad new benchmark work is lower priority than implementation work;
before public claims, run Tier-C bare-metal replicates.
