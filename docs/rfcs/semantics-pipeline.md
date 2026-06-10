# RFC: Retained, geometry-bearing semantics pipeline

Status: proposed (companion to `web-render-backend.md`, recommendation R1)
Motivation: make Fleury's accessibility/semantics a first-class frame output so
the web host can be an *accessible, structured* app — the differentiator over
xterm.js/Ratzilla — and so caret/focus/selection have a shared spatial model.

## 1. Why this exists

The native web host RFC depends on a `SemanticDomPresenter` that projects Fleury
semantics into a live ARIA DOM, kept in sync with each visual frame, with stable
identity and geometry correlation. The current semantics subsystem cannot
support that, and several apparently-separate problems turn out to be one missing
capability.

This RFC proposes the core change that unblocks it. It is framework-wide, not
web-only: a better semantics pipeline also benefits testing (durable selectors),
agent/remote mirrors (the code already anticipates these), and any future host.

## 2. Current state (evidence)

- **Rebuilt fresh, on demand, not per-frame.** `SemanticTree.fromElement` walks
  the element tree from scratch (`semantics.dart:522`), wired only through a
  debug provider (`run_tui.dart:515`, `setSemanticTreeProvider`). Production
  frames do not build semantics.
- **No geometry.** `SemanticNode` carries role/label/value/state/children and
  flags, but no `CellRect`/`CellOffset` (`semantics.dart:437`). There is no link
  from a node to the cells it painted.
- **Identity is opt-in.** Stable only with an explicit `id`/`Key`; otherwise
  `element-<hashCode>`, unstable across rebuilds (`semantics.dart:720`). The
  file's own comment notes stable IDs are "required by future
  incremental/observable semantic backends, remote/agent mirrors, durable test
  selectors."
- **Caret is not data.** Text input exposes `selectionBase`/`selectionExtent`
  character offsets in semantic state; the caret's painted cell is computed
  inside `RenderTextInput` paint and discarded. No rect, no cell coordinate.
- **Rich content already exists.** 52 `SemanticRole`s, 15 `SemanticAction`s, an
  extensible `SemanticState`. The *content* model is strong; identity, geometry,
  retention, and lifecycle are the gaps.

## 3. The unification insight

These web-host open questions are the **same** missing capability:

| Open question | Resolved by |
| --- | --- |
| IME caret-geometry hook | node/caret carries a painted `CellRect` |
| Stable semantic IDs for incremental ARIA | retained tree keyed by stable identity |
| Which semantic model long-term | the retained tree *is* the model |
| Focus/AT coherence | focused node ↔ caret rect ↔ cell region share one space |
| Semantic updates synced to visual commits | semantics is a frame output, diffed with paint |
| Selection ↔ semantics / copy-as-structure | cell↔node mapping from geometry |

One capability — **a retained, stable-identity semantics tree whose nodes carry
painted geometry, produced every frame** — answers all six.

## 4. Target capabilities

1. **Retained tree.** Persist across frames; diff (dirty-node) rather than
   rebuild. Mirrors Flutter's `SemanticsOwner`.
2. **Framework-owned identity by default.** Identity is derived from retained
   element/render identity rather than snapshot-local hash strings; `id`/`Key`
   still override, and keyed identity remains required for reorderable or
   virtualized collections.
3. **Painted geometry per node.** Each node carries the `CellRect` it occupied
   this frame (and clip), so it correlates to the visual grid.
4. **Caret/selection geometry.** The focused text field exposes its caret
   `CellRect`; selection geometry is expressible in the same space.
5. **Frame-synchronized production.** Built/updated in the frame pipeline, not a
   separate on-demand element walk, so visual and semantic commits agree.
6. **Bounded cost.** Always-on for web (a11y is the product), but incremental and
   gated so it does not pay full-tree cost on a one-cell change. (Flutter keeps
   semantics off until an AT is detected, ~30% frame cost when on — Fleury web
   should default it on but keep it incremental; native can keep it AT-gated.)

## 5. Design options

**A. Render-object semantics (Flutter model).** RenderObjects describe a
semantics configuration; a `SemanticsOwner` builds the retained node tree from
the render tree, taking each node's `rect` from the render object's paint bounds.
Geometry and stable identity are natural (render objects are persistent and
positioned). Cost: moves contribution from the element level (where Fleury's rich
app roles currently live) toward the render level.

**B. Element contribution + geometry correlation (incremental).** Keep semantic
*content* contributed where it is today (`SemanticContributor.buildSemanticNode`,
`SemanticChildrenProvider`), but (i) assign stable identity from the element, and
(ii) attach the painted `CellRect` by correlating each contributing element with
its render object's paint geometry during the frame; retain and diff the tree.

**C. Hybrid (recommended).** Keep the rich element-level *content* model
(option B's strength — the 52 roles describe app concepts, not render
primitives), but make the **owner** retained and frame-synchronized, source
**identity** from element identity, and source **geometry** from the contributing
element's render object paint bounds. This preserves Fleury's expressive
app-semantics while gaining identity/geometry/retention. It is the smallest
change that delivers all target capabilities.

## 6. Recommended direction

Adopt **option C**:

- Introduce a retained `SemanticsOwner` that holds the previous tree and produces
  a diff each frame (added/removed/updated nodes) for incremental consumers.
- Give every contributing element a framework-owned `SemanticNodeId` derived
  from retained element/render identity, overridable by `id`/`Key`. Do not
  promise durable identity for unkeyed dynamic-list items across reorder; keep
  keys as the durable app-authored identity mechanism.
- Add a `CellRect? bounds` (and clip) to `SemanticNode`, populated from the
  contributing element's render object paint geometry. Empty/zero for nodes with
  no visual extent.
- Expose **caret geometry**: the focused text input publishes its caret
  `CellRect`; `WebFocusCoordinator`/`CompositionController` consume it directly.
- Produce/update semantics **in the frame pipeline** behind a flag
  (`semanticsEnabled`): default on for web hosts, AT-gated for native. On web,
  disabling semantics is diagnostics-only because the retained visual grid is
  `aria-hidden`; callers must acknowledge that with an explicit
  `allowInaccessibleDiagnostics` option.

Non-goal: do not flatten the rich role model down to render primitives. The
app-level roles are an asset; this RFC adds identity/geometry/lifecycle around
them, it does not replace them.

## 7. Consumers unblocked

- **Web `SemanticDomPresenter`:** incremental ARIA from the node diff; nodes map
  to grid regions; links from semantic data; live regions only where requested.
- **IME:** caret `CellRect` → hidden-textarea/candidate-window placement.
- **Selection/copy:** cell→node lookup enables copy-as-structure and AT-aware
  selection.
- **Native screen-reader / remote-agent mirrors / durable test selectors:** the
  retained, stable-id tree the existing code comments anticipate.

## 8. Cost and risks

- **Per-frame semantics cost.** Mitigated by incremental diffing + the enabled
  flag. Measure against the same frame budget as the web render gate; native
  keeps it AT-gated so non-AT native sessions pay nothing.
- **Geometry plumbing.** Requires the frame pipeline to associate contributing
  elements with render paint bounds. Aligns with R2's damage work (both need
  paint-time geometry), so sequence them together.
- **Identity stability for dynamic lists.** Framework-owned identity is stable
  for retained nodes, but unkeyed reorderable/virtualized lists still need
  explicit keys for durable semantic identity. The RFC should not hide that
  requirement behind a generic "stable by default" claim.
- **Scope creep.** Keep the content model frozen; ship identity/geometry/owner
  first, rich ARIA projection second.

## 9. Phasing

1. Retained `SemanticsOwner` + framework-owned IDs for retained contributors
   (no behavior change for existing debug/test consumers).
2. `CellRect bounds` on nodes, populated from paint geometry; caret rect on
   focused text input.
3. Frame-pipeline production behind `semanticsEnabled` (default on for web;
   disabling it requires an explicit inaccessible-diagnostics acknowledgement).
4. Node-diff API for incremental consumers; wire `SemanticDomPresenter`.
5. Selection/copy cell↔node mapping; native AT and remote-mirror consumers.

## 10. Open questions

- Render-object vs element as the geometry source for nodes that contribute
  content but delegate painting to children.
- Exact identity scheme for unkeyed dynamic lists.
- Whether native should ever default semantics on (debug/inspection value) or
  remain strictly AT-gated.
- Where caret geometry should live: on the focused `SemanticNode`, or a separate
  `FocusGeometry` channel consumed by IME/selection.
