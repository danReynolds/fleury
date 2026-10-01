// `fleury shell` in a pseudo-terminal that is its controlling terminal, with
// an app attached from a session of its own — the IDE arrangement. The
// harness (test/fixtures/shell_pty_harness.py) types into the terminal and
// records what the shell, the app and the terminal's modes did; these tests
// assert on that record. The harness also plays the terminal emulator: it
// keeps the DEC modes and keyboard flags the shell's output sets, and reports
// a click or a pointer move only while those would make a real terminal
// report one.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final skip = Platform.isWindows
      ? 'fleury shell and its PTY harness are POSIX-only.'
      : null;

  test(
    'every key reaches the attached app, the terminal returns exactly, and '
    'the shell serves the next run',
    () async {
      final run = await _runHarness('keys');
      run.expectCompleted();

      // Raw mode as the app's own driver sets it: the terminal generates no
      // signals and does no line editing, echo, or flow control, so every
      // key is a byte the shell can forward.
      expect(run.termios('idle')['ISIG'], isTrue, reason: run.describe());
      expect(run.termios('attached'), <String, bool>{
        'ISIG': false,
        'ICANON': false,
        'ECHO': false,
        'IEXTEN': false,
        'IXON': false,
        'ICRNL': false,
        'OPOST': false,
      }, reason: run.describe());

      // Ctrl+Z undid the edit in the focused field and Ctrl+C, which nothing
      // handled, ended the app with an interrupt. The app has no terminal of
      // its own, so both could only have arrived as keys through the shell.
      // What was typed before it attached, while the shell was idle, never
      // reached it: the first thing the app saw was the x.
      expect(run.appRecords(0), <Object>[
        {'text': 'x'},
        {'text': ''},
        {'key': 'c', 'ctrl': true},
        {'exit': 'interrupt'},
      ], reason: run.describe());
      expect(run.appExit(0), 130, reason: run.describe());
      // The edit's repaint reached the screen too: a diff frame, writing just
      // the changed tail of the app's status line.
      expect(
        run.output,
        matches(RegExp(r'\x1B\[\d+;\d+H(\x1B\[[0-9;]*m)*TYPED-x')),
        reason: run.describe(),
      );
      expect(
        run.restoredExactly('afterSession'),
        isTrue,
        reason: 'the full termios snapshot must come back\n${run.describe()}',
      );
      // A default app reads pastes and focus changes, not the mouse: the
      // shell's terminal reports exactly those, at the keyboard tier it
      // probes, and every mode is back as it was once the app has gone.
      final attached = run.terminalModes('attached');
      expect(
        attached,
        containsAll(<int>[_paste, _focus]),
        reason: run.describe(),
      );
      for (final mode in [..._mouseButtons, _motion]) {
        expect(
          attached,
          isNot(contains(mode)),
          reason: '$mode\n${run.describe()}',
        );
      }
      expect(run.kittyStack('attached'), [3], reason: run.describe());
      _expectTerminalHandedBack(run, 'afterSession');

      // The next run attached to the same shell and got its keys too.
      expect(run.appRecords(1), <Object>[
        {'text': 'y'},
        {'key': 'c', 'ctrl': true},
        {'exit': 'interrupt'},
      ], reason: run.describe());
      expect(run.appExit(1), 130, reason: run.describe());

      // Idle again, Ctrl+C was the terminal's interrupt: it quit the shell.
      expect(run.shellExit, 130, reason: run.describe());
      expect(run.restoredExactly('afterShell'), isTrue, reason: run.describe());
      _expectTerminalHandedBack(run, 'afterShell');
      _expectScreenHandedBack(run);
      _expectDiscoveryRemoved(run);
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'an app whose mode asks for the mouse gets it: tracking comes on, a click '
    'presses its button, and the terminal comes back exactly',
    () async {
      final run = await _runHarness('mouse');
      run.expectCompleted();

      // Button presses, releases and drags (1000, 1002) in SGR encoding
      // (1006), as the app's own driver turns on for TerminalMode(mouse:
      // true) — and not all-motion (1003), which it did not ask for.
      final attached = run.terminalModes('attached');
      expect(attached, containsAll(_mouseButtons), reason: run.describe());
      expect(attached, isNot(contains(_motion)), reason: run.describe());
      // The click the terminal reported, relayed byte for byte, pressed the
      // button; the Ctrl+C after it ended the app.
      expect(run.appRecords(0), <Object>[
        {'pressed': 'button'},
        {'key': 'c', 'ctrl': true},
        {'exit': 'interrupt'},
      ], reason: run.describe());
      expect(run.appExit(0), 130, reason: run.describe());

      // After the app exits, tracking is off again and every mode the shell
      // changed is back as it was found; so is termios.
      _expectMouseTurnedOff(run);
      _expectTerminalHandedBack(run, 'afterSession');
      expect(
        run.restoredExactly('afterSession'),
        isTrue,
        reason: run.describe(),
      );
      expect(run.restoredExactly('afterShell'), isTrue, reason: run.describe());
      _expectTerminalHandedBack(run, 'afterShell');
      _expectScreenHandedBack(run);
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'an app whose mode asks for pointer motion gets hover: all-motion '
    'tracking comes on, and a move reaches its MouseRegion',
    () async {
      final run = await _runHarness('mouse-motion');
      run.expectCompleted();

      final attached = run.terminalModes('attached');
      expect(
        attached,
        containsAll(<int>[..._mouseButtons, _motion]),
        reason: run.describe(),
      );
      // The move the terminal reported hovered the region; the click after
      // it pressed the button.
      expect(run.appRecords(0), <Object>[
        {'hover': 'enter'},
        {'pressed': 'button'},
        {'key': 'c', 'ctrl': true},
        {'exit': 'interrupt'},
      ], reason: run.describe());

      _expectMouseTurnedOff(run);
      _expectTerminalHandedBack(run, 'afterSession');
      expect(
        run.restoredExactly('afterSession'),
        isTrue,
        reason: run.describe(),
      );
      _expectTerminalHandedBack(run, 'afterShell');
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'an app that asks for no mouse, pastes, focus reports, or keyboard flags '
    'gets a terminal that reports none of them',
    () async {
      final run = await _runHarness('no-input-reporting');
      run.expectCompleted();

      final attached = run.terminalModes('attached');
      for (final mode in [..._mouseButtons, _motion, _paste, _focus]) {
        expect(
          attached,
          isNot(contains(mode)),
          reason: '$mode\n${run.describe()}',
        );
      }
      // The flags the shell pushed to probe the keyboard are popped again,
      // on the screen they were pushed to: legacy keys, as the app's own
      // driver would leave them.
      expect(run.kittyStack('attached'), isEmpty, reason: run.describe());
      // A click stayed the terminal's; a typed key reached the app.
      expect(run.appRecords(0), [
        {'text': 'x'},
        {'key': 'c', 'ctrl': true},
        {'exit': 'interrupt'},
      ], reason: run.describe());
      _expectTerminalHandedBack(run, 'afterSession');
      expect(
        run.restoredExactly('afterSession'),
        isTrue,
        reason: run.describe(),
      );
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'an app from another Fleury is turned away with the reason, and the '
    'shell serves the next run',
    () async {
      final run = await _runHarness('mismatched-apps');
      run.expectCompleted();

      // The shell declares its own protocol, never a structured `v=`.
      final init = run.report['shellInit'] as String?;
      expect(init, endsWith(',shell=2'), reason: run.describe());
      expect(init, isNot(contains('v=')), reason: run.describe());

      // An app from before shell protocol 2 hangs up on that INIT; one from
      // a newer Fleury answers at its own version. Neither attaches.
      expect(
        run.output,
        contains(
          "the app could not attach: it disconnected before answering the "
          "shell's handshake.",
        ),
        reason: run.describe(),
      );
      expect(
        run.output,
        contains(
          'the app could not attach: it speaks shell protocol v3, and this '
          'shell speaks v2.',
        ),
        reason: run.describe(),
      );
      expect(
        run.output,
        contains('dart run fleury shell'),
        reason: run.describe(),
      );
      for (final label in ['afterOldApp', 'afterNewApp']) {
        expect(run.restoredExactly(label), isTrue, reason: run.describe());
        _expectTerminalHandedBack(run, label);
      }
      // The app from this build attached as usual afterwards.
      expect(run.appExit(0), 130, reason: run.describe());
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a Ctrl+Z the app leaves unhandled is an ordinary key: nothing stops',
    () async {
      // Unlike an app in a terminal of its own, an app behind the shell is
      // not a job of the shell's terminal: it runs in the IDE, so there is
      // nothing to suspend. As in the browser, the chord stays a key.
      final run = await _runHarness('unhandled-ctrl-z');
      run.expectCompleted();
      expect(run.appRecords(0), <Object>[
        {'key': 'z', 'ctrl': true},
        {'key': 'c', 'ctrl': true},
        {'exit': 'interrupt'},
      ], reason: run.describe());
      expect(run.appExit(0), 130, reason: run.describe());
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SIGTERM while an app is attached restores the terminal before exiting',
    () async {
      final run = await _runHarness('sigterm');
      run.expectCompleted();
      expect(run.shellExit, 143, reason: run.describe());
      expect(run.restoredExactly('afterShell'), isTrue, reason: run.describe());
      expect(run.appExit(0), 0, reason: 'the shell says goodbye first');
      _expectScreenHandedBack(run);
      _expectDiscoveryRemoved(run);
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'an app that dies without a goodbye still hands the terminal back',
    () async {
      final run = await _runHarness('app-killed');
      run.expectCompleted();
      expect(
        run.restoredExactly('afterSession'),
        isTrue,
        reason: run.describe(),
      );
      _expectScreenHandedBack(run);
      expect(run.shellExit, 130, reason: 'it waited until SIGINT quit it');
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'closing the terminal while an app is attached ends the shell and app',
    () async {
      final run = await _runHarness('hangup');
      run.expectCompleted();
      expect(run.shellExit, 129, reason: run.describe());
      expect(run.appExit(0), 0, reason: run.describe());
      _expectDiscoveryRemoved(run);
    },
    skip: skip,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// The shell leaves its terminal as it found it: after the last time it
/// took the screen over, it pops exactly the keyboard flags it pushed while
/// still on the alternate screen, turns autowrap back on (the app's renderer
/// runs with it off), shows the cursor, and leaves the alternate screen.
void _expectScreenHandedBack(_HarnessRun run) {
  final output = run.output;
  final enter = output.lastIndexOf('\x1B[?1049h');
  expect(enter, greaterThanOrEqualTo(0), reason: run.describe());
  final session = output.substring(enter);
  expect(session, contains('\x1B[?7l'), reason: 'autowrap off while drawing');
  final pop = session.indexOf('\x1B[<1u');
  final leave = session.indexOf('\x1B[?1049l');
  expect(pop, greaterThanOrEqualTo(0), reason: 'explicit-count keyboard pop');
  expect(leave, greaterThan(pop), reason: 'pop on the screen it was pushed');
  final exit = session.substring(pop);
  expect(exit, contains('\x1B[?2004l'));
  expect(exit, contains('\x1B[?25h'));
  expect(exit, contains('\x1B[?7h'));
}

/// DEC private modes: mouse button tracking (1000), drag tracking (1002),
/// SGR mouse encoding (1006), any-motion tracking (1003), bracketed paste
/// (2004), focus reports (1004).
const _mouseButtons = <int>[1000, 1002, 1006];
const _motion = 1003;
const _paste = 2004;
const _focus = 1004;

/// Every mouse mode is turned off after the last time tracking came on.
void _expectMouseTurnedOff(_HarnessRun run) {
  final output = run.output;
  final on = output.lastIndexOf('\x1B[?1000h');
  expect(on, greaterThanOrEqualTo(0), reason: run.describe());
  expect(
    output.indexOf('\x1B[?1006l\x1B[?1003l\x1B[?1002l\x1B[?1000l', on),
    greaterThan(on),
    reason: 'mouse tracking must be turned off again\n${run.describe()}',
  );
}

/// The emulated terminal is as the shell found it before the first app:
/// every DEC private mode, and no keyboard flags left on either screen.
void _expectTerminalHandedBack(_HarnessRun run, String label) {
  expect(
    run.terminalModes(label),
    run.terminalModes('idle'),
    reason: '$label\n${run.describe()}',
  );
  expect(run.kittyStack(label), isEmpty, reason: '$label\n${run.describe()}');
  expect(
    run.mainKittyStack(label),
    isEmpty,
    reason: '$label\n${run.describe()}',
  );
}

void _expectDiscoveryRemoved(_HarnessRun run) {
  expect(
    File('${run.workDir.path}/.fleury/handle').existsSync(),
    isFalse,
    reason: run.describe(),
  );
}

Future<_HarnessRun> _runHarness(String scenario) async {
  final packageRoot = Directory.current.absolute.path;
  final workDir = Directory.systemTemp.createTempSync('fleury_shell_pty_');
  addTearDown(() => workDir.deleteSync(recursive: true));
  File('${workDir.path}/pubspec.yaml').writeAsStringSync('''
name: shell_pty_fixture
environment:
  sdk: ^3.10.4
''');
  final result = await Process.run('python3', <String>[
    '$packageRoot/test/fixtures/shell_pty_harness.py',
    scenario,
    Platform.resolvedExecutable,
    packageRoot,
    workDir.path,
  ]);
  final reportFile = File('${workDir.path}/report.json');
  if (result.exitCode != 0 || !reportFile.existsSync()) {
    fail(
      'the PTY harness failed (exit ${result.exitCode})\n'
      'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
  }
  return _HarnessRun(
    workDir,
    jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>,
    latin1.decode(File('${workDir.path}/pty.bin').readAsBytesSync()),
  );
}

final class _HarnessRun {
  _HarnessRun(this.workDir, this.report, this.output);

  final Directory workDir;
  final Map<String, Object?> report;
  final String output;

  void expectCompleted() =>
      expect(report['failure'], isNull, reason: describe());

  int? get shellExit => report['shellExit'] as int?;

  Map<String, Object?> termios(String label) =>
      ((report['termios'] as Map<String, Object?>?)?[label]
          as Map<String, Object?>?) ??
      const <String, Object?>{};

  bool? restoredExactly(String label) =>
      (report['restoredExactly'] as Map<String, Object?>?)?[label] as bool?;

  /// The emulated terminal's state the harness recorded under [label].
  Map<String, Object?> _terminal(String label) {
    final state =
        (report['terminal'] as Map<String, Object?>?)?[label]
            as Map<String, Object?>?;
    if (state == null) fail('no terminal state recorded as $label');
    return state;
  }

  /// The DEC private modes set at [label].
  Set<int> terminalModes(String label) => {
    ...(_terminal(label)['modes'] as List<Object?>).cast<int>(),
  };

  /// The Kitty keyboard flag stack of the screen in use at [label].
  List<int> kittyStack(String label) =>
      (_terminal(label)['kitty'] as List<Object?>).cast<int>();

  /// The main screen's Kitty keyboard flag stack at [label].
  List<int> mainKittyStack(String label) =>
      (_terminal(label)['mainKitty'] as List<Object?>).cast<int>();

  Map<String, Object?> _app(int index) =>
      (report['apps'] as List<Object?>)[index] as Map<String, Object?>;

  int? appExit(int index) => _app(index)['exit'] as int?;

  List<Object?> appRecords(int index) =>
      (_app(index)['records'] as List<Object?>?) ?? const <Object?>[];

  String describe() {
    final logs = StringBuffer();
    for (final entry in workDir.listSync()) {
      if (entry is File && entry.path.endsWith('.log')) {
        logs.writeln('--- ${entry.path}\n${entry.readAsStringSync()}');
      }
    }
    return '${const JsonEncoder.withIndent('  ').convert(report)}\n'
        '$logs--- terminal output (escaped)\n'
        '${output.replaceAll('\x1B', r'\e')}';
  }
}
