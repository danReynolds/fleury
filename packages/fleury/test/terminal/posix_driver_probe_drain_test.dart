// Launch-audit follow-up: a startup probe reply that arrives AFTER the probe
// window (a slow SSH link, so the ~150ms wait timed out) must NOT be parsed as
// keystrokes — otherwise a Kitty/DA reply types garbage (`Gi=31,...`, or the
// `?…c` of a Device-Attributes reply) into the focused widget on first boot.
//
// The fix diverts stdin during a bounded post-timeout grace until the DA
// terminator lands (then replays real input after it) or the grace expires.
// This drives that state machine directly through @visibleForTesting seams
// over a non-TTY fake stdin (no real terminal / job control needed): the
// listener's probe/drain/parse routing is what's under test.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _RecordingStdout implements Stdout {
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

class _FakeStdin implements Stdin {
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

// ESC[?62;c — a Device-Attributes reply (the probe terminator).
const _daReply = [0x1B, 0x5B, 0x3F, 0x36, 0x32, 0x63];

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('PosixTerminalDriver late-probe-reply drain', () {
    late _FakeStdin input;
    late PosixTerminalDriver driver;
    late List<TuiEvent> events;
    late StreamSubscription<TuiEvent> sub;
    final savedGrace = PosixTerminalDriver.lateProbeGrace;

    setUp(() async {
      PosixTerminalDriver.lateProbeGrace = const Duration(milliseconds: 60);
      input = _FakeStdin();
      driver = PosixTerminalDriver(
        stdinOverride: input,
        stdoutOverride: _RecordingStdout(),
      );
      await driver.enter(TerminalMode.interactive);
      events = <TuiEvent>[];
      sub = driver.events.listen(events.add);
    });

    tearDown(() async {
      PosixTerminalDriver.lateProbeGrace = savedGrace;
      await sub.cancel();
      await driver.restore();
      await input.close();
    });

    test('a late DA reply is swallowed; real input after it replays', () async {
      driver.debugBeginLateProbeDrain();
      expect(driver.debugDrainingLateProbe, isTrue);

      // The terminal's late reply arrives, immediately followed by a keystroke.
      input.push([..._daReply, 0x68, 0x69]); // DA + 'h' 'i'
      await _pump();

      expect(
        driver.debugDrainingLateProbe,
        isFalse,
        reason: 'the DA terminator ends the drain',
      );
      // The DA bytes produced NO events; only the trailing 'hi' reached the app.
      expect(
        events.whereType<TextInputEvent>().map((e) => e.text).join(),
        'hi',
      );
      expect(
        events.whereType<KeyEvent>(),
        isEmpty,
        reason: 'no keystrokes synthesized from the DA reply',
      );

      // Drain over: subsequent input flows normally.
      input.push([0x7A]); // 'z'
      await _pump();
      expect(
        events.whereType<TextInputEvent>().map((e) => e.text).join(),
        'hiz',
      );
    });

    test('grace expiry discards the buffer, then input flows', () async {
      driver.debugBeginLateProbeDrain();
      // A reply with no DA terminator (a partial / non-answering terminal).
      input.push([0x1B, 0x5B, 0x3F]); // truncated CSI, never terminated
      await _pump();
      expect(driver.debugDrainingLateProbe, isTrue, reason: 'still waiting');

      // Wait out the grace.
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(
        driver.debugDrainingLateProbe,
        isFalse,
        reason: 'the grace elapsed with no DA — give up',
      );

      // The stale partial was discarded (not parsed); fresh input flows.
      input.push([0x6F, 0x6B]); // 'o' 'k'
      await _pump();
      expect(
        events.whereType<TextInputEvent>().map((e) => e.text).join(),
        'ok',
        reason: 'no garbage from the discarded partial reply',
      );
    });
  });
}
