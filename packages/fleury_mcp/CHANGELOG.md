# Changelog

## 0.1.0

Initial release.

An MCP (Model Context Protocol) server that drives a running Fleury app through
its semantic tree.

- **Read** the UI: `get_ui` and `find_nodes`, plus the `fleury://ui/tree`
  resource — roles, labels, values, state, and the actions each node supports.
- **Drive** it: `invoke_action`, `set_value`, `type_text`, `press_key`,
  `resize`, and `wait_for_change`.
- Token-efficient, bounded payloads (node cap + trimmed fields); a stale-id guard
  that fails safe instead of mis-targeting; structured + text tool results
  (MCP 2025-06-18); clean lifecycle teardown on disconnect/SIGINT/SIGTERM.
