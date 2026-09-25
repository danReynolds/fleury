// Compile-checked source for Full-screen and inline UIs.
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

import 'terminal_modes/repeat.dart' show repeatSetup;
import 'terminal_modes/resize.dart' show ResizingSetup;

Future<void> main(List<String> args) async {
  if (args.contains('--repeat')) {
    await repeatSetup();
    return;
  }
  InlineSetupResult? result;
  final outcome = await runApp(
    FleuryApp(
      title: 'Project setup',
      home: InlineSetup(
        onComplete: (value) {
          result = value;
          exitApp();
        },
      ),
    ),
    mode: args.contains('--full-screen')
        ? const TerminalMode.fullScreen(mouse: true)
        : const TerminalMode.inline(rows: 21, mouse: true),
    enableHotReload: false,
    debug: const DebugConfig(enabled: false),
  );
  if (outcome.signal case final signal?) {
    exitCode =
        128 +
        switch (signal) {
          AppSignal.interrupt => 2,
          AppSignal.terminate => 15,
          AppSignal.hangup => 1,
        };
    return;
  }
  print(result?.summary ?? 'Setup cancelled.');
}

Widget setupWithHost() => const ResizingSetup();

Future<void> openPreview(TerminalSession session, File previewFile) async {
  await session.runWithHandoff(() async {
    final pager = await Process.start('less', [
      '--',
      previewFile.path,
    ], mode: ProcessStartMode.inheritStdio);
    await pager.exitCode;
  });
}
