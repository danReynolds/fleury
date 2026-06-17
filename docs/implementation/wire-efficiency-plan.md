# Wire Efficiency & Startup Plan (post native-stack peer snapshot)

Status: COMPLETE 2026-06-11 (same day; all phases executed, measured verdicts in the execution log and peer-scorecards final snapshot). Originally proposed from the first all-native wire captures
(`profiling/caps/2026-06-11-native-*`). Companion to
`peer-scorecards.md` and the completed
`web-industry-leading-plan.md`.

## What the native snapshot actually says

Fleury already leads bytes/frame/FPS suite-wide and TTFB against every
managed-runtime peer. The remaining gaps decompose into exactly four
actionable targets and one un-actionable floor:

1. **Cursor bytes dominate fleury's overhead everywhere it trails.**
   SB.9: fleury `content 3397 / sgr 4 / cursor 1616 / sync 252` vs
   bubbletea `3087 / 17 / 237 / 44` — content is at parity; cursor is
   6.8x and sync 5.7x. SB.6's dominant overhead is likewise
   `cursor 24.0 KiB`. This is ONE encoder problem, not many.
2. **SB.4 bytes 1.17x** best — close; likely the same cursor story.
3. **TTFB vs ratatui (30.7 vs 14.2ms on SB.6)** — partly Dart AOT boot
   floor, partly fleury-attributable startup work. The runtime markers
   (`runTui.entry` → `terminal.enter` → `root.mounted` →
   `first.render.*`) exist precisely to split this; nobody has read them
   against the native runs yet.
4. **RSS ~20MiB / CPU 3-4%** vs ratatui 2.2MiB / 1% — dominated by the
   Dart-vs-Rust runtime floor, but the fleury-attributable share above
   the bare AOT floor has never been measured.
5. **Methodology skew:** the position rollup counts RSS/CPU in its
   severe set, so any scenario racing ratatui is labeled "catch up"
   regardless of fleury-controllable work — while the scoreboard header
   itself calls those axes "runtime-confounded". SB.9 also reports
   `needs data` despite 3 clean runs (rollup bug or variance gate).

## Definition of done

- W-1 **Cursor/sync overhead**: SB.9 cursor bytes ≤ 2x best peer;
  SB.6 cursor share ≤ 10% of total bytes; no scenario worse than
  `competitive` on the overhead axis. Byte-equivalence oracle stays
  green (the 300-frame diff-reproduces-next suite).
- W-2 **SB.4 bytes** ≤ 1.10x best peer.
- W-3 **Startup**: TTFB decomposed via runtime markers on native runs;
  fleury-attributable span (entry → first render end) ≤ 5ms; total TTFB
  ≤ 1.5x ratatui on SB.6/SB.12 (≈ ≤ 21ms), i.e. `competitive`, from
  `WAY OFF`.
- W-4 **RSS**: bare `dart compile exe` hello-world floor measured and
  documented; fleury-attributable delta ≤ 5MiB over it; ≤ 2x the best
  GC-runtime peer (Go fixtures ~8-9MiB).
- W-5 **Evidence completeness**: all 12 wire scenarios captured native
  (3 runs), zero `needs data` rows, SB.10 unblocked (demo-journey fix),
  one canonical native scoreboard replacing the pooled
  `profiling/caps/scoreboard.md`.
- W-6 **Methodology (Dan's call)**: position rollup either bands RSS/CPU
  against the best same-runtime-class peer or annotates the runtime
  floor — so the label measures fleury-controllable work. Public-claims
  language in `peer-scorecards.md` updated to match whatever is decided.

## Phases

### A — Complete the native evidence base (~1 session)

Run sb1, sb2, sb3, sb5, sb7, sb8, sb11 natively (3 runs,
`GOARCH=arm64`); fix the SB.9 `needs data` rollup; fold in SB.10 once
the demo-journey chip lands; regenerate the canonical scoreboard.
SB.1 (counter/startup) and SB.2/SB.5 (P0/P1 priorities) may add targets;
the plan absorbs them at phase boundaries.

### B — Cursor & sync byte encoder, round 2 (~1-2 sessions, core)

Diagnose from the captured `.bin` transcripts (real emitted escapes,
histogram by kind), then attack in order of expected yield:

1. Sparse-update cursor moves: SB.9-style scenarios move the cursor to
   scattered cells; evaluate cheaper anchoring (row-relative chains,
   gap write-through thresholds) against the actual transcripts.
2. Revisit the styled-gap write-through variant dropped during the
   merge (kept plain-only then for lack of byte-budget evidence; the
   native splits are that evidence — adopt only if transcripts show
   net wins and the equivalence oracle agrees).
3. Sync-wrap overhead: BSU/ESU per frame is ~8 bytes; for one-cell
   diffs that is a third of the frame. Skip the wrapper under a
   threshold (the terminal contract allows unsynchronized tiny diffs;
   verify no tearing assumptions in tests).
4. Re-run SB.4/SB.6/SB.9 after each change; native web captures as
   regression guard (shared renderer).

### C — Startup decomposition & diet (~1 session)

1. Read the runtime markers from the native SB.6/SB.12 fleury captures;
   split TTFB into VM boot / terminal enter / mount / first render.
2. Benchmark the bare AOT floor (hello-world `dart compile exe` under
   the same PTY harness) — the un-actionable share, documented.
3. Defer fleury-attributable startup work that isn't needed before the
   first frame (candidate suspects: capability detection probes, log
   buffer setup, debug-shell wiring — confirm from markers, don't
   guess).
4. Exit on W-3; if the VM floor alone exceeds 1.5x ratatui, document
   the floor and scope the claim to managed-runtime peers (Dan
   decision).

### D — RSS audit (~1 session, measure-first)

AOT hello-world RSS under the harness vs fleury fixture RSS → the
attributable delta; heap-snapshot the fixture (Dart VM service) for the
top retained owners; lazy-init what the first frame doesn't need.
Honest exit (W-4) — this phase chases fleury's share, not Rust's
number.

### E — Methodology + claims (~0.5 session, includes Dan decision W-6)

Implement whichever rollup treatment Dan picks; refresh
`peer-scorecards.md` standings and the public-claim phrasing
("leads wire efficiency suite-wide; ballpark-of-systems-languages on
footprint with a documented runtime floor").

## Sequencing

A first (evidence may re-rank B/C/D). B and C are independent; run B
then C (B touches the shared renderer — keep the equivalence oracle
between them). D measure-first, may shrink to documentation. E last.

Estimated total: 4-6 working sessions.

## Risks

- Cursor-encoding churn is the highest-regression-risk area in the
  repo; the byte-equivalence oracle and the per-scenario transcripts
  are the safety net. Every change lands behind a fresh capture
  comparison.
- The TTFB and RSS floors may dominate their gaps; both phases have
  documented-floor exits rather than unbounded optimization.
- PTY wire runs are timing-sensitive: all captures on an idle machine,
  3 runs minimum, medians only — variance discipline learned from the
  web side applies.
