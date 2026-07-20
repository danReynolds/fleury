import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/posix_driver.dart'
    show PosixTerminalModeController;
import 'package:test/test.dart';

class _FakeStdin implements Stdin {
  _FakeStdin({this.terminal = false});

  final bool terminal;
  final _controller = StreamController<List<int>>();

  void push(List<int> bytes) => _controller.add(bytes);
  Future<void> close() => _controller.close();

  @override
  bool get hasTerminal => terminal;

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingStdout implements Stdout {
  _RecordingStdout({this.terminal = false, this.onWrite, List<String>? trace})
    : trace = trace ?? <String>[];

  final bool terminal;
  final void Function(String bytes)? onWrite;
  final written = StringBuffer();
  final List<String> trace;

  @override
  bool get hasTerminal => terminal;

  @override
  void write(Object? object) {
    final bytes = '$object';
    written.write(bytes);
    trace.add('write:$bytes');
    onWrite?.call(bytes);
  }

  @override
  Future<void> flush() async => trace.add('flush');

  @override
  bool get supportsAnsiEscapes => terminal;

  @override
  int get terminalColumns {
    if (terminal) return 80;
    throw const StdoutException('not a terminal');
  }

  @override
  int get terminalLines {
    if (terminal) return 24;
    throw const StdoutException('not a terminal');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledFlushStdout extends _RecordingStdout {
  _ControlledFlushStdout();

  final List<Completer<void>> flushes = <Completer<void>>[];

  @override
  Future<void> flush() {
    final completer = Completer<void>();
    flushes.add(completer);
    return completer.future;
  }

  Future<void> waitForFlushCount(int count) async {
    while (flushes.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _FakeModeController implements PosixTerminalModeController {
  _FakeModeController(this.trace, {this.throwOnRawCount});

  final List<String> trace;
  final int? throwOnRawCount;
  int rawCount = 0;
  int restoreCount = 0;

  @override
  bool enableRawMode() {
    rawCount++;
    trace.add('mode:raw');
    if (rawCount == throwOnRawCount) {
      throw StateError('injected raw-mode re-entry failure');
    }
    return true;
  }

  @override
  bool restoreMode() {
    restoreCount++;
    trace.add('mode:restore');
    return true;
  }
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test(
    'raw Ctrl+Z restores before self-stop, is consumed, and resumes',
    () async {
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      late final _RecordingStdout out;
      out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: (bytes) {
          // Reply to whichever startup probes the ambient environment enables,
          // keeping this lifecycle test deterministic and fast.
          if (bytes.contains('\x1B[6n')) {
            scheduleMicrotask(
              () => input.push('\x1B[1;2R\x1B[?1;2c'.codeUnits),
            );
          } else if (bytes.contains('\x1B[c')) {
            scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
          }
        },
      );
      final modes = _FakeModeController(trace);
      var selfStops = 0;
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: modes,
        selfStopOverride: () {
          selfStops++;
          trace.add('stop');
          return true;
        },
      );
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);

      try {
        await driver.enter(TerminalMode.interactive);
        trace.clear();

        // Kitty can distinguish modified printable chords. Redo and other
        // app bindings must not be mistaken for the exact job-control chord.
        input.push('\x1B[122;6u'.codeUnits); // Ctrl+Shift+Z
        await _pump();
        expect(selfStops, 0);
        expect(
          events.whereType<KeyEvent>(),
          contains(
            const KeyEvent(
              KeyCode.char('z'),
              modifiers: <KeyModifier>{KeyModifier.ctrl, KeyModifier.shift},
            ),
          ),
        );
        events.clear();

        input.push(const <int>[0x1A]);
        await _pump();

        expect(selfStops, 1);
        expect(driver.debugSuspended, isTrue);
        expect(
          events.whereType<KeyEvent>(),
          isEmpty,
          reason: 'the job-control chord belongs to the driver, not the app',
        );
        final restoreAt = trace.indexOf('mode:restore');
        final exitAt = trace.indexWhere(
          (entry) =>
              entry.startsWith('write:') && entry.contains('\x1B[?1049l'),
        );
        final flushAt = trace.indexOf('flush');
        final stopAt = trace.indexOf('stop');
        expect(restoreAt, greaterThanOrEqualTo(0));
        expect(exitAt, greaterThan(restoreAt));
        expect(flushAt, greaterThan(exitAt));
        expect(stopAt, greaterThan(flushAt));

        out.written.clear();
        driver.write('FRAME-WHILE-STOPPED');
        expect(out.written.toString(), isEmpty);

        driver.debugResume();
        await _pump();
        expect(driver.debugSuspended, isFalse);
        expect(modes.rawCount, 2, reason: 'raw mode is re-applied after fg');
        expect(out.written.toString(), contains('\x1B[?1049h'));
        expect(events.whereType<ResizeEvent>(), hasLength(1));
      } finally {
        await sub.cancel();
        await driver.restore();
        await input.close();
      }
    },
  );

  test('restore invalidates a suspend continuation waiting on flush', () async {
    final input = _FakeStdin(terminal: true);
    final out = _ControlledFlushStdout();
    final modes = _FakeModeController(<String>[]);
    var selfStops = 0;
    final driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      terminalModeController: modes,
      selfStopOverride: () {
        selfStops++;
        return true;
      },
    );

    await driver.enter(TerminalMode.interactive);
    input.push(const <int>[0x1A]);
    await out.waitForFlushCount(1);

    final restoring = driver.restore();
    await out.waitForFlushCount(2);
    out.flushes[0].complete();
    out.flushes[1].complete();
    await restoring;
    await _pump();

    expect(
      selfStops,
      0,
      reason: 'a stale suspend must not stop after teardown',
    );
    expect(driver.debugSuspended, isFalse);
    await input.close();
  });

  test(
    'a signal delivered during restore cannot leave a grace timer',
    () async {
      final input = _FakeStdin();
      final out = _ControlledFlushStdout();
      final forcedExitCodes = <int>[];
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        signalGrace: const Duration(milliseconds: 20),
        forceExitOverride: forcedExitCodes.add,
      );

      await driver.enter(TerminalMode.interactive);
      final restoring = driver.restore();
      await out.waitForFlushCount(1);
      driver.deliverSignal(AppSignal.terminate);
      out.flushes.single.complete();
      await restoring;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(forcedExitCodes, isEmpty);
      await input.close();
    },
  );

  test(
    'stdin EOF closes events and later lifecycle callbacks stay harmless',
    () async {
      final input = _FakeStdin();
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: _RecordingStdout(),
      );
      final done = Completer<void>();
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add, onDone: done.complete);

      await driver.enter(TerminalMode.interactive);
      input.push('\x1B[200~abc'.codeUnits);
      await input.close();
      await done.future.timeout(const Duration(seconds: 1));
      expect(events.whereType<PasteEvent>(), [const PasteEvent('abc')]);

      // These paths normally emit resize/signal events. Once EOF has closed the
      // stream, they must be no-ops rather than add-to-closed-stream races.
      driver.debugResume();
      await driver.runWithTerminalHandoff(() {});
      driver.deliverSignal(AppSignal.terminate);
      await _pump();

      await driver.restore();
      await sub.cancel();
    },
  );

  test(
    'concurrent handoffs serialize and keep stdin and frame writes gated',
    () async {
      final input = _FakeStdin();
      final out = _RecordingStdout();
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
      );
      final events = <TuiEvent>[];
      final sub = driver.events.listen(events.add);
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
          reason: 'a second child must wait for terminal ownership',
        );

        input.push('x'.codeUnits);
        driver.write('FRAME-DURING-FIRST');
        await _pump();
        expect(
          events.whereType<TextInputEvent>(),
          isEmpty,
          reason: 'the parent stdin subscription is paused for the child',
        );
        expect(out.written.toString(), isNot(contains('FRAME-DURING-FIRST')));

        releaseFirst.complete();
        await secondStarted.future.timeout(const Duration(seconds: 1));
        driver.write('FRAME-DURING-SECOND');
        expect(out.written.toString(), isNot(contains('FRAME-DURING-SECOND')));

        releaseSecond.complete();
        await Future.wait<void>(<Future<void>>[first, second]);
        await _pump();
        expect(
          events.whereType<TextInputEvent>().map((event) => event.text).join(),
          'x',
          reason: 'buffered input resumes only after Fleury reclaims the tty',
        );
        expect(events.whereType<ResizeEvent>(), hasLength(2));

        driver.write('FRAME-AFTER');
        expect(out.written.toString(), contains('FRAME-AFTER'));
      } finally {
        await sub.cancel();
        await driver.restore();
        await input.close();
      }
    },
  );

  test(
    'failed re-entry rejects one handoff without wedging the queue',
    () async {
      final input = _FakeStdin(terminal: true);
      final out = _RecordingStdout();
      final modes = _FakeModeController(<String>[], throwOnRawCount: 2);
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: modes,
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
              'injected raw-mode re-entry failure',
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
        expect(modes.rawCount, 3);
        expect(modes.restoreCount, 2);

        driver.write('FRAME-AFTER-FAILURE');
        expect(out.written.toString(), contains('FRAME-AFTER-FAILURE'));
      } finally {
        await driver.restore();
        await input.close();
      }
    },
  );

  test(
    'a nested handoff reuses restored ownership without double lifecycle',
    () async {
      final input = _FakeStdin();
      final out = _RecordingStdout();
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
      );
      var starts = 0;
      var ends = 0;
      driver.onHandoffStart = () async => starts++;
      driver.onHandoffEnd = () async => ends++;

      try {
        await driver.enter(TerminalMode.interactive);
        final result = await driver
            .runWithTerminalHandoff(() async {
              driver.write('OUTER-FRAME');
              return driver.runWithTerminalHandoff(() async {
                driver.write('INNER-FRAME');
                return 42;
              });
            })
            .timeout(const Duration(seconds: 1));

        expect(result, 42);
        expect(starts, 1);
        expect(ends, 1);
        expect(out.written.toString(), isNot(contains('OUTER-FRAME')));
        expect(out.written.toString(), isNot(contains('INNER-FRAME')));
        driver.write('AFTER-NESTED');
        expect(out.written.toString(), contains('AFTER-NESTED'));
      } finally {
        await driver.restore();
        await input.close();
      }
    },
  );
}
