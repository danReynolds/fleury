---
title: Loading data
description: Build UI from a Future or a Stream with FutureBuilder and StreamBuilder.
---

Terminal apps fetch and stream constantly — an API call, a log tail, a process's
output. Fleury builds UI from a `Future` or `Stream` with the same two widgets
you know from Flutter: `FutureBuilder` and `StreamBuilder`, both handing your
builder an `AsyncSnapshot`.

## FutureBuilder

Give it a `Future` and a builder; the builder re-runs as the future resolves:

```dart
FutureBuilder<List<Item>>(
  future: _itemsFuture, // created once in initState: _itemsFuture = fetchItems();
  builder: (context, snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Text('Loading…');
    }
    if (snapshot.hasError) {
      return Text('Failed: ${snapshot.error}');
    }
    final items = snapshot.data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final item in items) Text(item.label)],
    );
  },
)
```

The `AsyncSnapshot` carries everything about the in-flight operation:
`connectionState` (`none`, `waiting`, `active`, `done`), `hasData` / `data`,
and `hasError` / `error`. Pass `initialData:` to render something before the
first result instead of a waiting state.

> Build the `Future` once — in `initState` or a field — not inside `build`. A
> future created fresh on every rebuild restarts the work each frame. This is the
> same footgun as in Flutter. To re-run the load (a refresh key, a retry button),
> reassign that field inside `setState` — the builder returns to its loading
> state and resolves again.

## StreamBuilder

`StreamBuilder` is the same shape over a `Stream`, rebuilding on every event —
ideal for a feed that updates over time:

```dart
StreamBuilder<int>(
  stream: ticks,            // e.g. a Stream<int> of elapsed seconds
  initialData: 0,
  builder: (context, snapshot) => Text('Elapsed: ${snapshot.data}s'),
)
```

`connectionState` moves through `waiting` → `active` (events flowing) → `done`
(the stream closed), so you can show a connecting state, the live value, and a
finished state from one builder.

## When to reach for which

- A one-shot load (a request, a file read) → **`FutureBuilder`**.
- A continuing feed (logs, metrics, a socket) → **`StreamBuilder`**.
- State you mutate yourself on a timer or callback → hold it in a `State` and
  `setState` (see [Widgets & state](/fleury/concepts/widgets-and-state/)); reach for the
  async builders specifically when the *source* is a `Future`/`Stream`.
