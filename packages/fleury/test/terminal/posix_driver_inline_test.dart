import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/posix_driver.dart'
    show PosixTerminalModeController;
import 'package:test/test.dart';

class _Input implements Stdin {
  final controller = StreamController<List<int>>();
  void send(String text) => controller.add(text.codeUnits);
  @override
  bool get hasTerminal => true;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Output implements Stdout {
  final bytes = StringBuffer();
  late void Function(String) onWrite;
  @override
  bool get hasTerminal => true;
  @override
  int get terminalColumns {
    if (!reportsSize) throw const StdoutException('size unavailable');
    return _columns;
  }

  set terminalColumns(int value) => _columns = value;
  int _columns = 80;
  bool reportsSize = true;
  @override
  int terminalLines = 24;
  @override
  void write(Object? object) {
    bytes.write(object);
    onWrite('$object');
  }

  @override
  Future<void> flush() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Modes implements PosixTerminalModeController {
  bool raw = false;
  @override
  bool enableRawMode() {
    raw = true;
    return true;
  }

  @override
  bool restoreMode() {
    raw = false;
    return true;
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// Waits until [condition] holds, or gives up after [timeout] and lets the
/// caller's expectations report what did not happen.
Future<void> _eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final clock = Stopwatch()..start();
  while (!condition() && clock.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _Input input;
  late _Output output;
  late _Modes modes;
  late PosixTerminalDriver driver;
  late List<TuiEvent> events;
  late List<Object> errors;
  late Map<ProcessSignal, void Function(ProcessSignal)> signals;
  late CellOffset cursor;
  late bool answerCursor;
  late bool holdCursor;
  late Duration? cursorDelay;
  late int cursorQueries;
  const mode = TerminalMode.inline(
    rows: 4,
    keyboardProtocol: KeyboardProtocolMode.legacy,
    mouse: true,
  );

  setUp(() {
    input = _Input();
    output = _Output();
    modes = _Modes();
    events = [];
    errors = [];
    signals = {};
    cursor = const CellOffset(0, 7);
    answerCursor = true;
    holdCursor = false;
    cursorDelay = null;
    cursorQueries = 0;
    output.onWrite = (bytes) {
      final cpr = bytes.contains('\x1B[6n');
      if (cpr) cursorQueries++;
      if (cpr && holdCursor) return;
      final delay = cursorDelay;
      if (cpr && delay != null) {
        // A slow link or a busy terminal: the whole reply, as the terminal
        // computed it when the query arrived, lands later.
        final reply = answerCursor
            ? '\x1B[${cursor.row + 1};${cursor.col + 1}R\x1B[?1;2c'
            : '\x1B[?1;2c';
        Timer(delay, () {
          if (!input.controller.isClosed) input.send(reply);
        });
        return;
      }
      if (cpr && answerCursor) {
        input.send('\x1B[${cursor.row + 1};${cursor.col + 1}R');
      }
      if (bytes.contains('\x1B[c')) input.send('\x1B[?1;2c');
    };
    driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: output,
      terminalModeController: modes,
      selfStopOverride: () => true,
      signalWatcherOverride: (signal, callback) {
        signals[signal] = callback;
        return null;
      },
    );
    final sub = driver.events.listen(
      events.add,
      onError: (Object e) => errors.add(e),
    );
    addTearDown(() async {
      await driver.restore();
      await sub.cancel();
      await input.controller.close();
    });
  });

  test(
    'entry reserves a bounded main-buffer region and uses glyph images',
    () async {
      final profile = await driver.enter(mode);
      expect(driver.size, const CellSize(80, 4));
      expect(driver.renderTarget.top, 7);
      expect(
        (profile.presentation as AnsiTerminalPresentation)
            .capabilities
            .imageProtocol,
        ImageProtocol.halfBlock,
      );
      expect(output.bytes.toString(), contains('\x1B[?7l'));
      expect(output.bytes.toString(), isNot(contains('1049')));
      expect(output.bytes.toString(), isNot(contains('\x1B[2J')));
      expect(output.bytes.toString(), isNot(contains('\x1B_G')));
      expect(cursorQueries, 1);
      await driver.restore();
      expect(modes.raw, isFalse);
      expect(output.bytes.toString(), contains('\x1B[?7h'));
      expect(output.bytes.toString(), contains('\x1B[8;1H'));
    },
  );

  test(
    'mouse reports use local rows and preserve an outside release',
    () async {
      await driver.enter(mode);
      input.send('\x1B[<0;3;9M\x1B[<0;3;2m');
      await _settle();
      final mouse = events.whereType<MouseEvent>().toList();
      expect(mouse[0].row, 1);
      expect(mouse[0].col, 2);
      expect(mouse[1].row, -6);
      expect(mouse[1].kind, MouseEventKind.up);
    },
  );

  test('concurrent height changes coalesce before the final repaint', () async {
    await driver.enter(mode);
    events.clear();
    await Future.wait([driver.resizeInline(2), driver.resizeInline(6)]);
    await _settle();
    expect(driver.size.rows, 6);
    expect(cursorQueries, 1, reason: 'known geometry needs no new query');
    expect(events.whereType<ResizeEvent>().length, 1);
  });

  for (final change in [
    'same height',
    'cancelled height change',
    'window bounce',
  ]) {
    test('$change repaints a frame suppressed during the resize', () async {
      await driver.enter(mode);
      events.clear();
      output.bytes.clear();
      final pending = <Future<void>>[];
      switch (change) {
        case 'same height':
          pending.add(driver.resizeInline(4));
        case 'cancelled height change':
          pending.addAll([driver.resizeInline(6), driver.resizeInline(4)]);
        case 'window bounce':
          output.terminalColumns = 60;
      }
      // The renderer can commit a frame while the driver's resize gate is up.
      // Even if geometry ends up unchanged, those discarded bytes need replay.
      driver.write('UPDATED-FRAME');
      output.terminalColumns = 80;
      expect(output.bytes.toString(), isEmpty);
      await Future.wait(pending);
      await _settle();
      expect(driver.size, const CellSize(80, 4));
      expect(events.whereType<ResizeEvent>().length, 1);
      expect(cursorQueries, 1, reason: 'unchanged geometry needs no new query');
      driver.write('REPAINTED-FRAME');
      expect(output.bytes.toString(), contains('REPAINTED-FRAME'));
    });
  }

  test(
    'unchanged height without a suppressed frame needs no repaint',
    () async {
      await driver.enter(mode);
      events.clear();
      await driver.resizeInline(4);
      await _settle();
      expect(events.whereType<ResizeEvent>(), isEmpty);
    },
  );

  test('physical resize gates writes and reanchors using the caret', () async {
    await driver.enter(mode);
    driver.recordInlineCursor(const CellOffset(3, 1));
    output.terminalLines = 10;
    cursor = const CellOffset(3, 7);
    holdCursor = true;
    signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
    await _settle();
    driver.write('MUST-NOT-PAINT');
    expect(output.bytes.toString(), isNot(contains('MUST-NOT-PAINT')));
    holdCursor = false;
    input.send('\x1B[8;4R\x1B[?1;2c');
    await _settle();
    expect(driver.renderTarget.top, 6);
    expect(driver.size, const CellSize(80, 4));
    expect(errors, isEmpty);
  });

  test(
    'handoff clears before child output, then acquires a fresh anchor',
    () async {
      await driver.enter(mode);
      output.bytes.clear();
      await driver.runWithTerminalHandoff(() {
        expect(modes.raw, isFalse);
        expect(output.bytes.toString(), contains('\x1B[8;1H'));
        driver.write('MUST-NOT-PAINT');
        output.write('CHILD\r\n');
        cursor = const CellOffset(0, 15);
      });
      expect(modes.raw, isTrue);
      expect(driver.renderTarget.top, 15);
      expect(output.bytes.toString(), isNot(contains('MUST-NOT-PAINT')));
      expect(cursorQueries, 2);
    },
  );

  test('suspend clears and resume reanchors before accepting frames', () async {
    await driver.enter(mode);
    await driver.debugSuspend();
    expect(modes.raw, isFalse);
    cursor = const CellOffset(0, 12);
    await driver.debugResume();
    await _settle();
    expect(driver.debugSuspended, isFalse);
    expect(driver.renderTarget.top, 12);
    expect(modes.raw, isTrue);
  });

  test(
    'height requests during handoff apply after the child releases the tty',
    () async {
      await driver.enter(mode);
      await driver.runWithTerminalHandoff(() async {
        final before = output.bytes.toString();
        await driver.resizeInline(9);
        expect(
          output.bytes.toString(),
          before,
          reason: 'child still owns output',
        );
        expect(driver.size.rows, 4);
      });
      expect(driver.size.rows, 9);
    },
  );

  test(
    'a second resize during cursor reporting retries at the new size',
    () async {
      await driver.enter(mode);
      output.bytes.clear();
      holdCursor = true;
      output.terminalColumns = 60;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _settle();
      output.terminalColumns = 40;
      cursor = const CellOffset(0, 10);
      holdCursor = false;
      // A stale report can be outside even the queried dimensions. Discard it
      // before validating bounds, then validate the fresh stable-size reply.
      input.send('\x1B[8;70R\x1B[?1;2c');
      await _settle();
      expect(cursorQueries, 3, reason: 'entry, stale report, fresh report');
      expect(driver.size, const CellSize(40, 4));
      expect(
        driver.renderTarget.top,
        7,
        reason: 'fresh cursor minus resting row',
      );
      expect(errors, isEmpty);
    },
  );

  for (final (label, invalid) in [
    ('row', const CellOffset(0, 24)),
    ('column', const CellOffset(80, 7)),
  ]) {
    test('out-of-bounds entry $label restores without allocating', () async {
      cursor = invalid;
      await expectLater(driver.enter(mode), throwsStateError);
      expect(driver.isActive, isFalse);
      expect(modes.raw, isFalse);
      expect(output.bytes.toString(), contains('\x1B[?7h'));
      expect(output.bytes.toString(), isNot(contains('\n')));
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
    });
  }

  for (final (label, invalid) in [
    ('row', const CellOffset(0, 24)),
    ('column', const CellOffset(60, 7)),
  ]) {
    test('out-of-bounds resize $label cannot authorize a clear', () async {
      await driver.enter(mode);
      output.bytes.clear();
      output.terminalColumns = 60;
      cursor = invalid;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _settle();
      expect(errors.single, isA<StateError>());
      expect(output.bytes.toString(), isNot(contains('\n')));
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
      await driver.restore();
      expect(modes.raw, isFalse);
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
    });
  }

  test('last-column last-row cursor is valid ownership evidence', () async {
    cursor = const CellOffset(79, 23);
    await driver.enter(mode);
    expect(driver.isActive, isTrue);
    expect(driver.size, const CellSize(80, 4));
    expect(driver.renderTarget.top, 20);
    expect(errors, isEmpty);
  });

  test(
    'unreportable size fails before painting and still restores modes',
    () async {
      output.reportsSize = false;
      await expectLater(driver.enter(mode), throwsStateError);
      expect(modes.raw, isFalse);
      expect(output.bytes.toString(), contains('\x1B[?7h'));
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
      expect(output.bytes.toString(), isNot(contains('1049')));
    },
  );

  test('zero-sized resize fails without painting at an assumed size', () async {
    await driver.enter(mode);
    output.bytes.clear();
    output.terminalLines = 0;
    signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
    await _settle();
    expect(errors.single, isA<StateError>());
    expect(output.bytes.toString(), isEmpty);
    await driver.restore();
    expect(modes.raw, isFalse);
    expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
  });

  test(
    'missing cursor report fails with restored modes and no guessed clear',
    () async {
      answerCursor = false;
      await expectLater(driver.enter(mode), throwsStateError);
      expect(modes.raw, isFalse);
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
      expect(output.bytes.toString(), isNot(contains('1049')));
    },
  );

  test(
    'restore observes an unhandled resize before clearing the region',
    () async {
      await driver.enter(mode);
      driver.recordInlineCursor(const CellOffset(3, 1));
      output.bytes.clear();
      output.terminalColumns = 60;
      output.terminalLines = 10;
      cursor = const CellOffset(3, 7);
      // Exit arrives before SIGWINCH / a new frame. The old top is no longer
      // evidence; a fresh report places the surviving region at row 6.
      await driver.restore();
      expect(cursorQueries, 2);
      final bytes = output.bytes.toString();
      expect(bytes, contains('\x1B[7;1H\x1B[2K'));
      expect(bytes, contains('\x1B[10;1H\x1B[2K'));
      expect(bytes, isNot(contains('\x1B[6;1H\x1B[2K')));
      expect(RegExp(r'\x1b\[2K').allMatches(bytes).length, 4);
      expect(
        bytes,
        isNot(contains('\n')),
        reason: 'cleanup must not allocate another region',
      );
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    },
  );

  test(
    'shutdown retries a cursor report invalidated by another resize',
    () async {
      await driver.enter(mode);
      output.bytes.clear();
      driver.recordInlineCursor(const CellOffset(0, 1));
      output.terminalColumns = 60;
      holdCursor = true;
      final restoring = driver.restore();
      await _settle();
      expect(cursorQueries, 2);
      output.terminalColumns = 40;
      cursor = const CellOffset(0, 9);
      holdCursor = false;
      input.send('\x1B[8;1R\x1B[?1;2c');
      await restoring;
      expect(cursorQueries, 3);
      expect(output.bytes.toString(), contains('\x1B[9;1H\x1B[2K'));
      expect(output.bytes.toString(), isNot(contains('\x1B[7;1H\x1B[2K')));
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    },
  );

  test(
    'shutdown after a pending resize uses a fresh report, not the stale reply',
    () async {
      await driver.enter(mode);
      driver.recordInlineCursor(const CellOffset(0, 1));
      output.terminalColumns = 60;
      holdCursor = true;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _settle();
      final restoring = driver.restore();
      await _settle();
      output.bytes.clear();
      cursor = const CellOffset(0, 11);
      holdCursor = false;
      // The window moves on before the pending report lands, so the report
      // describes a size the terminal no longer has.
      output.terminalColumns = 50;
      input.send('\x1B[8;1R\x1B[?1;2c');
      await restoring;
      expect(cursorQueries, 3);
      expect(output.bytes.toString(), contains('\x1B[11;1H\x1B[2K'));
      expect(output.bytes.toString(), isNot(contains('\x1B[7;1H\x1B[2K')));
      expect(output.bytes.toString(), isNot(contains('\n')));
      expect(modes.raw, isFalse);
    },
  );

  test(
    'shutdown without a cursor reply is bounded and does not guess rows',
    () async {
      await driver.enter(mode);
      output.bytes.clear();
      output.terminalColumns = 60;
      answerCursor = false;
      final clock = Stopwatch()..start();
      await driver.restore().timeout(const Duration(seconds: 3));
      expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
      expect(cursorQueries, 2);
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    },
  );

  test(
    'continuous resizing cannot keep shutdown querying indefinitely',
    () async {
      await driver.enter(mode);
      output.bytes.clear();
      output.terminalColumns = 60;
      output.onWrite = (bytes) {
        if (!bytes.contains('\x1B[6n')) return;
        cursorQueries++;
        Timer(const Duration(milliseconds: 10), () {
          output.terminalColumns = output.terminalColumns == 60 ? 40 : 60;
          input.send('\x1B[8;1R\x1B[?1;2c');
        });
      };
      await driver.restore().timeout(const Duration(seconds: 3));
      expect(cursorQueries, greaterThan(2));
      expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    },
  );

  test(
    'restore during a pending resize prevents a late region acquisition',
    () async {
      await driver.enter(mode);
      holdCursor = true;
      output.terminalColumns = 60;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _settle();
      // Bounded by the drain the pending report gets and restore's own
      // cleanup query, not by how long a live session would go on waiting.
      final clock = Stopwatch()..start();
      await driver.restore().timeout(const Duration(seconds: 5));
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      final restored = output.bytes.toString();
      await _settle();
      expect(output.bytes.toString(), restored);
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    },
  );

  group('a slow cursor report in a live session', () {
    test('arriving 1.5 s after a resize keeps the session and settles on the '
        'new size', () async {
      await driver.enter(mode);
      driver.recordInlineCursor(const CellOffset(3, 1));
      output.bytes.clear();
      events.clear();
      // A narrower window, answered as a congested SSH link or a busy
      // terminal answers: correctly, but late.
      output.terminalColumns = 60;
      cursor = const CellOffset(3, 7);
      cursorDelay = const Duration(milliseconds: 1500);
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      // Past the old fixed 1 s deadline: still waiting, painting gated.
      expect(errors, isEmpty);
      expect(driver.isActive, isTrue);
      driver.write('MUST-NOT-PAINT');
      expect(output.bytes.toString(), isNot(contains('MUST-NOT-PAINT')));
      await _eventually(() => driver.size == const CellSize(60, 4));
      await _settle();
      expect(errors, isEmpty);
      expect(driver.size, const CellSize(60, 4));
      expect(driver.renderTarget.top, 6, reason: 'late cursor minus caret');
      expect(
        cursorQueries,
        2,
        reason:
            'entry, then one resize query left in flight until it was '
            'answered',
      );
      expect(
        events.whereType<KeyEvent>(),
        isEmpty,
        reason:
            'the late report answered its own query; it never became '
            'an F3 press',
      );
      expect(events.whereType<ResizeEvent>(), hasLength(1));
      driver.write('REPAINTED-FRAME');
      expect(output.bytes.toString(), contains('REPAINTED-FRAME'));
    });

    test('a window drag answered slowly settles on the latest size, one query '
        'at a time', () async {
      await driver.enter(mode);
      output.bytes.clear();
      events.clear();
      holdCursor = true;
      output.terminalColumns = 60;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _eventually(() => cursorQueries == 2);
      // The drag goes on while that report is still on its way.
      output.terminalColumns = 40;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(errors, isEmpty, reason: 'past the old 1 s deadline');
      expect(
        cursorQueries,
        2,
        reason: 'a second query cannot be told from the first by its reply',
      );
      // The report lands at last, for the 60-column window the drag has
      // left: stale, so the driver asks again at 40 columns.
      holdCursor = false;
      cursor = const CellOffset(0, 10);
      input.send('\x1B[8;1R\x1B[?1;2c');
      await _eventually(() => driver.size == const CellSize(40, 4));
      await _settle();
      expect(errors, isEmpty);
      expect(cursorQueries, 3);
      expect(driver.renderTarget.top, 7, reason: 'cursor minus resting row');
      final bytes = output.bytes.toString();
      expect(
        RegExp(r'\x1b\[2K').allMatches(bytes),
        hasLength(4),
        reason: 'one reallocation; the stale report never placed a region',
      );
      expect(bytes, contains('\x1B[8;1H\x1B[2K'));
    });

    test('a drag longer than the report budget, answered throughout, is '
        'never cut short', () async {
      PosixTerminalDriver.inlineCursorReportBudget = const Duration(seconds: 1);
      addTearDown(
        () => PosixTerminalDriver.inlineCursorReportBudget = const Duration(
          seconds: 10,
        ),
      );
      await driver.enter(mode);
      holdCursor = true;
      var columns = 80;
      void drag() {
        output.terminalColumns = columns -= 4;
        signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      }

      drag();
      for (var step = 0; step < 6; step++) {
        await _eventually(() => cursorQueries == 2 + step);
        // Each report takes 300 ms, and the window has moved on by the time
        // it lands: 1.8 s of drag, never 1 s without a report.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        drag();
        input.send('\x1B[8;1R\x1B[?1;2c');
      }
      await _eventually(() => cursorQueries == 8);
      input.send('\x1B[9;1R\x1B[?1;2c');
      await _eventually(() => driver.size == CellSize(columns, 4));
      await _settle();
      expect(errors, isEmpty);
      expect(driver.size, CellSize(columns, 4));
    });

    test('a reply without a cursor report is asked again, paced from the '
        'measured round trip and doubling', () async {
      await driver.enter(mode);
      final sent = <Duration>[];
      final clock = Stopwatch()..start();
      final terminal = output.onWrite;
      output.onWrite = (bytes) {
        if (bytes.contains('\x1B[6n')) {
          sent.add(clock.elapsed);
          // The first three resize queries get the sentinel alone.
          answerCursor = sent.length > 3;
        }
        terminal(bytes);
      };
      output.terminalColumns = 60;
      cursor = const CellOffset(0, 9);
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _eventually(
        () => driver.size == const CellSize(60, 4),
        timeout: const Duration(seconds: 5),
      );
      await _settle();
      expect(errors, isEmpty);
      expect(sent, hasLength(4));
      final gaps = [
        for (var i = 1; i < sent.length; i++) sent[i] - sent[i - 1],
      ];
      expect(
        gaps[0],
        greaterThanOrEqualTo(const Duration(milliseconds: 150)),
        reason: 'the round-trip deadline, never a tight loop',
      );
      expect(gaps[1], greaterThanOrEqualTo(const Duration(milliseconds: 300)));
      expect(gaps[2], greaterThanOrEqualTo(const Duration(milliseconds: 600)));
      expect(driver.renderTarget.top, 6);
    });

    test('a modified F3 typed while the report is pending is a key, not the '
        'report', () async {
      await driver.enter(mode);
      driver.recordInlineCursor(const CellOffset(3, 1));
      output.bytes.clear();
      events.clear();
      output.terminalColumns = 60;
      cursor = const CellOffset(3, 7);
      cursorDelay = const Duration(milliseconds: 800);
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Shift+F3 in a legacy keyboard mode: the shape of a cursor report.
      input.send('\x1B[1;2R');
      await _eventually(() => driver.size == const CellSize(60, 4));
      await _settle();
      expect(errors, isEmpty);
      expect(driver.renderTarget.top, 6, reason: 'the terminal\'s report');
      expect(
        output.bytes.toString(),
        isNot(contains('\x1B[1;1H\x1B[2K')),
        reason: 'the key never placed a region at the top row',
      );
      final keys = events.whereType<KeyEvent>().toList();
      expect(keys, hasLength(1));
      expect(keys.single.code, KeyCode.f3);
      expect(keys.single.modifiers, {KeyModifier.shift});
    });

    for (final silence in ['never answers', 'answers without a report']) {
      test('from a terminal that $silence ends the session only at the report '
          'budget, without painting at a guess', () async {
        PosixTerminalDriver.inlineCursorReportBudget = const Duration(
          milliseconds: 1500,
        );
        addTearDown(
          () => PosixTerminalDriver.inlineCursorReportBudget = const Duration(
            seconds: 10,
          ),
        );
        await driver.enter(mode);
        output.bytes.clear();
        output.terminalColumns = 60;
        if (silence == 'never answers') {
          holdCursor = true;
        } else {
          answerCursor = false;
        }
        signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
        await Future<void>.delayed(const Duration(milliseconds: 1250));
        expect(errors, isEmpty, reason: 'still inside the report budget');
        expect(driver.isActive, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 750));
        expect(
          errors.single,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('stopped reporting its cursor position'),
          ),
        );
        final bytes = output.bytes.toString();
        expect(bytes, isNot(contains('\n')), reason: 'no new allocation');
        expect(bytes, isNot(contains('\x1B[2K')), reason: 'no guessed clear');
        await driver.restore();
        expect(modes.raw, isFalse);
        expect(output.bytes.toString(), isNot(contains('\x1B[2K')));
      });
    }

    /// Suspends ([transition] `suspend`) or hands the terminal off, runs
    /// [whileAway] while the app doesn't own it, and returns once the app is
    /// back.
    Future<void> leaveAndReturn(
      String transition,
      void Function() whileAway,
    ) async {
      if (transition == 'suspend') {
        await driver.debugSuspend();
        whileAway();
        await driver.debugResume();
      } else {
        await driver.runWithTerminalHandoff(whileAway);
      }
    }

    for (final transition in ['suspend', 'handoff']) {
      test('$transition during an unanswered resize waits a bounded drain, not '
          'the report budget, and reanchors on return', () async {
        await driver.enter(mode);
        output.terminalColumns = 60;
        holdCursor = true;
        signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
        await _settle();
        cursor = const CellOffset(0, 12);
        final clock = Stopwatch()..start();
        Duration? away;
        await leaveAndReturn(transition, () {
          away = clock.elapsed;
          expect(modes.raw, isFalse);
          holdCursor = false;
        });
        expect(away, lessThan(const Duration(seconds: 3)));
        await _settle();
        expect(errors, isEmpty);
        expect(driver.size, const CellSize(60, 4));
        expect(driver.renderTarget.top, 12);
        expect(
          cursorQueries,
          3,
          reason: 'entry, the abandoned resize query, the fresh anchor',
        );
      });

      test('$transition while a slow report is on its way takes that report, '
          'releases the region where it says, and reanchors on return', () async {
        await driver.enter(mode);
        events.clear();
        output.terminalColumns = 60;
        cursor = const CellOffset(0, 9);
        cursorDelay = const Duration(milliseconds: 600);
        signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
        await _settle();
        output.bytes.clear();
        String? released;
        await leaveAndReturn(transition, () {
          released = output.bytes.toString();
          cursor = const CellOffset(0, 15);
        });
        await _eventually(() => driver.renderTarget.top == 15);
        await _settle();
        expect(errors, isEmpty);
        // The report puts the 4-row region at rows 7-10 (row 9, resting row 3).
        expect(released, contains('\x1B[7;1H\x1B[2K'));
        expect(released, contains('\x1B[10;1H\x1B[2K'));
        expect(driver.size, const CellSize(60, 4));
        expect(driver.renderTarget.top, 15, reason: 'the fresh report');
        expect(cursorQueries, 3);
        expect(
          events.whereType<KeyEvent>(),
          isEmpty,
          reason: 'no reply outlived its query to become an F3 press',
        );
      });

      test('$transition: a report later than its drain, read only after the '
          'return, is not taken for the fresh anchor', () async {
        await driver.enter(mode);
        events.clear();
        output.terminalColumns = 60;
        holdCursor = true;
        signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
        await _settle();
        await leaveAndReturn(transition, () {
          // The abandoned query's report lands while the app is away, and
          // nobody reads it.
          input.send('\x1B[10;1R\x1B[?1;2c');
          holdCursor = false;
          cursor = const CellOffset(0, 15);
        });
        await _eventually(() => cursorQueries == 3 && driver.size.cols == 60);
        await _settle();
        expect(errors, isEmpty);
        expect(driver.renderTarget.top, 15, reason: 'not the stale row 9');
        expect(events.whereType<KeyEvent>(), isEmpty);
      });
    }

    test('quitting while a slow report is on its way clears the region where '
        'that report puts it', () async {
      await driver.enter(mode);
      driver.recordInlineCursor(const CellOffset(0, 1));
      output.terminalColumns = 60;
      cursor = const CellOffset(0, 11);
      cursorDelay = const Duration(milliseconds: 800);
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      output.bytes.clear();
      final clock = Stopwatch()..start();
      await driver.restore();
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 1500)));
      expect(
        cursorQueries,
        2,
        reason: 'no second query, whose reply could only land in the shell',
      );
      final bytes = output.bytes.toString();
      // Row 11 minus the caret's row 1 puts the region at rows 11-14.
      expect(bytes, contains('\x1B[11;1H\x1B[2K'));
      expect(bytes, contains('\x1B[14;1H\x1B[2K'));
      expect(RegExp(r'\x1b\[2K').allMatches(bytes), hasLength(4));
      expect(bytes, isNot(contains('\n')), reason: 'nothing allocated');
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    });
  });
}
