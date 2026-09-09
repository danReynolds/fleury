// Launch-audit F7: Ctrl+Z self-suspension must be write-exclusive and
// single-flight, the way editor handoff already is. Before the fix, _suspend
// restored the
// terminal for the shell and then `await`ed (flush/cancel) with NO write gate,
// so a frame flush scheduled on a microtask / the ~30Hz ticker sprayed ANSI
// onto the bare shell — the classic "my terminal is garbled after Ctrl+Z" —
// and a second Ctrl+Z attempted another self-stop.
//
// The raw Ctrl+Z byte path is covered by the ordinary PTY tier; inherited-stdio
// editor handoff remains an opt-in controlling-terminal proof. This unit test
// drives the gate directly through @visibleForTesting seams: selfStopOverride
// replaces Process.killPid and non-TTY fake stdio keeps the test deterministic.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/posix_driver.dart'
    show PosixTerminalModeController;
import 'package:test/test.dart';

/// Records every [write]; reports as a non-terminal so enter() stays cheap.
class _RecordingStdout implements Stdout {
  final StringBuffer written = StringBuffer();

  @override
  bool get hasTerminal => false;

  @override
  void write(Object? object) => written.write(object);

  @override
  Future<void> flush() async {}

  @override
  bool get supportsAnsiEscapes => false;

  // A real non-terminal stdout throws StdoutException on these; the driver's
  // `size` getter catches that and falls back to $COLUMNS/$LINES or 80x24.
  @override
  int get terminalColumns => throw const StdoutException('not a terminal');

  @override
  int get terminalLines => throw const StdoutException('not a terminal');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A non-terminal stdin backed by a controller — enter()'s listen() attaches,
/// nothing is fed.
class _FakeStdin implements Stdin {
  _FakeStdin({this.hasTerminal = false});
  final _controller = StreamController<List<int>>();

  @override
  final bool hasTerminal;

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

class _RawMode implements PosixTerminalModeController {
  _RawMode({this.available = true});
  final bool available;
  @override
  bool enableRawMode() => available;
  @override
  bool restoreMode() => true;
}

void main() {
  test('applications can own Ctrl+Z without driver self-suspension', () async {
    final input = _FakeStdin(hasTerminal: true);
    var stops = 0;
    final driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: _RecordingStdout(),
      suspendOnCtrlZ: false,
      terminalModeController: _RawMode(),
      selfStopOverride: () {
        stops++;
        return true;
      },
    );
    final events = <TuiEvent>[];
    final subscription = driver.events.listen(events.add);
    try {
      await driver.enter(TerminalMode.interactive);
      input._controller.add([0x1a]);
      await Future<void>.delayed(Duration.zero);
      final chord = events.whereType<KeyEvent>().single;
      expect(chord.code, KeyCode.z);
      expect(chord.hasCtrl, isTrue);
      expect(stops, 0);
      expect(driver.debugSuspended, isFalse);
    } finally {
      await driver.restore();
      await subscription.cancel();
      await input.close();
    }
  });

  test(
    'application-owned Ctrl+Z rejects native raw-mode failure before fallback',
    () async {
      final input = _FakeStdin(hasTerminal: true);
      final output = _RecordingStdout();
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: output,
        suspendOnCtrlZ: false,
        terminalModeController: _RawMode(available: false),
      );
      try {
        await expectLater(
          driver.enter(TerminalMode.interactive),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('requires native POSIX raw mode'),
            ),
          ),
        );
        expect(driver.isActive, isFalse);
        expect(input._controller.hasListener, isFalse);
        expect(output.written.toString(), isEmpty);
      } finally {
        await driver.restore();
        // Rejection intentionally never subscribes to stdin; drain only to close
        // this test controller. A fallback getter/setter would throw in the fake.
        final drained = input._controller.stream.drain<void>();
        await input.close();
        await drained;
      }
    },
  );

  group('PosixTerminalDriver Ctrl+Z self-stop gating (F7)', () {
    late _RecordingStdout out;
    late _FakeStdin input;
    late int selfStops;
    late bool stopTakes;
    late PosixTerminalDriver driver;

    setUp(() async {
      out = _RecordingStdout();
      input = _FakeStdin();
      selfStops = 0;
      stopTakes = true;
      driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        selfStopOverride: () {
          selfStops++;
          return stopTakes;
        },
      );
      await driver.enter(TerminalMode.interactive);
    });

    tearDown(() async {
      await driver.restore();
      await input.close();
    });

    test(
      'frame writes are dropped while suspended, and flow again on resume',
      () async {
        driver.write('FRAME-A');
        expect(out.written.toString(), contains('FRAME-A'), reason: 'baseline');

        await driver.debugSuspend();
        expect(driver.debugSuspended, isTrue);
        expect(
          selfStops,
          1,
          reason: 'the process self-stop was attempted once',
        );

        out.written.clear();
        driver.write('FRAME-B'); // scheduled frame arriving mid-suspend
        expect(
          out.written.toString(),
          isEmpty,
          reason:
              'a frame written while the shell owns the terminal must be '
              'dropped, not sprayed onto the prompt',
        );

        driver.debugResume();
        expect(driver.debugSuspended, isFalse);
        driver.write('FRAME-C');
        expect(
          out.written.toString(),
          contains('FRAME-C'),
          reason: 'writes flow again once we re-entered our mode',
        );
      },
    );

    test(
      'a second Ctrl+Z while suspended is a no-op (single-flight)',
      () async {
        await driver.debugSuspend();
        expect(selfStops, 1);
        await driver
            .debugSuspend(); // rapid second Ctrl+Z / queued during awaits
        expect(
          selfStops,
          1,
          reason:
              'suspend must not re-raise the stop or re-write sequences '
              'while already suspended',
        );
      },
    );

    test('a stop that does not take un-gates instead of freezing', () async {
      // If the self-stop fails (killPid returns false), we're still running —
      // the gate must NOT latch, or write() would no-op forever waiting for a
      // resume that never comes (a frozen screen — worse than the garble the
      // gate prevents).
      stopTakes = false;
      await driver.debugSuspend();
      expect(
        driver.debugSuspended,
        isFalse,
        reason: 'a failed stop leaves us running, so frames must still flow',
      );
      driver.write('STILL-ALIVE');
      expect(out.written.toString(), contains('STILL-ALIVE'));
    });
  });
}
