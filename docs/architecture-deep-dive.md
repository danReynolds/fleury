# Architecture deep dive

The [architecture overview](architecture-overview.md) gives the map. This page
goes into the machinery: why Fleury keeps several retained trees, what each tree
owns, how a state change becomes changed cells, and where terminal/browser
targets begin.

Fleury is not an ANSI string builder with widgets on top. It is a retained UI
engine for a cell grid. Every visual target consumes the same framework output:
a damage-tracked `CellBuffer`. Semantics are a parallel product of the same
mounted tree, projected or shipped by tests, browser hosts, served sessions,
agents, and debug tooling. That distinction is deliberate: the terminal
renderer should not need an accessibility tree to write ANSI, and the browser
should not need to scrape visual rows to be accessible.

## The short version

- **Widgets** are cheap configuration values.
- **Elements** hold identity, state, dependencies, and the dirty build queue.
- **Render objects** lay out integer cells and paint styled graphemes into a
  `CellBuffer`.
- **Semantics** describe meaning, state, geometry, and actions for tests,
  accessibility, and agents.
- **Hosts** own platform concerns: terminal drivers, browser DOM surfaces,
  input sources, frame scheduling, clipboard, sockets, and focus integration.

That split is the main architectural decision. It gives app authors a Flutter-
style programming model, while letting Fleury optimize for terminal realities:
cell widths, ANSI bytes, scroll reuse, terminal capabilities, browser cell
metrics, and machine-readable semantics.

## The retained trees

### Widget tree: configuration

Widgets are immutable descriptions of the UI. A rebuild creates new widget
objects freely; the framework decides whether the mounted tree underneath can be
reused.

The compatibility rule is intentionally small: a new widget can update an old
one in place when `runtimeType` and `Key` match. That preserves the element,
state, and render object below it. Fleury also has an internal
`WidgetUpdatePruner` hook for widgets that can prove a new configuration is
equivalent, so the reconciler can skip work without changing the public mental
model.

This is why keys matter. A local key tells the parent which child identity should
survive. A `GlobalKey` can move a subtree to a different parent in the same build
pass while preserving its `Element`, `State`, and render subtree.

### Element tree: identity and state

Elements are the durable spine. `State.setState` mutates app state immediately,
then marks the owning element dirty. The `BuildOwner` keeps a dirty set, sorts it
shallow-first, rebuilds only those elements, and finalizes any deactivated
subtrees that were not reclaimed by a global-key move.

That shallow-first rule matters: if a parent rebuild replaces a child subtree,
the framework should not also spend time rebuilding a now-discarded child. If
new dirt appears during a rebuild, the owner picks it up in the next flush pass.

The element tree also owns dependency and lifecycle behavior: mounted vs
deactivated vs unmounted, `didUpdateWidget`, `didChangeDependencies`, hot reload
`reassemble`, and the bridge from widgets to render objects.

### Render tree: cell layout and paint

Render objects implement the constraints-down, sizes-up protocol using integer
cell geometry. A parent calls `layout(CellConstraints)`, the child returns a
`CellSize`, and the parent later paints the child at an absolute `CellOffset`.
There is no pixel canvas in the core; paint writes cells.

The render layer has two invalidation paths:

- `markNeedsLayout` is for anything that can affect size, child constraints,
  child offsets, or layout-derived paint.
- `markNeedsPaintOnly` is for audited visual-only changes such as color, cursor
  blink, and style.

Fleury keeps this conservative by default. A layout-affecting change can make
old cells disappear without writing over them, so the presenter cannot trust a
paint-bounds hint for that frame. Paint-only changes can stay bounded by the
cells written during paint.

`RenderRepaintBoundary` is also deliberately different from a Flutter layer. It
is a CPU paint cache for a subtree: on a clean frame it blits cached cells into
the next frame buffer instead of re-walking the subtree. It is not a GPU layer,
and it is not a blanket performance answer. It is useful for paint-expensive
subtrees that change rarely.

### CellBuffer: frame truth and paint damage

`CellBuffer` is the frame image: a two-dimensional grid where each cell is a
grapheme plus style and role metadata. It enforces wide-grapheme invariants, so
writing over one half of a wide character repairs the neighboring cell instead
of leaving an impossible grid.

During a frame, the buffer records paint damage: a conservative rectangle plus
the exact rows written. Clearing the back buffer is done with damage suppressed,
then damage tracking starts before framework paint. That way reconstructing the
next frame does not itself count as user-visible damage.

The damage signal is a hint to diffing presenters, not the source of truth. The
source of truth is always the previous and next buffers. When damage is unsafe
or missing, presenters fall back to buffer diffs.

### Semantics tree: meaning and actions

The semantics tree is a typed model of what the UI means. A `SemanticNode`
contains an id, role, label, value, state, optional bounds, supported actions,
and child nodes. Tests query it. The browser target projects it into an
accessible DOM. Served sessions ship it over the wire next to visual frames.

The current producer can still rebuild a snapshot by walking the element tree,
but the model is intentionally delta-ready:

- `SemanticsOwner` retains the last snapshot and reports added, removed, and
  updated node ids.
- `SemanticDirtyTracker` records full-rebuild dirt or retained leaf updates per
  `BuildOwner`.
- Retained leaf replacement is checked against a full semantic rebuild in debug
  mode, so a missed escalation becomes a loud divergence instead of a silent
  accessibility bug.
- Semantic actions can be invoked back into the mounted element tree, which is
  how tests and the served browser accessibility tree drive the real app.

That is why semantics are documented as architecture, not a testing add-on. They
are one of the retained products of the framework. They are not globally
incremental yet: leaf-only updates can take the retained path, while structural
changes intentionally escalate to a full semantic rebuild.

## One update through the engine

Here is the visual path for a normal state change:

1. An input event, timer, animation tick, task update, or semantic action changes
   state.
2. `setState` or a render-object setter marks the relevant element or render
   object dirty.
3. The host `FrameScheduler` coalesces pending frame requests. With the default
   `Duration.zero` interval it flushes as soon as possible; hosts may opt into a
   minimum frame interval to merge high-rate streams.
4. `BuildOwner.flushBuild` rebuilds dirty elements shallow-first.
5. `BuildOwner.renderFrame` finds the root render object, attaches this
   runtime's damage tracker, runs layout with loose root constraints, and paints
   into the back `CellBuffer`.
6. `TuiFrameLoop` clears the back buffer without damage, enables damage
   tracking for paint, captures paint bounds/rows, consumes render damage, and
   returns the previous buffer, next buffer, and `TuiFrameDamage`.
7. A presenter turns that into output:
   - The terminal target calls `AnsiRenderer.renderDiff(previous, next, ...)`,
     bounded by damage when safe.
   - The embedded browser target builds a `FramePresentationPlan` and replaces
     only dirty retained DOM rows.
   - The served browser target encodes a binary plan, the browser client applies
     it to its mirror buffer, then uses the same retained DOM presenter.
8. The frame loop commits the next buffer as the new visible buffer only after
   presentation consumes it.
9. Semantic presentation runs on the semantic path. Browser hosts can defer it
   outside the visual frame budget, coalesce several frames, and still force a
   flush before dispatching a semantic action.

Idle is a first-class case. If the buffer pool is warm, no element has scheduled
build work, and no render object recorded visual change, hosts can skip
build/layout/paint/present entirely.

## The target seam

The public seam is split across two libraries:

- `package:fleury/fleury_core.dart` exports the platform-neutral framework:
  widgets, elements, render objects, cell model, semantics, focus, animation,
  and related primitives.
- `package:fleury/fleury_host.dart` re-exports the core plus host-facing runtime
  contracts: `TuiRuntime`, `TuiFrameLoop`, `FrameScheduler`,
  `FramePresentationPlanner`, `RenderDamageTracker`, semantic ownership, and
  shared scroll detection.

Both are `dart:io`-free. Terminal setup, POSIX/Windows drivers, native process
work, external editors, filesystem access, and `runApp` live above that seam in
the native umbrella. Browser hosts import the host SPI instead of the native
umbrella so the same app code can compile with dart2js.

The seam is not only about imports. A host must provide the platform facts the
core cannot know:

- viewport size and resize events
- cell metrics in the browser
- input source and focus handoff
- clipboard implementation
- terminal capabilities or browser surface capabilities
- frame scheduling policy
- visual surface and semantic presenter

This is why page layout can affect an embedded Fleury widget. The widget tree
owns UI behavior, but the browser host still depends on the containing element
having real size, correct cell metrics, and unobstructed input/focus routing.

## Terminal target

The terminal host owns a native `TerminalDriver`, input parsing, raw mode,
alternate screen setup, terminal capability detection, and ANSI output. It uses
the shared frame loop to get previous/next buffers, then diffs them through
`AnsiRenderer`.

When a frame is a full repaint, the terminal path clears the screen and homes
the cursor before diffing. Otherwise it passes safe damage bounds to the
renderer. If layout damage made bounds unsafe, the renderer receives no bounds
and compares the full buffers.

Scroll is handled as an optimization over buffers, not as a special list API.
Shared scroll-up detection looks for a row shift that reduces residual dirty
cells. The ANSI renderer can emit a terminal scroll; the DOM presenter can move
retained row elements. Keeping that detection shared prevents the targets from
learning different ideas of what a scroll frame is.

## Embedded browser target

`mountApp` runs the app itself in the browser. The DOM host creates a
`TuiRuntime`, measures cell geometry, dispatches browser input as Fleury events,
builds frame presentation plans, and paints a retained DOM grid.

The retained visual grid is intentionally separate from semantics. The grid is
`aria-hidden` and optimized for visual cell fidelity. The semantic presenter owns
the accessible DOM projection beside it. That split lets the visual surface use
row/span replacement while the semantic surface exposes roles, labels, values,
states, bounds, and actions.

Browser semantics are deferred from the visual frame by default. The host keeps
the last presented buffer and dirty coverage rows so it can patch text fallback
and semantic DOM state without lengthening the critical paint path. If an
assistive technology or agent activates a semantic node, the host flushes
pending semantics first so the peer's view is current — the shared
FrameSemanticsPipeline enforces this on the browser and serve paths alike —
then dispatch resolves against a fresh tree built from the live root (never
stale). Both paths return the invocation status to the peer.

## Served browser target

`fleury serve` keeps the app running as a native Dart process. The browser is a
thin client. The native side renders frames and sends structured protocol
frames; the browser side keeps a mirror `CellBuffer`, applies remote plans, and
presents the same retained DOM grid as the embedded host.

The protocol carries more than pixels:

- `PLAN` frames encode changed cells, style tables, scroll hints, inline image
  placements, and full-repaint state.
- `SEMANTICS` frames carry full semantic snapshots or patches.
- `INPUT_EVENT` frames carry structured browser input back to the app.
- `SEMANTIC_ACTION` frames let the browser's accessible DOM invoke actions on
  the live tree.

This is different from streaming xterm output into a page. The browser client
does not parse ANSI to infer UI state; it receives the frame plan and semantic
model Fleury already produced.

## Correctness machinery

Incremental systems are easy to make fast and wrong. Fleury uses explicit
oracles around the places drift would be subtle:

- **Renderer equivalence:** ANSI diff output must reproduce the same visible
  buffer as a full repaint.
- **Frame presentation tests:** bounded paint damage, conservative full diffs,
  row-diff fallback, and scroll residual rows are tested directly.
- **Transport parity:** a server-produced frame must survive the wire and
  reconstruct the same client mirror buffer, including scroll and overlay cases.
- **DOM parity:** the retained DOM rendered from a remote mirror must match the
  intended cell output.
- **Semantic divergence checks:** retained semantic leaf updates are asserted
  against full semantic tree rebuilds in debug mode.
- **Public boundary tests:** web-safe libraries stay behind the host SPI instead
  of accidentally importing native runtime code.

The important principle is that damage, retained DOM, and semantic deltas are
optimization paths. The tests keep them equivalent to the simpler full-buffer or
full-tree truth.

## Tradeoffs and pressure points

The architecture is optimized for app-grade, semantic, cross-target TUIs. It is
not a claim that Fleury has the smallest possible runtime for one-off CLIs, the
fastest possible large-grid browser renderer, or a free incremental path for
every tree mutation. These are the pressure points worth keeping visible.

### Conservative damage is a feature

Fleury intentionally treats layout damage as unsafe for bounded diffs. A layout
change can remove or move cells without painting every stale location. Falling
back to a wider diff for that frame is cheaper than debugging a stale character
that only appears after a resize or conditional child disappears.

That also means new render objects have to earn paint-only invalidation. If a
setter can move children, change size, or leave stale cells behind, it belongs on
the layout path until tests prove a tighter bound is safe.

### Full buffers remain the correctness boundary

`CellBuffer` remains the frame truth. Dirty rectangles, dirty rows, scroll hints,
and semantic patches are acceleration data around that truth, not replacements
for it. Fleury has already tested broader ideas such as public dirty-span buffer
handoff and style-aware same-row gap encoding; they were correct but neutral or
slower on the measured workloads.

The current conclusion is narrow: keep the full-buffer diff contract, continue
private renderer/output-path improvements where measurements point, and avoid
adding public damage metadata until a benchmark shows it unlocks real wins.

### Repaint boundaries are not magic

A repaint boundary avoids re-walking expensive paint code, but it still has to
copy cells into the next frame and the presenter may still inspect buffers. It
is a tool for stable, expensive paint subtrees, not a default wrapper for every
component.

### Semantics are retained, but not fully incremental

The semantic pipeline has retained owners and leaf-update paths, but it
escalates to full rebuilds for structural ambiguity and fallback-bearing cases.
That is intentional. Assistive technology and agents need correct meaning more
than they need the smallest possible semantic patch.

The pressure point is large semantic trees with frequent structural churn. If
that becomes a real workload, the fix is deeper retained semantic production and
clearer dirty-source attribution, not weakening the correctness oracle.

### DOM is the default backend, not a forever bet

The embedded and served browser paths currently present a retained DOM grid plus
a separate semantic DOM. That is the right default for compatibility, cell-sized
viewports, browser accessibility, and developer ergonomics. It is not a claim
that DOM will always beat canvas or WebGL on raw large-grid throughput.

The visual surface is intentionally behind `FrameSurface`: input, clipboard,
metrics, scheduling, remote protocol, and semantics live outside the DOM grid.
If a future canvas or WebGL renderer earns its keep, it should reuse those host
contracts instead of forcing a framework rewrite.

### Browser layout remains a host contract

Fleury can own the cell grid only after the host gives it reliable geometry.
The DOM host has to measure cell width/height, snap rows, observe resizes, sync
caret geometry, and keep the input target available. A bad containing layout can
starve the surface of size or intercept events even though the Fleury widget tree
is correct.

### Flutter instincts need translation

Fleury borrows Flutter's retained model, but terminal performance has different
failure modes. Moving text by scroll detection can beat rebuilding keyed rows.
Writing fewer ANSI bytes can matter more than minimizing object churn. A
cell-grid renderer has to respect grapheme widths and terminal capability
fallbacks in ways a pixel renderer does not.

### Data-heavy widgets need data architecture too

When a workload builds a huge search index or eagerly mounts a very large data
shape, the renderer is not automatically the bottleneck. The retained render
pipeline can make visible rows cheap, but filtering, indexing, and lazy data
source boundaries still belong to the widget or model layer. Treat those costs
as data-architecture pressure before proposing a render-tree rewrite.

### The runtime floor is accepted

Fleury is pure Dart so the same core can run natively and compile to JavaScript.
That keeps the target story simple and preserves the browser path, but it means
Dart's startup and memory floor are part of the product envelope. The
architecture focuses on making Fleury's own retained work proportional to the
change, not on winning every tiny native-memory or cold-start comparison.

## Where to read the code

| Area | Files |
|------|-------|
| Widget, element, state, reconciliation | `packages/fleury/lib/src/widgets/framework.dart` |
| Render objects and invalidation | `packages/fleury/lib/src/rendering/render_object.dart` |
| Basic render objects | `packages/fleury/lib/src/rendering/render_objects.dart` |
| Repaint-boundary cache | `packages/fleury/lib/src/rendering/render_repaint_boundary.dart` |
| Cell frame and damage tracking | `packages/fleury/lib/src/rendering/cell_buffer.dart` |
| Shared scroll detection | `packages/fleury/lib/src/rendering/scroll_detection.dart` |
| Runtime owner | `packages/fleury/lib/src/runtime/tui_runtime.dart` |
| Frame buffer lifecycle | `packages/fleury/lib/src/runtime/tui_frame_loop.dart` |
| Row-oriented presentation planning | `packages/fleury/lib/src/runtime/frame_presentation.dart` |
| Native terminal host | `packages/fleury/lib/src/runtime/run_app.dart` |
| Host SPI exports | `packages/fleury/lib/fleury_host.dart` |
| Semantic model and actions | `packages/fleury/lib/src/semantics/semantics.dart` |
| Retained semantic owner | `packages/fleury/lib/src/semantics/semantics_owner.dart` |
| Embedded web host | `packages/fleury_web/lib/src/run_tui_surface.dart` |
| Retained DOM grid | `packages/fleury_web/lib/src/dom_grid/dom_grid_surface.dart` |
| Served browser client | `packages/fleury_web/lib/src/remote_client/remote_surface_client.dart` |
| Remote protocol | `packages/fleury/lib/src/remote/remote_protocol.dart` |

For the neighboring public docs, read [Core and targets](core-and-targets.md)
for the package/import split, [Serving and embedding](serving-and-embedding.md)
for the two browser paths, [Built for agents](agents-and-semantics.md) for the
semantic graph, and [Performance](performance.md) for the benchmark contract.
