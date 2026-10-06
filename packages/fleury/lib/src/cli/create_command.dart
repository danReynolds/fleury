import 'dart:convert';
import 'dart:io';

import '../version.dart';
import 'dart_sdk.dart';

/// Generated projects depend on the release that created them. The fleury
/// packages version in lockstep, so one constraint covers all three.
const _fleuryConstraint = '^$fleuryVersion';
const _lintsVersion = '^6.0.0';
const _testVersion = '^1.26.3';
const _repositoryUrl = 'https://github.com/danReynolds/fleury.git';

/// The Dart SDK floor every generated project declares; the create tests keep
/// it equal to the framework's own.
const _sdkFloor = '3.10.4';

/// The language version pub derives from [_sdkFloor], which `dart format`
/// uses to lay out the generated sources.
final _languageVersion = _sdkFloor.substring(0, _sdkFloor.lastIndexOf('.'));

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

  // Normalize dot segments for naming without changing the requested target:
  // its original path still needs the file/symlink checks above.
  final projectName = options.projectName ?? _basename(target.uri.toFilePath());
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
  await _formatSources(target);

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
        'The project was created. Install the Dart SDK and ensure `dart` is '
        'on PATH, then run `dart pub get` from ${target.path}.',
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
          "If Fleury $fleuryVersion isn't on pub.dev yet, use Git "
          'dependencies in a different, empty directory: '
          '`fleury create another_app --dependency-source=git`.',
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
  stdout.writeln('  dart run fleury run');
  if (options.includeEditorConfig) {
    stdout.writeln(
      '  Or open VS Code with `code .` and press F5 '
      '(requires the Dart extension).',
    );
  }
  stdout.writeln(
    '  Edit and save while it runs — hot reload keeps your state.',
  );
  return 0;
}

/// Formats the generated Dart sources with the SDK's own formatter.
///
/// The templates are laid out for typical names, but a project name sets the
/// app's class name, and a long one pushes lines past 80 columns. Formatting
/// here keeps every new project `dart format`-clean whatever its name. It is
/// best effort: unformatted sources still compile, and without a runnable
/// SDK the `dart pub get` that follows reports the problem.
Future<void> _formatSources(Directory target) async {
  try {
    await Process.run(dartSdkExecutable, [
      'format',
      // Before `dart pub get` there is no package config to read it from.
      '--language-version=$_languageVersion',
      'bin',
      'lib',
      'test',
    ], workingDirectory: target.path);
  } on ProcessException {
    // No runnable SDK: the sources stay as written.
  }
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
    'README.md': _readme(
      projectName,
      includeEditorConfig: includeEditorConfig,
      dependencySource: dependencySource,
    ),
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
  fleury: $_fleuryConstraint

dev_dependencies:
  fleury_test: $_fleuryConstraint
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
  sdk: ^$_sdkFloor

$dependencies''';
}

String _appSource({required String className, required String displayName}) =>
    '''
import 'package:fleury/fleury.dart';

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
            Button(text: 'Increment', autofocus: true, onPressed: _increment),
            const SizedBox(height: 1),
            const Text('Press Enter or click the button.'),
          ],
        ),
      ),
    );
  }
}
''';

// The comment inside the argument list says why mouse mode is on, and, as a
// line comment, keeps the list split: the formatter leaves this layout alone
// for a short class name, even where [_formatSources] could not run.
String _entrypointSource({
  required String projectName,
  required String className,
}) =>
    '''
import 'package:fleury/fleury.dart';
import 'package:$projectName/app.dart';

void main(List<String> args) => runApp(
  const $className(),
  args: args,
  // Mouse reporting lets the Increment button respond to clicks.
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
    tester.sendKey(const KeyEvent(KeyCode.enter));
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

String _readme(
  String projectName, {
  required bool includeEditorConfig,
  required _DependencySource dependencySource,
}) {
  final runLead = includeEditorConfig
      ? 'Press F5 in VS Code, or run directly from an interactive terminal:'
      : 'Run directly from an interactive terminal:';
  final editorNote = includeEditorConfig
      ? '''
Under F5 the Dart debugger drives the reload (wired via `dart.hotReloadOnSave`
in `.vscode/settings.json`); the F5 flow requires the official Dart extension
(`Dart-Code.dart-code`). Fleury needs no custom editor extension.
'''
      : '';
  // Each source names the CLI and MCP server that match its framework: a Git
  // project resolves Fleury from the repository, so its tools come from there
  // too.
  final globalCli = switch (dependencySource) {
    _DependencySource.hosted =>
      '''
With the CLI activated globally (`dart pub global activate fleury`), the
launcher is just `fleury run`.''',
    _DependencySource.git =>
      '''
With the CLI activated globally from the same Git repository, the launcher is
just `fleury run`:

```sh
dart pub global activate --source git \\
  $_repositoryUrl \\
  --git-path packages/fleury
```''',
  };
  final agentSetup = switch (dependencySource) {
    _DependencySource.hosted =>
      '''
- **Driven by an AI agent** (macOS and Linux) — add the MCP server as a
  development dependency (`dart pub add --dev fleury_mcp`), then have your MCP
  host run''',
    _DependencySource.git =>
      '''
- **Driven by an AI agent** (macOS and Linux) — add `fleury_mcp` to
  `dev_dependencies` with the same Git source as `fleury_test`
  (`path: packages/fleury_mcp`), then have your MCP host run''',
  };
  return '''
# $projectName

A terminal application built with [Fleury](https://github.com/danReynolds/fleury).

## Run

$runLead

```sh
dart run fleury run
```

The launcher finds `bin/run_app.dart` on its own and compiles the app once.
A plain `dart run bin/run_app.dart` also works, with the same hot-reload
session, but compiles the app twice on a cold start.

$globalCli

Press Enter or click **Increment**. Press Ctrl+C to quit.

**Saving a changed file hot reloads the running app** — in any editor, on
macOS and Linux: the terminal updates in place and widget state survives. Set
`FLEURY_HOT_RELOAD=0` to opt out. On Windows the app runs without hot reload;
to reload there, run it under your editor's Dart debugger.

$editorNote
## Test

```sh
dart test
```

## The same app, elsewhere

- **In a browser** (macOS and Linux) — run
  `dart run fleury serve --spawn dart --enable-vm-service=0 run bin/run_app.dart`
  and open the printed URL. This streams the unchanged app to a browser tab
  and reloads it when you save. Stop the preview with Ctrl+C in the terminal
  running `serve` (hot restart is unavailable under a serve handle).
$agentSetup
  `dart run fleury_mcp -- dart run bin/run_app.dart` from this directory. It
  exposes the running UI over the Model Context Protocol, so an agent reads and
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
