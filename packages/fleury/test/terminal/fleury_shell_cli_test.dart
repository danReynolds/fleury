import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'shell refuses a non-tty stdin with a clear error before binding a socket',
    () async {
      // `Process.run` gives the child a piped (non-tty) stdin. Without the
      // guard, `fleury shell` bound the socket, then StdinException escaped
      // _runSession's raw-mode setup on app-attach and killed the shell with a
      // stale .fleury/handle + shell.sock left behind. The guard now refuses up
      // front — checked before the stdout guard so a non-tty stdin is named
      // even when stdout is redirected too.
      final tempDir = Directory.systemTemp.createTempSync('fleury_shell_cli_');
      try {
        final result = await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          '${Directory.current.path}/bin/fleury.dart',
          'shell',
        ], workingDirectory: tempDir.path);

        expect(
          result.exitCode,
          2,
          reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
        );
        expect(
          result.stderr.toString(),
          contains('stdin is not a terminal'),
        );
        // The refusal happens before the socket bind, so no session artifacts
        // are left behind.
        expect(Directory('${tempDir.path}/.fleury').existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
