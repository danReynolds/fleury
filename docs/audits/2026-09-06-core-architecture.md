# Core architecture performance follow-through

This pass targets shared framework work in ordinary app lifecycle and state
updates. It changes no document viewer, text-layout algorithm or specialized
widget. The final baseline is main `522ab372`, including the separately merged
derived-geometry architecture. Production changes were reviewed individually
before moving to the next candidate, then rebased and requalified together.

## Retained changes

1. **Batch render-child attachments during a parent rebuild** (`89be9140`).
   Mounting or replacing children used to rebuild the growing render-child
   list for each attachment, followed by a complete order synchronization.
   The parent now installs that list once at the end of its own reconciliation.
   Descendant-only replacements still attach immediately and schedule the
   parent order correction. Removal remains eager for GlobalKey reparenting.
   A `finally` restores the flag, including a failed reconciliation whose
   coherent partial tree is installed by the existing recovery path.
2. **Skip discarded positional-ID work** (`403e0faf`). When semantic dirt
   already requires a full tree walk, implicit-ID updates need no old/new
   positional comparison. The existing explicit-ID validation path remains.
   This also benefits terminal hosts that have no semantic presenter. Taking
   the full snapshot clears the condition; subsequent retained-leaf updates
   use the existing freshness checks again.
3. **Coordinate the full-flush decision with the dirty tracker** (`939ffe52`).
   Input already makes the shared semantic pipeline take a full snapshot.
   It now tells the dirty tracker immediately, preventing intervening updates
   from collecting leaf identities and building replacements the flush would
   discard. The conservative full walk, coverage, owner diff, action freshness
   and wire encoder remain unchanged.

The first change passed 93 targeted checks across its initial/follow-up runs,
including deterministic linear installation and failed-parent recovery tests.
The second passed 134 semantic/pipeline tests, and the third passed 135.
Each production change passed source analysis and all eight fast gates before
being retained. After the geometry rebase, 158 reconciliation, reparenting,
derived-geometry, semantic and pipeline checks passed, as did the profiling
host's two tests. Final contributor, wire and commit-specific CI results are
recorded in the associated PR.

## Final comparisons against current main

Values are medians of three fresh-process AOT medians, in microseconds.

| Workload | Main | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| Dashboard mount + first frame | 456 | 394 | 14% |
| Agent mount + first frame | 177 | 140 | 21% |
| Files mount + first frame | 368 | 315 | 14% |
| Editor mount + first frame | 154 | 137 | 11% |
| Finance mount + first frame | 548 | 459 | 16% |
| Terminal: update 16 unkeyed labels | 161 | 39 | 76% |
| Terminal: update 64 unkeyed labels | 772 | 117 | 85% |
| Terminal: replace 64 unkeyed subtrees | 1,465 | 586 | 60% |
| Structured: update 16 unkeyed labels | 684 | 330 | 52% |
| Structured: update 64 unkeyed labels | 2,773 | 1,011 | 64% |
| Structured: update 64 keyed labels | 1,452 | 871 | 40% |
| Structured: replace 64 unkeyed subtrees | 2,576 | 1,746 | 32% |

The 256-row scaling control improves from 17.156 to 3.141 ms for a structured
all-label update, and from 21.392 to 7.147 ms for terminal subtree replacement.
Those are scaling fixtures with many offscreen rows, not a general app speedup.
Single-label and keyed-reorder controls are preserved in the CSV; the largest
median increase is 1.2% (structured single-label update, 256 keyed rows).
All 48 control-tree cases have identical final rendered-text fingerprints
across revisions and repeats, and every measured update changes visible output.
The five sample mounts do not record output fingerprints; their lifecycle,
geometry and rendering contracts are covered by the regression suites.

## Measurement scope

The new `core_lifecycle_probe.dart` uses real `setState`, widget reconciliation,
layout, painting, exact cell diff and commit. Its control tree contains short
status labels under ordinary `Column`, component and optional `Padding`
wrappers: 16, 64 or 256 rows, keyed/unkeyed, with one-label changes, all-label
changes, reversal and component render-root replacement. It exercises shared
framework mechanisms; no large-text/document fixture is present.

At 120x40, each process measures 160 iterations after 15 mount warmups or
30 update warmups. The baseline and candidate alternate order across three
pairs. The final runs use native execution outside the filesystem sandbox;
no own compilation or tests run concurrently. The macOS arm64 host is shared,
not an isolated performance lab. The manifest pins Dart 3.12.2, source/harness
hashes, binaries and raw CSV hashes.

Terminal mode has no semantic consumer. Structured mode additionally builds
presentation plans and runs `FrameSemanticsPipeline` with coverage, owner diff
and the real `SemanticsWireEncoder.encodeTree` path. A manual profiling
scheduler flushes once after each committed frame. It measures that synchronous
work, not event-loop delay, input dispatch, transport, DOM or terminal display.
Mount timings include the profiling host's setup and first render; they are
not process startup or a time-to-fully-settled-screen measurement.

Three exploratory trial CSVs preserve the per-change comparisons made before
the geometry merge, on `cc3569d3` and under filesystem sandboxing. Their absolute
timings are superseded by the final native/latest-main comparison. In
particular, sandboxed finance mounts had substantial wall-time overhead that
was absent in native runs; no framework optimization claim is based on it.

## Architecture assessment and remaining boundary

The broader core was not exhausted: two independent kinds of duplicated work
were still visible once benchmarks included widget rebuilding and the complete
semantic flush. The earlier direct-render-object frame probes missed those
paths. The new optional presentation hook keeps the shared host's input
transactions and buffer lifecycle intact while including semantic costs.

Scheduling already coalesces requests and skips idle frames. Inherited
notifications queue dependent rebuilds, and cached constraints avoid layout
when geometry is unchanged. The runtime gate still verifies frame counts,
coalescing and backlog behavior. These observations do not justify replacing
the scheduler, dirty queue or retained architecture.

For 64-label updates on this candidate, median build/layout/paint phases are
54/0/38 microseconds in terminal mode. In structured mode the semantic flush
is about 675 microseconds: tree construction around 250, coverage 48, owner
diff 21 and encoding 339. Phase medians need not add to the total median.
That points to semantic construction/delivery for a future active-app profile;
it does not justify weakening the full-refresh fallback for custom state.
Large component replacement still pays eager-removal bookkeeping. Further
changes there need to preserve immediate detachment and custom-container
contracts rather than introduce a speculative mutation API.

This pass adds one per-multi-child-element boolean and no global/persistent
cache. It claims no total-RAM reduction, allocation rate, general leak result
or end-to-end input latency. Large-document wrapping and editing are explicitly
outside this pass's priorities.

## Reproduction

Use identical final `core_lifecycle_probe.dart` and `sample_frame_host.dart`
source on both revisions. In each worktree's `profiling` directory:

```sh
dart pub get
dart compile exe bin/core_lifecycle_probe.dart -o /tmp/core-VARIANT
/tmp/core-VARIANT 160 terminal
/tmp/core-VARIANT 160 structured
```

Run one process at a time, alternate variant order, and keep compiler/test
processes stopped. `core_cpu_probe.dart` provides optional JIT attribution;
JIT sample percentages are diagnostic and do not replace the AOT comparison.
The evidence manifest and four CSVs share the
`evidence/2026-09-06-core-architecture` prefix.
