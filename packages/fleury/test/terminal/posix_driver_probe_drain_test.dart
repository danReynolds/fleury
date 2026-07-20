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

// ESC[1;2R — a Cursor-Position report (row 1, col 2), which the ambiguous-width
// probe elicits. Fed to the input parser it decodes as CSI final 'R' with
// modifier param 2, i.e. KeyEvent(shift + f3): the phantom key this guards.
const _cprReply = [0x1B, 0x5B, 0x31, 0x3B, 0x32, 0x52];

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

    test(
      'a DA reply split across the timeout reassembles and is swallowed',
      () async {
        // The real failure the fix targets: the reply STARTED arriving before
        // the probe timed out (partial `ESC [ ? 6 2` buffered), and its final
        // `c` — plus a trailing keystroke — arrive after. The drain must
        // reassemble across the boundary, swallow the whole reply, and replay
        // only the real input.
        driver.debugBeginLateProbeDrain([
          0x1B,
          0x5B,
          0x3F,
          0x36,
          0x32,
        ]); // no 'c'
        expect(driver.debugDrainingLateProbe, isTrue);

        input.push([0x63, 0x6F, 0x6B]); // 'c' (terminator) + 'o' 'k'
        await _pump();

        expect(driver.debugDrainingLateProbe, isFalse);
        expect(
          events.whereType<TextInputEvent>().map((e) => e.text).join(),
          'ok',
          reason: 'the DA reassembled across the boundary; only "ok" is input',
        );
        expect(events.whereType<KeyEvent>(), isEmpty);
      },
    );

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

    // Finding 1 (P1): a later probe's reply must not be misattributed to an
    // earlier probe's Device-Attributes reply. On a slow link the image probe's
    // DA lands while the width probe is still outstanding; the completion
    // sentinel must wait for the LAST owed DA, or the width probe's own
    // Cursor-Position reply leaks to the parser as a phantom Shift+F3 at startup.
    test('a straggling second-probe reply is not read as a phantom key', () async {
      // Two DA replies are owed (image + width). The image probe's DA is already
      // in the buffer, but the width probe's reply is still in flight.
      driver.debugBeginLateProbeDrain([..._daReply], 2);
      expect(
        driver.debugDrainingLateProbe,
        isTrue,
        reason: 'the second probe’s DA is still owed — keep draining',
      );

      // The width probe's reply finally lands: its Cursor-Position report, then
      // its own DA terminator.
      input.push([..._cprReply, ..._daReply]);
      await _pump();

      expect(driver.debugDrainingLateProbe, isFalse);
      expect(driver.debugProbeRepliesPending, 0);
      expect(
        events,
        isEmpty,
        reason: 'no phantom Shift+F3 from the late Cursor-Position reply',
      );
    });

    test('a new probe exchange keeps a prior in-flight reply and owes a DA', () {
      // The image probe timed out with a partial reply buffered → drain armed.
      driver.debugBeginLateProbeDrain([0x1B, 0x5B, 0x3F], 1);
      expect(driver.debugProbeRepliesPending, 1);

      // The width probe starts before the image reply completes. It must not
      // clear the buffer or cancel the drain (either would let the reply leak);
      // it simply owes one more DA.
      driver.debugBeginProbeExchange();
      expect(
        driver.debugProbeRepliesPending,
        2,
        reason: 'a second DA reply is now owed',
      );
      expect(
        driver.debugProbeBuffer,
        [0x1B, 0x5B, 0x3F],
        reason: 'the first probe’s partial reply is kept, not cleared',
      );
    });

    // Finding 3 (P2): give-up must replay real keystrokes, not discard them —
    // otherwise a scripted/CI PTY that never answers DA loses everything typed
    // during an output stall, including the Ctrl+C escape hatch.
    test(
      'give-up replays buffered keystrokes instead of discarding them',
      () async {
        driver.debugBeginLateProbeDrain(); // one probe timed out, draining
        // The terminal never answers DA; the user's keystrokes are what arrive.
        input.push([0x71, 0x03]); // 'q' then Ctrl+C
        await _pump();
        expect(driver.debugDrainingLateProbe, isTrue, reason: 'within grace');

        await Future<void>.delayed(const Duration(milliseconds: 90));
        await _pump();
        expect(driver.debugDrainingLateProbe, isFalse);

        expect(
          events.whereType<TextInputEvent>().map((e) => e.text).join(),
          'q',
          reason: 'plain keystrokes typed during the stall survive give-up',
        );
        expect(
          events.whereType<KeyEvent>().where(
            (e) => e.hasCtrl && e.code.character == 'c',
          ),
          isNotEmpty,
          reason: 'the Ctrl+C escape hatch must survive give-up',
        );
      },
    );

    test(
      'give-up strips a straggling reply but replays the trailing keys',
      () async {
        driver.debugBeginLateProbeDrain();
        // A late Cursor-Position reply the terminal emitted, then a real 'x'.
        input.push([..._cprReply, 0x78]);
        await _pump();

        await Future<void>.delayed(const Duration(milliseconds: 90));
        await _pump();
        expect(driver.debugDrainingLateProbe, isFalse);

        expect(
          events.whereType<KeyEvent>(),
          isEmpty,
          reason:
              'the straggling Cursor-Position reply is stripped, not decoded',
        );
        expect(
          events.whereType<TextInputEvent>().map((e) => e.text).join(),
          'x',
          reason: 'real input trailing the reply is still replayed',
        );
      },
    );

    // Finding 2 (P2): an abandoned bracketed paste (ESC[200~ with no ESC[201~)
    // must not capture all later input forever; a generous idle deadline
    // finalizes it and restores keyboard control.
    test(
      'an abandoned bracketed paste is finalized after the idle timeout',
      () async {
        final savedPaste = PosixTerminalDriver.pasteIdleTimeout;
        PosixTerminalDriver.pasteIdleTimeout = const Duration(milliseconds: 40);
        try {
          // Paste opens but the ESC[201~ terminator never arrives.
          input.push([0x1B, 0x5B, ...'200~'.codeUnits, ...'hi'.codeUnits]);
          await _pump();
          expect(
            events,
            isEmpty,
            reason: 'paste still open — nothing emitted yet',
          );

          await Future<void>.delayed(const Duration(milliseconds: 70));
          await _pump();
          expect(
            events.whereType<PasteEvent>().map((e) => e.text),
            ['hi'],
            reason:
                'the abandoned paste is force-finalized on the idle deadline',
          );

          // Keyboard control is restored: Ctrl+C now reaches the app.
          input.push([0x03]);
          await _pump();
          expect(
            events.whereType<KeyEvent>().where(
              (e) => e.hasCtrl && e.code.character == 'c',
            ),
            isNotEmpty,
            reason: 'input is no longer swallowed by the stuck paste',
          );
        } finally {
          PosixTerminalDriver.pasteIdleTimeout = savedPaste;
        }
      },
    );
  });
}
