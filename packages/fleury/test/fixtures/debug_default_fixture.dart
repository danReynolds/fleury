// Prints whether runApp brought debug tooling up in THIS launch — run from
// source, from a snapshot, with or without assertions — by what it does: with
// debug tooling on, the debug shell consumes Ctrl+G before the app's onEvent
// ever sees it. Pass `on` / `off` to set DebugConfig.enabled explicitly.
//
// Used by test/debug/debug_default_test.dart.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';

class _Mounted extends StatelessWidget {
  const _Mounted(this.mounted);
  final Completer<void> mounted;

  @override
  Widget build(BuildContext context) {
    if (!mounted.isCompleted) mounted.complete();
    return const Text('probe');
  }
}

Future<void> main(List<String> args) async {
  final explicit = switch (args.firstOrNull) {
    'on' => true,
    'off' => false,
    _ => null,
  };
  final driver = FakeTerminalDriver();
  final mounted = Completer<void>();
  var appSawCtrlG = false;
  final app = runApp(
    _Mounted(mounted),
    driver: driver,
    enableHotReload: false,
    debug: DebugConfig(enabled: explicit),
    onEvent: (event) {
      if (event is KeyEvent && event.code.character == 'g' && event.hasCtrl) {
        appSawCtrlG = true;
      }
      return null;
    },
  );
  await mounted.future;
  driver.enqueue(
    const KeyEvent(KeyCode.char('g'), modifiers: {KeyModifier.ctrl}),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  exitApp();
  await app;
  await driver.dispose();
  stdout.writeln('DEBUG_TOOLING=${appSawCtrlG ? 'off' : 'on'}');
}
