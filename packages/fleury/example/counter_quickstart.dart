// The README "Quick start" example, kept as a compiled, tested file so
// the front-door docs can never silently rot. If you change this file,
// update the snippet in README.md to match (and vice versa).
//
// Run it:
//
//   # From packages/fleury:
//   dart run example/counter_quickstart.dart
//   # Press space to increment, Ctrl+C to quit.

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
