# Fresh-eyes expert assessment — 2026-07-05

A practitioner pass (senior TUI + Flutter perspective) over the areas the
perf pass and API/DX audit did *not* cover: event-loop behavior, input-stack
robustness, terminal-integration ergonomics, unicode correctness, and the
deployment story. Method: three deep code-path audits (input parser, frame
scheduling/resize, cursor/IME/screen-modes) plus hands-on measurement (idle
CPU in a real PTY, AOT/JIT time-to-first-frame, cell-width probes) — every
agent claim re-verified against the code before it appears here.

## The headline: the engine room is excellent

Most of what a veteran would probe came back not just adequate but ahead of
the peer set. **Validated (with evidence):**

| Area | Result |
| --- | --- |
| **Idle cost** | Render-on-demand, measured: an idle app emits **0 bytes and 0.00s CPU over 15s** in a real PTY. Ticker timer starts with the first animation, stops with the last; the text-caret blink stops on unfocus. |
| **Input→paint latency** | Same event-loop turn (microtask), ~0 added latency; 50 `setState`s in a turn coalesce to 1 frame (`frame_scheduler.dart`). |
| **Input parser** | Fuzz-tested state machine; 30ms ESC disambiguation; atomic bracketed paste with KMP terminator matching + flush-on-idle; SGR mouse; **full kitty keyboard protocol** (press/repeat/release, super/meta — `input_parser.dart:379-462`) — ahead of Bubble Tea/Textual. |
| **Unicode widths** | CJK=2, ZWJ family emoji=2, **VS16 emoji presentation=2** (most TUIs get this wrong), skin-tone=2, combining=1 — measured via cell probes. |
| **Panic safety** | Layered restore (finally + zone guard + SIGINT/SIGTERM/SIGTSTP/SIGCONT + editor handoff); raw-mode/alt-screen/mouse/paste all unwound. |
| **Resize** | Scheduler-coalesced, full reset + DEC 2026 sync wrap — no tearing, no debounce needed. |
| **Slow-terminal backpressure** | Native path blocks on write (bounded, ncurses-style); serve path has the producer gate. |
| **Deployment** | AOT: **25ms to first frame, 8.0MB binary** (measured); JIT `dart run` 1.7s (dev-only). |

No action needed on any of the above. Now the ranked findings.

## Priority list

### 1. Terminal IME / hardware-cursor caret — **fix; high value, low effort**

The serve path publishes the focused caret every frame (`WireFramePresenter
readCaret:` → CARET frames → the browser positions its IME element). The
**terminal path never does the symmetric thing**: the hardware cursor is
hidden at enter (`?25l`, `terminal_sequences.dart:15`) and never repositioned
— `ansi_frame_presenter.dart` has zero caret handling. Consequences on a real
terminal: **OS-level IME composition (Chinese/Japanese/Korean input) has no
anchor** — the composition window floats at the wrong place or nowhere;
terminal-native screen readers can't track the caret; terminals' cursor
features (beam styling, cursor-trail) are inert.

The plumbing already exists end-to-end: `TextInput`/`TextArea` set
`focusNode.caretRect` on every paint (`text_input.dart:1590`,
`text_area.dart:767`); only the ANSI presenter ignores it. Fix ≈ after
presenting a frame, if a caret exists → CUP to it + `?25h`, else `?25l`
(mind the sync-update wrap and the diff-cursor bookkeeping). Bubble Tea, Ink,
and Textual all do this. **The single biggest gap for international users —
and it's ~a day of work including tests.**

### 2. Inline mode — **product decision needed pre-freeze**

`TerminalMode.inline` exists (`terminal_driver.dart:33`) and is **exported
public API** — but it has zero references anywhere (no test, no doc, no
example), and the render path would not do what "inline" means: the renderer
paints absolute coordinates and full-clears (`2J`) on entry, so inline mode
would stomp the user's visible screen rather than render an Ink-style bounded
live region at the prompt (anchored, scrollback-preserving, persisting on
exit). The "CLI tool with a live status region" use-case — build tools, test
runners, installers, wizards, the segment that made Ink popular — is fleury's
biggest *product* gap; today fleury only truly supports full-screen apps.

This finding was subsequently explored in depth and **challenged against the
agent showcase** — full analysis, peer landscape (inline is unanimous across
Ink/Bubble Tea/Ratatui/Textual), design sketch, effort estimate (~2–3 weeks),
and decision triggers now live in **[RFC 0016: Inline Mode](../rfcs/0016-inline-mode.md)**.
Two refinements from that challenge: (1) the full-screen agent showcase is a
*legitimate deliberate shape* (the Crush/OpenCode shape — app-owned history is
mutable, resize-perfect, height-unbounded), so inline is **market coverage,
not a correction**; (2) a cheap adjacent win exists regardless of inline —
**exit persistence** for alt-screen apps (print the transcript/summary into
the normal buffer on quit), closing full-screen's biggest practical loss for
~a day of work.

Recommendation stands: **delete the constant before API freeze** (a public
flag that misbehaves), keep real inline as a headline post-launch feature
gated on RFC 0016's triggers (notably: whether `dune_cli` turns out to be
inline-shaped).

### 3. OSC niceties: window title + hyperlinks — **small, decide-and-do**

- **No OSC 0/2 window title** support at all — a `runApp(title:)` /
  `FleuryApp.title` → terminal-tab title is ~10 lines and table stakes
  (Bubble Tea has it).
- **OSC 8 hyperlinks: the capability enum exists but is hardcoded off**
  (`capabilities.dart:250 hyperlinks: false`) and nothing emits it. Half-built
  API is the worst pre-freeze state — either finish (a `Link`/`Text.link`
  affordance + capability detection) or remove the capability entry until
  it's real.

### 4. Flag-emoji (regional-indicator) width — **minor, measure-then-decide**

Cell probes: 🇯🇵 = **1 cell**, but most modern terminals render RI-pair flags
2 cells wide → one column of drift after a flag on probed-narrow terminals
(the SB.6 defensive pin covers unprobed ones). Rare in real TUIs; worth a
15-minute check against kitty/iTerm2/Alacritty and, if confirmed, width=2 for
RI pairs in the width table.

### 5. tmux DA-probe caveat — **docs only**

Inside tmux, DA/graphics probes hit tmux's parser, not the host terminal —
image-protocol detection can miss (industry-wide problem; peers share it).
The escape hatch exists (`FLEURY_IMAGE_PROBE=0` + env overrides); it just
isn't in the user docs. One paragraph in the deployment/terminal docs.

### Noted, explicitly *not* recommending work

- **Mouse capture is all-or-nothing** (wheel steals scrollback when enabled) —
  parity with every peer; fine.
- **SS3-with-modifier decoding** absent — only matters on misbehaving
  terminals; kitty PE covers the modern path.
- **Paste containing the literal terminator** — protocol limitation, not a bug.
- **Startup docs** — numbers are great (25ms AOT); consider quoting them in
  deployment.md, but that's marketing polish.

## Bottom line

The runtime fundamentals — scheduling, input, unicode, safety, performance —
are genuinely production-grade and in several places ahead of the peer set.
What shook out is **not engine work but terminal-citizenship**: one real fix
(IME caret, #1), one product decision the API freeze forces (#2), and two
small finish-or-remove calls (#3). If #1 lands and #2 is decided, this
assessment has no reservations.
