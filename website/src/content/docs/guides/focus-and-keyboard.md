---
title: Focus & keyboard
description: Handle key events, manage focus, and register app-wide shortcuts.
---

Fleury routes every key event to the focused part of the tree. Most widgets —
inputs, lists, trees, tables — manage their own focus and keys, so much of the
time you write nothing. This guide is for when you don't, and the first question
is *which tool*:

- **`Focus`** — a focusable region with an `onKey` callback. Reach for it to
  handle keys *while a particular subtree is focused* (an arrow-key navigator, a
  custom editor).
- **`FocusNode`** — when you need to *move* focus yourself: focus a field on
  mount, or jump focus on a button press.
- **`KeyBindings`** — app-wide shortcuts that fire *regardless of what's focused*
  (Ctrl-S to save, a command palette).

## Handle keys with Focus

`Focus` makes a subtree focusable and gives you an `onKey` callback. Return
`KeyEventResult.handled` to consume the event, or `.ignored` to let it bubble:

```dart
Focus(
  autofocus: true,
  onKey: (KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  },
  child: _list,
);
```

A `KeyEvent` carries `keyCode` (a `KeyCode` like `enter`, `escape`, `tab`, the
arrows), the typed `char` (for printable input), and modifier flags
`hasCtrl` / `hasAlt` / `hasShift`:

```dart
if (event.hasCtrl && event.char == 's') save();
```

## Manage focus explicitly

Create a `FocusNode` in `initState`, attach it, and dispose it:

```dart
final _node = FocusNode(debugLabel: 'editor');
// ...
_node.requestFocus();      // take focus
final hasIt = _node.hasFocus;
// ...
_node.dispose();
```

`Tab` / `Shift+Tab` move focus between focusable nodes by default.

## App-wide shortcuts

For shortcuts that should work regardless of what's focused, wrap a region in
`KeyBindings`. Each `KeyBinding` pairs a `KeyChord` with a handler and a label
(used by command surfaces and help):

```dart
KeyBindings(
  bindings: [
    KeyBinding(KeyChord.ctrl.s, label: 'Save', onEvent: (_) => save()),
    KeyBinding(KeyChord.escape, label: 'Close', onEvent: (_) => close()),
  ],
  child: app,
);
```

`KeyChord` has the common chords built in (`KeyChord.enter`, `.escape`, `.tab`)
and a `ctrl` / `alt` / `shift` builder for combinations (`KeyChord.ctrl.s`).

**One key to watch:** `Esc` already pops the `Navigator` by default. If you also
bind it — above, or in a `Focus` — be deliberate about which should win; to
intercept the pop rather than race it, reach for a `PopScope` (see
[Navigation](/guides/navigation/#guarding-back)).
