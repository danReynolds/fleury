# Avoid rebuilding a list for its own completed viewport metrics

When a list scrolls or follows appended output, it publishes viewport metrics
after the frame. Its owning `ListView` also receives that notification and used
to call `setState`, scheduling another build and output plan for the viewport it
just rendered. Application listeners still need the metrics to update counters
and other surrounding UI.

## Implementation

The controller keeps a private view revision. Commands and explicit notifications
advance it; a notification of completed viewport metrics does not. The owning
list remembers the last revision it handled and skips an unchanged revision.

Metric delivery still calls the virtual `notifyListeners` method, preserving
subclass observation. The metric marker is consumed before listeners run, so
commands and explicit refreshes from those listeners advance the revision. The
marker is cleared on return even if a subclass suppresses delivery or throws.
Attaching another controller initializes the list's remembered revision from that
controller. There is no new public API or caller-managed invalidation token.

The regression suite checks that metrics reach ordinary listeners and subclass
overrides without scheduling a second build. It also exercises commands and
refreshes during delivery, both listener registration orders, commands before
and after `super` in an override, and recovery after suppressed metric delivery.
The redundant-build test fails on baseline; the subclass-observation test fails
on the original prototype that bypassed overrides with `super.notifyListeners`.

## Measurement

The final implementation was compared against
`1f967547` on Dart 3.12.2. Both AOT binaries used the same frozen fixture and
dependencies. Five fresh process pairs alternated which side ran first; builds
and tests were kept outside the measurement period.

Each six-second measured window contained 240 edits, 600 log appends, and 24
resizes. The fixture uses `runApp`, `RemoteTerminalDriver`, and an in-process peer
that encodes, decodes, and applies wire plans to a cell buffer. It verifies final
input, semantics, log tail, and no continuing output after the workload stops.
It does not measure a physical terminal, browser display, or network transport.

| Pair | Baseline plans | Changed plans | Baseline process CPU (s) | Changed process CPU (s) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1,480 | 864 | 1.635 | 1.582 |
| 2 | 1,480 | 864 | 1.504 | 1.422 |
| 3 | 1,480 | 864 | 1.625 | 1.628 |
| 4 | 1,485 | 864 | 1.483 | 1.678 |
| 5 | 1,478 | 864 | 1.360 | 2.171 |

All ten runs passed: **41.5–41.8% fewer output plans**. Two additional two-second
blocked-output runs (one per side) also passed, with 80 edits, 200 appends, eight
resizes, and ten artificial stall windows each.

CPU is user+system time for the entire process, including startup, warmup, peer
decoding, and teardown. Other work loaded the host; CPU results were mixed and
do not establish a reduction. An earlier prototype experiment showed a median
9.4% CPU reduction, but that number is not a demonstrated gain for this final
implementation. The reliable result here is removal of redundant work, covered
by deterministic regression tests, not a latency or CPU threshold.

Local raw receipts and hashes are retained in
`/tmp/fleury-list-notification-final/` on the investigation machine. They are
not published benchmark artifacts. The deterministic test is reproducible with:

```sh
cd packages/fleury
FLEURY_VERIFY_REPAINT_CACHE=1 dart test test/widgets/list_view_metrics_rebuild_test.dart
```
