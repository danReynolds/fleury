// Sampled keyboard input, through the REAL runtime.
//
// This file exists because of a bug that 2846 tests could not see:
// `publishLatch()` was called only by FleuryTester, so `Keyboard.snapshot` in a
// running app stayed empty forever and every held-key control was dead. The
// harness supplied the wiring production was missing, so the tests agreed the
// feature worked.
//
// The rule this encodes: sampled input is verified through `runApp`'s own
// frame loop, with only the terminal substituted. Nothing here may stand in
// for a runtime responsibility.
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
