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
    return KeyBindings(
      bindings: [KeyBinding(.space, onEvent: (_) => setState(() => _count++))],
      child: Center(
        child: Text('count: $_count   (space to increment, Ctrl+C to quit)'),
      ),
    );
  }
}
```

A runnable counterpart lives at `example/counter_quickstart.dart` and is
covered by `test/example/counter_quickstart_test.dart`; the test mounts the app
and exercises the space-to-increment behavior.

`runApp` installs the binding, enters raw mode + the alternate screen,
detects terminal capabilities (color depth, image protocol, multiplexer),
wires input dispatch and the frame scheduler, and renders your widget
tree with a diffing ANSI renderer. Unhandled Ctrl+C exits by default.

## What's in the box

- **Framework**: `Widget` / `StatefulWidget` / `State`, `BuildContext`,
  `InheritedWidget`, keys + reconciliation, `MediaQuery`, layout
  constraints, the `RenderObject` tree, and a swappable
  `TerminalDriver` (POSIX today; `fleury_web` renders the same tree to a
  browser DOM cell grid — selectable text and a real accessibility tree,
  not a canvas bitmap).
- **Layout**: `Row` / `Column` / `Flex`, `Stack`, `Align` / `Center`,
  `Padding`, `SizedBox`, `Expanded` / `Flexible`, intrinsic sizing,
  `LayoutBuilder`.
- **Input + focus**: key bindings, focus traversal (Tab / directional),
  modal focus scopes, mouse + pointer routing, paste handling.
- **Navigation**: `Navigator` with routes + an `Overlay` for modals,
  menus, tooltips, and toasts.
- **Animation**: `AnimationBuilder` + `Animation` (spring-based,
  value-driven) and `FrameBuilder` / `FrameTicker` (frame-indexed),
  sharing one per-runtime scheduler. See below.
- **Hot reload**: state-preserving reload wired for VS Code — see
  [`doc/hot_reload.md`](doc/hot_reload.md).
- **Widgets**: a deep catalog lives in the companion `fleury_widgets`
  package — inputs, selects, tables, trees, charts, an image widget
  with four terminal graphics protocols, and more.

Design rationale and the phased delivery plan live in the RFC:
[`docs/rfcs/0007-fleury-framework.md`](../../docs/rfcs/0007-fleury-framework.md).

## Testing

Add `fleury_test` as a dev dependency, then use `FleuryTester` (the
`testWidgets` analog) from `package:fleury_test/fleury_test.dart`:

```yaml
dev_dependencies:
  fleury_test: ^0.1.0
  test: ^1.26.3
```

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

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

The animation system lives in two coordinated lanes — value-driven
springs (`AnimationBuilder` + `Animation`, which retarget from the live
value AND velocity so an interruption mid-flight stays smooth instead of
snapping) and discrete frame-indexed primitives (`FrameTicker` /
`FrameBuilder`). Both share a single per-runtime `TickerScheduler` owned by
the `TuiBinding` that `runApp` installs at the root; idle apps burn no
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

Most animations are one widget. `AnimationBuilder<T>` owns an `Animation`,
retargets whenever `value` changes, and disposes itself — no
`StatefulWidget`, no `didUpdateWidget`, no `dispose`. The engine is a
spring, so a retarget mid-flight continues from the live value and velocity
instead of restarting:

```dart
// A number that springs toward its target whenever `value` changes.
AnimationBuilder<int>(value, builder: (context, v) => Text('$v'))

// A panel that springs open/closed — toggle rapidly and it stays smooth.
AnimationBuilder<int>(
  open ? 30 : 0,
  spring: Spring.snappy,
  builder: (context, width) => SizedBox(width: width, child: child),
)
```

For sequences, loops, or an animation you drive imperatively, hold an
`Animation<T>` in your `State` and run steps against it:

```dart
final _x = Animation<int>(28);

// A toast: slide in, hold, slide out. The returned future fires at the end.
await _x.run([
  AnimationStep.to(0, spring: Spring.snappy),
  const AnimationStep.hold(Duration(seconds: 2)),
  AnimationStep.to(28,
      curve: Curves.easeIn, duration: const Duration(milliseconds: 200)),
]);

// A pulsing dot: ping-pong forever; settles to nothing when off-screen.
final _c = Animation<RgbColor>(const RgbColor(120, 0, 0))
  ..loop(
    between: (const RgbColor(120, 0, 0), const RgbColor(255, 60, 60)),
    period: const Duration(milliseconds: 700),
    curve: Curves.easeInOut,
  );
```

`example/animation_recipes.dart` is a runnable gallery of these patterns —
counter, interruptible panel, toast, badge flash, selection highlight,
health color — each mirrored by a widget test in
`test/example/animation_recipes_test.dart`.

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
  decorative animations; springs and `run` sequences settle to their
  target instantly.

### Examples

- `example/animation_showcase.dart` — every animated widget
  demonstrated together.
- `example/chat_demo.dart` — a `Spinner` integrated into the
  message-pane header of the full chat layout.

### Color

`rgbColorLerp(a, b, t)` interpolates `RgbColor` channels linearly; feed the
result to an `Animation<RgbColor>` (or read it inside an
`AnimationBuilder<RgbColor>`) to glide a color toward a target. Indexed ANSI
colors aren't on a meaningful number line, so animate the RGB value rather
than interpolating palette indices.
