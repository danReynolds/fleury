# RFC 0016: Inline Mode

**Status:** Exploration — not scheduled; revisit post-launch (or sooner if a
decision trigger below fires)
**Date:** 2026-07-05
**Decision point for:** whether/when to build a real inline rendering mode,
and what to do with the exported-but-unimplemented `TerminalMode.inline`
before the API freeze.

This captures the 2026-07-05 exploration: what inline mode is, where the peer
field stands, why fleury should eventually pursue it, the honest counter-case
we validated against our own agent showcase, the current (misleading) state in
the codebase, a design sketch grounded in fleury's architecture, and the
triggers that should promote this from "roadmap" to "scheduled."

---

## 1. What inline mode is

Terminal apps render in one of two shapes:

**Alt-screen (fleury today).** The app switches to the terminal's alternate
buffer (`ESC[?1049h`) — a separate full-screen canvas. Shell, prompt, and
scrollback are hidden; the app owns the whole screen; on exit the buffer pops
and the session is restored as if the app never drew. The shape of
*applications*: editors, htop, lazygit, dashboards, file managers.

**Inline.** The app renders **in the normal buffer, at the prompt, as part of
the scroll flow** — a live region a few lines tall that repaints in place
while the rest of the terminal remains the user's:

```
$ npm install
  ⠹ installing dependencies…        ← live region:
  ████████░░░░░░  42%  react-dom    ← repaints in place
  3 warnings
$ █                                  ← prompt returns *below* on exit
```

Scrollback stays intact, earlier output stays visible, and the final frame
**persists in history** after exit ("✔ Build finished in 3.2s" remains
forever). The shape of *commands with live output*: installers, test runners,
build tools, deploy CLIs, wizards, download progress.

Mechanically, inline differs from alt-screen in kind, not degree:

- **No absolute coordinates.** The app tracks "my UI is currently N lines
  tall" and repositions **relative** to a moving anchor (`CR` + `CUU n`),
  because the terminal scrolls underneath it. Absolute `CUP` breaks the
  moment the region grows past the bottom row.
- **Variable height.** The region is content-height, growing (emit newlines;
  the terminal scrolls naturally) and shrinking (erase the leftover tail
  lines) frame to frame.
- **Log interleaving.** Permanent lines can be inserted *above* the live
  region so they flow into scrollback while the UI stays pinned — Ink's
  `<Static>`, Ratatui's `Terminal::insert_before`. This is what makes the
  test-runner/transcript pattern work.
- **Persist-or-erase on exit** is the app's choice; persist is the default
  people want.

## 2. Peer landscape (verified 2026-07-05)

| Framework | Inline support |
| --- | --- |
| **Ink** (JS) | The *only* mode — its entire model. v6.7+ adopted DEC 2026 sync for atomic inline updates. |
| **Bubble Tea** (Go) | Inline is the **default**; alt-screen is the opt-in (`tea.WithAltScreen`). |
| **Ratatui** (Rust) | `Viewport::Inline` + `Terminal::insert_before`, plus a `scrolling-regions` cargo feature that uses DECSTBM scroll regions to insert-above **without flicker**; resizable inline viewport landed 2025–26. |
| **Textual** (Python) | `app.run(inline=True)` since 0.55 (2024). |
| **prompt_toolkit** (Python) | Inline-first (powers IPython); full-screen is the opt-in. |
| **termui** (Dart, small) | Inline via `ESC[nF` cursor-up repositioning. |
| **Nocterm** (Dart, near peer) | No documented inline mode. |
| **fleury** | ❌ — an unwired constant (see §5). |

**Table-stakes verdict:** for general-purpose TUI frameworks, effectively yes
— unanimous at the top of the field. For *fleury's launch*, no: the launch
scope is deliberately full-screen-app-shaped, and Textual thrived for years
without inline. It becomes table stakes the moment fleury courts the CLI-tool
or agent-CLI market — and fleury's own long-term vision already promises it
(`docs/leading-reactive-tui-roadmap.md:1445` "a meaningful subset of apps can
degrade from full-screen UI to inline or [prompts]"; `:1545` "become an inline
status UI in a local terminal").

## 3. Why pursue it

**Market coverage.** The unifying test: *is the command part of a shell
session, or a place you visit?* Inline is the first kind — and by count of
CLI tools shipped it is probably the larger half of the market:

- package managers / installers (`npm install`, `brew`, `ollama pull`)
- test runners in watch mode (failures scroll to history; live status pinned)
- build tools / monorepo runners (Turborepo-style live task trees)
- deploy/infra CLIs (`terraform apply`, Wrangler/Vercel/Fly, `kubectl rollout`)
- interactive wizards (`create-*` flows, inquirer/huh-style prompts — answers
  persist as a record; nobody alt-screens a three-question wizard)
- download/progress anything; git-hook runners (lint-staged)

Fleury cannot build **any** of these today.

**The agent-CLI split.** The flagship agent UIs divide by shape: **Claude
Code and Codex CLI are inline** (transcript flows into real scrollback —
copyable, greppable, surviving exit — with a live status/composer region
pinned below); **Crush (Charm) and OpenCode are full-screen**. Both shapes
ship at the top of the market. Fleury covers only one. For a framework whose
positioning leads with agents, not being able to build the Claude-Code shape
is a visible hole.

**Fleury-specific consumers.** `dune_cli` (the M2.6 flagship integration) is
plausibly inline-shaped — if it runs *between* commands rather than as a
resident console, inline becomes a flagship dependency (see triggers, §8).
Even the `fleury` CLI's own commands (benchmark runs, serve startup) would
present better as inline progress than raw prints.

## 4. The honest counter-case (validated against our own showcase)

We challenged "agent CLIs would be much nicer inline" against
`packages/samples/lib/src/agent_tui.dart` — which is essentially the Claude
Code UI (⏺ blocks, ⎿ results, bordered `›` composer, status bar) rendered
full-screen with an app-owned `ListView(pinToBottom)` transcript. The
challenge **partly refuted the claim**; the learnings:

App-owned history does things inline structurally cannot:

- **History is mutable.** In an inline app, once a block scrolls into terminal
  scrollback it is frozen — a finished tool result can never be collapsed,
  updated, or re-rendered. On resize, terminal reflow mangles old frames (the
  classic Ink artifact). An app-owned transcript collapses/expands after the
  fact, re-wraps perfectly on resize, and can search/filter in place.
- **No viewport-height ceiling.** Inline live regions taller than the terminal
  glitch (Ink clamps and still has artifacts); full-screen has no such limit.
- **Layout freedom** — sidebars/panels are impossible inline.

What full-screen genuinely loses:

- **Exit persistence — the big one.** Alt-screen pops on quit and the whole
  conversation vanishes; inline transcripts live in terminal history forever.
  *Mitigable without inline:* print the transcript (or a tail/summary) into
  the normal buffer on exit — a cheap framework affordance (a driver/`runApp`
  option to dump the final session record into scrollback). Worth doing
  regardless of this RFC.
- **Native terminal ergonomics on history** — terminal search (⌘F), tmux
  copy-mode across the session (in-app `SelectionArea` + OSC 52 mitigates,
  within the app's model).
- **Shell composability** — the `claude -p`-style run-between-commands flow is
  inherently inline.

**Conclusion:** the full-screen agent showcase is a legitimate, deliberate
shape (the Crush shape), not a compromise. Inline is **market coverage**, not
a correction of anything we ship.

## 5. Current state in fleury — and the pre-freeze action

`TerminalMode.inline` exists (`terminal_driver.dart`) and is **exported public
API**, but it only skips the alt-screen switch and cursor-hide. The render
path underneath still paints a terminal-sized buffer at **absolute**
coordinates and full-clears (`2J`) on entry — in the normal buffer that would
stomp the user's visible screen and scrollback: worst of both modes. It has
zero references, tests, docs, or examples.

**Pre-freeze action: remove the constant** (or explicitly mark it
experimental/unsupported) so the frozen surface doesn't imply a capability
that misbehaves. Track the real feature via this RFC.

## 6. Design sketch (grounded in the current architecture)

The retained model transfers cleanly: `TuiFrameLoop`'s double-buffering,
cell diffing, and damage tracking are reusable as-is. The work concentrates
at the **presenter/driver layer**:

1. **Content-height root** — `renderFrame` already gives the root loose
   constraints ("the root widget chooses its own size"), so measurement
   exists. The frame-loop buffer becomes (terminal-width × content-height),
   height varying per frame. *Small.*
2. **Relative cursor addressing — the core work.** `AnsiRenderer` emits
   absolute `CUP` everywhere. An `InlineFramePresenter` must re-base rows
   against a moving anchor (`CR` + `CUU`/`CUD`; column addressing can stay
   absolute via `CHA`). Either parameterize the renderer's row addressing or
   translate at the presenter. *~3–4 days.*
3. **Grow/shrink/persist** — grow by emitting newlines (terminal scrolls,
   anchor rides along); shrink by erasing tail lines (`EL`/`ED` from the new
   bottom); leave the final frame on exit (persist default) or erase.
   *Small–medium.*
4. **`insert_before` / static interleaving** — permanent lines inserted above
   the live region (the transcript/test-runner pattern). Ratatui's
   scrolling-regions (DECSTBM) approach is the flicker-free quality bar; the
   naive erase-region → print → repaint works first. API shape: a
   `printAbove(...)`/static sink on the inline runtime. *~3–4 days.*
5. **Resize reflow — the risk pocket.** On width change the terminal rewraps
   the app's *own previous lines*, breaking anchor math; even Ink still has
   artifacts here. Strategy: on resize, best-effort erase from anchor, full
   region repaint, accept bounded artifacts; PTY tests for grow/shrink/resize
   storms. *~3–4 days including tests.*
6. **Height policy** — clamp the region to viewport−1 (content scrolls
   internally beyond that). Ink clamps; Ratatui uses fixed height; we can do
   content-height-capped. *Decision + small.*
7. **Unaffected:** input stack (raw mode unchanged), serve/embed (inline is a
   terminal-driver concern; the browser has no "inline"), semantics.

**Estimate: 2–3 weeks of quality work.** Synergy: the terminal IME-caret fix
(expert-assessment #1) shares the "presenter owns post-frame cursor state"
plumbing — land it first; it lays inline's foundation.

## 7. Adjacent cheap win (do regardless)

**Exit persistence for alt-screen apps**: an option to print the final frame
/ transcript tail / summary into the normal buffer after the alt-screen pops.
Closes the biggest practical loss of full-screen agent CLIs (§4) for ~a day
of work, no inline machinery required.

## 8. Decision triggers — when to schedule this

Promote this RFC to scheduled work when **any** of:

1. **`dune_cli`'s shape resolves to inline** — a between-commands CLI rather
   than a resident console makes inline a flagship dependency (M2.6).
2. **Launch marketing targets the Ink/agent-CLI audience** — pitching "build
   Claude-Code-style tools" without inline undercuts the claim.
3. **Real user demand** — the first serious adopter asking for a wizard /
   installer / watch-mode tool.
4. **The prompt/wizard story ships** — the roadmap's "forms framework with
   shared full-screen, inline, and prompt-mode rendering"
   (`leading-reactive-tui-roadmap.md:1302`) requires inline as its substrate.

## References

- Ratatui: [`Viewport::Inline`](https://docs.rs/ratatui/latest/ratatui/enum.Viewport.html),
  [inline example](https://ratatui.rs/examples/apps/inline/),
  [scrolling-regions PR #1341](https://github.com/ratatui/ratatui/pull/1341),
  [resizable inline viewport PR #1964](https://github.com/ratatui/ratatui/pull/1964)
- [Nocterm](https://github.com/Norbert515/nocterm) ·
  [termui (Dart)](https://pub.dev/packages/termui)
- In-repo: `docs/implementation/expert-assessment-2026-07-05.md` (finding #2),
  `docs/leading-reactive-tui-roadmap.md:1302,1445,1545`,
  `packages/samples/lib/src/agent_tui.dart` (the full-screen agent shape)
