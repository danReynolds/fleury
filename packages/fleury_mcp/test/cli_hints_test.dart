// The executable's suggestions get pasted into terminals. The README installs
// fleury_mcp as a dev dependency, which provides `dart run fleury_mcp`: a bare
// `fleury_mcp` exists only after a global or source activation. Every command
// the executable suggests therefore uses the `dart run` form.
//
// Tagged `integration` (per dart_test.yaml): each test starts the executable.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('usage and the missing-command error suggest dart run', () async {
    final help = await _fleuryMcp(const ['--help']);
    expect(help.exitCode, 0, reason: '${help.stderr}');
    expect(
      help.stderr,
      contains('Example: dart run fleury_mcp -- dart run bin/run_app.dart'),
    );

    final missing = await _fleuryMcp(const []);
    expect(missing.exitCode, 2, reason: '${missing.stderr}');
    expect(
      missing.stderr,
      contains('`dart run fleury_mcp -- dart run bin/run_app.dart`'),
    );
  });

  test('the cold-start hint runs a compiled app through dart run', () async {
    // A missing script makes the app exit before it connects, so the server
    // fails fast after printing the hint for a JIT launch.
    final result = await _fleuryMcp([
      '--',
      Platform.resolvedExecutable,
      'missing_app.dart',
    ]);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    expect(result.stderr, contains('`dart run fleury_mcp -- ./my_app`'));
    expect(result.stderr, isNot(contains('run `fleury_mcp --')));
  });
}

Future<ProcessResult> _fleuryMcp(List<String> args) {
  final package = Directory.current.absolute.path;
  return Process.run(Platform.resolvedExecutable, [
    '--packages=$package/.dart_tool/package_config.json',
    '$package/bin/fleury_mcp.dart',
    ...args,
  ]);
}
