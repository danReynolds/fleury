# Core text storage and lifecycle performance

The preceding viewport/selection pass, PR #217, was reviewed, its findings
resolved, and its final CI passed before merging as
`85ea87fec94ccbfaa4097703384bd1c8b96fe649`. This pass starts from that main.

## Retained changes and review

Each production change was reviewed and measured before starting the next.
The incremental CSV preserves both retained and rejected trials, including
median/p95 timings, output fingerprints, changed-frame counts and copy lengths.
These are informational measurements; no gate or tolerance was weakened.

1. `eb485676`: ordinary glyphs retain only grapheme, width and immutable style.
   Lowered emoji atoms alone carry group metadata; newline identity comes from
   the grapheme. Reviewed newline creation, lowering boundaries and selection
   source recovery. 119 targeted regressions and all eight fast gates passed.
   The 67,000 ordinary glyphs in the selected rich-document heap probe shrink
   from 4,288,000 to 2,144,000 shallow live bytes.
2. `a1613467`: resolve styled source runs once per update and compare their
   values before remeasuring/wrapping. Preserve each source span boundary;
   preserve the cross-span paragraph walk on lowering surfaces. The snapshot
   observes mutation of reused child lists instead of trusting span identity.
   Tests cover equal distinct trees, mutable children, ambient styles,
   changed grapheme boundaries and policy changes. 122 regressions and all
   eight fast gates passed. At 1,000 lines, unchanged rich-document rebuilds
   fall from about 11–12 ms to 0.10–0.15 ms, including 1,000 styled spans.
3. `fd82aca4`: initially share immutable printable-ASCII glyphs inside each
   resolved source run with a temporary 95-slot index (extended in change 9). It is discarded after flattening;
   there is no retained/global pool or invalidation scheme. Styles and policy
   remain local to the run; non-ASCII clusters and lowered groups retain their
   resolver paths. 123 regressions, eight fast gates and the 7,680-case
   differential contract passed. The selected rich-document probe uses
   315,600 total Fleury-class shallow live bytes versus 4,474,560 on main.
4. `9092ad7b`: wrap over ranges in the existing glyph list, removing transient
   paragraph, word and separator lists. Reviewed empty/trailing/consecutive
   spaces, link whitespace, zero-width glyphs, forced word breaks, explicit
   newlines, truncation and unbounded widths. All 123 regressions, eight gates
   and the differential contract passed. Resizing a 1,000-line rich document
   drops from about 5.7 ms to 3.9 ms in the incremental comparison.
5. `87f42288`: copy only intersecting lines for ordinary selections, avoiding
   a temporary joined string for the whole document. Lowered groups retain
   their existing canonical-source splice. Regressions cover every forward
   and reverse pair of boundaries across blank lines, CJK and a ZWJ cluster.
   125 regressions, eight gates and the differential contract passed. A short
   selection in a 10,000-line document takes roughly half or less the former
   copy-plus-frame time in the measured plain/rich workloads.
6. `88c54c46`: use the character buffer when constructing selection text from
   single-code-unit glyphs, keeping multi-code-unit clusters intact. Reviewed
   UTF-16 preservation, empty clusters and source offsets. 125 regressions,
   eight gates and the differential contract passed. This reduces the
   incremental 1,000-line resize measurement by about 15%.

7. `cd24fe69`: retain the scalar document length with the existing layout-line
   identity. Repeated range queries now reuse it; replacement recomputes it, and
   every paint (including an empty paint) releases obsolete line snapshots.
   No per-line offset index was added. The full-copy control exposed a slowdown
   in the initial slice-based copy implementation: complete selections now use
   the SDK bulk join. With length reuse, 10,000-line drag frames fall from about
   0.35–0.37 ms to 0.10–0.12 ms, and partial/full copy both improve. 128 targeted
   regressions and all eight fast gates passed. The initial copy-control CSV
   is retained as evidence of the qualification finding, not the final result.

8. `5c799041`: fix an existing mainline clipboard bug exposed by the lowering
   control. A newline after a lowered emoji was included in its source group,
   then swallowed when copy restored the canonical emoji. Close the group
   before the newline unless the same group continues on the next row.
   Explicit, blank and trailing newlines are preserved; forced breaks inside
   one lowered cluster still reconstruct that cluster exactly once.
   129 targeted regressions and all eight fast gates passed.
9. `308a19ee`: use one temporary 95-slot glyph factory per flatten operation,
   including ordinary glyphs on lowering surfaces. Reuse requires identical
   immutable style; lowered atoms always retain source-position identity.
   This also removes repeated temporary indices for short source runs.
   130 targeted regressions, eight gates and the corrected differential
   contract passed. The incremental unselected split-policy probe falls
   from 2,332,048 to 317,072 shallow Fleury-class bytes.
10. `61fbeacd`: reuse already measured unwrapped plain-text paragraphs when
    constraints change. No extra persistent cache is added; size is constrained
    again using the kept line widths, including maxLines truncation. All
    content/width-policy/wrap setters invalidate the existing cache. Line-list
    identity still refreshes so pointer selection observes the new geometry.
    155 targeted layout/selection regressions and all eight gates passed.
11. `f614571e`: reuse unwrapped rich-text flow on constraint-only resize using
    the render object's existing layout-dirty flag and one scalar natural
    width. Dirty content/policy/wrap/maxLines still reflow. Refresh the
    selection-line identity while retaining glyphs and source-group offsets.
    137 targeted regressions and eight gates passed. Tests compare retained
    layouts with fresh/recomputed layouts across Unicode policies, empty text,
    edits, zero/unbounded widths, truncation and pointer selection on resize.
    Both fresh and repeatedly resized 7,680-case contract runs agree.

## Final measurements

Baseline: `85ea87fe` (main after #217). Candidate production revision:
`f614571e`. Dart 3.12.2, macOS 26.2 arm64, 10 logical CPUs. Values below are
the mean of two per-process AOT medians with alternating execution order.
Raw median/p95, output fingerprints, frame counts and copy lengths are in
`evidence/2026-09-05-core-text-storage-document.csv` (376 records). Opening
and editing still scale with document size; unchanged rebuilds reuse layout.

| Workload | Main | Candidate |
| --- | ---: | ---: |
| Rich text, 1,000 lines: open + first frame | 11.66 ms | 6.92 ms |
| Rich text, 1,000 lines: equal-content rebuild + frame | 12.48 ms | 0.098 ms |
| Rich text, 1,000 lines: edit + frame | 12.84 ms | 6.99 ms |
| Rich text, 1,000 lines: wrapped resize + frame | 5.74 ms | 3.43 ms |
| 1,000 styled spans: open / edit + frame | 11.42 / 12.81 ms | 7.48 / 7.68 ms |
| Rich text, 10,000 lines: open / edit + frame | 129.68 / 211.74 ms | 69.00 / 72.35 ms |
| Rich text, 10,000 lines: wrapped resize + frame | 103.31 ms | 37.56 ms |
| Rich text, 10,000 lines: unwrapped resize + frame | 66.03 ms | 0.110 ms |
| Plain text, 10,000 lines: unwrapped resize + frame | 5.53 ms | 0.214 ms |
| Plain text, 10,000 lines: pointer drag + frame | 0.360 ms | 0.103 ms |
| Rich text, 10,000 lines: partial / full copy + frame | 1.054 / 0.945 ms | 0.180 / 0.791 ms |
| Plain text, 10,000 lines: partial / full copy + frame | 0.831 / 0.821 ms | 0.163 / 0.713 ms |

The one-span and many-span variants both improve. The final unwrapped change
was separately compared against the preceding optimized candidate: 10,000-line
rich/spans resize falls from roughly 39–43 ms to 0.11 ms under both spec and
split policies. Its plain-text control falls from 7.59 ms to 0.25 ms. Separate
runs naturally differ in absolute timing; do not multiply these speedups.

Plain wrapped opening/resize remain within about 1% of main in the final
series; the 10,000-line edit control is 6.1% slower. No plain wrapped-edit win
is claimed. The 45 sample-app/mode/viewport controls range from 2.1% slower to
8.1% faster, with matching changed-frame counts, render-object counts and
mutated-leaf identities. They establish a small-control comparison, not a
claim of another broad frame speedup. Forced clean frames are not idle cost:
production skips the frame when idle. Leaf mode mutates the recorded Text
render object; it does not simulate the complete keyboard-input pipeline.

The selected 1,000-line spec rich-document fixture drops from 4,474,592 to
315,648 shallow Fleury-class live bytes after GC (92.9% less). The unselected
split-policy fixture drops from 4,476,016 to 317,072 bytes (92.9% less).
Ordinary glyph storage is now bounded by repeated ASCII/style values plus
non-ASCII occurrences; lowered atoms remain distinct. These totals exclude
SDK strings/lists and are not total application memory.

As a separate whole-process measure, the 1,000-line rich-text all-operation
AOT batch peaks at 218.7 MiB RSS on main versus 83.6 MiB on the candidate;
the 10,000-line batch is 301.2 versus 185.1 MiB. This includes fixtures, VM,
all operations and temporary allocation/GC effects. It is not steady-state
RAM, and results differ by fixture and process execution history.

All twelve lifecycle runs (three document shapes, two revisions, two fresh
processes each) release document render objects and non-constant glyphs on
unmount. The released Fleury-class total is unchanged after fifty more
mount/edit/resize/select/unmount cycles. Clearing the mounted document also
releases its glyphs. The new empty-document fixture initializes 176 bytes
(plain) or 208 bytes (rich/spans) of const widgets/style values on both
revisions after the initial warmup; this constant step is not growing
retention. The CSV preserves every before/mounted/emptied/released/after-50
snapshot, including that step. Whole VM-heap numbers are informational.

## Final review and qualification

The final production diff was reviewed for width-policy/resolver behavior,
source-run boundaries and mutable children, linked whitespace, lowered group
identity, copy boundaries, layout invalidation and retained selection state.
The last change passed 137 targeted regressions, all eight fast gates,
profiling analysis, and both 7,680-case contract modes. The embedded client
was regenerated with source fingerprint `e79aad9efd8e7a92`.

Copilot's first review claimed that the profiling switch requires explicit
break/return statements. Pinned Dart analysis and AOT compilation/runs prove
that finding false; its evidence response is recorded on PR #218. The final
production revision was submitted for another review. Final contributor,
wire, CI and merge receipts are recorded in
[PR #218](https://github.com/danReynolds/fleury/pull/218). The evidence manifest
pins production source hashes and AOT binary hashes so later documentation
commits do not change which implementation these measurements describe.

## Workloads and proof boundaries

`document_work_probe.dart` measures initial mount/first frame, equal rebuilds,
edits, resizing between 60 and 80 columns, pointer-driven selection and copy.
Fixtures are log-shaped with distinct numbers, ASCII, CJK and ZWJ emoji. They
use plain text, one styled source run, or one differently styled span per line.
Fixture generation is outside timing. Opening includes mount and first frame;
other operations include mutation, frame construction, diff and commit.
Process startup, terminal encoding/transport and terminal display are excluded.
The final probe also includes full-document copy as a regression control and
unwrapped resize as a separate workload. Defaults use soft wrapping.

`rich_text_contract_probe.dart` produces a deterministic fingerprint over 7,680
cases spanning widths 0/1/5/12/unbounded, wrap on/off, preserve/CJK/lowering,
truncation/overflow, blank lines, control sanitization, zero-width glyphs,
styles/links, viewport clipping and selected copy. All 7,680 display/layout
fingerprints match main (aggregate `2643625153`). Exactly 578 copied outputs
change, exclusively under split policy and exclusively by inserting the
previously lost newlines. Main copy aggregate is `3255039233`; corrected copy
is `1645656357`. The corrected combined fingerprint is `3670255327`, both
with fresh layouts and with repeated constraint changes (`--resize`).

The JIT CPU attribution probe is separate from AOT timing claims. After range
wrapping, 3,635 CPU samples from repeated 10,000-line resizes attributed about
51.5% inclusively to constructing selection lines; this motivated change 6.

Heap probes use deterministic Dart VM-service snapshots with explicit GC.
Fleury-class totals count shallow object storage and exclude SDK strings,
lists, VM/tool overhead and external allocations. They are not total RAM or
an allocation rate. Lifecycle snapshots exercise mount, replacement, resize,
selection and unmount, with ten warmup cycles and fifty additional cycles.
The final lifecycle probe also clears a large document while keeping its
render leaf mounted, then clears both frame buffers before inspection. This is bounded lifecycle evidence, not proof
that every application or callback lifetime is leak-free.

## Trials not retained

- A bounded per-run hash map shared non-ASCII glyphs as well, but opening and
  editing 1,000 short styled spans regressed about 10%. The fixed ASCII index
  retains most of the memory benefit and improves those operations.
- Checking glyph width before comparing for a newline improved only about
  2–4% in three alternating resize comparisons. It was discarded as a marginal
  result rather than expanded into another optimization.
- The earlier shared-frame pass already tested scratch-cell replay sharing
  and bounded Flex scratch allocation; ordinary sample-frame gains were only
  a few percent, with no demonstrated broad retained-memory reduction.
- Reconciliation rewrites, persistent layout caches and document virtualization
  remain unproven proposals. Caching the benchmark's two alternating widths
  would reward this script without establishing a real resize improvement.

## Stopping decision

This pass has mined the demonstrated large wins in the shared text pipeline:
retained glyph storage, equal-content rebuilding, transient wrap work,
selection/copy, and resize work that cannot change unwrapped flow. Stop broad
implementation hunting after this pass. The remaining measured trials were
small or regressed another representative workload; the larger proposals
need application traces and memory evidence before accepting new retained
state or changing architecture. In particular, plain wrapped layout remains
linear in document content, and rich-text edit/wrapped-resize still process
the document. Their cost is explicit in the receipts; it does not by itself
justify virtualization or a persistent multi-width cache for launch.

## Reproduction

Use Dart 3.12.2 on both revisions, run `dart pub get` in `profiling`, and copy
this revision's profiling tools to the main control worktree so both harnesses
are identical. Use distinct main/candidate binary names; the commands below
illustrate one side. Compile each in its own worktree before alternating runs. CPU probes must run serially without concurrent tests or compilers.

```sh
# In profiling, on both revisions:
dart compile exe bin/document_work_probe.dart -o /tmp/document-probe
/tmp/document-probe --kind rich --lines 1000 --frames 60
/tmp/document-probe --kind spans --lines 10000 --frames 30
/tmp/document-probe --kind rich --lines 1000 --frames 60 --policy split
/tmp/document-probe --kind rich --lines 10000 --frames 60 --operation resize --wrap false
# Repeat with --kind plain and spans; alternate main/candidate order.
# For macOS process peak RSS, prefix the all-operation command with /usr/bin/time -l.

dart compile exe bin/frame_pipeline_probe.dart -o /tmp/sample-probe
/tmp/sample-probe --cols 120 --rows 40 --frames 600
# Also 80x24 and 200x60; five sample apps, clean/leaf/full modes.

dart --deterministic --enable-vm-service=0 --disable-service-auth-codes bin/document_heap_probe.dart rich
# Also plain and spans, in two fresh processes per revision.
dart --deterministic --enable-vm-service=0 --disable-service-auth-codes bin/frame_heap_probe.dart --app rich-document --mode clean --cols 80 --rows 24 --frames 400 --selected true --policy spec
# For the main split-policy heap control use --selected false: main has the clipboard bug.

dart run bin/rich_text_contract_probe.dart --details
dart run bin/rich_text_contract_probe.dart --resize
```
