# Architecture overview

Fleury runs the *same* widget tree in a real terminal and in a browser. This
section is how that works under the hood — start here for the shape of the whole
system, then follow the links into each piece.

If you've used Flutter, a lot of this will feel familiar: Fleury borrows its
retained, reactive pipeline and rebuilds it for a grid of character cells instead
of pixels.

## One tree, four jobs

Fleury is a **retained-mode** framework. From your widgets it builds and keeps
four parallel trees, each with a single responsibility:

| Tree | Job |
|------|-----|
| **widget** | Immutable, throwaway configuration. Widgets describe *what* the UI should be; rebuilding one is cheap. |
| **element** | The durable spine. Elements hold identity and state across rebuilds — your `setState` lives here, and it's what lets Fleury rebuild only the subtree that changed. |
| **render** | Layout and paint over a **grid of cells**: constraints flow down, sizes come back up, and each render object paints graphemes-plus-style into a shared buffer. |
| **semantics** | A machine-readable shadow of the UI — roles, state, and the actions each node supports — produced every frame for tests and agents. |

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

Everything above is **platform-neutral**: it never mentions a terminal, a socket,
or the DOM. The core's only output is a `CellBuffer` — an abstract grid where
each cell is a grapheme plus a style (fg/bg, bold, dim, inverse…). A **target**
takes that buffer and paints it somewhere real.

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

Everything above the seam is identical regardless of where it ends up; the target
is the only part that knows about ANSI bytes, DOM nodes, or sockets. A parity
oracle asserts the terminal and the browser render the same tree, so the surfaces
can't quietly diverge.

## Go deeper

- **[Core and targets](core-and-targets.md)** — the core/target seam in detail:
  the `dart:io`-free boundary, the host SPI, and exactly which code compiles
  where.
- **[Serving and embedding](serving-and-embedding.md)** — the two browser paths
  above, and when to reach for each.
- **[Built for agents](agents-and-semantics.md)** — the semantics tree, and how
  agents and tests drive the UI by *meaning* instead of scraping ANSI.
- **[Performance](performance.md)** — why that incremental pipeline stays cheap
  as apps get busy, measured against peer frameworks.

## Influences

Fleury is its own framework, but it stands on prior art. The retained four-tree
pipeline (widget → element → render → semantics) is most directly influenced by
**Flutter**. The cell-grid model and the terminal focus follow the long line of
TUI toolkits — from `ncurses` to modern ones like **Ratatui**, **Textual**, and
**Bubble Tea**. And the semantic app graph echoes the accessibility trees of the
web (**ARIA**) and native UI platforms. What's new is the combination: that
pipeline, on a cell grid, with one app definition spanning a terminal and the
browser.
