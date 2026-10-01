// A full-screen app for test/fixtures/job_control_pty_harness.py: an
// interactive shell runs it as a job, and the harness suspends it the way a
// user does. By default nothing in it handles Ctrl+Z, so every press is job
// control.
//
//   --supervised   run under the hot-reload supervisor, as a plain
//                  `dart run bin/app.dart` does
//   --suspend-key  a chat composer instead: its text field always has focus
//                  and takes every Ctrl+Z for undo, so Ctrl+T is its suspend
//                  key, through TerminalSession.suspend
//
// FLEURY_JOB_PID_OUT names a file the mounted app writes its pid to — the app,
// not the supervisor, which also runs main() but never mounts the tree.
// FLEURY_JOB_EVENTS_OUT names a file the composer appends what happened to,
// one line each: `field:<text>` when the field changes, and
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
  );
  exit(switch (result.signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
    null => 0,
  });
}

void _writePid() {
  final out = Platform.environment['FLEURY_JOB_PID_OUT'];
  if (out != null) File(out).writeAsStringSync('$pid');
}

class _JobApp extends StatefulWidget {
  const _JobApp();

  @override
  State<_JobApp> createState() => _JobAppState();
}

class _JobAppState extends State<_JobApp> {
  @override
  void initState() {
    super.initState();
    _writePid();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => exitApp())],
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
  final _events = switch (Platform.environment['FLEURY_JOB_EVENTS_OUT']) {
    final path? => File(path),
    null => null,
  };

  @override
  void initState() {
    super.initState();
    _writePid();
    _draft.addListener(() => _record('field:${_draft.text}'));
  }

  void _record(String event) => _events?.writeAsStringSync(
    '$event\n',
    mode: FileMode.append,
    flush: true,
  );

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.scope<TerminalSession>();
    return KeyBindings(
      bindings: [
        KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => exitApp()),
        KeyBinding(
          KeySequence.ctrl.t,
          label: 'Suspend',
          enabled: session.supportsSuspend,
          onTrigger: (_) async =>
              _record('suspended:${await session.suspend()}'),
        ),
      ],
      child: Column(
        children: [
          Text('JOB-READY $pid'),
          TextInput(controller: _draft, autofocus: true, enableBlink: false),
        ],
      ),
    );
  }
}
