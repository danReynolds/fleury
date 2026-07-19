// Fixture for the "second same-process session" regression test. dart:io hands
// out the process-global stdin exactly once, so a second interactive session in
// one process cannot re-listen to it. This runs two sequential
// PosixTerminalDriver sessions against the REAL stdin and asserts the second is
// rejected with a CLEAR, legible error (not the opaque 'Stream has already been
// listened to') — and that the process then EXITS (a leaked/paused stdin
// subscription would keep the event loop alive and hang here).
import 'dart:io';

import 'package:fleury/fleury.dart' show TerminalMode;
import 'package:fleury/src/terminal/posix_driver.dart';

Future<void> main() async {
  final first = PosixTerminalDriver();
  await first.enter(TerminalMode.interactive);
  await first.restore();
  stdout.writeln('SESSION-0-OK');

  final second = PosixTerminalDriver();
  try {
    await second.enter(TerminalMode.interactive);
    stdout.writeln('SESSION-1-UNEXPECTEDLY-STARTED');
    await second.restore();
  } on StateError catch (e) {
    stdout.writeln(
      e.message.contains('one interactive session per process')
          ? 'SESSION-1-REJECTED-CLEANLY'
          : 'SESSION-1-WRONG-ERROR: ${e.message}',
    );
  }
  stdout.writeln('DONE');
  await stdout.flush();
}
