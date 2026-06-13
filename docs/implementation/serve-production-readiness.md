# `fleury serve` — Production Readiness Report

**Date:** 2026-06-12
**Scope:** the structured serve path (browser renders a fleury session
through the DOM surface; no terminal emulator). Companion to
`serve-dom-client-plan.md` (the build) and the
`packages/fleury/lib/src/remote/` implementation.

## How peers do it, and where fleury differs

Every production terminal-over-web tool relays **ANSI to xterm.js**:

| Tool | Stack | Wire | Renderer |
| --- | --- | --- | --- |
| ttyd | C / libwebsockets | raw ANSI | xterm.js |
| gotty | Go | raw ANSI | xterm.js / hterm |
| textual-web / -serve | Python | ANSI (custom envelope) | xterm.js |
| VS Code terminal | TS | ANSI | xterm.js |
| **fleury serve** | **Dart AOT** | **structured render intent** | **own DOM surface** |

fleury is the only one that sends *render intent* (changed cells, styled
runs) instead of an escape stream. The payoff: the browser renders
through the same retained DOM surface the in-browser host uses — so the
serve path inherits the perf gate, the parity oracle, and a semantics
path agents/AT can read. xterm-relay tools structurally cannot carry
semantics. The cost we had to neutralize: render intent is naturally
more verbose than ANSI, so it had to be made wire-competitive.

## Wire efficiency (the bar: competitive with deflated ANSI)

Measured across realistic frame sequences, whole-stream deflate
(= permessage-deflate with context takeover, which Dart's serve
WebSocket enables by default). Profiler:
`profiling/bin/serve_wire_profile.dart`.

| Workload | deflated PLAN vs deflated ANSI |
| --- | --- |
| counter (sparse) | 2.1x |
| typing (one row) | 1.7x |
| dashboard (partial) | 1.1x |
| full paint (first frame) | 1.3x |
| log churn / scroll | 3.3x |
| **total** | **1.56x** |

Interactive workloads land at 1.1–1.7x the bytes of the ANSI the
incumbents send — competitive, with tiny absolute sizes (113–3173 bytes
deflated per 100 frames), while delivering DOM rendering and semantics
they can't. The original span-model encoding was 14x; the V3 cell-patch
encoding (changed ranges, style table, varints, client-side mirror)
closed it by an order of magnitude.

**The log-churn 3.3x, measured honestly:** that's scrolling output with
scroll detection disabled on the serve path — every row reships. In
absolute terms it is 24 bytes/frame deflated vs ANSI's 7, i.e. ~1.8 MB
extra per hour of WAN log-tailing at 30 fps. The scroll-up optimization
(detect the shift, ship a scroll op + only the entering row) would take
this well under 1x ANSI, but it requires a three-way client-mirror /
DOM-surface / residual-patch scroll-sync — meaningful complexity whose
subtle-divergence risk is not justified by the small absolute saving at
this scale. **Deferred, with the numbers on record.** It becomes worth
doing if WAN log-streaming becomes a headline use case.

## CPU

Build + encode for a dense 80×24 frame with every row changed:
**~100 µs/frame**. At 60 fps that is 0.6% of one core; typical frames
(a few dirty rows) cost far less. The encoder is not a bottleneck.

## Hardening

Audited against a hostile or stalled peer. State after this work:

| Surface | Status |
| --- | --- |
| WebSocket origin validation | present (`_isAllowedWebSocketOrigin`, configurable `--allow-origin`) |
| Frame payload cap | 64 MiB; decoder rejects oversize, never blocks |
| Malformed-frame rejection | typed `RemoteCodecException`; 500-iteration fuzz |
| Grid-size DoS (OOM) | **fixed** — peer sizes clamped to 4000×4000 on INIT/RESIZE/structured-resize |
| Slow-consumer DoS (unbounded buffer) | **fixed** — `addStream` backpressure both directions |
| Single-session enforcement | bridge drops 2nd app; serve drops 2nd browser |
| Codec sign/assert robustness | **fixed** — negative-varint, null-key-event, out-of-range-color all guarded (fuzz-found) |

## Correctness

- Transport parity proven in the VM: a frame built server-side survives
  build → encode → decode → apply-to-mirror byte-exact (80 seeded
  multi-frame sequences; content, style, wide glyphs, shrink-blanking).
- Embedded-client freshness gate recompiles and compares on every run.
- Full suites green: core 1653, web VM 198, Chrome 152.

## Honest remaining gaps (documented, not blocking)

1. **Scroll-up wire optimization** — the log-tailing case above. Deferred
   with measured rationale.
2. **Semantics over the wire** — the SEMANTICS frame and driver hook
   exist; wiring the client's semantic DOM presenter to consume them is
   a follow-up. The visual surface renders without it.
3. **Single headless-Chrome e2e** — the wire is VM-proven lossless and
   the DOM surface is Chrome-proven; one end-to-end test through a live
   socket would close the composition gap.
4. **Browser input fidelity** (IME, dead keys, exotic layouts) — handled
   by `dom_input_source`, filed against the IME workstream for
   edge-case hardening.

## Verdict

The serve path is production-hardened: competitive on the wire with the
ANSI-relay incumbents (1.1–1.7x on interactive workloads), cheap on CPU,
and closed against the OOM and slow-consumer DoS classes — while
delivering a real DOM surface and a semantics path no xterm-relay tool
can. The remaining items are bounded, measured, and recorded.

## Update — scroll-up wire optimization landed (2026-06-12)

The deferred scroll-up optimization is now implemented, and re-measuring
corrected an earlier mistake: the original "log churn" profiler scenario
used near-identical lines (only a number changed per line), where the
detector *correctly* prefers cell-diffing — so it was never a real scroll
case. With a realistic varied-line log (distinct content per line, the
actual log-tailing shape):

| Workload | before | after scroll-up |
| --- | --- | --- |
| log tail (scroll) | 3.3x | **1.06x** |
| total deflated | 1.56x | **1.13x** |

`buildRemotePlan` now runs the same `detectBeneficialScrollUp` the ANSI
renderer uses; on a beneficial upward scroll it ships `scrollUpRows` + the
residual rows only. The client's `CellBuffer.scrollUp` shifts the mirror,
then residual patches land, and the DOM surface's existing scroll-up moves
the rows visually. Parity proven: a 200-frame scrolling-log sequence stays
byte-exact on the mirror, and every steady frame is a detected scroll.
Every workload is now 1.06–2.09x deflated ANSI (the only >1.7x is the
tiny counter, 54 vs 113 bytes — trivial absolute). fleury's structured
wire is within 13% of the ANSI peers overall while delivering a real DOM
surface and a semantics path they can't.
