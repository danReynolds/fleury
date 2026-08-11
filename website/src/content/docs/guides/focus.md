---
title: Focus & traversal
description: Make widgets focusable, control Tab order, and move focus with the arrow keys.
---

Focus decides *where* keys go. Fleury routes every key event to the focused part
of the tree, so before a shortcut can fire or a list can respond to `↓`,
something has to hold focus.

Most widgets handle this for you — inputs, lists, trees, and tables are already
focusable and already traverse. This guide is for when you build your own, or
need to drive focus directly. For what happens *after* a key reaches the focused
widget, see [Focus & keyboard](/fleury/guides/focus-and-keyboard/).

## Making something focusable

Wrap it in `Focus`. That's the whole requirement: a `Focus` in the tree can hold
focus, take part in `Tab` traversal, and receive keys.

```dart
Focus(
  child: MyControl(),
);
```

`autofocus: true` claims focus when the widget first appears — for the search
field in a dialog, or the list in a freshly-opened pane:

```dart
Focus(
  autofocus: true,
  child: SearchField(),
);
```

Autofocus is per-scope and one-shot: a widget claims focus when *its* scope has
no focused descendant yet, so opening a new screen autofocuses its own content
without stealing focus from unrelated parts of the app, and it won't re-fire on
every rebuild.

## Driving focus directly

For focus you control — "jump to the editor after loading", "focus the next
field on submit" — hold a `FocusNode`:

```dart
final _editor = FocusNode(debugLabel: 'editor');

// later
_editor.requestFocus();
if (_editor.hasFocus) { /* … */ }

@override
void dispose() {
  _editor.dispose();   // nodes are resources — always dispose
  super.dispose();
}
```

Pass it to the `Focus` it belongs to:

```dart
Focus(focusNode: _editor, child: Editor());
```

## Reacting to focus

To do something when focus enters or leaves a whole subtree — pause a
simulation, dim an inactive panel, stop a cursor blinking — use
`FocusDetector`. It fires for the subtree, not just one node, so focus moving
*between* two children doesn't report a change:

```dart
FocusDetector(
  onFocusChange: (hasFocus) => setState(() => _active = hasFocus),
  child: Panel(child: body),
);
```

## Tab order

`Tab` and `Shift+Tab` cycle focus in reading order — top to bottom, then left to
right. Inside a `FleuryApp(home: ...)` route you get this automatically.

A bare widget passed straight to `runApp` has a focus manager but no traversal
policy, so wrap it when it has more than one control:

```dart
runApp(
  FocusTraversalGroup(
    child: MyTwoPaneApp(),
  ),
);
```

`FocusTraversalGroup` also gives you **arrow-key traversal**: `←` `→` `↑` `↓`
move focus to the nearest focusable in that direction. It only acts on keys the
focused widget didn't already use, so `↓` inside a list still moves the list's
selection — traversal takes over at the edges.

Add your own group to *scope* traversal: a pane that should cycle on its own, or
a reusable widget you embed in apps you don't control.

## Excluding widgets from focus

Two different questions, two different knobs:

```dart
// Reachable by click, skipped by Tab — e.g. a button you don't want in
// the tab cycle.
Focus(skipTraversal: true, child: Button());

// Not focusable at all, by any route.
Focus(canRequestFocus: false, child: Decorative());

// A whole subtree taken out of focus — a hidden tab, an offscreen page
// kept alive.
ExcludeFocus(child: HiddenPage());
```

`skipTraversal` and `canRequestFocus` differ on purpose: click-to-focus and Tab
traversal are separate paths, and a control can reasonably be one but not the
other.

## Trapping focus in a dialog

A modal `FocusScope` keeps focus inside it — `Tab` cycles within the dialog
instead of walking out into the app behind it. It also truncates the key
dispatch chain at its boundary, so your app-wide bindings don't fire while the
dialog is open:

```dart
FocusScope(
  modal: true,
  child: Dialog(child: content),
);
```

This is what Fleury's own overlays (`Select`, `Menu`) use. Note that
`KeyBindings(modal: true)` is a *different* mechanism — it stops the key walk,
but not traversal. Use the focus scope when the dialog must trap `Tab` too.

## Reference

| API | What it does |
|---|---|
| `Focus` | Makes a subtree focusable; `autofocus`, `skipTraversal`, `canRequestFocus` live here. |
| `FocusNode` | A focus target you hold and drive: `requestFocus()`, `hasFocus`, `dispose()`. |
| `FocusDetector` | Calls back when focus enters or leaves a subtree. |
| `FocusTraversalGroup` | Scopes `Tab` cycling and arrow traversal to a subtree. |
| `FocusScope` | A focus boundary; `modal` traps traversal and stops keys reaching the app behind it. |
| `ExcludeFocus` | Removes a whole subtree from focus. |
| `FocusManager` | The app-level owner of the focus chain — rarely used directly. |

## How arrow traversal picks a target

Worth knowing when a layout doesn't move focus the way you expected. Pressing an
arrow that the focused widget didn't consume runs this search:

1. **Filter by direction.** Only focusable, attached, non-`skipTraversal`
   candidates whose center lies strictly past the current widget's center in
   that direction are eligible.
2. **Prefer near relatives.** Candidates sharing deeper tree ancestry with the
   current widget win, so siblings in the same pane beat far-away app chrome.
3. **Prefer descendants over shells.** A focusable child beats a focusable
   viewport or container ancestor when both are eligible.
4. **Weighted distance.** Cross-axis distance costs more than along-axis
   distance, but not infinitely — a much closer pane can still win.
5. **Stable tie-break.** Major-axis distance, then minor-axis, then traversal
   order.

If nothing qualifies, the key is left unhandled so an ancestor can still react.

The practical consequence: traversal follows *layout*, not declaration order, so
moving a widget on screen changes where the arrows go. When a jump feels wrong,
it's usually rule 2 or 3 — the intended target is in a different part of the
tree than it looks on screen. Wrapping the region in its own
`FocusTraversalGroup` scopes the search and usually settles it.
