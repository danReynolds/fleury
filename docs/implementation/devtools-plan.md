# DevTools plan — from debug shell to killer feature

**Status:** Prioritized implementation plan (DT0 landed; DT1+ scheduled work)
**Date:** 2026-07-06
**Origin:** First-principles review of the debug shell (what an ideal TUI
debug surface must answer, what peers have, what fleury has). Verdict there:
the in-app shell already beats every terminal peer; the gaps are two
unanswered debugging questions ("why does it look wrong" at the cell level,
"why didn't my key work") and the two consumers the architecture explicitly
anticipated but never built (browser panel, agents).

**The architectural bet is already placed.** `debug_events.dart` declares its
consumers as "(in-terminal panel, future browser DevTools, golden-test
fixtures)" and calls the browser panel "a thin pass." Every milestone below
rides that neutral event stream — none of them fork a second debug pipeline.

## The six questions an ideal shell answers (scorecard)

| Question | After DT0 | Closed by |
| --- | --- | --- |
| Why does it look wrong? | Semantic tree + paint flash; **no geometry, no pick** | **DT1** |
| Why is it slow / re-rendering? | Live + Rebuilds tabs (strong); bytes/frame unsurfaced | DT5 |
| What happened? | fd-complete Logs + **Errors tab (DT0)**; no filtering | DT5 |
| Why didn't my key work? | **Nothing** | **DT2** |
| What's the state? | Semantic state ✓; no focus tree | **DT2** |
| Share / replay? | Hook points reserved | M3.4 (existing roadmap) |

## DT0 — pre-freeze fixes ✅ (this PR)

`DebugConfig`/`DebugMode`/`DebugPanelSide` exported (were unconstructable);
`enabled` defaults off in product builds (`dart.vm.product`) so release
binaries are clean; **Errors tab** (bounded `RuntimeErrorReporter` history via
the controller-provider pattern); **Tab/Shift+Tab tab cycling** (Tree and
Rebuilds were keyboard-unreachable); tab strip wraps at narrow widths; the
[Debugging guide](../../website/src/content/docs/guides/debugging.md).

## DT1 — Inspect-at-cell ("select mode") · **the killer demo** · ~1–1.5 wk

The browser-DevTools gesture, in a terminal, which no TUI framework has:
press `i` in the shell → a crosshair overlays the app; move it with arrows or
click with the mouse → the panel shows, for that cell:

- the owning **render object → element → widget** chain (createdBy type names),
- **geometry**: constraints in, size out, offset — the layout explorer answer,
- the **cell contents**: grapheme, width class, style (fg/bg/attrs),
- the covering **semantic node** (role, label, state, actions).

**Design, grounded in what exists:** pointer **hit-testing already resolves a
cell to a render object** (mouse events do this every frame); the render tree
already retains constraints/size/offset per node; semantic paint-bounds
records already map screen rects to nodes (`SemanticPaintBoundsCapture`); the
crosshair is an overlay cell style, not new paint machinery. New work is the
inspect *mode* (a shell state that claims arrows/click while active), the
detail pane, and a `debugFillProperties`-style description hook on
render objects (start with type names + geometry; property bags can grow).

**Tests:** FleuryTester-level — enter inspect mode, move to a known cell,
assert the reported chain/geometry for a fixture layout. **Risk:** none
structural; scope discipline (property depth) is the only trap.
**Exit criterion:** the screenshot moment — point at any cell of the samples
dashboard and read who painted it and why it's that size.

## DT2 — Input trace + focus inspector · **kills the #1 TUI frustration** · ~1 wk

A new **Input** tab with two halves:

- **Trace**: a rolling log of the dispatch pipeline per event —
  `bytes → parsed event (+kitty/legacy path) → focus route → consumed by X /
  fell through to Y`. The answer to "why didn't my keybinding fire."
- **Focus inspector**: the focus tree with the active path highlighted,
  traversal order, and each node's binding surface.

**Design:** the parser, dispatcher, and `FocusManager` are all fleury-owned —
this is *surfacing*, not building. Add trace emission behind
`DebugEvents.enabled` (zero cost when the shell is off, matching the existing
frame-event discipline); dispatcher records the route as it walks; focus tree
snapshot mirrors the semantic-snapshot provider pattern.
**Tests:** synthetic key through a two-widget focus fixture → assert the
recorded route; focus-tree snapshot golden.
**Risk:** trace verbosity (mouse-move floods) — sample or filter motion events
by default.

## DT3 — Browser DevTools panel on `fleury serve` · **structurally uncopyable** · ~1–2 wk

The same `DebugEvents` stream, rendered as a real DevTools panel in the
browser that's already attached to every serve session. In-terminal over SSH,
browser panel when serving — no single-surface peer can copy this.

**Design:** a `debug` wire frame type carrying the existing event records
(they were designed to serialize — "golden-test fixtures" consumer); gated
behind a serve flag + dev-only negotiation so production serve sessions ship
nothing; client side is a collapsible panel in the served page chrome
(semantics already stream — the Tree tab's data is *already on the wire*).
**Order inside DT3:** logs + frames + errors first (pure event replay), tree
next (already wire-borne), DT1's inspect mode last (needs a pick→cell wire
message).
**Risks:** `remote_client` **bundle-size gate** (panel code must stay behind
lazy/dev-only paths — the gate will catch it: 512/160 KiB); wire-protocol
version skew (reuse the existing version-echo handshake).
**Tests:** the G1 live-wire harness already decodes frames by type — extend it
to assert debug frames appear when enabled and are absent by default.

## DT4 — Agent-legible devtools via `fleury mcp` · **most on-brand** · ~3–5 d

Expose the debug channel to agents alongside the semantic graph the MCP
server already serves: `debug_frames` (recent frame stats), `debug_logs`
(LogBuffer tail), `debug_errors` (history), each as MCP resources/tools in
`packages/fleury_mcp`. An agent driving a fleury app can then *read the
devtools while it works* — "your AI can use your debugger" is the sharpest
one-line differentiator fleury's positioning can ship, and it's mostly
plumbing: the providers built in DT0–DT2 are the data source.
**Tests:** extend the existing `mcp_server_test` resource coverage.

## DT5 — Polish backlog (schedule opportunistically)

- Log **filtering/search** + follow/pause in the Logs tab (tui-logger parity).
- **Bytes/frame in Live** (surface the existing `FLEURY_BYTE_TELEMETRY` data
  when the shell is open — no env var needed).
- **Self-observation filter**: tag shell-caused frames so Live/Rebuilds stats
  exclude the panel's own repaints.
- Key-steal refinement: `p`/`Tab` claims while open are documented; consider a
  panel-focus model if real apps report friction.
- Copy-from-panel (OSC 52 export of logs/errors/inspect reports).

## Sequencing rationale

DT1 before DT2 because it's the demo that *sells* the whole surface (and DT2
reuses its overlay/mode machinery). DT3 after both so the browser panel ships
with the full tab set rather than twice. DT4 anytime after DT0 — it's small
and independently valuable; do it alongside DT3 if a second track is open.
Replay (M3.4) stays where the roadmap put it — DT3's wire format is designed
so replay artifacts are "a recorded debug stream," not a new format.

**Total to killer-feature status: ~4–5 weeks of focused work**, every
milestone independently shippable and demoable.
