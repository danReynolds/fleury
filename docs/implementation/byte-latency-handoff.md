# Byte → Latency: Real-Terminal Confirmation Handoff

**Status:** External-evidence handoff
**Date:** 2026-06-04
**Purpose:** The byte-budget harness and the transport latency *estimator* model
the bytes → latency mapping, but a model is not hardware. This is the handoff for
the one step a non-TTY environment cannot do: confirming the mapping on real
terminals and over SSH.

## What already exists (built + validated locally)

- **Byte categorizer** — `AnsiByteBreakdown` / `CountingAnsiSink`
  (`packages/fleury/lib/src/rendering/ansi_byte_budget.dart`), UTF-8
  bytes-on-the-wire split into content / sgr / cursor / sync / other. Unit
  tested.
- **Offline harness** — `packages/fleury_widgets/benchmark/byte_budget_benchmark.dart`
  drives representative scenarios through real widgets, reports per-frame byte
  budgets and **estimated** latency across transport profiles. Baseline:
  `packages/fleury_widgets/benchmark/results/byte-budget-2026-06-04.json`.
- **Transport estimator** — `TransportProfile` (`local`, `ssh-lan`, `ssh-wan`,
  `slow-9600`): `frameMs = fixedOverheadMs + 1000 * bytes / bytesPerSecond`.
- **Live telemetry hook** — set `FLEURY_BYTE_TELEMETRY=1` and any Fleury app
  wraps its real output sink (`CountingAnsiSink.aggregate` around the live
  driver sink) and prints a byte + estimated-latency summary to stderr on exit.

## What the model already tells us (and the nuance to confirm)

Estimated per-frame latency from the 2026-06-04 baseline:

| Scenario (avg update) | bytes | local | ssh-lan | ssh-wan | slow-9600 |
| --- | --: | --: | --: | --: | --: |
| Full scroll | 1024 | 0.1 | 0.7 | 41.0 | 858 |
| Color churn | 428 | 0.0 | 0.6 | 40.4 | 362 |
| Sparse dashboard | 41 | 0.0 | 0.5 | 40.0 | 39 |

The refined hypothesis to confirm on hardware:

- **On fast links (local, LAN SSH), per-frame byte size is not the latency
  bottleneck** — frames are sub-millisecond regardless. Cursor compression buys
  throughput/CPU, not perceived latency, here.
- **On WAN SSH, latency is RTT-dominated and flat (~40 ms) across frame sizes** —
  so the lever there is frame *count* (round trips), not frame *size*.
- **On bandwidth-constrained links, byte size dominates** — this is where the
  cursor-compression byte savings (scroll 1274 → 1024 B ≈ 210 ms on 9600 baud)
  convert directly to time.

## The capture step (needs real terminal hardware)

This environment is non-TTY (`TERM=dumb`), so it cannot produce these. On a real
machine, for each target terminal (macOS Terminal, iTerm2, Kitty, Ghostty,
Alacritty, WezTerm) and over SSH (LAN and WAN):

1. Run a Fleury app driving a known scenario (e.g. the proof app, or a scripted
   scroll/dashboard) with telemetry on:

   ```sh
   FLEURY_BYTE_TELEMETRY=1 dart run path/to/app.dart
   ```

   Record the printed `[fleury byte telemetry]` summary (frames, total bytes,
   category split, estimated latency).

2. Measure *actual* input→paint latency independently (e.g. screen-capture
   frame timing, or a terminal that timestamps DA/cursor reports), to compare
   against the estimator's prediction for the observed byte counts.

3. Calibrate the `TransportProfile` constants (`bytesPerSecond`,
   `fixedOverheadMs`) against the measured numbers, then re-run the offline
   harness so its estimates reflect reality.

## Acceptance

- Real-terminal telemetry collected for at least: one local terminal, LAN SSH,
  WAN SSH, and one bandwidth-constrained link.
- Measured latency vs. estimated latency agree within a stated tolerance, or the
  profiles are recalibrated until they do.
- The refined hypothesis (bytes matter on slow links; RTT/frame-count on fast
  ones) is confirmed or corrected with data.
