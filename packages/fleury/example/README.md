# Fleury examples

## A counter

The smallest complete Fleury app: a counter that goes up when you press space.

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
      bindings: [
        KeyBinding(.space, onTrigger: (_) => setState(() => _count++)),
      ],
      child: Center(
        child: Text('count: $_count   (space to increment, Ctrl+C to quit)'),
      ),
    );
  }
}
```

This is `example/counter_quickstart.dart`, which
`test/example/counter_quickstart_test.dart` mounts and drives with the space
key. To start a project of your own, run `fleury create my_app`; the
[getting started guide](https://danreynolds.github.io/fleury/getting-started/)
walks through it.

## Run the examples

Unpack the package with `dart pub unpack fleury`, or use `packages/fleury` in a
checkout of the [repository](https://github.com/danReynolds/fleury). From that
directory, run each command in an interactive terminal. Ctrl+C quits.

- `example/counter_quickstart.dart`, the counter above: `dart run example/counter_quickstart.dart`
- `example/counter_demo.dart`, a counter you change with + and -, laid out with rows, columns, and padding: `dart run example/counter_demo.dart`
- `example/core_editor.dart`, search a list, edit a value, save with Ctrl+S, and confirm a delete: `dart run example/core_editor.dart`
- `example/inline_picker.dart`, a picker drawn below the shell prompt that prints the choice: `dart run example/inline_picker.dart`
- `example/chat_demo.dart`, a three-pane chat with lists, a composer, and arrow-key focus moves: `dart run example/chat_demo.dart`
- `example/selection_demo.dart`, mouse and keyboard text selection with clipboard copy: `dart run example/selection_demo.dart`
- `example/animation_showcase.dart`, every animated widget on one screen: `dart run example/animation_showcase.dart`
- `example/animation_recipes.dart`, common animation patterns such as springs, toasts, and badge flashes: `dart run example/animation_recipes.dart`
- `example/hot_reload_demo.dart`, state that survives a hot reload. Save-to-reload watches only `lib/` and `bin/`, so reload edits to this file with Dart: Hot Reload in your editor's debugger. From a terminal, Ctrl+G then F5 restarts it with your edits: `dart run fleury run example/hot_reload_demo.dart`
- `example/showcase.dart`, paints one frame of a richer layout on the alternate screen and leaves it a moment later, so the frame vanishes; run it under script(1) to capture the output: `dart run example/showcase.dart`
- `example/catalog/app_shell_demo.dart`, an app shell with routes, a command palette, and shortcuts: `dart run example/catalog/app_shell_demo.dart`
- `example/catalog/dashboard_demo.dart`, a live dashboard of charts, gauges, and a heatmap: `dart run example/catalog/dashboard_demo.dart`
- `example/catalog/dashboard_snapshot.dart`, prints one dashboard frame as text, no terminal needed: `dart run example/catalog/dashboard_snapshot.dart`
- `example/catalog/image_demo.dart`, one generated image at three fits: `dart run example/catalog/image_demo.dart`
- `example/catalog/toast_lifecycle.dart`, a result toast that updates in place: `dart run example/catalog/toast_lifecycle.dart`
