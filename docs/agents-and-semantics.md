# Built for agents

You can hand a Fleury app to an AI agent and have it *drive* the UI — read what's
on screen and operate it — through the [Model Context
Protocol](https://modelcontextprotocol.io), the open standard hosts like Claude
already speak.

That's unusual for a terminal UI. At the pixel level a TUI is just a grid of
characters, so the usual way to drive one is to screen-scrape: diff ANSI output,
match substrings, guess at key sequences. It's brittle and blind — restyle a
border and it breaks; the agent never really knows what's on screen, only what it
looks like. A Fleury agent never scrapes. Here's how, and what makes it possible.

## Drive it with an agent — `fleury_mcp`

The `fleury_mcp` package runs a Model Context Protocol server over a private wire
to your app:

```sh
fleury_mcp -- dart run bin/run_app.dart
```

It spawns your app, tracks its live semantic tree, and exposes it as MCP: the
graph as a **resource** (`fleury://ui/tree`), and the actions on it as **tools** —
`get_ui` / `find_nodes` to read, `invoke_action` / `set_value` / `type_text` /
`press_key` to drive, and `resize` / `wait_for_change` to surface more rows or
watch for asynchronous change.

Point an MCP host at it and the agent reads roles, labels, values, and the
actions each node supports, then drives the UI through them — no ANSI scraping,
no guessed keystrokes. The app needs no agent-specific code.

The resource is **live**: subscribe to it and the server pushes a compact
`notifications/resources/updated` — just the changed node ids — each time the UI
settles, so an agent following a streaming response or a ticking dashboard learns
*what* changed without re-reading the whole tree.

See [Driving with an agent (MCP)](/guides/driving-with-agents/) for the hands-on
setup: installing the driver, connecting a host, the full tool reference, and
making your app drive well.

## What powers it — the semantic tree

The MCP server is a *thin shim*, not a bolted-on adapter, because **the app
already produces everything the agent reads.** Alongside the visual tree,
Fleury can project a **semantic tree**: a *semantic app graph* describing what
the UI **means**, not how it's painted. Agent-reachable and browser surfaces
retain and update that graph when semantics or painted coverage change. The
headless tester builds a snapshot when `tester.semantics()` asks for one, and a
plain terminal run likewise skips the work until a debug consumer asks. That
graph *is* the
MCP resource; the `SemanticAction`s on it *are* the MCP tools. There's no scraping
layer to maintain — driving the UI is just reading the graph and invoking its
actions. The rest of this page is that graph.

## What the graph contains

Each node is a `SemanticNode` — a role, a human label, a value, interaction
state, the actions it supports, and
its children.

```dart
final class SemanticNode {
  final SemanticNodeId id;
  final SemanticRole role;        // table, chart, button, slider, message…
  final String? label;            // "CPU", "Submit", "row 3"
  final Object? value;            // 0.62, "draft", selected text…
  final String? hint;
  final bool enabled, focused, selected, busy;
  final bool? checked, expanded;
  final Set<SemanticAction> actions;   // what you can DO to it
  final List<SemanticNode> children;   // the tree
  final SemanticState state;           // completed / failed / disabled…
}
```

The role vocabulary is deliberately broad, and it includes roles built for the
apps agents actually live in — not just `button` and `textField`, but
`conversation`, `messageList`, `traceTimeline`, `patchReview` / `patchFile`,
`commandPalette`, and `command`. The actions are equally concrete: `activate`,
`submit`, `select`, `increment`, `decrement`, `open`, `close`, `navigate`,
`copy`, `start`, `cancel`.

## What an agent sees

Take the live `DataTable` below — the real widget, running in your browser:

<!-- fleury-example: datatable.basic 48x8 | A DataTable — and the semantic tree behind it -->

Behind those characters, the semantic graph an agent (or a test) reads looks
roughly like this:

```json
{
  "role": "table",
  "label": "People",
  "children": [
    { "role": "tableRow", "selected": true, "children": [
      { "role": "tableCell", "label": "name",    "value": "dan" },
      { "role": "tableCell", "label": "role",    "value": "author" },
      { "role": "tableCell", "label": "commits", "value": 1284 }
    ]},
    { "role": "tableRow", "children": [ /* ada, reviewer, 642 … */ ] }
  ],
  "actions": ["focus", "select", "copy"]
}
```

No ANSI parsing. The agent knows there's a table, which row is selected, the
typed cell values, and that it can `select` a different row or `copy` the
current one — then it issues that `SemanticAction` instead of guessing which
arrow keys to press.

## Holding a reference — stable ids

An agent that read a node a moment ago needs to act on *that* node, even after the
UI rebuilt. Every node carries a `SemanticNodeId`, and the framework derives a
stable one with no app effort: a node under a keyed ancestor (a list row's `Key`,
say) keeps its id across rebuilds *and reorders*, because the id folds in its
ancestor key chain rather than its raw position. A fully unkeyed node falls back
to a positional id — and those *can* shift as the tree changes, so the server
guards them: if a positional node's fingerprint (role + label + actions) changed
since the agent last read it, the action fails safe with a `stale_reference`
error instead of mis-targeting. Pinning `Semantics(id: SemanticNodeId('submit'))` on the nodes
that matter gives the agent a durable handle and sidesteps the guard entirely.

So the agent isn't guessing which ids are durable, `get_ui` and `find_nodes`
flag every positional node with `"stableId": false` and attach a one-line
`idGuidance` note explaining it; a stable id is simply unannotated. An agent
that needs to hold a reference across an interaction can see up front which
nodes need an app-assigned id — and it's the honest signal for the one case the
framework can't solve for you: an unkeyed node in a dynamic list has no identity
across a reshuffle, exactly as it wouldn't in Flutter, so durability there is an
app-authoring choice (add a `Key` or a `Semantics(id:)`), not a framework
default.

Settable nodes publish their raw constraints (min/max, option labels, a date
format) in semantic state; the MCP server derives a typed **`valueSchema`**
from them — the type and domain a `set_value` will accept — so an agent fills
a field correctly the first time, and an out-of-domain value is rejected with
a clear reason rather than silently dropped.

## The graph is the API — for tests, too

That graph isn't a diagram of something internal; it's the API — and agents
aren't its only consumer. A test reads the same tree and asserts on *meaning*:

```dart
testWidgets('Save advertises an activate action', (tester) {
  tester.pumpWidget(const Semantics(
    id: SemanticNodeId('save'),
    role: SemanticRole.button,
    label: 'Save',
    actions: {SemanticAction.activate},
    child: Text('Save'),
  ));

  final save = tester.semantics().single(
    role: SemanticRole.button, label: 'Save');
  expect(save.actions, contains(SemanticAction.activate));
});
```

`tester.semantics()` returns the same tree shown above; `.single(...)` finds a
node by role, label, value, or an action it advertises. The assertions are about
what a node *is* — its `value`, whether it's `selected`, the `state` it carries —
so they survive a re-theme, a relayout, or a port to the browser. "The CPU gauge
reads 0.62" and "row 3 is selected" are one `expect` each, not a screen-scrape.

Driving the UI is the mirror image: find a node that advertises an action, invoke
it, and watch the state change — exactly what an agent does instead of guessing
keystrokes.

```dart
testWidgets('activating Save runs its handler', (tester) async {
  var saved = 0;
  tester.pumpWidget(Semantics(
    role: SemanticRole.button,
    label: 'Save',
    actions: const {SemanticAction.activate},
    onAction: (_) => saved++,                 // the app's handler
    child: const Text('Save'),
  ));

  final result = await tester.invokeSemanticAction(
    SemanticAction.activate, role: SemanticRole.button, label: 'Save');

  expect(result.completed, isTrue);
  expect(saved, 1);                           // the UI actually changed
});
```

That `read graph → invoke action → observe change` loop is the whole story, and
it isn't terminal-only. [`fleury serve`](/architecture/serving-and-embedding/)
exposes the same loop over a socket: the tree ships out as JSON — the same
node fields `tester.semanticInspectionJson()` shows, redaction and all,
flattened into a full-then-patch diff envelope (`childIds` instead of nested
children) so it stays inside DEFLATE's window — and `SemanticAction`s come
back on the same channel, each answered with an invocation-status result. So an MCP agent, a test, and the
browser's accessibility mirror are all the same kind of consumer — reading
meaning and acting on it — with different goals.

## One tree, three payoffs

The graph isn't built for any single consumer — it's one artifact with three
uses:

- **Agents** read roles, state, and the available `SemanticAction`s and act
  through them — a typed surface, not a screenshot to interpret.
- **Tests** assert on meaning (above), so they survive a re-theme, a relayout, or
  a port to the browser.
- **Accessibility** comes along for free: it's the same roles-and-state tree a
  screen reader wants, so accessible output isn't a separate effort.

## On both surfaces

Because semantics are produced by the core (not a target), they exist whether
the app runs in a terminal or the browser. [`fleury serve`](/architecture/serving-and-embedding/)
streams the semantic tree to the client alongside the visual frame, so a remote
session is just as inspectable as a local one.

See [Core and targets](/architecture/core-and-targets/) for where semantics sit
in the pipeline.
