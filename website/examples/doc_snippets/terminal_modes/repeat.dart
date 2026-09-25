import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

Future<void> main() => repeatSetup();

Future<void> repeatSetup() async {
  while (true) {
    InlineSetupResult? result;
    final outcome = await runApp(
      FleuryApp(
        title: 'Project setup',
        home: InlineSetup(
          onComplete: (value) {
            result = value;
            requestExit();
          },
        ),
      ),
      mode: const TerminalMode.inline(rows: 21, mouse: true),
      enableHotReload: false,
    );

    if (outcome.signal case final signal?) {
      exitCode = switch (signal) {
        AppSignal.interrupt => 130,
        AppSignal.terminate => 143,
        AppSignal.hangup => 129,
      };
      return;
    }
    if (result == null) return;

    stdout.writeln(result!.summary);
    stdout.write('Open setup again? [y/N] ');
    await stdout.flush();
    if (stdin.readLineSync()?.trim().toLowerCase() != 'y') return;
  }
}
