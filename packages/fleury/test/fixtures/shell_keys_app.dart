// An app for `fleury shell` PTY tests. It attaches through the working
// directory's `.fleury/handle`, as an app run from an IDE does, and records
// what reaches it — each key the focused field left unhandled, each edit of
// that field, and how the session ended — one JSON object per line in the
// file named by `--result=`.
//
// Ctrl+Z in the focused field undoes the last edit; Ctrl+C is left unhandled,
// so it ends the app with an interrupt. The app runs in a session of its own,
// with no terminal, so an interrupt can only have arrived as the key.

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  final result = args
      .firstWhere(
        (arg) => arg.startsWith('--result='),
        orElse: () => throw ArgumentError('usage: --result=<path>'),
      )
      .substring('--result='.length);
  void record(Map<String, Object?> entry) => File(result).writeAsStringSync(
    '${jsonEncode(entry)}\n',
    mode: FileMode.append,
    flush: true,
  );

  final appExit = await runApp(_KeysApp(record), enableHotReload: false);
  record({'exit': appExit.signal?.name ?? 'requested'});
  exit(switch (appExit.signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
    null => 0,
  });
}

class _KeysApp extends StatelessWidget {
  const _KeysApp(this.record);

  final void Function(Map<String, Object?> entry) record;

  @override
  Widget build(BuildContext context) => KeyDetector(
    onKey: (event) => record({
      'key': event.code.character ?? event.code.special?.name,
      'ctrl': event.hasCtrl,
    }),
    child: Column(
      children: [
        const Text('SHELL-KEYS-READY'),
        TextInput(
          autofocus: true,
          enableBlink: false,
          onChanged: (text) => record({'text': text}),
        ),
      ],
    ),
  );
}
