# Implementation Plan: `fleury_mcp` production-hardening

**Tracks:** [Production-hardening RFC](rfc-fleury-mcp-production-hardening.md) ·
[Stable ids + `setValue` RFC](rfc-stable-semantic-ids-and-setvalue.md) (WS-0 = its A3).
**Status:** Not started (2026-06-29). This is a living checklist — tick boxes and
update the **Status board** as you go.

## How to use this doc

- Each workstream has **Tasks** (do these), **Acceptance** (must all be ticked to
  call it done), and **Validate** (suites that must be green).
- A workstream is **Done** only when every Acceptance box and Validate suite is
  green. Update the Status board row at the same time.
- Add dated lines to **Notes / changelog** for decisions, surprises, scope cuts.
- Legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked.

## Status board

| WS | Goal | Milestone | Priority | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| WS-3 | Authoritative id→element dispatch (early win) | M1 | P0 | — | `[x]` **done** (2026-06-29) |
| WS-0 | Build-owner structure generation (= A3) | M1 | P0 | — | `[x]` **done** (2026-06-29) — wire delivery → WS-2 |
| WS-2 | Generation-keyed settle + stale guard | M1 | P0 | WS-0 | `[ ]` not started |
| WS-1 | Resource subscriptions + delta push (Route A) | M2 | P0 | WS-0¹ | `[ ]` not started |
| WS-4 | Prompt-injection mitigation + rate-limit | M2 | P1 | — | `[ ]` not started |
| WS-9 | Typed affordances (expose + validate) | M2 | P1 | `setValue` (shipped) | `[ ]` not started |
| WS-8 | Test shapes (multi-contributor, fuzz, stress) | M2 | P1 | WS-3 | `[ ]` not started |
| WS-5 | Shared spawn / lifecycle | M3 | P1 | coord. `fleury serve` | `[ ]` not started |
| WS-6 | Cancellation, logging, error codes | M3 | P1/P2 | — | `[ ]` not started |
| WS-7 | Per-revision node index | M3 | P2 | — | `[ ]` not started |

¹ WS-1's delta granularity (whole-node, next-frame) is independent of WS-0, but
coalescing during settle is cleaner once WS-0's generation exists.

## Conventions

- **Validate commands** (from repo root):
  - `fleury`: `cd packages/fleury && dart analyze && dart test -x integration`
  - `fleury_widgets`: `cd packages/fleury_widgets && dart analyze && dart test`
  - `fleury_mcp`: `cd packages/fleury_mcp && dart analyze && dart test`
  - `fleury_web`: `cd packages/fleury_web && dart analyze && dart test`
- **Cross-RFC coordination:** WS-0 is the identity RFC's A3 — framework-core,
  gates M1. Scope/own it jointly before WS-2's MCP-facing work assumes it.

---

## M1 — Foundations & correctness

Start **WS-3** (independent, cheap) and **WS-0** (the foundation) in parallel;
**WS-2** lands once WS-0 exists.

### WS-3 — Authoritative id→element dispatch  ·  `[ ]`

**Goal.** Resolve `target.id → owning Element` from a live map built in the one
existing tree walk, so dispatch is O(1) and matches snapshot ids by construction
— removing the second-walk rebuild inconsistency that broke the reverted guard.
**Depends.** None (within-snapshot authority). Cross-snapshot held ids → WS-0.

**Tasks**
- [x] Capture `Map<SemanticNodeId, Element>` in `_collectInto`, indexing each
      contributor's *owned* ids (pruning grafted child-contributor subtrees by id,
      so a `DataTable`'s synthesized rows/cells map to the table element).
- [x] Carry it on `SemanticTree` (`_elementsById` + private ctor + `elementById`);
      **carry it through `replaceNodes`** so the web retained-leaf path keeps it.
- [x] Rewrite `invokeSemanticActionFromElement` to resolve `tree.elementById(id)`
      and dispatch via `_dispatchSemanticActionOnElement` — deleted the recursive
      `_dispatchSemanticAction`/`_dispatchSemanticActionAfterAsyncChild`/
      `_elementChildren`; dropped the now-unused `root` param.
- [x] Updated the live dispatch sites (`run_tui.dart`, `run_tui_surface.dart`) and
      **unified the tester** onto the production path — removed its duplicate
      `_dispatchSemanticAction`/`_semanticSubtreeContains`/`_collectSemanticNodes`
      (the divergence that hid the original cross-fire). Fixed two test call sites.
- [x] Removed `DataTable._ownsTarget` and both per-handler guards (now redundant).

**Acceptance**
- [x] Two-`DataTable` app: `setValue` on B routes to B, A untouched, **with
      `_ownsTarget` removed** (new `data_table_test.dart` "no cross-fire" test).
- [x] No second element walk in the dispatch path.

**Validate** — `[x]` `fleury` (1734) · `[x]` `fleury_widgets` (920) ·
`[x]` `fleury_web` (201, retained-leaf parity) · `[x]` `fleury_mcp` (45) · `[x]` analyze 0 errors.

### WS-0 — Build-owner structure generation (= identity-RFC A3)  ·  `[ ]`

**Goal.** A monotonic counter that bumps **only on tree-shape change**, covering
**all** elements (incl. non-`Semantics`), threaded onto the snapshot/wire. The
foundation under WS-2, cross-snapshot WS-3, and A3.
**⚠ Framework-core change with a real correctness surface** — the hot path
reshuffles shape *in place with no lifecycle event*; the reverted memo proves a
too-narrow signal is unsafe.

**Tasks**
- [x] Added `BuildOwner._structureGeneration` + `structureGeneration` getter +
      `_markStructureChanged()`.
- [x] Bump on base `Element` lifecycle: `mount`, `_deactivate`, `_activate`
      (these cover add / remove / reparent — `_deactivate` precedes every
      `unmount`).
- [x] Bump on the in-place child reorder (`_syncChildRenderObjects`'s
      `!_sameRenderObjectOrder` branch) — the one shape change the lifecycle hooks
      miss.
- [x] Value-only updates do **not** bump (verified by the property test).
- [x] Threaded onto `SemanticTree.structureGeneration` (read from `root.owner` in
      `fromElement`; carried through `replaceNodes` for the retained-leaf path) →
      `SemanticInspectionSnapshot.structureGeneration` → `toJson`/`toJsonCapped`.
- [~] **Wire + bridge delivery moved to WS-2** (its consumption boundary): add the
      generation to the semantics frame envelope + decode in `app_bridge`.

**Acceptance**
- [x] Property test (`structure_generation_test.dart`, 6 cases): bumps **iff**
      shape changed (add / remove / keyed reorder / non-Semantics sibling shift),
      **never** on a value-only rebuild or an unkeyed same-type "swap". *(Pins the
      reverted-memo failure mode.)*
- [x] The in-process inspection snapshot carries the generation; *(over-the-wire
      to the bridge → WS-2)*.

**Validate** — `[x]` `fleury` (1740, incl. framework + semantics + remote) ·
`[x]` `fleury_web` (201, parity) · `[x]` `fleury_mcp` (45, additive JSON key) ·
`[x]` analyze 0 errors.

### WS-2 — Generation-keyed settle + stale guard  ·  `[ ]`

**Goal.** Deterministic "observe after X": fail safe on a stale positional id via
the generation (catches the same-role/same-label swap the fingerprint misses),
and fix the never-close-under-animation settle.
**Depends.** WS-0.

**Tasks**
- [ ] Stamp `structureGeneration` on `get_ui` / `find_nodes` / resource output
      (`mcp_server.dart`).
- [ ] Accept an optional `observed_generation` arg on `invoke_action` /
      `set_value`; thread it to the bridge / dispatch.
- [ ] Stale guard in `_resolveActionableNode`: for a positional id, fail typed
      `stale` when `observedGeneration != current` (supersedes / augments the
      role+label fingerprint).
- [ ] Settle redesign (`app_bridge.dart:187-216`): Phase-1 completes on the
      generation advancing past the captured value; **bound Phase-2 by wall-clock**
      so a continuously-animating app no longer falls through to the 2 s timeout
      every observe (the bonus bug).
- [ ] `wait_for_change` rides the same generation-keyed path.
- [ ] *(Decision)* whether to also expose an app idle/busy bit on the wire
      (`TickerScheduler.isActive` / `TuiRuntime.hasFrameWork` exist internally) for
      a stronger settle — log the call in Notes.

**Acceptance**
- [ ] Scripted same-role/same-label node swap → typed `stale`, not silent
      mis-target.
- [ ] A ticking dashboard: an observe returns promptly, not after the 2 s timeout.
- [ ] `set_value` with a stale positional id fails safe; with a current
      generation, succeeds.

**Validate** — `[ ]` `fleury` (semantics) · `[ ]` `fleury_mcp` (e2e + showcase).

---

## M2 — Reactivity, safety & differentiation

*(Detail each at M2 kickoff; top-level tasks below are the breakout seeds.)*

### WS-1 — Resource subscriptions + delta push (Route A)  ·  `[ ]`

- [ ] Advertise `resources:{ subscribe:true, listChanged:true }` in `initialize`.
- [ ] Implement `resources/subscribe` / `unsubscribe`; gate call shape on
      negotiated `protocolVersion` (draft renames to `subscriptions/listen`).
- [ ] Emit `notifications/resources/updated` for `fleury://ui/tree` on each
      **settled** revision, coalesced.
- [ ] **Route A delta:** surface the decoder's `{changedIds, removedIds}`
      (computed at `remote_semantics.dart:185-198` but discarded) through a new
      decoder → `app_bridge` → MCP path; include it in the notification payload.
- [ ] Keep `wait_for_change` as the synchronous fallback.
- **Acceptance:** `[ ]` one coalesced `updated` per settled change carrying the
  delta; `[ ]` no notification storm under animation.
- **Validate:** `[ ]` `fleury_mcp`.

### WS-4 — Prompt-injection mitigation + rate-limit  ·  `[ ]`

- [ ] Design the untrusted-text policy (delimit/quote/mark app label/value spans)
      **without** corrupting text the agent needs verbatim, and **without**
      overloading the renderer-shared `sanitizeForDisplay`. *(Design task first.)*
- [ ] Implement the mitigation on the `get_ui` output path.
- [ ] Add a rate-limit / call-budget guard on mutating tools.
- **Acceptance:** `[ ]` a hostile-label fixture can't inject instructions through
  `get_ui`; `[ ]` a runaway agent is throttled.
- **Validate:** `[ ]` `fleury_mcp`.

### WS-9 — Typed affordances  ·  `[ ]`

- [ ] **Expose:** normalize the already-emitted `Stepper`/`RangeSlider`/
      `DatePicker` constraint keys into a documented `valueSchema` block; add
      `Select`'s option set from `widget.options` (`select.dart`).
- [ ] **Validate-before-dispatch:** reject an out-of-domain `set_value` against
      the schema in `mcp_server.dart` (today widgets silently clamp/no-op).
- [ ] Avoid `_looksSensitive` redaction substrings (`value`/`text`/`token`) in
      schema keys; check against the 800-node / per-node token budget test.
- **Acceptance:** `[ ]` `get_ui` reports per-node accepted type + constraints;
  `[ ]` out-of-domain `set_value` rejected by contract, not trial.
- **Validate:** `[ ]` `fleury_widgets` · `[ ]` `fleury_mcp`.

### WS-8 — Test shapes  ·  `[ ]`

- [ ] Multi-contributor dispatch test (two of each contributor; zero cross-fire) —
      the WS-3 acceptance gate.
- [ ] Concurrency stress (interleaved reads + mutations; consistent "after").
- [ ] Wire-decode fuzz (malformed/truncated/oversized frames → safe degrade).
- [ ] One real-host smoke (notification / cancellation / version negotiation).
- **Validate:** `[ ]` `fleury_mcp` · `[ ]` `fleury`.

---

## M3 — Robustness & polish

### WS-5 — Shared spawn / lifecycle  ·  `[ ]`

- [ ] Extract a shared spawn-and-attach primitive into `fleury_host_io`; adopt in
      both `FleuryAppBridge.spawn` and `fleury serve --spawn` (no serve regression).
- [ ] Close/refuse extra socket connections after first attach.
- [ ] Unify timeouts (`firstFrameTimeout` / `connectTimeout` / `settle` /
      server-side ready-wait) into one coherent, configurable budget.
- **Validate:** `[ ]` `fleury` (remote) · `[ ]` `fleury_mcp`.

### WS-6 — Protocol completeness  ·  `[ ]`

- [ ] Request cancellation (`notifications/cancelled`) — cancel an in-flight
      `wait_for_change`.
- [ ] `logging` capability — forward sanitized app logs as `notifications/message`.
- [ ] Machine-readable error `code` inside `isError` payloads (stale-ref vs
      not-found).
- [ ] *(P2)* progress notifications, `listChanged`, pagination cursors.
- **Validate:** `[ ]` `fleury_mcp`.

### WS-7 — Per-revision node index  ·  `[ ]`

- [ ] Build an id→node index once per revision (likely the same map as WS-3);
      `nodeById`/`where(id:)` become O(1)/O(matches), reused across reads + guard.
- **Acceptance:** `[ ]` repeated reads against an unchanged revision do no full
  walk.
- **Validate:** `[ ]` `fleury` · `[ ]` `fleury_mcp`.

---

## Pre-flight (before writing M1 code)

- [ ] Confirm WS-0 ownership + scope jointly with the identity RFC (it *is* A3).
- [ ] Decide WS-2 settle: generation-only vs generation + wire idle bit (Notes).
- [ ] Confirm WS-3's `elementsById` is the index WS-7 will reuse (avoid two maps).

## Notes / changelog

- *2026-06-29* — Plan created from the validated RFC. Sequencing: WS-3 ∥ WS-0,
  then WS-2. WS-0 flagged as framework-core (the one heavy item); WS-3 is the
  cheap early win; settle never-close-under-animation bug folded into WS-2.
- *2026-06-29* — **WS-3 done.** id→element map built in the one tree walk;
  `invokeSemanticActionFromElement` + the tester both dispatch via it (duplicate
  dispatch removed); `replaceNodes` carries the map for the web retained-leaf
  path; `DataTable._ownsTarget` removed; new two-table no-cross-fire test green.
  Suites: fleury 1734 · widgets 920 · web 201 · mcp 45 · analyze clean. Adapted
  vs the plan: dispatch lived in `invokeSemanticActionFromElement` (not a
  separate `_dispatchSemanticAction`), and the retained-leaf `replaceNodes` map
  carry-forward was an unplanned-but-necessary fix.
- *2026-06-29* — **WS-0 done.** `BuildOwner.structureGeneration` bumps on
  mount/deactivate/activate + in-place reorder; property test (6 cases) pins
  "bumps iff shape changed, never on value tick", incl. the reverted-memo case
  (non-Semantics sibling shift). Threaded onto `SemanticTree` →
  `SemanticInspectionSnapshot` → JSON. Suites: fleury 1740 · web 201 · widgets
  920 · mcp 45 · analyze clean. **Adapted:** the wire/bridge delivery of the
  generation moved into WS-2 (where it's consumed) rather than WS-0, since the
  in-process snapshot already carries it and the wire field only matters once the
  bridge/get_ui consume it.
