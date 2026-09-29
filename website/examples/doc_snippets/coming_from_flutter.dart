// Compile-checked source behind "Coming from Flutter"
// (website/src/content/docs/coming-from-flutter.md). Keeps the core migration
// examples honest: runApp, KeyBindings, context.push/context.pop,
// AnimationBuilder, AnimatedVisibility, and Effects. `pageSnippets` holds the
// page's short fragments verbatim, so each one compiles as written.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

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
          onTrigger: (_) => setState(() => _count++),
        ),
        KeyBinding(
          KeySequence.enter,
          label: 'Details',
          onTrigger: (_) => unawaited(context.push<void>(const DetailScreen())),
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
  const DetailScreen({super.key, this.id = ''});

  final String id;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeySequence.escape,
          label: 'Close',
          onTrigger: (_) => context.pop(),
        ),
      ],
      child: AnimatedVisibility(
        visible: true,
        enter: Effects.expand() + Effects.fadeIn(),
        child: AnimationBuilder<double>(
          0.8,
          builder: (context, t, child) =>
              Text('animated value: ${t.toStringAsFixed(2)}'),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const CounterApp();
}

/// The page's fragments, in page order. Each statement block matches a fence
/// on the page; the parameters stand in for the app's own names.
void pageSnippets(
  BuildContext context, {
  required Widget editor,
  required Widget details,
  required bool selected,
  required bool open,
  required String id,
  required void Function() save,
  required void Function() cancel,
}) {
  // Input is keyboard-first, pointer-aware.
  KeyBindings(
    bindings: [
      KeyBinding(KeySequence.ctrl.s, label: 'Save', onTrigger: (_) => save()),
      KeyBinding(
        KeySequence.escape,
        label: 'Cancel',
        onTrigger: (_) => cancel(),
      ),
    ],
    child: editor,
  );

  // Animation is value-first.
  final fill = Animation(0.0);

  fill.to(0.8, spring: Spring.snappy);
  fill.loop(between: (0.3, 1.0));

  AnimationBuilder<double>(
    selected ? 1.0 : 0.0,
    builder: (context, t, child) => Text('selected: ${t.toStringAsFixed(2)}'),
  );

  Text('Saved').animate().fadeIn().slideIn();
  AnimatedVisibility(
    visible: open,
    enter: Effects.expand(),
    child: Panel(title: 'Details', child: details),
  );

  // Routes are widgets, not route names.
  context.push<void>(DetailScreen(id: id));
  context.popUntil<HomeScreen>();
}
