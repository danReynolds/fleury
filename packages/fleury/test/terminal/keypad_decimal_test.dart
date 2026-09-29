import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Sink implements TuiEventSink {
  final events = <TuiEvent>[];
  @override
  void add(TuiEvent event) => events.add(event);
}

void main() {
  test('associated decimal text and logical press agree through release', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(utf8.encode('\x1b[57409;1;44u'), sink);
    parser.feed(utf8.encode('\x1b[57409;1:2u\x1b[57409;1:3u'), sink);
    expect(sink.events, const [
      InputBatch(
        key: KeyEvent(KeyCode.char(','), position: KeyPosition.numpadDecimal),
        committedText: ',',
      ),
      InputBatch(
        key: KeyEvent(
          KeyCode.char(','),
          type: KeyEventType.repeat,
          position: KeyPosition.numpadDecimal,
        ),
        committedText: ',',
      ),
      KeyEvent(
        KeyCode.char(','),
        type: KeyEventType.up,
        position: KeyPosition.numpadDecimal,
      ),
    ]);
  });

  for (final decimal in ['.', ',', '٫']) {
    test('configured decimal $decimal works for Kitty and legacy SS3', () {
      final parser = InputParser(keypadDecimal: decimal);
      final sink = _Sink();
      parser.feed(utf8.encode('\x1b[57409u\x1bOn'), sink);
      for (final event in sink.events.cast<InputBatch>()) {
        expect(event.committedText, decimal);
        expect(event.key!.code.character, decimal);
        expect(event.key!.position, KeyPosition.numpadDecimal);
      }
      expect(sink.events, hasLength(2));
    });
  }

  test('malformed text cannot change the learned decimal', () {
    final parser = InputParser();
    final sink = _Sink();
    parser.feed(
      utf8.encode('\x1b[57409;1;44u\x1b[57409;1;1114112u\x1b[57409;1:3u\x1bOn'),
      sink,
    );
    expect(sink.events, hasLength(3));
    expect((sink.events.last as InputBatch).key!.code, const KeyCode.char(','));
  });

  test(
    'a new press may change locale without changing the preceding release',
    () {
      final parser = InputParser();
      final sink = _Sink();
      parser.feed(
        utf8.encode('\x1b[57409;1;44u\x1b[57409;1:3;46u\x1b[57409;1;46u'),
        sink,
      );
      expect((sink.events[1] as KeyEvent).code, const KeyCode.char(','));
      expect((sink.events[2] as InputBatch).key!.code, const KeyCode.char('.'));
    },
  );
}
