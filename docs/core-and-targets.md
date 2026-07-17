# Fleury core and targets

The [architecture overview](architecture-overview.md) covers the core → cells →
targets model, and the [architecture deep dive](architecture-deep-dive.md)
explains the retained runtime underneath it. This page is the practical side of
that architecture: how the code is split across packages, why the core compiles
to JavaScript at all, and the one import rule that keeps your widgets
browser-safe.

The short version: Fleury **has** a platform-neutral core that turns your widget
tree into a `CellBuffer` — an abstract grid of styled cells — and a set of
**targets** that paint that buffer somewhere real. Everything above the seam (the
**host SPI**) is identical no matter where the app ends up; the target is the only
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

## Targets

A **target** supplies the platform pieces behind the host SPI: a surface to paint
into, an input source, a clock and frame scheduler, a clipboard, and (optionally)
somewhere to project semantics. *(The seam is named the host SPI after the
`fleury_host.dart` library that defines it; the pluggable implementation on the
other side is the target.)*

| Target | How you run it | Paints the `CellBuffer` to… | Platform |
|--------|----------------|-----------------------------|----------|
| **Terminal** | `package:fleury/fleury.dart` (`runApp`) | diffed **ANSI** via the POSIX/Windows native drivers | `dart:io` |
| **Browser, embedded** | `package:fleury_web` (`mountApp`) | retained **DOM** rows + a parallel semantic DOM | dart2js, client-side |
| **Browser, served** | `fleury serve` + DOM client | streamed **cell-diff frames** over a socket | server `dart:io`, client dart2js |

The two browser rows differ only in *where the app runs*. **Embedded** compiles
your whole app to JavaScript and runs it in the page — no backend. **Served**
keeps the app running natively on a server (so it can use the filesystem,
processes, anything `dart:io`) and streams only the changed cells to a thin
browser client. Both paint into the same retained DOM; see
[Serving and embedding](serving-and-embedding.md) for when to choose each.

Whichever target you use, it applies the same *damage* — the set of changed cells
— that the terminal would, and a parity oracle asserts both surfaces render the
same tree, so they can't silently diverge.

## The web-safety boundary

The native runtime — `runApp`, the terminal drivers, stdout/stderr **log
capture**, **process** tasks, the external editor, and **file I/O** — lives
*above* the host SPI and pulls in `dart:io` (and, via the Windows driver,
`dart:ffi`). It is exported from the `fleury.dart` umbrella, **not** from
`fleury_host.dart`.

That gives a simple rule for any code that might run in the browser:

> Import **`package:fleury/fleury_core.dart`**, not `package:fleury/fleury.dart`.
> The core has everything a widget or app needs; the umbrella drags in the
> native runtime and stops the program from compiling to JS. Reserve
> `fleury_host.dart` for code that *hosts* a Fleury tree — a platform target,
> a serve bridge — not for application UI; what it adds beyond the core is
> host machinery whose API is versioned for targets, not apps.

`fleury_widgets` follows exactly this split:

- **Most widgets are web-safe** — charts, lists, inputs, layout, document
  viewers, agent surfaces. They import the host SPI and compile to JS.
- **A few are native-only**, because they genuinely touch the platform: file I/O,
  process execution, and stdout/stderr log capture. Examples: `FileBrowser`,
  `FilePicker`, `Image`, `ProcessPanel`, `LogRegion`, `TerminalOutputRegion`.
  These can render over the **served** target — the server has `dart:io` — but
  can't compile into a client-side bundle.
- **`WorkflowSnapshot` is a supporting model, not a widget or an I/O service.**
  Its current `LogEntry` dependency lives in the native-only log library, so it
  is also omitted from `fleury_widgets_web.dart` today. Use it in terminal or
  served apps until that model dependency is split onto the web-safe surface.

## Package map

Keyed by the import you write. The first three are libraries of the one `fleury`
package — each row adds to the one above it; `fleury_widgets` and `fleury_web` are
separate packages.

| Import | What it adds | Web-safe? |
|--------|--------------|-----------|
| `fleury/fleury_core.dart` | framework primitives and the cell model | ✅ |
| `fleury/fleury_host.dart` | the above, plus the host SPI a target plugs into | ✅ |
| `fleury/fleury.dart` | the above, plus the native runtime: `runApp`, terminal drivers, `serve`, file/process/log | ❌ — pulls in `dart:io` |
| `fleury_widgets` | the widget library | ✅ mostly — a few native-only |
| `fleury_web` | the web/DOM target and the served browser client | ✅ — compiled with dart2js |

## Why this matters

Because the core is target-agnostic and `dart:io`-free, one app definition gets
you a real terminal app, a browser app compiled with dart2js, and a remotely
served session — with no second implementation, and a parity oracle keeping them
honest. Next: [Serving and embedding](serving-and-embedding.md) covers the two
browser paths in detail.
