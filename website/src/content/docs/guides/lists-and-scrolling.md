---
title: Lists & scrolling
description: Render long, scrollable lists with ListView, and scroll arbitrary content with ScrollView.
---

A `Column` lays its children out and stops there — if they overflow, you get the
overflow marker, not scrolling. For content that scrolls, Fleury has the two
widgets you'd reach for in Flutter: `ListView` for a list of items, and
`ScrollView` for an arbitrary scrollable child.

## ListView

`ListView` renders a vertical, scrollable, keyboard-navigable list. It handles
focus, arrow-key movement, and selection for you. The eager form takes a fixed
list of children:

```dart
ListView(
  children: [
    for (final item in items) Text(item.label),
  ],
)
```

For long or unbounded lists, use `ListView.builder` — it builds items on demand
and only mounts the visible ones, so a hundred-thousand-row list costs about a
screenful. The builder receives the index **and a `selected` flag** so you can
style the active row:

```dart
ListView.builder(
  itemCount: rows.length,
  itemBuilder: (context, i, selected) => Text(
    rows[i].label,
    style: selected ? const CellStyle(inverse: true) : CellStyle.empty,
  ),
  onActivate: (i) => _open(rows[i]),
)
```

If you've used Flutter, that third builder argument is the wrinkle: Fleury's
`itemBuilder` is `(context, index, selected)`, because selection lives in the list
itself rather than something you wire up around it.

`onActivate` fires when the user activates the highlighted row (Enter). Pass a
`ListController` if you need to drive scrolling or the selection programmatically;
otherwise the list manages its own.

## ScrollView

When what you want to scroll isn't a list — a long block of text, a form, a
composed panel — wrap it in `ScrollView`. It's a viewport onto a single child
(the equivalent of Flutter's `SingleChildScrollView`):

```dart
ScrollView(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('A long document…'),
      // …more than fits on screen…
    ],
  ),
)
```

Give it a `ScrollController` to read or set the scroll offset, and wrap it in a
`Scrollbar` if you want a visible track.

## How the user scrolls

Keyboard scrolling goes through focus: a **focused** `ScrollView` claims
Up/Down (one row), PageUp/PageDown (a viewport), and Home/End (top/bottom) —
pass `autofocus: true` or a `FocusNode` to make a scroll region reachable. At
the top or bottom edge, `edgeBehavior` decides whether the key is consumed
(`contain`) or bubbles to an ancestor (`bubble`, the default) so a pane
coordinator can move focus onward instead.

The **mouse wheel needs no focus** — hovering any `ScrollView` or `ListView`
and scrolling just works. In a list with a selection, the wheel moves the
selection (the viewport follows); in a plain scroll region it moves the
viewport.

## Follow the tail

For a log or transcript view — pinned to the newest line, but not fighting the
user when they scroll up to read — the behavior is built into `ListController`:

```dart
final _log = ListController(pinToBottom: true);

// …
ListView.builder(
  controller: _log,
  itemCount: _lines.length,
  itemBuilder: (context, i, selected) => Text(_lines[i]),
)
```

Appended items keep the viewport pinned to the tail; the user scrolling up
disengages the follow temporarily, and returning to the bottom resumes it —
the `less +F` / chat-transcript behavior. For reading position programmatically,
`ScrollController` exposes `offset`, `maxOffset`, `atTop` / `atBottom`,
`scrollBy`, and `jumpTo`.

## Which to use

- A homogeneous, navigable list of items → **`ListView`** (or `.builder` when
  it's long).
- A one-off tall thing that just needs to scroll → **`ScrollView`**.
- Tabular or hierarchical data → reach for [`DataTable`](/fleury/widgets/datatable/) or
  [`TreeTable`](/fleury/widgets/treetable/), which window their rows the same way
  `ListView.builder` does.

Fleury intentionally keeps the scrolling surface small — there are no slivers or
`CustomScrollView`. For the overwhelming majority of terminal UIs, `ListView` and
`ScrollView` cover it.
