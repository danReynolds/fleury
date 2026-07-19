import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String packageRoot;
  late String repoRoot;

  setUpAll(() {
    packageRoot = Directory.current.absolute.path;
    repoRoot = _findRepoRoot(Directory.current).path;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fleury_create_cli_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('help documents the editor and dependency controls', () async {
    final result = await _runCreate(packageRoot, tempDir, const ['--help']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('fleury create <directory>'));
    expect(result.stdout, contains('--no-editor-config'));
    expect(result.stdout, contains('--dependency-source=<kind>'));
  });

  test('creates a complete app and the minimal VS Code F5 contract', () async {
    final target = Directory('${tempDir.path}/my_app');
    final result = await _runCreate(packageRoot, tempDir, [
      target.path,
      '--no-pub',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      _relativeFiles(target),
      equals(const <String>[
        '.gitignore',
        '.vscode/launch.json',
        '.vscode/settings.json',
        'README.md',
        'analysis_options.yaml',
        'bin/run_app.dart',
        'lib/app.dart',
        'pubspec.yaml',
        'test/app_test.dart',
      ]),
    );

    final launch = _jsonObject(
      File('${target.path}/.vscode/launch.json').readAsStringSync(),
    );
    final configurations = launch['configurations'] as List<Object?>;
    expect(configurations, hasLength(1));
    final configuration = configurations.single as Map<String, Object?>;
    expect(configuration, <String, Object?>{
      'name': 'Fleury',
      'type': 'dart',
      'request': 'launch',
      'program': 'bin/run_app.dart',
      'console': 'terminal',
    });
    expect(
      File('${target.path}/${configuration['program']}').existsSync(),
      isTrue,
    );
    expect(configuration, isNot(contains('toolArgs')));

    final settings = _jsonObject(
      File('${target.path}/.vscode/settings.json').readAsStringSync(),
    );
    // Reload-on-save is deliberately part of the scaffold contract: without a
    // trigger, F5 + edit + save leaves the terminal unchanged and hot reload
    // looks broken (the Flutter muscle-memory expectation is save-to-reload).
    // `allIfDirty` only fires during a debug session, and being a workspace
    // setting it is a one-line delete to opt out.
    expect(settings, <String, Object?>{
      'dart.cliConsole': 'terminal',
      'dart.hotReloadOnSave': 'allIfDirty',
    });
    expect(settings, isNot(contains('editor.formatOnSave')));
    expect(settings, isNot(contains('dart.flutterHotReloadOnSave')));

    final pubspec = File('${target.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('name: my_app'));
    for (final package in const <String>[
      'fleury',
      'fleury_widgets',
      'fleury_test',
    ]) {
      final packagePubspec = File(
        '$repoRoot/packages/$package/pubspec.yaml',
      ).readAsStringSync();
      final version = _topLevelScalar(packagePubspec, 'version');
      expect(
        pubspec,
        contains('$package: ^$version'),
        reason: 'the scaffold constraint must track packages/$package',
      );
    }
    final frameworkPubspec = File(
      '$repoRoot/packages/fleury/pubspec.yaml',
    ).readAsStringSync();
    expect(
      _indentedScalar(pubspec, 'sdk'),
      _indentedScalar(frameworkPubspec, 'sdk'),
      reason: 'the generated SDK floor must track the framework SDK floor',
    );
    expect(
      File('${target.path}/bin/run_app.dart').readAsStringSync(),
      contains('TerminalMode(mouse: true)'),
    );
  });

  test('--no-editor-config omits every editor-specific file', () async {
    final target = Directory('${tempDir.path}/plain_app');
    final result = await _runCreate(packageRoot, tempDir, [
      target.path,
      '--no-pub',
      '--no-editor-config',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(Directory('${target.path}/.vscode').existsSync(), isFalse);
    expect(_relativeFiles(target), isNot(contains(startsWith('.vscode/'))));
    expect(result.stdout, contains('dart run bin/run_app.dart'));
    final readme = File('${target.path}/README.md').readAsStringSync();
    expect(readme, contains('interactive terminal'));
    expect(readme, isNot(contains('F5')));
    expect(readme, isNot(contains('VS Code')));
  });

  test('supports the truthful pre-publication Git dependency source', () async {
    final target = Directory('${tempDir.path}/git_app');
    final result = await _runCreate(packageRoot, tempDir, [
      target.path,
      '--no-pub',
      '--dependency-source=git',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final pubspec = File('${target.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('url: https://github.com/danReynolds/fleury.git'));
    expect(pubspec, contains('path: packages/fleury_widgets'));
    expect(pubspec, contains('path: packages/fleury_test'));
    expect(pubspec, contains('dependency_overrides:'));
  });

  test('rejects names that would make the app depend on itself', () async {
    for (final name in const <String>{
      'fleury',
      'fleury_widgets',
      'fleury_test',
      'lints',
      'test',
    }) {
      final target = Directory('${tempDir.path}/self_dependency_$name');
      final result = await _runCreate(packageRoot, tempDir, [
        target.path,
        '--project-name=$name',
        '--no-pub',
      ]);

      expect(result.exitCode, 2, reason: name);
      expect(result.stderr, contains('depends on the package "$name"'));
      expect(target.existsSync(), isFalse, reason: name);
    }
  });

  test('disambiguates a generated FleuryApp root class', () async {
    final target = Directory('${tempDir.path}/fleury_app_project');
    final result = await _runCreate(packageRoot, tempDir, [
      target.path,
      '--project-name=fleury_app',
      '--no-pub',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final app = File('${target.path}/lib/app.dart').readAsStringSync();
    final entrypoint = File(
      '${target.path}/bin/run_app.dart',
    ).readAsStringSync();
    expect(app, contains('class FleuryApplication extends StatefulWidget'));
    expect(app, contains('return FleuryApp('));
    expect(entrypoint, contains('const FleuryApplication()'));
  });

  test('validates all inputs before writing project files', () async {
    final missing = await _runCreate(packageRoot, tempDir, const ['--no-pub']);
    expect(missing.exitCode, 2);
    expect(missing.stderr, contains('missing project directory'));

    final invalidTarget = Directory('${tempDir.path}/Not-A-Package');
    final invalid = await _runCreate(packageRoot, tempDir, [
      invalidTarget.path,
      '--no-pub',
    ]);
    expect(invalid.exitCode, 2);
    expect(invalid.stderr, contains('not a valid Dart package name'));
    expect(invalidTarget.existsSync(), isFalse);

    for (final keyword in const <String>['extension', 'interface', 'mixin']) {
      final keywordTarget = Directory('${tempDir.path}/$keyword');
      final keywordResult = await _runCreate(packageRoot, tempDir, [
        keywordTarget.path,
        '--no-pub',
      ]);
      expect(keywordResult.exitCode, 2, reason: keyword);
      expect(keywordResult.stderr, contains('reserved Dart word'));
      expect(keywordTarget.existsSync(), isFalse);
    }

    final unknownTarget = Directory('${tempDir.path}/unknown_app');
    final unknown = await _runCreate(packageRoot, tempDir, [
      unknownTarget.path,
      '--no-pub',
      '--surprise',
    ]);
    expect(unknown.exitCode, 2);
    expect(unknown.stderr, contains('unknown option'));
    expect(unknownTarget.existsSync(), isFalse);

    final nonEmpty = Directory('${tempDir.path}/existing_app')..createSync();
    final marker = File('${nonEmpty.path}/keep.txt')..writeAsStringSync('mine');
    final occupied = await _runCreate(packageRoot, tempDir, [
      nonEmpty.path,
      '--no-pub',
    ]);
    expect(occupied.exitCode, 2);
    expect(occupied.stderr, contains('is not empty'));
    expect(marker.readAsStringSync(), 'mine');
    expect(_relativeFiles(nonEmpty), <String>['keep.txt']);

    final fileTarget = File('${tempDir.path}/file_app')
      ..writeAsStringSync('mine');
    final fileResult = await _runCreate(packageRoot, tempDir, [
      fileTarget.path,
      '--no-pub',
    ]);
    expect(fileResult.exitCode, 2);
    expect(fileResult.stderr, contains('is not a directory'));
    expect(fileTarget.readAsStringSync(), 'mine');

    if (!Platform.isWindows) {
      final linkTarget = Link('${tempDir.path}/linked_app')
        ..createSync(nonEmpty.path);
      final linkResult = await _runCreate(packageRoot, tempDir, [
        linkTarget.path,
        '--project-name=linked_app',
        '--no-pub',
      ]);
      expect(linkResult.exitCode, 2);
      expect(linkResult.stderr, contains('is not a directory'));
      expect(linkTarget.targetSync(), nonEmpty.path);
    }
  });

  test('--project-name supports a differently named destination', () async {
    final target = Directory('${tempDir.path}/My Fleury App');
    final result = await _runCreate(packageRoot, tempDir, [
      target.path,
      '--project-name=my_fleury_app',
      '--description=A focused terminal app',
      '--no-pub',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final pubspec = File('${target.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('name: my_fleury_app'));
    expect(pubspec, contains('description: "A focused terminal app"'));
    expect(
      File('${target.path}/lib/app.dart').readAsStringSync(),
      contains('class MyFleuryApp extends StatefulWidget'),
    );
    final expectedPath = Platform.isWindows
        ? '"${target.path}"'
        : "'${target.path}'";
    expect(result.stdout, contains('cd $expectedPath'));
  });
}

Future<ProcessResult> _runCreate(
  String packageRoot,
  Directory workingDirectory,
  List<String> args,
) {
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    '$packageRoot/bin/fleury.dart',
    'create',
    ...args,
  ], workingDirectory: workingDirectory.path);
}

List<String> _relativeFiles(Directory root) {
  final prefix = '${root.absolute.path}${Platform.pathSeparator}';
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map(
            (file) => file.absolute.path
                .substring(prefix.length)
                .replaceAll(Platform.pathSeparator, '/'),
          )
          .toList()
        ..sort();
  return files;
}

Map<String, Object?> _jsonObject(String source) =>
    Map<String, Object?>.from(jsonDecode(source) as Map);

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/tool/fleury_dev.dart').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find repo root from ${start.path}.');
    }
    current = parent;
  }
}

String _topLevelScalar(String yaml, String key) {
  final match = RegExp('^$key: (.+)\$', multiLine: true).firstMatch(yaml);
  if (match == null) throw StateError('Missing top-level $key');
  return match.group(1)!.trim();
}

String _indentedScalar(String yaml, String key) {
  final match = RegExp('^  $key: (.+)\$', multiLine: true).firstMatch(yaml);
  if (match == null) throw StateError('Missing indented $key');
  return match.group(1)!.trim();
}
