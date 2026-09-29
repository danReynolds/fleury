import 'dart:io';
import 'package:fleury/fleury.dart';
import 'demo_work.dart';

Future<void> main() async {
  final work = DemoWork();
  print('Sample task · PID $pid');
  try {
    final result = await runApp(
      FleuryApp(
        title: 'Sample task',
        home: ShutdownPanel(work: work, onFinish: () => exitApp()),
      ),
      mode: const TerminalMode.inline(rows: 7, mouse: true),
      enableHotReload: false,
    );
    exitCode = signalExitCode(result.signal);
  } finally {
    await work.close();
  }
  print('Resources closed. Exit code: $exitCode');
}
