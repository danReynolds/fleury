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
`get_ui` / `find_nodes` to read, `invoke_action` / `set_value` to drive, and
`resize` / `wait_for_change` to surface more rows or watch for asynchronous
change. Legacy `2025-06-18` clients also retain the focus-relative `type_text`
and `press_key` tools; they stay off the stateless surface until the request can
carry an explicit target or focus lease.

Point an MCP host at it and the agent reads roles, labels, values, and the
actions each node supports, then drives the UI through them — no ANSI scraping,
no guessed keystrokes. Positional nodes carry an opaque `targetRef`, so a
stateless action request does not depend on another task's last read and rejects
observable slot-identity changes. Semantically identical unkeyed replacements
still need distinct keys or stable semantic ids. The app needs no
agent-specific code.

For asynchronous app changes, `wait_for_change` returns the next settled tree
without polling. Current clients pass the opaque, instance-scoped `uiRevision`
from the prior result as `sinceRevision`, closing the gap between reading and
starting the wait while rejecting handles from a restarted server. Legacy
`2025-06-18` hosts can additionally subscribe for a
compact `notifications/resources/updated` delta. Current MCP replaced that
method with `subscriptions/listen`; Fleury does not advertise modern streaming
subscriptions yet.

See [Driving with an agent (MCP)](/guides/driving-with-agents/) for the hands-on
setup: installing the driver, connecting a host, completing a semantic
workflow, and making custom controls drive well.

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
  // …plus a cell `bounds` rect and a `validationError` for invalid inputs.
}
```

The role vocabulary is **open**. Core Fleury declares the generic set every
surface understands — `button`, `textField`, `list`, `listItem`, `region`,
`status`, `dialog`, `tree`, `command`, and the rest of `SemanticRole.values`.
The widget catalog adds the roles built for the apps agents actually live in —
`WidgetRoles.conversation`, `messageList`, `traceTimeline`, `patchReview` /
`patchFile`, `commandPalette`, `toolCall`, `approval` — and your own package can
add more. A declared role names the core role it projects through, so a surface
that has never heard of it (the served browser's accessibility mirror, an older
agent bridge, the text-coverage policy) still treats it as what it is:

```dart
abstract final class BoardRoles {
  static const board = SemanticRole('kanbanBoard', base: SemanticRole.region);
  static const card = SemanticRole('kanbanCard', base: SemanticRole.listItem);
}

Semantics(role: BoardRoles.card, label: task.title, child: ...)
tester.semantics().byRole(BoardRoles.card) // tests match on the role
```

On the wire the node carries `role: "kanbanCard"` and `coreRole: "listItem"`;
an agent filters by the specific name, and the browser mirror renders an ARIA
`listitem`. A declared name must be an identifier and must not be a core name
(both are asserted when the node is collected); only the name and its core
root travel, so the human label is always derived from the name. The actions are equally concrete: `activate`, `submit`, `select`,
`increment`, `decrement`, `open`, `close`, `navigate`, `copy`, `start`,
`cancel`.

## What an agent sees

Take the live `DataTable` below — the real widget, running in your browser:

<!-- fleury-example: datatable.basic 48x8 | A DataTable — and the semantic tree behind it -->

This excerpt was captured from `tester.semanticInspectionJson()` after
rendering this example at 48×8 cells. It shows the table and its selected data
row; snapshot metadata, node ids, the header, other rows, and additional node
state are omitted:

```json
{
  "role": "table",
  "label": "Data table",
  "value": 0,
  "actions": [
    "copy",
    "focus",
    "select",
    "setValue"
  ],
  "state": {
    "currentRowIndex": 0,
    "selectionMode": "row"
  },
  "children": [
    {
      "role": "tableRow",
      "selected": true,
      "children": [
        {
          "role": "tableCell",
          "label": "dan",
          "value": "dan",
          "state": {
            "columnId": "name"
          }
        },
        {
          "role": "tableCell",
          "label": "author",
          "value": "author",
          "state": {
            "columnId": "role"
          }
        },
        {
          "role": "tableCell",
          "label": "1284",
          "value": "1284",
          "state": {
            "columnId": "commits"
          }
        }
      ]
    }
  ]
}
```

No ANSI parsing. The agent can read the selected row and available actions;
`state.columnId` identifies each column. This table exposes the strings returned
by its `cellBuilder`, so even the commit count is a string, `"1284"`, rather than
a typed domain value. An agent can invoke `select` on a row, use the table's
`setValue` action to jump to a row index, or `copy` the current selection,
without guessing which arrow keys to press.

## Holding a reference — stable ids

An agent that read a node a moment ago needs to act on *that* node, even after the
UI rebuilt. Every node carries a `SemanticNodeId`, and the framework derives a
stable one with no app effort: a node under a keyed ancestor (a list row's `Key`,
say) keeps its id across rebuilds *and reorders*, because the id folds in its
ancestor key chain rather than its raw position. A fully unkeyed node falls back
to a positional id — and those *can* shift as the tree changes, so the server
guards them: if a positional node's app-issued target token changed since the
agent last read it, the action fails safe with a `stale_reference` error instead
of mis-targeting. The token survives value, focus, busy-state, and ticking
updates to the same logical element; it rotates when the mounted contributor or
the target's role, label, or advertised actions change, and when a synthesized
target disappears and returns. A semantically identical update with the same
widget `runtimeType` and `Key` is the same logical element under Fleury's
reconciliation contract, so use a distinct `Key` or stable `Semantics.id` when
those configurations are different logical targets. Controls with frequently
changing labels should also use a stable id rather than making each label
transition a new positional lease.
Pinning `Semantics(id: SemanticNodeId('submit'))` on the nodes
that matter gives the agent a durable handle and sidesteps the guard entirely.

So that the agent isn't guessing which ids are durable, `get_ui` and `find_nodes`
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

## Live semantic state without rebuilding content

Use `state:` for values known when a widget builds. Use `stateBuilder:` for
values that become available after layout, such as a list's visible range:

```dart
Semantics(
  role: SemanticRole.region,
  label: 'Source viewport',
  stateListenable: controller,
  stateBuilder: () {
    final range = controller.visibleRange;
    return SemanticState({
      if (range != null) ...{
        'visibleRangeStart': range.first,
        'visibleRangeEnd': range.last,
      },
    });
  },
  child: SizedBox(
    height: 8,
    child: ListView.builder(
      controller: controller,
      itemCount: lines.length,
      itemBuilder: (_, index, _) => Text(lines[index]),
    ),
  ),
)
```

Here `controller` is a `ListController` owned by the enclosing state. A completed
scroll updates the semantic snapshot without rebuilding this wrapper or its
content. First-party collections already use this pattern.

The callback runs when semantics are collected. It can run several times per
frame, and a terminal session without a semantic consumer may never call it.
Keep it a pure read: no inherited dependency reads, model mutations, or work
scheduling. Return a snapshot whose map and nested values will not be mutated.
Compute expensive content summaries when content changes; reading viewport state
should not scan the entire collection.

`stateListenable` invalidates the semantic snapshot even when no pixels change.
The element manages the subscription across moves and replacement, but does not
dispose your model. Without a listenable, changing the model alone does not
schedule a semantic update. Supply either `state` or `stateBuilder`.

For a custom collection wrapper whose visual content depends on the controller,
listen to `controller.viewChanges` in its build dependency. That signal covers
cursor changes, explicit content refresh, and scroll requests. Ordinary
controller listeners continue to receive completed viewport metrics as well.

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
- **Accessibility adapters** read the same roles and state. Custom controls
  still need meaningful semantics, and screen-reader behavior needs validation
  on each target; sharing the tree does not guarantee equivalent accessibility
  across terminals and browsers.

## On both surfaces

Because semantics are produced by the core (not a target), they exist whether
the app runs in a terminal or the browser. [`fleury serve`](/architecture/serving-and-embedding/)
streams the semantic tree to the client alongside the visual frame, so a remote
session is just as inspectable as a local one.

See [Core and targets](/architecture/core-and-targets/) for where semantics sit
in the pipeline.
