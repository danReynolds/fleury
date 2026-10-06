// The README's browser app: a Fleury widget tree mounted into a page element.
//
// Compile it next to index.html, then serve this directory with any static
// file server and open index.html:
//
//   dart compile js example/main.dart -o example/app.js -O2

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
