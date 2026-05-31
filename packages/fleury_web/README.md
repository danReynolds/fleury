# Fleury Web

Run [fleury](../fleury) apps in a browser via
[xterm.js](https://xtermjs.org). This is the foundation for live, interactive
documentation — embed a real, running widget on a web page instead of a
screenshot.

## How it works

fleury's core (`package:fleury/fleury_core.dart`) is free of
`dart:io`, so it compiles to JavaScript. This package supplies the missing
platform piece:

- **`WebTerminalDriver`** implements the framework's `TerminalDriver` over an
  xterm.js terminal: frames go to `term.write`; keystrokes from `term.onData`
  run through the same `InputParser` the native driver uses and surface as
  `TuiEvent`s; `term.onResize` drives `ResizeEvent`.
- **`runTuiWeb`** is the web counterpart of `runTui` — it mounts the app,
  renders on demand, and diffs each frame to the driver.

The host page creates the terminal and exposes it as
`globalThis.fleuryTerminal` (see `web/index.html`); the Dart side picks it up
from there.

## Run the demo

```sh
dart pub get
dart compile js web/main.dart -o web/main.dart.js

# serve the web/ directory with any static file server, e.g.:
dart pub global activate dhttpd
dhttpd --path web
# then open the printed http://localhost:8080
```

You'll get a focused counter you can drive with the arrow keys — input,
state, layout, ANSI, and rendering all running live in the browser.

> Like the POSIX driver (which needs a real TTY), `WebTerminalDriver` needs a
> real xterm.js instance, so it's exercised in a browser rather than the VM
> test suite. The byte-level parsing it delegates to `InputParser` is covered
> there.
