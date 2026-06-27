import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--layout-crash')) {
    return runApp(const _BoomWidget(), enableHotReload: false);
  }
  if (args.contains('--handoff')) {
    final driver = createNativeTerminalDriver();
    Timer(const Duration(milliseconds: 250), () {
      unawaited(
        withTerminalHandoff(driver, () {
          File('/dev/stdout').writeAsStringSync('PTY-HANDOFF\n');
        }),
      );
    });
    return runApp(
      const _PtySmokeApp(label: 'PTY-HANDOFF-MODE'),
      driver: driver,
      enableHotReload: false,
    );
  }
  return runApp(const _PtySmokeApp(), enableHotReload: false);
}

class _PtySmokeApp extends StatelessWidget {
  const _PtySmokeApp({this.label = 'PTY-FIRST-FRAME'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Column(
      children: [Text(label), Text('SIZE ${size.cols}x${size.rows}')],
    );
  }
}

class _BoomWidget extends LeafRenderObjectWidget {
  const _BoomWidget();

  @override
  RenderObject createRenderObject(BuildContext context) => _BoomRender();
}

class _BoomRender extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) {
    throw StateError('layout-boom');
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}
