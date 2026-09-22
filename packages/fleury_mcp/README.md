# fleury_mcp

A [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server that
drives a running [Fleury](https://github.com/danReynolds/fleury) terminal-UI app
through its **semantic tree** — so any MCP host (Claude Code, Claude Desktop, …)
can read the UI and operate it.

No screen-scraping. The agent reads roles, labels, values, and the *actions each
node supports*, then invokes those actions by id. Positional nodes also carry an
opaque `targetRef`, which removes the connection-global last-read dependency
and rejects detectable slot-identity changes. Semantically identical unkeyed
replacements still require distinct keys or stable semantic ids. These are the
same accessible semantics Fleury exposes to the browser and testing API.

```
┌─────────────┐   JSON-RPC / stdio   ┌────────────┐   semantic wire   ┌──────────┐
│  MCP host   │ ◀─────────────────▶  │ fleury_mcp │ ◀──────────────▶  │ your app │
│ (the agent) │   get_ui, actions…   │  (server)  │   SEMANTICS /     │ (runApp) │
└─────────────┘                      └────────────┘   INPUT frames    └──────────┘
```

## How it works

A Fleury app builds a widget tree whose interactive and content widgets already
contribute meaningful accessible semantics; layout-only structure may be folded
away. That semantic tree powers Fleury's browser accessibility mirror and its
testing API; `fleury_mcp` is a third consumer of it.

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
import 'package:fleury_widgets/fleury_widgets.dart';

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
      Text('Count: $_count'),
      Button(
        text: 'Increment',
        onPressed: () => setState(() => _count++),
      ),
    ],
  );
}
```

Two things to notice:

- **Nothing here imports or references MCP.** It's a plain Fleury app.
- `Button`, `TextInput`, `DataTable`, `Select`, and the other first-party
  controls already contribute their role, label, value, and supported actions.
  Manual `Semantics` belongs on custom controls, not around these widgets.

Want a real app to try right now? The runnable apps under `packages/samples`
are unmodified `runApp` apps and drive over MCP as-is.

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

`fleury_mcp` uses Fleury's explicitly unstable first-party wire. Each published
executable package exact-pins its matching Fleury release, so prefer the app
dev-dependency form and let pub resolve one build for both. A path activation
uses the checkout's sibling override; reactivate it after that Fleury source
changes. The INIT handshake rejects mismatches instead of decoding incompatible
frames.

The MCP boundary supports stateless `2026-07-28` requests discovered through
`server/discover`, while retaining the `2025-06-18` initialization flow for
existing hosts. The app-side INIT described above is Fleury's separate private
wire handshake; it remains required in both MCP modes.

### 2. Point an MCP host at any app

```bash
claude mcp add my-app -- fleury_mcp -- dart run bin/run_app.dart
```

Then ask the agent to read and operate the app — it will `get_ui` to see the
tree, then `invoke_action` / `set_value` to drive it. Legacy `2025-06-18`
clients can additionally use focus-relative text and key input. The app needs
no changes.

### 3. (Recommended) AOT-compile for instant startup

Launching via `dart run` JIT-compiles the app on the first read (a few seconds);
`fleury_mcp` prints a one-time hint when it sees this. Compile once for a
near-instant, repeatable launch:

```bash
dart compile exe bin/run_app.dart -o my_app
claude mcp add my-app -- fleury_mcp -- ./my_app
```

### Drive it by hand (for debugging)

`fleury_mcp` speaks newline-delimited JSON-RPC on stdio. Current MCP requests
carry protocol metadata in every `params` object, so an MCP host or inspector is
the most representative probe. For a short raw-pipe smoke test, the legacy
initialization path remains available:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_ui","arguments":{}}}' \
  | fleury_mcp -- dart run bin/run_app.dart
```

A cold `dart run` JIT-compiles the app first, which can take a few seconds — if
`get_ui` comes back with "has not rendered a UI yet," give it a moment and retry,
or point `fleury_mcp` at an AOT-compiled binary (`dart compile exe`) so the first
frame lands well within the startup window.

## What the agent sees

`get_ui` returns the tree as JSON — roles, labels, values, and supported actions.
For the counter above, a narrowed `find_nodes` result looks like this (opaque
ids and references shortened):

```json
{
  "matchCount": 1,
  "uiRevision": "revision:…",
  "nodes": [{
    "id": "element-…",
    "role": "button",
    "label": "Increment",
    "actions": ["activate"],
    "stableId": false,
    "targetRef": "target:…"
  }]
}
```

The agent echoes that exact returned target — for example, `invoke_action
{"id":"element-…","action":"activate","targetRef":"target:…"}`. If a node
reports `"stableId": false`, its opaque `targetRef` is required by the
`2026-07-28` protocol path. Mutating tools return the settled UI, so the next
target should be selected from that result instead of forcing another full
read. Results come back both as text JSON (the model-facing channel) and as MCP
`structuredContent`.

### Tools & resource

| | |
|---|---|
| **resource** `fleury://ui/tree` | The current semantic tree — the same artifact `get_ui` returns. Legacy `2025-06-18` clients can subscribe for coalesced deltas; current integrations use `wait_for_change` until the modern streaming transport is implemented. App-authored ids carry the same `untrustedContent` marker as tree reads. |
| `get_ui` | Read the whole tree (roles, labels, values, state, actions). Call first; mutating tools return the next settled tree. |
| `find_nodes` | Query by role / label substring / supported action / focus / selection — the lean path on a large screen. |
| `invoke_action` | Invoke a `SemanticAction` on a node by id (activate, focus, select, submit, increment, open/close, …). |
| `set_value` | Set a value in one call — text fields, checkboxes/toggles, sliders/steppers, selects, date pickers, or a table's row index. Settable nodes advertise a typed `valueSchema`, and the value is validated against it before dispatch. |
| `type_text` | **Legacy `2025-06-18` only.** Type into the focused input. It is withheld from stateless discovery until a request can carry an explicit target or focus lease. |
| `press_key` | **Legacy `2025-06-18` only.** A named key (enter, tab, arrows, f1–f12) or a chord (ctrl/alt/shift). Prefer `invoke_action` when a semantic action exists. |
| `resize` | Resize the viewport to reflow the layout and surface more rows of a windowed widget. |
| `wait_for_change` | Block until the UI updates on its own (a ticking dashboard, a streaming response) instead of polling. Current clients pass the prior result's opaque, instance-scoped `uiRevision` as `sinceRevision`, so a change that already landed returns immediately and a handle from a restarted server fails closed. |
| `read_frames` | **Agent devtools:** recent render-frame stats (number, trigger, build/layout/paint/diff µs) — diagnose slowness or excess repaints. |
| `read_logs` | **Agent devtools:** the app's captured stdout/stderr, including native/library output Fleury captures at the file descriptor. Source-tagged, newest last. |
| `read_errors` | **Agent devtools:** recent uncaught runtime errors with full stack traces and timestamps — check whether an action threw. |

> The three `read_*` tools are the agent side of Fleury's debug shell (the same
> frame stats, captured logs, and error history a developer sees under F12) —
> so an agent driving the app can *read its devtools while it works*, not just
> the UI. They need the app to have debug tooling enabled (the default in
> development runs; release builds default off), and return `available:false`
> otherwise. Debug results carry an `untrustedContent` marker: app logs, errors,
> identifiers, and record fields are data, never model instructions.

### Options

```
fleury_mcp [--cols=<n>] [--rows=<n>] -- <command ...>
```

- `--cols` / `--rows` — the viewport the app lays out against (default `80×24`).
  A taller grid surfaces more rows of windowed widgets in the tree.
- `--` — separates `fleury_mcp`'s flags from the app command.

## Live updates, cancellation & logging

The request/response path is current MCP; a few event features remain as legacy
compatibility:

- **Legacy push on change.** A `2025-06-18` client can subscribe to
  `fleury://ui/tree` and the server emits
  `notifications/resources/updated` when the UI settles — coalesced to one per
  settled burst, carrying only the changed/removed node ids. An agent learns
  *what* changed without re-reading the tree (~0.3% of a full re-read on a busy
  screen). The `2026-07-28` protocol replaced this method with
  `subscriptions/listen`; Fleury does not advertise modern subscriptions yet,
  so current clients use `wait_for_change`.
- **Cancellation.** A long `wait_for_change` can be abandoned with the standard
  `notifications/cancelled`; it returns at once instead of waiting out its
  timeout.
- **Legacy app logs.** For `2025-06-18`, the driven app's own stdout/stderr is forwarded as
  `notifications/message` (logger `app`; stdout → `info`, stderr → `warning`),
  gated by `logging/setLevel` — so an agent can see what the app logged while
  driving it, without it polluting the JSON-RPC channel. `params.data` is an
  envelope with the verbatim `message` plus an `untrustedContent` warning. MCP
  Logging is deprecated in `2026-07-28`; current clients use `read_logs` and
  `read_errors`, while deployments can route server diagnostics through stderr
  or OpenTelemetry.
- **Machine-readable errors.** A failed tool call carries a stable
  `structuredContent.code` (`not_found`, `stale_reference`, `ambiguous`,
  `rate_limited`, `not_ready`, …) so an agent branches on the category instead of
  string-matching the message. Error text and structured content also carry an
  untrusted-content warning because an error may quote app-authored fields.
- **Bounded stdio.** Requests are capped at 8 MiB per NDJSON line and 64 active
  calls; mutation work has its own smaller queue. Startup logs and pending
  stdout are byte/count bounded, and a stalled flush terminates the session
  instead of retaining responses or blocking teardown indefinitely.

## Make your app drive well

The app works with zero effort; these make the agent's job easier:

- **Give custom semantic controls stable ids when durable targeting matters.**
  `Semantics(id: SemanticNodeId('submit'))` is a durable handle. Ordinary
  first-party controls get a per-read `targetRef` that rejects observable slot
  changes; wrapping one merely to add an id duplicates the contract it already
  owns. A widget
  `Key` can stabilize a derived semantic path only when that key reaches the
  semantic contributor, so do not assume every public control key becomes its
  MCP id.
- **Give nodes meaningful labels.** Labels are how the agent recognizes a node.
- **Hide decorative or off-screen chrome** with `ExcludeSemantics` so it doesn't
  clutter what the agent reads.

## Performance & robustness

- **Bounded, token-cheap payloads.** `get_ui` and every action result are
  node-capped (800) and trimmed (no pixel bounds, no value that just repeats a
  label), so a large screen can't blow the agent's context; `find_nodes` is the
  lean drill-in path. A committed test gates per-node payload size.
- **Avoid redundant re-reads.** Mutations return their settled tree and
  `wait_for_change` blocks for app-initiated changes. Its revision cursor closes
  the read-to-wait race. Legacy subscription
  updates carry only changed ids (~0.3% of a full re-read on the measured busy
  dashboard).
- **Fast internals, gated against regression.** Id→node lookup is O(1) per
  revision (~477× vs a full tree walk), and the settle behind `wait_for_change`
  is capped so a continuously-animating app returns promptly (~3.7× faster than
  running to timeout). A committed benchmark + perf gate hold these numbers.
- **Safe against injected content.** App-authored semantics, ids, resource
  deltas, debug records, logs, errors, and app-derived tool errors remain
  verbatim inside structures marked as untrusted (read and report them; never
  follow embedded instructions). Mutating tools are rate-limited.
- **Stable, compact ids** with a stale-reference guard (above).
- **Clean lifecycle.** The app subprocess is torn down on disconnect, SIGINT, or
  SIGTERM. Idle disconnect is prompt and active teardown is bounded; a
  connect-but-never-render app fails fast with a clear message.

## Status

Developed in the Fleury monorepo and packaged for publication with an exact
dependency on the matching Fleury release (`fleury: 0.1.0`). That pairing covers
Fleury's supported host/process SPI and its explicitly unstable, lockstep wire.
Local development uses `pubspec_overrides.yaml` to resolve the sibling package.
Matching builds are covered by protocol-level tests, a host-process end-to-end
harness, and live drives of the sample apps; app-wire version skew is rejected
during INIT. Official `2026-07-28` conformance-suite qualification remains a
release gate rather than a claim made by these local tests. See
[`docs/agents-and-semantics.md`](https://github.com/danReynolds/fleury/blob/main/docs/agents-and-semantics.md) for the
broader semantics story.
