@TestOn('posix')
@Tags(['integration', 'pty'])
@Timeout(Duration(minutes: 4))
library;

// Ctrl+Z as a user presses it: the app runs as a job of an interactive bash
// whose controlling terminal is a PTY, and "suspended" means what it means to
// that user — the shell prints its prompt, runs the next command, and `fg`
// brings the app back. The harness (test/fixtures/job_control_pty_harness.py)
// does the typing and records the facts; these tests assert on them.
//
// The job is a process group, and a plain `dart run bin/app.dart` or
// `fleury run` puts more than the app in it: the hot-reload supervisor (or the
// launcher) is the process the shell started and waits on. Stopping only the
// app left that parent running in the foreground, so the shell never got the
// terminal back — no prompt, and a typed command never ran.
//
// An app whose text field always has focus never sees Ctrl+Z reach job
// control — the field undoes — so it binds its own suspend key to
// TerminalSession.suspend, which must suspend the same way.
//
// Only a job-control shell can continue a stopped job. A terminal emulator, a
// tmux pane, or `ssh -t host app` runs the command directly, as the session
// leader: a stop there is permanent. The app must never suspend then.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.absolute.path;
  final fixture = '$packageRoot/test/fixtures/job_control_fixture.dart';
  final packages = '--packages=$packageRoot/.dart_tool/package_config.json';
  final dart = Platform.resolvedExecutable;

  test('an app the shell started directly suspends and resumes', () async {
    final run = await _runHarness([dart, packages, fixture]);

    run.expectSuspendedAndResumed();
    expect(run.parentIsShell, isTrue, reason: run.describe());
  });

  test('a supervised app suspends as one job with its supervisor', () async {
    final run = await _runHarness([
      dart,
      packages,
      fixture,
      '--supervised',
    ], supervised: true);

    expect(
      run.parentIsShell,
      isFalse,
      reason: 'the app must run under a supervisor process\n${run.describe()}',
    );
    run.expectSuspendedAndResumed();
    expect(
      run.stateWhileStopped('parent'),
      startsWith('T'),
      reason: 'the supervisor stops with the app\n${run.describe()}',
    );
    expect(
      run.appPidAfterFg,
      run.appPid,
      reason:
          'the supervisor must continue the same app, not take the stop for '
          'an exit and respawn it\n${run.describe()}',
    );
  });

  test('an app under `fleury run` without hot reload suspends with its '
      'launcher', () async {
    // FLEURY_HOT_RELOAD=0: the launcher runs the app once, as its child, and
    // waits for it — no supervisor marker in the app's environment at all.
    final run = await _runHarness([
      'FLEURY_HOT_RELOAD=0',
      dart,
      '$packageRoot/bin/fleury.dart',
      'run',
      fixture,
    ]);

    expect(run.parentIsShell, isFalse, reason: run.describe());
    run.expectSuspendedAndResumed();
    expect(
      run.stateWhileStopped('parent'),
      startsWith('T'),
      reason: 'the launcher stops with the app\n${run.describe()}',
    );
  });

  test("a composer's own suspend key stops the whole job while Ctrl+Z "
      'undoes in its field', () async {
    // The composer's field always has focus, so Ctrl+Z is undo, never job
    // control. Ctrl+T calls TerminalSession.suspend. Supervised, as a plain
    // `dart run bin/app.dart` runs it: the supervisor has to stop too.
    final run = await _runHarness(
      [dart, packages, fixture, '--supervised', '--suspend-key'],
      supervised: true,
      suspendKey: true,
    );

    run.expectCtrlZUndid('undoBeforeSuspend');
    run.expectSuspendedAndResumed();
    expect(
      run.stateWhileStopped('parent'),
      startsWith('T'),
      reason: 'the supervisor stops with the app\n${run.describe()}',
    );
    expect(run.appPidAfterFg, run.appPid, reason: run.describe());
    expect(
      run.report['suspendResultsWhileStopped'],
      isEmpty,
      reason:
          'the request completes after fg, not when the app stops\n'
          '${run.describe()}',
    );
    expect(run.report['suspendResults'], ['true'], reason: run.describe());
    run.expectCtrlZUndid('undoAfterFg');
  });

  // The terminal runs the command itself: it is the session leader and the
  // PTY's controlling process, with no shell anywhere.
  test('an app no shell started never stops: Ctrl+Z is an ordinary key and '
      'suspend() completes with false', () async {
    final run = await _runHarness([dart, packages, fixture], noShell: true);

    expect(run.leaderPid, run.appPid, reason: 'the app leads the session');
    run.expectNeverSuspended();
  });

  test('a supervised app no shell started never stops either', () async {
    final run = await _runHarness(
      [dart, packages, fixture, '--supervised'],
      supervised: true,
      noShell: true,
    );

    expect(
      run.appParentPid,
      run.leaderPid,
      reason: 'the supervisor leads the session\n${run.describe()}',
    );
    run.expectNeverSuspended();
    expect(
      run.leaderStateAfter('ctrlZ'),
      isNot(startsWith('T')),
      reason: 'the supervisor keeps running\n${run.describe()}',
    );
  });

  // The orderly suspend restores the terminal, stops the job, and re-enters
  // the moment the stop returns. Linux gives a signal sent to the whole
  // process to its main thread, which the Dart VM leaves waiting while the
  // isolate runs on a worker: the isolate's thread came back from killpg and
  // ran on until the main thread stopped the process, long enough to put the
  // terminal back in raw mode before the shell's prompt.
  test('a stopped job is stopped when stopJob returns', () async {
    const iterations = 200;
    final workDir = Directory.systemTemp.createTempSync('fleury_stop_job_');
    addTearDown(() => workDir.deleteSync(recursive: true));
    final result = await Process.run('python3', <String>[
      '$packageRoot/test/fixtures/stop_job_pty_harness.py',
      workDir.path,
      '--',
      dart,
      packages,
      '$packageRoot/test/fixtures/stop_job_fixture.dart',
      '$iterations',
    ]);
    final reportFile = File('${workDir.path}/report.json');
    expect(
      reportFile.existsSync(),
      isTrue,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['failure'], isNull, reason: '$report');
    expect(report['stops'], iterations, reason: '$report');
    expect(
      report['early'],
      isEmpty,
      reason:
          'stopJob returned and the app ran on before these stops took '
          'effect: ${report['early']}',
    );
    expect(report['exit'], 0, reason: '$report');
  });
}

Future<_HarnessRun> _runHarness(
  List<String> command, {
  bool supervised = false,
  bool suspendKey = false,
  bool noShell = false,
}) async {
  final packageRoot = Directory.current.absolute.path;
  final workDir = Directory.systemTemp.createTempSync('fleury_job_control_');
  addTearDown(() => workDir.deleteSync(recursive: true));
  final result = await Process.run('python3', <String>[
    '$packageRoot/test/fixtures/job_control_pty_harness.py',
    workDir.path,
    if (supervised) '--supervised',
    if (suspendKey) '--suspend-key',
    if (noShell) '--no-shell',
    '--',
    ...command,
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

  Map<String, Object?> _facts(String who) =>
      (report[who] as Map<String, Object?>?) ?? const <String, Object?>{};

  bool get parentIsShell => _facts('parent')['pid'] == report['shellPid'];

  int? get appPid => _facts('app')['pid'] as int?;

  int? get appParentPid => _facts('app')['ppid'] as int?;

  int? get leaderPid => report['leaderPid'] as int?;

  int? get appPidAfterFg => _facts('afterFg')['appPid'] as int?;

  String? stateWhileStopped(String who) =>
      (report['whileStopped'] as Map<String, Object?>?)?[who] as String?;

  String? leaderStateAfter(String step) =>
      _facts(step)['leaderState'] as String?;

  /// The terminal output between two recorded steps (to the end without
  /// [to]).
  String _between(String from, [String? to]) {
    final offsets = report['offsets'] as Map<String, Object?>? ?? const {};
    final start = offsets[from] as int?;
    final end = to == null ? output.length : offsets[to] as int?;
    expect(start, isNotNull, reason: 'no $from step\n${describe()}');
    expect(end, isNotNull, reason: 'no $to step\n${describe()}');
    return output.substring(start!, end);
  }

  void expectSuspendedAndResumed() {
    expect(
      report['promptAfterSuspend'],
      isTrue,
      reason: 'one press must give the shell its prompt back\n${describe()}',
    );
    expect(report['failure'], isNull, reason: describe());
    expect(report['stoppedNotice'], isTrue, reason: describe());
    expect(stateWhileStopped('app'), startsWith('T'), reason: describe());
    expect(report['shellRanCommand'], isTrue, reason: describe());
    expect(report['resumedAfterFg'], isTrue, reason: describe());
    expect(report['jobExit'], 0, reason: describe());

    // The app handed the shell a restored terminal before its prompt — mouse
    // reporting off, cursor shown, alternate screen left — and `fg` entered
    // the app's modes again.
    final suspended = _between('suspend', 'fg');
    final prompt = suspended.indexOf('FLEURY-JOB-PROMPT\$ ');
    var restored = 0;
    for (final restore in ['\x1B[?1000l', '\x1B[?25h', '\x1B[?1049l']) {
      final at = suspended.indexOf(restore);
      expect(at, greaterThanOrEqualTo(0), reason: '$restore\n${describe()}');
      expect(at, lessThan(prompt), reason: '$restore\n${describe()}');
      restored = max(restored, suspended.lastIndexOf(restore, prompt));
    }
    // Nor did the app enter its modes again before it stopped, leaving the
    // prompt on the alternate screen with the cursor hidden.
    for (final enter in ['\x1B[?1049h', '\x1B[?25l']) {
      expect(
        suspended.substring(restored, prompt),
        isNot(contains(enter)),
        reason: 'the app re-entered $enter before the prompt\n${describe()}',
      );
    }
    final resumed = _between('fg', 'quit');
    for (final enter in ['\x1B[?1049h', '\x1B[?25l']) {
      expect(resumed, contains(enter), reason: '$enter\n${describe()}');
    }
  }

  /// No job-control shell started the app, so nothing suspended it: Ctrl+Z
  /// reached it as an ordinary key, its own suspend key's request completed
  /// with false, neither left a process stopped or the terminal restored for
  /// a shell, and the next key — Ctrl+Q — still ended it normally.
  void expectNeverSuspended() {
    expect(report['failure'], isNull, reason: describe());
    expect(
      report['supportsSuspend'],
      ['false'],
      reason: 'TerminalSession.supportsSuspend\n${describe()}',
    );
    expect(
      _facts('app')['pgid'],
      leaderPid,
      reason: "the app runs in the session leader's group\n${describe()}",
    );
    for (final (step, event) in [
      ('ctrlZ', 'key:ctrl+z'),
      ('suspendKey', 'suspended:false'),
    ]) {
      final facts = _facts(step);
      expect(facts['events'], contains(event), reason: describe());
      expect(facts['appState'], isNot(startsWith('T')), reason: describe());
      expect(facts['leaderState'], isNot(startsWith('T')), reason: describe());
      expect(facts['terminalReleased'], isFalse, reason: describe());
    }
    expect(report['exit'], 0, reason: describe());
    expect(report['restoredOnExit'], isTrue, reason: describe());
  }

  /// The composer's field undid a Ctrl+Z, and the job kept running: no
  /// prompt, and the app not stopped.
  void expectCtrlZUndid(String step) {
    final facts = report[step] as Map<String, Object?>?;
    expect(facts, isNotNull, reason: '$step never ran\n${describe()}');
    expect(facts!['undone'], isTrue, reason: describe());
    expect(facts['prompt'], isFalse, reason: describe());
    expect(facts['appState'], isNot(startsWith('T')), reason: describe());
  }

  String describe() {
    final bootstrap = File('${workDir.path}/bootstrap.log');
    final events = File('${workDir.path}/app-events.log');
    final tail = output.length > 3000
        ? output.substring(output.length - 3000)
        : output;
    return [
      'report: ${const JsonEncoder.withIndent('  ').convert(report)}',
      if (bootstrap.existsSync())
        'bootstrap log:\n${bootstrap.readAsStringSync()}',
      if (events.existsSync()) 'app events:\n${events.readAsStringSync()}',
      'pty tail: ${jsonEncode(tail)}',
    ].join('\n');
  }
}
