// Lock test (audit 2.e): ESC-prefixed non-printable chords drop Alt.
// ESC+a correctly becomes Alt+a; ESC+Tab / ESC+Enter currently emit bare Tab/Enter.
import 'package:fleury/fleury_core.dart';
import 'package:fleury/src/terminal/input_parser.dart';
import 'package:test/test.dart';

class _Sink implements TuiEventSink {
  final events = <TuiEvent>[];
  @override
  void add(TuiEvent event) => events.add(event);
}

void main() {
  test('ESC+Tab is Alt+Tab', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(const [0x1B, 0x09], sink);
    expect(
      sink.events,
      [const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.alt})],
    );
  });

  test('ESC+Enter is Alt+Enter', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(const [0x1B, 0x0D], sink);
    expect(
      sink.events,
      [const KeyEvent(KeyCode.enter, modifiers: {KeyModifier.alt})],
    );
  });

  test('ESC+a remains Alt+a (control)', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(const [0x1B, 0x61], sink);
    expect(
      sink.events,
      [const KeyEvent(KeyCode.char('a'), modifiers: {KeyModifier.alt})],
    );
  });
}
