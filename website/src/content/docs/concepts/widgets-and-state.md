---
title: Widgets & state
description: The programming model — stateless and stateful widgets, the State lifecycle, setState, keys, and context.
---

A Fleury UI is a tree of **widgets**: immutable descriptions of what should be on
screen. You never mutate a widget — you describe a new one and let the framework
work out the minimal change. (If you've used Flutter, this is the same model,
painting to a grid of cells instead of pixels; everything below will feel like
home.)

## Two kinds of widget

A **`StatelessWidget`** depends only on its inputs. Override one method, `build`,
which returns the widget's children:

```dart
class Greeting extends StatelessWidget {
  const Greeting(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) => Text('Hello, $name');
}
```

A **`StatefulWidget`** also carries mutable state that survives rebuilds — a
counter, a scroll position, a text buffer. The widget itself is still immutable;
the mutable part lives in a companion **`State`** object that the framework keeps
alive across rebuilds:

```dart
class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('Count: $_count'),
      Button(label: 'Increment', onPressed: () => setState(() => _count++)),
    ],
  );
}
```

## setState — the one rule

To change what's on screen, mutate your state inside **`setState`**:

```dart
setState(() => _count++);
```

`setState` runs your callback synchronously, then marks this widget for rebuild.
On the next frame the framework re-runs the dirty build path, performs the
layout and paint work that change requires, and diffs the new cell grid against
the old. The terminal presenter writes only cells that actually changed; when
the runtime has no frame work, it skips build, layout, paint, and presentation.

The rule is simply: **any state your `build` reads, you must change inside
`setState`.** Mutating a field without it leaves the screen stale.

## The State lifecycle

The framework owns your `State` object's life. The methods you can override, in
the order they fire:

- **`initState()`** — once, when the state is first inserted. Set up controllers,
  start subscriptions. Always call `super.initState()`.
- **`didChangeDependencies()`** — right after `initState`, and again whenever an
  inherited dependency you read (a `Theme`, a `MediaQuery`) changes. *Not* called
  for a plain `setState`.
- **`build(context)`** — whenever this state is marked dirty, an inherited
  dependency changes, or its parent supplies updated configuration. Keep it
  pure: no side effects, just describe the tree.
- **`didUpdateWidget(oldWidget)`** — when the parent rebuilds and hands this state
  a new widget instance of the same type. Compare `widget` to `oldWidget` and
  react (e.g. re-subscribe if a callback prop changed).
- **`dispose()`** — once, when the widget is removed for good. Tear down anything
  you started in `initState` — controllers, tickers, stream subscriptions.
  Always call `super.dispose()`.

```dart
class _ClockState extends State<Clock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();   // started in initState → cleaned up here
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('$_now');
}
```

Inside a `State` you also have three getters: **`widget`** (the current
configuration), **`context`** (this widget's location in the tree), and
**`mounted`** (whether the state is still in the tree — guard async callbacks
with `if (!mounted) return;` before calling `setState`).

## BuildContext

The `BuildContext` handed to `build` is a handle to *where* this widget sits in
the tree. You rarely call methods on it directly — most of the time you pass it
to a `.of(context)` lookup:

```dart
final theme = Theme.of(context);          // nearest ThemeData
final size  = MediaQuery.sizeOf(context);  // terminal size, in cells
```

These walk up the tree to find the nearest ancestor that provides the value, and
they **subscribe** this widget to it — change the theme and every widget that
read `Theme.of(context)` rebuilds. That's the mechanism behind theming and
responsive layout; it's an `InheritedWidget` under the hood (see below). There
are shorthands too: `context.theme` and `context.colors`.

Note one difference from a render tree: a `BuildContext` has no `.size`. A widget
doesn't know its own dimensions during `build` (it hasn't been laid out yet).
Read the *screen* size from `MediaQuery`, and make a subtree adapt to *its* space
with layout widgets like `Expanded` and `Wrap` (see [Layout](/fleury/guides/layout/)).

## Keys

When the framework rebuilds, it reuses existing `State` objects by matching each
new widget to the old one at the same position with the same type. Usually that's
exactly right and you pass no key. You reach for a **`Key`** when identity needs
to survive *reordering* — most often a list whose items get inserted, removed, or
shuffled:

- **`ValueKey(item.id)`** — ties a widget's identity to a stable value, so its
  state follows it when the list reorders. The common case.
- **`UniqueKey()`** — equal only to itself; use it to *force* a fresh state (a
  remount) where you'd otherwise get reuse.
- **`GlobalKey()`** — unique across the whole tree; lets you reach a widget's
  `State` from elsewhere via `key.currentState`. Powerful but heavier — prefer
  lifting state up before reaching for one.

## Sharing data down the tree: InheritedWidget

You've already used this. Every `.of(context)` call reads from an
**`InheritedWidget`** — a widget that sits high in the tree, exposes data to
everything beneath it, and rebuilds any descendant that read it when the value
changes. The built-ins you've met (`Theme`, `MediaQuery`, `DefaultTextStyle`) are
all inherited widgets, each fronted by a `.of(context)` helper.

You'd write your own when app-wide state — a current user, a router, a feature
flag — needs to reach many widgets, and you'd rather not thread it through ten
constructors to get there. Descendants opt in with
`context.dependOnInheritedWidgetOfExactType<T>()` (or your own `.of` helper) and
rebuild automatically when it changes.

---

Next: where the tree starts running — [App entry points](/fleury/concepts/app-entry/).
For arranging widgets once you have them, see [Layout](/fleury/guides/layout/); for the
leaf widgets that go in the tree, the [widget reference](/fleury/widgets/).
