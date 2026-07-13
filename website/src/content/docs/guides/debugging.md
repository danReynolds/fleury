---
title: Debugging
description: The built-in debug shell — a toggleable sidebar with live frame stats, the semantic tree, rebuild diagnostics, captured logs, and runtime errors.
---

Every fleury app ships with a **debug shell**: a dockable sidebar you can
toggle at any time during development, with no setup, no separate process, and
full support over SSH (it renders in the same terminal). It is on by default
in development runs and off by default in release builds.

## Try it hands-on

The **debug playground** sample simulates the situations the shell is built to
diagnose — a janky frame, an uncaught error, a log burst, a continuously
repainting region — and lets you trigger each and watch the matching tab react:

```sh
dart run packages/samples/bin/samples.dart debug   # then press Ctrl+G
```

Each trigger is a semantic button, so the same app is the agent-devtools demo:
point `fleury mcp` at it and an agent can invoke a scenario, then `read_errors`
/ `read_frames` / `read_logs` to see what it just caused — your AI reading your
debugger while it drives the app.

## Toggling it

| Key | Action |
| --- | --- |
| `Ctrl+G` | Open / close the shell (docked to the right by default) |
| `F11` | Docked ↔ fullscreen (while open) |
| `F12` | Jump straight to the **Logs** tab (opens the shell if closed; pressed again on Logs, closes it) |
| `Tab` / `Shift+Tab` | Next / previous tab (while open) |
| `p` | Toggle **paint flash** — repainted regions flash so you can *see* what each frame touched (while open) |
| `/` · `s` | In the **Logs** tab: open search (type to filter, `Enter` keeps it) · cycle the source filter (all / stdout / stderr) |
| `Esc` | Clear a Logs search, else fullscreen → back to docked |

The shell's hotkeys are routed *before* the app's input dispatcher, so they
work everywhere — including inside modal routes. While the shell is open,
these keys belong to the shell; close it (`Ctrl+G`) to give `Tab` and `p`
back to the app.

## The tabs

- **Live** — frame number, slow-frame count (>16ms), approximate FPS, and
  per-phase timings (build / layout / paint) with recent history.
- **Tree** — the live **semantic tree** (the same agent-legible tree your
  tests and `fleury mcp` consume), plus the terminal diagnosis: detected
  capabilities, color mode, image protocol, session type. Arrow keys move the
  node cursor; `Home` resets it.
- **Rebuilds** — what dirtied each frame: invalidation sources, last phase
  costs, and a recent-frames table. Pair with paint flash (`p`) to hunt
  unnecessary repaints.
- **Logs** — everything the stray-output capture caught: `print`s, logger
  writes, and even **native/FFI library output** (fleury captures at the file
  descriptor, so a C library's `printf` can't corrupt your frames — it lands
  here instead, and replays to the terminal after exit). Press `/` to search
  (matches highlight in place; `Enter` keeps the filter, `Esc` clears it) and
  `s` to cycle the source filter (all / stdout / stderr). On `fleury serve`
  sessions stray output goes to the server's console instead, so this tab is
  primarily a local-terminal tool.
- **Errors** — recent uncaught runtime errors (a throwing event handler, a
  failed async callback), newest first with timestamps. The banner overlay
  shows the current error; this tab keeps the last 50 so an error you
  dismissed isn't gone.

## Configuring it

`DebugConfig` is public API on `runApp`:

```dart
import 'package:fleury/fleury.dart';

await runApp(
  const MyApp(),
  debug: const DebugConfig(
    startMode: DebugMode.docked,      // open on launch for dev sessions
    side: DebugPanelSide.bottom,      // or .right (default)
    panelWidth: 44,                   // cells, when docked right
    panelHeight: 14,                  // cells, when docked bottom
  ),
);
```

**Release builds are clean by default.** `DebugConfig.enabled` defaults to
`true` under the JIT (`dart run`, tests, hot reload) and `false` in product
builds (`dart compile exe`), keyed off `dart.vm.product` — a shipped binary
has no debug hotkeys or event collection unless you opt back in with
`enabled: true`.

## Agents can read the shell too

The same frame stats, captured logs, and error history are exposed to agents
through [`fleury_mcp`](https://github.com/danReynolds/fleury/tree/main/packages/fleury_mcp)
as the `read_frames`, `read_logs`, and `read_errors` tools — so an AI driving
your app over MCP can *read its devtools while it works*, not just the UI tree.
They need debug tooling enabled (the default in development runs).

## Extras

- **Stray-output hook** — take captured lines live instead of the
  replay-on-exit: `runApp(onStrayOutput: (line) => myLogFile.write(...))`.
- **Byte telemetry** — `FLEURY_BYTE_TELEMETRY=1` prints a per-frame byte
  budget summary (content vs overhead) on exit.
- **ANSI capture** — `FLEURY_ANSI_CAPTURE=/path` tees every emitted byte to a
  file for offline analysis.
- **Escape hatch** — `FLEURY_FD_CAPTURE=0` disables the descriptor-level
  stray-output capture entirely (raw behavior; stray writes go straight to
  the terminal).
- **Hyperlinks override** — `FLEURY_HYPERLINKS=1` forces real terminal
  hyperlinks on (even under tmux); `FLEURY_HYPERLINKS=0` forces them off. See
  [Terminal hyperlinks](#terminal-hyperlinks-osc-8) below.

## Terminal hyperlinks (OSC 8)

Widgets like `MarkdownText` emit **real clickable links** (the OSC 8 escape) on
terminals that support them, and fall back to plain underlined text with the
URL shown inline everywhere else — so a destination is never hidden behind a
link that doesn't work. The browser surface (`fleury serve`) always renders
links as anchors; on the terminal, support is **detected from the environment**.

**Detected terminals** (auto-enabled, default-deny for anything unlisted):

| Terminal | Detected via |
| --- | --- |
| iTerm2 (≥ 3.1) | `TERM_PROGRAM=iTerm.app` + `TERM_PROGRAM_VERSION` |
| WezTerm, Ghostty | `TERM_PROGRAM` |
| GNOME Terminal / VTE (≥ 0.50) | `VTE_VERSION ≥ 5000` |
| kitty | `KITTY_WINDOW_ID` or `TERM=xterm-kitty` |
| Windows Terminal | `WT_SESSION` |

**tmux (and other multiplexers) are suppressed by default.** OSC 8 through a
multiplexer needs an explicit `terminal-features` opt-in in your tmux config and
is unreliable without it, so detection reports links as unavailable under tmux
regardless of the outer terminal. Escape tmux, or force it with
`FLEURY_HYPERLINKS=1`.

**Override.** `FLEURY_HYPERLINKS` wins outright over detection: `1`/`true`/`yes`/
`on` forces links on (even under tmux, and on terminals Fleury can't confirm);
`0`/`false`/`no`/`off` forces them off. Leave it unset to use detection.

**Check what was detected.** `fleury diagnose` reports the exact state —
`supported`, `suppressed-under-tmux` (the outer terminal is capable but a
multiplexer is in the way), `disabled-by-override` (`FLEURY_HYPERLINKS=0`), or
`unsupported` — and the debug shell's **Tree** tab shows it alongside the other
detected capabilities.
