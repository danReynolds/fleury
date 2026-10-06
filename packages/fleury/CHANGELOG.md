# Changelog

## Unreleased

- Optimized web builds (`dart compile js -O2` and up) no longer give routes a
  minified class name such as `minified:jg` as their accessible name, which a
  screen reader announced for every page; those routes are left unnamed.
  Native, test, and unminified builds still name a route after its screen class.

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
