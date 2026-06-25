---
title: Driving with an agent (MCP)
description: Point any MCP host at a Fleury app and let an AI agent read and operate it — no app changes, no screen-scraping.
---

Any Fleury app can be driven by an AI agent through the [Model Context
Protocol](https://modelcontextprotocol.io) — the open standard hosts like Claude
Code and Claude Desktop already speak. The agent reads your UI as roles, labels,
values, and the actions each node supports, then operates it by invoking those
actions. No ANSI scraping, no guessed keystrokes.

This guide is the *how*. For *why* it works — the semantic tree underneath — see
[Built for agents](/architecture/agents-and-semantics/).

## Your app needs no MCP code

Drivability is a property of the framework, not something you wire up. You add no
dependency and write no server code — a normal `runTui` app is already drivable,
because every widget contributes semantics and `runTui` already speaks the remote
wire when a host launches it.

```dart
import 'package:fleury/fleury.dart';

void main() => runTui(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});
  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text('Count: $_count'),
      Semantics(
        id: const SemanticNodeId('increment'),     // a stable handle (optional)
        role: SemanticRole.button,
        label: 'Increment',
        actions: const {SemanticAction.activate},
        onAction: (_) => setState(() => _count++),
        child: const Text('[ Increment ]'),
      ),
    ],
  );
}
```

High-level widgets like `Button`, `TextInput`, `DataTable`, and `Select` already
contribute their role, label, and actions — a `Button(label: …, onPressed: …)` is
agent-drivable as-is. The one thing worth adding is a stable `id:` on nodes that
matter (see [below](#make-your-app-drive-well)).

## Install the driver

The driver is a separate executable, `fleury_mcp`.

```sh
# Once published to pub.dev — add it as a dev-dependency and run it:
#   dev_dependencies:
#     fleury_mcp: ^0.1.0
# then `dart run fleury_mcp -- dart run bin/my_app.dart`

# Today, from a Fleury checkout — put it on your PATH:
dart pub global activate --source path packages/fleury_mcp
```

## Connect an MCP host

Point a host at any app — the app needs no changes:

```sh
claude mcp add my-app -- fleury_mcp -- dart run bin/my_app.dart
```

or configure it like any other MCP server:

```json
{
  "mcpServers": {
    "my-app": {
      "command": "fleury_mcp",
      "args": ["--", "dart", "run", "bin/my_app.dart"]
    }
  }
}
```

Then ask the agent to read and operate the app. It will call `get_ui` to see the
tree, then `invoke_action` / `set_value` / `type_text` to drive it, re-reading
after each step.

### Faster startup

Launching via `dart run` JIT-compiles your app on the first read (a few seconds);
`fleury_mcp` prints a one-time hint when it sees this. Compile once for a
near-instant launch:

```sh
dart compile exe bin/my_app.dart -o my_app
claude mcp add my-app -- fleury_mcp -- ./my_app
```

## What the agent can do

| | |
|---|---|
| **resource** `fleury://ui/tree` | The current semantic tree — the same artifact `get_ui` returns. |
| `get_ui` | Read the whole tree (roles, labels, values, state, supported actions). Call first, and after each action. |
| `find_nodes` | Query by role / label substring / supported action / focus / selection — the lean path on a large screen. |
| `invoke_action` | Invoke a `SemanticAction` on a node by id (activate, focus, select, submit, increment, open/close, …). |
| `set_value` | Set a value in one call — text fields, checkboxes/toggles, sliders/steppers, selects, date pickers, or a table's row index. |
| `type_text` | Type into the focused input. |
| `press_key` | A named key (enter, tab, arrows, f1–f12) or a chord (ctrl/alt/shift). Prefer `invoke_action` when a semantic action exists. |
| `resize` | Resize the viewport to reflow the layout and surface more rows of a windowed widget. |
| `wait_for_change` | Block until the UI updates on its own (a ticking dashboard, a streaming response) instead of polling. |

Results come back both as text JSON and as MCP `structuredContent`. Payloads are
node-capped and token-trimmed, so a large screen can't blow the agent's context;
`find_nodes` is the lean path for drilling into big trees.

## Make your app drive well

The app works with zero effort; these make the agent's job easier:

- **Pin stable ids** on the nodes that matter, with `Semantics(id: …)` or a
  `Key`. A node with a keyed ancestor keeps a stable id across rebuilds; a fully
  unkeyed node falls back to a positional id that can shift as the tree changes.
  A `Semantics(id: 'submit')` is a durable handle. (The server guards against
  acting on a *stale* positional id, so the worst case is a clear "re-read and
  retry", not a mis-click.)
- **Give nodes meaningful labels** — labels are how the agent recognizes a node.
- **Hide decorative or off-screen chrome** with `ExcludeSemantics` so it doesn't
  clutter what the agent reads.

## On both surfaces

Because the agent drives at the semantic layer — below the display surface — it
operates the **same app whether you'd otherwise view it in a terminal or a
browser** ([`fleury serve`](/architecture/serving-and-embedding/)). There is no
separate "CLI" vs "web" integration.
