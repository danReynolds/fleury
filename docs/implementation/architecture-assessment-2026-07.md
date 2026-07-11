# Fleury architecture assessment — 2026-07-10

**Verdict: architecturally sound. No fundamental weakness warrants redesign.**
The load-bearing bets are each the right call for what fleury is trying to be,
and — the rarer property — they are **defended by executable invariants**
(io-freedom, cross-package-import, public-API-boundary tests; 6–7 perf gates),
so the design cannot silently rot. The rough edges are *consolidation
opportunities and one deferred hardening*, not foundational flaws.

Method: five parallel verifications against `main` — four subsystem readers
(reactive core, presenter abstraction, wire/semantics, composition-root +
layering) each handed a specific claim to confirm/refute, plus a peer
calibration (Textual, Ink, Ratatui, Bubble Tea, notcurses). Three of the four
subsystem passes *corrected* the initial thesis; the corrected version is below.

---

## The load-bearing bets

| Bet | Verdict |
| --- | --- |
| **Retained three-tree reactive model** (Widget/Element/RenderObject) | **Right — for a stronger reason than DX.** The retained tree is the *persistent, addressable* structure the browser-diff **and** the agent-query both require; immediate-mode (Ratatui) has no standing tree for either and would force a parallel retained model anyway. Tax is measured (~6 KB/frame is the real cost of an actual state change, behind a frame-skip gate — an idle app allocates ~nothing), not assumed. |
| **Two surfaces, one framework** (presenter/driver seam) | **Sound — one-framework-two-backends done well, not over-reach.** The shared assets (widget tree, frame loop, damage model, planner, semantics, `FrameDriver` choreography) are legitimately shared; two codebases would be wrong. |
| **Semantic wire + agent story** | **The real moat, coherent, cleanly built.** One semantic representation — the browser a11y DOM and the agent bridge decode the *identical wire with the identical class* (`SemanticsWireDecoder`). The visible grid is a *separate* plan path the agent never sees. |
| **io-free core + host-provided io** | **Confirmed, stronger than claimed.** The guard walks the full transitive closure (not a grep), rejects `dart:io` *and* `dart:ffi`, and the core is also `dart:html`/`dart:js`-clean → genuinely wasm-viable. Textbook dependency inversion, no cycles, barrel-guarded. A genuine strength — leave it. |
| **Composition root** (`runApp` / `_runAppImpl`) | **Not the smell it first appears.** It's a large but *already-decomposed* composition root (heavy logic lives in `FrameDriver`/`TuiRuntime`/`InputDispatcher`/`FrameSemanticsPipeline`); it's tested the textbook way (public `driver:` DI + PTY integration), with **zero** `@visibleForTesting` seams in `runtime/`. A linear, auditable composition root is *correct* — its ordering is safety-critical. |
| **fd-capture** (dup2 + reader isolate) | Exotic but correct-altitude. Catches native/FFI writes zones/IOOverrides can't. Sound. |

---

## The one systemic weakness: parity by convention, not construction

The single theme worth acting on. Fleury has **two hand-mirrored hosts** — the
native `run_app.dart` and the browser `run_tui_surface.dart` — and several
cross-cutting concerns are kept in sync *by comment* rather than by shared
construction:

- **Frame telemetry** is re-implemented in each `FramePresenter`
  (`AnsiFramePresenter`, `WireFramePresenter`, and the browser embed presenter
  emits to a *different channel entirely*). This already bit: the empty
  `read_frames`-over-the-wire bug fixed this session (commit `5ee1cb5`) was
  exactly a cross-cutting concern silently shipping *absent* on one surface,
  caught only by an e2e.
- **Composition wiring** is duplicated across the two hosts, flagged by six
  “mirrors the in-browser host” comments in `run_app.dart`.
- **Inline-image cache eviction** is mirrored app-side (`_shippedImageIds`) and
  browser-side, coupled across a socket by comment — the next likely
  *user-visible* drift.

Crucially, **the team already knows this and is closing it**: `BrowserPresentationHost`
is an explicit anti-drift seam, and the clipboard subsystem (three transports
behind one `Clipboard` interface, chosen once at assembly) is the same concern
done *right* — proof the correct pattern is understood. That a framework this
size has *one* systemic theme, already diagnosed and half-closed, is itself a
strong soundness signal.

**Fix (structural, non-urgent):** lift the shared collaborator graph + the
`buildRoot` scope stack into a host-neutral builder (`mountTuiApp` in
`fleury_host`), and hoist `FrameEvent` assembly into `FrameDriver.onFrameCommitted`
(the driver already owns the commit, `debugWatching`, and the `FramePresentInfo`).
Both convert parity from convention into construction — “impossible to forget”
instead of “remember to mirror.”

---

## The other real risk: semantic node identity

Distinct from the parity theme, and the thing most likely to bite the **agent**
story. Auto-generated semantic ids are positional — `element-<hash>` (explicitly
not stable across rebuilds) or `auto:…~<index>` (carries a positional segment).
A held agent/AT reference can come to denote a *different* logical node after an
unkeyed list recycles element slots. The MCP layer guards with a role+label+
actions fingerprint, but its own docstring admits the residual gap (two nodes
differing only in value are interchangeable). The correct fix — a build-owner
**structure generation** backing stable ids (the deferred “A3” work) — would make
identity survive rebuilds without depending on app-author `Semantics(id:)`
discipline. **If one thing is hardened for the moat, it should be identity, not bytes.**

---

## What I would *not* touch

- **The io-free boundary and package layering.** Genuine strength; guard-enforced. Leave it.
- **The reconcile algorithm.** O(n) with a stable-unkeyed fast path and `identical`-instance skip; already survived real bugs. Fine.
- **The ANSI diff / wire plan.** The most mature code in the tree — damage-bounded, style-table-deduped, LEB128, scroll-detected, cursor-minimized. Not over-rendering.
- **The DEFLATE-cliff wire scheme.** *Solved, not fighting.* Per-frame wire cost is flat in tree size (~38 B/frame at 240 nodes) and gated against regression; residual exposure is only the first full frame of a connection. A smarter *compressor* is low-leverage — the diff already extracts the structural sharing DEFLATE needs.

---

## Perf / correctness backlog (feeds the low-level pass)

Ranked by leverage. All optimizations/hardening within the sound design — none
implies redesign.

1. **Prune the paint walk.** Layout is memoized per-node; paint is not — every
   rendered frame re-walks the *entire* render tree to paint, pruned only at
   explicit `RepaintBoundary` (nothing auto-inserts them). Bytes are fine (the
   ANSI diff bounds to damage); paint *CPU* is O(whole-tree) per interactive
   frame. Negligible today (small trees + frame-skip gate), but it dominates a
   large log/table under per-keystroke or streaming-token updates. **Fix:**
   auto-insert repaint boundaries at the natural cache points the framework
   already knows — `ListView`/`ScrollView` items, `Navigator` routes, `Overlay`
   entries. Turns a keystroke in a 5 000-node app from O(tree) to O(change).
2. **Semantic diff CPU.** `SemanticsOwner.update` already computes the
   added/removed/updated id sets each flush, but `WireSemanticFramePresenter`
   discards them and re-diffs the whole snapshot from scratch — and `_flatten`
   calls `node.toJson()` (which recurses the whole subtree) then throws the
   children away. O(tree) work for an O(changed) wire. **Fix:** thread the
   changed-id set into the encoder; **trivial down-payment shippable today** —
   replace `node.toJson()..remove('children')` with the existing
   `toScalarJson(includeBounds: true)` (O(1) per node) at
   `remote_semantics.dart:138`.
3. **Stable semantic ids (A3).** See “identity” above — correctness/robustness
   for the agent moat.
4. **Minor:** the `text_input.dart → TerminalFeature` capability leak (a neutral
   widget naming terminal features); the image-cache eviction coupling (rides
   the `mountTuiApp` structural fix).

---

## Positioning (peer-calibrated — state it precisely or it punctures)

Fleury is **not** novel for being retained/reactive (Textual, Ink), for ANSI
diffing (universal — Ratatui, Ink, notcurses, Textual all do it), for inline
images (notcurses is the ceiling), for reaching a browser (Textual streams ANSI
to xterm.js — a DOM grid of *flat cells*), or for being agent-drivable (a whole
MCP screen-scraper swarm already drives *any* TUI via PTV capture — but by
their own admission “no structured UI metadata is exposed by the applications”).

Fleury **is** novel — uniquely in the TUI field — for **one semantic tree that
is simultaneously the terminal paint source, the browser render source, and the
agent-automation surface.** That is Flutter’s proven unified-semantics pattern
(Semantics tree → paint + web-a11y DOM + driver automation) ported to the
terminal. State it as *that* — anchored to the **payload** (app-semantic vs
flat cells) and crediting Flutter as the upstream pattern — not as “renders to a
browser DOM” or “agents can drive it,” both of which the field already has in
weaker forms.

Two strategic notes:
- **Wedge = fidelity, not existence.** “The agent reads the actual widget tree,
  not a scrape of the screen.” Existence is contested; reliability is not.
- **A latent accessibility wedge is sitting unused.** *No* TUI framework ships
  a11y (Textual’s is roadmap-only; Ink/Bubble Tea are called out as
  screen-reader-hostile). Fleury is one step away — ARIA-annotate the semantics
  it already emits into the browser DOM (Flutter’s exact web-a11y trick) — from
  the first real accessibility story in the space. Defensible, and already 90%
  built.
- **Watch-item:** Textual is the one competitor that could pivot into this exact
  position (semantic web + MCP) with a larger community. Today it is behind on
  every one of fleury’s actual differentiators.
