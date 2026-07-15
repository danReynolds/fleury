---
title: "Tutorial: a filterable list"
description: Build a small interactive TUI end-to-end — state, a text input, live filtering, and layout.
---

In about fifteen minutes you'll build a list that narrows live as you type —
touching the three things every Fleury app is made of:
[state](/concepts/widgets-and-state/), [layout](/guides/layout/), and input.

You'll need a project with the `fleury` and `fleury_widgets` dependencies; the
first step of [Getting started](/getting-started/) sets that up if you haven't
already.

## What we're building

A single screen: a text field at the top, a filtered list below it, and a live
count. Type, and the list narrows in place.

## 1. A static list

Start with a stateless screen that just renders some data. Put this in
`bin/my_app.dart`:

```dart
import 'package:fleury/fleury.dart';

const _languages = [
  'Dart', 'Rust', 'Go', 'Python', 'TypeScript',
  'Elixir', 'Zig', 'Swift', 'Kotlin', 'Haskell',
];

void main() => runApp(const FilterApp());

class FilterApp extends StatelessWidget {
  const FilterApp({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final name in _languages) Text(name),
      ],
    ),
  );
}
```

`dart run bin/my_app.dart` shows the list, one item per row, padded a cell off
the edge. (`Ctrl-C` quits.) Nothing moves yet — let's make it react.

## 2. Hold state

Filtering means the screen changes over time, so we need a `StatefulWidget` and a
place to keep the query. Swap `FilterApp` for a stateful version:

```dart
class FilterApp extends StatefulWidget {
  const FilterApp({super.key});

  @override
  State<FilterApp> createState() => _FilterAppState();
}

class _FilterAppState extends State<FilterApp> {
  String _query = '';

  List<String> get _matches => _languages
      .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final name in _matches) Text(name),
      ],
    ),
  );
}
```

`_matches` derives the visible list from `_query` every build. `_query` is still
always `''`, so nothing's filtered — until we wire up the input.

## 3. Add the text field

`TextInput` edits text through a `TextEditingController`. The controller is a
`ChangeNotifier`, so we can **listen** to it and rebuild whenever the text
changes — that's how the list filters as you type. Create the controller in
`initState`, listen, and clean up in `dispose`:

```dart
class _FilterAppState extends State<FilterApp> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _matches {
    final query = _controller.text.toLowerCase();
    return _languages
        .where((name) => name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextInput(
          controller: _controller,
          autofocus: true,
          placeholder: 'Filter languages…',
        ),
        SizedBox(height: 1),
        for (final name in _matches) Text(name),
      ],
    ),
  );
}
```

Run it again and type. The listener calls `setState` on every keystroke; `build`
re-reads `_controller.text`, recomputes `_matches`, and the framework repaints
only the rows that changed. That's the whole reactive loop — `autofocus: true`
means you can type the moment it launches.

## 4. Layout and polish

Two touches make it feel finished. First, push the list to fill the space below
the field with `Expanded`, so the field stays pinned at the top. Second, add a
count and an empty state. Here's the final `build`:

```dart
@override
Widget build(BuildContext context) {
  final matches = _matches;
  return Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextInput(
          controller: _controller,
          autofocus: true,
          placeholder: 'Filter languages…',
        ),
        SizedBox(height: 1),
        Text('${matches.length} of ${_languages.length}',
            style: const CellStyle(dim: true)),
        SizedBox(height: 1),
        Expanded(
          child: matches.isEmpty
              ? const Text('No matches', style: CellStyle(dim: true))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final name in matches) Text(name)],
                ),
        ),
      ],
    ),
  );
}
```

That's a complete, interactive Fleury app: state held in a `State`, an input
bound through a controller, a derived list, and a layout that fills the screen.

## Where to go next

- The same app runs in a **browser** unchanged — see [Deployment &
  distribution](/guides/deployment/) to compile it with `dart2js` or preview it
  locally with `fleury serve`.
- Swap the plain `Column` of `Text` for a richer widget — a [`Tree`](/widgets/tree/),
  [`DataTable`](/widgets/datatable/), or [`Select`](/widgets/select/) — from the
  [widget reference](/widgets/). (Those live in `fleury_widgets`; add
  `import 'package:fleury_widgets/fleury_widgets.dart';` when you reach for them.)
- Add keyboard navigation (arrow keys to move a selection) with the patterns in
  [Focus & keyboard](/guides/focus-and-keyboard/).
