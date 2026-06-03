import 'package:fleury/fleury.dart';

import '../lib/fleury_example_console.dart';

Future<void> main() {
  return runTui(
    const ProofConsoleApp(),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.char == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}
