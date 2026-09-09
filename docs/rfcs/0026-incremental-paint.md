# RFC 0026: Incremental Paint

**Status:** Implemented, off by default (see §9)

**Date:** 2026-09-09
**Builds on:** RFC 0024 derived geometry, RFC 0009 performance

## 1. Summary

A frame no longer starts from a cleared buffer. The frame loop carries the
previous frame forward into the buffer it is about to paint, erases the region
that changed, and the paint walk skips every subtree whose cells are still
valid where they sit.

The three facts that make this possible were already in the framework and were
not being used together:

- **The previous frame is already in memory.** The loop keeps two buffers and
  derives damage by comparing them. Carrying one forward makes it a cache of
  the whole screen — no per-subtree cache buffer, no blit, no placement
  decision, no miss penalty.
- **Screen geometry is derived, not declared** (RFC 0024). "Did this subtree
  move" is not something a widget can forget to report.
- **The invalidation walk already visits every ancestor.** Recording a bit on
  the way costs no extra traversal.

What was missing was only the erasing, and where to erase is derived too.

## 2. The frame, in two phases

**Phase 1 — damage.** Walk the tree. A node contributes damage when it is
dirty, or when the geometry layout now gives it differs from the geometry it
last painted at. Its contribution is two rectangles: everything its subtree
painted last frame, and everything its subtree is about to occupy — both
knowable before a single cell is written, because layout has run and geometry
is derived. Erase that region, once, up front.

**Phase 2 — paint.** Walk the tree. A node repaints if it is dirty or if its
subtree's footprint intersects the damage; otherwise it is skipped whole,
children included, and the carried cells stand.

### Why erasing is one pass and not per node

The first version erased a node's old rectangle just before repainting it.
That is wrong for a node that MOVES: by the time it paints, whatever replaced
it has often already painted there, and the erase wipes it. A subtree
reparented from the first slot to the second blanked the widget that took its
place. There is exactly one instant in a frame at which erasing cannot destroy
something: before the first cell of it is written.

### Why phase 1 walks the whole tree

Not only the path of something that was marked. A node moves without ever being
marked — a sibling above it grew — and because geometry is derived *globally*,
the cause can be in a different branch entirely: a float anchored to a widget
elsewhere moves with that widget while nothing on its own path is invalidated.
Comparing the geometry a node last painted at with the geometry layout now
gives it is the only way to see that, and it has to be asked everywhere.

The walk is pointer-chasing plus one memoized geometry read per node — the same
read the paint walk is about to make, at the same epoch, so it is computed
once. A subtree a composite paints into a buffer of its own is walked for the
same question, but the answer there decides only whether the COMPOSITE's
rectangle is damage: individual footprints inside a cache mean nothing.

A node with nothing on screen is the exception that has to be handled
explicitly. It writes no cells, and a container is free not to paint it at all
— several do. Since it is never painted it never clears its own dirty bit, so
it must GIVE UP the cells it owned, once, rather than re-damage them forever.

### Why there is no "my children do not overlap" declaration

An earlier version asked each container whether its children painted into
disjoint rectangles, and skipped only children of one that said yes. A region
makes it unnecessary. Overlap matters only when one of the overlapping nodes
changed — and a node that changed is damage, which forces everything it
touches to repaint, in tree order. One derived test replaces a contract every
render-object author could get wrong.

## 3. Footprints come from the buffer, not from geometry

A node's footprint — the cells it and its descendants own — is measured by
clearing the buffer's damage window, painting, and reading it back.

Geometry answers where a node **is**. It does not answer where its cells
**landed**, and the difference is not hypothetical: a slide effect shifts its
child's cells sideways, an expand effect writes rows its own box does not
cover. Deriving the footprint from geometry left their old cells un-erased,
and stale text sat next to the new.

A node whose cells go through a composite — a repaint boundary's cache, a
viewport, an effect — has no screen footprint of its own; the composite's blit
put them wherever it chose. Damage for a change under a composite is therefore
charged to the composite's rectangle.

## 4. What it makes visible

Full repaint hid a whole class of contract violation. If paint reads state
that no invalidation covers, a cleared buffer repaints it correctly every
frame and nothing is ever wrong. Carry it forward and the same code leaves a
ghost. Two shipped widgets did this, and both are fixed here.

It also hid an asymmetry in `RenderRepaintBoundary`: allocating its cache set
`needsPaint = true` from inside its own paint, which is a fact about the next
few lines, not an invalidation. Routed through the setter it raised a real
dirty mark on a node whose paint had already cleared its bits, so the mark
outlived the frame that serviced it.

## 5. The check that makes it adoptable

`IncrementalPaint.verifyAgainstFullRepaint` paints the same tree the old way
into a scratch buffer after each carried frame and requires the two agree cell
for cell, image placements included.

This is the only check that can see the failure the design makes possible. A
skipped subtree writes nothing, so if its carried cells were stale the buffer
still matches what was painted — and frame damage, derived by comparing the
two buffers, reports no change. The screen is wrong and everything downstream
agrees it is right.

CI runs the whole suite once with it on — `packages/fleury`'s suite, which is
where the mode is exercised. It is deliberately NOT armed from
`package:fleury_test`: that package is compiled to JS for the website's browser
tests, so it cannot read `Platform.environment`, and while the mode is off
everywhere else there would be nothing for it to verify anyway.

A test asserts the verifier catches a
render object that changes what it paints without marking itself, and a second
test asserts that same divergence is invisible without it — so the check is
never passing vacuously.

## 6. Measured

Interleaved A/B on the repo's own sample apps at 120x40 (`profiling`'s frame
pipeline host, five alternating runs, medians; every run agreed in direction).
Each mode is measured as a repeated homogeneous workload, so a frame is timed
in the steady state its mode describes.

| app | one label changes | nothing changes | everything invalidated |
| --- | --- | --- | --- |
| dashboard | 113 -> 46 us (**-59%**) | 113 -> 11 (-90%) | 230 -> 239 (+3.9%) |
| finance | 139 -> 55 us (**-60%**) | 139 -> 20 (-86%) | 227 -> 247 (+8.8%) |
| files | 74 -> 44 us (**-41%**) | 74 -> 10 (-87%) | 162 -> 169 (+4.3%) |
| agent | 61 -> 40 us (**-34%**) | 60 -> 5 (-92%) | 73 -> 77 (+5.5%) |
| editor | 58 -> 39 us (**-33%**) | 57 -> 3 (-95%) | 68 -> 71 (+4.4%) |

The middle column is the one to read: a localized update — the frame an
interactive app spends its time on — is 1.5x to 2.6x cheaper, on apps that
ALREADY place repaint boundaries (`Panel`, `ListView` rows and `Overlay`
entries all do). The right column is the price: a frame in which every render
object was invalidated pays for the damage walk and gets nothing back.

The probe mutates a `RenderText` directly rather than going through `setState`,
so build time is excluded from both sides: a real update adds the same build
cost to each, which dilutes the percentage without changing the difference.

Two costs had to be removed before the middle column looked like this, and
both are worth stating because both were larger than they sound:

- **Carrying the frame forward cost as much as clearing it.** The obvious
  implementation blits the whole grid; that was ~7 us a frame, every frame. It
  is unnecessary: the buffer being painted into holds the frame BEFORE last,
  and it differs from the previous frame only where the previous frame's own
  diff already said. Carrying is now proportional to what moved.
- **A node with nothing on screen was re-damaging its old footprint forever.**
  A container may decline to paint a child (a flex skips one entirely outside
  the buffer) without `presentsChild` saying so, and a node that is never
  painted never clears its dirty bit. Its stale footprint was damage on every
  frame, which repainted the enclosing composite on every frame — of every app
  with one off-screen child. With that fixed, an unchanged dashboard frame
  paints 0 render objects instead of 59.

## 7. What it costs

Two walks of the tree per frame instead of one, and a damage-window save and
restore around every painted node. On a frame where everything was invalidated
that is pure overhead — 4% to 9% — because nothing can be skipped and the
region covers the screen. That is the deliberate trade: the frames an app
actually spends its time on are the ones where little changed.

## 8. The one divergence left, and why the switch is off

`packages/storybook` renders a blank preview pane with the mode on. Some
subtree there is produced as a side effect of an ancestor's PAINT — its widgets
are not in the element tree at all when the pane is skipped — so skipping that
paint skips the work that would have created them. Disabling skipping alone
restores it; carry-forward, the damage region and the erasing are all
uninvolved, and the full-repaint verifier over `packages/fleury`'s entire suite
finds no divergence at all.

Two candidate rules were built and neither resolved it, so both are stated as
what they are — hardening, not the fix:

- A node whose paint lays something out is never skipped, because a
  `LayoutBuilder` run from inside paint builds widgets and mounts elements.
  Recorded rather than declared: the node that does it is the one that finds
  out, from the frame phase.
- `_subtreeDirty` is recomputed on the way back up instead of being left
  cleared, so dirt a paint never reached is not discharged by it.

Until the storybook case is understood the mode is opt-in. This package's own
test harness turns it on, so the machinery and its verifier stay exercised
rather than becoming dead code waiting for a flag.

## 9. Scope

The mode is per surface, declared by the presenter through
`FramePresenter.requiresSelfContainedFrames`. The terminal presenter diffs the
two buffers the loop already holds, so it accepts carried frames. `fleury
serve` keeps its own mirror of the screen and coalesces frames under
backpressure, so the wire's previous frame is not always the loop's; it keeps
self-contained frames until that is resolved on the serve side.
