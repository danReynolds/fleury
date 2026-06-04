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

1. **Capture** (`profiling/capture_pty.dart`) — all-Dart, runs ANY framework's
   scenario app under a real pseudo-terminal (so it renders normally) and
   captures every output byte + per-read timestamps. Pure `dart:ffi`
   (openpty + posix_spawnp + non-blocking read loop); no Python, no Flutter, no
   third-party pty dep. POSIX (macOS / Linux). `fork()` in the VM is unsafe, so
   it uses posix_spawnp. Language-agnostic by construction.
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
dart run profiling/capture_pty.dart --out caps/<fw>-<scenario> -- <run command>
dart run profiling/analyze.dart fleury=caps/fleury-<s> nocterm=caps/nocterm-<s> ...
```

Toolchain status here: dart ✅ · go ✅ · cargo ✅ · python3 ✅ · node ✅ ·
**bun ✗ (OpenTUI deferred to a bun host)**.

## Are these the right axes? (research note, 2026-06-04)

There is **no established cross-framework TUI benchmark standard** — only ad-hoc
blog comparisons and per-framework micro-benches. Our axes are *reasoned* from
the byte→latency analysis (perceived-latency drivers) + cross-language fairness,
and they align with the one credible published methodology
([Rezi benchmarks](https://www.mintlify.com/RtlZeroMemory/Rezi/architecture/benchmarks)):
PTY-mode benchmarks that include the terminal write path (= our bytes-on-wire),
and "strict-ui vs full-ui" scenarios to avoid biasing layout-engine frameworks
against raw-buffer libs.

Formalization to do before publishing comparisons:
- **Add the axes the field actually leads with:** memory (RSS) and CPU under
  sustained load, and sustained FPS. Report RSS *with the caveat* that it's
  runtime-confounded (Go/Rust binary vs Dart-AOT vs Node vs Python floors
  differ), rather than omitting it — the field reports it.
- **Adopt the strict-vs-full-UI framing** so layout-engine vs raw-buffer
  comparisons are honest.
- Run Tier-C on bare metal with replicates (virtualized hosts add jitter).

Status: **capture + analyze + banding proven, all-Dart.** Remaining: write the per-
framework self-driving scenario apps (fleury first, then peers), define the
shared scenario set (reuse SB.* shapes), and collect Tier-C numbers on hardware.
