@TestOn('posix')
@Tags(['integration', 'pty'])
@Timeout(Duration(minutes: 3))
library;

// End-to-end proof of the dev bootstrap under a real PTY:
//
//   1. A generated throwaway app runs via plain `dart bin/main.dart` — no
//      flags, no editor. The first process becomes the supervisor and
//      re-spawns the entrypoint as a child process with a flag-origin VM
//      service (inheritStdio: the child owns the PTY).
//   2. Editing lib/marker.dart hot RELOADS on save: the frame shows the new
//      `live:` text while `boot:` (captured in initState) keeps the old one —
//      code swapped, state preserved.
//   3. `ext.fleury.restart` hot RESTARTS: the supervisor tears the child down
//      gracefully and respawns it, so `boot:` shows the new text — state
//      dropped on purpose, same terminal session.
//   4. `ext.fleury.shutdown` ends the session; the supervisor mirrors the
//      child's exit code (0) with the terminal restored.
//
// Then the three properties that only a real session can show:
//
//   5. A tty Ctrl+C (the whole foreground group, supervisor AND app) leaves a
//      slow teardown alone — the app exits with ITS code, not the driver's
//      force code and not death by a forwarded signal.
//   6. A direct `kill` of the supervisor alone still ends the session: with
//      no ack coming, the forward backstop delivers the signal to the app.
//   7. Watch roots follow the entrypoint, and a session with nothing to
//      watch is never supervised at all.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fleury_dev_bootstrap_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'plain dart run gets save-to-reload and hot restart',
    // pub get + JIT warmup + reload/restart phases legitimately take a
    // while; the tag-level 30s default is for lean PTY captures.
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final packageRoot = Directory.current;
      final repoRoot = _findRepoRoot(packageRoot);
      final appDir = Directory('${tempDir.path}/tempapp')
        ..createSync(recursive: true);

      // ── A minimal app that renders a live value and an initState-captured
      //    copy of it — the pair that distinguishes reload from restart. ──────
      File('${appDir.path}/pubspec.yaml').writeAsStringSync('''
name: tempapp
environment:
  sdk: ^3.9.0
dependencies:
  fleury:
    path: ${packageRoot.path}
''');
      Directory('${appDir.path}/lib').createSync();
      Directory('${appDir.path}/bin').createSync();
      File(
        '${appDir.path}/lib/marker.dart',
      ).writeAsStringSync(_marker('ALPHA'));
      File('${appDir.path}/bin/main.dart').writeAsStringSync('''
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:tempapp/marker.dart' as m;

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final String _boot;

  @override
  void initState() {
    super.initState();
    _boot = m.greeting();
    // Publish the (silently self-enabled) VM service URI for the test —
    // polling, because the child's service handshake is fire-and-forget.
    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      final out = Platform.environment['FLEURY_TEST_SVC_OUT'];
      if (out == null) return timer.cancel();
      final info = await developer.Service.getInfo();
      if (info.serverUri != null) {
        File(out).writeAsStringSync(info.serverUri.toString());
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text('live:\${m.greeting()}'), Text('boot:\$_boot')],
  );
}

Future<void> main() async {
  final appExit = await runApp(const App());
  // The canonical consumer shape: main owns the process exit code. The dev
  // bootstrap must survive this during hot restarts.
  exit(switch (appExit.signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    null => 0,
  });
}
''');

      final pubGet = await Process.run(Platform.resolvedExecutable, const [
        'pub',
        'get',
        '--no-example',
      ], workingDirectory: appDir.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');

      // ── Run it under a real PTY via the repo's capture helper. ─────────────
      final svcFile = File('${tempDir.path}/svc-uri');
      final outBase = '${tempDir.path}/cap';
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          '${repoRoot.path}/profiling/capture_pty.dart',
          '--out',
          outBase,
          '--timeout',
          '150',
          '--',
          Platform.resolvedExecutable,
          'bin/main.dart',
        ],
        workingDirectory: appDir.path,
        environment: {
          'FLEURY_TEST_SVC_OUT': svcFile.path,
          'FLEURY_DEV_BOOTSTRAP_LOG': '${tempDir.path}/bootstrap.log',
        },
      );
      final stderrBuf = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuf.write);
      final stdoutBuf = StringBuffer();
      process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
      var exited = false;
      final exitFuture = process.exitCode.then((c) {
        exited = true;
        return c;
      });

      void dumpDiagnostics(String phase) {
        final bin = File('$outBase.bin');
        final json = File('$outBase.json');
        printOnFailure('=== phase: $phase ===');
        printOnFailure('capture_pty stderr: $stderrBuf');
        printOnFailure('capture_pty stdout: $stdoutBuf');
        if (json.existsSync()) {
          printOnFailure('metadata: ${json.readAsStringSync()}');
        }
        if (bin.existsSync()) {
          final bytes = latin1.decode(bin.readAsBytesSync());
          printOnFailure(
            'pty tail:\n${bytes.substring(bytes.length < 4000 ? 0 : bytes.length - 4000)}',
          );
        }
        final log = File('${tempDir.path}/bootstrap.log');
        if (log.existsSync()) {
          printOnFailure('bootstrap log:\n${log.readAsStringSync()}');
        }
      }

      VmService? vm;
      try {
        // ── The bootstrap self-enabled the service. ──────────────────────────
        final uri = await _waitFor(
          () async {
            if (exited) {
              fail('app exited early\nstderr: $stderrBuf\nstdout: $stdoutBuf');
            }
            return svcFile.existsSync() ? svcFile.readAsStringSync() : null;
          },
          timeout: const Duration(seconds: 30),
          what: 'VM service URI',
        );
        if (uri == null) {
          // openpty unavailable (sandboxed CI shells) — the helper reports it
          // on stderr before any capture output exists.
          if (stderrBuf.toString().contains('openpty failed')) {
            markTestSkipped('PTY unavailable: ${stderrBuf.toString().trim()}');
            return;
          }
          fail('no service URI\nstderr: $stderrBuf\nstdout: $stdoutBuf');
        }

        vm = await vmServiceConnectUri(_wsUri(uri));

        // ── The supervised child's own service; drive its main isolate. ──────
        final firstChildId = await _findMainIsolate(vm);
        expect(firstChildId, isNotNull, reason: 'child main isolate not found');

        // ── Hot reload: edit a watched source file; nothing else. ────────────
        File(
          '${appDir.path}/lib/marker.dart',
        ).writeAsStringSync(_marker('BETA'));
        // The first reload of a fresh isolate group revalidates every library
        // in it — allow generous time, polling the bootstrap's log for the
        // completion line rather than guessing.
        final reloadDone = await _waitFor(
          () async {
            final log = File('${tempDir.path}/bootstrap.log');
            if (!log.existsSync()) return null;
            final text = log.readAsStringSync();
            return text.contains('reload: done') ? text : null;
          },
          timeout: const Duration(seconds: 45),
          what: 'reload completion',
        );
        if (reloadDone == null) {
          dumpDiagnostics('reload never completed');
          fail('reload never completed');
        }
        expect(reloadDone, contains('success=true'));
        await Future<void>.delayed(const Duration(seconds: 1));

        // ── Hot restart via the service extension: the child process exits
        //    and the supervisor spawns a fresh one with a NEW service URI. ─────
        final firstUri = uri;
        try {
          await vm.callServiceExtension(
            'ext.fleury.restart',
            isolateId: firstChildId,
          );
        } catch (error) {
          dumpDiagnostics('restart call failed: $error');
          rethrow;
        }
        try {
          await vm.dispose(); // The old process is going away.
        } catch (_) {}
        vm = null;
        final secondUri = await _waitFor(
          () async {
            if (!svcFile.existsSync()) return null;
            final now = svcFile.readAsStringSync();
            return (now.isNotEmpty && now != firstUri) ? now : null;
          },
          timeout: const Duration(seconds: 30),
          what: 'respawned child service',
        );
        if (secondUri == null) {
          dumpDiagnostics('no fresh child after restart');
          fail('no fresh child after restart');
        }
        vm = await vmServiceConnectUri(_wsUri(secondUri));
        final secondChildId = await _findMainIsolate(vm);
        expect(secondChildId, isNotNull, reason: 'restarted main not found');
        // Let the fresh app paint its first frame.
        await Future<void>.delayed(const Duration(seconds: 2));

        // ── Clean shutdown; exit code propagates through the supervisor. ─────
        await vm.callServiceExtension(
          'ext.fleury.shutdown',
          isolateId: secondChildId!,
        );
        final exitCode = await exitFuture.timeout(const Duration(seconds: 20));
        expect(exitCode, 0, reason: 'stderr: $stderrBuf\nstdout: $stdoutBuf');
      } finally {
        try {
          vm?.dispose();
        } catch (_) {}
        if (!exited) process.kill(ProcessSignal.sigkill);
      }

      // ── The captured byte stream tells the whole story in order. ───────────
      final metadata =
          jsonDecode(File('$outBase.json').readAsStringSync())
              as Map<String, Object?>;
      expect(metadata['timedOut'], isFalse);
      expect(metadata['exitCode'], 0);
      final output = latin1.decode(File('$outBase.bin').readAsBytesSync());

      final liveAlpha = output.indexOf('live:MARK-ALPHA');
      final bootAlpha = output.indexOf('boot:MARK-ALPHA');
      final liveBeta = output.indexOf('live:MARK-BETA');
      final bootBeta = output.indexOf('boot:MARK-BETA');
      expect(liveAlpha, greaterThanOrEqualTo(0), reason: 'first frame missing');
      expect(bootAlpha, greaterThanOrEqualTo(0), reason: 'first frame missing');
      expect(
        liveBeta,
        greaterThan(liveAlpha),
        reason: 'hot reload never repainted the edited value:\n$output',
      );
      expect(
        bootBeta,
        greaterThan(liveBeta),
        reason:
            'hot restart never re-ran initState (boot value stayed ALPHA):\n'
            '$output',
      );
      // Reload preserved state: the boot line still said ALPHA when the live
      // line already said BETA — i.e. boot:BETA appears only after the restart.
      expect(output.substring(0, bootBeta), contains('boot:MARK-ALPHA'));
      // The session ended with the terminal restored (alt-screen exit).
      expect(output, contains('\x1b[?1049l'));
    },
  );

  group('signal ownership', () {
    test(
      'a tty Ctrl+C leaves a slow teardown alone',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        // The tty case: the line discipline signals the whole foreground
        // group, so the supervisor AND the app each get their own SIGINT.
        // The supervisor used to forward a second copy 300 ms later, which
        // landed on an app already past `restore()` — with its signal
        // watchers cancelled, so the process died raw and everything after
        // `await runApp` (this app's 3 s teardown) never ran. The supervisor
        // then reported the conventional 130 and the emergency tty restore
        // made it look like a clean quit.
        final app = await _generateApp(tempDir);
        final session = await _startSession(app: app, timeoutSeconds: 90);
        try {
          await session.waitUntilChildReady();
          final appPid = await session.appPid();
          final supervisorPid = await _parentPidOf(appPid);
          expect(
            supervisorPid,
            isNotNull,
            reason: 'the app must be running under a supervisor process',
          );

          // Both processes, as the kernel would deliver them.
          Process.killPid(appPid, ProcessSignal.sigint);
          Process.killPid(supervisorPid!, ProcessSignal.sigint);

          final metadata = await session.finish();
          expect(
            metadata['exitCode'],
            77,
            reason:
                'the app must exit through its own teardown (77), not the '
                'driver force path or a forwarded signal (130):\n'
                '${session.diagnostics()}',
          );
          expect(
            session.bootstrapLog(),
            anyOf(
              contains('acked by the child, forward cancelled'),
              contains('child acked first, not forwarding'),
            ),
            reason: 'the forward must be cancelled by the ack, positively',
          );
        } finally {
          session.dispose();
        }
      },
    );

    test(
      'a direct kill of the supervisor still ends the session',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        // The other provenance: a script / service manager / this harness
        // kills the supervisor alone, so the app got nothing. No ack can
        // arrive, and the forward backstop has to deliver the signal or the
        // session outlives the kill.
        final app = await _generateApp(tempDir);
        final session = await _startSession(app: app, timeoutSeconds: 90);
        try {
          await session.waitUntilChildReady();
          final appPid = await session.appPid();
          final supervisorPid = await _parentPidOf(appPid);
          expect(supervisorPid, isNotNull);

          Process.killPid(supervisorPid!, ProcessSignal.sigterm);

          final metadata = await session.finish();
          expect(metadata['timedOut'], isFalse, reason: session.diagnostics());
          expect(
            metadata['exitCode'],
            78,
            reason:
                'the app must receive the forwarded SIGTERM and run its own '
                'teardown:\n${session.diagnostics()}',
          );
          expect(
            session.bootstrapLog(),
            contains('no ack, forwarding to child'),
            reason: 'the backstop is what ends a session nobody acked',
          );
        } finally {
          session.dispose();
        }
      },
    );
  });

  group('watch roots', () {
    test(
      'hot reload works when the app is launched from another directory',
      timeout: const Timeout(Duration(minutes: 4)),
      () async {
        // `dart ~/code/app/bin/main.dart` from anywhere else. Watch roots
        // resolved from the WORKING directory found no package config here,
        // so the supervisor watched nothing and saves did nothing — silently,
        // with the session otherwise looking supervised.
        final app = await _generateApp(tempDir);
        final session = await _startSession(
          app: app,
          timeoutSeconds: 120,
          workingDirectory: tempDir.path,
        );
        try {
          await session.waitUntilChildReady();
          app.marker.writeAsStringSync(_marker('BETA'));
          final reloaded = await _waitFor(
            () async {
              final text = session.bootstrapLog();
              return text.contains('reload: done') ? text : null;
            },
            timeout: const Duration(seconds: 60),
            what: 'reload completion',
          );
          expect(
            reloaded,
            isNotNull,
            reason:
                'a save never reached the supervisor:\n'
                '${session.diagnostics()}',
          );
          expect(reloaded, contains('success=true'));

          Process.killPid(await session.appPid(), ProcessSignal.sigint);
          final metadata = await session.finish();
          expect(metadata['exitCode'], 77, reason: session.diagnostics());
          // The repaint reached the terminal. It arrives as a cursor-addressed
          // patch of the changed cells, not a rewritten line, so match the new
          // text alone.
          expect(
            session.output(),
            contains('BETA'),
            reason:
                'the reloaded value never repainted:\n'
                '${session.diagnostics()}',
          );
        } finally {
          session.dispose();
        }
      },
    );

    test(
      'a session with nothing to watch is never supervised',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        // An entrypoint outside any package config (resolved by an explicit
        // --packages) has no watchable roots from either the entrypoint or
        // the working directory. Supervising it anyway bought nothing and
        // cost everything: the user's main() ran twice, the VM service
        // banner landed on their terminal, a second VM booted, and signal
        // ownership moved into a process that could only forward.
        final app = await _generateApp(tempDir);
        final outside = Directory('${tempDir.path}/outside')..createSync();
        final entrypoint = File('${outside.path}/main.dart')
          ..writeAsStringSync(app.entrypoint.readAsStringSync());
        final session = await _startSession(
          app: app,
          timeoutSeconds: 90,
          workingDirectory: tempDir.path,
          scriptArguments: [
            '--packages=${app.dir.path}/.dart_tool/package_config.json',
            entrypoint.path,
          ],
        );
        try {
          await session.waitUntilAppStarted();
          Process.killPid(await session.appPid(), ProcessSignal.sigint);
          final metadata = await session.finish();
          expect(metadata['exitCode'], 77, reason: session.diagnostics());

          final output = session.output();
          expect(
            'BOOT-MARKER'.allMatches(output),
            hasLength(1),
            reason:
                'main() ran in a supervisor as well as the app:\n'
                '${session.diagnostics()}',
          );
          expect(
            output,
            isNot(contains('Dart VM service')),
            reason: 'a supervised respawn puts the VM banner on the terminal',
          );
        } finally {
          session.dispose();
        }
      },
    );
  });
}

/// A generated throwaway app: a `tempapp` package whose entrypoint reports its
/// pid and service URI, renders a reloadable marker, and takes a deliberately
/// slow teardown after `runApp` returns.
class _GeneratedApp {
  _GeneratedApp(this.dir);

  final Directory dir;

  File get entrypoint => File('${dir.path}/bin/main.dart');
  File get marker => File('${dir.path}/lib/marker.dart');
}

Future<_GeneratedApp> _generateApp(Directory parent) async {
  final appDir = Directory('${parent.path}/tempapp')
    ..createSync(recursive: true);
  final packageRoot = Directory.current;
  File('${appDir.path}/pubspec.yaml').writeAsStringSync('''
name: tempapp
environment:
  sdk: ^3.9.0
dependencies:
  fleury:
    path: ${packageRoot.path}
''');
  Directory('${appDir.path}/lib').createSync();
  Directory('${appDir.path}/bin').createSync();
  final app = _GeneratedApp(appDir);
  app.marker.writeAsStringSync(_marker('ALPHA'));
  app.entrypoint.writeAsStringSync('''
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:tempapp/marker.dart' as m;

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final String _boot;

  @override
  void initState() {
    super.initState();
    _boot = m.greeting();
    final pidOut = Platform.environment['FLEURY_TEST_PID_OUT'];
    // Written from the widget, never from main(): under the supervisor main()
    // runs in both processes, and the test needs the pid of the one that owns
    // the terminal.
    if (pidOut != null) File(pidOut).writeAsStringSync('\$pid');
    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      final out = Platform.environment['FLEURY_TEST_SVC_OUT'];
      if (out == null) return timer.cancel();
      final info = await developer.Service.getInfo();
      if (info.serverUri != null) {
        File(out).writeAsStringSync(info.serverUri.toString());
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text('live:\${m.greeting()}'), Text('boot:\$_boot')],
  );
}

Future<void> main() async {
  stdout.writeln('BOOT-MARKER');
  final appExit = await runApp(const App());
  // Teardown the app owns: flushing state, closing a database, a final
  // report. It runs after runApp has restored the terminal, so a signal
  // forwarded to us here has the OS default disposition and kills the
  // process outright.
  await Future<void>.delayed(const Duration(seconds: 3));
  exit(switch (appExit.signal) {
    AppSignal.interrupt => 77,
    AppSignal.terminate => 78,
    null => 0,
  });
}
''');

  final pubGet = await Process.run(Platform.resolvedExecutable, const [
    'pub',
    'get',
    '--no-example',
  ], workingDirectory: appDir.path);
  expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');
  return app;
}

/// One `capture_pty` run of a generated app, with the side channels the tests
/// steer it by: the app's pid, its service URI, and the supervisor's log.
class _Session {
  _Session({
    required this.process,
    required this.outBase,
    required this.logFile,
    required this.pidFile,
    required this.svcFile,
    required this.stderrBuf,
    required this.stdoutBuf,
  });

  final Process process;
  final String outBase;
  final File logFile;
  final File pidFile;
  final File svcFile;
  final StringBuffer stderrBuf;
  final StringBuffer stdoutBuf;
  bool _exited = false;

  String bootstrapLog() =>
      logFile.existsSync() ? logFile.readAsStringSync() : '';

  String output() {
    final bin = File('$outBase.bin');
    return bin.existsSync() ? latin1.decode(bin.readAsBytesSync()) : '';
  }

  /// Waits for the app process itself (supervised or not) to be running.
  Future<void> waitUntilAppStarted() async {
    final started = await _waitFor(
      () async => pidFile.existsSync() && pidFile.readAsStringSync().isNotEmpty
          ? true
          : null,
      timeout: const Duration(seconds: 60),
      what: 'app startup',
    );
    if (started == null) {
      if (stderrBuf.toString().contains('openpty failed')) {
        markTestSkipped('PTY unavailable: ${stderrBuf.toString().trim()}');
        return;
      }
      fail('the app never started:\n${diagnostics()}');
    }
    // The first frame is painted a moment after initState.
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  /// Waits until the supervisor has connected to the child AND the child has
  /// registered its hot-reload extension — i.e. a fully wired session.
  Future<void> waitUntilChildReady() async {
    final ready = await _waitFor(
      () async {
        final log = bootstrapLog();
        return log.contains('child ready (hot-reload extension registered)')
            ? log
            : null;
      },
      timeout: const Duration(seconds: 60),
      what: 'a wired supervisor session',
    );
    if (ready == null) {
      if (stderrBuf.toString().contains('openpty failed')) {
        markTestSkipped('PTY unavailable: ${stderrBuf.toString().trim()}');
        return;
      }
      fail('the supervisor never got a ready child:\n${diagnostics()}');
    }
  }

  Future<int> appPid() async {
    final raw = await _waitFor(
      () async {
        if (!pidFile.existsSync()) return null;
        final text = pidFile.readAsStringSync().trim();
        return text.isEmpty ? null : text;
      },
      timeout: const Duration(seconds: 30),
      what: 'the app pid',
    );
    if (raw == null) fail('the app never reported a pid:\n${diagnostics()}');
    return int.parse(raw);
  }

  /// Awaits the capture and returns its metadata.
  Future<Map<String, Object?>> finish() async {
    await process.exitCode.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        fail('the session never ended:\n${diagnostics()}');
      },
    );
    _exited = true;
    return jsonDecode(File('$outBase.json').readAsStringSync())
        as Map<String, Object?>;
  }

  String diagnostics() {
    final out = output();
    return [
      'capture_pty stderr: $stderrBuf',
      'capture_pty stdout: $stdoutBuf',
      'bootstrap log:\n${bootstrapLog()}',
      'pty tail:\n${out.substring(out.length < 4000 ? 0 : out.length - 4000)}',
    ].join('\n');
  }

  void dispose() {
    if (!_exited) process.kill(ProcessSignal.sigkill);
  }
}

Future<_Session> _startSession({
  required _GeneratedApp app,
  required int timeoutSeconds,
  String? workingDirectory,
  List<String>? scriptArguments,
}) async {
  final scratch = app.dir.parent;
  final repoRoot = _findRepoRoot(Directory.current);
  final outBase =
      '${scratch.path}/cap-${DateTime.now().microsecondsSinceEpoch}';
  final logFile = File('$outBase.log');
  final pidFile = File('$outBase.pid');
  final svcFile = File('$outBase.svc');
  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      '${repoRoot.path}/profiling/capture_pty.dart',
      '--out',
      outBase,
      '--timeout',
      '$timeoutSeconds',
      // The app exits 77/78 by design (its own teardown); 130/143 is the
      // failure this suite is about — let both through so the assertions,
      // not capture_pty's own guard, report it.
      '--allow-exit-codes',
      '77,78,130,143',
      '--',
      Platform.resolvedExecutable,
      ...?scriptArguments,
      if (scriptArguments == null) app.entrypoint.path,
    ],
    workingDirectory: workingDirectory ?? app.dir.path,
    environment: {
      'FLEURY_TEST_SVC_OUT': svcFile.path,
      'FLEURY_TEST_PID_OUT': pidFile.path,
      'FLEURY_DEV_BOOTSTRAP_LOG': logFile.path,
    },
  );
  final stderrBuf = StringBuffer();
  final stdoutBuf = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(stderrBuf.write);
  process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
  return _Session(
    process: process,
    outBase: outBase,
    logFile: logFile,
    pidFile: pidFile,
    svcFile: svcFile,
    stderrBuf: stderrBuf,
    stdoutBuf: stdoutBuf,
  );
}

/// The parent of [childPid] — the supervisor of a supervised app.
Future<int?> _parentPidOf(int childPid) async {
  final result = await Process.run('ps', ['-o', 'ppid=', '-p', '$childPid']);
  if (result.exitCode != 0) return null;
  return int.tryParse((result.stdout as String).trim());
}

String _marker(String value) => "String greeting() => 'MARK-$value';\n";

String _wsUri(String httpUri) {
  final uri = Uri.parse(httpUri.trim());
  final path = uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws';
  return uri
      .replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: path)
      .toString();
}

Future<String?> _findMainIsolate(VmService vm) async {
  final list = (await vm.getVM()).isolates ?? const [];
  for (final ref in list) {
    if (ref.name == 'main') return ref.id;
  }
  return null;
}

Future<T?> _waitFor<T>(
  Future<T?> Function() probe, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final value = await probe();
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return null;
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/profiling/capture_pty.dart').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find repo root from ${start.path}.');
    }
    current = parent;
  }
}
