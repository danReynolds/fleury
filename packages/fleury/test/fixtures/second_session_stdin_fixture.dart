// The redirected stdin fallback rejects a second subscription clearly and
// exits naturally. Native TTY reuse has a separate integrated PTY fixture.
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
      e.message.contains('redirected stdin stream was already consumed')
          ? 'SESSION-1-REJECTED-CLEANLY'
          : 'SESSION-1-WRONG-ERROR: ${e.message}',
    );
  }
  stdout.writeln('DONE');
  await stdout.flush();
}
