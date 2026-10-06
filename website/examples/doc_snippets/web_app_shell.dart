// Compile-checked browser entry point. From its first import on, it is the
// web/main.dart that App entry points, Coming from Flutter and the fleury_web
// README show; test/docs_accuracy_test.dart pins each of them to it.

import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final host = web.document.getElementById('app')!;
  await mountApp(
    () => const FleuryApp(title: 'My app', home: MyHomeScreen()),
    into: host,
  );
}

class MyHomeScreen extends StatelessWidget {
  const MyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Hello from Fleury');
}
