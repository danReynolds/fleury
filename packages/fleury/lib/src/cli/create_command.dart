import 'dart:convert';
import 'dart:io';

import 'dart_sdk.dart';

const _fleuryVersion = '^0.1.0';
const _lintsVersion = '^6.0.0';
const _testVersion = '^1.26.3';
const _repositoryUrl = 'https://github.com/danReynolds/fleury.git';

/// Generates a new Fleury application project.
///
/// Kept outside the executable entrypoint so the scaffold contract remains a
/// small, reviewable unit even as the public CLI grows.
Future<int> runCreateCommand(List<String> args) async {
  final parsed = _CreateOptions.parse(args);
  if (parsed case _CreateParseError(:final message)) {
    stderr.writeln('fleury create: $message');
    stderr.writeln('Run `fleury create --help` for usage.');
    return 2;
  }

  final options = parsed as _CreateOptions;
  if (options.help) {
    _printCreateUsage();
    return 0;
  }

  final requestedPath = options.targetPath;
  if (requestedPath == null) {
    stderr.writeln('fleury create: missing project directory.');
    stderr.writeln('Run `fleury create --help` for usage.');
    return 2;
  }

  final target = Directory(requestedPath).absolute;
  final targetType = FileSystemEntity.typeSync(target.path, followLinks: false);
  if (targetType == FileSystemEntityType.file ||
      targetType == FileSystemEntityType.link) {
    stderr.writeln(
      'fleury create: ${target.path} exists and is not a directory.',
    );
    return 2;
  }
  if (target.existsSync() && target.listSync(followLinks: false).isNotEmpty) {
    stderr.writeln(
      'fleury create: ${target.path} is not empty; choose an empty directory.',
    );
    return 2;
  }

  final projectName = options.projectName ?? _basename(target.path);
  final nameError = _validateProjectName(projectName);
  if (nameError != null) {
    stderr.writeln('fleury create: $nameError');
    if (options.projectName == null) {
      stderr.writeln(
        'Choose a valid directory name or pass '
        '`--project-name=<name>`.',
      );
    }
    return 2;
  }

  final description =
      options.description ?? 'A terminal application built with Fleury.';
  final files = _projectFiles(
    projectName: projectName,
    description: description,
    includeEditorConfig: options.includeEditorConfig,
    dependencySource: options.dependencySource,
  );

  stdout.writeln('Creating $projectName in ${target.path}...');
  try {
    target.createSync(recursive: true);
    for (final entry in files.entries) {
      final file = File('${target.path}${Platform.pathSeparator}${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      stdout.writeln('  ${entry.key}');
    }
  } on FileSystemException catch (error) {
    stderr.writeln('fleury create: could not write the project: $error');
    return 1;
  }

  if (options.runPubGet) {
    stdout.writeln('Resolving dependencies...');
    final Process process;
    try {
      process = await Process.start(
        dartSdkExecutable,
        const <String>['pub', 'get'],
        workingDirectory: target.path,
        mode: ProcessStartMode.inheritStdio,
      );
    } on ProcessException catch (error) {
      stderr.writeln(
        'fleury create: could not run `dart pub get`: ${error.message}',
      );
      stderr.writeln(
        'Install the Dart SDK and ensure `dart` is on PATH, or rerun with '
        '`--no-pub`.',
      );
      return 1;
    }
    final code = await process.exitCode;
    if (code != 0) {
      stderr.writeln(
        'fleury create: `dart pub get` failed with exit code $code.',
      );
      stderr.writeln(
        'The project was created; resolve the dependency error and run '
        '`dart pub get` from ${target.path}.',
      );
      if (options.dependencySource == _DependencySource.hosted) {
        stderr.writeln(
          "If the fleury packages aren't on pub.dev yet, scaffold against "
          'the Git checkout instead: rerun with `--dependency-source=git`.',
        );
      }
      return code;
    }
  }

  stdout
    ..writeln('')
    ..writeln('Created $projectName.')
    ..writeln('')
    ..writeln('Next steps:')
    ..writeln('  cd ${_commandPath(_displayPath(requestedPath))}');
  if (!options.runPubGet) {
    stdout.writeln('  dart pub get');
  }
  if (options.includeEditorConfig) {
    stdout
      ..writeln('  code .')
      ..writeln('  Press F5 to run in an interactive terminal.')
      ..writeln('  Edit and save while it runs — hot reload keeps your state.');
  } else {
    stdout.writeln('  dart run bin/run_app.dart');
  }
  return 0;
}

void _printCreateUsage() {
  stdout.writeln('Create a new Fleury application.');
  stdout.writeln('');
  stdout.writeln('Usage: fleury create <directory> [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --project-name=<name>       Dart package name (defaults to directory).',
  );
  stdout.writeln('  --description=<text>        Package description.');
  stdout.writeln('  --dependency-source=<kind>  hosted (default) or git.');
  stdout.writeln(
    '  --no-editor-config          Do not generate the minimal VS Code files.',
  );
  stdout.writeln('  --no-pub                    Skip `dart pub get`.');
  stdout.writeln('  -h, --help                  Show this help.');
}

Map<String, String> _projectFiles({
  required String projectName,
  required String description,
  required bool includeEditorConfig,
  required _DependencySource dependencySource,
}) {
  final baseClassName = _pascalCase(projectName);
  final proposedClassName = baseClassName.endsWith('App')
      ? baseClassName
      : '${baseClassName}App';
  final className = proposedClassName == 'FleuryApp'
      ? 'FleuryApplication'
      : proposedClassName;
  final displayName = _displayName(projectName);
  final files = <String, String>{
    '.gitignore': _gitignore,
    'analysis_options.yaml': _analysisOptions,
    'pubspec.yaml': _pubspec(
      projectName: projectName,
      description: description,
      dependencySource: dependencySource,
    ),
    'README.md': _readme(projectName, includeEditorConfig: includeEditorConfig),
    'lib/app.dart': _appSource(className: className, displayName: displayName),
    'bin/run_app.dart': _entrypointSource(
      projectName: projectName,
      className: className,
    ),
    'test/app_test.dart': _testSource(
      projectName: projectName,
      className: className,
    ),
  };
  if (includeEditorConfig) {
    files['.vscode/launch.json'] = _launchJson;
    files['.vscode/settings.json'] = _settingsJson;
  }
  return files;
}

String _pubspec({
  required String projectName,
  required String description,
  required _DependencySource dependencySource,
}) {
  final dependencies = switch (dependencySource) {
    _DependencySource.hosted =>
      '''
dependencies:
  fleury: $_fleuryVersion
  fleury_widgets: $_fleuryVersion

dev_dependencies:
  fleury_test: $_fleuryVersion
  lints: $_lintsVersion
  test: $_testVersion
''',
    _DependencySource.git =>
      '''
dependencies:
  fleury:
    git:
      url: $_repositoryUrl
      path: packages/fleury
  fleury_widgets:
    git:
      url: $_repositoryUrl
      path: packages/fleury_widgets

dev_dependencies:
  fleury_test:
    git:
      url: $_repositoryUrl
      path: packages/fleury_test
  lints: $_lintsVersion
  test: $_testVersion

dependency_overrides:
  fleury:
    git:
      url: $_repositoryUrl
      path: packages/fleury
''',
  };
  return '''
name: $projectName
description: ${jsonEncode(description)}
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.10.4

$dependencies''';
}

String _appSource({required String className, required String displayName}) =>
    '''
import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

class $className extends StatefulWidget {
  const $className({super.key});

  @override
  State<$className> createState() => _${className}State();
}

class _${className}State extends State<$className> {
  var _count = 0;

  void _increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) {
    return FleuryApp(
      title: ${jsonEncode(displayName)},
      home: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Count: \$_count'),
            const SizedBox(height: 1),
            Button(
              label: 'Increment',
              autofocus: true,
              onPressed: _increment,
            ),
            const SizedBox(height: 1),
            const Text('Press Enter or click the button. Ctrl+C quits.'),
          ],
        ),
      ),
    );
  }
}
''';

String _entrypointSource({
  required String projectName,
  required String className,
}) =>
    '''
import 'package:fleury/fleury.dart';
import 'package:$projectName/app.dart';

void main() => runApp(
  const $className(),
  mode: const TerminalMode(mouse: true),
);
''';

String _testSource({required String projectName, required String className}) =>
    '''
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:$projectName/app.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('Enter increments the counter', (tester) {
    tester.pumpWidget(const $className());

    expect(tester.renderToString(emptyMark: ' '), contains('Count: 0'));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 1'));
  });

  testWidgets('the button is semantic and clickable', (tester) {
    tester.pumpWidget(const $className());
    tester.render();
    final button = tester.semantics().single(
      role: SemanticRole.button,
      label: 'Increment',
      focused: true,
      action: SemanticAction.activate,
    );
    final bounds = button.bounds!;
    final col = bounds.left + bounds.size.cols ~/ 2;
    final row = bounds.top + bounds.size.rows ~/ 2;

    tester.sendMouse(
      MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: col,
        row: row,
      ),
    );
    tester.sendMouse(
      MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: col,
        row: row,
      ),
    );

    expect(tester.renderToString(emptyMark: ' '), contains('Count: 1'));
  });
}
''';

String _readme(String projectName, {required bool includeEditorConfig}) {
  final runLead = includeEditorConfig
      ? 'Press F5 in VS Code, or run directly from an interactive terminal:'
      : 'Run directly from an interactive terminal:';
  final editorNote = includeEditorConfig
      ? '''
Under F5, **saving a changed file hot reloads the running app** — the terminal
updates in place and widget state survives (wired via `dart.hotReloadOnSave` in
`.vscode/settings.json`). A plain `dart run` starts no VM service, so that path
runs without hot reload. The F5 flow requires the official Dart extension
(`Dart-Code.dart-code`); Fleury needs no custom editor extension.
'''
      : '';
  return '''
# $projectName

A terminal application built with [Fleury](https://github.com/danReynolds/fleury).

## Run

$runLead

```sh
dart run bin/run_app.dart
```

Press Enter or click **Increment**. Press Ctrl+C to quit.

$editorNote
## Test

```sh
dart test
```

## The same app, elsewhere

- **In a browser** — `fleury serve --spawn dart run bin/run_app.dart` streams
  this app, unchanged, to a browser tab.
- **Driven by an AI agent** — `fleury_mcp -- dart run bin/run_app.dart` exposes
  the running UI over the Model Context Protocol, so an agent reads and
  operates it by meaning instead of screen-scraping.

Both come from the same widget tree you edit in `lib/app.dart`. Guides, live
widget demos, and the architecture tour:
[danreynolds.github.io/fleury](https://danreynolds.github.io/fleury/).
''';
}

const _gitignore = '''
.dart_tool/
.fleury/
build/
''';

const _analysisOptions = '''
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
''';

const _launchJson = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Fleury",
      "type": "dart",
      "request": "launch",
      "program": "bin/run_app.dart",
      "console": "terminal"
    }
  ]
}
''';

const _settingsJson = '''
{
  "dart.cliConsole": "terminal",
  "dart.hotReloadOnSave": "allIfDirty"
}
''';

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.lastWhere((part) => part.isNotEmpty, orElse: () => '');
}

String _displayPath(String path) => path.isEmpty ? '.' : path;

String _commandPath(String path) {
  if (RegExp(r'^[A-Za-z0-9_./:\\-]+$').hasMatch(path)) return path;
  if (Platform.isWindows) {
    return '"${path.replaceAll('"', '""')}"';
  }
  return "'${path.replaceAll("'", "'\\''")}'";
}

String? _validateProjectName(String name) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    return '"$name" is not a valid Dart package name. Use lowercase '
        'letters, digits, and underscores, beginning with a letter.';
  }
  if (_reservedWords.contains(name)) {
    return '"$name" is a reserved Dart word and cannot be a package name.';
  }
  if (_generatedDependencyNames.contains(name)) {
    return '"$name" cannot be used because every generated Fleury app '
        'depends on the package "$name".';
  }
  return null;
}

String _pascalCase(String name) => name
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

String _displayName(String name) => name
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

const _reservedWords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'inout',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'native',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'out',
  'part',
  'patch',
  'required',
  'rethrow',
  'return',
  'set',
  'show',
  'source',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

const _generatedDependencyNames = <String>{
  'fleury',
  'fleury_widgets',
  'fleury_test',
  'lints',
  'test',
};

enum _DependencySource { hosted, git }

sealed class _CreateParseResult {
  const _CreateParseResult();
}

final class _CreateParseError extends _CreateParseResult {
  const _CreateParseError(this.message);

  final String message;
}

final class _CreateOptions extends _CreateParseResult {
  const _CreateOptions({
    required this.targetPath,
    required this.projectName,
    required this.description,
    required this.includeEditorConfig,
    required this.runPubGet,
    required this.dependencySource,
    required this.help,
  });

  final String? targetPath;
  final String? projectName;
  final String? description;
  final bool includeEditorConfig;
  final bool runPubGet;
  final _DependencySource dependencySource;
  final bool help;

  static _CreateParseResult parse(List<String> args) {
    String? targetPath;
    String? projectName;
    String? description;
    var includeEditorConfig = true;
    var runPubGet = true;
    var dependencySource = _DependencySource.hosted;
    var help = false;

    String? valueAt(int index, String option) {
      if (index + 1 >= args.length || args[index + 1].startsWith('-')) {
        return null;
      }
      return args[index + 1];
    }

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-h' || arg == '--help') {
        help = true;
      } else if (arg == '--no-editor-config') {
        includeEditorConfig = false;
      } else if (arg == '--no-pub') {
        runPubGet = false;
      } else if (arg.startsWith('--project-name=')) {
        projectName = arg.substring('--project-name='.length);
      } else if (arg == '--project-name') {
        final value = valueAt(i, arg);
        if (value == null) {
          return const _CreateParseError('--project-name needs a value.');
        }
        projectName = value;
        i++;
      } else if (arg.startsWith('--description=')) {
        description = arg.substring('--description='.length);
      } else if (arg == '--description') {
        final value = valueAt(i, arg);
        if (value == null) {
          return const _CreateParseError('--description needs a value.');
        }
        description = value;
        i++;
      } else if (arg.startsWith('--dependency-source=')) {
        final value = arg.substring('--dependency-source='.length);
        final parsed = _parseDependencySource(value);
        if (parsed == null) {
          return _CreateParseError(
            'unsupported dependency source "$value"; use hosted or git.',
          );
        }
        dependencySource = parsed;
      } else if (arg == '--dependency-source') {
        final value = valueAt(i, arg);
        if (value == null) {
          return const _CreateParseError('--dependency-source needs a value.');
        }
        final parsed = _parseDependencySource(value);
        if (parsed == null) {
          return _CreateParseError(
            'unsupported dependency source "$value"; use hosted or git.',
          );
        }
        dependencySource = parsed;
        i++;
      } else if (arg.startsWith('-')) {
        return _CreateParseError('unknown option "$arg".');
      } else if (targetPath == null) {
        targetPath = arg;
      } else {
        return _CreateParseError(
          'expected one project directory, got "$targetPath" and "$arg".',
        );
      }
    }

    return _CreateOptions(
      targetPath: targetPath,
      projectName: projectName,
      description: description,
      includeEditorConfig: includeEditorConfig,
      runPubGet: runPubGet,
      dependencySource: dependencySource,
      help: help,
    );
  }
}

_DependencySource? _parseDependencySource(String value) => switch (value) {
  'hosted' => _DependencySource.hosted,
  'git' => _DependencySource.git,
  _ => null,
};
