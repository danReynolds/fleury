# RFC 0024: Derived Geometry

**Status:** Implemented

**Date:** 2026-09-05
**Builds on:** RFC 0007 framework, RFC 0009 performance, semantics pipeline RFC

## 1. Summary

A render object's position on screen is derived from layout state, on
demand, and nothing about geometry is recorded during paint.

Every container declares three facts about each child — where it put it
(`childOffsetOf`), what it clips it to (`childClipOf`), and whether it
presents it at all (`presentsChild`) — and `RenderObject.screenGeometry()`
composes them up the parent chain into a `RenderGeometry` (full bounds, the
accumulated clip, the visible part). Pointer hit-testing, focus rectangles
and carets, semantic bounds, bounds observers and anchors, text selection,
and the scrollbar drag map all read that.

`paint` became a non-virtual template: `paint(buffer, offset)` records the
placement in debug mode, checks it against the contract, and delegates to
`performPaint`. The buffer's bounds are the clip; no screen offset or clip
rectangle is threaded through paint any more.

## 2. What it replaces

Before this change four "capture channels" (`PointerRegionCapture`,
`FocusGeometryCapture`, `SemanticPaintBoundsCapture`,
`RetainedPaintGeometryCapture`) recorded screen rectangles while a subtree
painted, and `RenderRepaintBoundary` kept the records so a cache hit could
replay them at the boundary's new screen position. `paint` carried a
`screenOffset` (the true screen position of a scratch-local `offset`) and a
screen-space `clipRect` for that purpose, and every composite (viewport,
clip, effect, overflowing flex) re-derived both for its children.

That design had three costs. It was the framework's one real complexity
hotspot: 770 lines of capture scaffolding, a replay per boundary per frame,
a clip scope, and a `screenOffset`/`clipRect` pair on 53 paint signatures.
It could be wrong: a subtree that stopped painting kept its last recorded
geometry (a focusable under an opaque overlay still reported the rectangle
it had before), and the retraction sweep needed an anti-spin set to stop
hidden observers from requesting a frame forever. And it cost paint time on
the hot path: recording and replaying at every boundary on every frame.

## 3. Design

### 3.1 The contract

```dart
// On RenderObject; containers override what applies.
CellOffset childOffsetOf(RenderObject child) => CellOffset.zero;
bool presentsChild(RenderObject child) => true;
CellRect? childClipOf(RenderObject child) => null;
bool get hitTestsBeyondBounds => false;
void visitRenderChildren(void Function(RenderObject child) visitor);
```

A container answers from the same state its paint uses: `RenderFlex` from
its child offsets, `ScrollView` from `(0, -controller.offset)` with its own
box as the clip, `IndexedStack` presents only the active index, the
navigator presents only the routes from the first opaque one, an overlay
entry only while visible, the lazy list only the mounted window, an error
boundary nothing while it shows an error, a bounds anchor its child only
while the observed widget is visible, and `RenderTable` answers per region
(pinned header, scrolled body) with different clips.

### 3.2 Derivation and memoization

`screenGeometry()` resolves the parent chain: origin accumulates
`childOffsetOf`, the clip intersects `childClipOf` (a zero-sized clip means
"fully clipped"), and `presentsChild` false anywhere above yields null. The
screen itself is the outermost clip (`RenderDamageTracker.screenSize`, set
by the owner before layout).

Results are memoized per node against `RenderDamageTracker.geometryEpoch`,
which advances on every invalidation and at the start of every paint pass.
A memo hit allocates nothing and returns the same `RenderGeometry` instance
while nothing moved; a miss resolves the chain once and leaves every
ancestor memoized for the other queries of that epoch. Deriving geometry for
all 438 render objects of the probe fixture costs ~115 µs, down from ~360 µs
for the unmemoized walk.

### 3.3 Consumers

- **Pointer.** `PointerRouter` hit-tests the rendered tree top-down from
  `root` (set by the runtime and the tester after each frame). A subtree is
  pruned by its box unless it says `hitTestsBeyondBounds` (a `Stack`, whose
  `Positioned` children may overflow), and by any clip. Walk order is paint
  order, so the topmost region is the last hit. Hover, press, and drag
  capture reconcile after every frame against reachability: a target that
  left the tree, is no longer presented, or is fully clipped out is
  dropped, as the registry dropped it.
- **Focus.** `FocusNode.rect` and `caretRect` are getters over a
  `ScreenGeometrySource` (the `Focus` widget's render object) and a
  `CaretHost` (an editable's render object exposing `localCaretRect`).
  Hosts attach when the widget's render object is created and detach when
  the widget unmounts, so an app-owned node that outlives its widget
  reports nothing and retains no dead subtree. Traversal resolves each
  node's rect once per sort.
- **Semantics.** `_RenderSemanticBounds` is a plain pass-through box; a node
  derives its bounds at collection. When a paint pass ends,
  `SemanticDirtyTracker.refreshGeometry` re-derives every mounted node and
  records the ones that moved as retained leaf updates — how a scroll
  (a paint-only invalidation) reaches the wire with nothing recorded.
- **Bounds observation.** `BoundsNotifier` carries a `RenderGeometry`;
  `BoundsAnchor` reads the observed widget's `liveGeometry` during its own
  frame, so anchoring no longer depends on paint order. Observers remain
  paint-pass participants, but the sweep now asks them to re-derive
  (`refreshPaintFacts`) rather than retract; publishing an unchanged fact
  notifies nobody, so a hidden observer never spins.
- **Selection.** `selectionPaintRect` / `selectionClipRect` are the derived
  bounds and clip. The error boundary's semantic node uses the boundary's
  own geometry.

### 3.4 Paint is checked against the contract

```dart
@nonVirtual
void paint(CellBuffer buffer, CellOffset offset) {
  assert(_debugCheckPaintPlacement(buffer, offset));
  performPaint(buffer, offset);
}
```

In debug mode every paint records `(buffer, offset)`; a child painted into
the same buffer as its parent must land at
`parent.offset + parent.childOffsetOf(child)` and must be a child the parent
`presentsChild`. A composite that paints into a scratch buffer is skipped at
that boundary and checked again below it. Every painted frame of every test
therefore verifies the contract; a container that forgets it fails loudly
with the two offsets in the message. `derived_geometry_contract_test.dart`
adds the buffer-truth check: a probe's label is located in the rendered
frame and compared with its pointer, focus, and semantic geometry across the
container zoo (flex/padding/border/align, stack/positioned/indexed/wrap,
scroll view, lazy list, cached repaint boundary across a scroll, opaque
overlay).

## 4. Measured

Probe: `profiling/bin/geometry_probe.dart`, 1000-row `ListView.builder`
(60 mounted, 122 pointer regions, 438 render objects), 120×60. "Late" rows
are re-measured after every other row so JIT warmth is comparable; the
before column is commit `ffb0b32f` (capture channels), the after column
this change. Mean / p50 in µs.

| path | before | after |
| --- | --- | --- |
| frame with nothing dirty | 51 / 37 | 36 / 34 |
| paint: one row changes | 104 / 59 | 53 / 52 |
| paint: all mounted rows change | 1067 / 1009 | 998 / 949 |
| pointer: hover event | 0.6 / 1 | 4.7 / 4 |
| pointer: tap + frame (p50) | 62 | 101 |
| semantics: full snapshot | 904 / 831 | 916 / 868 |
| geometry of every render object | 361 / 336 | 115 / 76 |

Paint is cheaper on every axis. A hover costs a tree walk instead of a
registry scan — a few microseconds — and a tap pays two of them. The
perf gates (`benchmark gates`, `wire-gate`, `serve-wire-live`) pass without
re-baselining; the wire gate's bytes moved -2.7%.

## 5. Writing a render object

- Override `performPaint(buffer, offset)`; call `child.paint(buffer, …)`.
  There is no screen offset and no clip parameter: paint at buffer-local
  offsets, and let the buffer's bounds clip.
- Declare `childOffsetOf` wherever a child is painted anywhere but at your
  own offset; `childClipOf` wherever you clip; `presentsChild` wherever a
  mounted child is not painted this frame. The debug check tells you the
  moment paint disagrees.
- Answer `hitTestsBeyondBounds` true only if children may sit outside your
  box and must stay interactive there.
- Override `visitRenderChildren` to iterate in place if your `children`
  accessor copies.
- Never store screen geometry: ask `screenGeometry()` when you need it.

## 6. Open items

- `Stack` keeps overflowing `Positioned` children interactive
  (`hitTestsBeyondBounds`), matching the old registry rather than Flutter's
  box-bounded rule. Revisit if a container wants the pruning more than the
  overflow.
- The end-of-pass semantic sweep is O(mounted semantic nodes) per frame
  (~60 µs on the probe fixture at 60 nodes). A generation stamp on subtrees
  that did not move could skip most of it if it ever shows up.
