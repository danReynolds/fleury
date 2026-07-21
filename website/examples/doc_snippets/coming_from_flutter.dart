// Compile-checked source behind "Coming from Flutter"
// (website/src/content/docs/coming-from-flutter.md). Keeps the core migration
// examples honest: runApp, KeyBindings, context.push/context.pop,
// AnimationBuilder, Reveal, and Effects.

import 'dart:async';

import 'package:fleury/fleury.dart';

void main() => runApp(const FleuryApp(title: 'Counter', home: CounterApp()));

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
          KeySequence.space,
          label: 'Increment',
          onTrigger: () => setState(() => _count++),
        ),
        KeyBinding(
          KeySequence.enter,
          label: 'Details',
          onTrigger: () => unawaited(context.push<void>(const DetailScreen())),
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

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeySequence.escape,
          label: 'Close',
          onTrigger: () => context.pop(),
        ),
      ],
      child: Reveal(
        visible: true,
        enter: Effects.expand() + Effects.fadeIn(),
        child: AnimationBuilder<double>(
          0.8,
          builder: (context, t) =>
              Text('animated value: ${t.toStringAsFixed(2)}'),
        ),
      ),
    );
  }
}
