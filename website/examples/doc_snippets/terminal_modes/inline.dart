import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

Future<void> main() async {
  await runApp(
    FleuryApp(
      title: 'Project setup',
      home: InlineSetup(onComplete: (_) => requestExit()),
    ),
    mode: const TerminalMode.inline(rows: 21, mouse: true),
    enableHotReload: false,
  );
}
