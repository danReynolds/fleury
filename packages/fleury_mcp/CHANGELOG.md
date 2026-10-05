# Changelog

## 0.1.0

Initial public release, October 5, 2026. Requires Dart 3.10.4 or later and
exactly `fleury 0.1.0` for the matching first-party wire protocol.

- Drive a spawned Fleury app through its semantic tree, or attach to a human's
  native development session started with `fleury run --agent` using
  `--attach`, optional `--project`, and `--session`. Disconnecting an attached
  client preserves the app and its terminal.
- Read roles, labels, values, state, and supported actions with `get_ui`,
  `find_nodes`, and the `fleury://ui/tree` resource. Focus inspection names the
  deepest focused control rather than a surrounding region.
- Inspect compact cell/style runs, widget ancestry, layout, and semantics from
  the same frame with `get_inspection`. Use `get_dev_status`, `reload_app`,
  and `restart_app` for attached development sessions; restart invalidates old
  control references.
- Invoke semantic actions, set values, resize, and wait for UI changes.
  Instance-scoped revisions and explicit `targetRef` claims guard actions
  against stale observations. Distinct logical replacements still need stable
  keys or semantics IDs to distinguish otherwise identical controls.
- Bound and trim inspection payloads; return structured and text results with
  strict input schemas, output schemas, and read/mutation annotations.
- Support MCP `2026-07-28` discovery and per-request negotiation alongside
  legacy `2025-06-18` initialization. Legacy clients also retain the
  focus-relative `type_text` and `press_key` tools.
- Report long-running actions as pending after two seconds, prevent duplicate
  invocation on the busy control, and allow other actions to answer dialogs.
- Clean up spawned sessions on disconnect, SIGINT, and SIGTERM. Native
  attachment targets local macOS/Linux development, not production shared
  sessions.
