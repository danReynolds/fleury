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
    cursorQueries = 0;
    output.onWrite = (bytes) {
      final cpr = bytes.contains('\x1B[6n');
      if (cpr) cursorQueries++;
      if (cpr && holdCursor) return;
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
    'restore during a pending resize prevents a late region acquisition',
    () async {
      await driver.enter(mode);
      holdCursor = true;
      output.terminalColumns = 60;
      signals[ProcessSignal.sigwinch]!(ProcessSignal.sigwinch);
      await _settle();
      await driver.restore();
      final restored = output.bytes.toString();
      await _settle();
      expect(output.bytes.toString(), restored);
      expect(modes.raw, isFalse);
      expect(errors, isEmpty);
    },
  );
}
