# Serve on the Fleury Renderer — xterm.js Retirement Plan

**Date:** 2026-06-12
**Status:** PLANNED (maintainer directive: pre-launch, rely on the
fleury web renderer for served sessions now; no xterm fallback period)
**Companions:** remote protocol (`packages/fleury/lib/src/remote/`),
web host (`packages/fleury_web/lib/src/run_tui_surface.dart`), DOM
surface (`dom_grid/`), input (`dom_input_source.dart`).

## Why (one paragraph)

The serve path currently streams raw ANSI (`OUTPUT 0x10`) to a browser
page that needs a terminal emulator to interpret it — that emulator is
xterm.js, and with it come the glyph-rendering fight (ligatures,
customGlyphs, canvas addon, font stacks), a CDN dependency in an
otherwise single-binary story, and a renderer that can never carry
semantics. Fleury already owns a browser renderer that is perf-gated,
parity-oracled, and semantic: the DOM surface. Put the *presentation
plan* on the wire instead of ANSI and the served client becomes our own
surface — same frames driving local terminal, compiled web app, and
remote session. Pre-launch means we cut over, not coexist.

## Decisions (ratified by this plan unless overridden)

1. **Wire carries structured frames, not ANSI.** The serve path renders
   fleury frames only. Foreign-ANSI passthrough (e.g. subprocess
   terminal handoff mirrored over serve) is explicitly unsupported —
   handoff requires a local TTY and was never coherent over a mirror.
   The `OUTPUT 0x10` frame id is retired-but-reserved.
2. **Input is structured events**, not stdin bytes: serialized
   key/mouse/paste/focus events from `dom_input_source`, dispatched
   server-side as `TuiEvent`s. This skips browser-side escape encoding
   and server-side re-parsing entirely; the input parser remains the
   native-PTY path's concern.
3. **The client is a self-hosted dart2js bundle** embedded in the
   binary (generated asset + freshness gate), replacing the CDN script
   tags. No external network dependency to serve a session.
4. **Semantics ship over the wire** (the deferred coalesced flush,
   already off the visual frame) so served sessions are
   agent-drivable and accessible — the capability xterm structurally
   cannot have, and a launch differentiator for `fleury serve`.
5. **Sequencing: this lands BEFORE the web release switches.** The
   readiness bundle fingerprints fleury_web sources, so regenerate
   evidence once, after this merges: this plan → evidence refresh →
   `make-dom-default` + `retire-temporary-paths` preflights → switches.

## Phases

### Phase 1 — Protocol v2 (core, `remote_protocol.dart`)

New frame types alongside INIT/RESIZE:

- `PLAN` — binary-encoded presentation plan per rendered frame: dirty
  rows as span runs (reuse the cell/style encoding the DOM surface
  consumes), scroll-up ops, cursor position/visibility. This is the
  same shape `FramePresentationPlan` already models — encode it, don't
  invent a sibling.
- `SEMANTICS` — coalesced semantic-tree update batches (node
  add/update/remove, roles/state/actions), emitted on the existing
  deferred flush cadence.
- `INPUT_EVENT` — structured client→server events (key, mouse, paste,
  focus, resize can stay its own frame).
- INIT gains a protocol version byte; mismatch is a clean close with a
  rendered message, not undefined behavior.

Tests: encode/decode round-trip property tests (seeded RNG — the
renderer-oracle pattern) plus malformed-frame fuzz, which doubles as a
down-payment on the test-plan's fuzzing item.

### Phase 2 — Server: remote surface host (core `remote/`)

Today `RemoteTerminalDriver` impersonates a terminal and receives ANSI
from the renderer. Replace with a remote *surface host* that plugs in
at the same SPI the web host uses: frame loop → damage → presentation
plan → encode → `PLAN` frame; deferred semantic flush → `SEMANTICS`
frame; `INPUT_EVENT` → dispatch into the runtime. Extract whatever
host logic this shares with `run_tui_surface.dart` rather than copying
it — the web host is the reference implementation. The ANSI encoder is
simply not in this path anymore.

### Phase 3 — Client bundle (`fleury_web`)

A `remote_client` entrypoint: websocket connect → INIT handshake
(viewport from the window, resize observer thereafter) → `PLAN` frames
applied to `DomGridSurface` → `SEMANTICS` frames applied to the
semantic DOM presenter → `dom_input_source` events serialized back.
Build via `dart compile js -O2`; a `fleury_dev` verb regenerates the
embedded asset, and a freshness test (hash of source inputs vs asset)
fails the build when someone edits the client without regenerating.

### Phase 4 — Swap serve, delete xterm

`serve_index_html` becomes a minimal shell that loads the embedded
bundle. The xterm page, CDN tags, and the in-tree xterm tuning
(canvas addon / ligature suppression — currently uncommitted working
copy changes) are deleted, not migrated. Update
`serve_index_html_test`, `serve_spawn_test`, `serve_integration_test`
to assert the new page + handshake.

### Phase 5 — Verification

- **Parity oracle, extended:** in the Chrome suite, run a served
  session end-to-end (server in the test process, headless client) and
  assert the client DOM equals the server's cell buffer — the
  divergence-oracle pattern applied to the transport.
- **Input round-trip:** replay the existing dom-input trace fixtures
  through the wire and assert the server-dispatched `TuiEvent`s match
  the direct-path events.
- **Latency + bytes:** measure frame→DOM-applied over localhost
  websocket and PLAN-frame bytes vs the old ANSI bytes for the same
  scenarios (expect comparable; measure, don't assume). Record in the
  execution log; add a serve scenario to the web captures only if the
  numbers surprise.

### Phase 6 — Evidence + switches (the launch tail)

Regenerate the web readiness bundle from main (it currently fails
preflight on worktree-era fingerprints), run both release preflights,
throw `make-dom-default` and `retire-temporary-paths`. After this
plan, "fleury web" is one renderer everywhere a browser is involved.

## Risks, honestly

- **Browser input fidelity** (IME, dead keys, layouts) is the real
  one. `dom_input_source` is tested and already serves the dart2js
  path, but xterm had a decade of edge cases. Pre-launch tolerance
  applies; the input round-trip suite catches regressions; gaps get
  filed against the existing IME workstream rather than blocking.
- **Bundle size/startup**: dart2js client expected at a few hundred KB
  gzipped, self-hosted; measure at Phase 3, only optimize if it
  exceeds ~500 KB gzipped.
- **In-flight working-tree changes**: the current uncommitted xterm
  tuning becomes dead the moment Phase 4 lands — decide to drop it (or
  land it as a stopgap) before Phase 1 starts, so the tree is clean
  for evidence fingerprinting.

## Estimate

3–5 working sessions: protocol+server (1–2), client+swap (1–2),
verification+evidence (1).
