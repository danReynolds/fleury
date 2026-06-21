---
title: Focus & keyboard
description: Handle key events, manage focus, and register app-wide shortcuts.
---

Fleury routes keyboard input to the focused part of the tree. Most widgets
(inputs, lists, trees, tables) manage their own focus and keys; this guide is
for when you handle keys yourself.

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
