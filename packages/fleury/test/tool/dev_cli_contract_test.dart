import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('fleury CLI discovery', () {
    test('top-level help separates app and framework commands', () async {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/fleury.dart',
        '--help',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final output = '${result.stdout}${result.stderr}';
      expect(output, contains('App developer commands:'));
      expect(output, contains('Framework checkout commands:'));
      expect(output, contains('fleury dev demo'));
      expect(output, contains('fleury dev storybook'));
      expect(output, contains('fleury benchmark wire sb6 --help'));
    });
  });

  group('repo-local development launcher', () {
    test('help promotes canonical command groups', () async {
      final result = await _runTool(['--help']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final output = result.stdout.toString();
      expect(output, contains('Primary contributor commands:'));
      expect(output, contains('Evidence and release commands:'));
      expect(output, contains('Maintenance commands:'));
      expect(output, contains('Legacy benchmark aliases:'));
      expect(output, contains('storybook'));
      expect(output, contains('benchmark manifest --json'));
      expect(output, contains('Prefer `benchmark manifest [options]`'));
    });

    test('list exposes runnable demo names', () async {
      final result = await _runTool(['list']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Core demos:'));
      expect(result.stdout, contains('Widget demos:'));
      expect(result.stdout, contains('Demo app:'));
      expect(result.stdout, contains('Storybook:'));
      expect(
        result.stdout,
        contains(
          'demo -> packages/fleury_example_console/bin/'
          'fleury_example_console.dart',
        ),
      );
      expect(
        result.stdout,
        contains('storybook -> packages/storybook/bin/storybook.dart'),
      );
    });

    test(
      'dry-run routes demo and quick checks through current files',
      () async {
        final demo = await _runTool(['--dry-run', 'demo']);
        expect(demo.exitCode, 0, reason: demo.stderr.toString());
        expect(
          demo.stdout,
          contains('(packages/fleury_example_console) dart run bin/'),
        );

        final storybook = await _runTool(['--dry-run', 'storybook']);
        expect(storybook.exitCode, 0, reason: storybook.stderr.toString());
        expect(
          storybook.stdout,
          contains('(packages/storybook) dart run bin/storybook.dart'),
        );

        final storybookVerify = await _runTool([
          '--dry-run',
          'storybook',
          'verify',
          '--json',
        ]);
        expect(
          storybookVerify.exitCode,
          0,
          reason: storybookVerify.stderr.toString(),
        );
        expect(
          storybookVerify.stdout,
          contains(
            '(packages/storybook) dart run bin/storybook.dart verify --json',
          ),
        );

        final check = await _runTool(['--dry-run', 'check', '--quick']);
        expect(check.exitCode, 0, reason: check.stderr.toString());
        expect(check.stdout, contains('(packages/fleury) dart analyze'));
        expect(
          check.stdout,
          contains(
            '(packages/fleury_example_console) dart test '
            'test/demo_console_test.dart',
          ),
        );
        expect(check.stdout, contains('(packages/storybook) dart analyze'));
        expect(check.stdout, contains('(packages/storybook) dart test'));
        expect(check.stdout, isNot(contains('proof_console_test.dart')));
      },
    );
  });

  group('benchmark command discovery', () {
    test('help uses nested benchmark commands as canonical', () async {
      final result = await _runTool(['benchmark', '--help']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final output = result.stdout.toString();
      expect(output, contains('manifest [options]'));
      expect(output, contains('result [options]'));
      expect(output, contains('variance [options]'));
      expect(output, contains('fleury benchmark list'));
      expect(output, isNot(contains('benchmark-manifest')));
    });

    test('legacy benchmark aliases remain available', () async {
      final result = await _runTool(['benchmark-manifest', '--help']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout,
        contains('Usage: dart tool/fleury_dev.dart benchmark-manifest'),
      );
    });

    test('wire peer discovery exposes SB.10 demo-app peers', () async {
      final result = await _runTool([
        'benchmark',
        'wire',
        'sb10',
        '--list-peers',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final catalog = jsonDecode(result.stdout.toString());
      expect(catalog, isA<Map<String, Object?>>());
      final map = catalog as Map<String, Object?>;
      expect(map['name'], 'SB.10 Demo-App Journey');
      expect(map['command'], [
        'fleury',
        'benchmark',
        'wire',
        'sb10',
        '--runs=3',
      ]);
      final peers = map['peers'] as List<Object?>;
      expect(peers.map((peer) => (peer as Map<String, Object?>)['id']), [
        'textual',
        'bubbletea',
        'ink',
      ]);
    });
  });
}

Future<ProcessResult> _runTool(List<String> args) {
  return Process.run(Platform.resolvedExecutable, <String>[
    '../../tool/fleury_dev.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}
