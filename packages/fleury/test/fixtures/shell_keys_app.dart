// An app for `fleury shell` PTY tests. It attaches through the working
// directory's `.fleury/handle`, as an app run from an IDE does, and records
// what reaches it — each key the focused field left unhandled, each edit of
// that field, each click and hover, and how the session ended — one JSON
// object per line in the file named by `--result=`.
//
// Ctrl+Z in the focused field undoes the last edit; Ctrl+C is left unhandled,
// so it ends the app with an interrupt. The app runs in a session of its own,
// with no terminal, so an interrupt can only have arrived as the key. With
// `--no-field` there is no field, so Ctrl+Z is left unhandled too.
//
// The first edit also repaints a status line from SHELL-KEYS-EDIT-WAITING to
// SHELL-KEYS-EDIT-TYPED-<text>; the shared prefix means the renderer's diff
// writes just the changed tail, so the tail in the terminal's output proves a
// diff frame, not only the first frame, reached the screen.
//
// Its TerminalMode is the default (no mouse) unless:
//   --mouse               TerminalMode(mouse: true)
//   --mouse-motion        TerminalMode(mouseMotion: true)
//   --no-input-reporting  no bracketed paste, no focus reports, legacy keys
// With either mouse flag the screen starts with a button on row 1 and a hover
// region on row 2 (1-based, from column 1), above the rest: a click records
// {"pressed": "button"}, the pointer entering the region {"hover": "enter"}.

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

  final mouse = args.contains('--mouse');
  final motion = args.contains('--mouse-motion');
  final reporting = !args.contains('--no-input-reporting');
  final appExit = await runApp(
    _KeysApp(
      record,
      field: !args.contains('--no-field'),
      pointer: mouse || motion,
    ),
    mode: TerminalMode(
      mouse: mouse,
      mouseMotion: motion,
      bracketedPaste: reporting,
      focusReporting: reporting,
      keyboardProtocol: reporting
          ? KeyboardProtocolMode.lifecycle
          : KeyboardProtocolMode.legacy,
    ),
    enableHotReload: false,
  );
  record({'exit': appExit.signal?.name ?? 'requested'});
  exit(switch (appExit.signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
    null => 0,
  });
}

class _KeysApp extends StatefulWidget {
  const _KeysApp(this.record, {required this.field, required this.pointer});

  final void Function(Map<String, Object?> entry) record;
  final bool field;
  final bool pointer;

  @override
  State<_KeysApp> createState() => _KeysAppState();
}

class _KeysAppState extends State<_KeysApp> {
  String? _firstEdit;
  var _hovered = false;

  @override
  Widget build(BuildContext context) => KeyDetector(
    onKey: (event) => widget.record({
      'key': event.code.character ?? event.code.special?.name,
      'ctrl': event.hasCtrl,
    }),
    child: Column(
      children: [
        if (widget.pointer) ...[
          Button(
            text: 'SHELL-KEYS-BUTTON',
            onPressed: () => widget.record({'pressed': 'button'}),
          ),
          MouseRegion(
            onEnter: () {
              if (_hovered) return;
              _hovered = true;
              widget.record({'hover': 'enter'});
            },
            child: const Text('SHELL-KEYS-HOVER'),
          ),
        ],
        const Text('SHELL-KEYS-READY'),
        Text('SHELL-KEYS-EDIT-${_firstEdit ?? 'WAITING'}'),
        if (widget.field)
          TextInput(
            autofocus: true,
            enableBlink: false,
            onChanged: (text) {
              widget.record({'text': text});
              if (_firstEdit == null) {
                setState(() => _firstEdit = 'TYPED-$text');
              }
            },
          )
        else
          // Focus inside the detector without a field that handles keys.
          const Focus(autofocus: true, child: Text('SHELL-KEYS-NO-FIELD')),
      ],
    ),
  );
}
