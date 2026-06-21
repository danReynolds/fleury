# Fleury core and targets

**Audience:** developers who want the mental model of how Fleury is layered —
what "the core" is, what a "target" is, and why the same app can render to a
terminal *or* a browser. For the narrative version of the architecture, see
[the architecture overview](architecture.md); for the two browser delivery modes, see
[Serving and embedding](serving-and-embedding.md).

## The one-sentence model

Fleury is a **platform-neutral core** that turns your widget tree into an
abstract grid of styled cells, plus a set of **targets** that paint that grid
somewhere real — a terminal, the DOM, or a remote browser session.

```
        your app (widgets)
               │
   ┌───────────▼────────────┐
   │      Fleury core       │   platform-neutral, dart:io-free
   │  widget · element ·    │   → compiles to JS
   │  render · semantics    │
   │          ↓             │
   │      CellBuffer        │   an abstract grid of styled cells
   └───────────┬────────────┘
               │  host SPI (the seam)
   ┌───────────┼───────────────────────────┐
   ▼           ▼                            ▼
 Terminal    Web / DOM                   Remote
 (ANSI)      (runTuiWebDom)              (fleury serve)
 dart:io     dart2js, client-side        server runs core,
             in the browser              browser paints frames
```

Everything above the seam is the same regardless of where it ends up. The
target is the only part that knows about ANSI bytes, DOM nodes, or sockets.

## The core

The core is Flutter's architecture rebuilt for cells. It keeps four trees, each
with one job (expanded in [the architecture overview](architecture.md#the-architecture)):

| Tree | Job |
|------|-----|
| **widget** | immutable configuration — cheap, throwaway descriptions |
| **element** | identity + state — the durable spine; your `setState` lives here |
| **render** | layout + paint over a **cell grid** — constraints down, sizes up |
| **semantics** | the machine-readable shadow (roles/state/actions) for tests + agents |

From a state change the pipeline runs:

```
rebuild dirty subtree → layout → paint into a damage-tracked CellBuffer → target
```

The crucial property: **the core never mentions a terminal.** Its output is a
`CellBuffer` — a grid where each cell is a grapheme plus style (fg/bg, bold, dim,
inverse…). What happens to that buffer is the target's business.

### The core is `dart:io`-free

The two libraries that make up the core compile to JavaScript:

- **`package:fleury/fleury_core.dart`** — the framework primitives: widgets,
  elements, render objects, the cell model, theme, borders, edge insets.
- **`package:fleury/fleury_host.dart`** — the **host SPI** (re-exports the core
  plus the runtime seams a target plugs into: frame scheduler, input dispatcher,
  frame-presentation hooks, semantics owner).

Neither touches `dart:io`. That is what makes the browser targets possible at
all — see [Serving and embedding](serving-and-embedding.md).

## Targets (hosts)

A target — also called a **host** — is the code that supplies the platform
pieces behind the host SPI: a surface to paint into, an input source, a clock /
frame scheduler, clipboard, and (optionally) a place to project semantics.

| Target | Library | Paints the CellBuffer to… | Platform |
|--------|---------|---------------------------|----------|
| **Terminal** | `package:fleury/fleury.dart` (`runTui`) | diffed **ANSI** via the Posix/Windows native drivers | `dart:io` |
| **Web / DOM** | `package:fleury_web` (`runTuiWebDom`) | retained **DOM** rows + a parallel semantic DOM | dart2js |
| **Remote** | `fleury serve` (server) + DOM client | streamed **cell-diff frames** over a socket | server `dart:io`, client dart2js |
| **xterm bridge** (legacy) | `runTuiWeb` (`WebTerminalDriver`) | ANSI into an xterm.js-style transport | dart2js |

The terminal target diffs successive cell buffers and emits byte-frugal ANSI.
The web/DOM target applies the *same damage* to retained DOM row elements. A
test oracle asserts both surfaces render the same tree, so the targets can't
silently diverge.

## The web-safety boundary (practical rule)

The native runtime — `runTui`, the terminal drivers, stdout/stderr **log
capture**, **process** tasks, the external editor, and **file I/O** — lives
*above* the host SPI and pulls in `dart:io` (and, via the Windows driver,
`dart:ffi`). It is exported from the `fleury.dart` umbrella, **not** from
`fleury_host.dart`.

That gives a simple rule for any code that might run in the browser:

> Import **`package:fleury/fleury_host.dart`**, not `package:fleury/fleury.dart`.
> The host SPI has everything a widget needs; the umbrella drags in the native
> runtime and stops the program from compiling to JS.

`fleury_widgets` follows exactly this split:

- **51 web-safe widgets** (charts, lists, inputs, layout, viewers, agent
  surfaces…) import the host SPI and compile to JS.
- **7 native-only widgets** keep `fleury.dart` because they genuinely need the
  platform: `file_browser`, `file_picker`, `form`, `image` (file I/O),
  `log_region`, `terminal_output_region` (log capture), `process_panel`
  (process running). These can render over the **remote** target (the server has
  `dart:io`) but not as a client-side bundle.

## Package map

| Package | Role | Web-safe? |
|---------|------|-----------|
| `fleury` (`fleury_core`, `fleury_host`) | the core + host SPI | ✅ core/SPI |
| `fleury` (`fleury.dart` umbrella) | + native runtime: `runTui`, drivers, log/process/file, **serve** | ❌ `dart:io` |
| `fleury_widgets` | the widget library | ✅ 51 / ❌ 7 |
| `fleury_web` | the web/DOM target + the remote browser client | ✅ dart2js |

## Why this matters

Because the core is target-agnostic and `dart:io`-free, one app definition gets
you: a real terminal app, a browser app compiled with dart2js, and a remotely
streamed session — with no second implementation and a parity oracle keeping
them honest. The next doc,
[Serving and embedding](serving-and-embedding.md), covers the two browser
paths in detail.
