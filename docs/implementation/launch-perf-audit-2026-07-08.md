# Launch-hardening performance audit (2026-07-08)

**Status:** Findings report (no product code changes; throwaway experiments only)  
**Date:** 2026-07-08  
**Tree:** branch `fleury-main-sync`  
**Companion:** [launch-bug-audit-2026-07-08.md](launch-bug-audit-2026-07-08.md) (correctness)  
**Prior context:** [perf-pass-findings.md](perf-pass-findings.md) (2026-07-02), [perf-gates.md](perf-gates.md)

## Purpose

First-principles audit of whether Fleury is **robustly performant for launch**: not “is there a micro-opt left,” but whether the launch-critical paths stay within honest budgets, whether regressions are *caught*, and where architectural costs or tool holes let latency, bytes, or GC churn slip.

## Launch bar used for severity

| In bar | Out of bar (deferred) |
| --- | --- |
| Steady-state TUI frames (build → layout → paint → ANSI/wire) | Peer competitive ranking / public scoreboard claims |
| Dashboard / log / counter / demo-shaped load | Full multi-terminal matrix variance |
| `fleury serve` plan + semantics wire | Windows-only perf |
| Allocation / GC pressure on the per-frame path | Perfect 0-alloc paint |
| Gate honesty (CI, CLI, baselines) | Re-baselining as a product feature |

Severity:

| Level | Meaning |
| --- | --- |
| **blocker** | Launch performance claim is false or unguarded on a critical path. |
| **high** | Material latency/byte/GC cost or a reproducible scenario failure on a launch surface. |
| **medium** | Real cost or coverage hole; impact narrower or partially mitigated. |
| **low** | Hygiene, baseline drift, DX of tooling. |
| **note** | Observation / intentional tradeoff. |

---

## Executive summary

**Gates that ran green:** fast suite (`serve-semantics`, `image-bench`, `bundle-size`, `alloc-gate`), terminal `wire-gate` (byte axes), live `serve-wire-live`.  
**Not green / not honest enough:**

1. **SB.8 Overlay / Command Palette scenario fails correctness under churn** (reproduced 2×) — palette/route state drifts; this is a launch scenario, not a microbench.
2. **Serve plan path still full-scans the grid every frame** even for sparse damage — measured **~589 µs** `buildRemotePlan+encode` on 160×50 with a 3-cell dirty patch (24 B encoded). ANSI already has bounded-diff (~**4.8 µs** same shape).
3. **`screenDiffStats` full grid scan is a top SB.6 CPU symbol** and costs **~120 µs** on 160×50 alone (~7% of a 60 fps budget before paint/diff).
4. **Per-frame alloc is gated and flat vs baseline**, but composition is **Cell-dominated (~51%)** — immutable cell writes are the architectural tax; not a silent regression, but the ceiling for sustained FPS under dense paint.
5. **Process holes:** CI runs **no** perf gates; `wire-gate --gate` is a **CLI lie** (unknown arg); `benchmark local` **exits 0 when scenarios fail**; SB.6 wire is **−20% vs baseline** (improvement not locked in).

Net: the machinery from the July 2 pass is largely intact and still gated on the byte/alloc axes that were built. Launch risk is less “we forgot to optimize” and more **(a) one demo-critical scenario is red, (b) serve CPU ignores damage bounds the ANSI path already has, (c) gates are not in CI and some tooling lies about pass/fail.**

### Priority-ordered must-address list

| P | ID | Title | Severity |
| --- | --- | --- | --- |
| P0 | P1 | SB.8 command-palette / overlay churn fails correctness (repro) | **high** |
| P0 | P2 | Serve `buildRemotePlan` ignores paint damage bounds (full-grid CPU) | **high** |
| P0 | P3 | Full-scan `screenDiffStats` on every unbounded ANSI/serve path | **high** |
| P0 | P4 | Perf gates not in CI; local scenario fail does not fail the tool | **high** (process) |
| P1 | P5 | Cell allocation dominates per-frame churn (~6 KiB/frame baseline) | **medium** |
| P1 | P6 | Default `frameInterval = 0` uncapped under stream/log pressure | **medium** |
| P1 | P7 | Wire-gate CLI rejects `--gate`; docs imply universal `--gate` | **medium** (tooling) |
| P1 | P8 | SB.6 wire baseline stale (measured −20%; should re-baseline) | **low** |
| P1 | P9 | No true input→paint latency gate (G4 still open) | **medium** (coverage) |
| P1 | P10 | Backpressure / producer-gate unmeasured under slow peer (G5) | **medium** (coverage) |
| P2 | P11 | Every frame clears the full back buffer (paint floor) | **low** / intentional |
| P2 | P12 | Fast `gates` suite omits wire + serve-live by design | **note** |
| P2 | P13 | Candidate local scenario thresholds still `enforced: false` | **note** |

---

## Baseline health (re-run evidence)

| Check | Result | Notes |
| --- | --- | --- |
| `dart tool/fleury_dev.dart bootstrap` | OK | |
| `benchmark gates` (fast) | **PASS** | serve-semantics, image-bench, bundle-size, alloc-gate |
| `benchmark alloc-gate` | **6043.8 B/frame** vs baseline 6043.8 (+0.0%) | Top: `Cell` 1.23 MB / 400 frames |
| `benchmark wire-gate` | **PASS** | SB.6 **−20%** total bytes vs baseline (warn only on decrease) |
| `benchmark wire-gate --gate` | **usage error 64** | `unknown argument: --gate` — CLI/docs mismatch |
| `benchmark serve-wire-live --gate` | **PASS** | dashboard/log/counter raw+deflated within tolerance |
| `benchmark local all` (warmup=1, iter=5) | **SB.8 FAIL**; others pass | Tool **exit code 0** despite failure |
| `benchmark local SB.8` (warmup=2, iter=8) | **FAIL again** (same mismatch shape) | Not a one-shot flake |
| `benchmark profile SB.6` | OK | Top CPU: `appendCell`, `_checkBoundsColRow`, `screenDiffStats` |

### Local scenario snapshot (this machine)

| Scenario | Result | Headline metric |
| --- | --- | --- |
| SB.1 Time To Counter | pass | command_to_frame p95 **508 µs** |
| SB.2 Text Editing | pass | cursor_move p95 **335 µs** |
| SB.3 DataTable 100k | pass | page_move p95 **652 µs** |
| SB.4 LogRegion | pass | append_burst p95 **15.9 ms** |
| SB.5 Streaming Markdown | pass | chunk_update p95 **16.2 ms** |
| SB.6 Dashboard | pass | update_total p95 **544 µs** |
| SB.7 Resize Storm | pass | resize_frame p95 **381 µs** |
| **SB.8 Overlay / Palette** | **fail** | cycle p95 ~11 ms (under candidate 50 ms); **correctness red** |
| SB.9 Untrusted output | pass | process_run p95 ~198 ms (OS spawn variance) |
| SB.10 Demo journey | pass | journey p95 ~215 ms |
| SB.11 TreeTable | pass | filter_query p95 **2.6 ms** |
| SB.12 Layout dirtiness | pass | command_to_frame p95 **942 µs** |

### Throwaway micro-experiments (this machine, 2026-07-08)

| Experiment | Result |
| --- | --- |
| `screenDiffStats` 80×24 | **29.0 µs**/call (~1.7% of 16.7 ms) |
| `screenDiffStats` 160×50 | **119.6 µs**/call (~7.2%) |
| `screenDiffStats` 200×60 | **177.6 µs**/call (~10.7%) |
| Scroll detect 80×40 (scroll-up 1) | **105.9 µs**/call |
| `buildRemotePlan+encode` sparse 80×24 | **152.8 µs**, **23 B** encoded |
| `buildRemotePlan+encode` sparse 160×50 | **589.0 µs**, **24 B** encoded |
| `buildRemotePlan+encode` full 80×24 | **93.4 µs**, **2055 B** |
| `renderDiff` 160×50 sparse **full scan** | **866.0 µs**, 10 B out |
| `renderDiff` 160×50 sparse **1-row dirtyBounds** | **4.8 µs**, 10 B out (**~180×**) |

---

## Surfaces reviewed

| Surface | Paths / tools |
| --- | --- |
| Frame loop / scheduler | `tui_frame_loop.dart`, `frame_driver.dart`, `frame_scheduler.dart`, `run_app.dart` |
| Paint / cells | `cell_buffer.dart`, `cell.dart`, `render_object.dart`, `render_repaint_boundary.dart` |
| ANSI diff | `ansi_renderer.dart`, `scroll_detection.dart`, `ansi_frame_presenter.dart` |
| Serve / remote plan | `remote_codec.dart` `buildRemotePlan`, `remote_driver.dart` `presentFrame` |
| Images | `terminal_image_encoder.dart` (zero-image fast path present) |
| Semantics wire | `serve-semantics-gate`, prior serve readiness notes |
| Gates / CI | `profiling/bin/*`, `tool/fleury_dev.dart`, `.github/workflows/check.yml` |
| Scenarios | `packages/*/benchmark/scenario_benchmarks.dart` |

---

## Assumption validation

| # | Assumption | Verdict | Justification |
| --- | --- | --- | --- |
| A1 | Fast perf gates stay green on this tree | **PASS** | All four fast gates pass; alloc flat at baseline. |
| A2 | Terminal wire bytes stay within wire-gate | **PASS** | wire-gate pass; SB.6 improved vs baseline. |
| A3 | Live serve wire stays within serve-wire-live | **PASS** | All three scenarios ok. |
| A4 | Local scenario suite is launch-healthy | **FAIL** | SB.8 consistently fails correctness under palette/overlay churn. |
| A5 | Sparse frames avoid full-grid work on all presenters | **FAIL** | ANSI can bound; **serve plan always full-scans**. Unbounded ANSI still pays full `screenDiffStats`. |
| A6 | Per-frame allocation is under control | **PASS with ceiling** | Gate green; Cell-dominated ~6 KiB/frame is the structural budget, not drift. |
| A7 | Perf regressions cannot land without a red signal | **FAIL** | No CI gates; `local` exit 0 on fail; heavy gates opt-in; `--gate` broken on wire-gate. |
| A8 | Default runApp is safe under high-rate updates | **PARTIAL** | Microtask coalescing exists; **no default frame-rate cap** (`frameInterval` zero). |
| A9 | Prior July 2 image / semantics gates still hold | **PASS** | image zero-image/dedup; semantics anti-cliff flat. |

---

## Findings (priority ordered)

---

### P0 — Must address before “robustly performant for launch”

---

#### P1 — SB.8 Overlay / Command Palette churn fails correctness (reproducible)

| Field | Detail |
| --- | --- |
| **Severity** | **high** |
| **Priority** | P0 |
| **Class** | Confirmed scenario failure (correctness under load; not latency) |

**What happens**

`benchmark local SB.8` exercises CommandPalette through `Navigator.present` with alternating keyboard / semantic invoke / dismiss cycles plus a disabled-command probe. Pass is **`samples.every(correct)`**, not the candidate latency thresholds (`enforced: false`).

Observed (two independent runs, 5 and 8 measured iterations):

| Counter | Value (representative) | Required for pass |
| --- | --- | --- |
| `stalePaletteAfterCloseCount` | **41** | 0 |
| `routeDepthMismatchCount` | **40** | 0 |
| `semanticMismatchCount` | **53** | 0 |
| `paletteMismatchCount` / selected / visibleText | 4 each | 0 |
| `screenCommandInvokeCount` | **0** | > 0 |
| `disabledStayedOpen` | **false** | true |
| `actionFailureCount` | 1 | 0 |
| cycle p95 | ~11 ms | candidate 50 ms (informational) |

So the palette often remains in the semantic tree after “close,” route depth does not return to 1, and screen-scoped commands never register as invoked. Latency is fine; **state is wrong under churn**.

**Evidence**

- `packages/fleury_widgets/benchmark/scenario_benchmarks.dart` — SB.8 `pass: correct` (~1971); correctness predicates (~2220–2240); stale palette / route depth checks (~2179–2185).
- Logs: local-all run + dedicated SB.8 re-run (identical failure shape).

**Assumption challenged**

“Demo-shaped overlay + command palette is correct and fast under repeated open/filter/invoke/dismiss.”

**First-principles rationale**

Command palette and overlays are core demo/launch UX. A scenario that intentionally stress-tests them is failing for structural reasons (stale palette, route depth, zero screen-command invokes). That is a **launch blocker for “the toolkit holds under agent-style command use,”** regardless of microsecond paints. It also means the local suite cannot be trusted as a green “all scenarios pass” signal until fixed or quarantined with an explicit known-fail policy.

**Recommended fix**

1. Debug route/palette lifecycle: why `Navigator.depth != 1` after cycle settle; why `SemanticRole.commandPalette` remains after dismiss.  
2. Fix framework or widget; keep SB.8 as a **hard correctness gate**.  
3. Make `fleury_dev benchmark local` **exit non-zero** when any scenario `pass: false` (see P4).

---

#### P2 — Serve `buildRemotePlan` ignores paint damage bounds (full-grid CPU every frame)

| Field | Detail |
| --- | --- |
| **Severity** | **high** |
| **Priority** | P0 for serve launch claims |
| **Class** | Confirmed architectural asymmetry / CPU tax |

**What happens**

`RemoteTerminalDriver.presentFrame` always calls `buildRemotePlan(prev, next, fullRepaint: …)` with **no dirty bounds**. Inside `buildRemotePlan`:

1. `screenDiffStats(prev, next)` — full O(cols×rows)  
2. `detectBeneficialScrollUp` — additional full scans  
3. `_buildPatches` — walks rows/cols against `prevRef`

The ANSI path, by contrast, passes `dirtyBounds: frame.damage.diffBounds` into `renderDiff` (`ansi_frame_presenter.dart`) and **skips** whole-screen stats when bounds are present.

**Measured**

- Sparse 3-cell change on 160×50: **589 µs** plan+encode for **24 B** on the wire.  
- Same class of damage via bounded ANSI `renderDiff`: **4.8 µs**.  
- At 60 fps, 589 µs is **~3.5% of one core** for plan alone on a single sparse frame — before build/layout/paint/semantics.

**Evidence**

- `packages/fleury/lib/src/remote/remote_driver.dart` `presentFrame` (~175–202).  
- `packages/fleury/lib/src/remote/remote_codec.dart` `buildRemotePlan` (~480–524).  
- Throwaway experiment output (this audit).  
- Prior note in `perf-pass-findings.md` §3 (“3 full O(cols×rows) scans … ignoring diffBounds”) — **still true for CPU**; scroll-up optimization improved **bytes**, not the full-scan baseline.

**Assumption challenged**

“Sparse UI updates are cheap on both terminal and serve presenters.”

**First-principles rationale**

Serve is a launch surface. CPU on the host under multi-session spawn (see bug audit F8) multiplies this cost. Shipping 24 B while scanning 8000 cells every frame is classic “diff ignored the damage map.” Fixing this is the largest **serve CPU** lever remaining that is not already gated by deflate/semantics cliffs.

**Recommended fix**

Thread `FramePresentationPlan` / paint damage rows into `buildRemotePlan` (or skip scroll detect when damage is a small row set). Gate with a microbench: sparse 160×50 plan CPU ≤ N µs (and still byte-correct vs full scan oracle).

---

#### P3 — Full-scan `screenDiffStats` remains a hot cost when bounds are absent

| Field | Detail |
| --- | --- |
| **Severity** | **high** (large viewports / unbounded diffs) |
| **Priority** | P0 as a design invariant; mitigated on happy ANSI path |
| **Class** | Confirmed hot path (measured + profiled) |

**What happens**

`screenDiffStats` always walks every cell. It is:

- Called by unbounded `AnsiRenderer.renderDiff` before scroll detection.  
- Called by `buildRemotePlan` (P2).  
- Visible as **#3 exclusive project sample** on SB.6 VM profile (`scroll_detection.dart`).

**Measured costs**

| Size | µs/call | Share of 16.7 ms |
| --- | --- | --- |
| 80×24 | 29 | 1.7% |
| 160×50 | 120 | 7.2% |
| 200×60 | 178 | 10.7% |

Bounded ANSI path skips this entirely (~180× win on sparse 160×50).

**Assumption challenged**

“Diff cost scales with dirty region, not viewport.”

**First-principles rationale**

Users run wide panes and multi-pane dashboards. A constant full-grid tax before any cursor motion is paid **even when one metric cell changed**, unless damage bounds flow through. Launch-robust means sparse updates stay sparse end-to-end.

**Recommended fix**

1. Ensure production ANSI always supplies conservative damage bounds (audit cases that null them).  
2. Same for serve (P2).  
3. Optional: row-set based stats using `paintDamageRows` before full fallback.

---

#### P4 — Perf gates are not CI-enforced; local suite can fail silently

| Field | Detail |
| --- | --- |
| **Severity** | **high** (process / launch integrity) |
| **Priority** | P0 process |
| **Class** | Confirmed tooling gap |

**What happens**

1. `.github/workflows/check.yml` runs analyze + test + dart2js smoke — **no** `benchmark gates`, `wire-gate`, or `serve-wire-live` (documented in `perf-gates.md` as intentional with SDK-pin caveat).  
2. `dart tool/fleury_dev.dart benchmark local all` printed **SB.8 fail** but returned **exit code 0**.  
3. `benchmark wire-gate --gate` fails usage (`unknown argument: --gate`) while other gates accept `--gate` — easy for agents/docs to think wire was gated when it was not.

**Evidence**

- `docs/implementation/perf-gates.md` “CI status” section.  
- This audit’s command logs (SB.8, wire-gate --gate).  
- `tool/fleury_dev.dart` / `profiling/bin/fleury_wire_gate.dart` CLI surface.

**Assumption challenged**

“If CI is green and someone ran the usual check, performance cannot have regressed.”

**First-principles rationale**

Gates that only run when a careful human remembers them are not launch safety. Combined with P1, a contributor can see `local all` “complete” with exit 0 while a launch scenario is red.

**Recommended fix**

1. Pin CI SDK → add job for fast gates (`serve-semantics`, `image-bench`, `bundle-size`, `alloc-gate`).  
2. Nightly / pre-release: `wire-gate` + `serve-wire-live`.  
3. `benchmark local` / scoreboard: **non-zero exit** if any `pass: false`.  
4. Align CLI: either accept `--gate` on wire-gate (no-op, always gates) or fix docs/help.

---

### P1 — Should fix for robust launch performance

---

#### P5 — Cell allocation dominates per-frame package churn

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 |
| **Class** | Architectural cost (gated, not regressing) |

**What happens**

Alloc-gate steady-state: **6043.8 B/frame**, of which ~**1.23 MB / 400 frames** is `Cell` (~51%), then `CellRect` / `CellOffset` / `Semantics` / `CellStyle` / `Text`. Cells are immutable (`Cell.leading` etc.); every paint write allocates.

**Evidence**

- `profiling/bin/alloc_gate.dart` scenario + baseline `profiling/alloc_gate_baseline.json`.  
- SB.6 profile top allocations: `Cell`, then element/semantics types (includes mount mass).

**Assumption challenged**

“Per-frame GC pressure is negligible for 60 fps TUIs.”

**First-principles rationale**

6 KiB/frame × 60 ≈ 360 KiB/s project-only, before dart:core and widgets packages. Fine for many apps; under dense full-screen animation or large viewports, Cell churn + full clear (P11) is the FPS ceiling. The gate prevents *regression*; it does not lower the floor.

**Recommended fix**

Not a day-0 panic. Medium-term: reuse empty cells already const; consider flyweight for identical leading cells; paint-only paths that mutate less of the buffer. Any intentional alloc improvement must `--update-baseline`.

---

#### P6 — Default `frameInterval = Duration.zero` (uncapped frame rate)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 for streaming / log-tail / agent UIs |
| **Class** | API default risk |

**What happens**

`runApp` / `FrameScheduler` default `minFrameInterval` is zero: first request in a turn schedules a microtask; same-turn coalescing works, but **across turns** a high-rate `setState` stream can render every event-loop turn without a 16 ms floor. Docs advertise `frameInterval: Duration(milliseconds: 16)` for ~60 fps caps — opt-in.

**Evidence**

- `run_app.dart` default `frameInterval = Duration.zero`.  
- `frame_scheduler.dart` comments on coalescing vs rate cap.

**Assumption challenged**

“Burst updates naturally collapse to display rate.”

**First-principles rationale**

WAN SSH and serve wire cost scale with **frame count**. Uncapped producers create more plan/ANSI frames than the eye needs and stress P2/P3. A launch-recommended default for streaming demos (or serve spawn templates) should cap; pure interactive keystroke apps can stay zero.

**Recommended fix**

Document prominently; consider 16 ms default for `fleury serve --spawn` demos; keep zero for library default if API stability requires, but ship example apps with a cap.

---

#### P7 — Wire-gate CLI rejects `--gate` (docs / agent footgun)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (tooling) |
| **Priority** | P1 |
| **Class** | Confirmed CLI inconsistency |

**What happens**

Help text groups gates as `benchmark <gate> [--gate]`. `wire-gate` always gates and does **not** accept `--gate` (exit 64 usage). A scripted `wire-gate --gate` fails without measuring anything — and shell pipelines can still report exit 0 if not `set -e` careful.

**Recommended fix**

Accept and ignore `--gate` on wire-gate / serve-wire-live for uniformity, or fix help to list per-gate flags.

---

#### P8 — SB.6 wire baseline is stale (measured −20%)

| Field | Detail |
| --- | --- |
| **Severity** | **low** |
| **Priority** | P1 hygiene |
| **Class** | Baseline drift (improvement) |

**What happens**

wire-gate SB.6: totalBytes **87229** vs baseline **109059** (−20%). Gate **warns** on improvement; does not fail. Leaving a loose baseline means a future +15% regression from the *new* reality can still pass against the old number until it crosses +15% of 109k.

**Recommended fix**

`benchmark wire-gate --update-baseline` in a deliberate PR after confirming the improvement is intentional (ambiguous-width narrow path, sync skip, etc.).

---

#### P9 — No true input→paint latency gate (G4 still open)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (coverage) |
| **Priority** | P1 |
| **Class** | Coverage gap (from perf-pass-findings; still open) |

**What happens**

Scenario metrics use in-VM proxies (`command_to_frame_us`, etc.). No harness timestamps an injected PTY/WS event through to the frame that reflects it on the real output channel.

**Why launch**

WAN SSH and serve UX are latency products. Without p95 input→frame, regressions hide behind byte gates.

**Recommended fix**

Extend serve-wire-live or PTY capture: inject key → wait for content hash change → record delay; gate p95.

---

#### P10 — Backpressure / producer-gate unmeasured under slow peer (G5)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (coverage) |
| **Priority** | P1 |
| **Class** | Coverage gap |

**What happens**

`FrameDriver` defers production when `OutputFlowControl.isOutputBacklogged` — correctness-tested, not perf-characterized (bytes saved, drain latency, sustained FPS under throttle).

**Why launch**

Slow browser or SSH is exactly when backpressure must reduce work (ties to P2/P6). Unmeasured means we cannot prove the gate helps.

**Recommended fix**

Throttled client in `serve-wire-live`; report frames produced vs would-have-produced.

---

### P2 — Lower urgency / intentional

---

#### P11 — Full back-buffer clear every frame

| Field | Detail |
| --- | --- |
| **Severity** | **low** / intentional |
| **Priority** | P2 |
| **Class** | Design tradeoff |

**What happens**

`TuiFrameLoop.render` clears the entire back buffer under `withoutDamageTracking` before paint. Correct for sparse painters that only write dirty widgets; cost is O(cells) fill + later Cell allocations on rewrite.

**Assumption challenged**

“Only dirty cells are touched each frame.”

**Rationale**

Clearing is the simple correctness model. Optimizing to “retain previous pixels and paint dirty only” is a large change; RepaintBoundary already skips subtrees when used. Note only.

---

#### P12 — Fast `gates` suite omits wire + serve-live

| Field | Detail |
| --- | --- |
| **Severity** | **note** |
| **Priority** | P2 |
| **Class** | Intentional (documented) |

Heavy PTY/subprocess gates are explicit-only (~30s each). Fine if pre-release checklist includes them; bad if “gates green” is over-read as “all perf green.”

---

#### P13 — Local scenario latency thresholds still candidate / unenforced

| Field | Detail |
| --- | --- |
| **Severity** | **note** |
| **Priority** | P2 |
| **Class** | Process |

Most scenarios set `"enforced": false` on candidate p95 maps. Correctness flags (SB.8) do fail the scenario object; pure latency regressions may not. When baselines stabilize, flip enforcement for a small critical set (SB.4, SB.5, SB.6, SB.8).

---

## What is already solid (do not re-litigate)

| Area | Status |
| --- | --- |
| Image encoder zero-image + static dedup | Gate green (`image-bench`) |
| Semantics wire anti-cliff (DEFLATE) | Gate green; flat in tree size |
| Serve live raw+deflated totals | Gate green vs baseline |
| Terminal wire SB.1/6/9 | Gate green; SB.6 improved |
| Alloc-gate infrastructure | Deterministic, baselined, SDK-sensitive (documented) |
| Layout skip / dirty layout cache | SB.12 pass; prior sublinear reconcile tax holds |
| Microtask frame coalescing | Present; rate cap optional |
| Bundle size | 316 / 78 KiB under 512 / 160 limits |
| Ambiguous-width capability gating | Prior +60% SB.6 byte bug remains fixed (bytes improved further) |

---

## Prioritized recommendations

### Must before launch performance claims

1. **Fix SB.8** (P1) — treat as correctness P0; do not ship “palette/overlay ready” while red.  
2. **Damage-bound serve plans** (P2) — align `buildRemotePlan` with ANSI dirty bounds; add CPU micro-gate.  
3. **Audit unbounded ANSI callers** (P3) — never null `dirtyBounds` on steady-state paint-only frames without cause.  
4. **Process honesty** (P4) — non-zero exit on failed local scenarios; accept `--gate` on wire-gate; plan CI fast gates after SDK pin.  
5. **Re-baseline wire SB.6** (P8) so regressions are measured against current reality.

### Should for robust streaming / serve

6. Cap frame rate in streaming demos / serve templates (P6).  
7. Input→frame latency harness (P9).  
8. Slow-peer backpressure characterization (P10).  
9. Longer-term Cell/paint alloc reduction (P5) only with baselines.

### Can wait

10. Full retained-buffer paint (avoid clear) — large design.  
11. Enforcing all candidate local latency thresholds — after SB.8 and baselines stabilize.  
12. Peer scoreboard expansion — not a launch gate.

---

## Suggested sequencing

```
1. SB.8 root-cause + fix + keep scenario hard-fail
2. local suite exit non-zero on pass:false  (same PR or follow-up)
3. buildRemotePlan(damage) + microbench oracle vs full scan
4. wire-gate --update-baseline (SB.6) after confirming intentional
5. CLI --gate uniformity + docs
6. CI: pin SDK → fast gates job
7. G4/G5 harnesses on serve-wire-live
```

---

## Relation to bug audit (2026-07-08)

| Bug audit item | Perf interaction |
| --- | --- |
| Serve spawn no session cap (F8) | Multiplies P2 CPU per session |
| No INIT timeout (F9) | Hung processes still allocate |
| Layout dispose hole (F1) | Leaked State → timer/ticker frames |
| Dirty-queue stranding (F2) | “Frozen UI” misread as perf hang |
| OSC 52 / TTY issues | Not perf; do not conflate |

---

## What this audit is not

- Not a peer competitive ranking rewrite  
- Not re-baselining committed without review (only recommends)  
- Not implementing the serve damage-bound optimization  
- Not Windows perf  
- Not exhaustive Chrome web-suite re-run (serve client bundle-size only)

---

## Related docs

| Doc | Role |
| --- | --- |
| [perf-gates.md](perf-gates.md) | Gate inventory, triggers, CI plan |
| [perf-pass-findings.md](perf-pass-findings.md) | July 2 pass; several gaps now closed, P2/G4/G5 still open |
| [serve-production-readiness.md](serve-production-readiness.md) | Wire byte narrative |
| [launch-bug-audit-2026-07-08.md](launch-bug-audit-2026-07-08.md) | Correctness companion |
| [Claude.md](../../Claude.md) | Which gates to run after which paths |

---

## Evidence index

Captured under the implementer scratch `perf-audit/` directory during this audit:

```
gates-fast.log              # fast suite PASS
wire-gate-2.log             # wire-gate PASS (SB.6 −20%)
wire-gate.log               # failed --gate CLI misuse
serve-wire-live.log         # serve-wire-live PASS
local-all.json.log          # local all; SB.8 fail
sb8-rerun.log               # SB.8 fail reproduced
profile-sb6.log             # VM profile summary
sb6-vm-profile.json         # full profile artifact
exp-diffstats.out           # screenDiffStats timings
exp-remote-plan.out         # buildRemotePlan timings
exp-render-diff.out         # bounded vs full renderDiff
```
