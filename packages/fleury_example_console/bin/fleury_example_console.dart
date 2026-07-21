import 'package:fleury/fleury.dart';

import '../lib/fleury_example_console.dart';

Future<void> main() {
  return runApp(
    const DemoConsoleApp(),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.code.character == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}
