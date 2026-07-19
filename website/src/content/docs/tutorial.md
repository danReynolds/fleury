---
title: "Tutorial: a filterable list"
description: Build a small interactive TUI end-to-end — state, a text input, live filtering, and layout.
---

In about fifteen minutes you'll build a list that narrows live as you type —
touching the three things every Fleury app is made of:
[state](/fleury/concepts/widgets-and-state/), [layout](/fleury/guides/layout/), and input.

You'll need a project with the `fleury` and `fleury_widgets` dependencies; the
first step of [Getting started](/fleury/getting-started/) sets that up if you haven't
already.

## What we're building

A single screen: a text field at the top, a filtered list below it, and a live
count. Type, and the list narrows in place.

## 1. A static list

Start with a stateless screen that just renders some data. Replace
`lib/app.dart` in the generated project:

```dart
import 'package:fleury/fleury.dart';

const _languages = [
  'Dart', 'Rust', 'Go', 'Python', 'TypeScript',
  'Elixir', 'Zig', 'Swift', 'Kotlin', 'Haskell',
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const FleuryApp(title: 'Filter', home: FilterApp());
  }
}

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

The generated counter test also needs to follow the screen you just replaced.
Use this small smoke for the rest of the tutorial:

```dart title="test/app_test.dart"
import 'package:fleury_test/fleury_test.dart';
import 'package:my_app/app.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('shows the language list', (tester) {
    tester.pumpWidget(const MyApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Dart'));
  });
}
```

Run `dart test` to check the smoke. Then press F5 or run
`dart run bin/run_app.dart`. The list appears one item per row, padded a cell
off the edge. (`Ctrl-C` quits.) Nothing moves yet — let's make it react.

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

`TextInput.onChanged` reports the current text. Store that value in `_query`
with `setState`, and the list filters as you type:

```dart
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
        TextInput(
          autofocus: true,
          placeholder: 'Filter languages…',
          onChanged: (value) => setState(() => _query = value),
        ),
        SizedBox(height: 1),
        for (final name in _matches) Text(name),
      ],
    ),
  );
}
```

Run it again and type. `onChanged` calls `setState` on every edit; `build`
recomputes `_matches` from `_query`, and the framework repaints only the rows
that changed. That's the whole reactive loop — `autofocus: true` means you can
type the moment it launches.

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
          autofocus: true,
          placeholder: 'Filter languages…',
          onChanged: (value) => setState(() => _query = value),
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

Run it one more time. The field stays pinned while the list fills the screen,
the count updates as you type, and a query with no hits (try `zz`) shows the
empty state.

That's a complete, interactive Fleury app: state held in a `State`, an input
reported through `onChanged`, a derived list, and a layout that fills the screen.

## Where to go next

- The same **widget tree** runs in a browser with a target-specific host
  entrypoint and web-safe imports — see [Deployment &
  distribution](/fleury/guides/deployment/) to compile it with `dart2js` or preview the
  native app locally with `fleury serve`.
- Swap the plain `Column` of `Text` for a richer widget — a [`Tree`](/fleury/widgets/tree/),
  [`DataTable`](/fleury/widgets/datatable/), or [`Select`](/fleury/widgets/select/) — from the
  [widget reference](/fleury/widgets/). (Those live in `fleury_widgets`; add
  `import 'package:fleury_widgets/fleury_widgets.dart';` when you reach for them.)
- Add keyboard navigation (arrow keys to move a selection) with the patterns in
  [Focus & keyboard](/fleury/guides/focus-and-keyboard/).
