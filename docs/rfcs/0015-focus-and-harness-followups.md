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

## C15 — Durable scope focus-memory across pane unmount — **WITHDRAWN (wrong design)**

**Observation.** Scope focus-memory lives on the `_FocusScopeMarkerElement`, so
it dies with the element. The pane pattern `build(active ? A() : B())` *unmounts*
the inactive pane, so re-entry mounts a fresh marker with no memory —
`restoreFocusInScope`'s "re-entered pane" wording doesn't hold for unmounted panes.

**Original proposal (rejected).** Key memory by a stable scope identity in the
manager so it survives unmount/remount.

**Why it's the wrong design.** Focus dying on unmount is not a bug — it is
*consistent* with every other piece of State (scroll position, text drafts,
ephemeral fields all die on unmount too). Making focus alone survive would be a
focus-specific special case for something no other state gets, with surprising
lifetime/eviction semantics.

**The correct answer: keep the pane mounted.** If a surface wants to preserve a
pane across switches, don't unmount it — and Fleury already has the primitive:
`IndexedStack` (basic.dart), whose own doc says it "keeps the rest mounted but
unpainted, so their state survives switching between them — the basis for tabbed
or paged surfaces that must remember each page." Mounting-toggle preserves focus
*and* scroll *and* drafts, together, for free.

**This matches Flutter exactly.** Flutter has no ambient cross-unmount focus
memory either — unmounting destroys State the same way. Flutter's answers are (a)
keep the subtree mounted (`IndexedStack`/`Offstage`/`KeepAlive`), or (b)
`RestorationScope`/`restorationId` — which is for state restoration across
*process death / app relaunch* (serialized), a different concern from
within-session pane switching.

**Recommendation:** no framework work. A consumer that wants section-state
persistence (e.g. dune_cli's home) uses `IndexedStack` for its sections instead
of a `switch`-that-returns-one-screen. That is an app-level product choice
(persist each section vs. fresh-on-entry), not a Fleury gap.

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

- **C14 — defer** until the second modal producer (the palette) makes the
  shared "active scope" abstraction pay for itself. The focus-steal it would
  have prevented is already fixed structurally by `ExcludeFocus`, so there is no
  correctness gap open in the meantime.
- **C15 — withdrawn.** Not a framework change: focus dying on unmount is
  intended, and the fix for panes that must persist is to keep them mounted
  (`IndexedStack`, which already exists) — an app-level choice, matching Flutter.
- **C16 — defer** to its own suite-audited PR (flip `pump()` to a full frame,
  fix the fallout, review). High-churn, DX-only payoff, and a framework-owner
  call on whether fast build-only pumps are worth keeping.

The through-line lesson from PRs #24 and #26 — *locally-correct focus/render
changes leak globally; gate them* — is exactly why none of these ships as a
speculative add.
