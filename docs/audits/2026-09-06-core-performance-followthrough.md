# Core performance follow-through

This pass follows merged PR #222 (`bb2e10b8`). It keeps two changes in shared
framework/semantic machinery and rejects a weak third candidate. It changes no
document layout, specialized document widget, scheduler policy, cache lifetime,
or public container interface.

## Retained changes and individual review

1. **Direct semantic JSON-to-UTF-8 conversion.** The wire encoder and its
   per-node byte accounting used to construct a complete JSON string before
   encoding UTF-8; emitted frames also copied the resulting bytes again. They
   now share a stateless `JsonUtf8Encoder`. A typed result is returned directly;
   other list implementations are copied to preserve the `Uint8List` contract.
   No node or input is retained by the converter. Redaction, graph validation,
   exact byte limits, patch staging and FULL resynchronization stay unchanged.
   New Unicode/escaping tests compare FULL/PATCH bytes with the original JSON
   serialization, including exact payload boundaries and private-value
   redaction. All 30 wire/sender/pipeline tests, changed-source analysis and all
   eight fast gates passed before this change was committed.
2. **Cheaper eager child removal.** Standard multi-child containers recognize
   a single deletion that preserves all remaining child identities and order.
   They drop that child, release its parent data, clear its cached placement
   and remove its list entry without rebuilding both identity sets. A shared
   internal helper verifies the transition; general replacement/reorder still
   uses the existing reconciliation. The framework also reads the defensive
   children-list copy once per detach. Flex, Stack, IndexedStack, Wrap,
   Navigator and eager ListView use this path. Custom containers keep the same
   interface and calls; lazy lists retain their existing direct removal.
   Review checked immediate GlobalKey reparenting, parent-data release,
   retained sibling ownership, offset/visibility cleanup and fallback behavior.
   Twenty new container regressions and 246 existing geometry, lifecycle,
   reconciliation, list, navigator and overlay checks passed. Source analysis
   and all eight fast gates passed before retention.

PR #222 was rebased and requalified after the testing API merge, then merged.
Its final head `ff307f37` and the squash commit `bb2e10b8` have identical trees.
This branch's two retained changes were replayed onto that merged main without
conflicts. Final contributor, wire and exact-commit CI receipts are in the PR.

## Final AOT results

| Workload | Main | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| Terminal: replace 16 unkeyed subtrees | 111 | 89 | 20% |
| Terminal: replace 64 unkeyed subtrees | 643 | 335 | 48% |
| Terminal: replace 256 unkeyed subtrees | 7,193 | 2,349 | 67% |
| Structured: update 16 unkeyed labels | 322 | 304 | 6% |
| Structured: update 64 unkeyed labels | 1,001 | 910 | 9% |
| Structured: update 64 keyed labels | 887 | 784 | 12% |
| Structured: replace 64 unkeyed subtrees | 1,708 | 1,308 | 23% |
| Structured: replace 64 keyed subtrees | 1,513 | 1,093 | 28% |
| Structured: replace 256 unkeyed subtrees | 10,777 | 5,757 | 47% |

Values are medians of three fresh-process medians, in microseconds. They are
framework workload costs, not a general app speedup or physical input-to-display
latency claim. The large 256-row cases are scaling controls with offscreen rows.
All 48 control-tree cases preserve rendered-text fingerprints across variants
and repeats; every measured update changes visible output. The five sample
mounts do not record fingerprints and are covered by functional tests.

The largest median increase among the 53 cases was 6.7%: a structured
single-label update in the 64-row unkeyed control, 357 to 381 microseconds.
The earlier independent three-pair combined trial measured that same case at
362 to 355 microseconds. The final slower processes also spent more time in
unchanged build/paint/tree phases. Both raw trials are retained; no claim that
every workload improves, or that small differences beat shared-host variance,
is based on these results.

The encoder-only trial reduced the 64-label unkeyed structured encoder phase
from 339 to 258 microseconds (24%), and the full frame from 990 to 898 (9%).
The subsequent removal-only trial reduced 64-subtree terminal replacement from
593 to 312 microseconds (47%), and 256-subtree replacement from 7,110 to 2,394
(66%). These isolate the retained changes; use the final combined table above
for comparisons with main.

## Rejected candidate and remaining costs

A plain semantic-leaf shortcut avoided empty action-target maps while still
revoking old action leases. It passed 175 semantic/remote action tests, including
new disappear/reappear and stale-token checks, but produced small, inconsistent
whole-frame gains: for 64 unkeyed labels, 893 to 903 microseconds; keyed labels,
795 to 783. It was removed before continuing. Its production patch and raw
trial values are preserved as rejected evidence, not shipped code.

The final JIT attribution collected 10,312 samples across the complete core
workload. Semantic flush was about 54% inclusive and frame construction about
45%; semantic tree construction was 23% and encoding 23%. Exclusive samples
were distributed across string/JSON encoding, key hashing, semantic identity,
building and painting. JIT percentages are diagnostic, not AOT timing proof.
This does not justify a new retained cache or weaker semantic freshness policy.
Single-removal scans/list shifts remain linear per detach; large replacement
is not claimed to become asymptotically linear. Further ownership changes need
an app profile that warrants expanding that contract.

## Lifetime check

After warmup and each of three further lifecycle cycles, the probe reported
exactly **4,192 bytes in 129 live Fleury-package objects**. The class inventories
were identical and contained no mounted elements, render trees, BuildOwner,
SemanticTree, FrameSemanticsPipeline or SemanticsWireEncoder. Remaining objects
were constants/enums and shared values. The VM heap itself moved from
33.23 to 33.76 MB during this JIT/profiling run; that is not represented as a
stable total-memory result or a memory saving from these changes.

The lifetime probe warms and repeatedly runs the ordinary 16/64/256-row core
control trees through state changes, layout/paint, semantic construction,
encoding and disposal. It samples Fleury-package class counts after explicit
GC and a turn of the event loop. SDK containers, code, profiling fixture classes
and external allocations are not included in project-class totals. Raw VM heap
usage is also retained, but this is not a total-RAM, allocation-rate or general
leak qualification. In this SDK, `accumulatedSize` must not be treated as a
cumulative allocation counter; this probe uses post-GC `bytesCurrent` only.

## Reproduction and evidence

Use `profiling/bin/core_lifecycle_probe.dart` on both revisions with identical
`sample_frame_host.dart`, Dart 3.12.2 on macOS arm64, 120x40 viewport, 160 measured
iterations, 15 mount warmups or 30 state-update warmups. Compile each variant
with `dart compile exe`; alternate one native process at a time across three
pairs for each of `terminal` and `structured`. No own tests or compiler jobs ran
alongside timed processes; the host is shared, not an isolated performance lab.
Structured mode includes the real semantic wire encoder and a manual flush
scheduler, excluding input dispatch, event-loop waiting, transport and display.

The evidence manifest pins revisions, source/harness hashes, executable hashes,
final/trial CSVs and the lifetime result. The existing core CPU probe supplies
JIT attribution; `core_lifetime_probe.dart` supplies the bounded teardown check.
The embedded browser client was regenerated from final source. No gate baseline
or tolerance was changed.
