import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _FakeStdin implements Stdin {
  _FakeStdin({this.terminal = false, List<String>? modeTrace})
    : modeTrace = modeTrace ?? <String>[];

  final bool terminal;
  final List<String> modeTrace;
  final _controller = StreamController<List<int>>();
  bool _lineMode = true;
  bool _echoMode = true;

  void push(List<int> bytes) => _controller.add(bytes);

  @override
  bool get hasTerminal => terminal;

  @override
  bool get lineMode {
    modeTrace.add('get:line');
    return _lineMode;
  }

  @override
  set lineMode(bool value) {
    modeTrace.add('set:line:$value');
    _lineMode = value;
  }

  @override
  bool get echoMode {
    modeTrace.add('get:echo');
    return _echoMode;
  }

  @override
  set echoMode(bool value) {
    modeTrace.add('set:echo:$value');
    _echoMode = value;
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  Future<void> close() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingStdout implements Stdout {
  final written = StringBuffer();

  @override
  bool get hasTerminal => true;
  @override
  bool get supportsAnsiEscapes => true;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  void write(Object? object) => written.write(object);
  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailOnceOnReentryStdout extends _RecordingStdout {
  int enterSequenceWrites = 0;

  @override
  void write(Object? object) {
    final bytes = '$object';
    if (bytes.contains('\x1B[?1049h')) {
      enterSequenceWrites++;
      if (enterSequenceWrites == 2) {
        throw StateError('injected Windows re-entry failure');
      }
    }
    super.write(object);
  }
}

int _occurrences(String haystack, String needle) {
  var count = 0;
  var offset = 0;
  while (true) {
    final found = haystack.indexOf(needle, offset);
    if (found < 0) return count;
    count++;
    offset = found + needle.length;
  }
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'Windows stdin EOF closes events and late parser flush is harmless',
    () async {
      final input = _FakeStdin();
      final out = _RecordingStdout();
      final driver = WindowsTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        resizePollInterval: Duration.zero,
      );
      final done = Completer<void>();
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add, onDone: done.complete);

      await driver.enter(TerminalMode.interactive);
      input.push('\x1B[200~abc'.codeUnits);
      await input.close();
      await done.future.timeout(const Duration(seconds: 1));
      expect(events.whereType<PasteEvent>(), [const PasteEvent('abc')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await driver.runWithTerminalHandoff(() {});

      await driver.restore();
      await sub.cancel();
    },
  );

  test('Windows concurrent handoffs serialize terminal ownership', () async {
    final input = _FakeStdin();
    final out = _RecordingStdout();
    final driver = WindowsTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      resizePollInterval: Duration.zero,
    );
    final releaseFirst = Completer<void>();
    final releaseSecond = Completer<void>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();

    try {
      await driver.enter(TerminalMode.interactive);
      out.written.clear();
      final first = driver.runWithTerminalHandoff(() async {
        firstStarted.complete();
        await releaseFirst.future;
      });
      await firstStarted.future;
      final second = driver.runWithTerminalHandoff(() async {
        secondStarted.complete();
        await releaseSecond.future;
      });
      await _pump();

      expect(secondStarted.isCompleted, isFalse);
      driver.write('FRAME-DURING-FIRST');
      expect(out.written.toString(), isNot(contains('FRAME-DURING-FIRST')));

      releaseFirst.complete();
      await secondStarted.future.timeout(const Duration(seconds: 1));
      driver.write('FRAME-DURING-SECOND');
      expect(out.written.toString(), isNot(contains('FRAME-DURING-SECOND')));

      releaseSecond.complete();
      await Future.wait<void>(<Future<void>>[first, second]);
      expect(_occurrences(out.written.toString(), '\x1B[?1049l'), 2);
      expect(_occurrences(out.written.toString(), '\x1B[?1049h'), 2);
    } finally {
      await driver.restore();
      await input.close();
    }
  });

  test(
    'Windows failed re-entry rejects one handoff without wedging the queue',
    () async {
      final input = _FakeStdin();
      final out = _FailOnceOnReentryStdout();
      final driver = WindowsTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        resizePollInterval: Duration.zero,
      );
      final releaseFirst = Completer<void>();
      final releaseSecond = Completer<void>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();

      try {
        await driver.enter(TerminalMode.interactive);
        final first = driver.runWithTerminalHandoff(() async {
          firstStarted.complete();
          await releaseFirst.future;
        });
        await firstStarted.future;

        final second = driver.runWithTerminalHandoff(() async {
          secondStarted.complete();
          await releaseSecond.future;
        });
        await _pump();
        expect(
          secondStarted.isCompleted,
          isFalse,
          reason: 'the queued child must not overlap the failing handoff',
        );
        final firstFailure = expectLater(
          first,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'injected Windows re-entry failure',
            ),
          ),
        );

        releaseFirst.complete();
        await firstFailure;
        await secondStarted.future.timeout(const Duration(seconds: 1));

        driver.write('FRAME-DURING-SECOND');
        expect(out.written.toString(), isNot(contains('FRAME-DURING-SECOND')));

        releaseSecond.complete();
        await second.timeout(const Duration(seconds: 1));
        expect(out.enterSequenceWrites, 3);

        driver.write('FRAME-AFTER-FAILURE');
        expect(out.written.toString(), contains('FRAME-AFTER-FAILURE'));
      } finally {
        await driver.restore();
        await input.close();
      }
    },
  );

  test('Windows raw-mode setters disable echo before line mode', () async {
    final trace = <String>[];
    final input = _FakeStdin(terminal: true, modeTrace: trace);
    final out = _RecordingStdout();
    final driver = WindowsTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      resizePollInterval: Duration.zero,
    );

    try {
      await driver.enter(TerminalMode.interactive);
      expect(trace.take(4).toList(), <String>[
        'get:line',
        'get:echo',
        'set:echo:false',
        'set:line:false',
      ]);

      await driver.restore();
      expect(trace.sublist(trace.length - 2), <String>[
        'set:line:true',
        'set:echo:true',
      ]);
    } finally {
      await driver.restore();
      await input.close();
    }
  });

  test('Windows nested handoff performs one restore/re-entry cycle', () async {
    final input = _FakeStdin();
    final out = _RecordingStdout();
    final driver = WindowsTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      resizePollInterval: Duration.zero,
    );

    try {
      await driver.enter(TerminalMode.interactive);
      out.written.clear();
      final result = await driver
          .runWithTerminalHandoff(() => driver.runWithTerminalHandoff(() => 42))
          .timeout(const Duration(seconds: 1));

      expect(result, 42);
      expect(_occurrences(out.written.toString(), '\x1B[?1049l'), 1);
      expect(_occurrences(out.written.toString(), '\x1B[?1049h'), 1);
    } finally {
      await driver.restore();
      await input.close();
    }
  });
}
