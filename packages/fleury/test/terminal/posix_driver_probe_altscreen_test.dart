// F10: the startup ambiguous-width probe writes a visible glyph at the home
// cell plus a Cursor Position Report query (ESC[6n), then erases it. On the
// alternate screen that scratch paint is invisible and thrown away; under a
// mode WITHOUT the alternate screen (alternateScreen: false) it would land on
// the user's real screen and scrollback. The driver must therefore GATE the
// probe on the alternate screen — safety enforced, not merely a consequence of
// enter()'s call ordering.
//
// This drives enter() over terminal-reporting fake stdio (hasTerminal => true)
// and inspects the bytes written to stdout. The fake returns only the DA
// sentinel appended to each startup query: that models an unsupported but
// responsive terminal and lets every serialized probe reach its write within
// the aggregate startup budget.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/capabilities.dart';
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
        scheduleMicrotask(() => input.push('\x1B[?1;2c'));
      }
    },
  );
  final driver = PosixTerminalDriver(stdinOverride: input, stdoutOverride: out);
  await driver.enter(mode);
  await driver.restore();
  await input.close();
  return out.written.toString();
}

// The ambiguous-width probe's distinctive bytes: the Cursor Position Report
// query and the ambiguous box-drawing glyph it measures. The image-protocol
// probe (which is NOT gated and runs in both cases) emits neither, and no
// mode-entry/exit sequence contains them — so they uniquely mark the width
// probe.
const _cprQuery = '\x1B[6n';
const _probeGlyph = '─';

void main() {
  group('PosixTerminalDriver ambiguous-width probe alt-screen gate (F10)', () {
    test('alternateScreen:false does NOT emit the width probe', () async {
      // The gate short-circuits before any probe write, independent of the
      // ambient environment — so this holds unconditionally.
      final captured = await _enterAndCapture(
        const TerminalMode(alternateScreen: false),
      );
      expect(
        captured,
        isNot(contains(_cprQuery)),
        reason: 'no ambiguous-width probe query without the alternate screen',
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
