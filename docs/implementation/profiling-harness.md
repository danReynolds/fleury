# TUI Profiling Harness

**Status:** Core built + proven (2026-06-04); peer drivers = next phase
**Goal:** Know where fleury stands vs peer TUIs on good axes — band each as
**way-off / ballpark / competitive / leading** — so arch decisions are driven by
measurement, not belief. Per the frontier re-derivation, the aim is *credible
ballpark + bottleneck discovery*, NOT winning a perf race (OpenTUI/Bubble Tea
own raw perf). Code lives in `profiling/`.

## Why this is fair across languages

The trap the old one-shot peer fixtures fell into: comparing *internal CPU
timing* across Dart/Rust/Go/Python/Node — apples-to-oranges (different runtimes,
harness boundaries, what's-counted). This harness instead measures the **output
artifact on the wire**, which is language-agnostic, and runs every framework's
stream through the **same** `AnsiByteBreakdown` categorizer. A framework can't
hide behind its language; the bytes are the bytes.

## Architecture

1. **Capture** (`profiling/capture_pty.py`) — runs ANY framework's scenario app
   under a real pseudo-terminal (so it renders normally) and captures every
   output byte + per-read timestamps. Uses `pty.fork`, so it works even from a
   non-interactive shell (macOS `script` chokes on socket stdin). Language-
   agnostic by construction.
2. **Analyze** (`profiling/analyze.dart`) — runs each capture through
   `AnsiByteBreakdown` and reports the axes; with multiple labelled captures of
   the SAME scenario, bands each vs the best.

Proven end-to-end: capturing an "efficient" (relative moves + sync) vs
"wasteful" (absolute moves + redundant SGR) emitter bands them leading vs
ballpark and shows the byte split that explains why.

## Axes (output-artifact; lower is better)

| Axis | Meaning | Cross-language fair? |
| --- | --- | --- |
| bytes on the wire (total) | output efficiency | ✅ exact |
| bytes / frame | per-update cost | ✅ exact |
| frames emitted | round-trips (the WAN-SSH lever) | ✅ exact |
| control overhead % | non-content bytes | ✅ exact |
| time-to-first-byte | startup proxy | ⚠️ Tier B (pty timing) |

Deliberately **not** cross-compared: internal CPU phase timing (apples-to-
oranges — that's for our *introspective* profiling only). **Runtime-confounded,
report with caveat:** RSS/memory (Go/Rust binary vs Dart-AOT vs Node vs Python
have wildly different floors), full startup time.

## Measurement tiers

- **Tier A — bytes & frames:** built + proven. Most credible cross-language axis,
  the one we likely lead (cursor compression + sync). fleury's bytes already come
  exactly from the byte-budget harness (`renderDiff` output == wire bytes).
- **Tier B — output timing/throughput:** pty read timestamps give ttfb +
  inter-burst timing. Usable; coarse.
- **Tier C — real input→paint latency, RSS, startup across terminals + SSH:**
  needs real hardware (this env is non-TTY) and cross-machine runs. Pairs with
  `byte-latency-handoff.md`.

## Banding

Vs the best capture on each (lower-better) axis: **leading** ≤1.15×,
**competitive** ≤1.5×, **ballpark** ≤3×, else **way-off**. Bands are per-axis —
the expected honest result is mixed ("leading on bytes/frames, ballpark on
startup, trailing on raw throughput").

## Adding a framework (driver protocol) — the next phase

Each framework needs a **self-driving scenario app**: renders a shared scenario
(e.g. "append 200 log lines to a tailing view", "scroll a 10k-row table by 1,
×100", "stream 500 markdown chunks") and exits (or runs a fixed loop the harness
times out). Then:

```sh
python3 profiling/capture_pty.py --out caps/<fw>-<scenario> -- <run command>
dart run profiling/analyze.dart fleury=caps/fleury-<s> nocterm=caps/nocterm-<s> ...
```

Toolchain status here: dart ✅ · go ✅ · cargo ✅ · python3 ✅ · node ✅ ·
**bun ✗ (OpenTUI deferred to a bun host)**.

Status: **capture + analyze + banding proven.** Remaining: write the per-
framework self-driving scenario apps (fleury first, then peers), define the
shared scenario set (reuse SB.* shapes), and collect Tier-C numbers on hardware.
