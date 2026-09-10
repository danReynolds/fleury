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
    expect(sink.events, [
      const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.alt}),
    ]);
  });

  test('ESC+Enter is Alt+Enter', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(const [0x1B, 0x0D], sink);
    expect(sink.events, [
      const KeyEvent(KeyCode.enter, modifiers: {KeyModifier.alt}),
    ]);
  });

  test('ESC+CR+LF is ONE Alt+Enter, not Alt+Enter then Enter', () {
    final parser = InputParser();
    final sink = _Sink();
    // A terminal that sends CRLF turns Alt+Enter into these three bytes. The
    // trailing LF is the pair's second half and must be swallowed, exactly as
    // ground mode swallows it after a bare CR — otherwise a chat composer
    // inserts the newline and then submits on one keypress.
    parser.feed(const [0x1B, 0x0D, 0x0A], sink);
    expect(sink.events, [
      const KeyEvent(KeyCode.enter, modifiers: {KeyModifier.alt}),
    ]);
  });

  test('ESC+a remains Alt+a (control)', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(const [0x1B, 0x61], sink);
    expect(sink.events, [
      const KeyEvent(KeyCode.char('a'), modifiers: {KeyModifier.alt}),
    ]);
  });
}
