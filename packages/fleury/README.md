# Fleury

> Flutter ergonomics, terminal truth.

A Dart-native terminal UI framework that brings Flutter's familiar
authoring model — widgets, state, context, keys, constraints, inherited
dependencies, hot-reload-friendly rebuilds — to terminal UIs, while
implementing the runtime with terminal-native best practices: cell
buffers, ANSI diffing, raw-mode lifecycle management, grapheme-aware
text, capability detection, and safe input handling.

## Quick start

```dart
import 'package:fleury/fleury.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});
  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings.on(
      {.space: () => setState(() => _count++)},
      child: Center(
        child: Text('count: $_count   (space to increment, Ctrl+C to quit)'),
      ),
    );
  }
}
```

This exact example lives at `example/counter_quickstart.dart` and is
covered by `test/example/counter_quickstart_test.dart`, so the snippet
can't silently rot.

`runApp` installs the binding, enters raw mode + the alternate screen,
detects terminal capabilities (color depth, image protocol, multiplexer),
wires input dispatch and the frame scheduler, and renders your widget
tree with a diffing ANSI renderer. Ctrl+C always exits.

## What's in the box

- **Framework**: `Widget` / `StatefulWidget` / `State`, `BuildContext`,
  `InheritedWidget`, keys + reconciliation, `MediaQuery`, layout
  constraints, the `RenderObject` tree, and a swappable
  `TerminalDriver` (POSIX today; `fleury_web` renders the same tree to a
  browser canvas).
- **Layout**: `Row` / `Column` / `Flex`, `Stack`, `Align` / `Center`,
  `Padding`, `SizedBox`, `Expanded` / `Flexible`, intrinsic sizing,
  `LayoutBuilder`.
- **Input + focus**: key bindings, focus traversal (Tab / directional),
  modal focus scopes, mouse + pointer routing, paste handling.
- **Navigation**: `Navigator` with routes + an `Overlay` for modals,
  menus, tooltips, and toasts.
- **Animation**: `AnimationController` + `Tween` + `AnimatedBuilder`
  (continuous) and `FrameBuilder` / `FrameTicker` (frame-indexed),
  sharing one per-runtime scheduler. See below.
- **Hot reload**: state-preserving reload wired for VS Code — see
  [`doc/hot_reload.md`](doc/hot_reload.md).
- **Widgets**: a deep catalog lives in the companion `fleury_widgets`
  package — inputs, selects, tables, trees, charts, an image widget
  with four terminal graphics protocols, and more.

Design rationale and the phased delivery plan live in the RFC:
[`docs/rfcs/0007-fleury-framework.md`](../../docs/rfcs/0007-fleury-framework.md).

## Testing

Widget tests use `FleuryTester` (the `testWidgets` analog) from
`package:fleury/fleury_test.dart`:

```dart
testWidgets('space increments the counter', (tester) {
  tester.pumpWidget(const CounterApp());
  tester.sendKey(const KeyEvent(char: ' '));
  tester.pump();
  expect(tester.renderToString(), contains('count: 1'));
});
```

For whole-screen regression, assert against a golden:

```dart
expect(tester.renderToString(), matchesGolden('counter/initial.txt'));
```

Goldens write themselves on first run and update with
`FLEURY_UPDATE_GOLDENS=1 dart test` — review the diff before committing.

## Animation

The animation system lives in two coordinated lanes — continuous
tweens (Flutter-shaped: AnimationController + Tween + AnimatedBuilder)
and discrete frame-indexed primitives (FrameTicker / FrameBuilder).
Both share a single per-runtime `TickerScheduler` owned by the
`TuiBinding` that `runApp` installs at the root; idle apps burn no
scheduler CPU.

See [`docs/rfcs/0010-animation-infrastructure.md`](../../docs/rfcs/0010-animation-infrastructure.md)
for the design rationale.

### Ready-made widgets

```dart
Spinner()                          // braille (default) or ascii
Spinner(label: 'Connecting')
BlinkingCursor()                   // ~500 ms on/off block cursor
```

Drop them in anywhere — they're built on `FrameBuilder` and share
the scheduler with every other animation in the app.

### Custom animations

For typed value interpolation use `AnimationController` + `Tween` +
`AnimatedBuilder`, matching Flutter's idiom:

```dart
class _MyState extends State<MyWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = IntTween(begin: 0, end: 30).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: fill,
      builder: (ctx, _) => Text('█' * fill.value),
    );
  }
}
```

For low-frequency frame-indexed animations (spinners, cursor blink,
typing indicators), `FrameBuilder` is more direct:

```dart
FrameBuilder(
  interval: const Duration(milliseconds: 80),
  builder: (ctx, frame, elapsed, delta) {
    final frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    return Text(frames[frame % frames.length]);
  },
)
```

### Animation control

- `TickerMode(enabled: false, child: ...)` — mute tickers in a
  subtree (hidden tab, modal background). Internal elapsed-time
  state continues to advance so re-enabling resumes at the
  correct value; no replay of missed frames.
- `AnimationPolicy.disabled` on the binding — globally suppress
  decorative animations; AnimationController.forward / reverse
  / repeat snap to their end state synchronously.

### Examples

- `example/animation_showcase.dart` — every animated widget
  demonstrated together.
- `example/chat_demo.dart` — a `Spinner` integrated into the
  message-pane header of the full chat layout.

### Color tweens

`RgbColorTween` interpolates `RgbColor` channels linearly. Indexed
ANSI colors aren't on a meaningful number line, so the type system
rules out interpolating between them — for indexed colors use
`DiscreteTween<Color>` (swap at the midpoint).
