// PosixJobControl's shell-job rule: a session suspends only as the job of a
// process that ignores or catches SIGTSTP, as every job-control shell does.
// The rule is pinned here against fake process tables; readProcess, which
// feeds it from /proc (Linux) or the kernel's kinfo_proc (macOS, through
// FFI at hard-coded offsets), is pinned against processes whose signal
// dispositions the test sets, and against ps.
//
// The PTY tier (test/integration/job_control_pty_test.dart) runs the rule
// under real shells and launchers.

@TestOn('posix')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/terminal/posix_driver.dart'
    show JobControlProcess, PosixJobControl;
import 'package:test/test.dart';

void main() {
  group('createdByJobControl', () {
    // pid 50 runs in group 50; the processes above it are listed by pid.
    bool created(Map<int, JobControlProcess> table, {int self = 50}) =>
        PosixJobControl.createdByJobControl(self, 50, (pid) => table[pid]);

    final tstp = 1 << (PosixJobControl.sigtstp - 1);
    final otherSignals = ~tstp & 0xffffffff;

    test('a shell that ignores SIGTSTP started the job', () {
      expect(
        created({
          50: const JobControlProcess(parent: 10, group: 50),
          10: JobControlProcess(parent: 1, group: 10, ignored: tstp),
        }),
        isTrue,
      );
    });

    test('a shell that catches SIGTSTP (ksh) started the job', () {
      expect(
        created({
          50: const JobControlProcess(parent: 10, group: 50),
          10: JobControlProcess(parent: 1, group: 10, caught: tstp),
        }),
        isTrue,
      );
    });

    test('the job is the shell child of a supervisor or a wrapper in its '
        'group', () {
      expect(
        created({
          52: const JobControlProcess(parent: 51, group: 50),
          51: const JobControlProcess(parent: 50, group: 50),
          50: const JobControlProcess(parent: 10, group: 50),
          10: JobControlProcess(parent: 1, group: 10, ignored: tstp),
        }, self: 52),
        isTrue,
      );
    });

    test("a pipeline whose leader has exited still finds the shell", () {
      // The app is the second process of `producer | app`; the producer,
      // which led the group, is gone.
      expect(
        created({
          53: const JobControlProcess(parent: 10, group: 50),
          10: JobControlProcess(parent: 1, group: 10, ignored: tstp),
        }, self: 53),
        isTrue,
      );
    });

    test('a launcher that leaves SIGTSTP at its default did not', () {
      // login under fish's `exec`, tini under `docker run --init`: whatever
      // else they ignore or catch, a stop would stop them for good.
      expect(
        created({
          50: const JobControlProcess(parent: 10, group: 50),
          10: JobControlProcess(
            parent: 1,
            group: 10,
            ignored: otherSignals,
            caught: otherSignals,
          ),
        }),
        isFalse,
      );
    });

    test('only the first process outside the group counts', () {
      // A shell further up does not vouch for a launcher between it and the
      // job: the launcher is what would have to continue it.
      expect(
        created({
          50: const JobControlProcess(parent: 10, group: 50),
          10: const JobControlProcess(parent: 5, group: 10),
          5: JobControlProcess(parent: 1, group: 5, ignored: tstp),
        }),
        isFalse,
      );
    });

    test('an unreadable or missing process says no', () {
      expect(
        created({50: const JobControlProcess(parent: 10, group: 50)}),
        isFalse,
      );
      expect(created({}), isFalse);
      expect(
        created({50: const JobControlProcess(parent: 0, group: 50)}),
        isFalse,
      );
    });

    test('a job left to pid 1 has no shell on macOS, where pid 1 is '
        'launchd', () {
      // launchd ignores SIGTSTP, as a shell does, but continues nothing.
      final orphaned = {
        50: const JobControlProcess(parent: 1, group: 50),
        1: JobControlProcess(parent: 0, group: 1, ignored: tstp),
      };
      expect(
        PosixJobControl.createdByJobControl(
          50,
          50,
          (pid) => orphaned[pid],
          initCanBeShell: false,
        ),
        isFalse,
      );
      // On Linux pid 1 can be the shell itself: `docker run -it image bash`.
      expect(
        PosixJobControl.createdByJobControl(
          50,
          50,
          (pid) => orphaned[pid],
          initCanBeShell: true,
        ),
        isTrue,
      );
    });

    test('a chain that never leaves the group says no', () {
      expect(
        created({
          50: const JobControlProcess(parent: 51, group: 50),
          51: const JobControlProcess(parent: 50, group: 50),
        }),
        isFalse,
      );
    });
  });

  group('readProcess', () {
    final tstp = 1 << (PosixJobControl.sigtstp - 1);

    test(
      'reads a process that ignores SIGTSTP, as `trap "" TSTP` leaves it',
      () async {
        final process = await _sleeper(r'trap "" TSTP; exec sleep 30');
        final read = PosixJobControl.readProcess(process.pid);
        expect(read, isNotNull);
        expect(read!.ignored & tstp, isNonZero, reason: '$read');
        expect(read.caught & tstp, isZero, reason: '$read');
        expect(read.handlesSignal(PosixJobControl.sigtstp), isTrue);
        await _expectMatchesPs(process.pid, read);
      },
    );

    test('reads a process that catches SIGTSTP', () async {
      // The shell stays: a trap's handler lives in its own process.
      final process = await _sleeper(r'trap : TSTP; sleep 30; :');
      final read = PosixJobControl.readProcess(process.pid);
      expect(read, isNotNull);
      expect(read!.caught & tstp, isNonZero, reason: '$read');
      expect(read.ignored & tstp, isZero, reason: '$read');
      expect(read.handlesSignal(PosixJobControl.sigtstp), isTrue);
      await _expectMatchesPs(process.pid, read);
    });

    test('reads a process that leaves SIGTSTP at its default', () async {
      final process = await _sleeper('exec sleep 30');
      final read = PosixJobControl.readProcess(process.pid);
      expect(read, isNotNull);
      expect(read!.handlesSignal(PosixJobControl.sigtstp), isFalse);
      await _expectMatchesPs(process.pid, read);
    });

    test('reads this process: its parent and group', () {
      final read = PosixJobControl.readProcess(pid);
      expect(read, isNotNull);
      final ps = Process.runSync('ps', ['-o', 'ppid=,pgid=', '-p', '$pid']);
      final fields = (ps.stdout as String).trim().split(RegExp(r'\s+'));
      expect(read!.parent, int.parse(fields[0]));
      expect(read.group, int.parse(fields[1]));
    });

    test('a process that does not exist reads as null', () {
      expect(PosixJobControl.readProcess(0x3fffffff), isNull);
    });

    test(
      'reads a process whose name the kernel cut mid-character',
      () async {
        // Linux keeps 15 bytes of a process name: here 14 ASCII bytes and
        // the first byte of a three-byte character, so /proc holds a name
        // that isn't UTF-8. Dart names its own process `dart:<script>`, and
        // a script named in Japanese ends the same way.
        final dir = Directory.systemTemp.createTempSync('fleury_name_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final link = Link('${dir.path}/aaaaaaaaaaaaaa\u30a2\u30d7\u30ea')
          ..createSync('/bin/sleep');
        final process = await Process.start(link.path, ['30']);
        addTearDown(() {
          process.kill(ProcessSignal.sigkill);
          return process.exitCode;
        });
        final name = File('/proc/${process.pid}/comm').readAsBytesSync();
        expect(
          () => utf8.decode(name),
          throwsFormatException,
          reason: 'the name should not be UTF-8: $name',
        );
        final read = PosixJobControl.readProcess(process.pid);
        expect(read, isNotNull);
        expect(read!.parent, pid);
        await _expectMatchesPs(process.pid, read);
      },
      skip: Platform.isLinux ? false : 'only Linux reads process names',
    );
  });
}

/// Starts `/bin/sh -c [script]`, which ends up sleeping, and waits until its
/// trap is set up (a `ps` round trip is enough: the script's first command is
/// the trap).
Future<Process> _sleeper(String script) async {
  final process = await Process.start('/bin/sh', ['-c', script]);
  addTearDown(() {
    process.kill(ProcessSignal.sigkill);
    return process.exitCode;
  });
  // The trap runs before sleep starts; wait until the process is sleeping.
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final children = Process.runSync('ps', [
      '-o',
      'command=',
      '-p',
      '${process.pid}',
    ]);
    final command = (children.stdout as String).trim();
    final hasSleep = Process.runSync('pgrep', ['-P', '${process.pid}']);
    if (command.startsWith('sleep') ||
        (hasSleep.stdout as String).trim().isNotEmpty) {
      return process;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('the sleeper never started');
}

/// Parent and group as ps reports them; on Linux, the ignored and caught
/// masks too (procps prints them in hex; macOS's ps has no such columns).
Future<void> _expectMatchesPs(int target, JobControlProcess read) async {
  final ps = await Process.run('ps', ['-o', 'ppid=,pgid=', '-p', '$target']);
  final fields = (ps.stdout as String).trim().split(RegExp(r'\s+'));
  expect(read.parent, int.parse(fields[0]), reason: '$read');
  expect(read.group, int.parse(fields[1]), reason: '$read');
  if (!Platform.isLinux) return;
  final masks = await Process.run('ps', [
    '-o',
    'ignored=,caught=',
    '-p',
    '$target',
  ]);
  final hex = (masks.stdout as String).trim().split(RegExp(r'\s+'));
  int low(String mask) => int.parse(
    mask.length > 8 ? mask.substring(mask.length - 8) : mask,
    radix: 16,
  );
  expect(read.ignored, low(hex[0]), reason: 'ps: ${masks.stdout}');
  expect(read.caught, low(hex[1]), reason: 'ps: ${masks.stdout}');
}
