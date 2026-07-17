---
title: State management
description: setState for local state, ChangeNotifier + ListenableBuilder for state shared across widgets — the same model as Flutter.
---

Fleury follows Flutter's familiar local-state primitives. Most state is
**local** — a field in a `State`, mutated inside `setState`. When state needs to
be shared by widgets that aren't parent-and-child, reach for a
**`ChangeNotifier`** model and rebuild the readers with **`ListenableBuilder`**.
Fleury does not require a provider package for this pattern.

## Local state: `setState`

If one widget owns a piece of state and its descendants render it, keep it in
that widget's `State`:

```dart
class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [KeyBinding(.space, onEvent: (_) => setState(() => _count++))],
    child: Text('count: $_count'),
  );
}
```

Reach for something bigger only when threading the value through constructors
starts to hurt.

## Shared state: a `ChangeNotifier` model

When two sibling widgets — a header badge and a list, say — must reflect the
same data, lift it out of the widget tree into a plain model. The full runnable
version is in
[`doc_snippets/shared_state.dart`](https://github.com/danReynolds/fleury/blob/main/website/examples/doc_snippets/shared_state.dart).

```dart
class CartModel extends ChangeNotifier {
  final List<String> _items = [];
  List<String> get items => List.unmodifiable(_items);
  int get count => _items.length;

  void add(String item) {
    _items.add(item);
    notifyListeners(); // tells every ListenableBuilder to rebuild
  }
}
```

Own the model where it belongs — often the app root's `State` — and dispose it
with that State:

```dart
class _ShopAppState extends State<ShopApp> {
  final _cart = CartModel();

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }
```

Then bind any widget to it with `ListenableBuilder`. Only the builder's subtree
rebuilds when the model notifies — the rest of the screen is untouched:

```dart
ListenableBuilder(
  listenable: cart,
  builder: (context, _) => Text('Cart: ${cart.count} item(s)'),
)
```

The header badge and the list both wrap a `ListenableBuilder(listenable: cart)`,
so they stay in sync from one source of truth without either being an ancestor
of the other.

## Which do I use?

| Situation | Reach for |
|---|---|
| One widget owns it; descendants render it | `setState` |
| Siblings / distant widgets share it | `ChangeNotifier` + `ListenableBuilder` |
| A value that arrives async (timer, stream, future) | [`FutureBuilder` / `StreamBuilder`](/guides/loading-data/) |
| App-wide config read deep in the tree | `InheritedWidget` (see [Widgets & state](/concepts/widgets-and-state/)) |

There's no framework-blessed "app state" singleton — a `ChangeNotifier` you
create at the root and pass down (or expose via an `InheritedWidget`) is the
idiomatic built-in pattern, and it should feel familiar to Flutter developers.
