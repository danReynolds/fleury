import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

final class _RecordingStdout implements Stdout {
  @override
  bool get hasTerminal => false;
  @override
  void write(Object? object) {}
  @override
  Future<void> flush() async {}
  @override
  int get terminalColumns => throw const StdoutException('not a terminal');
  @override
  int get terminalLines => throw const StdoutException('not a terminal');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeStdin implements Stdin {
  final _controller = StreamController<List<int>>();

  void push(List<int> bytes) => _controller.add(bytes);
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

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test(
    'an abandoned bracketed paste is finalized after the idle timeout',
    () async {
      final savedPaste = PosixTerminalDriver.pasteIdleTimeout;
      PosixTerminalDriver.pasteIdleTimeout = const Duration(milliseconds: 40);
      final input = _FakeStdin();
      final driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: _RecordingStdout(),
      );
      await driver.enter(TerminalMode.interactive);
      final events = <TuiEvent>[];
      final subscription = driver.events.listen(events.add);
      try {
        input.push([0x1B, 0x5B, ...'200~'.codeUnits, ...'hi'.codeUnits]);
        await _pump();
        expect(events, isEmpty, reason: 'paste still open');

        await Future<void>.delayed(const Duration(milliseconds: 70));
        await _pump();
        expect(events.whereType<PasteEvent>().map((event) => event.text), [
          'hi',
        ]);

        input.push([0x03]);
        await _pump();
        expect(
          events.whereType<KeyEvent>().where(
            (event) => event.hasCtrl && event.code.character == 'c',
          ),
          isNotEmpty,
          reason: 'keyboard control is restored after the abandoned paste',
        );
      } finally {
        PosixTerminalDriver.pasteIdleTimeout = savedPaste;
        await subscription.cancel();
        await driver.restore();
        await input.close();
      }
    },
  );
}
