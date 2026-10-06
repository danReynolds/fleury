// The executable's suggestions get pasted into terminals, and it cannot tell
// which launcher started it: `dart run fleury_mcp` from an app's dev
// dependency, or a bare `fleury_mcp` after a global or source activation.
// Neither form works everywhere, so a suggestion names only what follows
// `--`, and the usage explains both launchers.
//
// Tagged `integration` (per dart_test.yaml): each test starts the executable.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('usage explains both launchers', () async {
    final help = await _fleuryMcp(const ['--help']);
    expect(help.exitCode, 0, reason: '${help.stderr}');
    expect(
      help.stderr,
      contains(
        'From an app that has fleury_mcp as a dev dependency, start it with '
        '`dart run fleury_mcp`;',
      ),
    );
    expect(
      help.stderr,
      contains('once it is globally activated, `fleury_mcp` works alone.'),
    );
  });

  test('the missing-command error names only the app command', () async {
    final missing = await _fleuryMcp(const []);
    expect(missing.exitCode, 2, reason: '${missing.stderr}');
    expect(missing.stderr, contains('e.g. `-- dart run bin/run_app.dart`.'));
    expect(missing.stderr, isNot(contains('fleury_mcp -- ')));
  });

  test('the cold-start hint names only the compiled app command', () async {
    // A missing script makes the app exit before it connects, so the server
    // fails fast after printing the hint for a JIT launch.
    final result = await _fleuryMcp([
      '--',
      Platform.resolvedExecutable,
      'missing_app.dart',
    ]);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    expect(
      result.stderr,
      contains('give `./my_app` as the app command after `--`.'),
    );
    expect(result.stderr, isNot(contains('fleury_mcp -- ./my_app')));
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
