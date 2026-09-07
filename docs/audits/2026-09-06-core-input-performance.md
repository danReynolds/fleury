# Core input performance

This follow-up measures real input in ordinary sample apps, building on the
qualified PR #223 head `3980fc98`. Its improvements are additional to the
[earlier encoder/removal pass](2026-09-06-core-performance-followthrough.md),
which used a different baseline. The retained production commit is `74a362f9`.

## Investigation and retained change

The runtime already coalesces frame requests and skips clean visual work.
Input still requires a conservative semantic refresh: contributors can read
live controller state without recording semantic dirt, and an ignored handler
result does not prove that state was unchanged. The existing regression for an
untracked contributor demonstrates why simply skipping that refresh is unsafe.
No invalidation or scheduling policy was changed.

The refresh repeatedly derived every semantic node's identity by walking its
entire ancestry. Real apps contain many shared framework wrappers. Full
snapshots now share ancestor paths within their synchronous collection walk,
alongside the existing snapshot-local sibling-index table. Each cached entry
keeps both the complete keyed scope and its positional suffix. A keyed child
discards the parent's positional suffix but retains its keyed ancestry, matching
the existing identity contract exactly. Fully unkeyed paths cache null and do
not compute unnecessary sibling positions.

The map is restored in `finally`, including nested snapshots and exceptions.
No path or element is retained between snapshots. Reads outside collection
continue using the original live parent walk. The public API, wire format,
action-target lease handling and full-refresh fallback are unchanged.

## Real-input AOT results

Each number is the median of three fresh-process medians, in microseconds.
Each process performs 30 warmup inputs and 1,000 measured inputs per case.

| Interaction | Baseline | Candidate | Reduction | Baseline p95 | Candidate p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dashboard: ignored key | 820 | 606 | 26% | 1,037 | 789 |
| Dashboard: pointer in unused corner | 817 | 597 | 27% | 1,052 | 775 |
| Files: ignored key | 526 | 273 | 48% | 683 | 382 |
| Files: pointer in unused corner | 528 | 277 | 48% | 687 | 388 |
| Files: change selection | 695 | 437 | 37% | 875 | 620 |
| Forms: ignored key | 261 | 184 | 30% | 358 | 286 |
| Forms: pointer in unused corner | 260 | 177 | 32% | 355 | 250 |
| Forms: move focus with Tab/Shift-Tab | 556 | 480 | 14% | 726 | 631 |
| Forms: type/backspace in Service name | 507 | 431 | 15% | 664 | 570 |

The two additional Tab controls in dashboard/files have no focus change in
these initial screens; their costs fall 27%/48%. They are idle-input controls,
not claims about faster focus movement. All 11 cases and p99 values are in the
[raw interaction CSV](evidence/2026-09-06-core-input-interactions.csv).
Most p99 values also improve, but forms/ignored-key rises from 438 to 470 us;
shared-host tail noise is not presented as a universal latency improvement.

The probe uses the real `runApp`, remote driver, dispatcher, frame scheduler,
frame loop and semantic wire encoder. Only the peer transport is in memory.
The timing starts at peer enqueue and ends on the first event-loop timer turn
after `onEvent`, after the frame and semantic microtasks drain. Snapshot
decoding, normalization and checksumming happen outside the measured window.
This measures runtime processing including scheduling, not network latency,
browser paint or physical input-to-display latency.

Top-level animation tickers are muted through `TickerMode`; TextInput's
separate caret timer remains active. Each forms idle case produces one extra
visual frame and typing produces two extra visual frames per 1,000 inputs.
Selection, typing and forms focus changes each produce 1,000 semantic updates;
idle cases produce none. A lack of output still incurs the full refresh and is
therefore a useful control for this optimization.

All six processes produce identical semantic fingerprints for each case.
Only runtime OverlayEntry/UniqueKey identity hashes and the dashboard's
wall-clock text are normalized. Full positional paths, labels, values, bounds,
focus, state and actions remain in the comparison; inspection omits action
lease nonce values. The probe also asserts that every typing step reaches the
named field and that every selection/focus/typing step changes the snapshot.
These fixtures use ordinary apps and short input; no document implementation
or large-document workload was optimized.

## Controls, lifetime and review

The existing core lifecycle benchmark was repeated in three alternating AOT
pairs per surface, 300 measured iterations per case. All 48 control-tree text
fingerprints matched; the five sample mounts have no fingerprint. Across 53
cases, the largest median increase was 2.3% (agent mount, 172 to 176 us).
Structured 64-row unkeyed controls improve by 42% for one label (365 to 212 us),
17% for all labels (886 to 737 us), and 12% for subtree replacement
(1,260 to 1,104 us). These controls establish that the input win is not bought
with a material regression elsewhere in the measured framework paths.

The teardown probe again reports 4,192 bytes in 129 Fleury-package instances,
with the exact same class inventory after warmup and three further lifecycle
cycles. It retains no mounted element/render trees. This is a bounded teardown
check, excluding SDK containers, allocation rate and total process RAM; it
does not establish a memory reduction or qualify every live-session lifecycle.

The change was reviewed before retention for keyed/unkeyed paths, escaped key
segments, transparent GlobalKeys, keyed-scope reparenting, snapshot immutability,
nested collection and exception cleanup. New tests compare snapshot identities
with the original live-walk algorithm and verify reparenting across keyed
scopes. All 169 focused semantic/wire/freshness regressions and all eight fast
performance gates passed. The browser client was regenerated: its JavaScript
bytes are unchanged; only the source fingerprint changes. Full contributor and
exact-head CI qualification are recorded in the PR.

Further reduction of input-triggered full refreshes would require a complete
semantic invalidation contract for custom and built-in contributors. That is
a larger correctness-sensitive change, not a justified shortcut in this pass.
Active-session heap under navigation and slow-peer pressure remains a separate
measurement target; the teardown evidence does not exhaust that area.

## Reproduction

From `profiling`, compile `bin/core_input_probe.dart` with Dart 3.12.2 using
`dart compile exe`, then run the executable with `1000`. Use this exact harness
on both revisions, alternating baseline/candidate, candidate/baseline,
baseline/candidate. Viewport is 120x40 on macOS arm64. Run one benchmark process
at a time without concurrent tests or compilation. The host was shared, not
an isolated performance lab.

The [manifest](evidence/2026-09-06-core-input.json) pins production revisions,
source/harness and executable hashes, raw CSVs and lifetime evidence. The
existing lifecycle probe uses `300 terminal` / `300 structured`; the lifetime
probe uses `dart --deterministic --enable-vm-service=0
--disable-service-auth-codes bin/core_lifetime_probe.dart`. No gate baseline or
tolerance was changed.
