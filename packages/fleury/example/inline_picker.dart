import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main() async {
  String? selected;
  final outcome = await runApp(
    FleuryApp(
      title: 'Choose a source',
      home: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose where your command comes from.'),
            const SizedBox(height: 1),
            for (final source in ['Local', 'Homebrew', 'Pub'])
              Button(
                text: source,
                autofocus: source == 'Local',
                onPressed: () {
                  selected = source;
                  requestExit();
                },
              ),
            const SizedBox(height: 1),
            const Text(
              'Tab or arrows to move · Enter to choose · Ctrl+C to cancel',
            ),
          ],
        ),
      ),
    ),
    mode: const TerminalMode.inline(rows: 10, mouse: true),
    enableHotReload: false,
    debug: const DebugConfig(enabled: false),
  );
  if (outcome.signal case final signal?) {
    exitCode = switch (signal) {
      AppSignal.interrupt => 130,
      AppSignal.terminate => 143,
      AppSignal.hangup => 129,
    };
    return;
  }
  // The live region has been cleared and the terminal returned to the caller.
  print(selected == null ? 'Cancelled.' : 'Selected $selected.');
}
