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

Each node is a [`SemanticNode`](https://github.com/danReynolds/fleury/blob/main/packages/fleury/lib/src/semantics/semantics.dart):
a role, a human label, a value, interaction state, the actions it supports, and
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

## The same tree powers three things

- **Tests that assert on meaning.** Check that "the CPU gauge reads 0.62" or
  "row 3 is selected" — assertions that survive a re-theme, a layout change, or a
  port to the browser, because they're about semantics, not glyphs.
- **Agents that drive, not scrape.** An AI agent reads roles, state, and the
  available `SemanticAction`s, then acts through them. The UI is a typed surface,
  not a screenshot to interpret.
- **Accessibility, for free.** It's the same tree a screen reader would want —
  roles, labels, and state — so accessible output isn't a separate effort.

## On both surfaces

Because semantics are produced by the core (not a target), they exist whether
the app runs in a terminal or the browser. [`fleury serve`](/architecture/serving-and-embedding/)
streams the semantic tree to the client alongside the visual frame, so a remote
session is just as inspectable as a local one.

See [Core and targets](/architecture/core-and-targets/) for where semantics sit
in the pipeline.
