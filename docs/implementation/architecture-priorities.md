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

4. **Frame-rate coalescing under high-rate updates.** *(new — 2026-06-04)*
   The latency estimator showed fast/WAN-SSH latency is RTT/frame-**count**
   dominated, not byte-size dominated. The lever is emitting fewer frames under
   bursty updates: investigate whether the runtime currently emits a frame per
   event-loop turn (e.g. one per streamed token/log line) or coalesces to a
   frame budget; if the former, add a frame-rate cap / coalescing window so a
   burst of N updates produces one frame. Directly improves remote-session
   responsiveness **and** the agent-streaming workload (token/log/markdown
   streams). Pair with the byte telemetry to measure frames-per-second emitted.

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
