// A full-screen app for test/fixtures/job_control_pty_harness.py: an
// interactive shell runs it as a job (or, with the harness's --no-shell, the
// terminal runs it directly), and the harness suspends it the way a user does.
// By default nothing in it handles Ctrl+Z, so every press is job control; Ctrl+T
// asks for the same suspension through TerminalSession.suspend.
//
//   --supervised   run under the hot-reload supervisor, as a plain
//                  `dart run bin/app.dart` does
//   --suspend-key  a chat composer instead: its text field always has focus
//                  and takes every Ctrl+Z for undo, so Ctrl+T is its suspend
//                  key
//
// FLEURY_JOB_PID_OUT names a file the mounted app writes its pid to — the app,
// not the supervisor, which also runs main() but never mounts the tree.
// FLEURY_JOB_EVENTS_OUT names a file the app appends what happened to, one
// line each: `supportsSuspend:<bool>` once mounted, `key:ctrl+<letter>` for a
// Ctrl chord that reaches runApp's onEvent (an unhandled Ctrl+Z only when it
// did not suspend), `field:<text>` when the composer's field changes, and
// `suspended:<result>` when a suspend request completes.
// Ctrl+Q ends the app with exit code 0.

import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  final result = await runApp(
    args.contains('--suspend-key') ? const _ComposerApp() : const _JobApp(),
    enableHotReload: args.contains('--supervised'),
    debug: const DebugConfig(enabled: false),
    args: args,
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl) {
        _record('key:ctrl+${event.code.character}');
      }
      return null;
    },
  );
  exit(switch (result.signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
    null => 0,
  });
}

/// Writes the pid file and records whether the session can suspend.
void _mounted(BuildContext context) {
  final out = Platform.environment['FLEURY_JOB_PID_OUT'];
  if (out != null) File(out).writeAsStringSync('$pid');
  final session = context.scope<TerminalSession>();
  _record('supportsSuspend:${session.supportsSuspend}');
}

final _events = switch (Platform.environment['FLEURY_JOB_EVENTS_OUT']) {
  final path? => File(path),
  null => null,
};

void _record(String event) =>
    _events?.writeAsStringSync('$event\n', mode: FileMode.append, flush: true);

/// Ctrl+T: the app's own suspend key.
KeyBinding _suspendKey(TerminalSession session) => KeyBinding(
  KeySequence.ctrl.t,
  label: 'Suspend',
  onTrigger: (_) async => _record('suspended:${await session.suspend()}'),
);

class _JobApp extends StatefulWidget {
  const _JobApp();

  @override
  State<_JobApp> createState() => _JobAppState();
}

class _JobAppState extends State<_JobApp> {
  @override
  void initState() {
    super.initState();
    _mounted(context);
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [
      KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => exitApp()),
      _suspendKey(context.scope<TerminalSession>()),
    ],
    child: Focus(autofocus: true, child: Text('JOB-READY $pid')),
  );
}

class _ComposerApp extends StatefulWidget {
  const _ComposerApp();

  @override
  State<_ComposerApp> createState() => _ComposerAppState();
}

class _ComposerAppState extends State<_ComposerApp> {
  final _draft = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mounted(context);
    _draft.addListener(() => _record('field:${_draft.text}'));
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [
      KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => exitApp()),
      _suspendKey(context.scope<TerminalSession>()),
    ],
    child: Column(
      children: [
        Text('JOB-READY $pid'),
        TextInput(controller: _draft, autofocus: true, enableBlink: false),
      ],
    ),
  );
}
