# TUI Profiling Harness

**Status:** Core built + proven and axis set formalized (2026-06-04); the
current primary peer matrix is runnable for
SB.1/SB.2/SB.3/SB.4/SB.5/SB.6/SB.7/SB.8/SB.9/SB.10/SB.11/SB.12
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
   captures every output byte + per-read timestamps + child RSS/CPU metadata.
   Pure `dart:ffi` (openpty + posix_spawnp + non-blocking read loop); no Python,
   no Flutter, no third-party pty dep. POSIX (macOS / Linux). `fork()` in the VM
   is unsafe, so it uses posix_spawnp. Language-agnostic by construction.
2. **Analyze** (`profiling/analyze.dart`) — runs each capture through
   `AnsiByteBreakdown` and reports the axes; with multiple labelled captures of
   the SAME scenario, bands each vs the best.

Proven end-to-end: capturing an "efficient" (relative moves + sync) vs
"wasteful" (absolute moves + redundant SGR) emitter bands them leading vs
ballpark and shows the byte split that explains why.

## Axes

| Axis | Direction | Meaning | Cross-language fair? |
| --- | --- | --- | --- |
| bytes on the wire (total) | lower | output efficiency | ✅ exact |
| bytes / frame | lower | per-update cost | ✅ exact |
| frames emitted | lower | round-trips (the WAN-SSH lever) | ✅ exact for CLI wire runs via scenario logical frame count; sync markers or PTY-read proxy otherwise |
| control overhead % | lower | non-content bytes | ✅ exact |
| time-to-first-byte | lower | startup proxy | ⚠️ Tier B (pty timing) |
| RSS max | lower | memory footprint | ⚠️ runtime-confounded |
| CPU load during capture | lower | CPU under sustained scenario load | ⚠️ runtime-confounded |
| sustained frame rate | higher | delivered update cadence | ⚠️ Tier B unless run on hardware |

Deliberately **not** cross-compared: internal CPU phase timing (apples-to-
oranges — that's for our *introspective* profiling only). RSS and CPU are
reported because the field reports them, but every publication must carry the
runtime-floor caveat: Go/Rust binary vs Dart-AOT vs Node vs Python have wildly
different memory/runtime baselines.

## Strict UI vs Full UI

Each capture declares `--ui-mode strict-ui|full-ui`.

- **strict-ui:** the smallest faithful implementation of the scenario, intended
  to isolate write-path and terminal-output efficiency. Raw-buffer libraries and
  layout engines can both compete here, but layout features not needed by the
  scenario stay out.
- **full-ui:** idiomatic framework implementation using the framework's normal
  layout, app shell, input, widgets, styling, and state machinery. This is the
  product-facing comparison, but it should not be mixed with strict-ui captures.

Analyzer banding is only meaningful within the same scenario and UI mode; mixed
mode captures are flagged. CLI wire runs pass a scenario logical frame count
(`steps + 1`) into capture metadata, so peer FPS/frames are not derived from
PTY read bursts. Direct capture users should pass `--frame-count=N` when they
know it; otherwise the analyzer falls back to synchronized-output markers or
PTY reads and flags mixed frame sources.

## Measurement tiers

- **Tier A — bytes & frames:** built + proven. Most credible cross-language axis,
  the one we likely lead (cursor compression + sync). fleury's bytes already come
  exactly from the byte-budget harness (`renderDiff` output == wire bytes).
- **Tier B — output timing/throughput:** pty read timestamps give ttfb +
  inter-burst timing. Usable; coarse.
- **Tier C — real input→paint latency, RSS, startup across terminals + SSH:**
  needs bare-metal hardware replicates (this env is non-TTY; virtualized hosts
  add jitter) and cross-machine runs. Pairs with `byte-latency-handoff.md`.

## Banding

Vs the best capture on each axis: **leading** ≤1.15×, **competitive** ≤1.5×,
**ballpark** ≤3×, else **way-off**. Lower-is-better axes compare value/best;
FPS compares best/value. Bands are per-axis — the expected honest result is
mixed ("leading on bytes/frames, ballpark on startup, trailing on raw
throughput").

## Adding a framework (driver protocol) — the next phase

Each framework needs a **self-driving scenario app**: renders a shared scenario
(e.g. "append 200 log lines to a tailing view", "scroll a 10k-row table by 1,
×100", "stream 500 markdown chunks") and exits (or runs a fixed loop the harness
times out). Then:

```sh
dart run profiling/capture_pty.dart --out caps/<fw>-<scenario> --ui-mode strict-ui --frame-count N -- <run command>
dart run profiling/analyze.dart fleury=caps/fleury-<s> nocterm=caps/nocterm-<s> ...
```

Toolchain status here: dart yes · go yes · cargo yes · python3 yes · node yes
· fixture-local bun yes via `npm ci` for OpenTUI.

## Are these the right axes? (research note, 2026-06-04)

There is **no established cross-framework TUI benchmark standard** — only ad-hoc
blog comparisons and per-framework micro-benches. Our axes are *reasoned* from
the byte→latency analysis (perceived-latency drivers) + cross-language fairness,
and they align with the one credible published methodology
([Rezi benchmarks](https://www.mintlify.com/RtlZeroMemory/Rezi/architecture/benchmarks)):
PTY-mode benchmarks that include the terminal write path (= our bytes-on-wire),
and "strict-ui vs full-ui" scenarios to avoid biasing layout-engine frameworks
against raw-buffer libs.

Formalization applied before publishing comparisons:
- **Field-standard axes added:** memory (RSS), CPU under sustained load, and
  sustained FPS are now part of capture/analyze output. RSS/CPU remain
  runtime-confounded and must be presented with that caveat.
- **Strict-vs-full-UI framing adopted:** captures carry `strict-ui` or `full-ui`;
  analyzer warns on mixed-mode comparisons.
- **Tier-C rule:** publish hardware numbers only after bare-metal replicates.

Status: **capture + analyze + banding proven, all-Dart, with the final axis
set in place.** The current primary scenario matrix now has self-driving
real-PTY wire apps through the `fleury benchmark wire ...` command surface,
including dynamic PTY resize driving for SB.7. Remaining: collect Tier-C
numbers on hardware before publishing peer claims.

## Current Wire Coverage (2026-06-08)

These commands build Fleury plus the configured primary peer fixtures, run
them under the same PTY capture harness, and analyze the captures together.
Bare scenario IDs run every configured peer for that scenario. Use
`--peer=<id>`, `--peers=a,b`, or a concrete ID such as `sb6-ratatui` to narrow
a run. Use `fleury benchmark wire <scenario> --list-peers` to inspect the
scenario's configured peers before running it. Use `--runs=3` or more for
decision signal; tiny `--rows`/`--steps` overrides are smoke tests only.
Use `--debug-capture` when a Fleury-side `DebugCaptureSnapshot` is needed for
dirty span, layout, repaint-boundary, or invalidation diagnostics; the JSON is
written beside the Fleury capture and is diagnostic-only for timing.
Use `--runtime-markers` when Fleury-side startup/render milestones are needed
to decompose raw TTFB; the marker sidecar is folded into the capture JSON and
scoreboard without changing PTY bytes. The scoreboard reports both raw marker
offsets and framework-over-runtime deltas.
Use local `--profile-memory` runs for Fleury-only RSS phase checks when a
scenario needs internal attribution, for example
`fleury benchmark local SB.6 --warmup=1 --iterations=3 --profile-memory --json --save=profiling/caps/sb6-local-memory.json`.
Relative `--save` paths are resolved from the repository root by the wrapper.

| Priority | Scenario | Primary peers | Commands |
| --- | --- | --- | --- |
| P0 | SB.4 LogRegion | Bubble Tea, Textual, OpenTUI | `fleury benchmark wire sb4 --runs=3` |
| P0 | SB.5 Streaming Markdown | Bubble Tea, Textual, Ink | `fleury benchmark wire sb5 --runs=3` |
| P1 | SB.2 Text Editing | Bubble Tea, Textual, Ink | `fleury benchmark wire sb2 --runs=3` |
| P1 | SB.3 DataTable | Textual, Ratatui, OpenTUI | `fleury benchmark wire sb3 --runs=3` |
| P2 | SB.1 Counter/Startup | Bubble Tea, Textual, Ink | `fleury benchmark wire sb1 --runs=3` |
| P2 | SB.6 Dashboard Updates | Bubble Tea, Ratatui, OpenTUI | `fleury benchmark wire sb6 --runs=3` |
| P2 | SB.12 Layout Dirtiness Cache | Nocterm, Ratatui, OpenTUI | `fleury benchmark wire sb12 --runs=3` |
| P3 | SB.8 Overlay/Palette Churn | Textual, Ink, Bubble Tea | `fleury benchmark wire sb8 --runs=3` |
| P3 | SB.9 Subprocess/Untrusted Output | Textual, Bubble Tea, OpenTUI | `fleury benchmark wire sb9 --runs=3` |
| P3 | SB.10 Proof-App Journey | Textual, Bubble Tea, Ink | `fleury benchmark wire sb10 --runs=3` |
| P4 | SB.7 Resize Storm | Textual, Ratatui, OpenTUI | `fleury benchmark wire sb7 --runs=3` |
| P4 | SB.11 TreeTable/filter/copy | Textual, Ratatui, OpenTUI | `fleury benchmark wire sb11 --runs=3` |

## First Reduced Reading (SB.4 full-ui, 2026-06-04)

Not publishable yet: local PTY runs, reduced data size, no Tier-C hardware, and
mixed frame sources (fleury synchronized-output markers vs peer PTY read
bursts). It is still the first real wire-level
fleury-vs-peer signal.

Scenario:
- SB.4 LogRegion tailing, `full-ui`
- 120x32 PTY
- `rows=200`, `append=10`, `steps=5`, `interval-ms=100`
- Fleury captured from an AOT executable built from
  `profiling/bin/fleury_sb4_wire.dart`
- Bubble Tea captured from a Go executable built from
  `peer-fixtures/bubbletea/sb4_log_region --wire`
- Textual captured from `peer-fixtures/textual/sb4_log_region --wire`

Analyzer result:

| Axis | fleury before renderer scroll fast path | fleury after renderer scroll fast path | Bubble Tea | Current band |
| --- | ---: | ---: | ---: | --- |
| bytes on the wire | 8834 B | 2983 B | 2411 B | fleury competitive |
| bytes / frame | 1472 | 497 | 268 | fleury ballpark |
| frames emitted | 6 sync frames | 6 sync frames | 9 PTY reads | fleury leading, caveated |
| control overhead | 37% | 19% | 5% | fleury WAY OFF |
| RSS max | ~19.5 MiB | ~19.5 MiB | ~9.1-9.5 MiB | fleury ballpark, runtime-confounded |
| CPU load | ~4% | ~5-6% | ~7-9% | fleury leading/competitive |
| sustained frame rate | ~11 fps warm | ~11 fps warm | ~14 fps warm | fleury competitive |

Byte split:
- fleury before: `content/sgr/cursor/sync/other = 5565/484/1207/172/1406`
- fleury after: `2430/120/228/172/33`
- Bubble Tea: `2288/17/10/44/52`

Additional Textual result, median over
`fleury benchmark wire sb4-textual --runs=3`:

| Axis | Fleury | Textual | Current band |
| --- | ---: | ---: | --- |
| bytes on the wire | 2983 B | 131555 B | fleury leading |
| bytes / frame | 497 | 907 | fleury leading |
| frames emitted | 6 sync frames | 145 PTY reads | fleury leading, caveated |
| control overhead | 19% | 75% | fleury leading |
| time-to-first-byte | 19.9 ms warm median | 127.5 ms | fleury leading; first run had cold-start outliers |
| RSS max | 19.5 MiB | 38.8 MiB | fleury leading, runtime-confounded |
| CPU load | 5% | 24% | fleury leading, runtime-confounded |
| sustained frame rate | 11.1 fps | 162.6 fps | Textual leading, frame-source caveated |

Textual byte split:
`content/sgr/cursor/sync/other = 32991/94510/3827/198/29`.

Immediate interpretation: the first run correctly exposed a renderer strategy
gap. Bubble Tea's viewport scrolls the terminal and writes newly exposed lines;
fleury's renderer was patching the shifted grid cell-by-cell. Adding a
whole-screen scroll-up fast path for beneficial row-shift diffs moved Fleury
from WAY OFF to competitive on total bytes for this reduced SB.4 wire case.

Remaining signal: Fleury still carries higher control overhead than the current
Bubble Tea wire view, mostly because it emits synchronized-output markers and
styled LogRegion rows while Bubble Tea is mostly plain text. Against Textual's
full-ui Log widget, Fleury is far ahead on bytes and runtime load. Next
decision-grade step: make peer frame sources exact and add the OpenTUI SB.4
wire app before treating frame/FPS bands as framework-level truth.

## Second Reduced Reading (SB.5 full-ui, 2026-06-04)

Not publishable yet: local PTY run only, reduced stream size, mixed frame
sources, and a full-ui parity caveat. Bubble Tea uses a Bubble Tea/Bubbles app
with Glamour full-document rendering plus fixture-owned sanitization/link
policy/copy metadata. Fleury uses `MarkdownView` with its semantic document
model and widget-level copy/link handling. This is useful product-facing signal,
not a formal ecosystem claim.

Scenario:
- SB.5 Streaming Markdown, `full-ui`
- 120x32 PTY
- `rows=200`, `steps=16`, `interval-ms=50`
- Fleury captured from an AOT executable built from
  `profiling/bin/fleury_sb5_wire.dart`
- Bubble Tea captured from a Go executable built from
  `peer-fixtures/bubbletea/sb5_streaming_markdown --wire`
- Command: `fleury benchmark wire sb5-bubbletea --runs=3`

Median analyzer result over 3 paired local runs:

| Axis | Fleury | Bubble Tea | Current band |
| --- | ---: | ---: | --- |
| bytes on the wire | 2455 B | 6789 B | fleury leading |
| bytes / frame | 246 | 428 | fleury leading |
| frames emitted | 10 sync frames | 16 PTY reads | fleury leading, caveated |
| control overhead | 39% | 2% | fleury WAY OFF |
| time-to-first-byte | 16.5 ms | 66.7 ms | fleury leading; first run had cold-start outliers |
| RSS max | 23.3 MiB | 26.0 MiB | fleury leading, runtime-confounded |
| CPU load | 5% | 61% | fleury leading, runtime-confounded |
| sustained frame rate | 11.9 fps | 9.4 fps | fleury leading/competitive |

Byte split:
- Fleury: `content/sgr/cursor/sync/other = 1503/492/184/236/40`
- Bubble Tea median: `6633/17/28/44/66`

Additional Textual result, median over
`fleury benchmark wire sb5-textual --runs=3`:

| Axis | Fleury | Textual | Current band |
| --- | ---: | ---: | --- |
| bytes on the wire | 2455 B | 279726 B | fleury leading |
| bytes / frame | 246 | 926 | fleury leading |
| frames emitted | 10 sync frames | 302 PTY reads | fleury leading, caveated |
| control overhead | 39% | 56% | fleury leading |
| time-to-first-byte | 20.5 ms warm median | 163.2 ms | fleury leading; first run had cold-start outliers |
| RSS max | 23.4 MiB | 56.2 MiB | fleury leading, runtime-confounded |
| CPU load | 5% | 42% | fleury leading, runtime-confounded |
| sustained frame rate | 11.8 fps | 176.7 fps | Textual leading, frame-source caveated |

Textual byte split:
`content/sgr/cursor/sync/other = 123260/149028/7211/198/29`.

Immediate interpretation: SB.5 is a strong sign that Fleury is not generally
behind on the major decision axes. For this Markdown streaming shape, Fleury
writes far fewer bytes and uses less CPU than both the Bubble Tea/Bubbles/
Glamour fixture and the Textual Markdown fixture. The same recurring issue
remains in the Bubble Tea comparison: Fleury's non-content byte share is high
because styling, cursor movement, and synchronized-output markers dominate
small visible updates. That is the next renderer optimization target if we want
the benchmark story to move from competitive to cleaner peer-leading.
