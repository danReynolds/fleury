---
title: Navigation
description: Move between screens with a Navigator stack — push, pop, return results, and guard back.
---

Multi-screen terminal apps — a list that drills into a detail view, a wizard, a
settings page — use a `Navigator`, much like Flutter. Give `FleuryApp` a `home`
screen and it owns the app's route stack:

```dart
void main() => runApp(
  const FleuryApp(title: 'My app', home: HomeScreen()),
);
```

The app theme, commands, status, shortcuts, and extensions sit above that
Navigator. `context.push` and `context.pop` therefore work from every route
without losing app-wide state. A bare widget passed directly to `runApp` is
still useful for one-screen tools, but it does not create a route stack.

## Push and pop

Push a screen by handing the navigator a **widget** (there are no named routes or
`MaterialPageRoute` — the widget *is* the route):

```dart
context.push(DetailScreen(id: item.id));
```

Pop back from within a screen:

```dart
context.pop();
```

## Returning a result

`push` returns a `Future` that completes with whatever the pushed screen pops.
Type it, and `await` it:

```dart
final confirmed = await context.push<bool>(ConfirmDialog());
if (confirmed == true) _delete();
```

The pushed screen returns its result by popping with a value:

```dart
context.pop(true);   // completes the awaiting push with `true`
```

## The full Navigator API

The whole `NavigatorState` is available via `Navigator.of(context)`, or directly
on the context:

- `context.push<T>(screen)` — push and (optionally) await a result.
- `context.pop([result])` — pop the top screen.
- `Navigator.of(context).pushReplacement(screen)` — replace the current screen.
- `Navigator.of(context).pushAndClear(screen)` — reset the stack to one screen.
- `Navigator.of(context).popUntil<HomeScreen>()` — pop back to a screen by type.
- `Navigator.of(context).canPop` — whether there's anything to pop.

## Custom shells

`FleuryApp(home: ...)` is the normal path, including for a home screen that
contains nested pane-local stacks. Use `child:` when fixed chrome must sit
outside the app's one root route, when you need to configure that root
Navigator explicitly, or when the app intentionally has no Navigator. The
custom-shell path never adds a hidden Navigator:

```dart
FleuryApp(
  title: 'Workspace',
  child: Row(
    children: [
      const SizedBox(width: 18, child: Text('Workspace')),
      const Expanded(child: Navigator(home: HomeScreen())),
    ],
  ),
)
```

Pass either `home` or `child`, never both. A descendant's nearest Navigator is
the one returned by `Navigator.of(context)`. Keep exactly one top-level
Navigator when using `child:`; put independent pane stacks beneath it. Sibling
root Navigators have no unambiguous target for `rootNavigator: true`.

## Transitions

Pass a `RouteTransition` to animate the push — `RouteTransition.fade` or
`RouteTransition.slide`:

```dart
context.push(DetailScreen(id: id), transition: RouteTransition.slide);
```

## Guarding back

To intercept a back/Esc — "you have unsaved changes" — wrap the screen in a
`PopScope`. With `canPop: false`, pops are vetoed and `onBlocked` runs instead, so
you can confirm first:

```dart
PopScope(
  canPop: !hasUnsavedChanges,
  onBlocked: () => _confirmDiscard(),
  child: EditScreen(),
)
```

This is the same contract as Flutter's `PopScope`, including how it composes with
the system back gesture (here, the Esc key).
