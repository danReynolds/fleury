---
title: Input & gestures
description: Handle taps, drags, and mouse hover — yes, mouse — in the terminal.
---

Keyboard is the terminal's primary input, and Fleury handles it through focus and
key bindings (see [Focus & keyboard](/guides/focus-and-keyboard/)). But terminals
also report the **mouse**, and Fleury surfaces it with the same widgets you'd use
in Flutter: `GestureDetector` and `MouseRegion`.

## Enabling the mouse

Mouse reporting is a terminal mode you opt into when you start the app:

```dart
runTui(const MyApp(), mode: const TerminalMode(mouse: true));
```

With it on, clicks, drags, and motion are routed to your gesture widgets.

## Taps and clicks

`GestureDetector` wraps a child and fires callbacks. `onTap` is the plain click;
the position-aware callbacks hand you the **cell** that was clicked as
`(col, row)`:

```dart
GestureDetector(
  onTap: () => _select(),
  onTapDown: (col, row) => _placeCursorAt(col, row),
  onSecondaryTap: () => _showContextMenu(),
  child: Cell(),
)
```

## Dragging

The drag callbacks track a press-move-release as cell coordinates — enough to
build a draggable splitter, a selection rectangle, or a slider:

```dart
GestureDetector(
  onDragStart: (col, row) => _begin(col),
  onDragUpdate: (col, row) => setState(() => _dividerCol = col),
  onDragEnd: () => _commit(),
  child: Divider(),
)
```

## Hover

`MouseRegion` reports the pointer entering, moving within, and leaving its child —
so you can highlight a row under the cursor or show a hover hint:

```dart
MouseRegion(
  onEnter: () => setState(() => _hovered = true),
  onExit:  () => setState(() => _hovered = false),
  onHover: (col, row) => setState(() => _cursor = col),  // position-aware
  child: Row(...),
)
```

## A note on reach

Mouse support is real and handy, but a good terminal app stays fully usable from
the keyboard — many users run without mouse reporting, over SSH, or in
multiplexers that swallow it. Treat the mouse as an accelerator on top of
keyboard navigation, not the only way in. For the keyboard side — focus
traversal, key chords, and bindings — see
[Focus & keyboard](/guides/focus-and-keyboard/).
