// A full-screen app for test/fixtures/job_control_pty_harness.py: an
// interactive shell runs it as a job, and the harness presses Ctrl+Z the way a
// user does. Nothing in it handles Ctrl+Z, so every press is job control.
//
//   --supervised  run under the hot-reload supervisor, as a plain
//                 `dart run bin/app.dart` does
//
// FLEURY_JOB_PID_OUT names a file the mounted app writes its pid to — the app,
// not the supervisor, which also runs main() but never mounts the tree.
// Ctrl+Q ends the app with exit code 0.

import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  final result = await runApp(
    const _JobApp(),
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

class _JobApp extends StatefulWidget {
  const _JobApp();

  @override
  State<_JobApp> createState() => _JobAppState();
}

class _JobAppState extends State<_JobApp> {
  @override
  void initState() {
    super.initState();
    final out = Platform.environment['FLEURY_JOB_PID_OUT'];
    if (out != null) File(out).writeAsStringSync('$pid');
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => exitApp())],
    child: Focus(autofocus: true, child: Text('JOB-READY $pid')),
  );
}
