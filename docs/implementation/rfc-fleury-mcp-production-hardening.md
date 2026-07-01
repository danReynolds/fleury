# RFC: Production-hardening the `fleury_mcp` layer

**Status:** Proposed (2026-06-29) — assessment + workstreams, ready to break out
into an implementation plan. No code yet.
**Owner:** `fleury_mcp`, the semantic app graph, the remote/host wire.
**Related:** [Stable semantic ids + `setValue`](rfc-stable-semantic-ids-and-setvalue.md)
(the node-identity + value-payload contract this RFC builds on; its deferred **A3
structure-generation handle** is a dependency here);
[`fleury_mcp` PR #19](https://github.com/danReynolds/fleury/pull/19);
[agent adapter boundary](agent-adapter-boundary.md).

## Scope

This RFC is about the **MCP layer's architecture and implementation quality** —
what `fleury_mcp` needs to be a *robust, reliable, performant* way to drive a
Fleury app, beyond the working v0.1 on `mcp-support`.

**In scope:** dispatch correctness, identity/consistency, reactivity (push),
security hardening, the process boundary, performance, protocol completeness,
and test shapes.

**Out of scope (deliberately):**

- Installability / publishing and end-user docs — tractable later, not
  architectural.
- The **node-identity derivation scheme** and the **`setValue` payload
  contract** — owned by [the identity RFC](rfc-stable-semantic-ids-and-setvalue.md).
  This RFC *depends on* that work (notably the deferred A3 structure-generation
  handle) but does not re-specify it.

## TL;DR

A semantic-tree-driven MCP layer is a well-charted design space, and Fleury's
**core model is mainstream — and on node identity, arguably ahead.** We expose a
compact accessibility subtree and let the agent act on nodes by id, the same
choices Playwright MCP, WebArena, and SeeAct converged on; and we issue *durable*
ids with a *fail-safe* staleness guard where the field largely uses ephemeral
re-snapshotted refs. The distance to "production-quality" is **not** the
tree/action/identity core. It is three things, in priority order:

1. **Push, not poll** — implement MCP resource subscriptions (the single biggest
   gap and the biggest reactivity win).
2. **A structure-generation stamp** — promote the role+label fingerprint to a
   monotonic generation check (the identity RFC's deferred A3), closing a real
   correctness hole and the settle race.
3. **The spec's security MUSTs** — output sanitization (a live prompt-injection
   surface) and rate limiting.

Everything else (dispatch-ownership-by-construction, the process boundary,
per-revision indexing, protocol niceties, test shapes) is real but secondary.

**Build the leading form, not just parity.** Two of those priorities should ship
in their *leading* form from day one — push **semantic deltas** (WS-1), not a
"re-read" ping; and return **the frame your action caused** (WS-2), not a settle
guess — plus one deliberate differentiator, **typed affordances** (WS-9): the
live UI as a self-describing, *typed* tool surface. These exploit an asymmetry
the field can't close: everyone else scrapes a derived tree *from the outside*;
Fleury owns the framework and can expose one *from the inside*, with guarantees.

## How we stack up

Research-anchored (primary sources: Microsoft Playwright docs+repo, the MCP spec,
WebArena/SeeAct papers, MDN/W3C WebDriver, arXiv 2511.19477). Verdict legend:
**✅ have / on par**, **★ ahead**, **◐ partial**, **✗ gap**.

| Axis | The field's pattern | Fleury today | Verdict |
| --- | --- | --- | --- |
| **Tree representation** | Compact accessibility subtree (role/text/props), not pixels or raw DOM — Playwright MCP "structured tree of accessible elements"; WebArena "subset of the DOM… role, text, properties"; SeeAct text-grounding beats vision by ~30 pts. | `fleury://ui/tree` = role/label/value/state/actions. | ✅ |
| **Targeting** | Act on a node by an id assigned during traversal → n-way classification (WebArena `click [1582]`, Playwright `ref=e5`). | `invoke_action`/`set_value`/`find_nodes` by node id. | ✅ |
| **Node identity** | Two poles: *ephemeral* refs re-snapshotted per step (Playwright/WebArena), or *durable* per-session ids (WebDriver UUID). Re-using a ref across renders causes "state divergence" (`ref=10` Cancel→Delete, arXiv 2511.19477). | Durable key-derived ids (`Semantics(id:)`, folded-key `auto:`) that survive rebuilds; positional fallbacks (`element-<hash>`, `auto:…~…`) guarded. | ★ |
| **Stale-ref safety** | Recommended mitigation = a version/generation check that **fails safely** on mismatch. | role+label fingerprint on positional ids only (`isPositionalSemanticId`). | ◐ — fingerprint is coarser than a generation stamp (see WS-2). |
| **Act-then-observe determinism** | Wait-until-actionable (Playwright: visible/stable/enabled, else `TimeoutError`); settle on quiescence. | Serialized mutations + event-driven `settle(sinceRevision:)` quiet-window. | ◐ — global quiet-window heuristic, no per-target readiness. |
| **Tool error model** | JSON-RPC errors for protocol issues vs `isError:true` for execution failures the LLM should react to (MCP tools spec). | Exactly this split (`_RpcError` vs `_ToolFailure`→`isError`). | ✅ |
| **Reactivity** | Server-push: `subscribe` + `notifications/resources/updated` (MCP spec). | Bare `resources:{}`, poll-style `wait_for_change`. | ✗ |
| **Payload bounding / caching** | Bound size; cache per snapshot. | Per-frame snapshot memoization; node caps (800 / `find_nodes` 50); `structuredContent`. | ✅ |
| **Security MUSTs** | Validate inputs · access controls · rate-limit · sanitize outputs (MCP tools spec). STDIO ⇒ auth optional. | Strong input validation + caps; **no** rate-limit; **no** output sanitization. | ◐ |
| **Protocol completeness** | cancellation, progress, `logging`, `listChanged`, pagination. | initialize/ping/tools/resources read+list only. | ✗ (low value) |

**One reassurance from the research:** the claims that an agent layer *must*
embed version-refs (`snapshotVersion:elementRef`) or auto-re-snapshot every step
were **refuted** (no consensus). So our durable-id design is a legitimate,
defensible point in the space — the work below *strengthens* it, it isn't
catching up to a standard we're violating.

## What we have (today, on `mcp-support`)

Two layers, both verified by the PR #19 review:

- **`FleuryAppBridge`** ([`app_bridge.dart`](../../packages/fleury_mcp/lib/src/app_bridge.dart))
  — a peer on the `fleury serve` wire: spawns the app (`FLEURY_HANDLE` Unix
  socket), `InitFrame` v2, decodes `SemanticsFrame` patches into a live
  `SemanticTree`, sends action/input/resize frames, ignores visual frames. Keeps
  a monotonic `revision`, a lazily-built **per-revision snapshot cache**, a
  first-frame watchdog, and an event-driven `settle()`.
- **`McpServer`** ([`mcp_server.dart`](../../packages/fleury_mcp/lib/src/mcp_server.dart))
  — JSON-RPC 2.0 over stdio. Resource `fleury://ui/tree`; tools `get_ui`,
  `find_nodes`, `invoke_action`, `set_value`, `type_text`, `press_key`, `resize`,
  `wait_for_change`. Concurrent request dispatch, serialized writes + broken-pipe
  teardown, **mutating-tool serialization**, and a positional **stale-reference
  guard**.

Solid and not up for change: the wire-reuse architecture, the JSON-RPC
robustness scaffolding, the tool error model, and the test pyramid.

## What we need — workstreams

Each is self-contained and sized for breakout into the implementation plan:
**Problem · Have · Need · Priority · Depends · Done-when.**

### WS-0 — Build-owner structure generation (foundational) — **P0**

- **Problem / why it leads.** Three items below — WS-2's deterministic settle,
  *cross-snapshot* safety of WS-3's id→element map, and the identity RFC's
  deferred **A3** — all need the *same* primitive: a signal that the tree's
  **shape** changed, covering **all** elements (not just `Semantics` ones). It
  does not exist today, and (validated) the hot reconcile path reshuffles shape
  *in place with no lifecycle event*, so it can't be derived from the existing
  `SemanticDirtyTracker`.
- **Have.** A per-frame `revision` (too fine — bumps on every reaction) and a
  `SemanticDirtyTracker` that fires only from `SemanticsElement` lifecycle.
- **Need.** A monotonic **structure generation** incremented in the framework
  reconcile core (`BuildOwner` / base `Element`) on add/remove/reparent **and**
  the in-place unkeyed child-order change (`framework.dart:1563`) — *not* on
  value ticks — threaded onto each emitted snapshot.
- **Depends.** None; it is the foundation. This *is* the identity RFC's A3 — land
  it once, three consumers benefit.
- **Done-when.** A structural reshuffle (incl. an unkeyed `Row`/`Column` reorder)
  bumps the generation; a value-only tick does not; the snapshot carries it.
- **Scope honesty.** Multi-site framework change with its own correctness surface
  — *not* "fold a counter onto the snapshot." See *Feasibility notes*.

### WS-1 — Reactive push: resource subscriptions — **P0**

- **Problem.** The UI is live and event-driven, but the agent learns it changed
  only by polling `get_ui` or blocking in `wait_for_change` — a tool-call
  round-trip per observation. This is our single biggest spec + reactivity gap.
- **Have.** Bare `resources:{}` capability; `wait_for_change`; an event-driven
  `settle()` debounce that already knows when the tree quiesces.
- **Need.** Advertise `resources:{ subscribe:true, listChanged:true }`; implement
  `resources/subscribe`/`unsubscribe`; emit `notifications/resources/updated`
  for `fleury://ui/tree` on each **settled** revision, **coalesced** so a 60 fps
  app doesn't spam. Keep `wait_for_change` as a synchronous-await convenience.
  Gate the call shape on negotiated `protocolVersion` (the draft renames
  `resources/subscribe` → `subscriptions/listen`; the `subscribe` flag and
  `notifications/resources/updated` are stable).
- **Leading form (build this, not bare parity).** Don't push a bare "re-read"
  ping — carry the **minimal semantic delta** (the changed nodes/fields) with the
  notification. Fleury already diffs semantics on the wire (`SemanticsWireDecoder`
  applies patch frames), so the change set should already exist upstream;
  surfacing it gives the agent a *change-oriented*, low-token observation channel
  a snapshot-scraper structurally can't match (the field's known token sink is
  re-snapshotting the whole tree each step). **Validated:** the wire *is* a
  structural patch, but `SemanticsWireDecoder.apply()` collapses it to a full tree
  and discards the change set, so there is no delta to "forward." Take **Route A**
  — surface the decoder's already-computed `{changedIds, removedIds}` through a
  new decoder→bridge→MCP path (reuses work; whole-node granularity, next-frame
  scope) — over Route B (re-diff snapshots in-bridge, a redundant O(tree)
  recompute). See *Feasibility notes*.
- **Depends.** None for the parity form (additive). The leading form depends on
  the wire exposing a structural delta. Synergizes with WS-7's coalescing.
- **Done-when.** A subscribed client receives one coalesced `updated` per settled
  change; the leading form carries the delta, not just the URI; no notification
  storm under animation; `wait_for_change` still works.
- *Refs:* [MCP resources](https://modelcontextprotocol.io/specification/2025-06-18/server/resources).

### WS-2 — Deterministic identity & consistency: structure-generation stamp — **P0**

- **Problem.** Two coupled correctness holes. (a) The role+label fingerprint
  **cannot detect a same-role/same-label node swap** (two "Delete" buttons
  trading positions) — the exact "state divergence" the version-stamp pattern
  exists to catch. (b) `settle()`'s 60 ms/2 s **global quiet-window can settle
  early** on a late async re-render, returning a transient tree; and the
  stale-ref baseline (`_lastServed`) is a single shared field a concurrent read
  can move mid-mutation.
- **Have.** Durable ids + positional-only fingerprint guard; per-mutation
  `_lastServed` local snapshot; serialized mutations.
- **Need.** Land the identity RFC's deferred **A3 structure-generation handle**:
  a monotonic generation bumped only on tree-*shape* change, stamped on `get_ui`
  output and passed back with an action. The dispatcher honors a fully-keyed id
  regardless, and fails an action on a positional id **safely** when
  `observedGeneration != current`. This supersedes the fingerprint *and* the racy
  shared baseline (the baseline becomes "what the agent observed"). Then key
  `settle()`/`wait_for_change` off the generation (and/or an action-acknowledgment
  on the wire) instead of a global quiet-window, so "observe after X" is
  deterministic.
- **Leading form.** Frame the action↔frame link as a *guarantee*, not a
  heuristic: because Fleury owns the frame loop, return "the settled tree your
  action produced" (the frame this action caused), not "no further change for
  60 ms." That is a determinism property a screen-scraper — which can't see *why*
  the UI changed — structurally cannot offer. **Validated mechanism:** *not* a
  wire action-ack (there is no 1-action→1-frame relationship to stamp — an
  unchanged accessible tree emits zero frames, animation emits many, and the
  scheduler coalesces). The deterministic settle is **generation-keyed** (waits
  until the observed structure generation from WS-0 is current), which is the
  only variant that also terminates under a continuously-animating app. See
  *Feasibility notes*.
- **Depends.** **WS-0** (the structure generation = the identity RFC's A3). Also
  fixes a bug WS-2 surfaced: under continuous animation today's 60 ms quiet-window
  settle *never closes* and always falls through to the 2 s timeout
  (`app_bridge.dart:209-214`) — the generation-keyed settle fixes it.
- **Done-when.** A scripted same-role/same-label swap fails safe (typed `stale`),
  not silently mis-targeted; settle returns the tree caused by *this* action, not
  a transient or a neighbor's; and a ticking dashboard no longer forces the 2 s
  settle timeout on every observe.
- *Refs:* [arXiv 2511.19477 (version stamp / state divergence)](https://arxiv.org/html/2511.19477v1),
  [Playwright actionability](https://playwright.dev/docs/actionability),
  [WebDriver stale element](https://developer.mozilla.org/en-US/docs/Web/WebDriver/Reference/Errors/StaleElementReference).

### WS-3 — Action dispatch: ownership as a framework guarantee — **P0 (early win)**

- **Problem.** Dispatch offers an action to the first contributor in the element
  walk that returns true, so correctness relies on each widget self-checking that
  `target.id` is its own. `DataTable` shipped without it (cross-fire); a
  subtree-guard in the dispatcher was reverted because it ran a **second element
  walk** and rebuilt ids inconsistent with the snapshot's. Today it's per-widget
  discipline — a future custom contributor can silently reintroduce the bug.
- **Have.** Per-widget self-checks (`DataTable._ownsTarget`).
- **Need.** Build an authoritative `Map<SemanticNodeId, Element>` **inside the
  existing single tree-build walk** (`_collectInto` / `SemanticTree.fromElement`),
  keyed by the same `_nodeId` that mints each node — so it matches the snapshot's
  ids *by construction*. Dispatch becomes O(1) `map[target.id]`, no second walk.
  (Validated: this is a small, well-scoped semantics-layer change; precedent
  exists in `SemanticDirtyTracker._dirtyLeafElements`.)
- **Depends.** Independent for *within-snapshot* authority (the early win). A
  *held* id across snapshots is made safe by WS-0's generation.
- **Done-when.** WS-8's multi-contributor test (two of every contributor) shows
  zero cross-fire with the per-widget guards removed.

### WS-4 — Security hardening: output sanitization + rate limiting — **P1**

- **Problem.** The MCP tools spec requires production servers to *validate
  inputs* (we do well), *rate-limit* (we don't), and *sanitize outputs*. The last
  one needs precision (validated): label/value/hint/state text **is** already run
  through `sanitizeForDisplay` on the `get_ui` path (`inspection.dart:325-352`) —
  but that's a **terminal-control-code filter, not prompt-injection defense**. A
  label like *"ignore previous instructions and …"* passes through verbatim. So
  the gap is *prompt injection*, not raw output sanitization, and rate-limiting.
- **Have.** Strong input validation (role/action enums, `_maxInputChars`,
  positive dims, id presence); size caps; **control-char output sanitization
  already on the `get_ui` path** (`sanitizeForDisplay`).
- **Need.** A **prompt-injection mitigation distinct from** the control-char pass
  — delimit/quote/mark app-controlled label/value spans as untrusted *without*
  corrupting text the agent needs verbatim (a policy design, not a one-line
  filter; must **not** overload the renderer-shared `sanitizeForDisplay`). Plus a
  rate-limit / call-budget guard on mutating tools. STDIO keeps auth optional
  (compliant), so no OAuth.
- **Depends.** None.
- **Done-when.** A hostile-label fixture can't inject instructions through
  `get_ui`; a runaway agent is throttled rather than unbounded.
- *Refs:* [MCP tools spec (security MUSTs)](https://modelcontextprotocol.io/specification/2025-06-18/server/tools),
  [MCP auth (STDIO)](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization),
  [MCP security checklist](https://github.com/slowmist/MCP-Security-Checklist).

### WS-5 — Bridge & process lifecycle — **P1**

- **Problem.** `FleuryAppBridge.spawn` re-implements the spawn-and-attach dance
  `fleury serve --spawn` already owns (two copies drift); a second connection to
  the listening socket is never accepted/closed; timeouts (`firstFrameTimeout`
  10 s, `connectTimeout` 20 s, `settle` 2 s, server-side ready-wait 5 s) are an
  incoherent set (the 5 s wait < the 10 s watchdog).
- **Have.** Working spawn, first-frame watchdog, SIGTERM→SIGKILL teardown.
- **Need.** Extract a shared spawn-and-attach primitive into the host SPI
  (`fleury_host_io`) used by both peers; close/refuse extra connections after
  first attach; unify timeouts into one coherent, configurable budget; state
  single-session-no-reconnect for v1.
- **Depends.** Coordinated with `fleury serve` (must not regress its
  warm-standby/multi-client path).
- **Done-when.** One tested spawn owner; no dangling socket; one timeout config.

### WS-6 — Protocol completeness — **P1 (cancellation/logging) / P2 (rest)**

- **Problem.** `handleLine` handles only initialize/ping/tools/resources
  read+list. A long `wait_for_change`/`settle` is exactly the call a client wants
  to abort, and there's no app-log channel to the host.
- **Have.** The core request/response + concurrent dispatch.
- **Need.** **P1:** request cancellation (`notifications/cancelled`) and the
  `logging` capability (forward sanitized app logs as `notifications/message`);
  add a machine-readable error `code` inside `isError` payloads so the agent
  branches on stale-ref vs not-found. **P2:** progress notifications for long
  settles, `listChanged`, pagination cursors.
- **Depends.** Cancellation pairs with WS-1 (a subscribed agent rarely blocks,
  reducing the need) but is independent.
- **Done-when.** A client can cancel an in-flight `wait_for_change`; app logs
  surface as MCP log notifications.

### WS-7 — Performance: per-revision node index — **P2**

- **Problem.** `get_ui`/`find_nodes`/the stale-guard each re-walk the tree
  (`where(id:)`/`nodeById` over a lazy generator, O(n)); the snapshot is cached
  per revision but the id→node index isn't, so a chatty agent on a large UI pays
  repeated full walks.
- **Have.** Per-revision snapshot memoization (already production-grade per the
  research), node caps.
- **Need.** Build an id→node index once per revision; `nodeById`/`where(id:)`
  become O(1)/O(matches), reused across reads + the guard within a revision.
- **Depends.** None; complements WS-2's live-id index (likely the same map).
- **Done-when.** Repeated reads against an unchanged revision do no full walk.

### WS-8 — Test shapes for production confidence — **P1**

- **Problem.** Good unit + e2e, but the `DataTable` cross-fire slipped through
  because single-widget tests don't probe multi-widget routing; the mutation
  mutex is new; the wire decode isn't fuzzed.
- **Have.** Fake-transport unit + real-spawn e2e + process-boundary e2e.
- **Need.** Multi-contributor dispatch tests (pins WS-3); concurrency stress
  (interleaved reads/mutations); wire-decode fuzz (malformed/truncated/oversized
  frames); one real-host smoke (notification/cancellation/version-negotiation
  quirks).
- **Depends.** WS-3 (multi-contributor test is its acceptance gate).
- **Done-when.** Each new shape exists and is green; the `DataTable` class of bug
  is caught by a test, not review.

### WS-9 — Typed affordances: the UI as a self-describing tool surface — **P1 (differentiator)**

- **Problem / opportunity.** Browser agents *infer* what's actionable and what a
  field accepts (ARIA + heuristics) and discover invalid actions by failing.
  Fleury nodes already *declare* their `SemanticAction`s — we can go a step the
  field can't and make the UI a *typed* tool surface.
- **Have.** Nodes advertise supported actions; `SemanticState` is the *designed*
  map-backed extension point and is already on the `get_ui` path. Stronger than
  assumed (validated): `Stepper`/`RangeSlider`/`DatePicker` **already emit**
  min/max/step/bounds into `state` today; only `Select` omits its option set.
- **Need (split).** **(a) Expose** — normalize the already-emitted constraint keys
  into a documented `valueSchema` block per actionable node, and add `Select`'s
  option set from `widget.options`. Mostly normalization, no new model field.
  **(b) Validate before dispatch** — net-new server-side check in `fleury_mcp`
  that rejects an out-of-domain `set_value` against the schema (today widgets
  silently clamp/no-op and the agent only learns via `changed:false`). *Caveats:*
  keep schema keys clear of the `_looksSensitive` redaction substrings
  (`value`/`text`/`token`) and within the 800-node / per-node token budget.
- **Depends.** The identity RFC's `setValue` contract (B4 typed coercion, largely
  shipped) — this *exposes* that typing to the agent. Sequence after `setValue`.
- **Done-when.** `get_ui` reports, per actionable node, the action's accepted type
  + constraints; an out-of-domain `set_value` is rejected by the contract, not by
  trial-and-error.
- **Why it leads.** It requires *authoring* the semantics, which is exactly what
  owning the framework gives us — no scraper of a derived tree can synthesize it.

## Deferred differentiators (parked)

Compelling but heavier or more product-shaped — captured so they aren't lost, not
scheduled here:

- **Deterministic record & replay** of agent sessions (the frame + action streams
  → reproducible eval and "why did it do X" forensics). Retained-mode + a
  frame-stream wire make it possible where the live web can't; a medium new build,
  strong as the basis for an agent eval harness.
- **Aligned dual grounding** — hand the agent a cheap, exact **cell-grid spatial
  render** alongside the semantic tree (deterministic, token-tiny, no OCR/bbox
  estimation) for spatial tasks, perfectly aligned to the same frame.
- **Drive-by-meaning, verify-by-pixels** — an MCP session that exposes the
  semantic tree to the agent while a human watches the *same* app live via
  `serve`, parity-oracle-guaranteed identical: human-in-the-loop with provable
  parity.

## Feasibility notes (validated against the code, 2026-06-29)

Four load-bearing assumptions were checked against the `mcp-support` source before
this proposal becomes an implementation plan. Two held, two were harder than
stated, one premise was refuted — and the results forced one structural change:
**WS-0 was promoted to a foundational workstream**, because three items depend on
the same primitive.

| Assumption | Verdict | What the code says |
| --- | --- | --- |
| WS-1: *forward* an existing semantic delta | **Harder** | The wire *is* a structural patch (`remote_semantics.dart:74-95` emits `{set, removed}`), but `SemanticsWireDecoder.apply()` collapses it to a full tree and **discards the change set** (`:185-210`); the bridge holds no delta (`app_bridge.dart:238-243`). No free forward → **Route A** (surface the decoder's change set) vs Route B (re-diff in-bridge, redundant). |
| WS-2: causal observe via a wire action-ack | **Harder / wrong tool** | No 1-action→1-frame relationship: an unchanged accessible tree emits **zero** frames so `revision` never bumps (`remote_semantics.dart:85`); animation emits many; `FrameScheduler` coalesces. An ack is additive but unattributable → use a **generation-keyed** settle. |
| WS-0: build-owner structure generation | **Harder (framework surgery)** | No such counter exists; the hot path `_reconcileStableUnkeyedChildren` reshuffles shape **in place with no lifecycle event** (`framework.dart:1524-1550`), so it can't ride `SemanticDirtyTracker`. Must increment in `BuildOwner` / base `Element` reconcile incl. the order-change branch (`framework.dart:1563`). |
| WS-3: dispatch id→element map, no rebuild | **Holds — early win** | Buildable in the existing single walk `_collectInto` / `SemanticTree.fromElement`, keyed by the same `_nodeId` that mints each node → matches snapshot ids by construction; O(1) dispatch. Precedent: `SemanticDirtyTracker._dirtyLeafElements` is already a `Map<id, Element>`. |
| WS-9: typed affordances in `get_ui` | **Holds** | `SemanticState` is the designed map-backed extension point, already on the `get_ui` path; `Stepper`/`RangeSlider`/`DatePicker` **already emit** min/max/step/bounds; only `Select` omits its option set. *Validate-before-dispatch* is net-new server code. |
| WS-4: label/value flows **unsanitized** | **Refuted (concern stands)** | label/value/hint/state **are** `sanitizeForDisplay`'d on the `get_ui` path (`inspection.dart:325-352`) — but that's a *terminal-control-code* filter, **not** prompt-injection defense. Rescope WS-4 to the latter. |

**What the verdicts change:**

- **WS-0 is the foundation, and it is real framework work** — not a semantics-layer
  add. It gates WS-2's settle, the cross-snapshot safety of WS-3's map, and the
  identity RFC's A3. One investment, three consumers; scope it as such.
- **WS-3 is the cheap, correct early win** and is independent of WS-0 for
  within-snapshot authority. Build the id→element map in the one existing walk;
  it removes the rebuild inconsistency that broke the earlier guard.
- **WS-2 drops the wire-ack;** the deterministic settle is generation-keyed (rides
  WS-0) — the only variant that terminates under a continuously-animating UI.
- **WS-1 takes Route A** (surface the decoder's `{changedIds, removedIds}`), not a
  free forward and not the redundant in-bridge re-diff.
- **WS-4 is rescoped** from "add output sanitization" (it exists) to "add a
  prompt-injection mitigation distinct from the control-char pass" — design-heavy,
  must not overload the renderer-shared `sanitizeForDisplay`.
- **WS-9 splits** into *expose* (mostly normalization + the `Select` gap) and
  *validate-before-dispatch* (net-new), with the redaction-substring and
  token-budget caveats.

**Bonus bug found (worth fixing regardless):** under continuous animation today's
`settle()` 60 ms quiet-window **never closes** — every window observes a new
revision, so it always falls through to the 2 s timeout (`app_bridge.dart:209-214`),
a latency cliff on any ticking UI. The generation-keyed settle (WS-0 + WS-2) is
the principled fix; a stopgap is to bound Phase-2 by wall-clock, not "no further
change."

## Milestones (how this breaks into a plan)

- **M1 — Foundations & correctness.** Start with **WS-3** (the id→element dispatch
  map — independent, cheap, kills the cross-fire bug class) in parallel with
  **WS-0** (the build-owner structure generation — the framework-surgery
  foundation = the identity RFC's A3). Then **WS-2** (generation-keyed settle +
  stale-guard + the never-settle-under-animation fix) rides WS-0. Outcome:
  actuation correct-by-construction, observation deterministic.
- **M2 — Reactivity, safety & differentiation.** WS-1 (subscriptions via Route A's
  delta push), WS-4 (prompt-injection mitigation + rate-limit — design-heavy, not
  plumbing), WS-9 (typed affordances: expose + validate), WS-8 (test shapes). The
  user-visible production leap: push + hardened + tested + a typed agent surface.
- **M3 — Robustness & polish.** WS-5 (shared spawn / lifecycle), WS-6
  (cancellation, logging, error codes; then progress/pagination), WS-7
  (per-revision index).

Each workstream's *Need* + *Done-when* is the seed for its task breakdown. The
one cross-RFC coordination point is **WS-0 = A3**: it is framework-core, gates M1,
and pays off in both this RFC and the identity RFC — so it should be scoped and
owned jointly, before M1's MCP-facing work assumes it.

## Open questions

- **Fingerprint vs generation stamp coverage.** Confirm the same-role/same-label
  swap is the *only* hole the fingerprint misses, and that A3's shape-change
  definition (add/remove/reparent/keyed-ancestor change, **not** value ticks)
  bumps at exactly the right granularity — too coarse re-reads every step, too
  fine misses the swap.
- **Subscription value at our tree sizes.** Measure end-to-end latency + token
  cost of poll `wait_for_change` vs `subscribe`+push for a ticking dashboard — is
  WS-1 a measurable win or mainly spec-conformance/ergonomics? (Both justify it;
  this sizes it.)
- **Output sanitization without corrupting labels.** What sanitization neutralizes
  prompt injection in app-controlled label/value text while preserving labels the
  agent needs verbatim to act?
- **Settle: action-ack vs observed-generation.** A wire-level action
  acknowledgment is the most deterministic but more invasive; a per-call
  observed-generation is lighter. One, or both?
- **Single-session forever?** Does an agent ever drive several apps / reconnect
  across an app restart? Settles whether WS-5 needs reconnect.
- **Shared-spawn home.** `fleury_host_io` is a legal (`dart:io`) home — confirm
  extraction doesn't leak process concerns into a web-safe surface or regress
  `fleury serve`'s warm-standby path.

## References

- [Stable semantic ids + `setValue` RFC](rfc-stable-semantic-ids-and-setvalue.md)
  (identity derivation, `setValue` contract, the A3 handle WS-2 depends on).
- [`fleury_mcp` PR #19](https://github.com/danReynolds/fleury/pull/19) and its
  code-review findings (DataTable cross-fire, concurrency, press_key).
- Field: [Playwright MCP snapshots](https://playwright.dev/mcp/snapshots) ·
  [Playwright actionability](https://playwright.dev/docs/actionability) ·
  [WebArena](https://webarena.dev/static/paper.pdf) ·
  [SeeAct (arXiv 2401.01614)](https://arxiv.org/html/2401.01614v1) ·
  [Building Browser Agents (arXiv 2511.19477)](https://arxiv.org/html/2511.19477v1) ·
  [WebDriver stale element](https://developer.mozilla.org/en-US/docs/Web/WebDriver/Reference/Errors/StaleElementReference).
- MCP spec: [resources](https://modelcontextprotocol.io/specification/2025-06-18/server/resources) ·
  [tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools) ·
  [authorization](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization) ·
  [security checklist](https://github.com/slowmist/MCP-Security-Checklist).
