# Profiling V2 validation

The V2 lab is implemented independently of PR #251. No framework runtime API
or rendering algorithm changes are included. The workflow and measurement
boundaries are documented in [Profiling V2](../implementation/profiling-v2.md).

## Validation

- [25 profiling tests passed](evidence/2026-09-15-profiling-v2/profiling-tests.log), including every workload, per-edit correctness, statistics, failure accounting, and external profiler isolation.
- [Eight CLI contract tests passed](evidence/2026-09-15-profiling-v2/cli-tests.log).
- [Analysis passed](evidence/2026-09-15-profiling-v2/analysis.log) with four existing informational unnecessary-import notices in `input_alloc_gate.dart`. [Reporting/shared-host regression tests](evidence/2026-09-15-profiling-v2/report-tests.log) passed after the final reporting cleanup.
- [Two real live-socket sessions completed](evidence/2026-09-15-profiling-v2/live-success.json), retaining five raw latency samples each. These were correctness checks, not an AOT performance comparison.
- [A deliberately forced 1 ms initial-paint timeout](evidence/2026-09-15-profiling-v2/live-failure.json) returned exit 1 and preserved the failed attempt. It was an expected negative test.
- [Changing one copied raw sample](evidence/2026-09-15-profiling-v2/tamper-rejected.json) caused checksum rejection, an incomplete report, and exit 1. The original experiment remained intact.

## Repeatable experiments

Both source revisions include current main `46c6e780a632dd88f7b6d828e33232f1845937ae`.
The candidate is PR #251 at `2d44578c247e3de29ab742d518d7887b113bf8b7`.
Each experiment used the same frozen workload on both sides, AOT Dart 3.12.2 on
macOS arm64, five alternating fresh-process pairs, 300 measured operations and
50 warmup operations per process. Burst cases use 16 inputs per operation.
Builds finished before measurements; no concurrent benchmark or test jobs ran
during the timed sweeps. This remains evidence from one developer machine.

The [A/A calibration](evidence/2026-09-15-profiling-v2/aa-report.md) ran 60
processes across six scenarios. Every total-time p50/p95 comparison reported
**no clear change**. This calibrates noise for that session; it is not a
cross-machine guarantee.

The [main versus PR #251 comparison](evidence/2026-09-15-profiling-v2/pr251-report.md)
ran 110 processes across all 11 scenarios. Every total-time p50/p95 comparison
also reported **no clear change** at the default 5% practical threshold.
For example, the medians across processes were 46 → 46 µs for 40 panes,
222 → 223 µs for typing, and 1017 → 1034 µs for list navigation. Paired percentage
estimates and uncertainty are in the report; they are calculated within pairs,
not by dividing these aggregate medians.

Several isolated layout phases hit the microsecond timer floor on one or both
sides. V2 labels those **below timer resolution**, rather than reporting a
misleading 100% improvement. The results do not establish an application-wide
performance benefit for #251. Structural layout savings and its correctness
qualification are separate evidence in that PR. No merge was performed.

## Diagnosis

The [external CPU/heap diagnostic](evidence/2026-09-15-profiling-v2/trace.md)
recorded 643 CPU samples over a 0.86-second typing window, with no unknown leaf
samples. Heap usage was 32,027,584 bytes before the workload, 43,698,544 after,
and 32,967,936 after forced GC. These include JIT state and sample bookkeeping;
they are not evidence of a leak or an AOT allocation rate.

The initial development check exposed two measurement problems, both fixed:
collecting profile objects inside the app inflated its own heap, and forcing GC
before fetching CPU samples lost JIT symbols. The supervisor now runs in a
separate process, and CPU symbols are fetched before diagnostic GC. A regression
test verifies that VM-service profile objects are not instantiated in the
measured app. CPU/heap diagnostics are never mixed into the clean AOT comparison.

## Reproduce and inspect

```sh
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=46c6e780 --candidate=46c6e780 \
  --scenario=panes-40,resize,typing,list,burst,slow-output \
  --runs=5 --samples=300 --warmup=50 --out=/tmp/fleury-aa

dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=46c6e780 --candidate=2d44578c \
  --runs=5 --samples=300 --warmup=50 --out=/tmp/fleury-pr251

dart tool/fleury_dev.dart benchmark lab trace \
  --scenario=typing --samples=1000 --warmup=100 --out=/tmp/fleury-trace
```

Compressed evidence bundles preserve manifests, exact frozen harness files,
dependency locks, raw samples and checksums: [A/A](evidence/2026-09-15-profiling-v2/aa-raw.tar.gz),
[PR #251](evidence/2026-09-15-profiling-v2/pr251-raw.tar.gz), and
[diagnostic profiles](evidence/2026-09-15-profiling-v2/trace-raw.tar.gz).
Extract a comparison archive into a new directory and run `benchmark lab report
--out=<directory>` to regenerate its report. Source snapshots/binaries are
retained in the original local experiment directories; archives omit those
rebuildable copies. Manifest writes were subsequently made atomic and report
headings clarified; those changes do not alter the frozen workloads or raw data.
