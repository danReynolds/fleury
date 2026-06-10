# Fleury Web: Path to Industry-Leading Architecture & Performance

Status: plan accepted as the working roadmap (2026-06-10). Owner: advisory
engagement. Companion to `docs/rfcs/web-render-backend.md`,
`docs/rfcs/semantics-pipeline.md`, and the execution log.

## Definition of done — the sign-off bar

"Industry-leading and modern" is claimed when ALL of the following hold:

**Performance (measured, median-of-3, browser-inclusive once Phase 5 lands):**

- P-1. Visual-pipeline steady p95 ≤ 16.67ms on every scenario except
  `full-frame-churn` and `stress`, which get explicit documented budgets
  (target ≤ 33ms / 2-frame; see Phase 3 exit).
- P-2. Semantic presentation runs on its own latency budget: ≤ 100ms p95
  from visual commit to semantic DOM flush, never blocking the visual frame.
- P-3. Steady over-budget frame rate ≤ 5% per scenario, and any over-budget
  frame is attributable (flat build stats + dominant GC/VM slice) — no
  over-budget frame caused by framework work.
- P-4. No-change frames (noop) cost < 1ms p95 of script work.
- P-5. Startup: no frame over 50ms after the third frame; first interactive
  frame budget defined and gated (Phase 7 sets the number from data).
- P-6. Gates expressed on browser-inclusive frame time (CDP tracing), not
  Dart script time alone.

**Architecture:**

- A-1. Semantic presentation decoupled from the rAF visual frame
  (deadline-aware, coalescing, force-flush before semantic action dispatch
  and focus/AT queries).
- A-2. No static global frame state: dirty/damage trackers owned per
  runtime; two concurrent `runTuiSurface` hosts on one page verified
  isolated by test.
- A-3. Damage model graduated from single union rect to multi-range rows;
  `rowsReplaced` equals true dirty-row count on scattered updates.
- A-4. Retained-vs-full semantics divergence oracle and escalation-edge
  tests kept green in CI permanently.
- A-5. IME (`chrome-ime-macos` 6/6) and VoiceOver manual evidence recorded
  via the manual-validation machinery.
- A-6. DOM host is the package default and the xterm-compatible path is
  retired (the two bundle-bound preflights pass).

## Where we are (2026-06-10 baseline, median-of-3 capture p95, ms)

| Tier | Scenario | Total p95 | Visual-side drivers | semanticApply |
|---|---|---|---|---|
| Row-local | dirty-row | 52.8 | build 9.3, paint 12.3 | 25.5 |
| Row-local | single-dirty-cell | 61.0 | build 18.1, paint 8.6 | 15.8 |
| Row-local | noop | 20.9 | paint 9.6 (!) | 0.1 |
| Moderate | large | 47.8 | build 9.9, paint 12.2 | 26.2 |
| Moderate | cursor-blink | 112.4 | build 49.5 | 37.3 |
| Moderate | text-input-burst | 111.6 | build 7.7, domApply 10.7 | 30.4 |
| Heavy | normal-80x24 | 261.7 | paint 73.5, build 53.8, span 28.3 | 137.9 |
| Heavy | full-frame-churn | 385.9 | build 61.0, domApply 37.3, span 15.6 | 117.4 |
| Heavy | scroll-row-churn | 393.4 | build 141.8, paint 60.0 | 52.0 |
| Heavy | resize-burst | 630.0 | paint 80.9, build 51.0 | 106.1 |
| Heavy | stress-300x100 | 487.7 | build 145.0, paint 101.3, domApply 89.7 | 183.0 |

(Per-slice p95s don't co-occur, so rows overstate any single frame — but
several slices blow the 16.67ms budget alone.)

Two structural conclusions drive the phase order:

1. `semanticApply` is the dominant single slice in most scenarios →
   Phase 2 (decouple) is the highest-leverage single change.
2. Deferred semantics is NOT sufficient for the heavy tier: `runtimeBuild`
   (142ms on scroll) and `runtimePaint` (101ms on stress) are visual-side
   framework costs → Phase 3 (visual throughput) is mandatory for the
   sign-off bar, and `noop` paint at 9.6ms means even no-change frames do
   paint work they shouldn't.

## Phases

### Phase 0 — Human gate + merge (prereq, mostly Dan)

- Dan promotes candidate thresholds (command + fingerprint in
  `profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review-plan.md`),
  re-run readiness bundle.
- RFC re-review using `web-rfc-review-packet.md`; merge
  `codex/fleury-web-phase1` to main. Follow-up phases land as normal
  reviewed branches on main.
- Exit: branch merged; reviewed thresholds in place as the regression floor.

### Phase 1 — De-globalize frame-state trackers (arch enabler; ~1 session)

- Move `SemanticDirtyTracker` and `RenderDamageTracker` from static globals
  to instances owned by `TuiRuntime` (threaded to render objects via their
  owner/binding, to `SemanticsElement` via its binding).
- Add accumulate-across-frames semantics to the dirty tracker (sticky
  escalation until flushed) — required by Phase 2 coalescing.
- Exit gate: two `runTuiSurface` hosts on one page in a Chrome test with no
  dirty-state cross-talk (A-2); all suites green; benchmarks unchanged
  within noise.

### Phase 2 — Semantics off the visual frame (the structural fix; ~2-3 sessions)

Design:

- rAF callback ends at visual present + commit + caret-geometry sync
  (caret stays frame-synced: IME-critical, cheap).
- Semantic pass becomes a deferred task (post-frame scheduling with a
  deadline cap, injected `SemanticFlushScheduler` for deterministic tests)
  consuming the accumulated dirty snapshot + the committed front buffer for
  coverage scanning.
- Coalescing: N visual frames → 1 semantic flush computed from the current
  element tree (intermediate states intentionally skipped).
- Force-flush paths: semantic action dispatch, focus/AT queries, dispose.
- Divergence assertion moves to the flush point. Instrumentation gains
  `semanticFlushLatencyMs` + `coalescedFrameCount`; budget gates split per
  P-1/P-2. Benchmark harness drives + awaits semantic quiescence and
  reports both budgets.
- Risk: `run_tui_surface_test.dart` churn (tests assume same-frame
  semantics) — mitigated by the injectable scheduler; semantic staleness
  visible to AT bounded by the 100ms cap + force-flush.
- Exit gate: P-2 met on all scenarios; row-local + moderate tiers meet P-1
  for the visual pipeline; no semantics slice inside the rAF timing.

### Phase 3 — Visual render throughput for the heavy tier (~2-3 sessions)

Ordered by expected leverage:

- **Noop paint bug**: a no-change frame spends 9.6ms p95 in paint —
  diagnose why paint runs at all (repaint-boundary caching / frame-request
  short-circuit); fix → P-4.
- **Scroll shift reuse**: scroll currently rebuilds + repaints + replaces
  every row (build 141.8ms). The terminal path already does scroll
  detection for ANSI; give the DOM path the equivalent — detect row-shift
  in the damage/diff layer and MOVE retained row elements (reorder +
  patch edges) instead of rebuilding all spans. Pair with a widget-level
  story (row recycling or buffer-level scroll primitive) to cut the build
  slice.
- **Span-level patching**: `replaceChildren` rebuilds every span in a dirty
  row; patch in place when run structure is stable (textContent/style
  mutation), fall back to replace on structure change.
- **Full-churn budget**: after the above, set the documented budget for
  `full-frame-churn`/`stress` from measurement (target ≤ 33ms visual p95;
  these are adversarial worst cases — peers on DOM renderers do not hold
  16.67ms here either, but the bound must be measured and stated, not
  hand-waved).
- Exit gate: P-1 across the suite with the two documented exceptions
  bounded; scroll-churn visual p95 ≤ 16.67ms.

### Phase 4 — GC/allocation discipline + wasm trial (row-local tails; ~1-2 sessions)

- CDP sampling heap profile of the frame path; kill the top per-frame
  allocators (span model lists, intermediate strings, semantic tree
  wrappers).
- Confirm/diagnose the repeatable ~32ms last-steady-frame
  `semanticTreeBuild` GC spike with 64-128-frame captures.
- **Exploratory**: `dart compile wasm` benchmark target (WasmGC). If the
  tail distribution improves materially, make wasm the recommended
  production target and re-baseline.
- Exit gate: P-3 (≤ 5% over-budget, all attributable); no steady frame
  > 2× budget across 3 runs on row-local scenarios.

### Phase 5 — Honest measurement upgrade (parallel-capable; ~1-2 sessions)

- CDP tracing capture per frame (browser style/layout/paint/composite) →
  browser-inclusive frame time in instrumentation + scoreboard + gates
  (P-6).
- Re-examine Chrome flags (`--disable-gpu` off for at least one recorded
  config); longer captures (64+ frames) as the standard; keep warmup-8
  convention.
- Exit gate: gates re-expressed browser-inclusive; one re-baselined
  promoted evidence set.

### Phase 6 — Damage model graduation (~1 session)

- Replace the single union-rect producer with banded row damage (bitset or
  range list per frame) end-to-end: CellBuffer → `TuiFrameDamage` →
  presentation plan.
- Add a scattered-dirty benchmark scenario (e.g. 5 disjoint dirty rows on
  160x50).
- Exit gate: A-3 (`rowsReplaced` == true dirty rows on the scattered
  scenario); no regression elsewhere.

### Phase 7 — Warmup / first-frame story (~1 session)

- Decompose the 50-240ms first frames (dart2js cold start, first full DOM
  build, cold style caches, first semantic build — the last is free after
  Phase 2).
- Cheap wins first (pre-warmed style cache, deferred first semantics);
  set the startup budget from the resulting data and gate it (P-5).

### Phase 8 — Accessibility evidence + release actions (manual + ~1 session)

- Run the `chrome-ime-macos` manual checklist (6 checks) and a VoiceOver
  pass; record via `web-manual-validation` tooling (A-5).
- Re-run readiness bundle; execute the two bundle-bound preflights:
  `make-dom-default`, then `retire-temporary-paths` (xterm path removal)
  (A-6).
- Optional but recommended for the "industry-leading" claim externally: a
  public side-by-side demo vs xterm.js (accessibility tree + perf capture)
  — ties to the engagement's "prove standing" priority.

## Sequencing

```
Phase 0 (Dan) ─→ merge
Phase 1 ─→ Phase 2 ─→ Phase 3 ─→ Phase 4 ─→ re-baseline ─→ Phase 7
                 │                                │
Phase 5 (parallel from Phase 2 on) ───────────────┘
Phase 6 (independent; ideally before Phase 3 scroll work)
Phase 8 last (needs stable everything)
```

Rough total: 9-13 working sessions of agent time plus Dan's review gates
and the manual accessibility passes.

## Risk register

- **Semantic staleness window (Phase 2)**: AT reads between visual commit
  and semantic flush see ≤ 100ms-old tree. Mitigation: latency cap,
  force-flush on action/focus, caret stays frame-synced.
- **Test churn (Phase 2)**: same-frame semantics assumptions in ~24 Chrome
  tests. Mitigation: injectable flush scheduler; rewrite assertions to
  "after flush".
- **GC tails may not fully yield to allocation work (Phase 4)**: dart2js +
  V8 GC has a floor. Fallbacks: wasm target trial; if still bounded, the
  attribution-based gate (P-3) is the honest stance and stays.
- **Scroll-shift detection complexity (Phase 3)**: DOM row reordering must
  preserve focus/selection/semantic mapping. Mitigation: land behind the
  existing presentation-plan seam with equivalence tests against the
  non-shifted path.
- **Two regressed-looking scenarios (normal-80x24, resize-burst)** are
  variance-dominated today; Phase 5's browser-inclusive, longer captures
  make their numbers trustworthy before Phase 3 declares victory on them.
