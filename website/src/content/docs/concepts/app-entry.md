---
title: App entry points
description: runTui, runTuiWeb, and runTuiWebDom — how a widget tree starts running on each target.
---

A Fleury app is a widget tree handed to a run function. Which one you call
depends on where the app runs — a terminal, or a browser. They share a model
(mount the tree, render the first frame, then re-render on every input and every
`setState`) but differ in signature, so it's worth knowing all three.

## `runTui` — the terminal

The default. Lives in `package:fleury/fleury.dart` and drives a real terminal:

```dart
import 'package:fleury/fleury.dart';

void main() => runTui(const MyApp());
```

It takes a **widget instance** and returns a `Future<void>` that completes when
the app exits. On startup it acquires the terminal, switches it into interactive
mode (raw input, the alternate screen, hidden cursor), mounts your tree, paints
the first frame, and then renders again after every input event and every
`setState`. On exit — `Ctrl-C`, or your handler asking to stop — it restores the
terminal to exactly how it found it.

The options you'll actually reach for:

```dart
runTui(
  const MyApp(),
  onEvent: (event) {
    // Inspect every input event before the framework re-renders.
    // Return an ExitRequested to quit cleanly; null lets it through.
    return null;
  },
  globalBindings: [
    KeyBinding(KeyChord.ctrl.q, onEvent: (_) => /* quit */, label: 'Quit'),
  ],
)
```

`mode` (a `TerminalMode`, default `TerminalMode.interactive`) controls the raw-
mode/alt-screen/mouse setup; `enableHotReload` (default `true`) wires up state-
preserving hot reload under the Dart VM. Because `runTui` depends on `dart:io`,
it's exported from `fleury.dart` — *not* from the web-safe `fleury_core`.

## What `runTui` sets up (there's no `MaterialApp`)

Coming from Flutter, you might look for a `MaterialApp`/`WidgetsApp` to wrap your
root. There isn't one — `runTui` assembles the ambient scaffold itself. Before it
mounts your widget, it injects:

- a **`MediaQuery`** carrying the terminal size (rebuilt on resize),
- the **focus root**, so `Focus` and traversal work,
- **pointer routing**, so `GestureDetector` / `MouseRegion` receive mouse events,
- an **`Overlay`** for floating layers (tooltips, toasts), and
- a root **`Navigator`**, so `context.push` / `context.pop` work app-wide.

That's why navigation, focus, media queries, and the mouse "just work" with no
setup. The one thing `runTui` does **not** inject is a `Theme` — `Theme.of(context)`
returns sensible defaults until you wrap a subtree in your own (see
[Theming](/guides/theming/)).

## `runTuiWebDom` — the browser

To run the **same widget tree** client-side in a browser, compile to JavaScript
with `dart2js` and call `runTuiWebDom` from `package:fleury_web/fleury_web.dart`.
It paints into a retained DOM cell grid and — this is the part that matters for
agents and accessibility — mirrors the tree into a **semantic DOM** by default:

```dart
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final host = web.document.getElementById('app')!;
  runTuiWebDom(() => const MyApp(), hostElement: host);
}
```

Two differences from `runTui` worth flagging:

- It takes a **widget factory** (`() => const MyApp()`), not an instance.
- It returns a `Future<TuiSurfaceHost>` (a handle to the running surface), not
  `void`.

The host element must have an explicit size and a monospace font, or the grid
measures zero cells and paints nothing:

```html
<div id="app" style="width:80ch;height:24em;font-family:monospace"></div>
```

This is the path the live examples throughout these docs use — every embedded
widget on this site is the real tree, compiled with `dart2js` and mounted with
`runTuiWebDom`.

## `runTuiWeb` — the legacy browser path

`runTuiWeb` (also from `fleury_web`) is the older browser entry point that drives
an xterm-style terminal emulator rather than a DOM cell grid. It takes the same
`() => MyApp()` factory. `runTuiWebDom` is the direction of travel — prefer it
for new work; `runTuiWeb` remains for the terminal-emulator use case.

## Which one?

| Target | Function | Takes |
|---|---|---|
| Terminal (native) | `runTui` | a widget instance |
| Browser, client-side | `runTuiWebDom` | a widget factory |
| Browser, terminal-emulator | `runTuiWeb` | a widget factory |

There's also a *third* way to get an app into a browser without compiling it
yourself — `fleury serve`, which runs your native app and streams its frames to a
browser. That's a shipping decision rather than an entry point; see
[Deployment & distribution](/guides/deployment/) for when to embed (client-side
`runTuiWebDom`) versus serve.
