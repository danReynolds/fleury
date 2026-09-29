// F10: the startup ambiguous-width probe writes a visible glyph at the home
// cell plus a Cursor Position Report query (ESC[6n), then erases it. On the
// alternate screen that scratch paint is invisible and thrown away; under a
// bounded inline mode it would land on the user's real screen and scrollback.
// The driver must therefore GATE the
// probe on the alternate screen — safety enforced, not merely a consequence of
// enter()'s call ordering.
//
// This drives enter() over terminal-reporting fake stdio (hasTerminal => true)
// and inspects the bytes written to stdout. The fake answers cursor queries
// so inline can allocate a region, and returns the DA sentinel to close each
// startup query within the aggregate budget.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/capabilities.dart';
import 'package:fleury/src/terminal/posix_driver.dart'
    show NativePosixTerminalModeController;
import 'package:test/test.dart';

/// A stdout that reports a real terminal and records every write.
class _TerminalStdout implements Stdout {
  _TerminalStdout({this.onWrite});

  final void Function(String bytes)? onWrite;
  final StringBuffer written = StringBuffer();

  @override
  bool get hasTerminal => true;

  @override
  void write(Object? object) {
    final bytes = object.toString();
    written.write(bytes);
    onWrite?.call(bytes);
  }

  @override
  Future<void> flush() async {}

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A stdin that reports a real terminal so raw mode engages (_changedStdin) and
/// the probe's terminal guards pass.
class _TerminalStdin implements Stdin {
  final _controller = StreamController<List<int>>();
  bool _lineMode = true;
  bool _echoMode = true;

  @override
  bool get hasTerminal => true;

  @override
  bool get lineMode => _lineMode;
  @override
  set lineMode(bool value) => _lineMode = value;

  @override
  bool get echoMode => _echoMode;
  @override
  set echoMode(bool value) => _echoMode = value;

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

  void push(String bytes) => _controller.add(bytes.codeUnits);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Enters [mode] on a driver backed by terminal-reporting fake stdio, then
/// restores, and returns everything written to stdout during that lifecycle.
Future<String> _enterAndCapture(TerminalMode mode) async {
  final input = _TerminalStdin();
  final out = _TerminalStdout(
    onWrite: (bytes) {
      if (bytes.contains('\x1B[c')) {
        scheduleMicrotask(
          () => input.push(
            '${bytes.contains('\x1B[6n') ? '\x1B[5;1R' : ''}\x1B[?1;2c',
          ),
        );
      }
    },
  );
  final driver = PosixTerminalDriver(
    stdinOverride: input,
    stdoutOverride: out,
    // This test owns fake stdio; raw-mode changes must use its setters rather
    // than inspecting or mutating the test runner's actual input descriptor.
    terminalModeController: NativePosixTerminalModeController.withBindings(
      null,
    ),
  );
  await driver.enter(mode);
  await driver.restore();
  await input.close();
  return out.written.toString();
}

// Both modes may query the cursor. Only the width probe paints this glyph;
// inline's allocation queries must never paint scratch content.
const _cprQuery = '\x1B[6n';
const _probeGlyph = '─';

void main() {
  group('PosixTerminalDriver ambiguous-width probe alt-screen gate (F10)', () {
    test('inline queries its anchor without painting a width probe', () async {
      // The gate short-circuits before any probe write, independent of the
      // ambient environment — so this holds unconditionally.
      final captured = await _enterAndCapture(
        const TerminalMode.inline(rows: 10),
      );
      expect(
        captured,
        contains(_cprQuery),
        reason: 'inline still queries its allocation anchor',
      );
      expect(
        captured,
        isNot(contains(_probeGlyph)),
        reason: 'no probe glyph painted on the real screen',
      );
    });

    test('the interactive (alternate-screen) path still probes', () async {
      // Meaningful only when the environment does not independently suppress
      // the probe (an ASCII glyph tier or the FLEURY_AMBIGUOUS_WIDTH kill
      // switch would skip it regardless of the screen). Ask the driver's own
      // gate rather than restating it — a restatement can drift.
      if (!widthProbeIsPermittedByEnvironment(Platform.environment)) {
        markTestSkipped('ambient env suppresses the ambiguous-width probe');
        return;
      }

      final captured = await _enterAndCapture(TerminalMode.interactive);
      expect(
        captured,
        contains(_cprQuery),
        reason: 'the alternate-screen path runs the width probe (ESC[6n)',
      );
    });
  });
}
