# Fleury core and targets

The [architecture overview](architecture-overview.md) covers the core → cells →
targets model. This page is the practical side of it: how the code is split
across packages, why the core compiles to JavaScript at all, and the one import
rule that keeps your widgets browser-safe.

The short version: Fleury is a **platform-neutral core** that turns your widget
tree into a `CellBuffer` — an abstract grid of styled cells — plus a set of
**targets** that paint that buffer somewhere real. Everything above the seam (the
**host SPI**) is identical regardless of where it ends up; the target is the only
part that knows about ANSI bytes, DOM nodes, or sockets.

## The core is `dart:io`-free

The core never mentions a terminal. The two libraries that make it up compile to
JavaScript:

- **`package:fleury/fleury_core.dart`** — the framework primitives: widgets,
  elements, render objects, the cell model, theme, borders, edge insets.
- **`package:fleury/fleury_host.dart`** — the **host SPI**: it re-exports the
  core plus the runtime seams a target plugs into (frame scheduler, input
  dispatcher, frame-presentation hooks, semantics owner).

Neither touches `dart:io` (nor, transitively, `dart:ffi`). That is what makes the
browser targets possible at all — the same widget code that runs in a terminal
can be compiled to JS and dropped into a page.

## Targets (hosts)

A target — also called a **host** — supplies the platform pieces behind the host
SPI: a surface to paint into, an input source, a clock / frame scheduler,
clipboard, and (optionally) a place to project semantics.

| Target | Library | Paints the `CellBuffer` to… | Platform |
|--------|---------|-----------------------------|----------|
| **Terminal** | `package:fleury/fleury.dart` (`runApp`) | diffed **ANSI** via the POSIX/Windows native drivers | `dart:io` |
| **Browser, embedded** | `package:fleury_web` (`mountApp`) | retained **DOM** rows + a parallel semantic DOM | dart2js, client-side |
| **Browser, served** | `fleury serve` + DOM client | streamed **cell-diff frames** over a socket | server `dart:io`, client dart2js |

The two browser rows differ only in *where the app runs*. **Embedded** compiles
your whole app to JavaScript and runs it in the page — no backend. **Served**
keeps the app running natively on a server (so it can use the filesystem,
processes, anything `dart:io`) and streams only the changed cells to a thin
browser client. Both paint into the same retained DOM; see
[Serving and embedding](serving-and-embedding.md) for when to choose each.

Whichever target you use, it applies the *same damage* the terminal would, and a
parity oracle asserts both surfaces render the same tree — so they can't silently
diverge.

## The web-safety boundary (practical rule)

The native runtime — `runApp`, the terminal drivers, stdout/stderr **log
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
  (process running). These can render over the **served** target (the server has
  `dart:io`) but not as a client-side bundle.

## Package map

| Package | Role | Web-safe? |
|---------|------|-----------|
| `fleury` (`fleury_core`, `fleury_host`) | the core + host SPI | ✅ core/SPI |
| `fleury` (`fleury.dart` umbrella) | + native runtime: `runApp`, drivers, log/process/file, **serve** | ❌ `dart:io` |
| `fleury_widgets` | the widget library | ✅ 51 / ❌ 7 |
| `fleury_web` | the web/DOM target + the served browser client | ✅ dart2js |

## Why this matters

Because the core is target-agnostic and `dart:io`-free, one app definition gets
you a real terminal app, a browser app compiled with dart2js, and a remotely
served session — with no second implementation, and a parity oracle keeping them
honest. Next: [Serving and embedding](serving-and-embedding.md) covers the two
browser paths in detail.
