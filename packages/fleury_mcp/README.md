# fleury_mcp

A [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server that
drives a running [Fleury](https://github.com/danReynolds/fleury) terminal-UI app
through its **semantic tree** — so any MCP host (Claude Code, Claude Desktop, …)
can read the UI and operate it.

No screen-scraping. The agent reads roles, labels, values, and the *actions each
node supports*, then invokes those actions by id — the same accessible semantics
Fleury already exposes to the browser and to tests.

```
┌─────────────┐   JSON-RPC/stdio   ┌────────────┐   semantic wire   ┌──────────┐
│  MCP host   │ ◀───────────────▶  │ fleury_mcp │ ◀──────────────▶  │ your app │
│ (the agent) │                    │  (server)  │                   │ (runTui) │
└─────────────┘                    └────────────┘                   └──────────┘
```

## Quick start

`fleury_mcp` launches your app and bridges it. The app just needs to call
`runTui(...)` — it auto-discovers the server over `FLEURY_HANDLE`, the same way
`fleury serve` spawns it.

```bash
# From a Fleury checkout: put `fleury_mcp` on your PATH.
dart pub global activate --source path packages/fleury_mcp

# Drive an app:
fleury_mcp -- dart run my_app.dart
```

stdout is a clean JSON-RPC channel; your app's own `print`/log output is
forwarded to stderr so it can't corrupt the protocol.

### Add it to Claude Code

```bash
claude mcp add fleury -- fleury_mcp -- dart run my_app.dart
```

Then ask the agent to read and operate your app. It will call `get_ui` to see
the tree, then `invoke_action` / `set_value` / `type_text` to drive it.

### Faster startup (recommended)

Launching via `dart run` JIT-compiles your app on the first read (a few
seconds). AOT-compile once for a near-instant, repeatable launch:

```bash
dart compile exe my_app.dart -o my_app
fleury_mcp -- ./my_app
```

`fleury_mcp` prints a one-time hint when it detects a `dart run` launch.

## Options

```
fleury_mcp [--cols=<n>] [--rows=<n>] -- <command ...>
```

- `--cols` / `--rows` — the viewport (terminal grid) the app lays out against.
  A taller grid surfaces more rows of windowed widgets (long tables, logs) in
  the semantic tree. Default `80×24`.
- `--` — separates `fleury_mcp`'s flags from the app command (recommended when
  the app takes its own flags).

## What the agent gets

**Resource**

| URI | Description |
|-----|-------------|
| `fleury://ui/tree` | The app's current semantic tree as JSON — the same artifact `get_ui` returns. |

**Tools**

| Tool | What it does |
|------|--------------|
| `get_ui` | Read the current UI as a semantic tree (roles, labels, values, state, supported actions). Call first, and after each action. |
| `find_nodes` | Query the tree by role / label substring / supported action / focus / selection — handy on a large screen. |
| `invoke_action` | Invoke a `SemanticAction` on a node by id (activate, focus, select, submit, increment, open/close, …). The node must advertise it. |
| `set_value` | Set a value in one call — text fields, checkboxes/toggles, sliders/steppers, selects, date pickers, or a table's row index. |
| `type_text` | Type into the focused input. |
| `press_key` | Press a named key (enter, tab, arrows, f1–f12, …) or a chord (with ctrl/alt/shift). Prefer `invoke_action` when a semantic action exists. |
| `resize` | Resize the viewport to reflow the layout and surface more windowed rows. |
| `wait_for_change` | Block until the UI updates on its own (a ticking dashboard, a streaming response) instead of polling. |

Results come back both as text JSON (the model-facing channel) and as MCP
`structuredContent` for programmatic clients.

## How it stays robust & cheap

- **Stable, compact ids.** Nodes are addressed by a derived id that survives
  rebuilds and reorders when the app uses keys or `Semantics(id:)`; auto-ids are
  compacted to keep the payload small. A positional id that comes to denote a
  *different* node after the tree shifts is caught by a stale-reference guard
  rather than mis-targeted.
- **Bounded payloads.** `get_ui` and every action result are node-capped and
  token-trimmed (no pixel bounds, no value that just repeats a label), so a
  large screen can't blow the agent's context. `find_nodes` is the lean path for
  drilling into big trees.
- **Clean lifecycle.** The app subprocess is torn down on disconnect, SIGINT, or
  SIGTERM; a connect-but-never-render app fails fast with a clear message.

## Status

Pre-1.0, developed in the Fleury monorepo (`publish_to: none`, path dependency
on `fleury`). The protocol surface is stable and verified against the MCP
Inspector and a host-process end-to-end harness. See
[`docs/agents-and-semantics.md`](../../docs/agents-and-semantics.md) for the
broader semantics story.
