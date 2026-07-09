# DevTools plan — from debug shell to killer feature

**Status:** Prioritized implementation plan (DT0 landed; DT1+ scheduled work)
**Date:** 2026-07-06 · **Re-prioritized 2026-07-06** (maintainer call): rank by
*expected usage frequency*, not demo value. Focus debugging, agent devtools,
and log ergonomics are daily-drivers; cell inspection is an occasional tool —
it moves to the tail. Ordering within the picks: agent devtools first because
it is the smallest and everything it needs already exists after DT0.
**Origin:** First-principles review of the debug shell (what an ideal TUI
debug surface must answer, what peers have, what fleury has). Verdict there:
the in-app shell already beats every terminal peer.

**The architectural bet is already placed.** `debug_events.dart` declares its
consumers as "(in-terminal panel, future browser DevTools, golden-test
fixtures)" and calls the browser panel "a thin pass." Every milestone below
rides that neutral event stream — none of them fork a second debug pipeline.

## The six questions an ideal shell answers (scorecard)

| Question | After DT0 | Closed by |
| --- | --- | --- |
| Why didn't my key work? / what's focusable? | **Nothing** | **DT2** |
| What happened? | fd-complete Logs + Errors tab (DT0); no filtering | **DT3** |
| Why is it slow / re-rendering? | Live + Rebuilds tabs (strong); bytes/frame unsurfaced | **DT3** |
| Can my agent see all this? | Semantic graph only (`fleury mcp`) | **DT1** |
| Why does it look wrong? | Semantic tree + paint flash; no geometry, no pick | DT5 (deprioritized) |
| Share / replay? | Hook points reserved | M3.4 (existing roadmap) |

## DT0 — pre-freeze fixes ✅ (PR #45)

`DebugConfig`/`DebugMode`/`DebugPanelSide` exported (were unconstructable);
`enabled` defaults off in product builds (`dart.vm.product`) so release
binaries are clean; **Errors tab** (bounded `RuntimeErrorReporter` history via
the controller-provider pattern); **Tab/Shift+Tab tab cycling** (Tree and
Rebuilds were keyboard-unreachable); CSI Z back-tab parsing (Shift+Tab was a
dead key on legacy terminals); tab strip wraps at narrow widths; the
[Debugging guide](../../website/src/content/docs/guides/debugging.md).

## DT1 — Agent devtools via `fleury mcp` · **✅ LANDED** · ~3–5 d

Expose the debug channel to agents alongside the semantic graph the MCP
server already serves, in `packages/fleury_mcp`:

- `debug_frames` — recent frame stats (number, phase timings, slow count),
- `debug_logs` — the `LogBuffer` tail (fd-captured stray output included),
- `debug_errors` — the bounded `RuntimeErrorReporter` history.

**Landed** as the `read_frames` / `read_logs` / `read_errors` MCP tools (pull-style `debugRequest`/`debugResponse` wire frames → a runtime `DebugFrameLog` + query assembler → the bridge → MCP). An agent driving a fleury app can then *read the devtools while it works* —
"your AI can use your debugger" is the sharpest one-line differentiator
fleury's positioning can ship. It's mostly plumbing: the DT0 providers are the
data source, and the MCP server already has the resource/tool patterns.
**First because:** smallest milestone, zero new collection machinery, and each
later milestone (focus data, filtered logs) extends what agents can see for
free.
**Tests:** extend the existing `mcp_server_test` resource coverage.

**Closed-loop hardening (post-landing):** a spawn-real-app e2e
(`fleury_mcp/test/mcp_debug_e2e_test.dart`) that drives scenarios and reads
the debug channel back found that **two of the three tools returned nothing
over the very path they were built for** — the fake-bridge unit tests fed
canned JSON and couldn't see it. Fixed: `WireFramePresenter` now emits frame
telemetry (`read_frames`), and remote sessions fd-capture with a live tee
through the saved descriptors (`read_logs` fills while the parent's log
forwarding keeps working). The tee work also flushed out a latent transport
race (frames sent before `incoming` had a listener were dropped — any await
between connect and `enter()` hung the handshake), fixed in
`unix_socket_transport` and locked by `unix_socket_prelisten_test`.
**DT4 note:** `fleury_web`'s `_SurfaceFramePresenter` (browser/embed) still
does not emit frame telemetry — the browser panel milestone should hoist the
emission into `FrameDriver` (or mirror it) rather than add a third copy.

## DT2 — Focus inspector + input trace · ~1 wk

A new **Focus** tab answering "what is focusable, who has focus, and why did
my key go where it went":

- **Focus tree** — every `FocusNode` in the tree with the active path
  highlighted: what's focusable, traversal order, autofocus claims, and each
  node's binding surface (which keys it would consume). This is the half that
  makes focus *legible* — today focus state is invisible except by behavior.
- **Input trace** — a rolling log of the dispatch pipeline per event:
  `bytes → parsed event (kitty/legacy path) → focus route → consumed by X /
  fell through to Y`. The answer to "why didn't my keybinding fire," and the
  natural companion to the tree (the trace shows the route *through* it).

**Design:** the parser, dispatcher, and `FocusManager` are all fleury-owned —
this is *surfacing*, not building. Focus-tree snapshot mirrors the
semantic-snapshot provider pattern; trace emission goes behind
`DebugEvents.enabled` (zero cost when the shell is off); the dispatcher
records the route as it walks. Once landed, expose both through DT1's MCP
surface (`debug_focus`, `debug_input_trace`) — an agent that can *see the
focus tree* can also explain focus bugs.
**Tests:** synthetic key through a two-widget focus fixture → assert the
recorded route; focus-tree snapshot golden.
**Risk:** trace verbosity (mouse-motion floods) — sample or filter motion
events by default.

## DT3 — Logs & Live polish sprint · ~1 wk aggregate

The daily-driver ergonomics, individually small — ship as one polish PR or
opportunistically:

- **Log filtering + search** in the Logs tab — **✅ landed**: `/` opens an
  incremental search (matches highlight in place, `Enter` keeps / `Esc` clears),
  `s` cycles the source filter (all / stdout / stderr). Still open: a level
  filter once structured levels exist, and **follow/pause** + scroll-through-
  history (tui-logger parity for long sessions).
- **Bytes/frame in Live** — surface the existing `FLEURY_BYTE_TELEMETRY`
  numbers whenever the shell is open, no env var needed.
- **Self-observation filter** — tag shell-caused frames so Live/Rebuilds
  stats exclude the panel's own repaints.
- **Copy-from-panel** — OSC 52 export of a log selection / error report.

## DT4 — Browser DevTools panel on `fleury serve` · ~1–2 wk

The same `DebugEvents` stream, rendered as a real DevTools panel in the
browser that's already attached to every serve session. In-terminal over SSH,
browser panel when serving — structurally uncopyable by single-surface peers.
**Design:** a `debug` wire frame type carrying the existing event records,
gated behind a serve flag + dev-only negotiation; client side is a collapsible
panel in the served page chrome (the Tree tab's data is already on the wire).
**Risks:** `remote_client` **bundle-size gate** (panel code stays behind
dev-only paths — the gate will catch it: 512/160 KiB); wire-protocol version
skew (reuse the version-echo handshake).
**Tests:** the G1 live-wire harness already decodes frames by type — assert
debug frames appear when enabled and are absent by default.

## DT5 — Inspect-at-cell ("select mode") · deprioritized

The browser-DevTools gesture (crosshair → owning widget chain, constraints/
size/offset, cell style, semantic node). Still uniquely feasible (pointer
hit-testing, retained geometry, and `SemanticPaintBoundsCapture` all exist)
and still the flashiest demo — but an *occasional* tool next to the
daily-drivers above, so it waits until DT1–DT4 land. Design notes preserved
from the original plan: inspect mode as shell state claiming arrows/click; a
`debugFillProperties`-style description hook on render objects; FleuryTester
tests against a fixture layout.

## Sequencing rationale

DT1 first: smallest, complete data already available, and it compounds — every
later milestone's data lands in agents' hands the moment it exists. DT2 next:
the biggest unanswered debugging question, and its providers feed both the
panel and the MCP surface. DT3 rides afterward as ergonomics on surfaces
people are now living in. DT4 ships the full tab set to the browser rather
than shipping twice. DT5 when the daily-drivers are done. Replay (M3.4) stays
where the roadmap put it — DT4's wire format is designed so replay artifacts
are "a recorded debug stream," not a new format.

**Total for DT1–DT3 (the prioritized set): ~2.5–3 weeks**, each independently
shippable and demoable; DT4–DT5 add ~2.5–3.5 weeks when scheduled.
