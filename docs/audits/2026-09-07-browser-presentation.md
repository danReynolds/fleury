# Browser presentation work and listener storage

Baseline: `80343208771bf65145afb29c01b18bf0ea0aab1b`, main after #224.
This pass targets the shared browser host and semantic DOM presenter with
ordinary short-label screens. It keeps two small changes and introduces no
new cache, event delegation, CSS containment, or public API.

## Retained changes and review

The local browser host already compares each measurement with its previous
measurement. It now delivers geometry to the surface only when that value or
the surface size changes. Previously, every active frame rewrote every row's
style even with identical geometry. A Chrome MutationObserver control with
three real counter updates goes from six attribute writes to zero on a two-row
grid. Changed geometry, device-pixel ratio, newly sized rows, and a surface
resized outside the host still receive the current measurement. The existing
surface API retains its behavior.

The semantic DOM presenter now installs a click listener only when a node has
an action or needs to block clicks because it is disabled. Enabled passive
nodes already did nothing in their listener. They continue to let the browser
bubble clicks to an actionable ancestor. Full and incremental presentation
both synchronize listeners when actions or enabled state change. Tag changes,
stale-node sweeping and disposal still remove old listeners.

The review checked first measurement, equal new measurement objects, geometry
changes without cell-count changes, external surface resizing, cursor styles,
passive-to-actionable transitions, disabled passive nodes, bubbling, tag
replacement, stale targets, and disposal. The focused browser/served-host suite
passes 60 tests. Four new regression tests cover the retained changes. The host
mutation assertion was also run on baseline and fails with six writes.

## Native listener counts

The diagnostic page mounts a semantic presenter with passive labels and four
nodes requiring listeners: an actionable root, two buttons and a disabled
passive node. Chrome's `Memory.getDOMCounters` samples the page while it remains
mounted. Each row uses a fresh process and the same final probe source.

| Passive labels | Semantic nodes | Native listeners before | After |
| --- | ---: | ---: | ---: |
| 16 | 20 | 20 | 4 |
| 64 | 68 | 68 | 4 |
| 128 | 132 | 132 | 4 |

That removes 80–97% of the native listeners in these fixtures. All semantic DOM
fingerprints, node counts, action requests and disabled-node checks match. The
probe measures listener objects in a mounted page; it does not claim a total
RAM percentage or byte savings. Its `--frames` argument selects the number of
passive labels when reusing the capture launcher, not a timed frame count.

## Browser frame controls

Chrome animation-callback durations: median of the three process-level
percentiles, in milliseconds:

| Control | Baseline p50 | Candidate p50 | Baseline p95 | Candidate p95 |
| --- | ---: | ---: | ---: | ---: |
| Normal interaction | 1.484 | 1.399 | 2.344 | 2.103 |
| One changing cell | 1.049 | 0.961 | 1.732 | 1.481 |
| Typing (includes skipped callbacks) | 0.334 | 0.273 | 2.125 | 2.172 |
| Cursor updates | 1.420 | 1.358 | 2.181 | 2.488 |
| Clean-frame control | 0.168 | 0.106 | 0.416 | 0.276 |
| Full-frame changes | 3.147 | 2.992 | 4.265 | 3.857 |
| Resize | 1.235 | 1.236 | 2.390 | 2.332 |

Normal-interaction callback medians improve in all three pairs (5–15%), with
a 5.7% reduction in the median of process medians. Other controls vary: one
changing-cell pair reverses direction, resize medians are effectively flat,
and the cursor p95 rises by 0.307 ms in the aggregate. Clean callbacks also
vary despite their rendering work already being skipped. These shared-host
runs do not establish a universal latency or frame-rate improvement. The
deterministic geometry-write and listener-count reductions are the strongest
results. Raw paired values, callback durations, rendering traces and host load
are retained rather than reducing the evidence to one speedup number.

Across the 42 captures, all 6,000 framework-frame counts and the checked
dirty-row, span, DOM creation/replacement and semantic counters match baseline.
There are 7,811 traced Chrome callbacks, including warmup/startup callbacks.

Captures use Dart 3.12.2, optimized dart2js (`-O2`) and native headless Chrome on
macOS arm64. The seven controls cover normal interaction, one changing cell,
typing, cursor updates, clean frames, full-frame changes and resizing. Scenario
names describe nominal viewport sizes; actual snapped dimensions are retained
in each capture. No large-document widget is used.

Each process warms 30 requested steps and measures 100. The input scenario
produces 200 frames, and resize produces 300; skipped frames and actual frame
counts remain explicit. Three fresh pairs alternate baseline/candidate order.
Only one timed Chrome process runs at a time, with no own tests or compilers
running alongside it.

The capture report now also records complete Chrome animation-callback
durations. These include host input/geometry work outside the existing Dart
render slices; the Dart `totalFrameMs` metric alone cannot measure the geometry
guard. Callback durations remain separate from the rendering trace, which
buckets style, layout and paint between animation-frame callbacks. Both trace
populations include warmup/startup and are not an end-to-end input-to-display
measurement. Synchronous browser layout can overlap the callback duration, so
the two trace timings must not be added. The general capture tool samples
browser heap/DOM counters after teardown without forced GC; those values are not used as memory evidence here.

## Rejected trials

An initial guard inside `DomGridSurface.resize` eliminated the redundant
mutations but added another full metric comparison on the hot path. Across
three pairs, several frame controls were slower, so that version was removed.
The retained host change uses the comparison the host already performs and
avoids calling resize for unchanged geometry. Its final measurements are
separate from the rejected trial.

Two CSS-only exploratory pages tried row layout containment and strict
containment of the semantic mirror. Neither established a clear benefit, so
no containment change was retained. Clean requested frames already skip the
rendering pipeline; this pass does not claim a new clean-frame optimization.

## Qualification and reproduction

- `dart tool/fleury_dev.dart check`: all package analyses and 5,493 tests pass,
  including 527 web tests, browser/dart2js smoke and PTY/integration checks
  (two existing skips).
- `dart tool/fleury_dev.dart benchmark gates`: all eight fast gates pass,
  with no baseline or tolerance changes.
- The final capture-tool timing addition is separately analyzed and exercised
  by every final Chrome timing run; the full contributor check above qualified
  the production changes before this reporting-only addition.
- The remote client bundle is regenerated: 399,949 to 400,047 JavaScript bytes
  (+98 bytes), source fingerprint `830af984a971a41a`.
- Local review found no actionable correctness issue. Hosted CI results remain
  attached to the pull request for the committed head.

From each checkout's `packages/fleury_web/`, compile the page once, before any
timed runs:

```sh
dart run tool/web_frame_capture.dart --compile-only --page-dir=/tmp/web-base
dart run tool/web_frame_capture.dart --page-dir=/tmp/web-base \
  --scenario=single-dirty-cell-160x50 --frames=100 --warmup=30 \
  --trace-frames --output=/tmp/base-cell.json
```

Repeat for the other six controls and for a separately compiled candidate,
alternating process order. For the native listener probe, copy the same final
`web/semantic_listener_probe.dart` into baseline before compiling:

```sh
mkdir -p /tmp/listener-base
cp /tmp/web-base/index.html /tmp/listener-base/index.html
dart compile js web/semantic_listener_probe.dart -O2 \
  -o /tmp/listener-base/benchmark_capture.dart.js
dart run tool/web_frame_capture.dart --page-dir=/tmp/listener-base \
  --frames=64 --output=/tmp/listener-base-64.json
```

Repeat with 16 and 128 labels and the candidate. The
[evidence manifest](evidence/2026-09-07-browser.json) records exact source and
compiled-JavaScript hashes, per-process frame results, the rejected trial, and
the listener snapshots.
