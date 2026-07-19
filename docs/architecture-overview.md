# Architecture overview

Fleury runs the *same* widget tree in a real terminal and in a browser. This
section is how that works under the hood — start here for the shape of the whole
system, then follow the links into each piece.

If you've used Flutter, a lot of this will feel familiar: Fleury borrows its
retained, reactive pipeline and rebuilds it for a grid of character cells instead
of pixels.

## One tree, four jobs

Fleury is a **retained-mode** framework. Its pipeline has four related views
(the fourth, semantics, is retained only where a surface consumes it):

| Tree | Job |
|------|-----|
| **widget** | Immutable, throwaway configuration. Widgets describe *what* the UI should be; rebuilding one is cheap. |
| **element** | The durable spine. Elements hold identity and state across rebuilds — your `setState` lives here, and it's what lets Fleury rebuild only the subtree that changed. |
| **render** | Layout and paint over a **grid of cells**: constraints flow down, sizes come back up, and each render object paints graphemes-plus-style into a shared buffer. |
| **semantics** | A machine-readable projection of the UI — roles, state, geometry, and supported actions. Browser and agent surfaces retain and update it; tests and plain-terminal debug collect it on demand. |

A state change runs one **incremental** pipeline:

```
setState → rebuild only the dirty subtree → lay it out → paint into a
damage-tracked CellBuffer → hand the changed cells to a target
```

Only the dirty path does work; the rest of the tree is reused untouched, and the
target is handed only the cells that actually changed. A button label changing
doesn't re-lay-out the table next to it, and an idle frame produces nothing at
all. (This four-tree pipeline is the part most directly inherited from Flutter —
see [Influences](#influences).)

## A platform-neutral core, plus targets

Everything above is **platform-neutral in the way that matters**: free of
`dart:io` (it compiles to JavaScript, guarded by a transitive-import test) and
presenter-agnostic — nothing in it writes bytes to a terminal, a socket, or
the DOM. Terminal *vocabulary* (capability enums, the ANSI renderer as a pure
`CellBuffer → bytes` function) does live in the core; actually writing bytes
to a device is the targets' job. The core's primary visual output is a `CellBuffer` — an abstract
grid where each cell is a grapheme plus a style (fg/bg, bold, dim, inverse…).
The same mounted tree also produces semantics for hosts that need accessibility,
agent control, or structured browser sessions. A **target** takes the visual
buffer and semantic model it needs and presents them somewhere real.

```
        your app (widgets)
               │
   ┌───────────▼────────────┐
   │      Fleury core       │   platform-neutral, dart:io-free
   │  widget · element ·    │   → compiles to JavaScript
   │  render · semantics    │
   │          ↓             │
   │      CellBuffer        │   an abstract grid of styled cells
   └───────────┬────────────┘
               │  host SPI (the seam)
   ┌───────────┼───────────────────────────┐
   ▼           ▼                            ▼
 Terminal    Browser, embedded        Browser, served
 (ANSI)      (mountApp)                (fleury serve)
 dart:io     the app compiles to JS    the app runs on a server;
             and runs in the page      the browser paints streamed frames
```

The two browser targets are not the same thing. **Embedded** compiles your whole
app to JavaScript with dart2js and runs it client-side — no backend, every live
demo on this site works this way. **Served** keeps the app running natively on a
server (so it can use the filesystem, processes, anything `dart:io`) and streams
the changed cells to a thin browser client. Same widget tree, different place the
code lives.

Everything above the seam is identical regardless of where it ends up; the
target is the only part that *talks to* a terminal, the DOM, or a socket. A parity
oracle asserts the terminal and the browser render the same tree, so the surfaces
can't quietly diverge.

## How this section is organized

This page is the map. The rest of the architecture section splits the system by
the question you are trying to answer:

- **[Architecture deep dive](architecture-deep-dive.md)** — the retained trees
  in detail: widget, element, render, cell buffer, semantics, frame damage,
  presentation planning, tradeoffs, and pressure points.
- **[Core and targets](core-and-targets.md)** — the package/import split: the
  `dart:io`-free core, the host SPI, and exactly which code compiles where.
- **[Serving and embedding](serving-and-embedding.md)** — the two browser paths:
  embedded `mountApp` versus served `fleury serve`, and when to reach for each.
- **[Built for agents](agents-and-semantics.md)** — the semantic app graph, and
  how tests, accessibility, and agents drive the UI by meaning instead of
  scraping ANSI.
- **[Performance](performance.md)** — the performance contract and benchmark
  surface that keep the incremental pipeline honest.

## Influences

Fleury is its own framework, but it stands on prior art. The retained four-tree
pipeline (widget → element → render → semantics) is most directly influenced by
**Flutter**. The cell-grid model and the terminal focus follow the long line of
TUI toolkits — from `ncurses` to modern ones like **Ratatui**, **Textual**, and
**Bubble Tea**. And the semantic app graph echoes the accessibility trees of the
web (**ARIA**) and native UI platforms. What's new is the combination: that
pipeline, on a cell grid, with one app definition spanning a terminal and the
browser.
