// Fixture for the "second same-process session" regression test. Runs two
// sequential PosixTerminalDriver sessions against the REAL process-global
// stdin (single-subscription), then falls off the end of main(). It must:
//   1. not crash on the second enter() ('Stream has already been listened to'),
//   2. still exit even though stdin is kept open by the parent — proving the
//      retained subscription's idle-cancel releases it (a merely-paused stdin
//      subscription would keep the event loop alive and hang here).
import 'dart:io';

import 'package:fleury/fleury.dart' show TerminalMode;
import 'package:fleury/src/terminal/posix_driver.dart';

Future<void> main() async {
  for (var i = 0; i < 2; i++) {
    final driver = PosixTerminalDriver();
    await driver.enter(TerminalMode.interactive);
    await driver.restore();
    stdout.writeln('SESSION-$i-OK');
    await stdout.flush();
  }
  stdout.writeln('ALL-SESSIONS-DONE');
  await stdout.flush();
}
