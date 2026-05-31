# Baseline benchmark results

Per RFC 0009 §4.3. Each row is one snapshot of the suite; add a new
row when shipping a perf-impacting change.

## Reading the table

- `RunTime`: microseconds per `run()` reported by `package:benchmark_harness`.
  The harness calls `run()` many times within a ~2-second window and
  averages.
- The grouping (render / paint / build / parser) maps to the
  sub-suite files under `benchmark/`.

## Hardware / SDK context

When you record a row, note machine + SDK in the header below.

---

## 2026-05-17 — initial baseline

- Dart SDK: 3.10.4 (stable)
- Platform: Linux x86_64 (cloud sandbox; perf is **relative** within
  the row, not absolute)
- Commit at time of measurement: pre-optimization baseline; immediately
  after the three high-confidence wins in RFC 0009 §2 landed
  (StringBuffer batching, raw-coord writes, buffer pool)

### render

| benchmark | µs/run |
| --- | --- |
| `diff_no_change[80x24]` | 230.9 |
| `diff_single_cell[80x24]` | 242.2 |
| `diff_row_change[80x24]` | 257.4 |
| `diff_full_repaint[80x24]` | 687.9 |
| `diff_no_change[200x60]` | 1442.3 |

### paint

| benchmark | µs/run |
| --- | --- |
| `paint_single_text[80x24]` | 26.4 |
| `paint_dense_text[24 rows of text, 80x24]` | 605.4 |
| `paint_typical_chat[80x24]` | 122.6 |
| `paint_typical_chat[200x60]` | 222.5 |

### build

| benchmark | µs/run |
| --- | --- |
| `flushbuild_1_dirty` | 6.7 |
| `flushbuild_10_dirty` | 70.5 |
| `flushbuild_100_dirty` | 1017.5 |
| `reassemble_walk[200 elements]` | 3118.5 |
| `mount+unmount[100 counters]` | 1025.0 |

### parser

| benchmark | µs/run | derived throughput |
| --- | --- | --- |
| `parser_ascii_1KB` | 131.1 | ~7.8 MB/s |
| `parser_csi_1KB` | 155.6 | ~6.6 MB/s |
| `parser_utf8_1KB` | 293.6 | ~3.5 MB/s |
| `parser_mixed_1KB` | 135.4 | ~7.6 MB/s |

### Analysis

Where time actually goes, ranked by absolute cost:

1. **`diff_no_change[200x60]` at 1442 µs** — pure walk-and-compare for
   12000 cells = 120ns/cell. Mostly `Cell == Cell` cost. A larger
   buffer just walks more cells; cost is linear.

2. **`paint_dense_text` at 605 µs** — 24 `Text` widgets × ~60
   graphemes each = ~1440 `writeGrapheme` calls. Each call allocates
   one `Cell`. Per-cell cost: ~420ns including layout + writeGrapheme
   work. Allocation cost dominates.

3. **`flushbuild_100_dirty` at 1017 µs** — per-dirty cost grows
   from 6.7 µs (n=1) to 10.2 µs (n=100). The O(n²) find-min loop
   starts to show but is still proportional to the actual rebuild
   cost. Not a clean win target.

4. **Parser at ~130 µs/KB ASCII** — equates to ~7.8 MB/s. Even a
   500-key/sec stress test is ~5 KB/s, four orders of magnitude under
   capacity. Parser is not the bottleneck.

### First optimization attempted: H1 — REGRESSION, REVERTED

Hypothesis was that mutable `Cell` with in-place writes would
eliminate the ~1440 Cell allocations per frame in
`paint_dense_text`.

Implementation:
- Made `Cell` mutable (removed `@immutable`, removed `const`
  constructors, added `setEmpty()`/`setLeading()`/`setContinuation()`
  mutators).
- `CellBuffer` allocates N distinct Cells once at construction;
  `writeGrapheme` mutates fields in place.
- `clear()` calls `setEmpty()` on each cell instead of assigning a
  const empty marker.

Result on the same hardware/SDK:

| benchmark | baseline µs | post-H1 µs | delta |
| --- | ---: | ---: | --- |
| `paint_single_text[80x24]` | 26.4 | 45.4 | **+72%** |
| `paint_dense_text[80x24]` | 605.4 | 606.7 | -0% |
| `paint_typical_chat[80x24]` | 122.6 | 137.8 | +12% |
| `paint_typical_chat[200x60]` | 222.5 | 335.9 | **+51%** |
| `mount+unmount[100]` | 1025 | 1117 | +9% |

The bottleneck shifted, not improved. The original code's
`_cells[i] = const Cell.empty()` is a single reference assignment to
a canonicalized const singleton — extremely fast. The new code's
`_cells[i].setEmpty()` is a method call + three field writes —
slower per cell. For 1920-cell `clear()` per frame this is a real
regression (~+20 µs per frame on 80×24, ~+120 µs on 200×60).

The allocation savings on `writeGrapheme` are real but smaller than
the `clear()` regression in most benchmarks (only `paint_dense_text`
is mostly-paint and mostly-not-clear, where the two roughly cancel).

**Lesson learned.** Dart's young-gen GC handles short-lived
allocations very cheaply — single-digit nanoseconds per Cell. The
hypothesis underestimated this. Writing to a const-canonicalized
reference is faster than mutating fields on an existing object,
especially when the JIT doesn't fully devirtualize.

This is exactly the "gated on profiling, not vibes" discipline RFC
0009 §7 called for. The hypothesis sounded right; the data said no.

**RFC 0009 H1 status updated:** in-place mutation variant is not a
win in standard Dart. The packed-`int64`-per-cell variant (which
would eliminate the cell-object allocation entirely AND skip the
overhead of mutating fields through getters) is still open as a
future investigation.

### Second optimization attempted: H6 — WIN, LANDED

Hypothesis was that `BuildOwner.flushBuild`'s O(n²) find-min loop
would visibly improve when replaced with a one-shot sort.

Implementation:
- Snapshot dirty elements, sort by depth ascending, iterate.
- Outer `while` loop handles newly-marked-dirty elements from
  cascading rebuilds.

Result:

| benchmark | baseline µs | post-H6 µs | delta |
| --- | ---: | ---: | --- |
| `flushbuild_1_dirty` | 6.7 | 6.7 | 0% |
| `flushbuild_10_dirty` | 70.5 | 67.1 | -5% (noise) |
| `flushbuild_100_dirty` | 1017 | 595 | **-42%** |
| `reassemble_walk[200]` | 3118 | 3255 | +4% (noise) |
| `mount+unmount[100]` | 1025 | 1051 | +2% (noise) |

Big win exactly where predicted: when n is large, the find-min loop's
O(n²) cost was real and is gone. For typical `setState` with
n=1–5 there's no measurable difference, as expected.

**H6 landed.** RFC 0009 §5.6 decision criterion ("flushBuild >5% of
frame time during reassemble or dense state-changing animations") is
met for the dense-state case; reassemble itself is dominated by the
per-element rebuild work, not the dispatch loop.

---

## 2026-05-19 — post-widget-slice measurements

- Dart SDK: 3.10.4 (stable)
- Platform: Linux x86_64 (cloud sandbox; numbers are **relative**)
- Commits in scope:
  `f004e2d` ListView · `bd4257b` Text soft-wrap · `8068474` Container/Border ·
  `12a0475` external FocusNode + chat_demo · `2180174` FocusTraversalGroup

### widgets

| benchmark | µs/iter | notes |
| --- | ---: | --- |
| `text_wrap_short[80x24]` | 33 | baseline, no wrap needed |
| `text_wrap_off_240ch[80x24]` | 63 | softWrap=false baseline |
| `text_wrap_medium_240ch[80x24]` | **335** | one 240ch message wraps to ~3 lines |
| `text_wrap_long_40paragraphs[80x60]` | 10,446 | 40 paragraphs (~120 wrapped lines) |
| `listview_paint[100 items, 80x24]` | 138 | ~22 visible, steady-state paint |
| `listview_paint[1000 items, 80x24]` | 200 | only 1.5× slower than 100 items |
| `listview_arrow_down[1000, 80x24]` | **2,803** | full rebuild of all 1000 items per arrow |
| `listview_jumpToIndex[1000, 80x24]` | 2,594 | rebuild cost dominates over backward layout walk |
| `container_border_paint[80x24]` | 45 | single bordered pane |
| `container_border_grid[6 panes, 80x24]` | 210 | linear with pane count |
| `focus_bounds_baseline[20 widgets]` | 121 | Column of 20 plain Text |
| `focus_bounds_overhead[20 widgets]` | 165 | same Column, each Text wrapped in Focus |

### Findings

**Word wrap is the hottest path.** A single 240-char message takes
~335 µs to wrap + paint, ~5× slower than `softWrap: false`. The 40-
paragraph case hits 10 ms, which is well into "visible jank" territory
at 60 fps. The chat-MVP case (50 wrapped messages visible) extrapolates
to ~17 ms per frame just for wrap+paint of message text, right at the
16 ms 60 fps budget. The algorithm allocates a `StringBuffer` per line
plus per-token splits — likely targets for optimization. Filed under
"measure before optimizing"; this is now measured.

**ListView eager-build cost is real but bounded.** Steady-state paint
of a 1000-item list is only 200 µs because layout/paint visits only
visible items. The cost shows up on selection change (`listview_arrow_down`,
2.8 ms for 1000 items) — that's the eager `itemBuilder` invocation for
every index. Linear in `itemCount`. Fine at ≤200 items; lazy mounting
would erase the cost for larger lists.

**`_anchorThatEndsAt` does NOT dominate.** `jumpToIndex(999)` clocks at
2.6 ms, almost identical to `arrow_down` (2.8 ms). The cost is the
rebuild, not the backward layout walk — the walk terminates after
`viewport.rows` items regardless of `itemCount` for uniform-height
rows.

**`_RenderFocusBounds` is essentially free.** The 20-widget overhead
delta is 44 µs across 20 wrappers, or **~2.2 µs per Focus**. Earlier
concern about render-tree bloat from adding the bounds wrapper was
overblown.

**Container + BoxBorder is cheap.** ~45 µs for one bordered pane,
~210 µs for six side-by-side. Linear; no surprises.

### Actionable items

1. **Word-wrap optimization is worth a focused pass.** Suspected wins:
   skip the algorithm entirely on lines with no spaces past `maxWidth`
   (already done via the `_intrinsicWidth <= maxCols` early return for
   single-line cases, but a multi-line path could split paragraphs and
   only wrap those that actually need it); reuse a single
   `StringBuffer`; avoid `text.split(' ')` allocation by walking
   graphemes once. Targeting a 2–3× wrap speedup is realistic.

2. **Lazy `ListView` becomes the next real perf lever, not just an
   ergonomics improvement.** At 200 items the eager build cost is
   ~560 µs per arrow press, fine. At 2000+ items it's 5–6 ms.
   Lazy mounting eliminates ~95% of that for typical viewports.

3. **No action needed on focus bounds, ListView steady-state paint,
   or Border** — all in budget.

---

## 2026-05-19 — wrap optimization pass

- Dart SDK: 3.10.4 (stable)
- Same machine as 2026-05-19 widget-slice measurement above; numbers
  are **relative** to that baseline, run on the same hardware in
  sequence.
- Two changes:
  1. `RenderText` memoizes its layout result by `CellConstraints` on
     the wrap path; the single-line fast path bypasses the cache to
     avoid adding cache-check overhead to a path that was already
     cheap. Cache is invalidated on text / softWrap / widthResolver /
     profile changes (not style — paint-only).
  2. `DefaultWidthResolver.widthOfText` and `widthOfGrapheme` now
     have ASCII fast paths: pure-ASCII strings skip the
     `text.characters` iterator entirely and use `code unit
     count == cell width`; single printable-ASCII graphemes skip
     the `runes` iterator and range scans.

### Wrap-heavy benchmarks (vs widget-slice baseline)

| benchmark | before µs | after µs | delta |
| --- | ---: | ---: | --- |
| `text_wrap_short[80x24]` | 33 | 31 | -6% |
| `text_wrap_off_240ch[80x24]` | 63 | 59 | -6% |
| `text_wrap_medium_240ch[80x24]` | 335 | 129 | **-61%** |
| `text_wrap_long_40paragraphs[80x60]` | 10,446 | 1,848 | **-82%** |

### Sanity-check benchmarks (variance ≥ delta — no regression)

| benchmark | before µs | after µs | delta |
| --- | ---: | ---: | --- |
| `listview_paint[100]` | 138 | 134 | -3% |
| `listview_paint[1000]` | 200 | 203 | +1% |
| `listview_arrow_down[1000]` | 2,803 | 3,350 | +20% — sampling noise (this benchmark varied 2,800–3,400 across runs both before and after) |
| `listview_jumpToIndex[1000]` | 2,594 | 3,025 | +17% — same as above |
| `container_border_paint` | 45 | 44 | noise |
| `container_border_grid[6]` | 210 | 225 | +7%, noise |
| `focus_bounds_baseline[20]` | 121 | 106 | -12% (ASCII fast path on the 20 Text widgets) |
| `focus_bounds_overhead[20]` | 165 | 149 | -10% (same) |

### Outcome

Chat-MVP extrapolation (50 wrapped messages visible) drops from
~17 ms/frame to ~6.5 ms on first paint, and to ~2.5 ms on subsequent
paints when the cache hits (text and column width unchanged). Both
sit well under the 16 ms 60 fps budget.

Remaining quick wins not pursued (diminishing returns):

- `text.split(' ')` allocation in `_wrapParagraph` — would save
  another ~10–20% on wrap cost. Easy to revisit.
- Single shared `StringBuffer` reused across layouts — small wins
  reach.

Tests added: three cache-invalidation cases (text change, constraint
change, softWrap change) confirm the cache is correctly invalidated.

---

## 2026-05-19 — lazy ListView.builder

- Dart SDK: 3.10.4 (stable)
- Same machine; absolute numbers vary across runs (~10-20%), so the
  important comparison is the delta on the rebuild-heavy benchmarks.
- Change: `ListView.builder(itemCount, itemBuilder)` now mounts only
  visible items as Elements. Off-screen items don't exist in the
  element tree. Items mount when they scroll into view and unmount
  when they scroll out. Variable-height items work naturally — no
  `itemExtent` required, because layout pulls items from the builder
  in sequence and stops when the viewport fills.
- The eager `ListView(children: [...])` constructor preserves the
  previous behavior.

### Selection-change / scroll benchmarks (huge wins)

| benchmark | before µs | after µs | delta |
| --- | ---: | ---: | --- |
| `listview_arrow_down[1000]` | 3,350 | 435 | **-87%** (~8×) |
| `listview_jumpToIndex[1000]` | 3,025 | 249 | **-92%** (~12×) |

These benchmarks dominate by build cost — each arrow press used to
rebuild 1000 item subtrees. With lazy, only the visible ~5 items
exist as Elements, so only they get rebuilt.

### Steady-state benchmarks (lazy infra adds small overhead)

| benchmark | before µs | after µs | delta |
| --- | ---: | ---: | --- |
| `listview_paint[100]` | 134 | 196 | +46% — lazy bookkeeping is real |
| `listview_paint[1000]` | 203 | 214 | +5% (noise) |

For tiny static lists where eager was already cheap, the per-layout
bookkeeping (active-children map updates, mount-during-layout
checks) shows up. Acceptable tradeoff: the rebuild path is what
actually scales with list size and that's now O(visible) instead of
O(itemCount).

### Findings

- Lazy mounting is the right default for `.builder`. Migrated all
  test/benchmark/example call sites from the old single-constructor
  API to `.builder` and they got the win for free.
- Eager `children:` still useful for cases where the children are
  already constructed (e.g., pre-built list of widgets, very small
  bounded lists where eager is faster).
- Three new tests verify lazy correctness: itemBuilder only invoked
  for visible items; items unmount when scrolled out; selection-
  change updates active items in place without remounting (via
  `Widget.canUpdate` reconciliation, not full remount).

---

## 2026-05-21 — animation infrastructure (RFC 0010 phase 6)

- Dart SDK: 3.10.4 (stable)
- Same machine; FakeClock-driven so timing is deterministic.

### animation

| benchmark | µs/iter | notes |
| --- | ---: | --- |
| `10 spinners share 1 scheduler timer (structural)` | 3 | One FakeClock advance against 10 active tickers. Structural property: `scheduler.activeTickerCount == 10`, one underlying timer. |
| `Animation spring to() [snappy]` | 17 | One spring retarget advanced through a full settle (~10 ticks). Includes analytic spring math, notifyListeners, future resolution. |
| `Animation rebuild per animation tick` | 25 | One scheduler advance + clear + renderFrame of a Text whose content depends on `animation.value` (implicit reactivity). End-to-end build + layout + paint cost per animation frame. |

### Findings

- **Scheduler coalescing works as designed.** 10 concurrent
  spinners produce one underlying timer; the per-tick cost
  scales linearly with active ticker count, not with timer
  count.
- **Animation hot path is sub-20 µs.** The analytic spring +
  notify isn't a bottleneck. An app with 100 concurrent
  Animations ticking at 30 Hz would spend ~50 ms/sec on
  animation machinery — well within budget.
- **Animation rebuild at ~25 µs** includes the full
  build/layout/paint cycle for a one-Text subtree. Scales
  linearly with the subtree's normal render cost.

Cross-terminal manual smoke (RFC §21.2 phase 6 exit criterion):
left to the user — automation can't reach iTerm2 / WezTerm /
real SSH. Recommended verification:

  1. `dart run example/animation_showcase.dart` shows all five
     animated widgets working concurrently.
  2. `dart run example/chat_demo.dart` — confirm the spinner in
     the message-pane header animates without flicker; confirm
     no spinner residue after a modal opens/closes mid-animation.
  3. Both, run over an SSH session with ≥50 ms latency
     (`mosh` or `tc qdisc add … delay 100ms`) — confirm no
     stale-frame backlog (animations stay smooth and don't
     "catch up" by jumping).

---

## 2026-05-27 — RepaintBoundary added

- Dart SDK: 3.10.4 (stable)
- Platform: Linux x86_64 (cloud sandbox; perf is **relative**, not absolute)
- Change: `RenderObject` gains a paint dirty bit + `markNeedsPaint`;
  `RenderRepaintBoundary` caches its subtree's `CellBuffer` and blits it
  on subsequent frames instead of re-walking paint. Opt-in via the new
  `RepaintBoundary` widget.

### paint (A/B against the prior row)

| benchmark | µs/run | Δ |
| --- | --- | --- |
| `paint_dense_text[24 rows, 80x24]` | 692.9 | ≈ baseline (no boundary) |
| `paint_dense_text+RepaintBoundary[80x24]` | **111.6** | **~6.2× faster** vs un-wrapped |
| `paint_typical_chat[80x24]` | 140.3 | (no boundary) |
| `paint_typical_chat[200x60]` | 241.2 | (no boundary) |
| `paint_typical_chat+RepaintBoundary[200x60]` | **615.0** | **slower** on sparse content |

The boundary is a clear win on dense subtrees: the blit replaces a full
paint walk. On sparse content in a *large* buffer (a small UI inside a
200×60 frame) the blit copies more cells than the original paint touches,
so it regresses — the boundary is **opt-in for a reason**, same as
Flutter. Practical recommendation: wrap subtrees that paint a lot and
change rarely (sidebars, headers, panels); don't wrap sparse content that
otherwise barely paints. Bbox-tight blits could close the sparse gap and
are a natural follow-up.

---

## 2026-05-27 — RepaintBoundary blit tightened to content bbox

- Same hardware/SDK as above.
- Change: `RenderRepaintBoundary` now scans its cache once after re-paint for
  the bounding box of non-empty cells, and the post-paint blit copies only
  that rectangle. Dense subtrees see a full-size bbox (no regression); sparse
  subtrees in a large frame now copy only their content.

### paint (A/B vs prior row)

| benchmark | µs/run | Δ |
| --- | --- | --- |
| `paint_dense_text[24 rows, 80x24]` | 606.9 | (no boundary) |
| `paint_dense_text+RepaintBoundary[80x24]` | **95.9** | **~6.3× faster** |
| `paint_typical_chat[200x60]` | 286.5 | (no boundary) |
| `paint_typical_chat+RepaintBoundary[200x60]` | **169.8** | **~1.7× faster** (was 2.5× *slower* before bbox) |

The previous full-buffer blit cost the boundary its win on sparse-content-in-a-
big-frame; tightening the blit to the actual content closes that regression
and pushes the boundary into a net positive on both shapes. Boundaries are
now safe-to-use on any subtree that paints non-trivially and changes rarely.
