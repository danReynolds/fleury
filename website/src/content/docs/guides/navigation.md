---
title: Navigation
description: Move between screens with a Navigator stack — push, pop, return results, and guard back.
---

Multi-screen terminal apps — a list that drills into a detail view, a wizard, a
settings page — use a `Navigator`, exactly like Flutter. You don't set one up:
`runApp` installs a root `Navigator` over your app, so `context.push` and
`context.pop` work everywhere out of the box.

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
