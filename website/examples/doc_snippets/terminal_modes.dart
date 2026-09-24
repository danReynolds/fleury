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
        : const TerminalMode(inlineRows: 21, mouse: true),
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

class MoreRoomButton extends StatelessWidget {
  const MoreRoomButton({super.key});

  @override
  Widget build(BuildContext context) => ScopeBuilder<TerminalSession>(
    builder: (_, session) => Button(
      text: 'More room',
      onPressed: session.isInline
          ? () async {
              await session.resizeInline(20);
            }
          : null,
    ),
  );
}

Future<void> openPreview(TerminalSession session, File previewFile) async {
  await session.runWithHandoff(() async {
    final pager = await Process.start('less', [
      '--',
      previewFile.path,
    ], mode: ProcessStartMode.inheritStdio);
    await pager.exitCode;
  });
}
