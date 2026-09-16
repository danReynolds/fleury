# Cache recovery, geometry and keyed-list rebuilds

Follow-up to the September 15 architecture audit, updated against main
`2e5fd0e5ba1a1ea40c016c7eac0b66e7bb5cf7c3`.

## Changes

- A repaint exception leaves that cache and enclosing caches invalid. Partially
  written cells are never reused as a completed cache. Recovery stays with the
  host/error boundary; a persistent exception does not create a retry loop.
  Invalidations raised during a successful paint survive for the next frame.
- Repaint boundaries declare the clip already imposed by their finite cache.
  Fully clipped content no longer advertises visible focus/semantic bounds;
  partially clipped semantic bounds match displayed cells. Switching caching
  in either direction invalidates geometry and enclosing caches. Overflowing
  content still needs layout space or an external overlay.
- Keyed lazy lists automatically reuse their validated reverse lookup when the
  ordered keys are unchanged. Every key is still read on each parent update;
  visible rows still rebuild. Changed keys rebuild the lookup, validating
  duplicates including those outside the viewport. There is no new public API.

## Identity ownership and complexity

The key callback may close over mutable data. Neither unchanged callback
identity nor unchanged item count establishes that keys stayed the same.
A parent update therefore compares every key against the prior snapshot. This
is O(itemCount), but avoids a new key array and reverse map when keys match.

At the first changed key, capture reuses the already checked prefix and builds
a fresh map. Remaining keys are read once, and duplicates checked against the
entire captured prefix. The previous snapshot is never mutated: callbacks and
validation must succeed before publishing the replacement. Count changes use
a full capture. Navigation without a parent update already reuses the snapshot.

Keys require stable equality and hash codes. Equal fresh key objects can reuse
the snapshot; as with any map cache, the old equal key instances can remain
retained until keys change or the list unmounts. Row state, current-item identity,
viewport anchoring and pointer selection keep their existing behavior.

## Correctness evidence

Regressions cover paint exceptions before and after partial writes in single
and nested boundaries; frame-driver recovery after an unrelated repaint;
clipping and cache-mode changes under an outer cache; visible labels updating
with stable keys; same-closure mutable data; offscreen mutations and duplicates;
failed-capture retry; and a 200-update identity oracle exercising insertion,
removal, replacement, swapping, reversal and navigation.

The focused suite also covers eager/lazy controllers, horizontal scrolling,
follow-tail behavior, cursor/viewport preservation and pointer selection. The
profiling lab checks every measured update's 20 visible labels and exact key
read counts. Validation receipts and final measurements are recorded below.

## Validation and measurements

Measured runtime candidate: `b3fb70f7890f12d276a829dbc83f63286908f8fe`.
Later review changes strengthen a test assertion and integrate main PR #258
(composed buttons, managed toasts and stable Container backgrounds). The list
lookup and cache implementation are unchanged by that integration. The receipts
below describe the original measured candidate; final combined-head checks and
merge readiness are reported on PR #256.

- 3,543 core tests passed with one skipped, using repaint-cache verification;
  real-process/PTY integration tests were excluded locally.
- 1,294 companion widget tests, 167 focused runtime tests and 29 profiling tests
  passed. The strengthened five-test key-lookup suite also passed afterward.
- Changed runtime, test and profiling sources analyze cleanly. All eight fast
  structural gates passed. The regenerated browser asset changes only its
  source fingerprint; the JavaScript payload is unchanged.
- Final-head full repository CI is tracked on the PR separately from these
  local receipts; the previous head's checks do not qualify the new head.

The V2 lab ran five serial AOT process pairs per workload, reversing order each
pair, with the same frozen harness and dependency locks on both sides. Baseline
is main `f00a5b31`. The six list rebuild cases use 150 samples and 30 warmups;
the four broader cases use 500 samples and 60 warmups. All 100 processes passed
correctness checks and their retained raw artifact checksums were verified.
No builds or tests from this task ran during the measured processes.

| Workload | Main p50 | Candidate p50 | Paired change and 95% interval |
| --- | ---: | ---: | --- |
| 1,000 stable integer keys | 92 us | 64 us | -30.4% [-30.9, -29.4] |
| 100,000 stable integer keys | 5,881.5 us | 625 us | -89.4% [-89.8, -89.3] |
| 100,000 stable string keys | 9,399 us | 673 us | -93.0% [-93.5, -92.8] |
| Swap first pair, 100,000 keys | 5,781 us | 5,897.5 us | +1.4% [-3.2, +2.9] |
| Replace final key, 100,000 keys | 5,797.5 us | 5,906 us | +1.3% [+0.7, +2.0] |
| Unkeyed parent rebuild | 53 us | 52 us | +1.9% [-1.9, +2.0] |
| 40 panes | 46 us | 44 us | 0.0% [-4.3, +2.2] |
| Dashboard leaf update | 111 us | 112 us | +0.9% [0.0, +1.8] |
| Typing | 222 us | 224 us | 0.0% [-0.9, +3.2] |
| List navigation | 1,029 us | 1,035 us | +0.8% [-0.9, +2.0] |

Displayed p50s are medians of process summaries. Changes and bootstrap intervals
are computed from paired processes, so they need not equal the ratio of the two
displayed medians. The three stable-key cases improve at both p50 and p95; the
other cases show no clear change at the lab's 5% practical threshold. This
reproduces the earlier isolated prototype result with the checked-in V2 harness.

These are single-machine framework measurements, not physical terminal latency.
List rebuild cases measure setState through pump; frame cases exclude encoding
and display; input cases measure enqueue through a dispatch checkpoint. The
unchanged key scan is still O(N). No heap-size or GC-pressure reduction is claimed:
map reuse is supported by the code path and bounded hash-work regression tests,
not an allocation profile. Expensive application key callbacks may dominate.

## Reproduction

From a bootstrapped checkout:

```sh
cd packages/fleury
FLEURY_VERIFY_REPAINT_CACHE=1 dart test -x 'integration || pty'
```

From the repository root, use the pinned refs to reproduce the recorded
measurements. Use `origin/main` and `HEAD` for a new comparison:

```sh
dart tool/fleury_dev.dart benchmark gates
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=f00a5b31 --candidate=b3fb70f7 \
  --scenario=keyed-list-1k,keyed-list,keyed-list-strings,keyed-list-reorder,keyed-list-replace,unkeyed-list-rebuild \
  --runs=5 --samples=150 --warmup=30 --out=/tmp/keyed-list-comparison
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=f00a5b31 --candidate=b3fb70f7 \
  --scenario=panes-40,dashboard-leaf,typing,list \
  --runs=5 --samples=500 --warmup=60 --out=/tmp/cache-list-comparison
```

Use new output directories and run on a quiet machine without concurrent
builds/tests. The lab retains frozen harnesses, source/binary/dependency hashes,
raw samples, correctness counters and per-process confidence intervals. Raw
machine/build/test receipts remain local; only the summary ships with the PR.
