import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  final driver = PosixTerminalDriver();
  try {
    await driver.enter(
      args.contains('--inline')
          ? const TerminalMode.inline(rows: 10)
          : const TerminalMode.fullScreen(),
    );
    driver.write('FRAME-START');
    await stdout.flush();
    // Exceed the PTY output queue. Input and output share O_NONBLOCK.
    driver.write('x' * (128 * 1024));
    driver.write('FRAME-END');
    await stdout.flush();
  } finally {
    await driver.restore();
  }
  stdout.writeln('OUTPUT-RESTORED');
}
