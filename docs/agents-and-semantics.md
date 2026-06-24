# Built for agents

A terminal UI is, at the pixel level, a grid of characters. To *test* one or let
an *agent* drive one, the usual move is to screen-scrape — diff ANSI output,
match substrings, guess at key sequences. It's brittle: restyle a border and the
test breaks; the agent never really knew what was on screen, only what it looked
like.

Fleury keeps a **semantics tree** alongside the visual one and makes it a
headline feature. Every frame, the framework produces a *semantic app graph*: a
tree describing what the UI **means**, not how it's painted.

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

## Read it, drive it — in code

That graph isn't a diagram of something internal; it's the API. A test reads it
and asserts on *meaning*:

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
exposes the same loop over a socket: the tree ships out as JSON
(`tester.semanticInspectionJson()` is that exact payload, redaction and all), and
`SemanticAction`s come back on the same channel. The browser client consumes the
outbound half — projecting a live accessibility tree straight from the wire — so
an agent is just the same kind of consumer with a different goal.

## Drive it with an agent — `fleury_mcp`

That front door is built. The `fleury_mcp` package runs a [Model Context
Protocol](https://modelcontextprotocol.io) server — the open standard any
MCP-capable agent (Claude included) already knows how to connect to — over the
same wire:

```sh
fleury_mcp -- dart run my_app.dart
```

It spawns your app, tracks its live semantic tree, and exposes it as MCP:

- a **resource**, `fleury://ui/tree` — the current semantic snapshot;
- **tools** the agent calls — `get_ui` and `find_nodes` to read the UI,
  `invoke_action` to operate a node through one of its advertised
  `SemanticAction`s, `set_value` to set a field/slider/select in one call (a node
  advertising `setValue`), and `type_text` / `press_key` for raw input.

Point an MCP host at it and the agent reads roles, labels, values, and the
actions each node supports, then drives the UI through them — no ANSI scraping,
no guessed keystrokes. The Dart side is a thin shim precisely because the app
already emits MCP's shapes: the graph *is* the resource, the `SemanticAction`s
*are* the tools. A host configures it like any other MCP server (the executable
comes from the `fleury_mcp` package — `dart pub global activate fleury_mcp`, or
invoke it as `dart run fleury_mcp:fleury_mcp`):

```json
{
  "mcpServers": {
    "my-app": {
      "command": "fleury_mcp",
      "args": ["--", "dart", "run", "my_app.dart"]
    }
  }
}
```

## One tree, three payoffs

The graph isn't built for any single consumer — it's one artifact with three
uses:

- **Tests** assert on meaning (above), so they survive a re-theme, a relayout, or
  a port to the browser.
- **Agents** read roles, state, and the available `SemanticAction`s and act
  through them — a typed surface, not a screenshot to interpret.
- **Accessibility** comes along for free: it's the same roles-and-state tree a
  screen reader wants, so accessible output isn't a separate effort.

## On both surfaces

Because semantics are produced by the core (not a target), they exist whether
the app runs in a terminal or the browser. [`fleury serve`](/architecture/serving-and-embedding/)
streams the semantic tree to the client alongside the visual frame, so a remote
session is just as inspectable as a local one.

See [Core and targets](/architecture/core-and-targets/) for where semantics sit
in the pipeline.
