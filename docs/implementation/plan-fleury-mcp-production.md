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
| WS-0 | ~~Build-owner structure generation (= A3)~~ | M1 | P0 | — | `[~]` **reverted** (2026-06-29) — milestone review found it under-delivered + too coarse; superseded by WS-2 fingerprint. See changelog. |
| WS-2 | Enriched-fingerprint stale guard + capped settle + web-dispatch fix | M1 | P0 | WS-3 | `[x]` **done** (2026-06-29) |
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

### WS-0 — ~~Build-owner structure generation (= identity-RFC A3)~~  ·  `[~]` REVERTED

**Built, then reverted (2026-06-29).** The generation was implemented and committed
(`42eb8d9`), but the M1 milestone review found the *global* counter unfit as a
stale-guard primitive. Two independent holes:
- **Under-delivered (→ silent mis-target):** the counter bumps on any element
  change, but the wire only ships it on a *semantic-dirty* frame, and the bump
  itself missed direct-unmount paths (lazy `ListView` removal bypasses
  `_deactivate` — proven: itemCount 4→3 left the generation unchanged). A
  positional id could shift while the bridge's generation stayed stale.
- **Too coarse (→ false positives):** one whole-tree counter invalidates *every*
  positional id on *any* structural change anywhere, false-flagging held ids in
  static corners of a dynamic UI — which would push agents to stop passing it,
  neutering the guard.

A per-node fingerprint (WS-2) is both safe (no false positives) and reliable (no
wire/bump dependency), so WS-0 was reverted in full. A *scoped* per-subtree
generation remains a possible future "leading" investment if durable positional
targeting on dynamic UIs becomes a priority — **parked, not built.**

### WS-2 — Enriched-fingerprint stale guard + capped settle + web-dispatch fix  ·  `[x]` done

**Goal.** Deterministic "observe after X" without the global-generation holes:
fail safe on a stale positional id via a per-node fingerprint, fix the
never-close-under-animation settle, and fix the web-dispatch regression the
milestone review surfaced. **Depends.** WS-3 (dispatch map).

**Tasks**
- [x] **Web-dispatch fix (HIGH, from the review).** Web action dispatch resolved
      against `semanticsOwner.currentTree`, which can be a const-constructed
      coverage-fallback or retained-leaf tree with a null element map → a live,
      actionable button silently no-ops. Now dispatch builds a fresh
      `fromElement(mounted)` (matching the terminal path); reverted the
      now-needless `replaceNodes` element-map carry-forward (also a MED
      stale-element risk). Regression test reproduces a real fallback frame.
- [x] **Enriched fingerprint** (`_fingerprint`): role + label + child-count +
      sorted action-set (NUL-joined). Catches same-role/same-label swaps that
      role+label alone misses, while deliberately excluding `value`/mutable state
      so a node whose value ticks between read and action never false-flags (no
      livelock). Positional-id-only; stable `Semantics(id:)` exempt.
- [x] **Capped settle** (`app_bridge.dart`): keep the revision-quiet debounce (so
      discrete reactions, even multi-frame animations, settle correctly), but
      bound Phase-2 by a `settleCap` (500 ms) past the first reaction so a
      continuously-animating app returns promptly instead of eating the 2 s
      timeout. Latency-only — the returned tree is always the latest.
- [x] `wait_for_change` already rides `settle`.
- [~] *(Decision logged)* No wire idle/busy bit and no `observed_generation` arg —
      the fingerprint needs neither.

**Acceptance**
- [x] A same-role/same-label positional swap differing only in the action set →
      typed `stale`, no action frame sent (the enrichment in action).
- [x] A positional id whose own value ticked → NOT flagged; the action dispatches
      (no livelock).
- [x] Web dispatch fires through a coverage-fallback (null-map `currentTree`)
      frame (`run_tui_surface_test`).
- [x] Stable id exempt; existing label-swap + value-tick cases preserved.

**Validate** — `[x]` `fleury` (1734) · `[x]` `fleury_web` (201) ·
`[x]` `fleury_widgets` (920) · `[x]` `fleury_mcp` (47) · `[x]` analyze 0 errors.

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
  carry-forward was an unplanned-but-necessary fix. *(The carry-forward was later
  reverted in the WS-2 rework — see below — once web dispatch moved to a fresh
  `fromElement` tree and no longer needed `currentTree`'s map.)*
- *2026-06-29* — **WS-0 built (`42eb8d9`) and WS-2 first cut (`c72aed1`), then an
  M1 milestone review (3 adversarial agents over the framework generation, the
  dispatch map, and the wire/settle/guard) found THREE HIGH issues — two
  empirically proven:**
  1. *(framework)* lazy `ListView` removal bypasses `_deactivate`, so the
     generation didn't bump on a real shape change → stale-guard silently passes.
  2. *(WS-3 web dispatch)* dispatch against `currentTree` fails after a
     coverage-fallback frame (null element map) → live buttons no-op.
  3. *(WS-2 wire)* the generation ships only on semantic-dirty frames, so a
     non-semantic positional shift isn't delivered → mis-target. Plus the global
     counter is too coarse (false-positives every positional id on any churn).
- *2026-06-29* — **WS-2 reworked per the review (Option A, user-approved).**
  Reverted WS-0 + WS-2's generation guard entirely; kept WS-3's dispatch map.
  (1) Web dispatch now builds a fresh `fromElement(mounted)` (HIGH #2 fixed +
  regression test); `replaceNodes` carry-forward reverted. (2) Stale guard now a
  per-node **enriched fingerprint** (role+label+childCount+actions, value
  excluded → no livelock) — safe (no false positives) and needs no wire/bump
  machinery. (3) Settle keeps revision-quiet but caps Phase-2 at 500 ms so a
  ticking app returns promptly (latency-only). **Why this beats fixing the
  generation:** the global counter was simultaneously under-delivered (unsafe)
  and too coarse (unusable); a per-node fingerprint is more precise *and* removes
  the whole wire/bump failure surface. A scoped generation is parked as a future
  "leading" option. Suites: fleury 1734 · web 201 · widgets 920 · mcp 47 · clean.
  → Next: re-run the M1 milestone review on the rework, then M2.
