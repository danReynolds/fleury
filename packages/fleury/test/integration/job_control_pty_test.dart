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

import 'dart:convert';
import 'dart:io';

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
}

Future<_HarnessRun> _runHarness(
  List<String> command, {
  bool supervised = false,
}) async {
  final packageRoot = Directory.current.absolute.path;
  final workDir = Directory.systemTemp.createTempSync('fleury_job_control_');
  addTearDown(() => workDir.deleteSync(recursive: true));
  final result = await Process.run('python3', <String>[
    '$packageRoot/test/fixtures/job_control_pty_harness.py',
    workDir.path,
    supervised ? 'supervised' : 'direct',
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

  int? get appPidAfterFg => _facts('afterFg')['appPid'] as int?;

  String? stateWhileStopped(String who) =>
      (report['whileStopped'] as Map<String, Object?>?)?[who] as String?;

  void expectSuspendedAndResumed() {
    expect(
      report['promptAfterCtrlZ'],
      isTrue,
      reason: 'one Ctrl+Z must give the shell its prompt back\n${describe()}',
    );
    expect(report['failure'], isNull, reason: describe());
    expect(report['stoppedNotice'], isTrue, reason: describe());
    expect(stateWhileStopped('app'), startsWith('T'), reason: describe());
    expect(report['shellRanCommand'], isTrue, reason: describe());
    expect(report['resumedAfterFg'], isTrue, reason: describe());
    expect(report['jobExit'], 0, reason: describe());
  }

  String describe() {
    final bootstrap = File('${workDir.path}/bootstrap.log');
    final tail = output.length > 3000
        ? output.substring(output.length - 3000)
        : output;
    return [
      'report: ${const JsonEncoder.withIndent('  ').convert(report)}',
      if (bootstrap.existsSync())
        'bootstrap log:\n${bootstrap.readAsStringSync()}',
      'pty tail: ${jsonEncode(tail)}',
    ].join('\n');
  }
}
