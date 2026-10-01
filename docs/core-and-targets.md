# Fleury core and targets

The [architecture overview](architecture-overview.md) covers the core → cells →
targets model, and the [architecture deep dive](architecture-deep-dive.md)
explains the retained runtime underneath it. This page is the practical side of
that architecture: how the code is split across packages, why the core compiles
to JavaScript at all, and the one import rule that keeps your widgets
browser-safe.

The short version: Fleury has a platform-neutral core that turns your widget
tree into a `CellBuffer` — an abstract grid of styled cells — and a set of
**targets** that paint that buffer somewhere real. The shared framework sits
behind the **host SPI**; hosts supply platform input and presentation services.
Core includes pure ANSI encoding, while targets own writing bytes, updating DOM
nodes, and opening sockets.

## The core is `dart:io`-free

The platform-neutral libraries compile to JavaScript without native I/O:

- **`package:fleury/fleury_core.dart`** — the framework primitives: widgets,
  elements, render objects, the cell model, theme, borders, edge insets.
- **`package:fleury/fleury_host.dart`** — the **host SPI**: it re-exports the
  core plus the runtime seams a target plugs into (frame scheduler, input
  dispatcher, frame-presentation hooks, semantics owner).
- **`package:fleury/fleury_wire.dart`** — the explicitly unstable frame,
  codec, and transport contracts used by first-party browser and agent peers.
  It is public so those packages never reach through `src/`, but it is a
  lockstep surface for matching Fleury builds, not part of the supported host
  SPI.

None of these touches `dart:io` (nor, transitively, `dart:ffi`). That is what
makes the browser targets possible at all — the same widget code that runs in a
terminal can be compiled to JS and dropped into a page.

## Targets

A **target** supplies the platform pieces behind the host SPI: a surface to paint
into, an input source, a clock and frame scheduler, a clipboard, and (optionally)
somewhere to project semantics.

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

The targets share frame production and derive output from the changed cells.
Parity tests check the browser DOM against the core cell buffer through scroll
and overlay sequences, and an equivalence test checks that the terminal's ANSI
output reproduces the buffer. Host-specific behavior such as terminal
capabilities and browser focus still needs testing on the supported platforms.

## The web-safety boundary

The native runtime — `runApp`, the terminal drivers, stdout/stderr **log
capture**, the external editor, and **file I/O** — lives
*above* the host SPI and pulls in `dart:io` (and, through the POSIX and Windows
drivers and the `stdio` package that captures output, `dart:ffi`). It is
exported from the `fleury.dart` umbrella, **not** from `fleury_host.dart`.

That gives a simple rule for any code that might run in the browser:

> Import **`package:fleury/fleury_core.dart`**, not `package:fleury/fleury.dart`.
> The core has everything a widget or app needs; the umbrella drags in the
> native runtime and stops the program from compiling to JS. Reserve
> `fleury_host.dart` for code that *hosts* a Fleury tree — a platform target,
> a serve bridge — not for application UI; what it adds beyond the core is
> host machinery whose API is versioned for targets, not apps.

`fleury_core.dart` includes the complete widget catalog:

- **Every widget is web-safe** — charts, lists, inputs, layout, document
  viewers, log views, and agent surfaces all compile to JS and run in a browser.
  A widget whose usual data comes from the platform takes that source as a
  parameter instead of reaching for `dart:io`:
  - `FileBrowser` and `FilePicker` read directories through a `FileSource`.
    Natively they default to `LocalFileSource`, the local disk. In a browser,
    pass one: a `MemoryFileSource`, or your own implementation over data the
    app already has.
  - `LogRegion` and `TerminalOutputRegion` render log entries and a
    `LogBuffer`. `runApp` fills that buffer from captured stdout and stderr; a
    browser app can feed one itself.
  - `Image` loads bytes or decoded pixels anywhere; only `Image.file` needs the
    native filesystem, so browser apps load bytes asynchronously and use
    `Image.bytes` or `Image.decoded`.
- **`LocalFileSource` is native-only.** Import `fleury.dart` to construct one.
  The shared `fleury_core.dart` import exports every widget without native I/O;
  a test walks the browser-selected imports to keep that guarantee.

## Package map

Keyed by the import you write. Core, native hosting, widget support, and themes
are libraries of the one `fleury` package, which also contains the full widget
catalog. Browser hosting, testing, and MCP are optional companion packages.

| Import | What it adds | Web-safe? |
|--------|--------------|-----------|
| `fleury/fleury_core.dart` | framework primitives and the cell model | ✅ |
| `fleury/fleury_host.dart` | the above, plus the host SPI a target plugs into | ✅ |
| `fleury/fleury_host_io.dart` | the host SPI plus the supported contracts a native process host uses to spawn and supervise a Fleury app (`spawnFleuryApp`) | ❌ — pulls in `dart:io` |
| `fleury/fleury_wire.dart` | explicitly unstable remote frames/codecs/transports for matching first-party peers | ✅ |
| `fleury/fleury.dart` | core + stable host SPI + the native runtime: `runApp`, terminal drivers, file/process/log | ❌ — pulls in `dart:io` |
| `fleury/fleury_widget_support.dart` | supported contracts for custom widget libraries | ✅ |
| `fleury/themes.dart` | optional community palette presets | ✅ |
| `fleury_web` | the web/DOM target and the served browser client | ✅ — compiled with dart2js |
| `fleury_test` | `testWidgets`, the headless `FleuryTester`, semantic matchers, and golden files | ❌ — a dev dependency for VM tests; goldens use `dart:io` |
| `fleury_mcp` | the `fleury_mcp` MCP server executable and its library (`FleuryAppBridge`, `McpServer`) | ❌ — a native process that spawns your app |

## Primitives and the bundled catalog

Core owns the primitives needed to implement a widget library: layout, text,
editing, focus, input, selection, scrolling, overlays, navigation, animation,
semantics, and theme roles. `Button`, `TextInput`, `TextArea`, and `Spinner` also
provide small terminal defaults so a useful app can depend on core alone.
`FleuryApp`, its status row, and output-capture views remain optional helpers;
a custom tree does not need to adopt an application shell.

The same package bundles forms, checkboxes and selectors, pickers, menus,
dialogs, tables, charts, document views, and workflow UI. Both `fleury.dart`
and `fleury_core.dart` export this catalog, so adding a richer control does not
require another dependency or import.

Catalog implementations live in `packages/fleury/lib/src/catalog`, examples in
`example/catalog`, and benchmarks in `benchmark/catalog`. Consumer tests live
in `packages/fleury_test/test/catalog`; this avoids making the first core
publication depend on its own test companion. Keep catalog files grouped and
compose them from the framework contracts so a future extraction stays practical.
The private `src/primitives.dart` export list stays independent of the catalog;
`fleury_core.dart` combines both for app authors.

The catalog's component theme and `FleuryApp` are optional. Community palettes
live in the opt-in `package:fleury/themes.dart` library; bundling controls does
not select an application's appearance.

### Implementing a widget library

Import `package:fleury/fleury_widget_support.dart` alongside `fleury_core.dart`
for the supported widget-authoring contracts:

- `FocusableControl` supplies focus, hover/pressed state, keyboard/pointer and
  semantic activation. Its builder owns the entire appearance; it adds no
  button border, padding, or application shell.
- `FormControlRegistration` and `FormControlScope` connect custom value controls
  to form validation. `FocusableControl(participatesInForm: true)` handles this
  for activation controls.
- `CellStyleState` and `resolveCellStyle` resolve the same interactive style
  cascade as core controls. `revealInScrollViews` reveals a laid-out target.
- `dependOnScope` supports subscribing widget accessors such as `Form.of`;
  `readScope` performs an imperative lookup without a rebuild subscription.
  Ordinary application builds use `context.scope<T>()`.
- `projectDisplayText` gives custom painters the spelling to measure and paint
  for a surface's text policy. Preserve the original text for semantics/copy,
  and sanitize untrusted text before display projection.

These APIs follow the package's version compatibility contract, including for
third-party widget libraries. Consumer tests use these imports to exercise
custom-control focus, semantics, and form behavior.
`fleury_internal.dart` remains for repository tests/profiling, with no external
compatibility promise. Browser and MCP wire peers remain exact-pinned because
`fleury_wire.dart` is a separate, explicitly unstable protocol surface.

## Why this matters

Because the core is target-agnostic and `dart:io`-free, one app definition gets
you a real terminal app, a browser app compiled with dart2js, and a remotely
served session, with a shared rendering pipeline and tests that check the
terminal and browser output against the core cell buffer. Next:
[Serving and embedding](serving-and-embedding.md) covers the two
browser paths in detail.
