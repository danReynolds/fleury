// Architecture regression probe: the expired callback must now be rejected.
import 'dart:async';
import 'package:fleury/fleury.dart';

Future<void> main() async {
  final firstDriver = FakeTerminalDriver();
  var staleAccepted = false;
  final first = runApp(
    const Text('first'),
    driver: firstDriver,
    enableHotReload: false,
    onEvent: (event) {
      if (event is KeyEvent && event.code == KeyCode.enter) {
        Timer(const Duration(milliseconds: 100), () {
          staleAccepted = exitApp();
        });
        return const ExitRequested();
      }
      return null;
    },
  );
  await Future<void>.delayed(const Duration(milliseconds: 20));
  firstDriver.enqueue(const KeyEvent(KeyCode.enter));
  await first;
  await firstDriver.dispose();
  final secondDriver = FakeTerminalDriver();
  final watch = Stopwatch()..start();
  final second = runApp(
    const Text('second'),
    driver: secondDriver,
    enableHotReload: false,
  );
  final backup = Timer(const Duration(milliseconds: 700), exitApp);
  await second;
  backup.cancel();
  await secondDriver.dispose();
  print(
    'stale exit accepted=$staleAccepted; '
    'second ended at ${watch.elapsedMilliseconds}ms',
  );
}
