# Notification bursts and element dependency storage

This pass starts at `25bd5cc0` (main after #223). It investigates notification
bursts and allocation churn in ordinary short-label screens, retains lazy
element dependency storage, and rejects notification coalescing. It changes
no public API, notification timing, semantic freshness rule, or gate tolerance.

## Retained change and review

Every `Element` previously constructed two mutable sets before it had any
dependencies: one for inherited widgets and one for external sources such as
animations. Most structural elements never use either set, and none of the
five measured sample screens uses an external dependency set in its settled
state. These are SDK collections, so the earlier Fleury-class-only heap
inventories did not include their storage.

The sets are now allocated on first registration. Detaching releases them;
external teardown transfers the old set into a local batch before calling any
source, so a re-entrant registration creates a separate set. This also avoids
an empty list copy and error collector on the common path with no external
dependencies. Actual sources still detach in insertion order, and a throwing
source cannot prevent later sources from detaching.

Review checked first registration, repeated reads, inherited notification,
`didChangeDependencies`, GlobalKey deactivation/reactivation, registrations
made during detach callbacks, and exception-safe cleanup. Four regression
tests cover deduplication, throwing-source cleanup, and ordinary/re-entrant
GlobalKey moves. The focused inherited-state, lifecycle, reparenting and
animation suite passes 162 tests. The regenerated browser client's JavaScript
bytes are unchanged; only its source fingerprint changes.

## Live storage

Each row uses a separate deterministic Dart 3.12.2 VM process on macOS arm64,
a 120x40 viewport, the production-shaped sample host, 300 leaf frames, and
explicit GC. Baseline and candidate use identical flags. After sampling the
heap, the probe walks every mounted element through the VM service and reads
its actual dependency fields and each set's shallow size.

| Sample | Elements | Element-owned sets before | After | Live bytes saved |
| --- | ---: | ---: | ---: | ---: |
| Dashboard | 262 | 524 | 88 | 27,904 |
| Agent | 135 | 270 | 38 | 14,848 |
| Files | 310 | 620 | 111 | 32,576 |
| Finance | 498 | 996 | 160 | 53,504 |
| Editor | 102 | 204 | 28 | 11,264 |

That removes 82–86% of the two element-owned dependency sets. Every dependency
edge count and element count matches baseline. The retained sets containing
real edges are unchanged. Inherited providers' separate dependent sets are
also unchanged.

These are exact shallow-byte savings for these objects in this VM, including
the SDK sets that prior project-class totals excluded. They are **not** a
percentage reduction in total application RAM, a GC-pause result, or an AOT
RSS measurement. The absolute savings in these ordinary screens are 11–52 KiB.

## Allocation evidence

The allocation probe uses `setTraceClassAllocation` and
`getAllocationTraces`, separately from all timing runs. A known-allocation
control creates 123 objects and retains only 17. After explicit GC, both
versions report 123 allocation traces but only 17 live objects / 272 bytes.
The probe does not treat `accumulatedSize` as bytes allocated: Dart 3.12.2
reports that field from its heap walk, like `bytesCurrent`. The existing
allocation gates are kept as compatibility
checks and are not used to substantiate allocation-rate claims here.

In five mount/frame/teardown cycles of a 64-label board:

| Traced class | Baseline allocations | Candidate allocations |
| --- | ---: | ---: |
| SDK `_Set` | 4,492 | 947 |
| Framework cleanup collectors | 5,400 | 3,255 |
| SDK growable-list objects | 11,090 | 6,907 |
| SDK fixed-list/backing-array objects | 6,498 | 6,498 |

The one-cycle set control is 898 versus 189; the five-cycle results scale to
five times those counts plus two service-call allocations on both versions.
These are instrumented JIT object counts for the named classes, not total
allocated bytes. VM stack tails can be truncated; the recorded allocation
sites remain visible. The traces are diagnostic and never used as latency
measurements.

## AOT performance controls

Three fresh process pairs alternate baseline/candidate, candidate/baseline,
baseline/candidate. One benchmark runs at a time. The existing lifecycle probe
uses 500 iterations per case and the real-input probe uses 1,000. This covers
53 lifecycle/frame cases and 11 ordinary input cases. All 48 frame output
fingerprints and all 11 semantic-input fingerprints agree across versions.

| Terminal subtree replacement | Baseline median | Candidate median |
| --- | ---: | ---: |
| 16 rows, unkeyed | 88 us | 81 us |
| 16 rows, keyed | 103 us | 95 us |
| 64 rows, unkeyed | 322 us | 296 us |
| 64 rows, keyed | 376 us | 357 us |
| 256 rows, unkeyed | 2,348 us | 2,258 us |
| 256 rows, keyed | 2,650 us | 2,520 us |

These replacement cases improve by about 4–8%. Ordinary mount medians move
between 2.7% faster and 0.2% slower. Ordinary input medians move between 1.8%
faster and 1.6% slower: this is a storage/allocation improvement, not a claim
of faster typing. The largest median increase among the 53 core controls is
4 us / 4% in the smallest keyed structured one-label case (100 to 104 us).
Raw per-process values, phases and tails remain in the evidence.

The lifecycle probe includes rebuild/layout/paint and exact frame diff, with
semantic delivery in structured mode. The input probe uses real `runApp`
dispatch and scheduling with an in-memory peer; it excludes network and
physical display latency and mutes animation tickers.

## Rejected notification coalescing

The first trial deferred inherited-notifier broadcasts until the provider's
build, delivering one dependent walk for a burst. It passed the initial 33
notifier/focus/listener tests, but three alternating AOT pairs found little
benefit for 1–8 notifications per frame. Deliberate 64-event bursts improved
terminal frames by 12–16%, but structured frames by only about 3%. Review also
found that a scope with no subscribers would now schedule work.

The behavior change was not justified by these ordinary-workload results.
The trial was removed before the storage change, and its patch and timings
are retained only as rejected evidence.

## Qualification and reproduction

- `dart tool/fleury_dev.dart check`: all package analyses and 5,489 tests pass,
  including browser, dart2js smoke and PTY/integration checks (two existing
  skips).
- `dart tool/fleury_dev.dart benchmark gates`: all eight fast gates pass,
  with no baseline or tolerance changes.
- The post-disposal lifetime probe has four identical observations: 129 live
  Fleury objects / 4,192 bytes. This checks the measured class retention after
  repeated ordinary lifecycles, not total application memory or all leaks.
- The four dependency regression tests and the wider 162-test focused suite
  pass. Local review found no actionable correctness issue in the retained
  change; hosted CI results remain attached to the pull request.

From `profiling/`, compile separate baseline and candidate executables before
timing. Copy the same final probe sources into both checkouts and use Dart
3.12.2. Run each binary in a fresh process and alternate order across pairs:

```sh
dart compile exe bin/core_lifecycle_probe.dart -o /tmp/core-probe
dart compile exe bin/core_input_probe.dart -o /tmp/input-probe
/tmp/core-probe 500
/tmp/core-probe 500 structured
/tmp/input-probe 1000

dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
  bin/dependency_storage_probe.dart dashboard
# Repeat for agent, files, finance, editor, in separate processes.

dart --deterministic --profiler --enable-vm-service=0 \
  --disable-service-auth-codes bin/live_allocation_probe.dart AllocationSentinel
dart --deterministic --profiler --enable-vm-service=0 \
  --disable-service-auth-codes bin/live_allocation_probe.dart _Set 5 terminal mount
# Also _Set 1; _TeardownErrors, _GrowableList and _List at 5 cycles.

dart compile exe bin/notification_burst_probe.dart -o /tmp/burst-probe
/tmp/burst-probe 1000
```

The [evidence manifest](evidence/2026-09-06-dependency.json) records source and
binary hashes, raw measurements, live storage inventories and allocation
traces. The scope stays in shared element lifecycle and storage; browser DOM
presentation remains a separate unmeasured opportunity.
