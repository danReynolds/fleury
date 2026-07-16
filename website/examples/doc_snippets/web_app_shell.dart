// Compile-checked browser counterpart to the mountApp snippets in App entry
// points and Coming from Flutter.

import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final host = web.document.getElementById('app')!;
  await mountApp(
    () => const FleuryApp(title: 'My app', home: HomeScreen()),
    into: host,
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Hello from Fleury');
}
