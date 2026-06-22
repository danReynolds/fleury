# Performance

Fleury is built to stay cheap as apps get busy. The performance story is
architectural — a few decisions in the core — rather than micro-optimizations
bolted on after the fact.

## Retained mode, incremental everything

Many terminal UIs are immediate-mode: every frame, your code re-describes the
whole screen and the framework redraws it. Fleury keeps a *retained* tree — widgets,
elements, and render objects, like Flutter. A `setState` marks one subtree
dirty; only that path rebuilds, re-lays-out, and re-paints. The rest of the tree
is reused untouched. A button label changing doesn't re-lay-out the table next
to it.

## Diff to the cells, not the screen

Layout and paint produce a grid of cells. The terminal target diffs the new grid
against the previous one and emits **only the cells that changed** as ANSI — no
full repaints. A frame with no changes emits nothing at all, so an idle app
costs nothing, and a busy app pays only for what actually moved.

## Data widgets are windowed

The data widgets — `DataTable`, `TreeTable`, lists — build only the rows that
are actually on screen. A hundred-thousand-row table costs about what a
screenful costs; scrolling rebinds the visible window instead of rebuilding the
dataset. Large, text-shaped data is a first-class case, not a cliff.

## The browser wire is a patch stream

When you stream an app to a browser with [`fleury serve`](/architecture/serving-and-embedding/),
the server doesn't ship repaints. Each frame is encoded as compact **cell-range
patches** against a shared style table, varint-packed, so a live, churning app
stays small over a socket. The [semantics tree](/architecture/agents-and-semantics/)
rides the same wire.

## Measured against peers, not asserted

Fleury is benchmarked against current releases of the frameworks people actually
reach for — Ratatui, Textual, Bubble Tea, Ink — using a scenario harness (data
tables, streaming logs, text editing, Markdown rendering) so the comparison is
about realistic workloads rather than a synthetic loop. The framework also ships
a built-in profiling surface, so you can see rebuild, layout, and paint costs in
your own app.
