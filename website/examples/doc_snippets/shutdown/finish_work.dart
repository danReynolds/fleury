import 'dart:async';
import 'dart:io';
import 'package:fleury/fleury.dart';
import 'demo_work.dart';

Future<void> main() async {
  final work = DemoWork();
  AppSignal? interruptedBy;
  Future<void>? stopping;

  Future<void> finish() => stopping ??= () async {
    try {
      await work.finish();
    } finally {
      exitApp();
    }
  }();

  void interrupt(AppSignal signal) {
    interruptedBy ??= signal;
    unawaited(finish());
  }

  print('Sample task · PID $pid');
  try {
    final result = await runApp(
      FleuryApp(
        title: 'Sample task',
        home: KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.c,
              onTrigger: (_) => interrupt(AppSignal.interrupt),
            ),
          ],
          child: ShutdownPanel(work: work, onFinish: () => unawaited(finish())),
        ),
      ),
      onEvent: (event) {
        if (event is SignalEvent) {
          interrupt(event.signal);
          return const EventHandled();
        }
        return null;
      },
      mode: const TerminalMode.inline(rows: 7, mouse: true),
      enableHotReload: false,
    );
    exitCode = signalExitCode(interruptedBy ?? result.signal);
  } finally {
    await work.close();
  }
  print('Resources closed. Exit code: $exitCode');
}
