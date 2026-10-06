# Changelog

## 0.1.1

- `fleury serve --spawn` no longer gives up on an app that is slow to start.
  It waits until the app connects or the browser leaves, says when an app is
  still starting after 10 seconds, and shows the browser why a session failed
  to start. A page reloaded during a slow start reuses the app that was
  starting.
- An app spawned by `fleury serve` or `fleury_mcp` that exits before it
  connects has its output shown before the error. `spawnFleuryApp` accepts a
  null `connectTimeout` (no deadline) and an `onSlowStart` callback.
- Optimized web builds (`dart compile js -O2` and up) no longer give routes a
  minified class name such as `minified:jg` as their accessible name; those
  routes are left unnamed. Native, test, and unminified builds still name a
  route after its screen class.
- `fleury create` writes sources that `dart format` leaves unchanged, whatever
  the project's name. Its README points to the published CLI, gives the
  activation command for a Git checkout, and adds `fleury_mcp` as a
  development dependency for agents.
- `fleury run --help` and `fleury shell --help` print their usage and exit 0.
- The `fleury diagnose` Markdown report leaves out the local hostname and
  shows the home directory as `~`.
- The README's test example is a complete file, and the pub.dev Example tab
  shows the counter and how to run each example. The dashboard example no
  longer fails on every tick.

## 0.1.0

Initial public release, October 5, 2026. Requires Dart 3.10.4 or later.

### Framework and widgets

- Flutter-style widgets, state, context, keys, reconciliation, scopes, and
  constraint-based layout backed by a terminal-native cell renderer.
- Full widget catalog in `fleury.dart` and the browser-safe `fleury_core.dart`:
  text inputs, forms, lists, tables, trees, menus, dialogs, charts, and controls
  for agent applications, including messages, tool calls, approvals, and logs.
- Shared state with `Scope` and `Notifier`, navigation and owned overlays,
  spring animations, frame tickers, themes, and interactive control styles.
- Community presets through `themes.dart` and supported widget-authoring
  contracts through `fleury_widget_support.dart`.

### Terminal runtime

- Full-screen and inline applications with ANSI diff rendering, capability
  detection, Unicode grapheme handling, keyboard and mouse input, bracketed
  paste, focus traversal, selection, and clipboard integration.
- Terminal restoration on exit, suspend, and handoff; job-control-aware
  Ctrl+Z and `TerminalSession.suspend()` for native POSIX sessions.
- Kitty and iTerm2 image support with portable glyph rendering; experimental
  Sixel support.
- Inline sessions recover from delayed cursor reports after resize or resume.
  Nested focus detectors report focus within their descendants, and semantic
  inspection identifies the deepest focused control.
- Open `Select` menus close when their owner is replaced or removed.
  Shift+Arrow selection skips labels with no width instead of throwing.

### Development and agent tooling

- The `fleury` CLI creates tested app scaffolds, runs apps with state-preserving
  hot reload, reports runtime diagnostics, and provides browser previews and
  terminal-shell attachment.
- Hot reload remains available after a slow application startup. Debug tooling
  defaults on for source development runs and off for compiled applications.
- `fleury run --agent` exposes an opt-in local development session for
  `fleury_mcp --attach`. Agents can inspect cells, semantics, and layout from
  one frame, observe reload errors, reload, and restart while the human keeps
  ownership of the terminal.
- Semantic actions, shared `FleuryTarget` queries, stable control references,
  and redacted inspection support tests and agent clients without coordinate
  guessing. Companion packages provide test helpers, MCP, and browser hosting.

### Supported scope

- Native launch support targets modern UTF-8, xterm-compatible POSIX terminals.
  The Windows driver is preview-only.
- `fleury serve` provides a development preview. Native MCP attachment is
  development tooling; production shared-session control is not included.

This first-release summary consolidates the pre-release development notes.
Their full history remains available in Git.
