import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

Future<void> main() async {
  await runApp(
    const FleuryApp(title: 'Project setup', home: ResizingSetup()),
    mode: const TerminalMode.inline(rows: 17, mouse: true),
    enableHotReload: false,
  );
}

class ResizingSetup extends StatelessWidget {
  const ResizingSetup({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.scope<TerminalSession>();
    return InlineSetup(
      onComplete: (_) => requestExit(),
      onStepChanged: (step) async {
        await session.resizeInline(step.rows);
      },
    );
  }
}
