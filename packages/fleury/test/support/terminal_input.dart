// Drives a widget test with the bytes a terminal sends, through the real
// InputParser: a synthetic KeyEvent can hide the modifier shape a protocol
// actually delivers (kitty's Shift+Backspace is `CSI 127;2u`, not 0x7F).
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import 'harness.dart';

final class _Sink implements TuiEventSink {
  final events = <TuiEvent>[];

  @override
  void add(TuiEvent event) => events.add(event);
}

/// Parses [bytes] as a terminal delivers them and dispatches every event the
/// parser emits.
void pressTerminalBytes(FleuryTester tester, String bytes) {
  final sink = _Sink();
  InputParser()
    ..feed(bytes.codeUnits, sink)
    ..flush(sink);
  for (final event in sink.events) {
    switch (event) {
      case InputBatch():
        tester.sendBatch(event);
      case KeyEvent():
        tester.sendKey(event);
      case TextInputEvent(:final text):
        tester.type(text);
      default:
        fail('unexpected event $event');
    }
  }
}
