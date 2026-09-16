# Profiling V2: compare, explain, verify

Use the profiling lab to compare a framework change against a pinned baseline.
It runs one frozen workload against both revisions, records raw measurements,
and reports variation between fresh processes. Existing wire probes and
structural gates remain the tools for terminal output and correctness.

## Start with a comparison

From a bootstrapped checkout:

```sh
dart tool/fleury_dev.dart benchmark lab list
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=origin/main --candidate=HEAD \
  --scenario=typing,list,burst,slow-output,panes-40,resize \
  --runs=5 --samples=300 --warmup=30 --out=/tmp/fleury-comparison
```

Refs are resolved locally to full commit hashes. Fetch before running if you
want the latest remote baseline. Uncommitted framework edits are **not** part of
either source revision; commit a candidate first. The workload itself comes
from the invoking checkout and is copied once, byte for byte, onto both source
snapshots. Its hash and exact files are retained. This lets the same new probe
run against older framework revisions that do not contain it.

The output directory must not already exist. The runner extracts source
archives under it, resolves matching dependency locks, builds both AOT binaries,
then runs serial baseline/candidate pairs. The order reverses every pair. Each
scenario/side/pair gets a fresh process; compilation finishes before measurement
starts. No existing worktree is modified. Git, tar, Dart and package resolution
are required; this workflow targets the same POSIX hosts as the existing tools.

Run comparisons on a quiet machine, outside concurrent builds/tests. Five
pairs is the minimum for a directional assessment, not a guarantee of
statistical power. Use more pairs and longer workloads when the result matters.
Run an A/A calibration (`--baseline=HEAD --candidate=HEAD`) on the same machine
to see the noise floor. Do not compare old files from different sessions by
pooling their raw frames.

## What is measured

| Workload | Boundary and checks |
| --- | --- |
| `panes-16`, `panes-40`, `panes-96` | One visible wrapping label changes in a grid of explicitly sized panes. Mutation through build, layout, paint, diff and commit; every measured mutation must change output. |
| `dashboard-leaf`, `editor-leaf` | The real sample app, with a visible text leaf changed. Same frame boundary and validation. These isolate rendering; they are not full user journeys. |
| `resize` | Real dashboard alternating 120×40 and 100×32; includes resize invalidation and the subsequent frame. |
| `typing` | Real TextInput alternates insertion/deletion beside a lazy log list. Input enqueue to the first event-loop checkpoint after dispatch. Controller and wire semantic value are verified. |
| `list` | Arrow navigation through a 100,000-row ListView; every input must advance the controller. |
| `paste` | Paste 4 KiB through the real input path. Clearing between pastes occurs outside the timed operation. Full controller and semantic text are checked. |
| `burst` | Sixteen text/delete events injected without awaiting individual responses, with log updates. Tracks each event's queue and dispatch-to-checkpoint time, and verifies every edit callback as well as final state. |
| `slow-output` | Same batch with a 10 ms blocked output sink. Checks that production stops while blocked and final output catches up. Dispatch latency and batch drain latency are separate. |

`--samples` means frames, individual closed-loop operations, or batches for
burst/slow-output. Batches contain 16 measured input events. `--warmup` uses the
same units and is excluded from samples. Burst load is an unpaced batch, **not**
a fixed-rate external arrival stream or a throughput ceiling.

Frame timings include buffer preparation and diff/plan work but exclude ANSI
encoding, transport and terminal rendering. Input timings include the real
runApp/structured-peer path but exclude OS input acquisition, socket transit,
peer rendering and physical display. A dispatch checkpoint may occur before
backpressured output drains. No measurement here is called input-to-photon.

Input cases disable caret blinking and animation tickers. The synthetic batch
fixture drives log changes from each edit so work and expected results are
deterministic. The sample-app pipeline fixtures retain their ordinary app code.
Debug counters are off. Raw samples accumulate in memory and are serialized
after the run; bookkeeping and validation between samples can still affect GC.
Microsecond phase values at zero on either side are below timer resolution and
cannot produce a percentage improvement claim.

## Read the artifact

Start at `report.md`; inspect `report.json` for all phase p50/p95/p99 comparisons.
Each reported quantile is calculated separately in each process. Bootstrap
intervals resample **process pairs**, never thousands of correlated frames as
independent observations. Relative changes use paired process values. The
default practical threshold is 5% (`--practical-percent` changes it).

An interval wholly beyond that threshold is a candidate improvement or
regression. Overlapping intervals and small differences report **no clear
change**. Fewer than five pairs are exploratory. Many metrics are examined
without a multiple-comparison correction: reproduce an interesting finding in
a focused second experiment before drawing a conclusion. Always read absolute
microseconds alongside percentages and separate phase gains from total cost.

`manifest.json` records source/harness/binary/lock hashes, SDK, OS, CPU count,
load snapshot, workload configuration and exact run order. `runs/` contains
stdout/stderr, immutable raw result JSON, all event/frame samples, correctness
checks, encoded output bytes and counts, and per-batch drain durations. End RSS
and process-lifetime maximum RSS include setup and harness memory; they are not
retained application heap or a workload-only memory peak.

Failed builds, timeouts, invalid output, missing samples and failed processes
make the whole experiment **incomplete** and return a nonzero exit status.
Remaining processes still run where possible. Failed-run logs are retained;
their measurements are never quietly replaced or averaged away. An interrupted
experiment can be inspected by regenerating its report:

```sh
dart tool/fleury_dev.dart benchmark lab report --out=/tmp/fleury-comparison
```

Raw artifact checksums are verified when reporting. Keep the output directory
until review is finished. The runner retains its owned source copies/binaries
for reproduction; delete that directory yourself when it is no longer needed.

## Explain a finding

Run the same scenario in diagnostic mode on the checkout being investigated:

```sh
dart tool/fleury_dev.dart benchmark lab trace \
  --scenario=typing --samples=3000 --warmup=100 --out=/tmp/fleury-typing-trace
```

Start with `trace.md` for CPU rankings, heap totals and attribution-quality warnings.
`trace.json` contains inclusive/exclusive CPU rankings, raw CPU samples,
GC timeline events, heap/class counters before and after the workload, and a
post-GC heap inventory. SDK classes such as strings and arrays are retained;
the report does not filter memory down to Fleury classes. The profile window
starts after mounting/warmup and ends before teardown. It also includes harness
validation and output accounting between measured operations; distinguish those
stacks from framework work. Check `cpuSampleCount` before trusting rankings.

A separate supervisor collects profiles while the app is paused at explicit
phase boundaries. Profile decoding and heap-inventory objects stay out of the
app's measured heap. The app only emits phase markers and pauses for collection.

This is a **JIT diagnostic run**, with forced GC at its boundaries and VM-service
overhead. Its timings cannot be compared to clean AOT samples. Class counters
are not allocation stack traces; use the existing `live_allocation_probe.dart`
when a particular class needs allocation-site attribution. A before/after heap
inventory also does not replace a long-running leak/GC-pressure experiment.

## Complete the proof at the right layer

| Question | Tool |
| --- | --- |
| Does the candidate reduce framework work or input scheduling delay? | `benchmark lab compare` |
| Which stacks or heap classes explain it? | `benchmark lab trace`, targeted allocation probes |
| Did idle skipping, coalescing, repaint behavior or output correctness break? | `benchmark gates`, runtime and repaint regression suites |
| Does native terminal output shrink; what is startup/CPU/RSS cost? | `benchmark wire …` and PTY artifacts |
| Does real served-socket latency/plan/semantics cost change? | `benchmark serve-wire-live …` |
| Did browser paint or physical terminal responsiveness improve? | Browser/terminal dogfooding and surface-specific measurements |

The live-socket profiler now retains every attempt and fails incomplete batches,
including all-failed batches. Its raw latency samples include partial samples
before a failure. PTY captures now record actual input `sentAtMs` beside the
requested delay. PTY polling is still 2 ms, so it cannot resolve sub-millisecond
input differences. Legacy `fps` fields mean observed scenario update cadence
(sometimes a logical-update or read proxy), **not maximum rendering capacity**.

CI runs the profiling correctness/smoke tests and existing structural gates.
It does not gate machine-sensitive lab timing percentages.

## Keyed-list parent rebuilds

The `list` scenario measures arrow input. The `keyed-list` scenarios measure
parent rebuilds with 20 visible rows and changing labels:

```sh
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=origin/main --candidate=HEAD \
  --scenario=keyed-list-1k,keyed-list,keyed-list-strings,keyed-list-reorder,keyed-list-replace,unkeyed-list-rebuild \
  --runs=5 --samples=150 --warmup=30 --out=/tmp/keyed-list-comparison
```

`keyed-list-1k` uses 1,000 integer keys; the other keyed cases use 100,000.
`keyed-list` and `keyed-list-strings` leave ordered keys unchanged. The reorder
case swaps the first two items each time; the replace case changes the final
key. `unkeyed-list-rebuild` is the control without identity lookup.

Each sample measures parent `setState` through `FleuryTester.pump()`. Outside
the timed operation, the workload verifies all 20 visible labels on every
update, and checks total key calls after the run. These cases exclude initial
mount, encoding, transport and display. They use the same frozen workload,
paired AOT runner and report validation as the other lab scenarios.

To explain key-comparison or map-building costs, use the same scenario with
`benchmark lab trace`. Diagnostic JIT timings are separate from AOT comparison
results. Every keyed parent update still checks all keys; unchanged keys reuse
the reverse lookup automatically. Callback identity alone cannot establish
that captured mutable data stayed unchanged.
