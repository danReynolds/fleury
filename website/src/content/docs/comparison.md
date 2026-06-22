---
title: How Fleury compares
description: Where Fleury sits among terminal UI frameworks — Ratatui, Textual, Bubble Tea, Ink — and when to pick each.
---

There are excellent terminal UI frameworks already. Fleury isn't trying to
replace all of them — it's aimed at a specific combination: **a retained
widget-tree model, a browser target, and a semantic graph built for tests and
agents**, in Dart.

Here's the landscape on a few verifiable axes. (Frameworks move quickly; this
reflects releases current as of mid-2026 — check each project's own docs for the
latest.)

| Framework | Language | Programming model | First-class web target |
| --- | --- | --- | --- |
| **Fleury** | Dart | Retained widget tree | **Yes** — embed via dart2js *or* serve |
| Ratatui | Rust | Immediate mode | No |
| Textual | Python | Retained tree (CSS-like) | Yes — serve (textual-web) |
| Bubble Tea | Go | Elm (Model / Update / View) | No |
| Ink | JavaScript | Retained tree (React) | No |

## What makes Fleury different

- **Two surfaces from one codebase.** The same widget tree runs in a terminal,
  embeds in a page client-side with dart2js (no backend), or streams from a
  native process with `fleury serve`. Textual can serve to the browser; Fleury
  additionally compiles *into* a page as a plain JS bundle.
- **A semantic app graph for tests and agents.** Roles, state, and actions ship
  as a first-class output, so tests assert on meaning and AI agents drive the UI
  through typed actions rather than scraping ANSI. See
  [Built for agents](/architecture/agents-and-semantics/).
- **Flutter's model, if you already know it.** Widgets, `State`, `build`,
  `setState`, incremental rebuilds — the mental model transfers directly.

## When to pick something else

- **Ratatui** if you're in Rust and want maximum control with an immediate-mode
  model and a mature ecosystem.
- **Textual** if you're in Python and want a batteries-included framework with a
  large widget set, CSS-like styling, and devtools.
- **Bubble Tea** if you're in Go and like the Elm architecture and the Charm
  ecosystem (Bubbles, Lip Gloss, Glamour).
- **Ink** if you're in Node and want to build CLIs with React.

## Fleury's trade-offs

Fleury is Dart — less common in the terminal space than Go, Rust, or Python, so
the surrounding ecosystem is younger. It's also pre-1.0: the API is still
settling, and it's distributed as a Git dependency today. If you need a
long-stable, widely-deployed framework right now, one of the above may fit
better. If the retained model, the web target, and the agent-facing semantics
are what you're after, that's exactly the gap Fleury fills.
