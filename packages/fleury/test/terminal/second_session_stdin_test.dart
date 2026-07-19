// Regression coverage for finding #1: a second Fleury session in the SAME
// process crashed at enter() because dart:io's `stdin` is a process-global
// single-subscription stream — restore() cancels its subscription, and it can
// never be listened to again, so the next runApp's `stdin.listen(...)` threw
// the opaque 'Stream has already been listened to'. The driver now latches that
// the global stdin was spent and rejects a second enter() up front with a
// clear message (a real second-session-with-input feature would need a separate
// process; that is out of scope here — this makes the limit legible instead of
// a crash). An injected (test) stdin is exempt: each driver owns its own.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A single-subscription fake stdin (non-broadcast controller) that reproduces
/// dart:io's hazard: listening a second time after a cancel throws.
class _FakeStdin implements Stdin {
  final _controller = StreamController<List<int>>();

  Future<void> close() => _controller.close();

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullStdout implements Stdout {
  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void write(Object? object) {}

  @override
  Future<void> flush() => Future<void>.value();

  @override
  int get terminalColumns => throw const StdoutException('not a terminal');

  @override
  int get terminalLines => throw const StdoutException('not a terminal');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'an injected stdin is exempt: a fresh stream drives a session normally',
    () async {
      // The guard keys on identity with the process-global stdin, so an
      // injected stream is never latched — each driver cancels its own on
      // restore, exactly as before. This pins that the guard doesn't leak into
      // the injected/test path.
      final first = PosixTerminalDriver(
        stdinOverride: _FakeStdin(),
        stdoutOverride: _NullStdout(),
      );
      await first.enter(TerminalMode.interactive);
      await first.restore();

      final second = PosixTerminalDriver(
        stdinOverride: _FakeStdin(),
        stdoutOverride: _NullStdout(),
      );
      // A different injected stream is fine; no cross-driver latch.
      await second.enter(TerminalMode.interactive);
      await second.restore();
    },
  );

  test(
    'posix: a second real-stdin session is rejected cleanly and the process '
    'still exits',
    () async {
      // Runs the fixture in a child process against the real process-global
      // stdin: session two must be rejected with the clear message (not the
      // opaque dart:io error), and the process must exit (never hang on a
      // dangling stdin subscription).
      final fixture =
          '${Directory.current.path}/test/fixtures/second_session_stdin_fixture.dart';
      final process = await Process.start(
        Platform.resolvedExecutable,
        <String>['run', fixture],
        workingDirectory: Directory.current.path,
      );
      // Keep the child's stdin OPEN (never write/close, never EOF) so a leaked
      // stdin subscription would keep its event loop alive and hang — exiting
      // proves session one released it on restore.
      final out = StringBuffer();
      final err = StringBuffer();
      process.stdout.transform(utf8.decoder).listen(out.write);
      process.stderr.transform(utf8.decoder).listen(err.write);

      var timedOut = false;
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 40),
        onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await process.stdin.close().catchError((_) {});

      expect(
        timedOut,
        isFalse,
        reason: 'process hung (a stdin subscription was never released)',
      );
      expect(exitCode, 0, reason: 'stdout:\n$out\nstderr:\n$err');
      expect(out.toString(), contains('SESSION-0-OK'));
      expect(
        out.toString(),
        contains('SESSION-1-REJECTED-CLEANLY'),
        reason: 'second session must be rejected with the clear message',
      );
      expect(err.toString(), isNot(contains('already been listened')));
    },
    timeout: const Timeout(Duration(seconds: 90)),
    // PosixTerminalDriver is POSIX-only.
    skip: Platform.isWindows ? 'POSIX driver only' : null,
  );
}
