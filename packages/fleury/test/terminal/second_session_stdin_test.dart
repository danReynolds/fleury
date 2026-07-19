// Regression coverage for finding #1: a second Fleury session in the SAME
// process crashed at enter() because dart:io's `stdin` is a process-global
// single-subscription stream — restore() cancelled its subscription, so the
// next runApp's `stdin.listen(...)` threw 'Stream has already been listened
// to'. The driver now retains that one subscription (pause on restore, resume
// on the next enter), with a zero-delay idle-cancel so a single-session run
// still exits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A single-subscription fake stdin (non-broadcast controller) that reproduces
/// dart:io's hazard: listening a second time after a cancel throws.
class _FakeStdin implements Stdin {
  final _controller = StreamController<List<int>>();

  void push(List<int> bytes) {
    if (!_controller.isClosed) _controller.add(bytes);
  }

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

String _typed(List<TuiEvent> events) =>
    events.whereType<TextInputEvent>().map((event) => event.text).join();

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  test(
    'without sharing, cancel-then-relisten on one stdin throws — the hazard',
    () async {
      // The non-shared (injected) path cancels on restore, exactly as a real
      // single-subscription stdin behaves. Reusing the SAME stream for a second
      // driver reproduces the crash the shared path exists to prevent.
      final stdinStream = _FakeStdin();
      final first = PosixTerminalDriver(
        stdinOverride: stdinStream,
        stdoutOverride: _NullStdout(),
      );
      await first.enter(TerminalMode.interactive);
      await first.restore();

      final second = PosixTerminalDriver(
        stdinOverride: stdinStream,
        stdoutOverride: _NullStdout(),
      );
      await expectLater(
        () => second.enter(TerminalMode.interactive),
        throwsA(isA<StateError>()),
      );
      await second.restore();
      await stdinStream.close();
    },
  );

  test('posix: a second shared-stdin session reuses it — no crash, input flows',
      () async {
    final stdinStream = _FakeStdin();
    final firstEvents = <TuiEvent>[];
    final first = PosixTerminalDriver(
      stdinOverride: stdinStream,
      stdoutOverride: _NullStdout(),
      stdinIsSharedOverride: true,
    );
    final firstSub = first.events.listen(firstEvents.add);
    await first.enter(TerminalMode.interactive);
    stdinStream.push('a'.codeUnits);
    await _flush();
    expect(_typed(firstEvents), 'a');

    await first.restore();
    // Back-to-back second session, with no event-loop turn in between, so it
    // resumes the retained subscription before the idle-cancel timer fires.
    final secondEvents = <TuiEvent>[];
    final second = PosixTerminalDriver(
      stdinOverride: stdinStream,
      stdoutOverride: _NullStdout(),
      stdinIsSharedOverride: true,
    );
    final secondSub = second.events.listen(secondEvents.add);
    await second.enter(TerminalMode.interactive); // must NOT throw

    stdinStream.push('b'.codeUnits);
    await _flush();
    expect(_typed(secondEvents), 'b', reason: 'reused stdin feeds session two');
    expect(
      _typed(firstEvents),
      'a',
      reason: 'the restored first session must not receive later input',
    );

    await second.restore();
    await _flush(); // let the idle-cancel timer settle
    await firstSub.cancel();
    await secondSub.cancel();
    await stdinStream.close();
  });

  test('windows: a second shared-stdin session reuses it — no crash, input flows',
      () async {
    // Off-Windows the console-mode controller is a no-op, so the driver's
    // stdin lifecycle is exercisable here with fakes.
    final stdinStream = _FakeStdin();
    final firstEvents = <TuiEvent>[];
    final first = WindowsTerminalDriver(
      stdinOverride: stdinStream,
      stdoutOverride: _NullStdout(),
      stdinIsSharedOverride: true,
    );
    final firstSub = first.events.listen(firstEvents.add);
    await first.enter(TerminalMode.interactive);
    stdinStream.push('a'.codeUnits);
    await _flush();
    expect(_typed(firstEvents), 'a');

    await first.restore();
    final secondEvents = <TuiEvent>[];
    final second = WindowsTerminalDriver(
      stdinOverride: stdinStream,
      stdoutOverride: _NullStdout(),
      stdinIsSharedOverride: true,
    );
    final secondSub = second.events.listen(secondEvents.add);
    await second.enter(TerminalMode.interactive); // must NOT throw

    stdinStream.push('b'.codeUnits);
    await _flush();
    expect(_typed(secondEvents), 'b', reason: 'reused stdin feeds session two');
    expect(_typed(firstEvents), 'a');

    await second.restore();
    await _flush();
    await firstSub.cancel();
    await secondSub.cancel();
    await stdinStream.close();
  });

  test(
    'posix: two real-stdin sessions do not crash and the process still exits',
    () async {
      final fixture =
          '${Directory.current.path}/test/fixtures/second_session_stdin_fixture.dart';
      final process = await Process.start(
        Platform.resolvedExecutable,
        <String>['run', fixture],
        workingDirectory: Directory.current.path,
      );
      // Keep the child's stdin OPEN (never write/close, never EOF) so a merely
      // paused stdin subscription would keep its event loop alive and hang —
      // exiting proves the retained subscription's idle-cancel released it.
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
        reason: 'process hung (a paused stdin subscription was never released)',
      );
      expect(exitCode, 0, reason: 'stdout:\n$out\nstderr:\n$err');
      expect(out.toString(), contains('ALL-SESSIONS-DONE'));
      expect(err.toString(), isNot(contains('already been listened')));
    },
    timeout: const Timeout(Duration(seconds: 90)),
    // PosixTerminalDriver is POSIX-only.
    skip: Platform.isWindows ? 'POSIX driver only' : null,
  );
}
