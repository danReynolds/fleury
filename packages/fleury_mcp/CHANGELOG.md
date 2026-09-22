# Changelog

## 0.1.0

Initial release.

An MCP (Model Context Protocol) server that drives a running Fleury app through
its semantic tree.

- **Read** the UI: `get_ui` and `find_nodes`, plus the `fleury://ui/tree`
  resource — roles, labels, values, state, and the actions each node supports.
- **Drive** it: `invoke_action`, `set_value`, `resize`, and
  instance-scoped-revision-aware `wait_for_change`; legacy `2025-06-18`
  clients also retain the focus-relative `type_text` and `press_key` tools.
- Token-efficient, bounded payloads (node cap + trimmed fields); a stale-id guard
  that rejects observable positional recycling (semantically identical logical
  replacements require distinct keys or stable semantics ids); explicit
  `targetRef` claims remove the connection-global last-read dependency.
- MCP `2026-07-28` discovery, per-request protocol negotiation, modern result
  envelopes and cache hints, while retaining the `2025-06-18` initialization
  path for existing hosts.
- Strict input schemas, baseline object output schemas, human-readable tool
  titles, and conservative read/mutation annotations.
- Structured + text tool results; clean lifecycle teardown on
  disconnect/SIGINT/SIGTERM.
