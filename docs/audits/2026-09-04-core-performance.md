# Core performance audit — 2026-09-04

Baseline: `origin/main` at `8718fd332ddd47e46ac2fa4573385dc39ea22b7d`.
Candidate: `codex/core-performance-audit`. This pass starts from main and
does not include the earlier widget-focused performance branch.

The shared frame pipeline is healthy in the workloads measured here. The
best demonstrated improvement is in **frame construction**: background fills
were expressed as thousands of independent glyph writes. A bulk operation in
`CellBuffer` reduces that work across ordinary applications. The evidence
does not justify replacing the retained tree, introducing a native renderer,
or moving frame encoding to another isolate.

## Architecture assessment

| Layer | Current behavior and evidence | Decision |
| --- | --- | --- |
| Scheduling | `FrameDriver` shares the frame program across hosts, coalesces requests, skips frames without visual/build work, and stops producing frames while a transport is backlogged. | Keep. A forced clean-tree render in a profiling tool must not be mistaken for production idle work. |
| Build/reconciliation | `BuildOwner` queues dirty elements, processes parents first, and retains compatible elements. Snapshot sorting and scratch allocations remain, but the profiles did not establish them as the dominant application cost. Exception recovery and GlobalKey ownership are deliberate constraints. | Keep the three-tree model and current lifecycle contracts. Measure a large reactive rebuild before changing the queue or reconciler. |
| Layout | Cached constraints/sizes work: forced clean frames perform zero layouts and skip the root. At 120×40, even the all-dirty sample layouts took only 3–28 µs on main. | Keep. Broadly weakening conservative invalidation would trade correctness for a small saving in these fixtures. |
| Paint/composition | Every rendered frame reconstructs its cell buffer. Boundaries avoid repainting their descendants but still replay cells and geometry. Main's forced clean-tree paint cost was 102–308 µs at 120×40; several sample trees have no boundaries. Glyph placement, wide-neighbor repair, width measurement, and style merging dominate the diagnostic profile. | Improve the buffer operations and repeated text/style work first. Bulk fill is implemented and measured below. |
| Diff/presentation | `TuiFrameLoop` reuses two buffers and derives the authoritative diff from actual cells. Boundary caching does not remove that scan. | Preserve the ground-truth diff. Dirty hints cannot replace it without proving every custom painter, wide-cell edit, scroll, and image transition. |
| Input/semantics | Focus dispatch follows the active ancestor chain. Structured hosts share deferred semantic flushing, retained-output and leaf-update paths. Input still conservatively invalidates semantics because custom contributors can expose untracked state. | Preserve freshness. A large semantic tree under sustained input is a separate scaling workload; these measurements do not justify removing the conservative fallback. |

Relevant implementation:
[frame driver](../../packages/fleury/lib/src/runtime/frame_driver.dart),
[build owner and reconciliation](../../packages/fleury/lib/src/widgets/framework.dart),
[render invalidation](../../packages/fleury/lib/src/rendering/render_object.dart),
[frame buffers and diff](../../packages/fleury/lib/src/runtime/tui_frame_loop.dart),
[semantic pipeline](../../packages/fleury/lib/src/runtime/frame_semantics_pipeline.dart).

## Implemented: bulk background fills

`CellBuffer.fillRect` fills a clipped rectangle with one immutable styled
space cell, shared across the region. It performs wide-pair repair at the
two horizontal edges of each row. The old sequence measured a space,
repaired neighbors, recorded damage, and constructed a `Cell` at every
position. The operation still writes O(area) cell references, but glyph
measurement is eliminated, Cell construction becomes O(1) per rectangle,
and wide-neighbor repair becomes O(rows).

The standard background painter now uses this operation. Child painting
and the subsequent background inheritance pass retain their existing
behavior. The cell representation, repaint-boundary model, and diff
authority are unchanged. The primitive also preserves image placements,
matching individual grapheme writes rather than `clear()`.

Correctness coverage compares the complete buffer and damage bounds with
the previous per-cell algorithm in 500 deterministic cases, including
clipped, outside, empty, one-column, wide-glyph, image-overlay, and
interaction-style cases. Explicit tests check wide pairs cut at both edges
and a zero-sized buffer. Existing background composition tests also pass.

## Measurements

Dart 3.12.2, macOS arm64, 10 logical CPUs. Both variants were compiled AOT
from the same worktree before timing. Two runs per variant, in
base/candidate/candidate/base order, at 80×24, 120×40, and 200×60. Each
sample app was warmed for 30 frames and measured for 200 frames per mode.
Our compilation and test processes were stopped during timings; the shared
host was not isolated from other work.

At 120×40, forced clean-tree paint time, expressed as the mean of the two
run medians:

| Sample app | Main | Bulk fill | Reduction |
| --- | ---: | ---: | ---: |
| Dashboard | 303.5 µs | 251.5 µs | 17% |
| Agent | 116.5 µs | 64.5 µs | 45% |
| Files | 133.0 µs | 81.0 µs | 39% |
| Editor | 101.5 µs | 49.5 µs | 51% |
| Finance | 307.5 µs | 255.5 µs | 17% |

Savings persist across viewport sizes and all-dirty frames. At 200×60,
forced clean-tree paint falls by 20–58%, depending on the app. All recorded
layout counts, repaint/cache counts, and replayed-cell counts match between
variants for every app, mode, size, and repetition.

These are **paint-phase timings**, with debug counters enabled. The probe
explicitly renders even when nothing is dirty; production idle skips that
work. Its phase timers exclude buffer clearing, cell diff, ANSI encoding,
transport, and terminal display. These percentages are not end-to-end
input-latency or energy savings.

The corresponding JIT CPU profiles support the mechanism: across the same
800-frame-per-mode workload, exclusive samples in `_placeGrapheme` fell
from 550 to 100 and `_evictWideNeighbors` from 409 to 101. Sampling is
diagnostic, not a gate. `_RenderFilledBox.paint` inclusive samples include
its descendants and must not be interpreted as fill-only time. Allocation
snapshots from that profiler are not normalized per-frame allocation
measurements, so no bytes-per-frame improvement is claimed from them.

The core counter, editor, and layout scenarios all passed in alternating
AOT runs. Small-sample counter p95 initially moved upward, so it was checked
with 50 warmups and 1,000 measured iterations: main p95 was 44/51 µs,
candidate 44/44 µs. There is no repeatable counter-latency regression or
claimed input-latency win. Editor cursor p95 was 67/82 µs on main and
65/65 µs on the candidate; the broader layout scenario remained noisy.

The [measurement receipt](evidence/2026-09-04-core-paint.json) records source
hashes, environment, core scenario metrics, and CPU profile details. The
[frame measurements](evidence/2026-09-04-core-paint-frames.csv) contain all
240 app/mode/size/variant/run records, including structural counters.

### Reproduction

Build separate binaries from main and the candidate; do not overwrite the
baseline binary. From `profiling/`:

```sh
dart compile exe bin/retained_tax_probe.dart -o /tmp/fleury-retained-VARIANT
/tmp/fleury-retained-VARIANT --cols 120 --rows 40 --frames 200
```

Repeat at 80×24 and 200×60 in the order above. From `packages/fleury/`:

```sh
dart compile exe benchmark/scenario_benchmarks.dart -o /tmp/fleury-core-VARIANT
/tmp/fleury-core-VARIANT --warmup=3 --iterations=40 --save=/tmp/core-VARIANT.json
/tmp/fleury-core-VARIANT --filter=SB.1 --warmup=50 --iterations=1000
```

For the diagnostic retained-frame CPU profile, use a temporary sibling copy
of `packages/fleury/tool/benchmark_profile.dart`, replacing its child script
with `$repoRoot/profiling/bin/retained_tax_probe.dart` and the initial
`--filter` runner argument with `--frames`, `800`. Invoke that copy with
`SB.1 --cpu-top=40 --save=<path>`, then remove it. `SB.1` is only the wrapper's
scenario-selection label in this adaptation; the actual target is the
five-app retained-frame probe.

## Next core opportunities, in order

1. **Reuse text measurements during paint.** `RenderText` retains projected
   text and wrapped lines, but paint measures each line and then each
   grapheme; `writeGrapheme` measures that grapheme again. Width operations
   remain prominent after bulk fill. Investigate a private, bounded paint
   representation that reuses the layout's measured glyphs. It must
   invalidate on text, constraints, resolver, and width policy changes,
   and preserve alignment, ellipsis, clipping, and selection. Retained
   memory and text-edit latency must be measured along with steady paint.
2. **Reduce repeated background style composition.** After child paint, the
   background painter scans its rectangle and merges styles for cells
   lacking an explicit background. `CellStyle.merge` and `restyleCell`
   remain visible in the candidate profile. First measure repeated style
   combinations; any scoped reuse or buffer operation must preserve nested
   backgrounds, wide pairs, overlays, and boundary replay.
3. **Coalesce ancestor invalidation if large reactive trees justify it.**
   `_markNeedsLayoutUp` walks to the root even if ancestors are already
   dirty, and paint invalidation separately reaches enclosing boundaries.
   This can amplify K leaf changes across depth D. An early return cannot
   simply drop the walk: the root tracker must still receive frame-phase
   damage, including detached/reparented and in-frame mutations. Measure
   this on a real burst-update tree before adding per-node owner caches or
   invalidation epochs.
4. **Trim reconciliation scratch work after profiling broad rebuilds.**
   The stable-unkeyed path still allocates general-path scratch containers
   before it returns. Deferring those allocations is plausible, but the
   catch path must retain a coherent partially updated tree and preserve
   GlobalKey ownership. Current app profiles do not put this ahead of paint.

Each opportunity has a narrower test than an architecture rewrite. Broader
automatic repaint boundaries also remain conditional: they trade subtree
paint work for cell-cache memory and replay, and several lists/overlays
already install them. Current measurements do not justify changing that
policy globally.

## Validation

- Focused buffer/background tests: 61 passed.
- `dart tool/fleury_dev.dart check`: passed; 5,305 tests across 12 suites,
  one pre-existing LogBuffer offset skip. Includes package analysis, Chrome
  tests, documentation examples, dart2js smoke, and runtime integration.
- `dart tool/fleury_dev.dart benchmark gates`: all eight fast gates passed.
- `dart tool/fleury_dev.dart benchmark wire-gate`: SB.1, SB.6, and SB.9
  passed against the existing checked-in baselines. These historical
  baseline comparisons are regression checks, not before/after output-byte
  savings attributable to bulk fill.
- Embedded remote client rebuilt: compiled JavaScript unchanged; source
  fingerprint refreshed.
- Differential behavior, damage tracking, generated asset, source hashes,
  and final diff reviewed locally. No CI, PR, merge, or physical-terminal
  result is claimed for this branch.
