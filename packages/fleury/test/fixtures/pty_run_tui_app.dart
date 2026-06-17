import 'package:fleury/fleury.dart';

Future<void> main() {
  return runTui(const _PtySmokeApp(), enableHotReload: false);
}

class _PtySmokeApp extends StatelessWidget {
  const _PtySmokeApp();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Column(
      children: [
        const Text('PTY-FIRST-FRAME'),
        Text('SIZE ${size.cols}x${size.rows}'),
      ],
    );
  }
}
