---
title: Coming from Flutter
description: A practical map from Flutter's widget model to Fleury's cell-grid UI model.
---

Fleury is deliberately familiar if you know Flutter: apps are widget trees,
state lives in `State`, `build` returns widgets, and `setState` schedules a
rebuild. The difference is the surface. Flutter lays out pixels and usually
leans on Material/Cupertino; Fleury lays out terminal-style **cells** and can
paint the same tree to a real terminal, a browser embed, or a served browser
session.

This is not a Flutter renderer or a Material porting layer. It is the same
programming model, tuned for keyboard-first tools, dashboards, agent UIs, and
structured terminal/browser surfaces.

## The short version

| Flutter instinct | Fleury answer |
|---|---|
| `Widget`, `State`, `BuildContext`, `setState` | Same model, same names. |
| `runApp(const MyApp())` | Same name for terminal/native apps. |
| `MaterialApp` / `WidgetsApp` | `FleuryApp(title:, home:, theme:)` is the lightweight app shell. |
| logical pixels | integer cells (`EdgeInsets.all(1)`, not `8.0`). |
| Material controls | Fleury core widgets plus `fleury_widgets` for tables, charts, forms, agent surfaces, and controls. |
| Flutter web build | `mountApp(() => const FleuryApp(title: 'My app', home: MyApp()), into: host)` for client-side browser embeds, or `fleury serve` for a native app streamed to the browser. |

## A tiny app

If you can read this Flutter-style counter, you can read Fleury:

```dart
import 'package:fleury/fleury.dart';

void main() => runApp(
  const FleuryApp(title: 'Counter', home: CounterApp()),
);

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.space,
          label: 'Increment',
          onEvent: (_) => setState(() => _count++),
        ),
      ],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('count: $_count'),
            const SizedBox(height: 1),
            const Text('press Space'),
          ],
        ),
      ),
    );
  }
}
```

The important differences are visible in the imports and input model:

- `package:fleury/fleury.dart` is the native terminal app umbrella.
- `KeyBindings` maps terminal/browser key chords directly to callbacks.
- Layout dimensions are cells, so `height: 1` means one terminal row.

## Imports and entrypoints

Most Flutter developers expect one app root and one rendering target. Fleury has
the same widget tree, but different host entrypoints:

| Use case | Import | Entrypoint |
|---|---|---|
| Native terminal app | `package:fleury/fleury.dart` | `runApp(const FleuryApp(title: 'My app', home: MyApp()))` |
| Higher-level widgets in a terminal app | `package:fleury_widgets/fleury_widgets.dart` | still `runApp` |
| Client-side browser embed | `package:fleury/fleury_core.dart`, `package:fleury_web/fleury_web.dart`, plus web-safe widgets | `mountApp(() => const FleuryApp(title: 'My app', home: MyApp()), into: host)` |
| Browser session backed by a native process | terminal app imports | `fleury serve --spawn dart run my_app.dart` |

For a browser embed, the entrypoint is a tiny web file:

```dart
import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final host = web.document.getElementById('app')!;
  mountApp(
    () => const FleuryApp(title: 'My app', home: MyApp()),
    into: host,
  );
}
```

Client-side browser bundles can only use web-safe code. Import
`package:fleury_widgets/fleury_widgets_web.dart` instead of the full
`fleury_widgets.dart` barrel when compiling with dart2js. If the app needs
`dart:io` widgets such as file/process/log surfaces, ship it as a terminal app
or use `fleury serve`.

## Same API, same mental model

These transfer with little or no adjustment:

| Area | Carries over |
|---|---|
| Core model | `Widget`, `StatelessWidget`, `StatefulWidget`, `State`, `build`, `setState`, `BuildContext`, `InheritedWidget` |
| Keys | `Key`, `ValueKey`, `UniqueKey`, `GlobalKey` |
| Layout | `Column`, `Row`, `Expanded`, `Flexible`, `Spacer`, `Stack`, `Positioned`, `Padding`, `Center`, `Align`, `Container`, `ConstrainedBox`, `AspectRatio`, `SizedBox`, `Wrap`, `IntrinsicWidth`, `IntrinsicHeight`, `LayoutBuilder` |
| Async | `FutureBuilder`, `StreamBuilder`, `AsyncSnapshot`, `ConnectionState` |
| Navigation | `Navigator.push`, `pop`, `pushReplacement`, `popUntil`, `PopScope`, plus `context.push` / `context.pop` helpers |
| Focus and pointer input | `FocusNode`, `Focus`, `FocusScope`, `GestureDetector`, `MouseRegion` |
| Lists | `ListView`, `ListView.builder`, `ScrollView` |
| Inherited data | `Theme.of`, `MediaQuery.of`, `DefaultTextStyle`, `ListenableBuilder`, `ChangeNotifier`, `Listenable` |
| Text | `Text`, `RichText`, `TextSpan` |

The table is intentionally boring: most of the muscle memory is valid.

## Renamed or simplified

| Flutter | Fleury | Why |
|---|---|---|
| `TextStyle` | `CellStyle` | A cell has foreground/background color and terminal attributes such as bold, dim, underline, and inverse. It does not have fonts. |
| `BoxConstraints` | `CellConstraints` | Constraints are integer cells; `null` represents unbounded. |
| `Offset` / `Size` | `CellOffset` / `CellSize` | Coordinates and dimensions are whole cells. |
| `AnimatedBuilder` | `ListenableBuilder` | Rebuild from any `Listenable`: an `Animation`, a `ChangeNotifier`, or another notifier. |
| `TweenAnimationBuilder` | `AnimationBuilder` | Animate a value toward a new target when it changes. |
| `SingleChildScrollView` | `ScrollView` | A scrollable viewport around one child. |
| `Shortcuts` / `Actions` / `Intent` | `KeyBindings` / `KeyChord` | A key chord maps directly to a callback; no `Intent` layer. |

`EdgeInsets` keeps the familiar constructors (`all`, `symmetric`, `only`), but
the values are cells:

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
  child: Text('two columns, one row'),
)
```

## Where Flutter instincts need adjustment

### Cells are not pixels

Fleury layout is integer cell layout. Width is columns; height is rows. A
terminal cell is usually taller than it is wide, so a visually square box often
uses an `AspectRatio` around `2.0`, not `1.0`.

That sounds small, but it changes what "polish" means. You tune information
density, alignment, wrapping, keyboard flow, and semantic structure before you
think about pixel-perfect spacing.

### `FleuryApp` is deliberately smaller than `MaterialApp`

You do not port `MaterialApp`, `CupertinoApp`, or `WidgetsApp` wholesale.
`runApp` installs terminal host services such as `MediaQuery`, focus, pointer
routing, the root `Overlay`, log capture, and scheduling. `FleuryApp` owns the
application concerns: its theme and command/status/extension scopes sit above
its `Navigator`, so pushed routes keep the same app context.

```dart
void main() => runApp(
  FleuryApp(
    title: 'My app',
    theme: ThemeData(
      colorScheme: const ColorScheme(primary: RgbColor(0x3D, 0xDC, 0x97)),
    ),
    home: const MyApp(),
  ),
);
```

Small one-screen tools can still pass a bare widget to `runApp`. For a custom
navigation topology, use `FleuryApp(child: ...)` and place explicit `Navigator`
widgets in that shell. `child` does not create an implicit route stack.

### Input is keyboard-first, pointer-aware

Flutter's `Shortcuts` / `Actions` stack is intentionally simpler in Fleury:

```dart
KeyBindings(
  bindings: [
    KeyBinding(KeyChord.ctrl.s, label: 'Save', onEvent: (_) => save()),
    KeyBinding(KeyChord.escape, label: 'Cancel', onEvent: (_) => cancel()),
  ],
  child: editor,
)
```

Pointer and hover still exist through `GestureDetector` and `MouseRegion`, but
terminal users expect every important workflow to work from the keyboard.

### Animation is value-first

Flutter's `Animation<T>` is usually a read-only listenable driven by an
`AnimationController`. Fleury's `Animation<T>` is the mutable value you retarget:

```dart
final fill = Animation(0.0);

fill.to(0.8, spring: Spring.snappy);
fill.loop(between: (0.3, 1.0));
```

For the common "animate when this state value changes" case, use
`AnimationBuilder`:

```dart
AnimationBuilder<double>(
  selected ? 1.0 : 0.0,
  builder: (context, t) => Text('selected: ${t.toStringAsFixed(2)}'),
)
```

For entrance/exit effects, use `Animate` or `Reveal`:

```dart
Text('Saved').animate().fadeIn().slideIn();
Reveal(visible: open, enter: Effects.expand(), child: Panel());
```

### Routes are widgets, not route names

With `FleuryApp(home: ...)` there is no `MaterialPageRoute` and no named-route
table. Push the widget you want to show:

```dart
context.push(DetailScreen(id: id));
context.popUntil<HomeScreen>();
```

Use `PopScope` for the same kind of "can this route close?" guard you would use
in Flutter.

## Not there, and what to use instead

| Flutter | Use instead |
|---|---|
| `InkWell` / ripples | `GestureDetector`, `MouseRegion`, focus styles, and key hints. |
| `Scaffold`, `AppBar`, Material layout chrome | Compose Fleury widgets directly; terminal apps usually want denser app-specific chrome. |
| `CustomScrollView` / slivers / `GridView` | `ListView`, `ListView.builder`, `ScrollView`, `Wrap`, or purpose-built table/tree widgets. |
| `ValueListenableBuilder` / plain `Builder` | `ListenableBuilder` or a small `StatelessWidget`. |
| `FittedBox` / `FractionallySizedBox` / `OverflowBox` | `LayoutBuilder`, `ConstrainedBox`, explicit cell sizing, and wrapping/clipping behavior. |
| `Hero` / route-shared element transitions | `Reveal`, route transitions, or simpler terminal-native motion. |

## Porting checklist

1. Start with the app's state and widget structure; most `StatefulWidget` /
   `setState` code ports directly.
2. Replace `MaterialApp` with `FleuryApp(title:, home:, theme:)`; keep `runApp`
   focused on the terminal host.
3. Translate dimensions from pixels to cells. Remove `double` spacing habits.
4. Replace Material controls with Fleury widgets or focused app-specific
   widgets.
5. Add keyboard paths first, then pointer affordances.
6. Decide the host: terminal `runApp`, static browser `mountApp`, or native app
   streamed through `fleury serve`.

The fastest way in is the [tutorial](/fleury/tutorial/), then
[Widgets & state](/fleury/concepts/widgets-and-state/) and [App entry points](/fleury/concepts/app-entry/).
