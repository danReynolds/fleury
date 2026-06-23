---
title: Coming from Flutter
description: What's identical, what's renamed, and what's deliberately different — a Flutter developer's map to Fleury.
---

Fleury is the Flutter widget model on a cell grid. If you know Flutter, you
already know most of this — `Widget` / `State` / `build` / `setState` /
`BuildContext` / `InheritedWidget` all mean exactly what you expect. This page is
the map for the rest: what carries over unchanged, what got a new name, and the
few places Fleury deliberately diverges.

## Identical — same name, same idea

These transfer with no adjustment:

| Area | Carries over |
|---|---|
| Core model | `Widget`, `StatelessWidget`, `StatefulWidget`, `State`, `build`, `setState`, `BuildContext`, `InheritedWidget` |
| Keys | `Key`, `ValueKey`, `UniqueKey`, `GlobalKey` |
| Layout | `Column`, `Row`, `Expanded`, `Flexible`, `Stack`, `Positioned`, `Padding`, `Center`, `Align`, `Container`, `ConstrainedBox`, `AspectRatio`, `SizedBox`, `Wrap`, `IntrinsicWidth/Height`, `LayoutBuilder` |
| Async | `FutureBuilder`, `StreamBuilder`, `AsyncSnapshot`, `ConnectionState` |
| Navigation | `Navigator.push` / `pop` / `pushReplacement` / `popUntil`, `PopScope` |
| Input | `GestureDetector`, `MouseRegion`, `FocusNode`, `Focus`, `FocusScope` |
| Lists | `ListView`, `ListView.builder` |
| Inherited data | `Theme.of`, `MediaQuery.of`, `DefaultTextStyle`, `ListenableBuilder`, `ChangeNotifier`, `Listenable` |
| Rich text | `RichText`, `TextSpan` |

If your Flutter instinct is to type one of these, type it — it's there.

## Renamed — same idea, new name

| Flutter | Fleury | Why |
|---|---|---|
| `TextStyle` | `CellStyle` | A cell has terminal attributes (bold, dim, inverse, fg/bg) — not fonts. |
| `BoxConstraints` | `CellConstraints` | Integer cells, with `null` for "unbounded" instead of `double.infinity`. |
| `Offset` / `Size` | `CellOffset` / `CellSize` | Whole-cell coordinates. |
| `AnimatedBuilder` | `ListenableBuilder` | Rebuild on any `Listenable` (pass an `Animation`, a `ChangeNotifier`…). |
| `TweenAnimationBuilder` | `AnimationBuilder` | Animate a value toward a target when it changes. |
| `SingleChildScrollView` | `ScrollView` | A scrollable viewport onto one child. |
| `Shortcuts` / `Actions` / `Intent` | `KeyBindings` / `KeyChord` | A chord maps straight to a callback — no `Intent` indirection. |

A note on `EdgeInsets`: same API (`all` / `symmetric` / `only`), but the values
are **integer cells**, not doubles — `EdgeInsets.all(1)`, not `8.0`.

## Deliberately different — read these

A handful of things look familiar but behave differently on purpose.

### `Animation` is a mutable value, not a read-only one

This is the big one. **In Flutter, `Animation<T>` is a read-only listenable** that
an `AnimationController` drives over `Tween`s. **In Fleury, `Animation<T>` is the
*mutable* thing you drive** — you create it, read `.value`, and retarget it with
one verb:

```dart
final fill = Animation(0.0);   // not Flutter's read-only Animation
fill.to(0.8, spring: Spring.snappy);
fill.loop(between: (0.3, 1.0));
```

It's spring-driven by default (so interrupting an in-flight animation is
velocity-preserving for free), and it fuses what Flutter splits across
`AnimationController` + `Tween` + a listenable into one object. We kept the name
`Animation` because it's the right word for what it is — just know it points the
other way from Flutter's. See [Animation](/guides/animation/).

### There's no `MaterialApp` / `WidgetsApp`

You don't wrap your app in a root widget. `runTui(MyApp())` assembles the
ambient scaffold for you — it injects `MediaQuery`, the focus root, pointer
routing, an `Overlay`, and a root `Navigator`, so `context.push` /
`MediaQuery.of` / focus all work out of the box. The one thing it does **not**
inject is a `Theme` — `Theme.of(context)` returns sensible defaults until you
wrap a subtree in your own `Theme`. See [App entry points](/concepts/app-entry/).

### Implicit-animation widgets → the effects system

There's no `AnimatedContainer`, `AnimatedOpacity`, `AnimatedSwitcher`, `Hero`, or
`AnimatedList`. Instead, animate any widget with the fluent `.animate()` effects,
animate a value with `AnimationBuilder`, or mount/unmount with `Reveal`:

```dart
Text('Saved').animate().fadeIn().slideIn();   // entrance
Reveal(visible: open, enter: Effects.expand(), child: Panel());
```

### Routes are widgets, not named strings

No `MaterialPageRoute` or named-route table. You push a widget and pop by type:

```dart
context.push(DetailScreen(id: id));
context.popUntil<HomeScreen>();
```

### Everything is integer cells

Sizes, offsets, and insets are whole cells, not logical pixels. And a terminal
cell is about twice as tall as it is wide, so an `AspectRatio` of `0.5` reads as
visually square. See [Layout](/guides/layout/).

## Not there (yet) — and what to use instead

| Flutter | Use instead |
|---|---|
| `Spacer` | `Expanded(child: EmptyBox())` (a `Spacer` is on the way) |
| `InkWell` | `GestureDetector` + `MouseRegion` (no ripple in a terminal) |
| `CustomScrollView` / slivers / `GridView` | `ListView` / `ListView.builder` / `ScrollView` |
| `ValueListenableBuilder` / plain `Builder` | `ListenableBuilder` / a small `StatelessWidget` |
| `FittedBox` / `FractionallySizedBox` / `OverflowBox` | `LayoutBuilder` + explicit sizing |

---

The fastest way in: do the [tutorial](/tutorial/) (it's pure Flutter muscle
memory), then skim [Widgets & state](/concepts/widgets-and-state/) for the two or
three spots where the cell grid changes the rules.
