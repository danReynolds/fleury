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

  test('plain dart run gets save-to-reload and hot restart',
      // pub get + JIT warmup + reload/restart phases legitimately take a
      // while; the tag-level 30s default is for lean PTY captures.
      timeout: const Timeout(Duration(minutes: 4)), () async {
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
    File('${appDir.path}/lib/marker.dart').writeAsStringSync(_marker('ALPHA'));
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
      final uri = await _waitFor(() async {
        if (exited) {
          fail(
            'app exited early\nstderr: $stderrBuf\nstdout: $stdoutBuf',
          );
        }
        return svcFile.existsSync() ? svcFile.readAsStringSync() : null;
      }, timeout: const Duration(seconds: 30), what: 'VM service URI');
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
      File('${appDir.path}/lib/marker.dart')
          .writeAsStringSync(_marker('BETA'));
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
  });
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
