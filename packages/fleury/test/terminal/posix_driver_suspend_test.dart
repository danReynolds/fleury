// Launch-audit F7: SIGTSTP (Ctrl+Z) must be write-exclusive and single-flight,
// the way editor handoff already is. Before the fix, _suspend restored the
// terminal for the shell and then `await`ed (flush/cancel) with NO write gate,
// so a frame flush scheduled on a microtask / the ~30Hz ticker sprayed ANSI
// onto the bare shell — the classic "my terminal is garbled after Ctrl+Z" —
// and a second Ctrl+Z re-raised the stop.
//
// The real signal delivery + editor handoff are covered by the PTY job-control
// tier (opt-in, FLEURY_PTY_JOB_CONTROL=1). This unit test drives the gate
// directly through @visibleForTesting seams so the invariant runs in CI: it
// needs no real job control (selfStopOverride replaces Process.killPid) and no
// real terminal (non-TTY fake stdio — enter() sets _mode and skips the
// probe/raw-mode work, while write()'s gate is terminal-independent).

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
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
  final _controller = StreamController<List<int>>();

  @override
  bool get hasTerminal => false;

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

void main() {
  group('PosixTerminalDriver SIGTSTP gating (F7)', () {
    late _RecordingStdout out;
    late _FakeStdin input;
    late int selfStops;
    late PosixTerminalDriver driver;

    setUp(() async {
      out = _RecordingStdout();
      input = _FakeStdin();
      selfStops = 0;
      driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: out,
        selfStopOverride: () => selfStops++,
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
        expect(selfStops, 1, reason: 'the stop was re-raised once');

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
  });
}
