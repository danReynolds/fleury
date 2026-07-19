import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'SIGTERM exits shell conventionally and removes discovery state',
    () async {
      final packageRoot = Directory.current.absolute;
      final repoRoot = _findRepoRoot(packageRoot);
      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_shell_sigterm_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outBase = '${tempDir.path}/shell_sigterm';

      final capture = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        '${repoRoot.path}/profiling/capture_pty.dart',
        '--out',
        outBase,
        '--timeout',
        '25',
        '--terminate-after-output-ms',
        '750',
        '--allow-exit-code',
        '143',
        '--',
        Platform.resolvedExecutable,
        'run',
        '${packageRoot.path}/bin/fleury.dart',
        'shell',
      ], workingDirectory: tempDir.path);

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
      expect(metadata['timedOut'], isFalse);
      expect(metadata['exitCode'], 143);
      expect(capturedOutput, contains('fleury shell ready'));

      final socketMatch = RegExp(
        r"FLEURY_HANDLE='([^']+)' dart run bin/run_app\.dart",
      ).firstMatch(capturedOutput);
      expect(socketMatch, isNotNull);
      final socketPath = socketMatch!.group(1)!;
      final handleFile = File('${tempDir.path}/.fleury/handle');
      expect(handleFile.existsSync(), isFalse);
      expect(File(socketPath).existsSync(), isFalse);
      expect(File(socketPath).parent.existsSync(), isFalse);
    },
    skip: Platform.isWindows
        ? 'The PTY harness and Unix-domain shell are POSIX-only.'
        : null,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(seconds: 45)),
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
