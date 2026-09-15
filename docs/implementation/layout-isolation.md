# Root-driven layout isolation

A child change has two effects that need not be identical: work must run inside
its subtree, and ancestor geometry may need recomputing. Fleury keeps both facts
in the render tree instead of scheduling detached layout roots.

## Contract

- `markNeedsLayout()` marks the changed object's layout inputs dirty. Work stays
  reachable along its entire ancestry, with or without a frame damage tracker.
- An `isolatesChildLayout` container promises that both its allocated size and
  all intrinsic dimensions are independent of descendant layout changes.
  `RenderSizedBox` opts in only when width and height are explicitly specified.
  Its own property changes still invalidate parent geometry normally.
- Above that container, ancestor geometry can remain cached while descendant
  work remains pending. Tight constraints alone cannot make this promise: a
  parent may have derived them from intrinsic measurements.
- Audited containers can opt into `canReuseLayoutForDescendantChanges`. They
  visit dirty live children with their previous constraints, check the returned
  sizes, and reuse their geometry only if sizes and their own inputs stayed
  unchanged. Otherwise they run normal layout immediately.
- Row/Column, padding, and sized boxes opt into that traversal. All other render
  objects retain their normal `performLayout` behavior, including intrinsic
  consumers and error boundaries. Custom render objects are conservative by
  default; overriding either protected hook requires preserving its contract.

There is no queued-node ownership, depth sorting, detach cleanup, second layout
phase, or public widget parameter. Parent calls remain on the stack, so errors
reach the same containment scope as ordinary layout. A removed child disappears
from the traversal; a moved child receives its new parent's constraints.

First-layout error recovery is a significant exception to stable size: an error
boundary's initial fallback extent may differ from the recovered subtree. The
size check detects this and recomputes ancestor offsets in the same traversal.
The regression suite includes this case.

`markNeedsPaint()` retains its existing conservative contract. Its audited
paint-only counterpart remains available. Layout invalidations still record
conservative frame damage because cells inside a fixed box can move or vanish.

## Why this scope

A general intrinsic-dependency graph and independent layout scheduler would
introduce dependency registration, error-scope reconstruction, and lifecycle
bookkeeping. Explicit fixed-size containers already give a narrower proof of
isolation. Reusing only audited parent algorithms realizes that benefit without
changing custom layouts or the frame driver's ownership.

The original PR #251 benchmark called `markNeedsPaint()` without changing real
content. Changing that method's contract did not demonstrate a production
layout benefit. The replacement workload changes actual text content, including
wrapping, inside status panes. It keeps paint work present in the timings.

## Correctness evidence

`packages/fleury/test/rendering/layout_isolation_test.dart` contains 16 tests:

- The eight original PR regression probes: intrinsic width through wrappers,
  error containment/recovery, removed dirty nodes, and ownerless render trees.
- Parent reuse with unchanged pane extent, explicit pane resizing, one-axis
  sizing, and conservative custom-parent behavior.
- Containment above the isolated pane, first-error recovery with a size change,
  reparenting under new constraints, and intrinsic-height updates.
- Two independent trees across 160 uninterrupted mutations: incremental layout
  versus forced full layout. Content includes wide graphemes and newlines;
  mutations include wrapping, pane dimensions, viewport constraints, and order.
  Every output cell and pane geometry must match.

The original eight probes passed on main and failed on the original PR. All 16
pass with the replacement. Full core/widget, repaint-cache, and performance gate
results are recorded separately as validation completes.

## Performance evidence

Run `dart run bin/layout_isolation_probe.dart` from `profiling`, or compile that
file with `dart compile exe`. Baseline was main `f52b0007`, using identical probe
source and Dart 3.12.2. The AOT runs used 5,000 updates per configuration and
reversed baseline/candidate order for the second run. These are informational
rendering measurements on one machine, not end-to-end application speed claims.

| Panes | Layout calls/update | Main layout p50 (us) | Candidate layout p50 (us) | Main frame p50 (us) | Candidate frame p50 (us) |
| --- | --- | --- | --- | --- | --- |
| 16 | 4 → 2 | 1.21 | 0.92–0.96 | 6.25–6.50 | 6.08–6.38 |
| 40 | 4 → 2 | 1.08–1.13 | 0.25–0.29 | 13.71 | 13.54–14.00 |
| 96 | 4 → 2 | 1.54 | 0.96–1.00 | 31.88–32.25 | 31.42–31.79 |

The deterministic improvement is avoiding two parent layout algorithms per
update. Layout time improves in this workload. Total-frame differences are
small and the 40-pane timings straddle baseline; painting remains dominant.
This supports a focused layout optimization, not a general application speedup.
Raw results live in `docs/audits/evidence/2026-09-15-layout-isolation/`.

Further opt-ins require both a proof that prior child constraints/offsets remain
valid and tests against full layout. One-axis isolation and general tight-node
scheduling are deliberately outside this change.
