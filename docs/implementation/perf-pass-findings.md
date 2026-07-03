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

### 1. SB.6 dashboard: real +60% byte regression (RESOLVED — root-caused and fixed)

The moment the gate ran: **SB.6 total bytes 175,106 vs baseline 109,059
(+60.6%), bytes/frame 1447 vs 901, control overhead 57% vs 31% (+26pt), frames
unchanged.** PTY-captured byte categorization located it precisely: **cursor
moves tripled, 24.8k → 85.4k** (content and color essentially flat), i.e. the
diff was emitting an absolute `CUP` *per cell* instead of one per contiguous run.

Root cause: commit `97cd002` ("absolute reposition after ambiguous-width
glyphs") invalidates the tracked cursor after **every non-ASCII, non-wide
glyph** — which is the entire block-element / box-drawing vocabulary
(`█ ▁ ▂ ─ │`) that gauges, sparklines, and bar charts are built from. It's a
real fix for the "Warp garble" (terminals that render those glyphs two columns
wide desync), but it paid the per-cell repositioning on **every** terminal,
including the ~95% that render them one column wide. A 48-cell sparkline fill
cost 48 cursor moves instead of one.

Fixed by making the defensive repositioning **capability-gated**: a one-time
startup Cursor-Position probe (the same `t_u7`/`ESC[6n` technique vim uses to
auto-set `ambiwidth`) measures whether the terminal draws ambiguous glyphs one
or two columns wide. Narrow terminals emit compact contiguous runs; wide or
unprobed terminals keep the safe per-cell pinning, so the garble fix is intact.
`AnsiRenderer.ambiguousCharsAreWide` defaults to the safe `wide`; the driver
flips it to `narrow` only on a positive probe (env override
`FLEURY_AMBIGUOUS_WIDTH=narrow|wide` in reserve). **Post-fix SB.6: +3.3% vs
baseline (the intentional color legibility pass), gate green — no re-baseline
needed.** Not a `_requiresFullDiff` issue (the earlier hypothesis) — the
absolute-CUP encoding change from `05ce2d4` was measured inert (~0.6k).

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
- ~~**Serve rebuilds the full semantic tree** … on any visual-only dirty
  frame~~ **INVESTIGATED (Tier 1, 2026-07-03) — not a delivered-wire problem.**
  The tree IS rebuilt per changed frame (`SemanticTree.fromElement`, a redaction
  walk), but the wire is already diffed by `SemanticsWireEncoder` to O(changed)
  nodes and permessage-DEFLATE crushes the residual: **10–38 B/frame delivered,
  flat in tree size** (`serve_semantics_profile`; a revert to full-resend cliffs
  to ~2180 B at 244 nodes), CPU ≤552 µs at 244 nodes (~3% of a 60 fps budget).
  The G1 "semantics dominate 5–13× plan" finding was **raw** bytes — deflated +
  diffed it is a non-issue for realistic UIs (the all-changing G1 log scenario
  was pathological; a real log scrolls ≈1 changed node/frame). No fix warranted;
  instead the anti-cliff invariant is now **guarded** (`fleury benchmark
  serve-semantics-gate`) so a regression toward full-resend can't slip in.
  Node-level dirty tracking (skip the toJson walk for unchanged nodes) is the
  only latent micro-opt, negligible at 60 fps.
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
| G1 | ~~**`fleury serve` live-wire path** is unmeasured — the serve byte profiles are *synthetic* in-process buffers~~ **BUILT** | The flagship two-surface story now has live wire-level proof for the serve surface | **`serve_wire_live_profile` + `serve_wire_live_gate`** (`fleury benchmark serve-wire-live`): boots real serve `--spawn`, a headless deflate-off WS client drives runApp scenarios (dashboard/log/counter) and records real socket bytes **classified by frame type** + cadence; offline whole-stream DEFLATE for the post-compression number. Gate keys on the stable raw+deflated totals (bytes/frame is coalescing-noisy → warn-only). **Finding: the serve wire is semantics-dominated — 5–13× the plan bytes** (dashboard sem 5.3k vs plan 1.0k B/f; log 7.0k vs 0.5k; counter 0.28k vs 0.03k) — the semantics stream, re-sent per frame (§3), is the real serve wire cost and was invisible to the plan-only synthetic tool. |
| G2 | ~~**Inline-image perf** — zero coverage; `AnsiByteBreakdown` has no image category~~ **BUILT (terminal side)** | Images are the largest per-frame payload; the #30 encoder fast path shipped unmeasured | **`AnsiByteBreakdown` now has an `image` category** (recognizes APC/DCS/OSC-1337; before, escapes were mis-counted as **content**, not `other`) + **`image_bench` (`fleury benchmark image-bench [--gate]`)**: image bytes/frame + encode µs per protocol, static vs animated, with a `--gate` on the dedup and zero-image-fast-path invariants. Measured: kitty 403 B first-frame, **0 B/frame static (dedups)**, 451 B/frame animated, 18.8 µs encode; iterm2 414/0/414 B, 6.8 µs. Follow-up (v2): the browser/serve image wire (rides G1) and the embed `InlineImageOverlay` (DOM, not bytes); sixel needs the RGBA sidecar. |
| G3 | **No per-frame allocation gate** — only manual `heap_probe`, no baseline | Steady-state per-frame churn is exactly what RSS deltas mask and what erodes sustained FPS | Alloc-per-frame gate reusing the heap-probe machinery on SB.6, baselined like the wire gate |
| G4 | **No true input→paint latency** on either surface (`commandToFrameUs` is an in-VM proxy; the wire never correlates injected input → resulting frame) | Input responsiveness is the headline UX axis for WAN-SSH and served browser | Timestamp injected event → frame that reflects it; report/gate p95 in the live-wire + web harness |
| G5 | **Backpressure/producer-gate is correctness-tested, never perf-characterized** (bytes saved, drain latency, sustained slow-peer all unquantified) | The gate's whole value is bytes+latency saved under a slow link | Throttled-drain transport in the live-wire tool; measure vs an ungated baseline |
| G6 | **No dart2js bundle-size gate** (`web-capture` validates existence, not size) | First-load weight regresses trivially (a stray import = 100s of KB) | Record `File(js).lengthSync()` + gzip in the web capture JSON; gate in `web-readiness` |

## Suggested sequencing

1. **Land PR #28** (gate restored) + add the fixtures-compile smoke check.
2. ~~Resolve the SB.6 +60% regression~~ **DONE** — capability-gated ambiguous-width repositioning (see §1); gate green, no re-baseline.
3. **Encoder zero-image fast path + kitty key caching** — clear, self-contained wins on the terminal image path (do alongside G2 so the fix is measured).
4. ~~G1 live-serve-wire harness~~ **DONE** — `serve_wire_live_*` (see G1). Surfaced that semantics dominate the **raw** serve wire 5–13×, which on investigation (§3, Tier 1) is **not** a delivered-cost problem — the diff encoder + DEFLATE already keep it flat at 10–38 B/frame, now guarded by `serve-semantics-gate`. The next real serve/perf levers are the coverage tools (G2/G6), not semantics. G4/G5 layer onto this harness.
5. ~~G2 image bench + `AnsiByteBreakdown` image category~~ **DONE (terminal)** — `image` category + `image_bench --gate` (dedup + zero-image invariants byte-gated). Browser/serve image wire + embed overlay are the v2 follow-ups.
6. **Retained-tree-tax investigations** (`CellConstraints` pooling, paint-only bounded diff, resize diff-base preservation) — profile-guided (`fleury benchmark profile SB.6/SB.12`), bigger and lower-urgency.
7. **G3 allocation gate, G6 bundle-size gate** — regression insurance once the above land.
