# Architecture Priorities

**Status:** Living priority list (arch track)
**Last updated:** 2026-06-04
**Frame:** Architecture + feature set + DX first; performance ballpark, not
beat-native. Pre-launch — the breaking-change window is open, so API-shape
decisions are timing-sensitive.

Legend: ✅ done · ▶ active · ⏸ gated (needs a product/posture decision first) ·
🔒 resolved (no work).

The spine across most of this: **precise invalidation / minimal work** — the
three-tree, an eventual live semantic tree, byte-efficient rendering, and frame
coalescing are all "do exactly what changed, nothing more."

---

## 🧭 Re-derived priorities (2026-06-04 frontier refresh)

A bounded competitive/frontier research pass (live web, sourced) re-derived
priorities. Verdict on the question that triggered it — *is the arch strong
enough that Tier 2 is low priority?* — **yes.** The arch is genuinely strong;
the remaining Tier 2/3 items are incremental gap-fills. The leverage has moved
off "more arch depth" and onto **one frontier we still uniquely own.**

What the research found (all verified w/ sources, mid-2026):
- **fleury's semantic / agent-legible *render-tree* is still unowned.** No TUI
  framework exposes a queryable, machine-readable tree of its rendered UI.
  Accessibility is an industry-wide failure (Bubble Tea a11y issue open since
  2023; Textualize folded; "the text mode lie" essay). Proof of the gap:
  `agent-tui` exists *because* agents must screenshot + scrape ANSI to drive
  TUIs.
- **But the field converged adjacent, not at us:** the momentum is structured
  agent↔frontend *message* protocols — ACP (25+ agents, Zed/JetBrains/MS), Toad,
  goose 2.0. These serialize the agent's I/O stream, **not** the rendered UI
  tree. Complementary to fleury, but it means the coding-agent workload's pull is
  partly satisfied *without* a UI tree.
- **The principle is already won elsewhere:** browser/mobile agents use the
  accessibility tree, not pixels (Playwright MCP: 2–5KB structured vs ~500KB
  screenshots). Validates the intuition — but those are GUI, not terminal.
- **Several fleury "differentiators" have eroded as standalone claims:** testing
  (Nocterm pump/sendKey, Textual pytest-snapshot already do it), retained-
  reactive (Bubble Tea v2 went declarative), capability contracts (Bubble Tea v2
  baked in synchronized output + grapheme correctness), and **raw perf** (OpenTUI
  Zig core + Bubble Tea v2 own perf with *shipped, validated* work — our
  self-graded numbers lose that comparison).

The strategic key: **the SAME semantic tree serves accessibility + agent-drive +
testing.** Betting on any one alone is weak (accessibility has no monetization
precedent — Textualize died; agent-legibility alone risks ACP absorbing it). The
defensible, unowned position is the **intersection**, and as of mid-2026 nobody
is standing there.

Honest asterisks (don't oversell): the semantic-UI-tree need is currently *ahead
of the demand curve* for coding agents (ACP satisfies them at the message
layer); strongest near-term pull is **agents driving third-party/legacy TUIs**
and **accessibility** — smaller, earlier markets. **Toad** (McGugan, same
frontend/backend instinct) is the competitor to watch; still a private prototype,
so the window is open.

### The re-derived list

- **P1 — Make the semantic tree the flagship (was "gated").** Promote the
  incremental/observable semantic tree and build the *convergence*: one live,
  queryable structure that yields (a) an accessibility/screen-reader projection
  (a verifiable "nobody else has this" first — de-risks our self-graded-evidence
  problem by competing on a checkable axis), (b) an agent read/drive surface
  (read state + invoke `SemanticAction`s), (c) test assertions. Tier-1
  freeze-proofing already laid the identity foundation.
- **P2 — Ride ACP, don't fight it.** Stand up `fleury_acp` (already planned
  fast-follow) and position the semantic tree as *complementary*: ACP carries the
  agent stream; fleury exposes the rendered UI as data. Don't reinvent ACP.
- **P3 — Reframe perf, stop racing it.** Recast the byte/frame work as
  correctness/determinism enablers, not a speed race vs OpenTUI/Bubble Tea.
- **P4 — Prove standing (still open).** The self-graded-evidence gap remains;
  the accessibility projection (P1a) is the cheapest verifiable proof point.
- **Demoted to opportunistic gap-fills:** async-compute seam, focus-preservation.
  **Still no:** native render core (OpenTUI owns that cross-language perf lane).
- **Posture call, now informed:** "best-in-class for Dart **and** own the
  semantic-convergence frontier" — which travels as an idea/protocol even though
  the impl is Dart. Cross-language via a native core is a losing race; the
  convergence tree is the cross-language-relevant bet.

The Tier 2/3 lists below remain accurate as a backlog but are subordinate to P1–P4.

## ✅ Completed

- **Paint-only / layout invalidation split** — closed the last conservative
  `markNeedsPaint()` straggler (selection geometry), enforced by a
  falsification-proven guard. 5 relayouts/selection-change → 0.
  `[commit 69414e3]`
- **Byte-budget harness + cursor-move compression** — found cursor positioning
  (not SGR) is the dominant update-frame overhead; relative same-row moves cut
  it 48% → 12% (scroll −20%, total −17%), proven output-equivalent.
  `[commits 69414e3, a66d4cb]`
- **Bytes → latency estimator + live telemetry hook** — `TransportProfile` model
  + `FLEURY_BYTE_TELEMETRY`; hardware capture handed off in
  [byte-latency-handoff.md](byte-latency-handoff.md). `[commit a66d4cb]`
- **(Tier 1) Semantic-tree API freeze-proofing** — key-derived stable node
  identity, an explicit identity contract (`SemanticNodeId` doc), and a
  producer-agnostic snapshot model so an incremental/observable backend won't be
  a breaking change. Guarded by `semantic_identity_test`.
- **(Tier 2) Frame-rate coalescing** — `FrameScheduler` coalesces frame requests
  and an opt-in `runTui(frameInterval:)` caps the render rate so high-rate
  streams / rapid setState collapse to one frame per interval (frame-count is
  the WAN-SSH + agent-streaming latency lever). Default uncapped = unchanged
  behavior; clock-injectable + unit-tested (`frame_scheduler_test`).
- **(Tier 1) Contract-conformance tests** — runtime role-materialization checks
  + a catalog drift guard over the whole 47-widget semantic surface
  (`semantic_contract_conformance_test`). **Capability finding corrected:** the
  audit's "fallback at ~6% = critical drift" was a measurement artifact — color
  and grapheme-width degrade centrally (renderer downsampling + width resolver),
  and the only protocol-gated widgets (Image, MarkdownText, DataTable) already
  declare requirements. No per-widget capability fallback was owed to chart /
  Unicode-glyph widgets; adding it would have been cargo-cult.

## 🔒 Resolved (no work)

- **Three-tree (Widget/Element/RenderObject): keep.** Earns its keep — 46 render
  objects vs 140 component widgets (shallow render tree); caches persist across
  rebuilds. Not a simplification candidate.
- **Native lower-level layer: no, stay pure Dart.** Would break the web target
  and hot reload to optimize a non-bottleneck. Dart AOT is Bubble-Tea-class.

---

## ▶ Active — Tier 1 ✅ complete (2026-06-04)

Both Tier-1 items landed (see Completed). Remaining catalog-cohesion drift that
is *real* (after the capability correction): dead theming defaults and the
3-pattern copy API — these are DX/API-ergonomics items, deferred with the rest
of the API track until after the storybook work, not arch blockers.

## ▶ Active — Tier 2 (additive; address real workloads)

3. **Async-compute seam (`Isolate.run`).** A `compute`-style affordance in the
   effects/task model with cancellation, mount-safety, and an above-threshold
   guard. Removes the single-isolate ceiling for sort/filter/parse/diff on the
   data-heavy workloads Fleury targets. ~1 week, no strategic decision needed.

4. ✅ **Frame-rate coalescing under high-rate updates.** *(done — 2026-06-04)*
   Confirmed the runtime coalesced only within an event-loop turn (microtask),
   not across turns — so a burst rendered one frame per event. Added
   `FrameScheduler` (clock-injectable, unit-tested) and an opt-in
   `runTui(frameInterval:)` rate cap that collapses a burst to one frame per
   interval (10 updates → 1 render, verified) while merging updates. Default
   `Duration.zero` is unchanged behavior. See Completed.

5. **Focus-preservation-across-screens hardening.** The decision log keeps
   inactive-screen command scopes *disabled* pending "focus preservation
   hardening" — a flagged gap in the app kernel that multi-screen dev tools (the
   target) lean on. Investigate before it calcifies into the public contract.

## ▶ Active — Tier 3 (decide & document; cheap, protects API freeze)

6. **Write the architecture rationale notes** for the two resolved decisions
   (three-tree-for-terminal; pure-Dart-not-native) + a one-pager on the
   Hybrid-Islands seam as a designed-for backstop. Closes the questions, arms
   contributors.

7. **Resolve the state-management posture before API freeze.** `InheritedWidget`
   + `ChangeNotifier` is the whole built-in story, with no Dart-terminal
   Riverpod fallback. Decide: stay minimal + "bring your own", ship a first-party
   reactive-state story, or define adapter seams now.

## ⏸ Gated (need a product / posture decision first)

8. **Incremental / observable semantic tree.** Build only if the live-a11y or
   live-mirror (agent/remote) product bet is committed. Design on paper now so
   the path is known (ties to Tier-1 #1).

9. **Native render islands (C-ABI core).** Build only if the cross-language
   posture is chosen — then it's the *mechanism* for non-Dart frontends (the
   OpenTUI axis), not a perf tweak. Keep the seam designed-for; don't build
   speculatively.

---

## Notes
- Hardware byte→latency capture (the handoff) is external evidence, tracked in
  [byte-latency-handoff.md](byte-latency-handoff.md), not a code task here.
- "Incremental SGR" was investigated and **descoped** as a steady-state lever —
  it's a first-paint-only win (SGR dominates first paint, ~6% of update bytes).
