// Compile-checked source for Full-screen and inline UIs.
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  String? selected;
  final outcome = await runApp(
    FleuryApp(
      title: 'Choose a source',
      home: SourcePicker(
        onSelected: (value) {
          selected = value;
          requestExit();
        },
      ),
    ),
    mode: args.contains('--full-screen')
        ? const TerminalMode(mouse: true)
        : const TerminalMode.inline(rows: 10, mouse: true),
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
  print(selected == null ? 'Cancelled.' : 'Selected $selected.');
}

class SourcePicker extends StatelessWidget {
  const SourcePicker({super.key, required this.onSelected});

  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose a source'),
        for (final source in ['Local', 'Homebrew', 'Pub'])
          Button(
            text: source,
            autofocus: source == 'Local',
            onPressed: () => onSelected(source),
          ),
      ],
    ),
  );
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

Future<void> openReadme(TerminalSession session) async {
  await session.runWithHandoff(() async {
    final pager = await Process.start('less', [
      'README.md',
    ], mode: ProcessStartMode.inheritStdio);
    await pager.exitCode;
  });
}
