// Every frame and tick runs in runApp's guarded zone, whoever asked for it.
//
// A data source wired in main() before runApp — a Timer, a socket, a
// subprocess listener — notifies from main()'s zone. The frame it requests
// must still run inside runApp's guard: before, the flush was scheduled in
// the requester's zone, so a failing post-frame callback (or any timer the
// frame started) escaped the guard, and in a real process the isolate died
// with the terminal left raw and on the alternate screen.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _ThrowsAfterThree extends StatelessWidget {
  const _ThrowsAfterThree(this.model);
  final ValueNotifier<int> model;

  @override
  Widget build(BuildContext context) {
    final value = context.listen(model).value;
    if (value == 3) {
      TuiBinding.of(context).addPostFrameCallback((_) {
        throw StateError('post-frame boom');
      });
    }
    return Text('tick $value');
  }
}

void main() {
  test('a frame requested from outside runApp runs inside its guard', () async {
    final escaped = <Object>[];
    final model = ValueNotifier(0);
    final driver = FakeTerminalDriver();
    late Future<AppExit> app;
    runZonedGuarded(() {
      // main(): the data source is wired before runApp.
      Timer.periodic(const Duration(milliseconds: 5), (timer) {
        if (model.value >= 3) {
          timer.cancel();
          return;
        }
        model.value++;
      });
      app = runApp(
        _ThrowsAfterThree(model),
        driver: driver,
        requireInteractiveTerminal: false,
      );
    }, (error, _) => escaped.add(error));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    requestExit();
    await app.timeout(const Duration(seconds: 8));

    expect(escaped, isEmpty, reason: 'the error escaped runApp to main()');
    expect(
      driver.output,
      contains('post-frame boom'),
      reason: 'the runtime reported the error on screen',
    );
  });
}
