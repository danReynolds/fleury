import 'dart:io';

import 'package:fleury/fleury.dart';

// Attaches to the shell, paints one frame, and exits. Keys typed through the
// shell are covered by test/remote/shell_pty_test.dart, whose harness types
// only once the app is on screen; this smoke test's capture types on a timer,
// and the shell discards what is typed before an app attaches.

Never _exitWith(AppExit appExit) => exit(switch (appExit.signal) {
  AppSignal.interrupt => 130,
  AppSignal.terminate => 143,
  AppSignal.hangup => 129,
  null => 0,
});

Future<void> main() async {
  _exitWith(await runApp(const _ShellCliE2eApp(), enableHotReload: false));
}

class _ShellCliE2eApp extends StatefulWidget {
  const _ShellCliE2eApp();

  @override
  State<_ShellCliE2eApp> createState() => _ShellCliE2eAppState();
}

class _ShellCliE2eAppState extends State<_ShellCliE2eApp> {
  var _scheduledExit = false;

  @override
  Widget build(BuildContext context) {
    if (!_scheduledExit) {
      _scheduledExit = true;
      TuiBinding.of(context).addPostFrameCallback((_) {
        if (!exitApp()) {
          throw StateError('shell E2E app lost its active session');
        }
      });
    }
    return const Text('SHELL-CLI-E2E-FIRST-FRAME');
  }
}
