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
which returns what the widget displays:

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

## Rebuild after changing state

When a field in your `State` changes, use **`setState`** to rebuild its widget:

```dart
setState(() => _count++);
```

`setState` runs your callback synchronously, then marks this widget for rebuild.
On the next frame the framework re-runs the dirty build path, performs the
layout and paint work that change requires, and diffs the new cell grid against
the old. The terminal presenter writes only cells that actually changed; when
the runtime has no frame work, it skips build, layout, paint, and presentation.

For fields owned by your `State`, use `setState` to schedule the rebuild.
Controllers and other listenables notify their listeners themselves; use a
`ListenableBuilder` when your surrounding UI reads their state.

## Who owns a control's value?

With `value` and `onChanged`, your state owns the value. The control asks for a
change, and you supply the updated value:

```dart
Checkbox(
  label: 'Contain arrows',
  value: contain,
  onChanged: (value) => setState(() => contain = value),
)
```

Try that checkbox in the [scroll-edge demo](/fleury/guides/lists-and-scrolling/#see-what-happens-at-an-edge).
The same `contain` field controls both its checkmark and the pane's edge behavior.

A controller holds live state that both your code and the widget can change.
Create it once in `State` and dispose it with that state:

```dart
final list = ListController(initialIndex: 24);

@override
void dispose() {
  list.dispose();
  super.dispose();
}
```

The [task browser](/fleury/guides/lists-and-scrolling/#scroll-a-large-list)
starts at task 25. Arrow keys and the **Go to 25** button update the same
`list.currentIndex`; ordinary rebuilds preserve it.

An `initial*` widget argument seeds internal state once. For example,
`NumberInput(initialValue: 42)` keeps the user's edits when its parent rebuilds.
Use a controller for later programmatic changes, or a new key for a deliberate
reset. Supply a seed or a controller for the same value, not both.

Input `onChanged` callbacks report user and semantic edits. Programmatic
controller writes notify controller listeners, so updating a model does not
echo through an input callback. Replacing a controller adopts the new one's
state; omitting it creates fresh internally owned state.

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
responsive layout; it's a `Scope` under the hood (see below). There
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

## Sharing data down the tree: Scope

You've already used this. Every `.of(context)` call reads from a **`Scope`** — a
widget that sits high in the tree, shares one value with everything beneath it,
and rebuilds any descendant that read it when the value is replaced by one that
is not equal or, for a `Listenable` such as a `ChangeNotifier`, when it
notifies. The built-ins you've met (`Theme`, `MediaQuery`,
`DefaultTextStyle`) are scopes, each fronted by a `.of(context)` helper.

You'd reach for your own when a model — a current user, a router, a feature
flag — needs to reach many widgets, and you'd rather not thread it through ten
constructors to get there. Wrap the subtree in `Scope(value: model, child: ...)`
(or `Scope<Model>.create(...)` to let the scope own the model) and read it
anywhere below with `Scope.of<Model>(context)`. The type argument is the key,
and the nearest scope of that type wins. The
[State management](/fleury/guides/state-management/) guide covers the rest.

---

Next: where the tree starts running — [App entry points](/fleury/concepts/app-entry/).
For arranging widgets once you have them, see [Layout](/fleury/guides/layout/); for the
leaf widgets that go in the tree, the [widget reference](/fleury/widgets/).
