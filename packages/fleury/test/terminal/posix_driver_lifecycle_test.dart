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

  /// A latency-simulating fake answers on a timer, which can outlive the test
  /// that armed it. Pushing into a closed controller throws asynchronously and
  /// the failure lands on whatever test is running next, so the fake tracks
  /// its own closure rather than leaving that to each caller.
  bool closed = false;

  void push(List<int> bytes) {
    if (closed) return;
    _controller.add(bytes);
  }

  Future<void> close() {
    closed = true;
    return _controller.close();
  }

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

/// A terminal-reporting stdin that never answers a probe: every startup query
/// stays in flight for its full timeout, which is the window a concurrent
/// `restore()` has to land in.
class _SilentTerminalStdin implements Stdin {
  final _controller = StreamController<List<int>>();
  bool _lineMode = true;
  bool _echoMode = true;

  @override
  bool get hasTerminal => true;

  @override
  bool get lineMode => _lineMode;
  @override
  set lineMode(bool value) => _lineMode = value;

  @override
  bool get echoMode => _echoMode;
  @override
  set echoMode(bool value) => _echoMode = value;

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

/// A signal subscription that only records its own cancellation.
class _TraceSignalSubscription implements StreamSubscription<ProcessSignal> {
  _TraceSignalSubscription(this.signal, this.trace);

  final ProcessSignal signal;
  final List<String> trace;

  @override
  Future<void> cancel() async => trace.add('unwatch:${signal.name}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A stdout whose final flush hangs until released — a pty write blocked
/// behind a dropped SSH session or an XOFF.
class _HangingFlushStdout extends _RecordingStdout {
  _HangingFlushStdout({required super.trace}) : super(terminal: true);

  final Completer<void> release = Completer<void>();
  var flushes = 0;

  @override
  Future<void> flush() {
    flushes++;
    trace.add('flush');
    // The first flushes are startup probes; only a flush during restore is
    // held, and the test decides when it lets go.
    return holding ? release.future : Future<void>.value();
  }

  bool holding = false;
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test(
    'unsupported Kitty input falls back to legacy parsing across resume',
    () async {
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      late final _RecordingStdout out;
      out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: (bytes) {
          if (bytes.contains('\x1B[6n')) {
            scheduleMicrotask(
              () => input.push('\x1B[1;2R\x1B[?1;2c'.codeUnits),
            );
          } else if (bytes.contains('\x1B[c')) {
            scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
          }
        },
      );
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(trace),
        selfStopOverride: () => true,
      );

      try {
        final profile = await driver.enter(TerminalMode.interactive);
        expect(profile.keyboard, KeyboardCapabilities.legacy);
        expect(
          (profile.presentation as AnsiTerminalPresentation).synchronizedOutput,
          isFalse,
          reason: 'a DA sentinel without a mode-2026 reply is unsupported',
        );
        expect(out.written.toString(), contains('\x1B[<1u'));
        expect(out.written.toString(), isNot(contains('\x1B[>4;2m')));
        out.written.clear();

        await driver.debugSuspend();
        driver.debugResume();

        expect(out.written.toString(), isNot(contains('\x1B[>4;2m')));
        expect(out.written.toString(), isNot(contains('\x1B[>31u')));
        out.written.clear();
        await driver.restore();
        expect(out.written.toString(), isNot(contains('\x1B[>4;0m')));
      } finally {
        await driver.restore();
        await input.close();
      }
    },
  );

  test('mode-2026 support is negotiated into the session profile', () async {
    final trace = <String>[];
    final input = _FakeStdin(terminal: true);
    late final _RecordingStdout out;
    out = _RecordingStdout(
      terminal: true,
      trace: trace,
      onWrite: (bytes) {
        if (bytes.contains('[?u')) {
          scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
        } else if (bytes.contains('?2026\$p')) {
          scheduleMicrotask(
            () => input.push('\x1B[?2026;2\$y\x1B[?1;2c'.codeUnits),
          );
        } else if (bytes.contains('\x1B[6n')) {
          scheduleMicrotask(() => input.push('\x1B[1;2R\x1B[?1;2c'.codeUnits));
        } else if (bytes.contains('\x1B[c')) {
          scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
        }
      },
    );
    final driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      terminalModeController: _FakeModeController(trace),
    );

    try {
      final profile = await driver.enter(TerminalMode.interactive);
      expect(
        (profile.presentation as AnsiTerminalPresentation).synchronizedOutput,
        isTrue,
      );
      expect(out.written.toString(), contains('\x1B[?2026\$p'));
    } finally {
      await driver.restore();
      await input.close();
    }
  });

  test(
    'negotiated keyboard fallback is the mode restored after resume',
    () async {
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      late final _RecordingStdout out;
      out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: (bytes) {
          if (bytes.contains('\x1B[?u')) {
            scheduleMicrotask(() => input.push('\x1B[?3u\x1B[?1;2c'.codeUnits));
          } else if (bytes.contains('\x1B[6n')) {
            scheduleMicrotask(
              () => input.push('\x1B[1;2R\x1B[?1;2c'.codeUnits),
            );
          } else if (bytes.contains('\x1B[c')) {
            scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
          }
        },
      );
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(trace),
        selfStopOverride: () => true,
      );

      try {
        final profile = await driver.enter(TerminalMode.interactive);
        expect(profile.keyboard.distinguishesRepeats, isTrue);
        expect(profile.keyboard.supportsHeldState, isFalse);
        out.written.clear();

        await driver.debugSuspend();
        driver.debugResume();

        expect(out.written.toString(), contains('\x1B[>3u'));
        expect(
          out.written.toString(),
          isNot(contains('\x1B[>31u')),
          reason:
              'resume must not re-enable the lifecycle tier that was rejected',
        );
      } finally {
        await driver.restore();
        await input.close();
      }
    },
  );

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

  test('restore() during startup negotiation reports the lifecycle StateError '
      '(RFC 0021 §12)', () async {
    // runApp's zone handler calls cleanup() on any uncaught async error and
    // the startup probes hold the driver for up to ~500 ms, so a restore
    // landing mid-negotiation is reachable in production. `enter` must
    // surface it as its own StateError. It used to read `_mode!` (i.e.
    // `_terminalState!.effectiveMode`) three lines BEFORE the lifecycle
    // guard, so a restore that had already nulled `_terminalState` produced
    // a bare null-check `_TypeError` instead.
    final input = _SilentTerminalStdin();
    PosixTerminalDriver? driver;
    var fired = false;
    final restored = Completer<void>();
    final out = _RecordingStdout(
      terminal: true,
      onWrite: (bytes) {
        // The first startup query. Tear the driver down while it waits for
        // a reply that never comes.
        if (fired || !bytes.contains('\x1B[?u')) return;
        fired = true;
        scheduleMicrotask(() async {
          await driver!.restore();
          restored.complete();
        });
      },
    );
    driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      terminalModeController: _FakeModeController(out.trace),
    );

    await expectLater(
      driver.enter(TerminalMode.interactive),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'PosixTerminalDriver was restored while enter was negotiating.',
        ),
      ),
    );
    expect(fired, isTrue, reason: 'the probe write hook must have run');
    await restored.future;
    await input.close();
  }, timeout: const Timeout(Duration(seconds: 15)));

  test(
    'restore() keeps SIGINT/SIGTERM shielded until the terminal is back',
    () async {
      // Cancelling the last subscription to a signal restores the OS default
      // disposition. restore() cancels the real watchers first (so nothing can
      // re-arm signal grace) and then yields through the remaining cleanup —
      // during which the hot-reload supervisor's 300 ms forward used to kill
      // the process raw, mid-restore. A no-op shield now covers that window
      // and is dropped last.
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      late final _RecordingStdout out;
      out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: (bytes) {
          if (bytes.contains('\x1B[6n')) {
            scheduleMicrotask(
              () => input.push('\x1B[1;2R\x1B[?1;2c'.codeUnits),
            );
          } else if (bytes.contains('\x1B[c')) {
            scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
          }
        },
      );
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(trace),
        selfStopOverride: () => true,
        signalWatcherOverride: (signal, onSignal) {
          trace.add('watch:${signal.name}');
          return _TraceSignalSubscription(signal, trace);
        },
      );
      try {
        await driver.enter(TerminalMode.interactive);
        trace.clear();
        await driver.restore();

        final unwatches = [
          for (var i = 0; i < trace.length; i++)
            if (trace[i] == 'unwatch:${ProcessSignal.sigint.name}') i,
        ];
        expect(
          unwatches,
          hasLength(2),
          reason: 'real watcher + shield: $trace',
        );
        final shieldWatch = trace.indexOf('watch:${ProcessSignal.sigint.name}');
        expect(
          shieldWatch,
          lessThan(unwatches.first),
          reason:
              'the shield is listening before the real watcher is cancelled',
        );
        expect(
          unwatches.last,
          greaterThan(trace.indexOf('mode:restore')),
          reason: 'the shield outlives the cooked-mode restore',
        );
        expect(
          unwatches.last,
          greaterThan(trace.lastIndexOf('flush')),
          reason: 'the shield outlives the final flush',
        );
        expect(
          trace.where((e) => e == 'unwatch:${ProcessSignal.sigterm.name}'),
          hasLength(2),
        );
      } finally {
        await driver.restore();
        await input.close();
      }
    },
  );

  group('startup negotiation adapts to link latency', () {
    // Answers every startup query the driver can emit, [delay] after the
    // request is written — a fake link with a measurable round trip. The
    // patterns are ordered specific-first because each query carries the
    // Device Attributes sentinel (`ESC [ c`) that terminates it.
    // A terminal processes its input in order and answers every query it
    // finds, so one write holding several queries gets several replies, in
    // the order the queries were read.
    String answerEveryQuery(String bytes) {
      const answers = <(String, String)>[
        ('\x1B[?u', '\x1B[?31u'),
        ('?2026\$p', '\x1B[?2026;2\$y'),
        ('\x1B_G', '\x1B_Gi=31;OK\x1B\\'),
        ('\x1B[6n', '\x1B[1;2R'),
        ('\x1B[c', '\x1B[?1;2c'),
      ];
      final found = <(int, String)>[];
      for (final (query, answer) in answers) {
        var at = bytes.indexOf(query);
        while (at >= 0) {
          found.add((at, answer));
          at = bytes.indexOf(query, at + query.length);
        }
      }
      found.sort((a, b) => a.$1.compareTo(b.$1));
      return found.map((f) => f.$2).join();
    }

    void Function(String bytes) slowTerminal(
      _FakeStdin input,
      Duration delay,
    ) => (bytes) {
      final reply = answerEveryQuery(bytes);
      if (reply.isEmpty) return;
      final bytesToPush = reply.codeUnits;
      Timer(delay, () => input.push(bytesToPush));
    };

    test('the capability probes after keyboard negotiation go out in ONE '
        'exchange', () async {
      // Sent one after another, synchronized output, the image protocol
      // and the width battery cost a round trip each — over a 50 ms SSH
      // link that is most of startup. They are independent, so they go
      // out in one write and the terminal answers them in order.
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      final writes = <String>[];
      final out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: (bytes) {
          writes.add(bytes);
          final reply = answerEveryQuery(bytes);
          if (reply.isNotEmpty) {
            Timer(const Duration(milliseconds: 5), () {
              input.push(reply.codeUnits);
            });
          }
        },
      );
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(trace),
      );
      try {
        final profile = await driver.enter(TerminalMode.interactive);
        expect(
          (profile.presentation as AnsiTerminalPresentation).synchronizedOutput,
          isTrue,
        );
        final exchanges = writes.where((w) => w.contains('\x1B[c')).toList();
        expect(
          exchanges,
          hasLength(2),
          reason:
              'keyboard negotiation, then every remaining capability query '
              'in one exchange; got ${exchanges.length} exchanges',
        );
        final batch = exchanges.last;
        expect(batch, contains('?2026\$p'));
        expect(
          batch,
          contains('\x1B[6n'),
          reason: 'the width battery rides the same exchange',
        );
        // Positional segmentation: the query a terminal is most likely to
        // choke on (the image APC) must be last so it can only cost
        // itself, and every query that paints must end with an erase.
        expect(batch.indexOf('?2026\$p'), lessThan(batch.indexOf('\x1B[6n')));
        final apc = batch.indexOf('\x1B_G');
        if (apc >= 0) {
          expect(apc, greaterThan(batch.lastIndexOf('\x1B[6n')));
          expect(
            batch.substring(apc),
            contains('\r\x1B[K\x1B[c'),
            reason: 'the APC cleans up after itself before its sentinel',
          );
        }
      } finally {
        await driver.restore();
        await input.close();
      }
    });

    test('a 200 ms link negotiates the same capabilities a local one does '
        '(3.b)', () async {
      // The defect: every probe carried a fixed 150 ms deadline, so a link
      // slower than ~130 ms round trip timed ALL of them out and the session
      // silently degraded on every axis at once — the ordinary condition of an
      // agent TUI over SSH. 200 ms is a plain transpacific hop.
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      final out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: slowTerminal(input, const Duration(milliseconds: 200)),
      );
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(trace),
      );

      try {
        final profile = await driver.enter(TerminalMode.interactive);
        expect(
          profile.keyboard,
          isNot(KeyboardCapabilities.legacy),
          reason: 'the keyboard reply arrived; latency must not veto it',
        );
        expect(profile.keyboard.distinguishesRepeats, isTrue);
        expect(
          (profile.presentation as AnsiTerminalPresentation).synchronizedOutput,
          isTrue,
          reason:
              'the second probe scales to the round trip the first measured',
        );
      } finally {
        await driver.restore();
        await input.close();
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a terminal that answers NOTHING is asked nothing more', () async {
      // With the base budget this held by arithmetic alone: the remaining
      // budget after the first probe was shorter than the quarantine
      // grace, so the batch timed out before it was written. A longer
      // budget used to send ~200 bytes of queries — 14 painted glyphs and
      // an APC — to a terminal that had answered nothing.
      final saved = PosixTerminalDriver.startupNegotiationBudget;
      PosixTerminalDriver.startupNegotiationBudget = const Duration(
        milliseconds: 900,
      );
      addTearDown(() => PosixTerminalDriver.startupNegotiationBudget = saved);
      final input = _SilentTerminalStdin();
      final writes = <String>[];
      final out = _RecordingStdout(terminal: true, onWrite: writes.add);
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(out.trace),
      );
      try {
        await driver.enter(TerminalMode.interactive);
        final sent = writes.join();
        expect(sent, contains('\x1B[?u'), reason: 'the keyboard probe');
        for (final query in ['?2026\$p', '\x1B[6n', '\x1B_G']) {
          expect(
            sent,
            isNot(contains(query)),
            reason: 'a silent terminal must not be sent $query',
          );
        }
      } finally {
        await driver.restore();
        await input.close();
      }
    });

    test(
      'a terminal that answers NOTHING still starts on the base budget',
      () async {
        // The adaptive deadline may never be reachable by staying silent: no
        // answer means no measurement, so the budget stays at 500 ms and the
        // cost of an unanswered handshake is exactly what it was before.
        final input = _SilentTerminalStdin();
        final out = _RecordingStdout(terminal: true);
        final driver = PosixTerminalDriver(
          stdinOverride: input,
          stdoutOverride: out,
          terminalModeController: _FakeModeController(out.trace),
        );
        final clock = Stopwatch()..start();
        try {
          final profile = await driver.enter(TerminalMode.interactive);
          clock.stop();
          expect(profile.keyboard, KeyboardCapabilities.legacy);
          expect(
            clock.elapsed,
            lessThan(const Duration(milliseconds: 1500)),
            reason:
                'a silent terminal must not reach the 2 s adaptive ceiling; '
                'the base budget is 500 ms',
          );
        } finally {
          await driver.restore();
          await input.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      'a local terminal still negotiates inside the original budget',
      () async {
        final trace = <String>[];
        final input = _FakeStdin(terminal: true);
        final out = _RecordingStdout(
          terminal: true,
          trace: trace,
          onWrite: slowTerminal(input, Duration.zero),
        );
        final driver = PosixTerminalDriver(
          stdinOverride: input,
          stdoutOverride: out,
          terminalModeController: _FakeModeController(trace),
        );
        final clock = Stopwatch()..start();
        try {
          final profile = await driver.enter(TerminalMode.interactive);
          clock.stop();
          expect(profile.keyboard.distinguishesRepeats, isTrue);
          expect(
            (profile.presentation as AnsiTerminalPresentation)
                .synchronizedOutput,
            isTrue,
          );
          expect(
            clock.elapsed,
            lessThan(PosixTerminalDriver.startupNegotiationBudget),
            reason: 'adaptivity must not slow the fast path down',
          );
        } finally {
          await driver.restore();
          await input.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    // The arithmetic behind the two behaviours above, pinned without a clock:
    // these are the shipped numbers, and changing one is a decision, not a
    // refactor.
    test('the deadline ladder is the documented one', () {
      const ms = Duration(milliseconds: 1);

      // Nothing answered yet: the one fixed deadline in the sequence.
      expect(PosixTerminalDriver.probeTimeoutFor(null), ms * 400);
      expect(
        PosixTerminalDriver.negotiationBudgetFor(null),
        PosixTerminalDriver.startupNegotiationBudget,
      );

      // A local terminal keeps the pre-adaptive timings exactly.
      expect(PosixTerminalDriver.probeTimeoutFor(ms * 1), ms * 150);
      expect(PosixTerminalDriver.probeTimeoutFor(ms * 50), ms * 150);
      expect(PosixTerminalDriver.negotiationBudgetFor(ms * 50), ms * 500);

      // A measured link buys 3 round trips per probe, 8 for the sequence.
      expect(PosixTerminalDriver.probeTimeoutFor(ms * 200), ms * 600);
      expect(PosixTerminalDriver.negotiationBudgetFor(ms * 200), ms * 1600);

      // Both are bounded: startup stops being free somewhere.
      expect(PosixTerminalDriver.probeTimeoutFor(ms * 400), ms * 1200);
      expect(PosixTerminalDriver.probeTimeoutFor(ms * 900), ms * 1500);
      expect(
        PosixTerminalDriver.negotiationBudgetFor(ms * 400),
        PosixTerminalDriver.maxStartupNegotiationBudget,
      );
    });
  });

  test(
    'suspend and handoff surrender input authority, and announce it',
    () async {
      // The runtime recovers held keys on a focus-out (RFC 0020 §10). Suspend
      // (Ctrl+Z) and a terminal handoff ($EDITOR) are the other two ways this
      // terminal stops reporting releases, and neither said so: held keys
      // stayed held across them. Both now emit a focus-out, and a focus-in
      // on return — ahead of the resume repaint.
      final trace = <String>[];
      final input = _FakeStdin(terminal: true);
      late final _RecordingStdout out;
      out = _RecordingStdout(
        terminal: true,
        trace: trace,
        onWrite: (bytes) {
          if (bytes.contains('\x1B[6n')) {
            scheduleMicrotask(
              () => input.push('\x1B[1;2R\x1B[?1;2c'.codeUnits),
            );
          } else if (bytes.contains('\x1B[c')) {
            scheduleMicrotask(() => input.push('\x1B[?1;2c'.codeUnits));
          }
        },
      );
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        terminalModeController: _FakeModeController(trace),
        selfStopOverride: () => true,
      );
      final events = <TuiEvent>[];
      StreamSubscription<TuiEvent>? sub;
      Iterable<bool> focus() =>
          events.whereType<TerminalFocusEvent>().map((e) => e.focused);
      try {
        await driver.enter(TerminalMode.interactive);
        sub = driver.events.listen(events.add);

        await driver.debugSuspend();
        await _pump();
        expect(focus(), [false], reason: 'suspend surrenders authority');

        driver.debugResume();
        await _pump();
        expect(focus(), [false, true]);
        final regained = events.indexWhere(
          (e) => e is TerminalFocusEvent && e.focused,
        );
        expect(
          events.skip(regained + 1).whereType<ResizeEvent>(),
          isNotEmpty,
          reason: 'focus-in lands before the resume repaint',
        );

        events.clear();
        await driver.runWithTerminalHandoff(() async {
          await _pump();
          expect(focus(), [false], reason: 'the child owns the terminal');
        });
        await _pump();
        expect(focus(), [false, true]);
      } finally {
        await sub?.cancel();
        await driver.restore();
        await input.close();
      }
    },
  );

  test("restore()'s signal shield is bounded: a second signal ends the "
      'process instead of being swallowed', () async {
    // The shield keeps SIGINT/SIGTERM subscribed for the whole restore so a
    // forwarded signal cannot kill the process raw mid-teardown. Unbounded,
    // that made a HUNG teardown (a pty write blocked behind a dropped SSH
    // session) unkillable by anything but SIGKILL, which restores nothing.
    final trace = <String>[];
    final input = _FakeStdin(terminal: true);
    late final _HangingFlushStdout out;
    final handlers = <ProcessSignal, List<void Function(ProcessSignal)>>{};
    final exits = <int>[];
    out = _HangingFlushStdout(trace: trace);
    final driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: out,
      terminalModeController: _FakeModeController(trace),
      selfStopOverride: () => true,
      forceExitOverride: exits.add,
      signalWatcherOverride: (signal, onSignal) {
        handlers.putIfAbsent(signal, () => []).add(onSignal);
        return _TraceSignalSubscription(signal, trace);
      },
    );
    await driver.enter(TerminalMode.interactive);
    out.holding = true;
    final restoring = driver.restore();
    await _pump();
    // The shield is the newest SIGINT watcher; the real one is cancelled.
    final shield = handlers[ProcessSignal.sigint]!.last;
    shield(ProcessSignal.sigint);
    expect(exits, isEmpty, reason: 'one signal is swallowed, as designed');
    shield(ProcessSignal.sigint);
    expect(exits, [130], reason: 'the second is the user overruling a hang');
    out.release.complete();
    await restoring;
    await input.close();
  });
}
