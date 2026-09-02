// Every press edge reaches ticker consumers, through the REAL runtime.
//
// Regression test for a double-latch defect: run_app briefly latched the
// keyboard from tickerScheduler.onFrameStart IN ADDITION to the FrameDriver's
// render latch. `publishLatch` expires edges on a quiet call, so the second
// site expired every `wasPressed` edge immediately before the tickers ran —
// 0 of 5 presses observed. Both clocks are wired today, but the session keeps
// exactly one of them LIVE (RFC 0020 §5.6); the app here runs a ticker, so
// the edges this asserts are published and expired on the ticker's clock.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.onSeen);
  final void Function() onSeen;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late Keyboard _keyboard;
  Ticker? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboard = Keyboard.of(context);
    _ticker ??= TuiBinding.of(context).createTicker((_) {
      if (_keyboard.snapshot.wasPressed(KeyPosition.a)) widget.onSeen();
      setState(() {}); // renders every frame, like a real game
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Focus(autofocus: true, child: Text('probe'));
}

void main() {
  test('a ticker observes every press edge', () async {
    final driver = FakeTerminalDriver(
      keyboardCapabilities: KeyboardCapabilities.full,
    );
    var seen = 0;
    final app = runApp(
      FleuryApp(title: 'probe', home: _Probe(() => seen++)),
      driver: driver,
      requireInteractiveTerminal: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    for (var i = 0; i < 5; i++) {
      driver.enqueue(const KeyEvent(KeyCode.a, position: KeyPosition.a));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      driver.enqueue(
        const KeyEvent(
          KeyCode.a,
          position: KeyPosition.a,
          type: KeyEventType.up,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    requestExit();
    await app.timeout(const Duration(seconds: 8));
    print('EDGES-SEEN $seen of 5');
    expect(seen, 5, reason: 'wasPressed must not be a race');
  });
}
