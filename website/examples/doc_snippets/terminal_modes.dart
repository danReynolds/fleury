// Compile-checked source for Full-screen and inline UIs.
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

Future<void> main(List<String> args) async {
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
    mode: args.contains('--full-screen')
        ? const TerminalMode(mouse: true)
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

Widget setupWithHost() => ScopeBuilder<TerminalSession>(
  builder: (_, session) => InlineSetup(
    onComplete: (_) => requestExit(),
    onStepChanged: (step) async {
      if (session.isInline) await session.resizeInline(step.rows);
    },
  ),
);

Future<void> openPreview(TerminalSession session, File previewFile) async {
  await session.runWithHandoff(() async {
    final pager = await Process.start('less', [
      '--',
      previewFile.path,
    ], mode: ProcessStartMode.inheritStdio);
    await pager.exitCode;
  });
}
