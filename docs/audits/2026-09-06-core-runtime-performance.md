# Core runtime performance follow-up

This pass starts at main `e5217c0f` after PRs #217 and #218 were merged.
The user checkout remains untouched; changes were made in an isolated worktree.
The three production changes are `9a46aa69`, `1591a8c3`, and `b938c4f7`.
Each was reviewed and passed targeted tests, analysis and all eight fast gates
before the next change began.

## Selection of work

| Area | Evidence and decision |
| --- | --- |
| Plain-text ambient rebuild/resize | The corrected real-frame host exposes repeated sanitization of unchanged text. A 963-sample JIT resize profile attributes 77.3% inclusively to the text setter; substring creation, scanning, splitting and joining dominate. Retained the equality fast path. |
| Full semantic snapshot construction | The old unkeyed-root probe misses positional IDs under keyed runtime roots. The replacement covers settled sample apps and keyed scopes containing 50/200/1,000 text rows. Repeated sibling scans make the 1,000-row baseline cost roughly 29 ms. Retained a snapshot-scoped index. |
| Plain-text mount/edit | A separate 6,900-sample JIT edit profile attributes 69% inclusively to layout, with string slicing the largest exclusive entry. The renderer also duplicates the existing multiline sanitizer, creating unnecessary line strings and a second canonical document. Reused the existing helper. |
| Shared sample-frame loop | Five apps, three viewport sizes and clean/leaf/full modes remain regression controls. Baseline ordinary 120×40 frames cost roughly 0.06–0.24 ms. This pass does not claim another broad visual-frame win. |
| Input routing and terminal presentation | Read-only inspection plus the existing runtime/input and terminal-wire gates; no new timing improvement claimed. Focus routing walks the active ancestor chain, and existing idle skipping/coalescing remain in place. |

JIT sample percentages identify work; all speed comparisons below use AOT.

## Retained changes and review

1. **Unchanged canonical text exits before sanitization.** Comparing against
   the already-sanitized logical value is safe because strings are immutable.
   Changed input still goes through sanitization and the existing post-sanitize
   comparison. No second source reference or cache is introduced. Passed 71
   text/sanitizer/policy/resize tests and analysis, then all eight fast gates.
2. **Wide sibling lists are indexed once per full semantic snapshot.** The
   temporary identity map is active only during synchronous collection and
   restored in `finally`, including nested snapshots and exceptions. Only
   `MultiChildRenderObjectElement` lists use it. Single-child wrappers and
   standalone/retained-leaf/action-dispatch ID reads keep their existing walk.
   IDs, positional-staleness rules and action tokens are unchanged. Passed 132
   semantics/pipeline tests and analysis, then all eight fast gates. New
   regressions cover linear sibling visits, nested snapshots, failed snapshots,
   physical position changes without replacing the element, and target lookup.
3. **Plain text uses `sanitizeMultiline`.** Removes the renderer's duplicate
   split/sanitize/join helper. The shared helper scans safe input without
   allocating line strings and returns the same immutable source string;
   unsafe input still uses the same per-line escape/control handling. Passed
   125 text/sanitizer/policy/resize/editing tests and analysis, then all gates.

The first semantic-index trial cached single-child positions as well. It made
ordinary sample semantic builds roughly 3–11% slower and was rejected. The
retained version avoids hashing those wrappers. The original semantic ID probe
now explains that its entirely unkeyed root is a control, not the wide
positional-ID workload.

## Final measurements

| Operation | Main | Candidate | Observation |
| --- | ---: | ---: | --- |
| Full semantic snapshot, 50 unkeyed rows | 167 µs | 102 µs | 39% less CPU |
| Full semantic snapshot, 200 unkeyed rows | 1.519 ms | 0.407 ms | 73% less CPU |
| Full semantic snapshot, 1,000 unkeyed rows | 31.685 ms | 2.135 ms | 93% less CPU |
| Full semantic snapshot, 1,000 keyed rows | 2.052 ms | 2.043 ms | Essentially unchanged control |
| Plain 10,000-line unwrapped open | 16.944 ms | 12.912 ms | 24% less CPU in focused comparison |
| Plain 10,000-line wrapped full copy | 0.811 ms | 0.842 ms | 3.8% higher in focused control; no copy improvement claimed |
| Plain 10,000-line unwrapped resize | 6.363 ms | 0.244 ms | Large win also present in the initial equality-only comparison: 3.542 → 0.283 ms |

The first six rows use five alternating focused comparisons; resize uses the
three-process full matrix. The broad final sweep ran during substantial other
build activity on the shared host (observed load average about 51), with some
unchanged controls moving sharply. Its raw values are preserved. Focused
follow-ups resolved the apparent dashboard-semantics and unwrapped-open
regressions, and reduced the full-copy difference from 47% to 3.8%. Therefore
the large structural improvements are the headline; modest changes in wrapped
layout/edit or ordinary frames should not be generalized from this sweep.
The 45 sample-frame controls range from -9.5% to +3.3%; focused sample semantic
builds range from -5.8% to +1.6%.

Post-GC memory measurements reproduce exactly in both fresh processes per
revision. Mounting the 1,000-line plain document adds **381,072 → 263,264 bytes**
to the process-wide two-byte-string class total. That is **117,808 bytes
(115 KiB) less retained string storage**, with exactly one fewer added string
instance, consistent with sharing the canonical source. Fleury-class shallow
storage is unchanged at 102,096 bytes while mounted. After unmount, string
totals return to their initial values, and neither those totals nor Fleury
class totals grow after 50 additional cycles. The emptied-widget fixture
initializes the same constant 176 bytes of Fleury objects on both revisions.

All document output, selection/copy and changed-frame fingerprints match
across the final matrix. The embedded client was regenerated with source
fingerprint `0f63c11c68bcdd92`. Changed profiling tools analyze cleanly; a
whole-profiling analysis reports four existing unnecessary-import infos in
`input_alloc_gate.dart`. Final contributor-check, terminal-wire, CI, review
and merge receipts are recorded in the associated performance PR.

## Measurement boundaries and reproduction

The evidence manifest pins source/harness revisions and SHA-256 hashes, AOT
binaries, SDK/OS, and raw CSVs. Both revisions use identical harness source.
CPU runs are serial, with three alternating fresh processes per workload and
revision. Reported comparisons are medians of per-process medians. Document
operations use 60 measured frames after 10 warmups, semantic builds use 300
after 30 warmups, and sample controls use 600 frames per mode.

Document operations include mutation, real frame construction/diff and commit;
opening includes mount and the first frame. Fixture generation, terminal
encoding/transport/display and process startup are excluded. Resize uses the
shared host's `FleuryTester.viewportSize` setter, so ambient MediaQuery rebuilds
are included. Full semantic snapshot timings exclude visual paint, coverage,
semantic diff and transport; idle and retained-leaf flushes usually avoid this
full walk. The row fixture is a mounted `ScrollView`/`Column` at 120×40 with
one `Text` per row, comparing keyed and unkeyed rows under a keyed scope.

The heap probe uses explicit GC in two fresh deterministic VM-service processes
per revision. It measures before mount, mounted after edit/resize/selection and
a semantic snapshot, emptied while mounted, released, and after 50 more cycles.
Fleury-class bytes are shallow and exclude SDK storage. SDK string totals are
reported separately and are process-wide; lifecycle deltas are evidence about
retained string storage, not allocation rate or total application RAM.

```sh
# In profiling on both revisions, with identical final probe files:
dart pub get
dart compile exe bin/document_work_probe.dart -o /tmp/document-probe
/tmp/document-probe --kind plain --lines 10000 --frames 60 --wrap false
# Also 1,000 lines and wrapped text; alternate baseline/candidate order.
dart compile exe bin/semantic_build_probe.dart -o /tmp/semantic-probe
/tmp/semantic-probe 300
dart compile exe bin/frame_pipeline_probe.dart -o /tmp/frame-probe
/tmp/frame-probe --cols 120 --rows 40 --frames 600
# Also 80×24 and 200×60.
dart --deterministic --enable-vm-service=0 --disable-service-auth-codes bin/document_heap_probe.dart plain
```

## Next measurement target

Large plain wrapped edits and wrapped resize still process the document.
String/line materialization and width measurement are the next trace-backed
targets if application workloads require more improvement. Reusing additive
token widths is not automatically equivalent: combining marks, variation
selectors and inserted spaces can change grapheme boundaries. No persistent
multi-width cache, semantic structure-generation cache, reconciliation rewrite
or virtualization layer is introduced by this pass.
