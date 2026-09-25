// Compile-checked source for Full-screen and inline UIs.
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

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
