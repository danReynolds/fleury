// Compile-checked source behind the hand-written fences in "Coming from
// Flutter" (website/src/content/docs/coming-from-flutter.mdx). The page's
// larger examples are excerpts of lib/flutter_map.dart, which the live demos
// run; this file covers the short fragments, verbatim, in page order.

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

// `FleuryApp` is deliberately smaller than `MaterialApp`.
void main(List<String> args) => runApp(
  FleuryApp(
    title: 'My app',
    theme: ThemeData(
      colorScheme: const ColorScheme(primary: RgbColor(0x3D, 0xDC, 0x97)),
    ),
    home: const MyHomeScreen(),
  ),
  args: args,
  mode: const TerminalMode(mouse: true),
);

class MyHomeScreen extends StatelessWidget {
  const MyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('My app');
}

/// The page's fragments; the parameters stand in for the app's own names.
void pageSnippets({required Widget details, required bool open}) {
  // Renamed or simplified: EdgeInsets values are cells.
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: Text('two columns, one row'),
  );

  // Animation is value-first.
  final fill = Animation(0.0);

  fill.to(0.8, spring: Spring.snappy);
  fill.loop(between: (0.3, 1.0));

  Text('Saved').animate().fadeIn().slideIn();
  AnimatedVisibility(
    visible: open,
    enter: Effects.expand(),
    child: Panel(title: 'Details', child: details),
  );
}
