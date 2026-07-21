import 'dart:io';

import 'package:fleury/fleury.dart';

Never _exitWith(AppExit appExit) => exit(switch (appExit.signal) {
  AppSignal.interrupt => 130,
  AppSignal.terminate => 143,
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
  var _activated = false;
  var _scheduledExit = false;

  KeyEventResult _onKey(KeyEvent event) {
    if (event.code != KeyCode.enter) return KeyEventResult.ignored;
    setState(() => _activated = true);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_activated && !_scheduledExit) {
      _scheduledExit = true;
      TuiBinding.of(context).addPostFrameCallback((_) {
        if (!requestExit()) {
          throw StateError('shell E2E app lost its active session');
        }
      });
    }
    return Focus(
      autofocus: true,
      onKey: _onKey,
      child: Text(
        _activated
            ? 'SHELL-CLI-E2E-INPUT-RECEIVED'
            : 'SHELL-CLI-E2E-FIRST-FRAME',
      ),
    );
  }
}
