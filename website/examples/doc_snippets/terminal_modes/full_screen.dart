import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

Future<void> main() async {
  await runApp(
    FleuryApp(
      title: 'Project setup',
      home: InlineSetup(onComplete: (_) => requestExit()),
    ),
    mode: const TerminalMode(mouse: true),
    enableHotReload: false,
  );
}
