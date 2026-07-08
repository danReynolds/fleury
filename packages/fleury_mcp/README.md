# fleury_mcp

A [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server that
drives a running [Fleury](https://github.com/danReynolds/fleury) terminal-UI app
through its **semantic tree** — so any MCP host (Claude Code, Claude Desktop, …)
can read the UI and operate it.

No screen-scraping. The agent reads roles, labels, values, and the *actions each
node supports*, then invokes those actions by id — the same accessible semantics
Fleury already exposes to the browser and to its testing API.

```
┌─────────────┐   JSON-RPC / stdio   ┌────────────┐   semantic wire   ┌──────────┐
│  MCP host   │ ◀─────────────────▶  │ fleury_mcp │ ◀──────────────▶  │ your app │
│ (the agent) │   get_ui, actions…   │  (server)  │   SEMANTICS /     │ (runApp) │
└─────────────┘                      └────────────┘   INPUT frames    └──────────┘
```

## How it works

A Fleury app builds a widget tree, and **every widget already contributes
accessible semantics** — a role, a label, a value, the actions it supports. That
same semantic tree powers Fleury's browser accessibility mirror and its testing
API; `fleury_mcp` is a third consumer of it.

The connection reuses the wire `fleury serve` already speaks:

1. **`runApp` auto-detects `FLEURY_HANDLE`.** When a host sets that env var,
   the app runs in *remote mode* — instead of drawing to a terminal it streams
   `SEMANTICS` frames over a private Unix socket and accepts `INPUT_EVENT` /
   `SEMANTIC_ACTION` frames back. This is built in; the app opts into nothing.
2. **`fleury_mcp` spawns your app** with `FLEURY_HANDLE` pointed at a socket it
   owns, becomes the peer on that wire, and re-exposes the live semantic tree
   and its actions as MCP **tools** + a **resource** over JSON-RPC/stdio.
3. It **ignores the visual frames** (cells, images) entirely — an agent reads
   meaning, not pixels.

Because it operates at the *semantic* layer — below the display surface — it
drives the **same app whether you'd otherwise view it in a terminal or a
browser** (`fleury serve`). There is no separate "CLI" vs "web" integration.

> **Why the fit is this clean.** The semantic tree wasn't built for agents — it's
> the same roles / labels / values / actions structure Fleury already produces
> for its accessibility mirror and its testing API. And that's *exactly* what an
> agent needs: **what's here** (roles), **what it says** (labels/values), **what
> I can do** (actions). So the mapping is nearly 1:1 — the tree **is** the
> resource, the `SemanticAction`s **are** the tools — and `fleury_mcp` is a thin
> shim over an existing, tested foundation, not a separate agent subsystem bolted
> on. The same property makes it cheap: the agent reads structured *meaning*, not
> a screen-scrape of cells. Most *terminal* UIs render cells directly, leaving an
> agent to scrape ANSI; Fleury already produces a semantic tree for accessibility
> and testing, so agents read and drive it the same structured way.

## Your app needs no MCP code

Drivability is a property of the framework, not something you wire up. You add no
dependency, write no server code, and call no `enableMcp()`. You write a normal
`runApp` app:

```dart
import 'package:fleury/fleury.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});
  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Semantics(
        id: const SemanticNodeId('count'),
        role: SemanticRole.text,
        label: 'Count',
        value: _count,
        child: Text('Count: $_count'),
      ),
      Semantics(
        id: const SemanticNodeId('increment'),
        role: SemanticRole.button,
        label: 'Increment',
        actions: const <SemanticAction>{SemanticAction.activate},
        onAction: (_) => setState(() => _count++),
        child: const Text('[ Increment ]'),
      ),
    ],
  );
}
```

Two things to notice:

- **Nothing here imports or references MCP.** It's a plain Fleury app.
- The `Semantics(...)` wrappers are doing *two* jobs, and both are optional:
  high-level widgets like `Button`, `TextInput`, `DataTable`, and `Select` (from
  `package:fleury_widgets`) already contribute their role, label, and actions for
  free — a `Button(label: 'Increment', onPressed: …)` is agent-drivable as-is.
  The one genuinely useful thing to add is the **`id:`**, which gives the agent a
  stable handle (see *Make your app drive well* below).

Want a real app to try right now? Every app in `packages/samples`
(`dashboard` · `files` · `agent`) is an unmodified `runApp` app and drives over
MCP as-is.

## Drive it

### 1. Get the `fleury_mcp` executable

```bash
# Once published to pub.dev — as a dev-dependency of your app:
#   dev_dependencies:
#     fleury_mcp: ^0.1.0
# then invoke it with `dart run fleury_mcp -- <your app>`.

# Today, from a Fleury checkout — put it on your PATH:
dart pub global activate --source path packages/fleury_mcp
```

### 2. Point an MCP host at any app

```bash
claude mcp add my-app -- fleury_mcp -- dart run bin/my_app.dart
```

Then ask the agent to read and operate the app — it will `get_ui` to see the
tree, then `invoke_action` / `set_value` / `type_text` to drive it. The app needs
no changes.

### 3. (Recommended) AOT-compile for instant startup

Launching via `dart run` JIT-compiles the app on the first read (a few seconds);
`fleury_mcp` prints a one-time hint when it sees this. Compile once for a
near-instant, repeatable launch:

```bash
dart compile exe bin/my_app.dart -o my_app
claude mcp add my-app -- fleury_mcp -- ./my_app
```

### Drive it by hand (for debugging)

`fleury_mcp` speaks newline-delimited JSON-RPC on stdio, so you can poke it
without a host:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_ui","arguments":{}}}' \
  | fleury_mcp -- dart run bin/my_app.dart
```

A cold `dart run` JIT-compiles the app first, which can take a few seconds — if
`get_ui` comes back with "has not rendered a UI yet," give it a moment and retry,
or point `fleury_mcp` at an AOT-compiled binary (`dart compile exe`) so the first
frame lands well within the startup window.

## What the agent sees

`get_ui` returns the tree as JSON — roles, labels, values, and supported actions.
For the counter above:

```json
{
  "schemaVersion": 1,
  "nodeCount": 3,
  "roleCounts": { "app": 1, "text": 1, "button": 1 },
  "focusedNodeId": "increment",
  "root": {
    "id": "auto:…/app", "role": "app",
    "children": [
      { "id": "count",     "role": "text",   "label": "Count", "value": 0 },
      { "id": "increment", "role": "button", "label": "Increment",
        "actions": ["activate"] }
    ]
  }
}
```

The agent then drives by id — e.g. `invoke_action {"id": "increment",
"action": "activate"}` — and re-reads to see the change. Results come back both
as text JSON (the model-facing channel) and as MCP `structuredContent`.

### Tools & resource

| | |
|---|---|
| **resource** `fleury://ui/tree` | The current semantic tree — the same artifact `get_ui` returns. **Subscribable**: `resources/subscribe` and the server pushes `notifications/resources/updated` (with just the changed node ids) whenever the UI settles. |
| `get_ui` | Read the whole tree (roles, labels, values, state, actions). Call first, and after each action. |
| `find_nodes` | Query by role / label substring / supported action / focus / selection — the lean path on a large screen. |
| `invoke_action` | Invoke a `SemanticAction` on a node by id (activate, focus, select, submit, increment, open/close, …). |
| `set_value` | Set a value in one call — text fields, checkboxes/toggles, sliders/steppers, selects, date pickers, or a table's row index. Settable nodes advertise a typed `valueSchema`, and the value is validated against it before dispatch. |
| `type_text` | Type into the focused input. |
| `press_key` | A named key (enter, tab, arrows, f1–f12) or a chord (ctrl/alt/shift). Prefer `invoke_action` when a semantic action exists. |
| `resize` | Resize the viewport to reflow the layout and surface more rows of a windowed widget. |
| `wait_for_change` | Block until the UI updates on its own (a ticking dashboard, a streaming response) instead of polling. |
| `read_frames` | **Agent devtools:** recent render-frame stats (number, trigger, build/layout/paint/diff µs) — diagnose slowness or excess repaints. |
| `read_logs` | **Agent devtools:** the app's captured stdout/stderr, including native/library output Fleury captures at the file descriptor. Source-tagged, newest last. |
| `read_errors` | **Agent devtools:** recent uncaught runtime errors with full stack traces and timestamps — check whether an action threw. |

> The three `read_*` tools are the agent side of Fleury's debug shell (the same
> frame stats, captured logs, and error history a developer sees under F12) —
> so an agent driving the app can *read its devtools while it works*, not just
> the UI. They need the app to have debug tooling enabled (the default in
> development runs; release builds default off), and return `available:false`
> otherwise.

### Options

```
fleury_mcp [--cols=<n>] [--rows=<n>] -- <command ...>
```

- `--cols` / `--rows` — the viewport the app lays out against (default `80×24`).
  A taller grid surfaces more rows of windowed widgets in the tree.
- `--` — separates `fleury_mcp`'s flags from the app command.

## Live updates, cancellation & logging

Beyond request/response, the server is a full MCP citizen:

- **Push on change.** Subscribe to `fleury://ui/tree` and the server emits
  `notifications/resources/updated` when the UI settles — coalesced to one per
  settled burst, carrying only the changed/removed node ids. An agent learns
  *what* changed without re-reading the tree (~0.3% of a full re-read on a busy
  screen). `wait_for_change` stays for hosts that prefer to pull.
- **Cancellation.** A long `wait_for_change` can be abandoned with the standard
  `notifications/cancelled`; it returns at once instead of waiting out its
  timeout.
- **App logs.** The driven app's own stdout/stderr is forwarded as
  `notifications/message` (logger `app`; stdout → `info`, stderr → `warning`),
  gated by `logging/setLevel` — so an agent can see what the app logged while
  driving it, without it polluting the JSON-RPC channel.
- **Machine-readable errors.** A failed tool call carries a stable
  `structuredContent.code` (`not_found`, `stale_reference`, `ambiguous`,
  `rate_limited`, `not_ready`, …) so an agent branches on the category instead of
  string-matching the message.

## Make your app drive well

The app works with zero effort; these make the agent's job easier:

- **Pin stable ids on the nodes that matter** with `Semantics(id: SemanticNodeId(…))` or a
  `Key`. Without one, a node gets a derived id that stays stable across rebuilds
  *when it has a keyed ancestor*, but a fully-unkeyed node falls back to a
  positional id that can shift as the tree changes. A `Semantics(id: SemanticNodeId('submit'))`
  is a durable handle. (The server guards against acting on a *stale* positional
  id, so the worst case is a clear "re-read and retry", not a mis-click.)
- **Give nodes meaningful labels.** Labels are how the agent recognizes a node.
- **Hide decorative or off-screen chrome** with `ExcludeSemantics` so it doesn't
  clutter what the agent reads.

## Performance & robustness

- **Bounded, token-cheap payloads.** `get_ui` and every action result are
  node-capped (800) and trimmed (no pixel bounds, no value that just repeats a
  label), so a large screen can't blow the agent's context; `find_nodes` is the
  lean drill-in path. A committed test gates per-node payload size.
- **Push deltas, not re-reads.** A subscription update carries only the changed
  ids — ~0.3% of a full re-read on a busy dashboard (~322× lighter).
- **Fast internals, gated against regression.** Id→node lookup is O(1) per
  revision (~477× vs a full tree walk), and the settle behind `wait_for_change`
  is capped so a continuously-animating app returns promptly (~3.7× faster than
  running to timeout). A committed benchmark + perf gate hold these numbers.
- **Safe against injected content.** All app-derived text is delimited as
  untrusted (read-and-report, never follow embedded instructions), and the
  mutating tools are rate-limited.
- **Stable, compact ids** with a stale-reference guard (above).
- **Clean lifecycle.** The app subprocess is torn down on disconnect, SIGINT, or
  SIGTERM (exits in well under a second on stdin close); a connect-but-never-
  render app fails fast with a clear message.

## Status

Pre-1.0, developed in the Fleury monorepo (`publish_to: none`, path dependency on
`fleury`). The protocol surface is stable and verified against the MCP Inspector,
a host-process end-to-end harness, and live drives of the sample apps. See
[`docs/agents-and-semantics.md`](../../docs/agents-and-semantics.md) for the
broader semantics story.
