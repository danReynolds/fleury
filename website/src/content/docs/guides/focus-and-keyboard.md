---
title: Focus & keyboard
description: Handle key events, manage focus, and register app-wide shortcuts.
---

Fleury routes every key event to the focused part of the tree. Most widgets —
inputs, lists, trees, tables — manage their own focus and keys, so much of the
time you write nothing. This guide is for when you don't, and the first question
is *which tool* — pick by **scope**:

| Use | When | Scope |
|---|---|---|
| **`KeyBindings`** | App- or screen-wide shortcuts (`Ctrl+S`, `Ctrl+P`, quit) that should fire regardless of what's focused | Ambient — matches while its subtree is mounted |
| **`Focus`** | A widget handles keys *only while it's focused* (a custom list navigator, a canvas) | Local — active on focus |
| **`FocusNode`** | You need to *drive* or *read* focus imperatively — move it (`Tab` between panes), check `hasFocus`, or wire a `Panel`'s accent | A handle you hold and pass to a widget |

Reach for **`KeyBindings`** first — most shortcuts are ambient. They compose: a
pane can hold a `FocusNode`, wrap its body in a `Focus` for while-focused keys,
and still sit under an app-level `KeyBindings` for global shortcuts.

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
arrows), the modifier flags `hasCtrl` / `hasAlt` / `hasShift`, and — for a
modifier chord — a `char` holding the base key (Ctrl+S → `char: 's'`). Plain
typed text is *not* a `KeyEvent`: printable and Unicode input arrives as a
`TextInputEvent` that the text widgets consume, so `Focus(onKey:)` sees keys and
chords, not character entry.

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

Inside a `FleuryApp(home: ...)` route or an explicit
`FocusTraversalGroup`, `Tab` / `Shift+Tab` move between focusable nodes. A bare
widget passed directly to `runApp` has the focus manager but no traversal
policy; wrap it in a group when it has multiple controls.

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

**One key to watch:** inside `FleuryApp(home: ...)` (or another explicit
`Navigator`), `Esc` already pops the current route by default. If you also bind
it — above, or in a `Focus` — be deliberate about which should win; to intercept
the pop rather than race it, reach for a `PopScope` (see
[Navigation](/fleury/guides/navigation/#guarding-back)).

