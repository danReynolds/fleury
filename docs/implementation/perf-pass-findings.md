# Performance pass — findings & priority list (2026-07-02)

Entry point for the performance phase of the pre-launch audit (architecture →
performance → API). It (1) evaluates the architecture's performance from a
technical standpoint, (2) reviews the profiling tooling and its gaps, and (3)
gives a priority-ranked list of what to investigate or address.

## TL;DR

The perf **story is strong on wire bytes** (Fleury's documented strength) and
the profiling infrastructure is more complete than expected — but a **hard
regression gate had silently rotted**, and restoring it immediately surfaced a
**real, pre-existing +60% byte regression in the dashboard scenario**. The
architectural cost that trails flat-buffer peers is the **retained-tree tax**
(per-frame layout-skip checks + `CellConstraints` allocation + a whole-screen
diff whenever any node's size changes), and the largest **coverage gap** is the
`fleury serve` live-wire path and the entire inline-image pipeline — neither is
benchmarked on either surface.

## Tooling state

Three surfaces already have hard perf gates:

| Surface | Tooling | Gate |
| --- | --- | --- |
| Terminal (real PTY) | `capture_pty` → `analyze` (`AnsiByteBreakdown`) → `scoreboard`; `fleury benchmark local/profile/wire`; **wire-gate** on SB.1/6/9 | byte-axis regression gate (`wire_gate_baseline.json`) |
| Browser **embed** (dart2js in headless Chrome) | `fleury benchmark web-capture`/`web-suite`, 13 scenarios, `thresholds.json`, web-readiness bundle | hard p95 gate (`maxTotalFrameP95Ms` 16.67, domApply, semanticApply, over-budget %) |
| MCP agent | `mcp_benchmarks` + `mcp_perf_gate_test` | hard gate (delta < 2% of full read, indexed lookup < 0.5× walk, …) |

On-demand/diagnostic: `fleury_heap_probe` (VM allocation composition), `fleury
benchmark profile` (VM CPU/alloc), `serve_startup_profile` (the only live-socket
tool — connect→first-paint).

## What the pass found

### 0. The wire-gate was dead (FIXED — PR #28)

All 12 `profiling/bin/fleury_sb*_wire.dart` fixtures and the wire-gate called
`runTui`, renamed to `runApp`, so `fleury benchmark wire` / `wire-gate` failed
to compile and `dart analyze profiling` was red. The **only hard byte-regression
gate for the terminal path had been silently non-functional.** Fixed in PR #28.
Follow-up: add an "all `bin/*_wire.dart` compile" smoke check so it can't rot
silently again.

### 1. SB.6 dashboard: real +60% byte regression (INVESTIGATE — top priority)

The moment the gate ran: **SB.6 total bytes 175,106 vs baseline 109,059
(+60.6%), bytes/frame 1447 vs 901, control overhead 57% vs 31% (+26pt), frames
unchanged.** Isolation: pre-merge `main@86b3581` shows the *identical* number
(174,982) — so this **predates the PR1–PR9 pipeline work and the merge** (which
added ~0.1%, confirmed inert: image-path changes are no-ops on image-free
frames). It slipped in through the June→July app-feedback/Focus/LayoutBuilder
work while the gate was dead. The +26pt control-byte overhead with unchanged
frame count points at **more frames taking the whole-screen diff path** (a size
change trips `_requiresFullDiff` → null-`dirtyBounds` full scan → more scattered
cursor moves). Next: `git bisect` the June-11→main range with the restored gate
to attribute the commit, then fix (if a real regression) or re-baseline in the
same commit (if an intentional, measured output change).

### 2. The retained-tree tax (SB.6 / SB.7 / SB.12 — architectural, real but bounded)

The catch-up rows vs flat-buffer peers (Ratatui/OpenTUI) share one root cause:
Fleury pays retained widget/element/render bookkeeping that a peer recomputing a
flat buffer does not. Byte output stays lean; **raw per-frame CPU trails.**
Local numbers (Fleury-only harness): SB.6 ~170µs/update (45 layouts performed /
29 skipped), SB.7 ~168µs/resize (every distinct size = full rebuild + full
relayout + full repaint), SB.12 idle frame still ~148µs (tree walk + per-frame
`CellConstraints` alloc + diff scan even when zero layouts run). Concrete
optimization targets:

- **`CellConstraints` pooling** — a fresh constraint object is allocated per node
  per frame just to run the `_constraints == constraints` skip check.
- **Paint-only frames keep a bounded `dirtyBounds`** instead of falling to a full
  diff (the scoped-repaint path exists but SB.6 rarely hits it because value
  changes alter size).
- **`handleResize` could preserve the diff base for the overlapping region**
  rather than diffing the new frame against an all-empty prev.

(SB.11 is a **fixture-comparability caveat, not a gap** — Fleury builds a 100k
retained TreeTable + search index while the peers compute visible rows; ~92% of
its journey is one-time index/fixture construction. Don't publish peer RSS/CPU
from SB.11.)

### 3. Uncovered hot paths (no benchmark exercises these — regressions invisible)

The benchmark suite drives `AnsiRenderer.renderDiff`, cell paints, builds, and
the parser only. The **terminal-image encoder, the serve/wire codec, and the
semantics-flush path have zero coverage.** Ranked by impact:

- **Terminal image encoder has no zero-image fast path** — `encodeFrame` runs
  every presented frame on *any* Kitty/iTerm2/Sixel terminal and allocates
  lists/sets/StringBuffer even with no images on screen. Highest leverage (paid
  by every frame of every session on a modern terminal). Clear fix: early-return
  when placements + encoder state are empty and it's not a full repaint.
- **Kitty placement reconciliation is O(n²)** with an uncached `key` getter that
  rebuilds an interpolated string per comparison. Fix: cache the key in a field +
  `Map` lookup.
- **`buildRemotePlan` (serve) does 3 full O(cols×rows) scans** per frame
  (`screenDiffStats` + `detectBeneficialScrollUp` + `_buildPatches`), ignoring
  the frame's `diffBounds` — the ANSI path already early-exits on bounded damage;
  the wire path lost that optimization.
- **Serve rebuilds the full semantic tree** (`SemanticTree.fromElement` +
  `owner.update` diff) on any visual-only dirty frame, once per microtask flush.
- **`InlineImageOverlay.apply`** (browser embed) has no empty early-exit — runs
  the reconcile every frame even with zero images.
- Per-frame `Stopwatch` allocations not gated on `debugWatching`; `cell_buffer`
  clears the image maps every frame even when empty (micro).

(Corrected during analysis: the sixel median-cut is already O(pixels × log
colors); the animated-image re-ship is correctly bounded; the "stray mount
build" is benign — mount routes through `rebuild()` which clears the dirty flag.)

## Coverage gaps → tooling that should exist

| # | Gap | Why it matters | Proposal |
| --- | --- | --- | --- |
| G1 | **`fleury serve` live-wire path** (app→real browser: steady bytes/frame, cadence, coalescing) is unmeasured — the serve byte profiles are *synthetic* in-process buffers; `web-capture` is the *embed*, not serve | The flagship two-surface story has wire-level proof for ONE surface | `serve_wire_live_profile`: boot serve, headless WS client, drive SB scenarios, record real socket bytes (pre/post-DEFLATE) + cadence; gate steady-state bytes/frame |
| G2 | **Inline-image perf** — zero coverage on either surface; `AnsiByteBreakdown` has **no image category** (Kitty/iTerm2/Sixel bytes land in `other`, invisible to the gate) | Images are the largest per-frame payload and most likely wire blow-up; a dedup regression would trip no gate | Image bench both surfaces (static + N-frame animation, bytes/frame + encode µs, assert dedup) + add an image category to `AnsiByteBreakdown` |
| G3 | **No per-frame allocation gate** — only manual `heap_probe`, no baseline | Steady-state per-frame churn is exactly what RSS deltas mask and what erodes sustained FPS | Alloc-per-frame gate reusing the heap-probe machinery on SB.6, baselined like the wire gate |
| G4 | **No true input→paint latency** on either surface (`commandToFrameUs` is an in-VM proxy; the wire never correlates injected input → resulting frame) | Input responsiveness is the headline UX axis for WAN-SSH and served browser | Timestamp injected event → frame that reflects it; report/gate p95 in the live-wire + web harness |
| G5 | **Backpressure/producer-gate is correctness-tested, never perf-characterized** (bytes saved, drain latency, sustained slow-peer all unquantified) | The gate's whole value is bytes+latency saved under a slow link | Throttled-drain transport in the live-wire tool; measure vs an ungated baseline |
| G6 | **No dart2js bundle-size gate** (`web-capture` validates existence, not size) | First-load weight regresses trivially (a stray import = 100s of KB) | Record `File(js).lengthSync()` + gzip in the web capture JSON; gate in `web-readiness` |

## Suggested sequencing

1. **Land PR #28** (gate restored) + add the fixtures-compile smoke check.
2. **Bisect + resolve the SB.6 +60% regression** (fix or re-baseline) — the gate is red until this is closed.
3. **Encoder zero-image fast path + kitty key caching** — clear, self-contained wins on the terminal image path (do alongside G2 so the fix is measured).
4. **G1 live-serve-wire harness** — unblocks measuring the whole serve surface (the biggest blind spot); then G4/G5 layer onto it.
5. **G2 image bench + `AnsiByteBreakdown` image category** — makes the image pipeline gateable.
6. **Retained-tree-tax investigations** (`CellConstraints` pooling, paint-only bounded diff, resize diff-base preservation) — profile-guided (`fleury benchmark profile SB.6/SB.12`), bigger and lower-urgency.
7. **G3 allocation gate, G6 bundle-size gate** — regression insurance once the above land.
