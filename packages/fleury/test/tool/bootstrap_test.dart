import 'dart:io';

import 'package:test/test.dart';

const _companions = [
  'fleury_test',
  'fleury_widgets',
  'fleury_web',
  'fleury_mcp',
];

void main() {
  test(
    'bootstrap dry-run explains missing overrides without creating them',
    () async {
      final fixture = _bootstrapFixture();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final result = await _bootstrap(fixture, dryRun: true);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      for (final name in _companions) {
        final package = '${fixture.path}/packages/$name';
        expect(File('$package/pubspec_overrides.yaml').existsSync(), isFalse);
        expect(Directory('$package/.dart_tool').existsSync(), isFalse);
        expect(
          result.stdout.toString().replaceAll('\r\n', '\n'),
          contains(
            '(packages/$name) Copy pubspec_overrides.yaml.template '
            'to pubspec_overrides.yaml\n(packages/$name) dart pub get',
          ),
        );
      }
    },
  );

  test(
    'bootstrap resolves sibling templates and preserves customized overrides',
    () async {
      final fixture = _bootstrapFixture();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final custom = File(
        '${fixture.path}/packages/fleury_mcp/pubspec_overrides.yaml',
      );
      const customContent =
          '# Keep my local choices.\ndependency_overrides:\n'
          '  fleury:\n    path: ../custom_fleury\n';
      _minimalPackage(
        Directory('${fixture.path}/packages/custom_fleury'),
        'fleury',
      );
      custom.writeAsStringSync(customContent);

      final result = await _bootstrap(fixture);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(custom.readAsStringSync(), customContent);
      for (final name in _companions) {
        final package = '${fixture.path}/packages/$name';
        if (name != 'fleury_mcp') {
          expect(
            File('$package/pubspec_overrides.yaml').readAsStringSync(),
            File('$package/pubspec_overrides.yaml.template').readAsStringSync(),
          );
        }
        // pub get must run after copying: each package actually resolves the
        // sibling dependency, including the developer's custom source.
        final config = File(
          '$package/.dart_tool/package_config.json',
        ).readAsStringSync();
        expect(
          config,
          contains(name == 'fleury_mcp' ? 'custom_fleury' : '../../fleury'),
        );
      }
      final repeated = await _bootstrap(fixture, dryRun: true);
      expect(repeated.exitCode, 0, reason: repeated.stderr.toString());
      expect(repeated.stdout, isNot(contains('Copy pubspec_overrides')));
      expect(custom.readAsStringSync(), customContent);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'Pub excludes local override templates and generated files from packages',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'fleury_pub_template_',
      );
      addTearDown(() => fixture.deleteSync(recursive: true));
      _minimalPackage(fixture, 'fleury_archive_fixture');
      final commonRules = File('../fleury_test/.pubignore').readAsStringSync();
      for (final name in _companions) {
        expect(
          File('../$name/.pubignore').readAsStringSync(),
          startsWith(commonRules),
          reason: '$name must exclude local overrides and build files',
        );
      }
      File('../fleury_web/.pubignore').copySync('${fixture.path}/.pubignore');
      File(
        '${fixture.path}/pubspec_overrides.yaml.template',
      ).writeAsStringSync('not valid YAML: [');
      File(
        '${fixture.path}/pubspec_overrides.yaml',
      ).writeAsStringSync('dependency_overrides: {}\n');
      File(
        '${fixture.path}/README.md',
      ).writeAsStringSync('# Archive fixture\nTests publication exclusions.\n');
      File(
        '${fixture.path}/CHANGELOG.md',
      ).writeAsStringSync('## 0.1.0\nInitial fixture.\n');
      File('LICENSE').copySync('${fixture.path}/LICENSE');
      final generated = File('${fixture.path}/build/should_not_ship.dart');
      generated.parent.createSync();
      generated.writeAsStringSync('// Generated file.\n');
      File(
        '${fixture.path}/.flutter-plugins-dependencies',
      ).writeAsStringSync('{}\n');
      Directory('${fixture.path}/web').createSync();
      File(
        '${fixture.path}/web/demo.dart',
      ).writeAsStringSync('void main() {}\n');
      for (final extension in ['js', 'js.deps', 'js.map']) {
        File(
          '${fixture.path}/web/demo.dart.$extension',
        ).writeAsStringSync('// Generated output.\n');
      }
      final result = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'publish',
        '--dry-run',
      ], workingDirectory: fixture.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final output = result.stdout.toString();
      expect(
        output,
        contains('Validating package'),
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(output, contains('fleury_archive_fixture.dart'));
      expect(output, contains('demo.dart'));
      expect(output, isNot(contains('demo.dart.js')));
      expect(output, isNot(contains('pubspec_overrides.yaml.template')));
      expect(output, isNot(contains('should_not_ship.dart')));
      expect(output, isNot(contains('pubspec.lock')));
      expect(output, isNot(contains('.flutter-plugins-dependencies')));
    },
    tags: const ['integration'],
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Directory _bootstrapFixture() {
  final fixture = Directory.systemTemp.createTempSync('fleury_bootstrap_');
  final tool = File('${fixture.path}/tool/fleury_dev.dart');
  tool.parent.createSync(recursive: true);
  File('../../tool/fleury_dev.dart').copySync(tool.path);
  for (final name in [
    'fleury',
    ..._companions,
    'fleury_git',
    'fleury_example_console',
    'storybook',
    'samples',
  ]) {
    _minimalPackage(Directory('${fixture.path}/packages/$name'), name);
  }
  _minimalPackage(Directory('${fixture.path}/profiling'), 'profiling');
  _minimalPackage(
    Directory('${fixture.path}/website/examples'),
    'web_examples',
  );
  for (final name in _companions) {
    File('../$name/pubspec_overrides.yaml.template').copySync(
      '${fixture.path}/packages/$name/pubspec_overrides.yaml.template',
    );
  }
  return fixture;
}

void _minimalPackage(Directory directory, String name) {
  directory.createSync(recursive: true);
  File('${directory.path}/pubspec.yaml').writeAsStringSync(
    'name: $name\nversion: 0.1.0\n'
    'description: A disposable package for Fleury contributor tooling tests.\n'
    'repository: https://github.com/danReynolds/fleury\n'
    'environment:\n  sdk: ">=3.10.4 <4.0.0"\n',
  );
  final library = File('${directory.path}/lib/$name.dart');
  library.parent.createSync();
  library.writeAsStringSync('// Fixture.\n');
}

Future<ProcessResult> _bootstrap(
  Directory fixture, {
  bool dryRun = false,
}) => Process.run(
  Platform.resolvedExecutable,
  [
    '${fixture.path}/tool/fleury_dev.dart',
    if (dryRun) '--dry-run',
    'bootstrap',
  ],
  workingDirectory: fixture.path,
  environment: {
    // Use this test's SDK for nested pub invocations on every platform.
    'PATH':
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.isWindows ? ';' : ':'}${Platform.environment['PATH'] ?? ''}',
    // These fixtures only resolve local paths. Any hosted dependency is
    // a test setup error and must not silently access the real registry.
    'PUB_HOSTED_URL': 'http://127.0.0.1:1',
  },
);
