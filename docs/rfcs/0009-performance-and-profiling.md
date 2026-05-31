# RFC 0009: Performance and Profiling for fleury

**Status:** Living plan
**Date:** 2026-05-17
**Decision point for:** which optimizations to land before P1 close vs.
  defer until measured pressure justifies them.

This document captures what we know about fleury's render-loop
performance today, what we've already optimized, what we *think* the
remaining hotspots are, and the discipline we want to apply to
deciding when to act on them.

The framing is intentional: **performance work is gated on profiling,
not vibes.** Every proposed change below is a hypothesis with a stated
mechanism, an estimated cost to implement, and the decision criterion
that would justify spending that cost.

## 1. Current pipeline (steady state)

A single `setState` flows through:

1. `State.setState(fn)` runs `fn` synchronously and calls
   `Element.markNeedsBuild()`.
2. `markNeedsBuild` adds the element to `BuildOwner._dirtyElements`
   and (on transition empty → non-empty) fires `onScheduleBuild`.
3. `runTui` schedules a frame via `scheduleMicrotask`.
4. `BuildOwner.flushBuild` walks dirty elements **shallowest-first**
   (O(n²) find-min over the set), rebuilding each.
5. The runtime's `renderFrame`:
   a. (Re)allocates a `CellBuffer` pair if size changed.
   b. Clears the back buffer.
   c. `BuildOwner.renderFrame(root, back)` — runs layout top-down,
      then paint top-down. Each `Text.paint` writes graphemes via
      `CellBuffer._writeGraphemeAt`, allocating one `Cell` per
      grapheme.
   d. `AnsiRenderer.renderDiff(front, back, sink)` walks every cell
      in both buffers, skipping identical ones, accumulating cursor
      moves + SGR + grapheme bytes into a `StringBuffer`, then
      writing the buffer once to the sink.
   e. Front/back roles swap.

The diff path is the win the framework already has: even with a
naive paint phase, the bytes written to stdout are minimal (a
single character change typically emits ~8 bytes total).

## 2. Optimizations already implemented

These are the obvious-win changes we've already landed, in order:

| Change | Mechanism | Win |
| --- | --- | --- |
| **Cell-level diff render** | Walk both buffers; emit only cells that differ; coalesce SGR resets to non-empty transitions | Tiny per-frame byte output for typical app updates |
| **Synchronous `setState` → microtask frame** | Coalesce multiple `setState` calls within one frame via `BuildOwner.onScheduleBuild` only firing on empty → dirty transition | One frame per burst, not per `setState` |
| **`AnsiRenderer` batched writes** | Internal `StringBuffer`; one `sink.write` per frame instead of ~50 | Fewer `IOSink` queue operations; cleaner profile |
| **`CellBuffer._writeGraphemeAt(col, row, ...)`** | Internal raw-coord write avoids per-grapheme `CellOffset` allocation in `writeText` | Eliminates O(text length) heap allocations in dense paint loops |
| **Front/back buffer pool in `runTui`** | Allocate two buffers once per terminal size; alternate roles each frame | One `CellBuffer` + its `List<Cell>` allocation per size change, not per frame |
| **Style-reset elision for default-styled runs** | Don't emit `\x1B[0m` on `null → CellStyle.empty` transitions (only on `non-empty → empty`) | Plain-text frames have zero SGR bytes |

## 3. Performance posture (as of this writing)

For typical TUI surfaces (80×24 to 200×60 terminals, normal interaction
rates):

- **Per-frame byte output is minimal.** A character-toggle typically
  emits ~8 bytes; a full sidebar repaint after a conversation switch
  is hundreds to low-thousands of bytes.
- **Cell allocations during paint** are the dominant garbage source.
  For an 80×24 buffer painted densely, ~2k `Cell` allocations per
  frame. At 30fps that's 60k/sec — small absolute numbers, but the
  largest single allocation source in the render path.
- **Layout runs every frame** regardless of whether constraints
  changed. For trees on the order of 50–200 render objects this is a
  few hundred microseconds at most, but it grows linearly with tree
  size.
- **`flushBuild`'s shallowest-first scan** is O(n²) on the dirty set.
  Typical n is 1–5; reassembleApplication can push it to several
  hundred. Not currently a bottleneck.

We have not profiled this. The numbers above are estimates from
reading the code, not measurements.

## 4. Profiling support — to be added

Before acting on the hypotheses in §5, we need observable data.
Concrete plan:

### 4.1 Microbenchmarks

A `benchmark/` directory under `packages/fleury/` using
`package:benchmark_harness` covering:

- `paint_dense_text` — paint a screenful of text via `Text` widgets
  in a `Column`.
- `paint_typical_chat` — sidebar + scrolling message pane + composer.
- `diff_no_change` — two identical buffers (cost of the "nothing
  changed" path).
- `diff_single_cell_change` — measure the floor cost of an
  incremental update.
- `diff_full_repaint` — every cell differs.
- `flushbuild_n_dirty` — N = 1, 10, 100, 1000 elements all dirty.
- `reassemble_walk` — synthetic 200-element tree, measure
  `reassembleApplication` cost.
- `parser_throughput` — feed bytes through `InputParser`; measure
  events/sec.

Goal: numbers in microseconds for each path, with allocation count
where the Dart VM service exposes it. The benchmark file outputs
JSON so we can diff successive runs (catch regressions in CI).

### 4.2 Real-app profiling

Once the Dune CLI has a working chat MVP:

- `dart --pause-isolates-on-exit --enable-vm-service` + DevTools CPU
  profiler. Run the demo, exercise typical paths (scroll a long
  conversation, switch sidebars, mount a modal). Save the recorded
  profile artifacts under `benchmark/recordings/`.
- DevTools memory profiler with allocation tracking. Identify the
  top class-allocation sites per frame.
- Long-haul soak: run for 30 minutes of automated keystrokes. Watch
  for retained-set growth (memory leaks).

### 4.3 Reporting

Each benchmark emits a row to a `benchmark/results.csv` (or similar)
checked in periodically. Commits that change the render path should
include a before/after row. This is a soft discipline at first; if
churn is high, automate via a CI gate later.

## 5. Hypotheses for further optimization

Listed in order of: highest-confidence first, then largest expected
impact, then smallest implementation cost. Each is **gated on
profiling** unless explicitly approved otherwise.

### 5.1 H1 — Cell representation as packed `int64` or parallel typed arrays

**Status:** mutable-cell variant **attempted and reverted**; packed-int
variant still open. See `benchmark/baseline_results.md` for the
post-mortem data.

**Hypothesis:** ~90% of `Cell` allocations in the paint phase can be
eliminated by representing cells as primitive values instead of
heap-allocated immutable objects.

**Mechanism.** Today `Cell` is a class with `String? grapheme`,
`CellRole role`, `CellStyle style`. Each `_writeGraphemeAt` call
allocates one (or two for wide graphemes). Two redesigns to consider:

- **Packed `int64`** for cells with no truecolor: 21 bits codepoint
  + 2 bits role + 3 bits attr (bold/italic/underline) + 4 bits
  fg index (16-color) + 4 bits bg index + spare. Wide graphemes
  (multi-code-point clusters) handled by reserving a small
  "grapheme table" for the rare non-ASCII clusters and storing an
  index in the packed cell. Most TUI content is ASCII; this is the
  fast path.
- **Parallel typed arrays.** `Uint32List` for codepoints,
  `Uint32List` for fg colors, `Uint32List` for bg colors,
  `Uint8List` for role+attrs. Style truecolor RGB packs into a
  Uint32. Cell becomes a "view" or just `(col, row)` operations on
  the arrays. Higher rewrite cost but supports full truecolor cells.

**Cost.** Medium-to-large refactor. Touches `Cell`, `CellBuffer`,
`AnsiRenderer`, every `RenderObject.paint`, and tests that compare
`Cell` values.

**Risk.**
- Style range is awkward with truecolor + attrs in 64 bits; the
  parallel-arrays variant probably wins on flexibility.
- Cell equality semantics change subtly (value-typed comparison
  instead of class-instance equality). All tests that build
  expected cells need updating.

**Decision criterion.** Profile shows `Cell` allocation alone
accounts for >10% of paint-phase time, OR allocation tracking shows
`Cell` is the top source of young-gen pressure under continuous
animation.

**Post-mortem (mutable-cell variant, 2026-05-17).** Tried making
`Cell` mutable so `CellBuffer.writeGrapheme` could update fields in
place instead of allocating a new instance. Result was a 51%
regression on `paint_typical_chat[200x60]` and a 72% regression on
`paint_single_text`. The win was less than expected on
`paint_dense_text` (no measurable change) because:

1. Dart's young-gen GC handles short-lived `Cell` allocations very
   cheaply — single-digit nanoseconds per instance. The hypothesis
   overestimated allocation cost.
2. `CellBuffer.clear()` previously did `_cells[i] = const Cell.empty()`
   — a single reference assignment to a canonicalized singleton, on
   the order of 1ns per cell. The mutable-cell variant has to do
   `_cells[i].setEmpty()` — a method call plus three field writes
   per cell, ~10–25ns. For 1920 cells per frame on 80×24 this is
   ~+20µs per frame; for 12000 cells per frame on 200×60 it's
   ~+120µs. Most of the clear cost was hidden behind the const
   reference, and the mutable variant brought it into view.
3. The JIT doesn't fully devirtualize `setEmpty()` even on a final
   class. Even if it did, the three field writes still cost more
   than one reference assignment to a const.

The data says: the *packed-int64-per-cell* variant is the only way
H1 could win in Dart. That eliminates both the object allocation
*and* the field-mutation cost. It's a larger refactor and remains
open as a future hypothesis.

### 5.2 H2 — Layout caching: skip `performLayout` for clean subtrees with stable constraints

**Hypothesis:** in steady-state, most of the render tree's layout
result is unchanged from the previous frame. Caching `(constraints,
size)` per render object and skipping re-layout when constraints are
unchanged AND the subtree is clean saves 50%+ of layout cost on the
typical chat surface (the sidebar and footer don't change every time
a message arrives).

**Mechanism.** Add `_lastLayoutConstraints` and `_layoutDirty` to
`RenderObject`. `RenderObject.layout(constraints)` short-circuits
when `constraints == _lastLayoutConstraints` and
`!_layoutDirty`. `_layoutDirty` is set when the render object's
configuration changes (via the widget's `updateRenderObject`) or
when a descendant marks itself dirty (need to propagate up the
parent chain).

**Cost.** Small infrastructure change in `RenderObject` base; care
required around the propagation (need a `markNeedsLayout` analog).

**Risk.**
- Render objects with intrinsic-size-dependent layout (notably
  `RenderText`) need to invalidate when the underlying string or
  resolver changes — easy to forget.
- The propagate-up-on-child-dirty logic is the trap. Flutter handles
  this with care; we'd be reinventing.

**Decision criterion.** Profile shows layout > 20% of frame time in
a non-trivial app surface (sidebar + pane + composer with a
~100-element tree).

### 5.3 H3 — Damage rectangles (per-widget dirty regions)

**Hypothesis:** even with the buffer-level diff, we're re-running
paint for the entire render tree every frame. For a 200×60 terminal
with a 10×3 modal in the corner that's the only thing changing, we
waste paint cycles on 11,970 cells we'll then memcmp away in the
diff.

**Mechanism.** Each `RenderObject` tracks its previous paint rect.
When dirty, it reports a damage rectangle. The framework unions all
damage rects and re-paints only those regions; the rest of the
buffer is copied from the previous frame. The diff renderer then
only walks the damaged regions.

**Cost.** Hard. Requires per-render-object damage tracking,
union-find for overlapping rects, and a copy-from-previous-buffer
pass. Architectural.

**Risk.**
- Easy to get incorrect on overlaps, especially with `Stack`.
- Wide-grapheme eviction across damage boundaries is subtle.
- May not pay off if the existing diff is already fast enough.

**Decision criterion.** Profile shows paint > 30% of frame time
under typical animation, AND we measure that the damaged-area
fraction is consistently small (< 25% of cells).

### 5.4 H4 — Coalesced cursor moves (relative motion)

**Hypothesis:** the renderer always emits absolute cursor positions
(`\x1B[<row>;<col>H`, 7+ bytes). For dirty cells close to the
current cursor, relative motion (`\x1B[<n>C` etc.) is shorter and
the network/serial gain matters on slow links (SSH over a saturated
connection, serial-attached devices).

**Mechanism.** When the next dirty cell is within ~10 columns of
the current cursor position on the same row, emit `\x1B[<n>C` /
`\x1B[<n>D` instead of an absolute `H`. Trivial selection rule;
adopt only when measurable benefit.

**Cost.** Small. ~50 lines in `AnsiRenderer`.

**Risk.**
- Terminal implementations of relative motion sometimes have
  off-by-one quirks. Worth testing across xterm, iTerm, Terminal.app,
  Windows Terminal, kitty, wezterm.
- The byte savings are typically 4–5 bytes per cursor move, small
  in absolute terms.

**Decision criterion.** Real complaint about render lag over SSH
where bandwidth, not framework cost, is the bottleneck.

### 5.5 H5 — Delta SGR encoding

**Hypothesis:** when style transitions only toggle one attribute
(e.g., bold on → bold off), emitting a full reset + re-apply is
wasteful. A delta encoding (`\x1B[22m` to clear bold only) saves
bytes.

**Mechanism.** Compare the previous emitted style and the new one;
emit only the SGR codes for fields that changed.

**Cost.** Small to medium; the SGR delta logic is the bulk.

**Risk.**
- SGR delta codes are well-defined but edge cases exist (e.g.,
  `\x1B[39m` to reset fg vs. `\x1B[0m`).
- Cost vs. benefit: a full reset is 4 bytes (`\x1B[0m`); the delta
  might be 4 bytes too (`\x1B[22m`). Marginal.

**Decision criterion.** Profile shows SGR sequences are >15% of
total output bytes during typical UI updates.

### 5.6 H6 — `flushBuild` sorts dirty elements once instead of repeated find-min

**Status:** **landed** 2026-05-17. `flushbuild_100_dirty`: 1017 → 595 µs
(-42%). Typical n=1–5 cases unchanged. See `benchmark/baseline_results.md`.

**Hypothesis:** `BuildOwner.flushBuild`'s current O(n²) find-min
loop is fine for small n but degrades on `reassembleApplication`
(n can be hundreds or thousands).

**Mechanism.** Take a snapshot of the dirty set, sort by depth, then
iterate. Repeat the outer loop if new dirty elements were added
during iteration.

**Cost.** Tiny.

**Risk.**
- Behavior differs from the existing algorithm when a rebuild marks
  an ancestor dirty. Current algorithm picks up the now-shallowest
  ancestor on the next iteration of the inner loop; sort-once
  defers it to a second outer pass, which may rebuild the ancestor
  AND the original descendant (the descendant gets rebuilt again
  via reconciliation when the ancestor's rebuild cascades).
- The edge case is rare; correctness is maintained.

**Decision criterion.** Profile shows `flushBuild` accounts for >5%
of frame time during reassemble OR during dense state-changing
animations.

### 5.7 H7 — Static-above-dynamic content (Ink's trick)

**Hypothesis:** chat scrollback (or any append-only content) doesn't
benefit from re-rendering. Treating it as "static" output above the
dynamic frame area lets it bypass the cell buffer entirely.

**Mechanism.** A `StaticContent` widget renders into the terminal
scrollback (above the current frame) and only emits new content
when its content changes. The framework's cell buffer covers only
the "dynamic" frame area below it.

**Cost.** Architectural change. Requires a clear contract about
which terminal modes work with this (alt-screen breaks it; the
scrollback above gets cleared on alt-screen enter).

**Risk.**
- Doesn't work with `TerminalMode.interactive` (alt screen). Would
  need an inline mode for this feature.
- Scroll behavior across terminals is variable.

**Decision criterion.** A real chat consumer has demonstrable lag
from re-painting the scrollback, AND ships in `TerminalMode.inline`
or a hybrid mode.

### 5.8 H8 — Threaded rendering

**Hypothesis:** moving the layout + paint + diff work to a separate
isolate frees the main isolate for input handling and app logic.

**Mechanism.** Spawn a worker isolate. Main isolate sends widget
tree snapshots (or just dirty subtree info); worker sends back ANSI
bytes. Main isolate writes to stdout.

**Cost.** Hard. Isolate communication overhead vs. saved work is
unclear. State-management gets harder (no shared memory).

**Risk.**
- Sync between input dispatch and render is tricky.
- The Dart isolate-message serialization cost may exceed the render
  cost we're trying to offload.

**Decision criterion.** Profile shows the render pipeline blocks
input dispatch for >16ms regularly, AND we've tried H1–H4 first.

### 5.9 H9 — `Container` does no rendering itself

**Hypothesis:** `Container` is implemented as a `StatelessWidget`
that builds `SizedBox`/`Padding`. This adds extra Elements and
RenderObjects to the tree for every Container. A direct
`RenderContainer` that handles size + padding + (eventually)
background in one render object would reduce tree depth.

**Mechanism.** A single `RenderContainer` does both sizing and
padding-style insetting. Container becomes a leaf-ish render
object.

**Cost.** Small refactor. The current Container is a thin
StatelessWidget so consumers don't notice.

**Risk.** Negligible.

**Decision criterion.** Profile shows tree depth or per-tree-node
overhead is significant in container-heavy UIs.

### 5.10 H10 — Use `Uint32List` directly in `CellBuffer` (no boxed ints)

**Hypothesis:** even with H1 (packed cells), if the storage is a
`List<int>`, each element is a boxed `int` object. Switching to
`Uint32List` (or `Int64List`) gives unboxed storage and faster
access.

**Mechanism.** Replace `List<Cell>` with `Uint32List`/`Uint64List`
backed by typed views. Pairs naturally with H1.

**Cost.** Bundled with H1.

**Risk.** Cell values must fit in the chosen integer width.

**Decision criterion.** Falls out of H1's profile.

## 6. Non-goals for this slice

Explicit list of things we are **not** treating as performance work,
to avoid scope creep:

- **Animation framework.** Tickers/AnimationController/Tween land
  with the visual-polish slice; their perf properties are a separate
  discussion.
- **Mouse hit-testing performance.** Mouse lives in RFC 0010
  (currently unwritten).
- **Compile-time optimizations.** AOT compilation is what `dart
  compile exe` does; we don't shape the framework around AOT
  specifics.
- **Native code / FFI.** Not for fleury. The whole point of being
  pure Dart is the single-binary distribution story; introducing
  native deps undoes that.

## 7. Discipline

Before merging any change from §5:

1. The benchmark (§4.1) that would show the win exists and is
   committed.
2. Before/after numbers are in the commit message.
3. The decision criterion stated in the hypothesis is met.

This is a soft rule. We're not trying to bureaucratize perf work —
just to keep us honest about whether the optimization is actually
needed at the time we ship it.

## 8. Review cadence

Revisit this doc once Dune chat MVP ships and we have real
profile data. The hypotheses here may compress, expand, or get
struck through entirely based on what shows up.

## 9. References

1. Ratatui rendering — buffer + diff: https://ratatui.rs/concepts/rendering/under-the-hood/
2. Notcurses — damage rectangles, per-plane composition: https://nick-black.com/dankwiki/index.php?title=Notcurses
3. Bubble Tea — line-level diff rendering: https://github.com/charmbracelet/bubbletea
4. Ink — Yoga layout, static-above-dynamic content: https://github.com/vadimdemedes/ink
5. Flutter `RenderObject.layout` caching: https://api.flutter.dev/flutter/rendering/RenderObject/layout.html
6. Dart `Uint32List` and unboxed integer storage: https://api.dart.dev/stable/dart-typed_data/Uint32List-class.html
