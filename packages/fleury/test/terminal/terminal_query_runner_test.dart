import 'dart:async';

import 'package:fleury/src/input/events.dart';
import 'package:fleury/src/terminal/input_parser.dart';
import 'package:fleury/src/terminal/terminal_query_runner.dart';
import 'package:test/test.dart';

void main() {
  test(
    'routes typed replies to a query while preserving interleaved input',
    () async {
      final parser = InputParser();
      final input = _InputSink();
      late TerminalQueryRunner runner;
      runner = TerminalQueryRunner(
        parser: parser,
        inputSink: input,
        write: (_) async {
          parser.feed(
            'a\x1b[?31u\x1b[?1;2cb'.codeUnits,
            input,
            responseSink: runner,
          );
        },
      );

      final response = await runner.request(
        '\x1b[?u\x1b[c',
        timeout: const Duration(milliseconds: 50),
      );

      expect(String.fromCharCodes(response), '\x1b[?31u\x1b[?1;2c');
      expect(input.events, const <TuiEvent>[
        TextInputEvent('a'),
        TextInputEvent('b'),
      ]);
      runner.dispose();
    },
  );

  test('CPR is owned only for the exchange that requested it', () async {
    final parser = InputParser();
    final input = _InputSink();
    late TerminalQueryRunner runner;
    runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      write: (_) async {
        parser.feed(
          '\x1b[1;3R\x1b[?1;2c\x1b[1;3R'.codeUnits,
          input,
          responseSink: runner,
        );
      },
    );

    await runner.request(
      '\x1b[6n\x1b[c',
      timeout: const Duration(milliseconds: 50),
    );
    parser.feed('\x1b[1;3R'.codeUnits, input, responseSink: runner);

    expect(
      input.events,
      const <TuiEvent>[
        KeyEvent(
          KeyCode.f3,
          modifiers: <KeyModifier>{KeyModifier.alt},
          position: KeyPosition.f3,
        ),
        KeyEvent(
          KeyCode.f3,
          modifiers: <KeyModifier>{KeyModifier.alt},
          position: KeyPosition.f3,
        ),
      ],
      reason: 'bytes after the DA sentinel and after the exchange are input',
    );
    runner.dispose();
  });

  test(
    'late replies are quarantined without swallowing ordinary input',
    () async {
      final parser = InputParser();
      final input = _InputSink();
      final writes = <String>[];
      late TerminalQueryRunner runner;
      runner = TerminalQueryRunner(
        parser: parser,
        inputSink: input,
        lateResponseGrace: const Duration(milliseconds: 100),
        write: (bytes) async => writes.add(bytes),
      );

      await expectLater(
        runner.request(
          '\x1b[6n\x1b[c',
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final next = runner.request(
        '\x1b[?u\x1b[c',
        timeout: const Duration(milliseconds: 50),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        writes,
        hasLength(1),
        reason: 'the next exchange waits for quarantine',
      );

      parser.feed(
        'x\x1b[2;4R\x1b[?1;2c'.codeUnits,
        input,
        responseSink: runner,
      );
      await Future<void>.delayed(Duration.zero);
      expect(input.events, const <TuiEvent>[TextInputEvent('x')]);
      expect(writes, hasLength(2));

      parser.feed('\x1b[?31u\x1b[?1;2c'.codeUnits, input, responseSink: runner);
      expect(String.fromCharCodes(await next), '\x1b[?31u\x1b[?1;2c');
      runner.dispose();
    },
  );

  test('quarantine wait counts against the next query deadline', () async {
    final parser = InputParser();
    final input = _InputSink();
    final writes = <String>[];
    final runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      lateResponseGrace: const Duration(milliseconds: 100),
      write: (bytes) async => writes.add(bytes),
    );

    await expectLater(
      runner.request('first\x1b[c', timeout: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      runner.request('second\x1b[c', timeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );

    expect(writes, <String>['first\x1b[c']);
    runner.dispose();
  });

  test(
    'a reply split across timeout completes in quarantine, not as input',
    () async {
      final parser = InputParser();
      final input = _InputSink();
      late TerminalQueryRunner runner;
      runner = TerminalQueryRunner(
        parser: parser,
        inputSink: input,
        lateResponseGrace: const Duration(milliseconds: 100),
        write: (_) async {},
      );

      final query = runner.request(
        '\x1b[6n\x1b[c',
        timeout: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(Duration.zero);
      parser.feed('\x1b[1;'.codeUnits, input, responseSink: runner);
      await expectLater(query, throwsA(isA<TimeoutException>()));

      parser.feed('2R\x1b[?1;2c\x03'.codeUnits, input, responseSink: runner);
      await Future<void>.delayed(Duration.zero);

      expect(
        input.events,
        const <TuiEvent>[
          KeyEvent(
            KeyCode.char('c'),
            modifiers: <KeyModifier>{KeyModifier.ctrl},
          ),
        ],
        reason: 'the split CPR/DA is consumed and trailing input is preserved',
      );
      runner.dispose();
    },
  );

  test('a lone Escape is delayed, then released after quarantine', () async {
    final parser = InputParser();
    final input = _InputSink();
    late TerminalQueryRunner runner;
    runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      lateResponseGrace: const Duration(milliseconds: 10),
      write: (_) async {},
    );

    final query = runner.request(
      '\x1b_qa=t,f=24,s=1,v=1,i=31;AAAA\x1b\\\x1b[c',
      timeout: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(Duration.zero);
    parser.feed(const <int>[0x1b], input, responseSink: runner);
    await expectLater(query, throwsA(isA<TimeoutException>()));
    expect(input.events, isEmpty, reason: 'it remains ambiguous during grace');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(input.events, const <TuiEvent>[KeyEvent(KeyCode.escape)]);
    runner.dispose();
  });

  test('aggregate response overflow fails closed', () async {
    final parser = InputParser();
    final input = _InputSink();
    late TerminalQueryRunner runner;
    runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      maxResponseBytes: 8,
      write: (_) async {},
    );

    final query = runner.request(
      '\x1b[?u\x1b[c',
      timeout: const Duration(milliseconds: 100),
    );
    await Future<void>.delayed(Duration.zero);
    parser.feed('\x1b[?1u\x1b[?2u'.codeUnits, input, responseSink: runner);

    await expectLater(query, throwsA(isA<StateError>()));
    expect(input.events, isEmpty);
    runner.dispose();
  });

  test('a blocked transport write remains inside the query deadline', () async {
    final parser = InputParser();
    final input = _InputSink();
    final blockedWrite = Completer<void>();
    final runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      write: (_) => blockedWrite.future,
    );

    await expectLater(
      runner.request('\x1b[?u\x1b[c', timeout: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );

    runner.dispose();
    blockedWrite.complete();
  });

  test('a transport write failure fails the exchange centrally', () async {
    final parser = InputParser();
    final input = _InputSink();
    final runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      write: (_) => throw StateError('write failed'),
    );

    await expectLater(
      runner.request(
        '\x1b[?u\x1b[c',
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<StateError>()),
    );
    expect(input.events, isEmpty);
    runner.dispose();
  });

  test('serializes concurrent callers', () async {
    final parser = InputParser();
    final input = _InputSink();
    final writes = <String>[];
    late TerminalQueryRunner runner;
    runner = TerminalQueryRunner(
      parser: parser,
      inputSink: input,
      write: (bytes) async => writes.add(bytes),
    );

    final first = runner.request(
      'first\x1b[c',
      timeout: const Duration(milliseconds: 50),
    );
    final second = runner.request(
      'second\x1b[c',
      timeout: const Duration(milliseconds: 50),
    );
    await Future<void>.delayed(Duration.zero);
    expect(writes, <String>['first\x1b[c']);

    parser.feed('\x1b[?1;2c'.codeUnits, input, responseSink: runner);
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(writes, <String>['first\x1b[c', 'second\x1b[c']);

    parser.feed('\x1b[?1;2c'.codeUnits, input, responseSink: runner);
    await second;
    runner.dispose();
  });
}

final class _InputSink implements TuiEventSink {
  final List<TuiEvent> events = <TuiEvent>[];

  @override
  void add(TuiEvent event) => events.add(event);
}
