// A mouse report the terminal sends before it processes the mouse disable
// still arrives afterwards. If the driver has already stopped reading by
// then, the report stays in the tty queue for the next reader: the shell
// after an exit or a Ctrl+Z, the editor after a handoff, which shows it as
// `^[[<35;18;5M` garbage. The driver disables input reports while it still
// reads, and keeps reading until a Device Attributes reply shows the terminal
// processed the disable.
import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// Plays the terminal on the other end of the tty, one [latency] away. It
/// answers every Device Attributes query in order and has mouse reports in
/// flight when the mouse disable reaches it.
final class _Tty {
  static const latency = Duration(milliseconds: 5);
  static const report = '\x1B[<35;18;5M';

  final _input = StreamController<List<int>>();
  final StringBuffer written = StringBuffer();

  /// What the terminal sent while nothing in this driver was reading it:
  /// what the shell, or a handed-off child, reads next.
  final leftForNextReader = <String>[];

  /// Set by the suspend test's self-stop: a stopped process reads nothing.
  bool stopped = false;
  bool _reportsInFlight = true;

  late final stdin = _TtyStdin(this);
  late final stdout = _TtyStdout(this);

  void _arrive(String bytes) {
    if (stopped || !_input.hasListener || _input.isPaused) {
      leftForNextReader.add(bytes);
    } else {
      _input.add(bytes.codeUnits);
    }
  }

  void _onWrite(String bytes) {
    written.write(bytes);
    // In the terminal's order: what it sent before processing this write
    // arrives first, then its answers to the queries in it.
    if (_reportsInFlight && bytes.contains('\x1B[?1003l')) {
      _reportsInFlight = false;
      Timer(latency, () => _arrive('$report$report'));
    }
    if (bytes.contains('\x1B[?1003h')) _reportsInFlight = true;
    for (final _ in '\x1B[c'.allMatches(bytes)) {
      Timer(latency, () => _arrive('\x1B[?62;22c'));
    }
  }

  Future<void> close() => _input.close();
}

final class _TtyStdout implements Stdout {
  _TtyStdout(this._tty);

  final _Tty _tty;

  @override
  bool get hasTerminal => true;

  @override
  void write(Object? object) => _tty._onWrite('$object');

  @override
  Future<void> flush() async {}

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TtyStdin implements Stdin {
  _TtyStdin(this._tty);

  final _Tty _tty;

  @override
  bool get hasTerminal => true;

  @override
  bool lineMode = true;

  @override
  bool echoMode = true;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _tty._input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Long enough for every reply still in flight to land.
Future<void> _settle() => Future<void>.delayed(_Tty.latency * 4);

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  late _Tty tty;

  setUp(() => tty = _Tty());
  tearDown(() => tty.close());

  test('reports in flight at exit are read, not left for the shell', () async {
    final driver = PosixTerminalDriver(
      stdinOverride: tty.stdin,
      stdoutOverride: tty.stdout,
    );
    await driver.enter(TerminalMode.interactive);

    await driver.restore();
    await _settle();

    expect(tty.leftForNextReader, isEmpty);
    expect(
      _count(tty.written.toString(), '\x1B[?1003l'),
      1,
      reason: 'the input modes are released once',
    );
    expect(tty.written.toString(), endsWith('\x1B[?1049l'));
  });

  test(
    'reports in flight at Ctrl+Z are read before the process stops',
    () async {
      final driver = PosixTerminalDriver(
        stdinOverride: tty.stdin,
        stdoutOverride: tty.stdout,
        selfStopOverride: () => tty.stopped = true,
      );
      await driver.enter(TerminalMode.interactive);

      await driver.debugSuspend();
      await _settle();

      expect(driver.debugSuspended, isTrue);
      expect(tty.leftForNextReader, isEmpty);

      tty.stopped = false;
      driver.debugResume();
      await driver.restore();
      await _settle();
      expect(tty.leftForNextReader, isEmpty);
    },
  );

  test(
    'reports in flight at a handoff are read, not left for the child',
    () async {
      final driver = PosixTerminalDriver(
        stdinOverride: tty.stdin,
        stdoutOverride: tty.stdout,
      );
      await driver.enter(TerminalMode.interactive);

      late List<String> childRead;
      await driver.runWithTerminalHandoff(() async {
        await _settle();
        childRead = List.of(tty.leftForNextReader);
      });

      expect(childRead, isEmpty);
      await driver.restore();
    },
  );
}
