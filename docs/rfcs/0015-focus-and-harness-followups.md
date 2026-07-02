# RFC 0015 — Focus-scope activation & harness-frame follow-ups

Status: **Deferred (design captured)** · Origin: the pre-merge review of the
app-feedback branch (PR #24) surfaced three architecture-depth items that are
deliberately *not* in that PR or its cleanup follow-up. Each is a real
improvement, but each is a generalization ahead of a demonstrated consumer need
and carries the exact regression profile the review just caught (a
locally-correct focus/render change leaking globally). This RFC records the
analysis and the recommendation so the decision is teed up rather than made
silently.

## Context

After PR #24, focus restoration works and is tested: on `pop`, the revealed
route restores focus via its `FocusScope` memory (`restoreFocusInScope`), with
a push-time snapshot fallback for focus held outside the navigator. Covered
routes are focus-inert (`ExcludeFocus`). The test harness's `settle()` runs a
production-shaped frame; `pump()` remains build-only.

Three follow-ups were proposed. All three are sound; none is urgent.

---

## C14 — "Scope activation" as a focus-system concept

**Observation.** The restore *trigger* lives in the navigator: each route
carries a `restoreKey` (GlobalKey) and `pop()` hand-calls
`restoreFocusInScope`. The focus system can distinguish an *empty* scope from
an *occupied* one (`scopeHasFocusedNode`) but has no notion of an *active* vs
*inactive* scope. So every future modal producer (an overlay dropdown, the
command palette) that wants focus-trap + restore must copy the navigator's
choreography by hand: `requestFocus(null)` on open, hold a context, call
`restoreFocusInScope` *before* unmounting.

**Proposal.** Give the focus system a first-class "active scope": a scope that
becomes active claims focus (restoring its remembered child), and a scope
deactivating restores the previously-active scope. The navigator's GlobalKey +
pop-call plumbing collapses into "mark this route's scope active/inactive."

**Assessment — defer.**
- The only modal producer today is `present()`, which the navigator already
  drives correctly (tested). Command palette / dropdowns are hypothetical.
- "Active scope" is a genuinely new axis in the focus model (today: focused
  node + modal frontier). Adding it touches the same code paths PR #24 just
  stabilized — high blast radius for zero current consumer.
- **Recommendation:** revisit when the *second* modal producer lands (the
  palette). At two consumers the shared abstraction pays for itself; at one it
  is speculative generalization. Until then, if a new producer appears, factor
  a small `NavigatorState`-style helper it can reuse rather than pushing the
  concept into the focus core.

## C15 — Manager-keyed scope memory (survive pane unmount)

**Observation.** Scope focus-memory lives on the `_FocusScopeMarkerElement`, so
it dies with the element. `restoreFocusInScope`'s doc advertises "a re-entered
pane," but the standard pane pattern — `build(active ? A() : B())`, which
*unmounts* the inactive pane — destroys the marker; re-entry mounts a fresh one
with no memory. So cross-pane focus restoration silently never works outside
the navigator (where lower routes stay mounted).

**Proposal.** Key memory by a *stable* scope identity in the manager, not the
element, so it survives unmount/remount.

**Assessment — defer (it is a feature, not cleanup).**
- There is no stable identity across unmount/remount unless the app supplies
  one — i.e. this needs new API surface: `FocusScope(restorationId: '…')`, a
  manager-side `Map<Object, FocusNode>` keyed by it, and an eviction policy
  (when is a remembered node stale forever?). That is a focus-restoration
  *feature*, comparable to Flutter's `RestorationScope`.
- No consumer has asked for it. dune_cli switches sections by unmounting panes
  and is well served by autofocus-on-re-entry; "return to the exact widget you
  left in Conversations after visiting Posts" is a nicety nobody requested.
- **Recommendation:** build it when a consumer wants durable per-region focus
  restoration, as its own small RFC with the `restorationId` surface — not as
  ambient behavior (ambient cross-mount memory has surprising lifetime/eviction
  semantics).

## C16 — Make `pump()` a full production frame

**Observation.** `settle()`-steps are production-shaped (build → layout/paint →
drain); `pump()` is build-only. So `event → pump() → assert` against a tree with
a `LayoutBuilder` reads the *previous* render's layout-built subtree. The
divergence is documented as a caller burden ("call `render()` before `pump()`
when a post-frame callback needs geometry").

**Proposal.** Make `pump()` itself a full frame; `settle()` becomes a loop of
pumps. One frame semantics, no divergence.

**Assessment — defer (needs its own reviewed sweep).**
- `pump()` is the most-used test primitive; making it lay out + paint on every
  call is a behavior change to the entire suite. The review already showed
  `settle()`'s render-per-step surfaces latent layout-time throws (the
  `LayoutBuilder` unbounded assert, constraint violations) that build-only
  pumps never hit — so this needs a full-suite audit, not a one-line change.
- Fleury's build-only `pump()` is arguably load-bearing: fast, allocation-free
  pumps are useful for pure state assertions. Flutter's `pump()` does lay out;
  Fleury diverged deliberately. Whether to converge is a framework-owner call.
- **Recommendation:** if pursued, do it as a dedicated PR: flip `pump()` to a
  full frame, run the whole suite, fix the fallout, and review — the same gate
  discipline PR #24 used. Not a cleanup-commit change.

---

## Decision

Ship the mechanical cleanup (done). Hold C14–C16 behind demonstrated need:
C14 at the second modal producer, C15 when a consumer wants durable
region-restoration (as a `restorationId` RFC), C16 as its own suite-audited PR.
The through-line lesson from PR #24 — *locally-correct focus/render changes leak
globally; gate them* — applies most to exactly these three.
