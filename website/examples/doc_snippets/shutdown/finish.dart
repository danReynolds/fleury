import 'package:fleury/fleury.dart';

Future<void> main() async {
  await runApp(
    FleuryApp(
      title: 'One step',
      home: Button(text: 'Done', onPressed: () => exitApp()),
    ),
    mode: const TerminalMode.inline(rows: 5, mouse: true),
    enableHotReload: false,
  );
  print('Back in the command.');
}
