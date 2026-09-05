# Text viewport performance follow-up

PR #216 merged as `aa62ef9e63a5f8011198913dd76de181ddcd839a` before this
investigation. All comparisons below use that merged main as the baseline.
This pass looked for a substantial core CPU or memory improvement, measured
each candidate, and reviewed each retained change before the next one.

## Result

`RenderText` and `RenderRichText` recorded selection geometry correctly but
then traversed every laid-out row, including rows outside the paint buffer.
Buffer writes clipped the output only after that work. A `ScrollView` with a
long text child therefore paid for the whole document on every scroll frame.

The painters now skip rows above the buffer using string lengths to maintain
selection offsets, and stop at its bottom. They record full selection and
retained geometry first. No cache, public API, layout contract, or retained
state was added. Text outside the viewport remains available for selection
and copy. Ellipsis still belongs to the last laid-out visible line, rather
than being moved to the viewport edge.

The AOT probe scrolls a real `ScrollView(Text(...))` or
`ScrollView(RichText(...))` by one row in an 80×24 viewport, at the top,
middle, and bottom of a log-shaped document containing ASCII, CJK, ZWJ
emoji and distinct line numbers. Each position has 40 warmup frames and
200 measured frames. Two runs alternate baseline/candidate order. Every
measured frame changes output; final cell fingerprints agree across builds.
Times include the scroll mutation, build/layout/paint, exact diff, scroll
classification and commit. Initial layout, encoding, transport and terminal
display are excluded.

The table uses the mean of the two run medians; ranges cover all three
positions. It describes this active scrolling workload, not all Fleury apps.

| Content | Lines | Main frame time | Candidate frame time | Speedup |
| --- | ---: | ---: | ---: | ---: |
| Plain text | 100 | 181–184 µs | 80–96 µs | 1.9–2.3× |
| Plain text | 1,000 | 1,389–1,422 µs | 79–81 µs | 17–18× |
| Plain text | 10,000 | 13,486–13,937 µs | 77–106 µs | 128–181× |
| Styled text | 100 | 245–250 µs | 97–111 µs | 2.3–2.6× |
| Styled text | 1,000 | 1,989–2,026 µs | 98–106 µs | 19–20× |
| Styled text | 10,000 | 19,350–19,893 µs | 97–125 µs | 155–204× |

The five shipped sample apps were also compared at 80×24, 120×40 and
200×60, with 600 frames each in forced-clean, visible-leaf mutation and
all-render-objects-dirtied modes. Changes in mean median whole-frame time
range from 2.8% slower to 3.5% faster. This is effectively flat; the claim
is the document-scrolling improvement. Production idle skips rendering and
is not represented by forced-clean frames.

## Review and regression evidence

1. `cb11b522`: plain-text row culling. Reviewed buffer versus screen
   coordinates, selection offsets over skipped rows, blank lines, the
   layout-owned ellipsis condition, and retained geometry registration before
   culling. Its 699 rendering/editing/selection/scroll/width-policy tests and
   all eight fast performance gates passed before the next change.
2. `f51d49ce`: styled-text row culling. Applied the same boundary using
   `_selectionLines` lengths, without traversing hidden styled glyph lists.
   Expanded the full-paint-versus-viewport comparison to styled spans,
   including explicit inverse overrides. All three viewport tests and all
   eight fast gates passed. The other 709 targeted tests passed; the first
   combined invocation caught a missing internal import in the new test,
   which was corrected before its successful rerun.

The viewport tests compare every cell against a crop of a full-height paint,
with and without a partial selection, both width policies, wrapping,
alignment, maxLines and ellipsis. They exercise negative and fully offscreen
offsets and deliberately separate scratch-buffer coordinates from screen
selection coordinates. A counting resolver requires exactly nine grapheme
measurements for three visible three-grapheme rows of a 1,000-line document.
Fully hidden text must perform zero measurements while still recording its
full selection bounds.

Final contributor, embedded-client freshness and terminal-wire qualification
results are recorded in the PR. No performance-gate tolerance or baseline
was changed.

## Memory result and measurement correction

The deterministic JIT heap probe keeps each sample mounted, warms 300 frames,
then measures after explicit GC before and after 400 visible-leaf updates.
Fleury-class live bytes are identical on main and the final candidate:

| App | Fleury-class live bytes on both builds |
| --- | ---: |
| Dashboard | 270,320 |
| Agent | 108,272 |
| Files | 225,152 |
| Editor | 88,192 |
| Finance | 384,080 |

These are shallow bytes for classes defined in Fleury packages, including
widgets/samples. They exclude SDK strings/lists, external storage and VM/tool
overhead; they are not total RAM, peak memory or a general leak guarantee.
This pass claims no measured memory reduction.

An allocation sanity check with 100 versus 400 frames exposed a misleading
counter: in pinned Dart 3.12.2, the VM populates `accumulatedSize` and
`bytesCurrent` from the same current-heap walk, and does the same for their
instance counters. See the [pinned VM implementation](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/class_table.cc#L363-L370).
Dividing that value by frames does not measure cumulative allocation across
GC. Existing allocation-named gates were left intact, but their output is
not used here as proof of allocation rate. The new probe explicitly reports
post-GC live objects instead.

## Candidates not retained and remaining boundary

- Reusing immutable cells during scratch replay: all five mounted sample
  heaps were unchanged and whole-frame CPU improved only about 0–3% at
  120×40. A differential test passed 3,024 separate/self-copy cases with
  wide-cell repair, style overrides, damage and image metadata preserved.
  The candidate and its experiment-only test were removed.
- Bounding overflowing Flex scratch storage to its box plus a wide-cell
  halo: sample frame medians changed by roughly −1% to +5% across 40×12,
  80×24 and 120×40. The change could help pathological overflow storage,
  but a large representative benefit was not established. It was set aside
  without adding a production change.

Initial text projection, layout, wrapping and selection hit testing still
depend on document size. Skipping rows above the viewport still visits their
string lengths; it does not retain an offset index. The bottom of a
10,000-line document therefore remains slightly slower than its top. A new
index or a broader invalidation/cache redesign needs separate workload
evidence; neither is necessary for the demonstrated gain.

## Reproduction and raw evidence

Use the same probe source in two isolated profiling packages, one at the
baseline and one at the candidate. Compile before timing, then run one
process at a time, reversing order on the second run:

```sh
cd profiling
dart pub get
dart compile exe bin/scroll_text_probe.dart -o /tmp/scroll-text
/tmp/scroll-text --kind plain --lines 1000 --frames 200
/tmp/scroll-text --kind rich --lines 1000 --frames 200
dart compile exe bin/frame_pipeline_probe.dart -o /tmp/frame-pipeline
/tmp/frame-pipeline --cols 120 --rows 40 --frames 600
dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
  bin/frame_heap_probe.dart --app dashboard --mode leaf --frames 400
```

- [Environment, methodology and hashes](evidence/2026-09-05-text-viewport.json)
- [72 scrolling measurements](evidence/2026-09-05-text-viewport-scroll.csv)
- [180 sample-app measurements](evidence/2026-09-05-text-viewport-samples.csv)
- [10 mounted-app heap measurements](evidence/2026-09-05-text-viewport-heap.csv)
