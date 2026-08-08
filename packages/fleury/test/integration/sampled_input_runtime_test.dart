// Sampled keyboard input, through the REAL runtime.
//
// The rule this file encodes: sampled input is verified through `runApp`'s
// own frame loop, with only the terminal substituted. Nothing here may stand
// in for a runtime responsibility — FleuryTester publishes the frame latch
// itself, so a whole test corpus can agree a sampled feature works while the
// runtime wiring is broken.
//
// (An earlier version of this header claimed the runtime never latched at
// all. False — the FrameDriver always did, via `onLatchInput`; the grep that
// "proved" otherwise searched for `publishLatch()` with parentheses and
// missed the tear-off. The real runtime defect was the OPPOSITE: a second
// latch site briefly added at `tickerScheduler.onFrameStart` expired
// `wasPressed` edges before tickers could read them — see
// ticker_edge_visibility_test.dart.)
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.onSample);
  final void Function(KeyboardSnapshot) onSample;
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
      widget.onSample(_keyboard.snapshot);
    })..start();
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

void main() {
  test('a ticker in a REAL runApp observes a held key', () async {
    final driver = FakeTerminalDriver(
      size: const CellSize(80, 24),
      keyboardCapabilities: KeyboardCapabilities.full,
    );
    final samples = <KeyboardSnapshot>[];
    final done = Completer<void>();

    unawaited(
      runApp(
        FleuryApp(
          title: 'sampled',
          home: _Probe((snapshot) {
            samples.add(snapshot);
            if (samples.length > 12 && !done.isCompleted) {
              done.complete();
              requestExit();
            }
          }),
        ),
        driver: driver,
        requireInteractiveTerminal: false,
      ),
    );

    // Let the app mount and start ticking, then physically hold A down.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    driver.enqueue(const KeyEvent(KeyCode.a, position: KeyPosition.a));
    await done.future.timeout(const Duration(seconds: 5));

    expect(
      samples.any((s) => s.isHeld(KeyPosition.a)),
      isTrue,
      reason:
          'the runtime must publish the frame latch — if this fails, '
          'every held-key control in every app is dead',
    );
  });
}
