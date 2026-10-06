// Asking a subcommand for help succeeds: it prints the usage and exits 0
// without a terminal, a project, or a framework checkout. `fleury run --help`
// used to exit 64, and `fleury shell --help` failed its terminal check before
// it read its arguments.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.absolute.path;

  // `create --help` has its own test beside the create command's.
  for (final (subcommand, usage) in const [
    ('run', 'usage: fleury run'),
    ('shell', 'usage: fleury shell'),
    ('serve', 'fleury serve [--port=<n>]'),
    ('diagnose', 'fleury diagnose [--json]'),
  ]) {
    test('fleury $subcommand --help prints its usage and succeeds', () async {
      // Process.run hands the child a pipe for stdin, not a terminal.
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=$packageRoot/.dart_tool/package_config.json',
        '$packageRoot/bin/fleury.dart',
        subcommand,
        '--help',
      ]);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      expect('${result.stdout}${result.stderr}', contains(usage));
    });
  }
}
