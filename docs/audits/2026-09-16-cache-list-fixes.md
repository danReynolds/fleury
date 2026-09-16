# Cache recovery, geometry and keyed-list rebuilds

Follow-up to the September 15 architecture audit, based on main `ebc05ea5`.
Measured runtime candidate: `147626b5adc31cfdb5272966c1bb0f3d7d48589b`.

## Changes

- A repaint exception leaves that cache and enclosing caches invalid. Partially
  written cells are never reused as a completed cache. Recovery stays with the
  host/error boundary; a persistent exception does not create a new retry loop.
  Invalidations raised during a successful paint still survive for the next
  frame.
- Repaint boundaries declare the clip already imposed by their finite cache.
  Fully clipped content no longer advertises visible focus/semantic bounds;
  partially clipped semantic bounds match the displayed cells. Switching
  caching in either direction invalidates geometry and enclosing caches.
  This keeps existing clipping behavior. It does not add overflow painting to
  the cache: overflowing content needs layout space or an external overlay.
- Lazy lists accept optional `itemKeyRevision`. An unchanged non-null revision
  and item count reuse the ordered-key snapshot. Visible rows still rebuild;
  the revision describes identities, not row content. Omitting it keeps the
  previous safe behavior for callbacks over mutable data. Snapshot creation
  must succeed before its revision can be reused.

The list API is opt-in because a callback can close over mutable data. Neither
callback identity nor unchanged item count proves that the keys stayed the same.
Use a persistent integer revision and increment it whenever keys or their order
change. A count change automatically refreshes the index. Switching into or out
of revision mode also refreshes it. No reverse-lookup callback is reintroduced.

## Correctness evidence

New regressions cover:

- An exception before or after partial writes, with one cache and nested caches;
  the next paint succeeds without reinvalidating the failed subtree and then
  becomes cacheable again.
- The real frame driver presents its root-backstop error, then recovers cached
  content when an unrelated sibling asks for a repaint.
- Fully and partially clipped focus/semantic geometry, cache hits, and mode
  changes below an outer cache. Disabling a cache restores pass-through overflow
  and enabling it restores the existing bounded clip.
- Both lazy list constructors avoiding a full key scan while updating visible
  row content, scrolling into later rows, reordered cursor/viewport/state,
  count changes, revision/keyed-mode transitions, mutable unversioned callbacks,
  and retrying a revision whose first key capture failed.

All 3,541 core tests (one skipped), 1,294 companion widget tests, 120 focused
list tests and all eight fast performance gates passed.
The core suite ran with repaint-cache verification enabled; real-process and
PTY integration tests were excluded locally. Static analysis of changed code
and tests is clean. The browser client was regenerated: only its source
fingerprint changed, not its JavaScript payload. Full repository CI is tracked
on the PR separately from these local receipts.

## Keyed-list measurement

`profiling/bin/keyed_list_rebuild_probe.dart` compares two configurations of the
same candidate binary, not two historical revisions. Both rebuild a keyed list
and change the labels of its 20 visible rows. Only the revision mode reuses the
key snapshot. Each process performs 30 warmups and 150 measured updates. Five
fresh process pairs per size alternate mode order; correctness checks verify
the displayed labels and exact key-call counts. Dart 3.12.2, macOS arm64.

| Item count | Automatic rescan p50 | Revision reuse p50 | Keys per update, auto / revision |
| ---: | ---: | ---: | ---: |
| 1,000 | 89 µs | 57 µs | 1,000 / 0 |
| 100,000 | 5,783 µs | 57 µs | 100,000 / 0 |

Values are medians of the five per-process p50s. Both modes rebuilt 20 rows per
update. The result supports an opt-in improvement for repeated parent rebuilds
with unchanged identities, not a universal list speedup. It measures setState
through the tester pump, excluding encoding, transport and display. It does not
quantify retained memory or physical terminal latency.

## V2 comparison with main

The unchanged V2 harness compared main `ebc05ea5` with candidate `147626b5` in
40 fresh AOT processes: five pairs across four scenarios, 500 samples and 60
warmups per process, alternating side order. All correctness checks passed.
No other tests or builds from this task ran during timed measurements.

| Scenario | Main p50 | Candidate p50 | Assessment at the 5% threshold |
| --- | ---: | ---: | --- |
| 40 panes | 45 µs | 45 µs | No clear change |
| Dashboard leaf update | 112 µs | 113 µs | No clear change |
| Typing | 223 µs | 224 µs | No clear change |
| List navigation | 1,019 µs | 1,052 µs | No clear change |

The paired intervals and p95 results are retained in the local V2 report. These are
single-machine measurements; no clear change is not a guarantee that every
workload has zero overhead. Frame workloads exclude encoding and display; input
workloads measure enqueue through a dispatch checkpoint, not physical latency.

## Receipts and reproduction

The review run retains the targeted raw samples (mode/order, counters, raw
per-process timings and executable checksum), the V2 manifest/frozen harness/
raw results, and complete local test logs. All 40 V2 raw-result checksums were
verified. Raw machine/build/test receipts stay local; this source change ships
only this measurement summary and the reproducible probes. The commands below
produce fresh evidence for another environment.

```sh
cd packages/fleury
FLEURY_VERIFY_REPAINT_CACHE=1 dart test -x 'integration || pty'
```

From the repository root:

```sh
dart tool/fleury_dev.dart benchmark gates
dart compile exe profiling/bin/keyed_list_rebuild_probe.dart -o /tmp/keyed-list-probe
/tmp/keyed-list-probe 100000 auto
/tmp/keyed-list-probe 100000 revision
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=ebc05ea5 --candidate=147626b5 \
  --scenario=panes-40,dashboard-leaf,typing,list \
  --runs=5 --samples=500 --warmup=60 --out=/tmp/cache-list-comparison-new
```

Run timing comparisons serially on a quiet machine and use a new output
directory. The targeted probe's comparison protocol is also documented in
`docs/implementation/profiling-v2.md`.
