import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('embedded version agrees with the published package version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: ([^\r\n]+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(fleuryVersion, version);
  });

  test(
    'source and standalone CLIs report their own version from another directory',
    () async {
      final packageRoot = Directory.current.absolute.path;
      final temp = Directory.systemTemp.createTempSync('fleury_cli_version_');
      addTearDown(() => temp.deleteSync(recursive: true));
      // A nearby app manifest must never replace the CLI's own version.
      File(
        '${temp.path}/pubspec.yaml',
      ).writeAsStringSync('name: unrelated_app\nversion: 99.9.9\n');

      Future<void> check(String executable, List<String> prefix) async {
        Future<ProcessResult> run(List<String> args) => Process.run(
          executable,
          [...prefix, ...args],
          workingDirectory: temp.path,
        );
        final version = await run(const ['--version']);
        expect(version.exitCode, 0, reason: version.stderr.toString());
        expect(version.stdout.toString().trim(), 'fleury $fleuryVersion');

        final text = await run(const ['diagnose']);
        expect(text.exitCode, 0, reason: text.stderr.toString());
        expect(text.stdout, contains('| fleury | $fleuryVersion |'));

        final json = await run(const ['diagnose', '--json']);
        expect(json.exitCode, 0, reason: json.stderr.toString());
        final diagnosis =
            jsonDecode(json.stdout as String) as Map<String, Object?>;
        expect(diagnosis['fleuryVersion'], fleuryVersion);
      }

      await check(Platform.resolvedExecutable, [
        '--packages=$packageRoot/.dart_tool/package_config.json',
        '$packageRoot/bin/fleury.dart',
      ]);

      final executable =
          '${temp.path}/fleury${Platform.isWindows ? '.exe' : ''}';
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        '$packageRoot/bin/fleury.dart',
        '-o',
        executable,
      ], workingDirectory: packageRoot);
      expect(
        compile.exitCode,
        0,
        reason: 'stdout:\n${compile.stdout}\nstderr:\n${compile.stderr}',
      );
      await check(executable, const []);
    },
    tags: const ['integration'],
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
