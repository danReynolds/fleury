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
- Full suites green: core 1663, web VM 199, Chrome 154.

## Honest remaining gaps (documented, not blocking)

1. **Scroll-up wire optimization** — *closed*, see the 2026-06-12 update
   below.
2. **Semantics over the wire** — *closed*, see the 2026-06-13 update below.
3. **Single headless-Chrome e2e** — *closed*, see the 2026-06-13 update
   below.
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

## Update — semantics over the wire + end-to-end composition (2026-06-13)

The two remaining composition gaps are closed.

**Semantics over the wire (gap 2).** The serve host already shipped a
`SemanticsFrame`; the client now consumes it. On each frame whose semantic
tree changed (gated on `SemanticDirtyTracker.hasDirt`, so the tree build is
paid only on real change), the host serializes a redacted
`SemanticInspectionSnapshot` and sends it. The browser client decodes it,
reconstructs a `SemanticTree` via the new
`SemanticInspectionSnapshot.toSemanticTree()`, and drives the same
`SemanticDomPresenter` the in-browser host uses — so a served session is
screen-reader- and agent-readable, the differentiator an ANSI-to-xterm relay
structurally cannot offer. The client lays the grid surface and the semantic
tree out as sibling roots under the host (the grid root owns its children via
`replaceChildren`, so semantics must not live inside it), mirroring
`runTuiWebDom`. Reconstruction is redaction-preserving (sensitive values stay
`<redacted>` across the wire) and additive-schema-tolerant: an unknown role
degrades to `text`, an unknown action is dropped — never an exception. A
malformed semantics frame is swallowed, never tearing down the visual session.

**End-to-end through a live socket (gap 3).** Split across the two layers
each proves best:

- *Transport composition, VM, real socket* (`serve_e2e_socket_test`): a real
  `HttpServer` + `WebSocketTransformer` (Dart's default permessage-deflate)
  carries a full-paint plan, a partial-update plan, and a semantics frame; the
  client decodes off the socket, applies patches to a cell mirror, and
  reconstructs the semantic tree. The mirror reproduces the server's final
  frame cell-for-cell and the semantics arrive intact.
- *Browser-DOM composition, headless Chrome* (`remote_client_e2e_test`):
  server-encoded wire bytes (the actual serve encoder) are decoded and rendered
  through the real `DomGridSurface` **and** the real `SemanticDomPresenter` —
  the two calls `RemoteSurfaceClient` makes per frame. Asserts both the visual
  grid DOM (`status: running`, `[ Run ]`) and the accessible DOM (the button's
  `role`/`aria-label`/`data-fleury-actions`, the status region's `aria-live`).

Together they cover the literal socket transport (VM) and the browser's
turning of those bytes into a real accessible DOM (Chrome). Parity also
proven at the unit layer: a `SemanticsFrame` round-trips through
`encodeFrame`/`FrameDecoder` and reconstructs to the same roles, labels,
actions, and state.

Suites green after this work: **core 1663, web VM 199, Chrome 154**; the
embedded-client freshness gate recompiled and matched.

## Update — semantics over the wire didn't scale; now it does (2026-06-13)

Profiling the semantics path we'd just shipped surfaced a real defect: the
host sent a **full** redacted snapshot on every changed frame, with no
diffing, on the assumption that permessage-deflate's context takeover would
crush the near-identical resends. It does — until the serialized tree exceeds
DEFLATE's **32 KiB sliding window**, after which the compressor can no longer
reference the previous frame and per-frame cost goes off a cliff. Measured
(`profiling/bin/serve_semantics_profile.dart`, one small change per frame):

| tree | nodes | full snapshot z/frame |
| --- | --- | --- |
| list of 80 | 84 | 106 |
| list of 120 | 124 | 163 |
| list of 160 | 164 | 400 |
| list of 240 | 244 | **2180** |

A 3× node increase (80→240) cost **20×** the bytes — the knee lands exactly
where one frame's raw snapshot (~32 KiB) stops fitting the window alongside
its predecessor. DEFLATE's window is the hard ceiling (permessage-deflate
maxes at 15 window bits), so the compressor cannot be the fix; the wire must
carry less.

**Fix: a semantic wire diff** (`remote_semantics.dart`,
`SemanticsWireEncoder`/`Decoder`). The tree is flattened to id-keyed nodes
carrying `childIds` instead of nested `children`; the host ships a FULL flat
node list once per connection, then PATCHes (only the nodes whose serialized
form changed, plus removed ids). The client keeps the flat map, applies the
patch, and rebuilds the nested tree. A localized change touches O(changed)
nodes regardless of tree size. Re-profiled:

| tree | nodes | full z/frame | diff z/frame | speedup |
| --- | --- | --- | --- | --- |
| list of 80 | 84 | 106 | 19 | 5.7x |
| list of 160 | 164 | 400 | 28 | 14.1x |
| list of 240 | 244 | 2180 | 38 | **57.2x** |

The diff is **flat in tree size** (10→38 bytes/frame across 12→244 nodes)
where full-resend was super-linear. Semantics is now a negligible constant on
the wire, so the "wire-competitive" claim holds *including* the semantics
traffic the visual profiler doesn't count.

Properties proven (`remote_semantics_test`, plus the parity and both e2e tests
re-pointed through the encoder/decoder):

- A FULL→PATCH stream reproduces, frame for frame, the exact tree a full
  resend would (50-frame streaming sequence; structural add/remove included).
- Redaction is inherited from the snapshot and re-applied on decode — no
  plaintext crosses the wire even via a patch; an all-redacted frame with no
  visible change ships **zero bytes**.
- Resync-safe: a fresh connection always begins with a FULL frame, so a patch
  arriving before any full (or a malformed/over-version payload) is ignored,
  keeping the last good tree rather than corrupting state. Correctness rests
  on the WebSocket being ordered and lossless.
- The real run loop is now covered, not just synthetic frames: a `runTui`
  session driven through `RemoteTerminalDriver` emits a decodable
  `SemanticsFrame` on first paint whose framework-built button (label,
  actions) reconstructs on the client (`remote_surface_driver_test`).

**Server CPU per changed frame** (the diff-detect cost, measured): the encoder
detects changes by structural comparison against the last-sent flat nodes
rather than re-serializing every node — an unchanged node early-exits and
allocates nothing, so computing the diff is close to O(changed) in CPU and
garbage. Measured cost (snapshot redaction walk + encode), µs per *changed*
frame, steady-state patch:

| tree | nodes | snapshot µs | encode µs | total µs |
| --- | --- | --- | --- | --- |
| 24 | 28 | 28 | 31 | 59 |
| 80 | 84 | 82 | 86 | 168 |
| 240 | 244 | 249 | 251 | 500 |

Even the 244-node tree is ~3% of a 60 fps frame, and only on frames where the
semantic tree actually changed. The structural-equality change halved the
encode half (it was 469 µs at 244 nodes when it re-serialized every node) and
removed its per-node string garbage.

Suites green: **core 1671, web VM 199, Chrome 154**; freshness gate matched.

## Update — robustness fuzz + the visual path past the window (2026-06-13)

**Fuzzed the semantic decoder** (the codec-fuzz precedent applied to the new
surface; `remote_semantics_test`). 1000 random envelopes found a real crash: a
patch whose node dropped a required field made the final
`SemanticInspectionSnapshot.fromJson` throw, and the catch only wrapped the
initial `jsonDecode`, not the reconstruction — so a malformed/hostile patch
could take down the decode path. Now caught and rejected. Also capped
reconstruction depth (`maxSemanticTreeDepth = 1024`): `_nest` had only a cycle
guard, so a deep *acyclic* `childIds` chain inside the 64 MiB payload cap could
still overflow the stack; it now prunes. A deeper-than-cap chain and the fuzz
both pass (tree-or-null, never a throw).

**Re-probed the visual path with the same 32 KiB-window lens** that exposed the
semantics cliff, to check the "competitive with ANSI" claim where context
takeover stops helping anyone. Added a `big churn 200x60` scenario — every cell
of a 12 000-cell grid changing every frame (~36 KiB raw/frame, past the window
for both wires):

| workload | deflated PLAN vs ANSI |
| --- | --- |
| big churn 200×60 (full repaint every frame) | **1.79x** |

Neither cell-diffing (fleury) nor ANSI relay (peers) can exploit cross-frame
redundancy in full churn, so this is apples-to-apples — and PLAN stays 1.79x
ANSI, inside the same band as the interactive workloads (1.06–2.09x). The
visual path has no analogous cliff: it already ships only changed cells, and
where everything changes it degrades gracefully alongside the peers rather than
falling off relative to them.

Suites green after this work: **core 1673, web VM 199, Chrome 154**; freshness
gate matched.

## Update — browser render cost vs xterm.js, measured (2026-06-13)

The wire and server-CPU axes were measured; the remaining open question was the
*browser* render cost of the DOM surface versus a terminal emulator. Built a
head-to-head (`packages/fleury_web/benchmark/`): fleury's `DomGridSurface` versus
xterm.js across **all three of its renderer tiers** (DOM, canvas addon, WebGL
addon), fed the **same frame stream** — fleury from a presentation plan, xterm
from the equivalent ANSI produced by fleury's own `AnsiRenderer`. The product
peers (ttyd/gotty/textual-web/VS Code) all render through xterm.js or hterm, so
the meaningful render axis is the renderer tier, not the product. Per-frame
main-thread cost (median; 60 fps budget 16.7 ms):

| workload | fleury apply+render | xterm DOM parse | xterm DOM parse→render |
| --- | --- | --- | --- |
| typing 80×24 | ≤0.10 ms | 1.2 ms | 8.1 ms |
| dashboard 80×24 | 0.20 ms | 1.2 ms | 7.8 ms |
| churn 120×40 | 0.20 ms | 0.7 ms | 7.2 ms |
| churn 200×60 | 0.30 ms | 1.2 ms | 5.5 ms |

`fleury apply+render` is the full client path — `applyRemotePlan` + `present` +
forced layout, all synchronous. `xterm parse` is its `write()`→buffer step
(renderer-independent — the same core ANSI parser for all three tiers);
`parse→render` is wall time to its rAF-scheduled render (≈ one frame of
scheduling latency on top of sub-frame render compute). GPU paint is excluded
for both.

The DOM surface is not the bottleneck it might be assumed to be: the client
turns a received frame into rendered DOM in **≤0.4 ms p95 even at 200×60
(12 000 cells)** — under xterm's ANSI parse alone — because the structured
protocol diffs server-side, so the client applies known patches rather than
re-parsing an escape stream each frame. Both sit far under the 60 fps budget; on
terminal workloads the limit is the display refresh, not the renderer.

xterm's canvas and WebGL tiers need a real GL context, which headless `dart test`
Chrome does not provide — the harness detects this and reports those tiers
`unavailable` rather than silently falling back to DOM and faking a number.

**Run on a real GPU (Apple M1 Pro, ANGLE Metal, 60 Hz), all three xterm tiers**
— synchronous main-thread cost per frame, medians (the visible-window run is
noisy, so only the cleanly-measurable `parse`/`apply` step and medians are
quoted):

| workload | fleury | xterm DOM | xterm canvas | xterm WebGL |
| --- | --- | --- | --- | --- |
| dashboard 80×24 | 0.50 ms | 1.8 ms | 1.4 ms | 0.9 ms |
| churn 120×40 | 0.70 ms | 2.8 ms | 9.4 ms | 0.8 ms |
| churn 200×60 | 0.70 ms | 2.8 ms | 6.5 ms | 0.8 ms |

Two findings survive the noise: (1) fleury's synchronous cost is the lowest at
every size — under all three xterm tiers — because the client applies
server-diffed patches instead of re-parsing ANSI; (2) xterm's **WebGL CPU stays
flat as the grid grows** (~0.8 ms) where its DOM (→2.8 ms) and canvas (→9.4 ms)
tiers climb — the GPU offload is real and is the flattest-scaling xterm tier, but
it still does not pull ahead of fleury. So even against GPU-accelerated WebGL on
Apple Silicon, the DOM surface is comparable-to-lower per-frame main-thread cost;
WebGL's advantage is flat scaling at large grids, not beating fleury. All tiers
sit far under the 60 fps budget. The benchmark vendors xterm.js + addons on
demand (not committed) and lives outside `test/`, so it never runs in CI.

## Update — semantic actions now round-trip; the a11y tree is operable (2026-06-14)

A live audit of a served storybook session caught a real gap: semantics flowed
**one way**. The client built the accessible DOM and the `SemanticDomPresenter`
wired click→`onSemanticActionRequest`, but `RemoteSurfaceClient` never set that
handler and the protocol had no inbound action frame — so a screen reader or
agent *activating* a node through the a11y tree was silently dropped. Reading
worked; driving didn't, undercutting the "agent-drivable **and** accessible"
claim from the gap-2 work (keyboard and pointer-on-grid still operated
everything).

**Fix — a `0x15 SEMANTIC_ACTION` frame** (peer → app), the structured
counterpart to the app → peer `SemanticsFrame`. The client wires
`onSemanticActionRequest` to send `(SemanticNodeId, SemanticAction)`; the driver
surfaces it via `RemoteSurfaceSink.onSemanticAction`; `runTui` invokes it on the
live tree with the core `invokeSemanticActionFromElement` (the same call the
in-browser host uses) and re-renders — so the result streams back over the
existing PLAN + SEMANTICS frames. An action for a missing/disabled node is a
safe no-op; an unrecognized action name is rejected by the codec, not misread.

Proven: a `runTui` session driven through `RemoteTerminalDriver` fires the
widget's `onAction` when a `SemanticActionFrame` arrives
(`remote_surface_driver_test`); the frame round-trips through the framing layer
(`remote_transport_parity_test`); and **live** — clicking the accessible-DOM
checkbox node in a served storybook now toggles it (`aria-checked` flips), where
before it was a no-op. The embedded client asset was regenerated.

Suites green: **core 1676, web VM 199, Chrome 154**; freshness gate matched.
