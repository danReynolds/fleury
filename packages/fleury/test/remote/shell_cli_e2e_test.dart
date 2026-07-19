import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final skipPty = Platform.isWindows
      ? 'fleury shell and the PTY harness use POSIX Unix sockets/openpty.'
      : null;

  test(
    'real CLI shell renders a nested app and cleans up',
    () async {
      final packageRoot = Directory.current.absolute;
      final repoRoot = _findRepoRoot(packageRoot);
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_shell_cli_e2e_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final projectDir = Directory('${tempDir.path}/project with spaces')
        ..createSync();
      final outBase = '${tempDir.path}/shell';

      final capture = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        '${repoRoot.path}/profiling/capture_pty.dart',
        '--out',
        outBase,
        '--timeout',
        '35',
        '--cols',
        '80',
        '--rows',
        '24',
        '--input-hex',
        '0d',
        '--input-after-output-ms',
        '3000',
        '--',
        Platform.resolvedExecutable,
        '${packageRoot.path}/test/fixtures/shell_cli_e2e_runner.dart',
        packageRoot.path,
        projectDir.path,
      ], workingDirectory: repoRoot.path);

      final capturedOutput = File('$outBase.bin').existsSync()
          ? latin1.decode(File('$outBase.bin').readAsBytesSync())
          : '<no PTY capture was written>';
      expect(
        capture.exitCode,
        0,
        reason:
            'stdout:\n${capture.stdout}\nstderr:\n${capture.stderr}'
            '\nPTY output:\n$capturedOutput',
      );

      final metadata =
          jsonDecode(File('$outBase.json').readAsStringSync())
              as Map<String, Object?>;
      final output = capturedOutput;
      expect(metadata['timedOut'], isFalse);
      expect(metadata['exitCode'], 0);
      expect(output, contains('SHELL-CLI-E2E-FIRST-FRAME'));
      expect(
        output,
        matches(RegExp(r'\x1B\[[0-9]+;[0-9]+HINPUT-RECEIVED')),
        reason: 'Enter should flow through shell and repaint the changed cells',
      );
      expect(output, contains('SHELL-CLI-E2E-ABSOLUTE-HANDLE'));
      expect(output, contains('SHELL-CLI-E2E-DUPLICATE-REFUSED'));
      expect(output, contains('SHELL-CLI-E2E-CLEANUP'));
      final socketMatch = RegExp(
        r"FLEURY_HANDLE='([^']+)' dart run bin/run_app\.dart",
      ).firstMatch(output);
      expect(socketMatch, isNotNull);
      final socketPath = socketMatch!.group(1)!;
      expect(
        output,
        contains("FLEURY_HANDLE='$socketPath' dart run bin/run_app.dart"),
      );
      expect(output, contains('\x1B[?1049h'));
      expect(output, contains('\x1B[?1049l'));
      expect(
        output.lastIndexOf('\x1B[?1049l'),
        greaterThan(output.indexOf('\x1B[?1049h')),
      );
      expect(File('${projectDir.path}/.fleury/handle').existsSync(), isFalse);
      expect(File(socketPath).existsSync(), isFalse);
      expect(File(socketPath).parent.existsSync(), isFalse);
    },
    skip: skipPty,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'CLI shell rejects non-terminal stdin before creating a handle',
    () async {
      final packageRoot = Directory.current.absolute;
      final repoRoot = _findRepoRoot(packageRoot);
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_shell_no_stdin_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outBase = '${tempDir.path}/shell_no_stdin';

      final capture = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        '${repoRoot.path}/profiling/capture_pty.dart',
        '--out',
        outBase,
        '--timeout',
        '15',
        '--allow-exit-code',
        '2',
        '--',
        '/bin/sh',
        '-c',
        'exec "\$1" run "\$2" shell </dev/null',
        'sh',
        Platform.resolvedExecutable,
        '${packageRoot.path}/bin/fleury.dart',
      ], workingDirectory: tempDir.path);

      expect(
        capture.exitCode,
        0,
        reason: 'stdout:\n${capture.stdout}\nstderr:\n${capture.stderr}',
      );

      final metadata =
          jsonDecode(File('$outBase.json').readAsStringSync())
              as Map<String, Object?>;
      final output = latin1.decode(File('$outBase.bin').readAsBytesSync());
      expect(metadata['exitCode'], 2);
      expect(output, contains('stdin is not a terminal'));
      expect(File('${tempDir.path}/.fleury/handle').existsSync(), isFalse);
    },
    skip: skipPty,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 1)),
  );
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
