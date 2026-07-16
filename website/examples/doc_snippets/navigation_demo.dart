// Compile-checked source behind the Navigation guide. Exercises context.push
// (awaiting a result), context.pop(result), Navigator.of(context), PopScope, and
// RouteTransition against the real API. Guarded by ../test/doc_snippets_test.dart
// so the guide can't drift. See README.md.

import 'package:fleury/fleury.dart';

void main() =>
    runApp(const FleuryApp(title: 'Navigation demo', home: NavApp()));

class NavApp extends StatelessWidget {
  const NavApp({super.key});

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final confirmed = await context.push<bool>(
        const DetailScreen(),
        transition: RouteTransition.slide,
      );
      if (confirmed == true) {
        // act on the result
      }
    },
    child: const Text('Open detail'),
  );
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    child: GestureDetector(
      onTap: () => context.pop(true),
      child: Text(Navigator.of(context).canPop ? 'Close' : 'Home'),
    ),
  );
}
