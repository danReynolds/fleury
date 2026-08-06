// A real app, over a real PTY, sampling the keyboard from a real ticker.
//
// This exists because every earlier sampled-input test ran against
// FleuryTester, which published the frame latch itself — so the whole lane
// could be dead in production while 2846 tests agreed it worked. Nothing here
// is substituted: the driver negotiates, the parser parses injected bytes, the
// dispatcher routes, and the runtime's own frame loop latches.
import 'dart:io';

import 'package:fleury/fleury.dart';

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late Keyboard _keyboard;
  Ticker? _ticker;
  var _reported = false;
  var _frames = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboard = Keyboard.of(context);
    _ticker ??= TuiBinding.of(context).createTicker(_tick)..start();
  }

  void _tick(Duration _) {
    _frames++;
    final keys = _keyboard.snapshot;
    final held = keys.isHeld(KeyPosition.a);
    if (held && !_reported) {
      _reported = true;
      stdout.write('SAMPLED-HELD-A frame=$_frames\r\n');
    }
    // Give the injected bytes time to arrive, then report the verdict.
    if (_frames == 90) {
      stdout.write(
        'VERDICT held=${_keyboard.snapshot.isHeld(KeyPosition.a)} '
        'caps=${_keyboard.capabilities.supportsHeldState}\r\n',
      );
      requestExit();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Focus(autofocus: true, child: Text('sampling'));
}

Future<void> main() async {
  await runApp(const FleuryApp(title: 'sampled', home: _Probe()));
  exit(0);
}
