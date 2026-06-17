# Fleury Frame Path: Industry-Leading Performance & Architecture Plan

Status: working roadmap v2 (2026-06-10). Owner: advisory engagement.
Companion to `docs/rfcs/web-render-backend.md`,
`docs/rfcs/semantics-pipeline.md`, and the execution log.

## Scope

**In scope:** performance and architecture of the frame path — and that
means BOTH packages. The web benchmark slices attribute the heavy-tier
cost to `runtimeBuild` (element reconciliation) and `runtimePaint`
(render-object painting), which are `packages/fleury` core code measured
through the web host. The trackers, damage model, semantics production,
and frame loop are all core. This plan is therefore a **core frame-path
upgrade driven by web gates**: the web harness is the best per-phase
instrumentation Fleury has, and because native and web share
`TuiRuntime`/`TuiFrameLoop`, every core win lands on the terminal target
for free. Core-touching phases carry a terminal-parity check.

**Out of scope (explicitly, per maintainer direction 2026-06-10):**

- Manual accessibility evidence, IME, and VoiceOver validation — deferred
  roadmap items, not part of this plan's bar.
- Release actions (`make-dom-default`, `retire-temporary-paths`) — they
  depend on manual evidence by design and stay parked with it.
- A **general core audit** (widgets API surface, effects system, app
  kernel, text editing, DX cohesion). Deliberately deferred: it is a
  different kind of work, and it will be strictly better-informed after
  this plan lands (modernized runtime bones, far richer instrumentation).
  This plan IS the core perf/arch upgrade for the frame path; the general
  audit picks up everything the frame path doesn't touch.

## Definition of done — the sign-off bar

**Performance (measured, median-of-3, browser-inclusive once Phase 5 lands):**

- P-1. Visual-pipeline steady p95 ≤ 16.67ms on every scenario except
  `full-frame-churn` and `stress`, which get explicit documented budgets
  (target ≤ 33ms; see Phase 3 exit).
- P-2. Semantic presentation on its own latency budget: ≤ 100ms p95 from
  visual commit to semantic DOM flush, never blocking the visual frame.
- P-3. Steady over-budget frame rate ≤ 5% per scenario, and every
  over-budget frame attributable (flat build stats + dominant GC/VM
  slice) — none caused by framework work.
- P-4. No-change frames (noop) cost < 1ms p95 of script work.
- P-5. Startup: no frame over 50ms after the third frame; first
  interactive frame budget set from Phase 7 data and gated.
- P-6. Gates expressed on browser-inclusive frame time (CDP tracing), not
  Dart script time alone.
- P-7. Terminal parity: the native benchmark suite (profiling/ harness)
  shows no regression at each core-touching phase, and core wins are
  measured on the native target too.

**Architecture:**

- A-1. Semantic presentation decoupled from the rAF visual frame
  (deadline-aware, coalescing, force-flush before semantic action
  dispatch and focus queries).
- A-2. No static global frame state in core: dirty/damage trackers owned
  per runtime; two concurrent hosts on one page verified isolated by test.
- A-3. Damage model graduated from single union rect to multi-range rows
  end-to-end (core producer → host consumer); `rowsReplaced` equals true
  dirty-row count on scattered updates.
- A-4. Retained-vs-full semantics divergence oracle and escalation-edge
  tests kept green in CI permanently.

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

Structural conclusions driving the phase order:

1. `semanticApply` is the dominant single slice in most scenarios →
   Phase 2 (decouple) is the highest-leverage single change. (Host-led,
   core-assisted.)
2. Deferred semantics is NOT sufficient for the heavy tier: `runtimeBuild`
   and `runtimePaint` are CORE costs that blow the budget alone →
   Phases 3-4 are core work, mandatory for the bar.
3. `noop` paint at 9.6ms means no-change frames do core paint work they
   shouldn't — likely the cheapest meaningful win on the board.

## Core vs web split by phase

| Phase | packages/fleury (core) | packages/fleury_web (host) |
|---|---|---|
| 1 Trackers | Instance-owned trackers threaded via runtime/binding; accumulate semantics | Consume per-runtime instances |
| 2 Deferred semantics | Sticky dirty accumulation; flush contract on SemanticsOwner; action-dispatch flush hook | Flush scheduler, coalescing, latency instrumentation, benchmark harness updates |
| 3 Visual throughput | Noop-paint fix (repaint-boundary/frame short-circuit); build-cost levers (reconciliation, recycling, scroll primitive); paint-path cost; scroll-shift damage signal | Row-move DOM application; span-level patching |
| 4 GC/allocation | Build/layout/paint/semantic-production allocations | Span model allocations; wasm build target trial |
| 5 Measurement | — | CDP tracing, GPU-on config, longer captures |
| 6 Damage granularity | CellBuffer banded row damage → TuiFrameDamage multi-range | Plan consumption; scattered-dirty scenario |
| 7 Warmup | First-build cost | Cold caches, startup capture + budget |

## Phases

### Phase 0 — Gate hygiene + merge (prereq, mostly Dan)

- Dan promotes candidate thresholds (command + fingerprint in
  `profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review-plan.md`),
  re-run readiness bundle.
- RFC re-review using `web-rfc-review-packet.md`; merge
  `codex/fleury-web-phase1` to main. Follow-up phases land as reviewed
  branches on main.
- Establish the native-side parity baseline: run the existing terminal
  profiling harness once at the merge point so P-7 has a reference.
- Exit: branch merged; reviewed thresholds as regression floor; native
  parity baseline recorded.

### Phase 1 — De-globalize frame-state trackers (core; ~1 session)

- Move `SemanticDirtyTracker` and `RenderDamageTracker` from static
  globals to instances owned by `TuiRuntime`, threaded to render objects
  via their owner and to `SemanticsElement` via its binding.
- Add accumulate-across-frames semantics (sticky escalation until
  flushed) — required by Phase 2 coalescing.
- Exit gate: two `runTuiSurface` hosts on one page in a Chrome test with
  no dirty-state cross-talk (A-2); all suites green; web benchmarks within
  noise; native parity run clean (P-7).

### Phase 2 — Semantics off the visual frame (host-led, core-assisted; ~2-3 sessions)

- rAF callback ends at visual present + commit + caret-geometry sync
  (caret stays frame-synced: input-critical, cheap).
- Semantic pass becomes a deferred task (post-frame scheduling with a
  deadline cap; injectable `SemanticFlushScheduler` for deterministic
  tests) consuming the accumulated dirty snapshot + committed front
  buffer for coverage scanning.
- Coalescing: N visual frames → 1 semantic flush computed from the
  current element tree.
- Force-flush paths: semantic action dispatch, focus queries, dispose.
- Divergence assertion moves to the flush point. Instrumentation gains
  `semanticFlushLatencyMs` + `coalescedFrameCount`; budgets split per
  P-1/P-2; benchmark harness drives + awaits semantic quiescence.
- Risks: test churn in same-frame-semantics assertions (mitigated by the
  injectable scheduler); staleness bounded by the 100ms cap + force-flush.
- Exit gate: P-2 met on all scenarios; row-local + moderate tiers meet
  P-1 for the visual pipeline.

### Phase 3 — Visual render throughput (core-heavy; ~2-3 sessions)

Ordered by expected leverage:

- **Noop paint fix (core)**: no-change frames spend 9.6ms p95 in paint —
  diagnose (repaint-boundary caching / frame-request short-circuit in
  `TuiRuntime.renderFrame`/`TuiFrameLoop`) and fix → P-4. Benefits every
  target and every scenario's idle frames.
- **Scroll shift reuse (core + host)**: scroll rebuilds + repaints +
  replaces every row (build 141.8ms). The ANSI renderer already does
  scroll detection; lift the equivalent into the shared damage layer
  (core emits a row-shift signal in `TuiFrameDamage`) so the DOM host
  MOVES retained row elements and the terminal renderer keeps its scroll
  fast path from one source of truth. Pair with a build-side story (row
  recycling or a buffer-level scroll primitive) to cut reconciliation
  cost.
- **Build-cost levers (core)**: profile `runtimeBuild` on scroll/stress;
  extend the existing reconciliation fast paths (`WidgetUpdatePruner`,
  stable-unkeyed-children) where the data points.
- **Span-level patching (host)**: patch spans in place when run structure
  is stable instead of `replaceChildren`; fall back on structure change.
- **Adversarial budgets**: after the above, set the documented budgets
  for `full-frame-churn`/`stress` from measurement (target ≤ 33ms visual
  p95) — stated bounds, not hand-waving.
- Exit gate: P-1 across the suite with the two documented exceptions;
  scroll-churn visual p95 ≤ 16.67ms; native parity run shows the scroll/
  build wins on the terminal target too (P-7).

### Phase 4 — GC/allocation discipline + wasm trial (core-heavy; ~1-2 sessions)

- CDP sampling heap profile of the frame path; kill the top per-frame
  allocators (build/layout/paint allocations, semantic tree production,
  span model lists).
- Confirm/diagnose the repeatable ~32ms last-steady-frame
  `semanticTreeBuild` GC spike with 64-128-frame captures.
- **Exploratory**: `dart compile wasm` benchmark target (WasmGC). If tail
  distribution improves materially, make wasm the recommended production
  web target and re-baseline.
- Exit gate: P-3 (≤ 5% over-budget, all attributable); no steady frame
  > 2× budget across 3 runs on row-local scenarios.

### Phase 5 — Honest measurement upgrade (host tooling; parallel from Phase 2; ~1-2 sessions)

- CDP tracing capture per frame (browser style/layout/paint/composite) →
  browser-inclusive frame time in instrumentation, scoreboard, and gates
  (P-6).
- Re-examine Chrome flags (`--disable-gpu` off for at least one recorded
  config); longer captures (64+ frames) as standard; keep warmup-8.
- Exit gate: gates re-expressed browser-inclusive; one re-baselined
  promoted evidence set.

### Phase 6 — Damage model graduation (core → host; ~1 session; ideally before Phase 3 scroll work)

- Replace the single union-rect producer with banded row damage (bitset
  or range list) end-to-end: CellBuffer → `TuiFrameDamage` →
  presentation plan. The native bounded-diff path consumes the same
  ranges (P-7 win).
- Add a scattered-dirty benchmark scenario (e.g. 5 disjoint dirty rows on
  160x50).
- Exit gate: A-3; no regression elsewhere.

### Phase 7 — Warmup / first-frame story (~1 session)

- Decompose the 50-240ms first frames (dart2js cold start, first full
  build, cold style caches; first semantic build is free after Phase 2).
- Cheap wins first (pre-warmed style cache, deferred first semantics);
  set the startup budget from resulting data and gate it (P-5).

## Sequencing

```
Phase 0 (Dan) ─→ merge + native parity baseline
Phase 1 ─→ Phase 2 ─→ Phase 3 ─→ Phase 4 ─→ re-baseline ─→ Phase 7
                 │         ▲                      │
Phase 5 (parallel) ────────┼──────────────────────┘
Phase 6 ───────────────────┘  (feeds Phase 3 scroll work)
```

Rough total: 9-12 working sessions of agent time plus Dan's review gates.

## Relationship to the future general core audit

This plan upgrades core's **frame path**: build reconciliation cost,
paint/repaint caching, damage production, semantics production, frame
state ownership, allocation behavior — validated on two render targets
with per-phase instrumentation. What it deliberately does NOT touch:
widget API surface and DX cohesion, effects/process model, app kernel,
text-editing engine, capability security. Those belong to the general
core audit, which should run AFTER this plan: it will inherit a
modernized runtime, two-target benchmark evidence, and instrumentation
that makes its own claims testable.

## Risk register

- **Semantic staleness window (Phase 2)**: AT/queries between visual
  commit and semantic flush see a ≤ 100ms-old tree. Mitigation: latency
  cap, force-flush on action/focus, caret stays frame-synced.
- **Test churn (Phase 2)**: same-frame semantics assumptions in ~24
  Chrome tests. Mitigation: injectable flush scheduler.
- **GC tails may not fully yield (Phase 4)**: dart2js + V8 GC has a
  floor. Fallbacks: wasm trial; if still bounded, the attribution-based
  gate (P-3) is the honest stance and stays.
- **Scroll-shift complexity (Phase 3)**: DOM row reordering must preserve
  focus/selection/semantic mapping; the shared damage signal must not
  regress the ANSI scroll path. Mitigation: land behind the
  presentation-plan seam with equivalence tests against the non-shifted
  path on both targets.
- **Core churn risk**: Phases 1/3/4/6 touch the runtime shared with the
  terminal target. Mitigation: P-7 parity runs at every core-touching
  phase; the 1593-test core suite + divergence oracle as the safety net.
- **Variance-dominated scenarios (normal-80x24, resize-burst)**: Phase
  5's browser-inclusive, longer captures make their numbers trustworthy
  before Phase 3 declares victory on them.
