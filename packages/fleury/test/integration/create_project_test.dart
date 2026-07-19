import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final skipPty = Platform.isWindows
      ? 'PTY capture uses POSIX openpty and posix_spawnp.'
      : null;
  late Directory tempDir;
  late Directory project;
  late String packageRoot;
  late String repoRoot;

  setUpAll(() async {
    packageRoot = Directory.current.absolute.path;
    repoRoot = _findRepoRoot(Directory.current).path;
    tempDir = Directory.systemTemp.createTempSync('fleury_create_project_');
    project = Directory('${tempDir.path}/created_app');

    final create = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      '$packageRoot/bin/fleury.dart',
      'create',
      project.path,
      '--project-name=fleury_app',
      '--no-pub',
    ], workingDirectory: tempDir.path);
    if (create.exitCode != 0) {
      throw StateError(
        'create failed (${create.exitCode})\n'
        'stdout:\n${create.stdout}\nstderr:\n${create.stderr}',
      );
    }

    File('${project.path}/pubspec_overrides.yaml').writeAsStringSync('''
dependency_overrides:
  fleury:
    path: ${jsonEncode('$repoRoot/packages/fleury')}
  fleury_widgets:
    path: ${jsonEncode('$repoRoot/packages/fleury_widgets')}
  fleury_test:
    path: ${jsonEncode('$repoRoot/packages/fleury_test')}
''');

    final pubGet = await _runDart(project, const ['pub', 'get']);
    if (pubGet.exitCode != 0) {
      throw StateError(
        'generated project pub get failed (${pubGet.exitCode})\n'
        'stdout:\n${pubGet.stdout}\nstderr:\n${pubGet.stderr}',
      );
    }
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'fresh project analyzes, tests, and compiles as an executable',
    () async {
      final analyze = await _runDart(project, const ['analyze']);
      expect(
        analyze.exitCode,
        0,
        reason: 'stdout:\n${analyze.stdout}\nstderr:\n${analyze.stderr}',
      );

      final tests = await _runDart(project, const ['test']);
      expect(
        tests.exitCode,
        0,
        reason: 'stdout:\n${tests.stdout}\nstderr:\n${tests.stderr}',
      );

      final executable = '${tempDir.path}/created_app_executable';
      final compile = await _runDart(project, [
        'compile',
        'exe',
        'bin/run_app.dart',
        '-o',
        executable,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: 'stdout:\n${compile.stdout}\nstderr:\n${compile.stderr}',
      );
      expect(
        File(executable).existsSync() || File('$executable.exe').existsSync(),
        isTrue,
      );
    },
    tags: const ['integration'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'globally activated CLI executable resolves its generated Git project',
    () async {
      final pubCache = Directory('${tempDir.path}/global_pub_cache')
        ..createSync();
      final gitConfig = File('${tempDir.path}/gitconfig');
      final fleuryRepository = Uri.directory(
        repoRoot,
        windows: Platform.isWindows,
      );
      final stdioRepository = _packageRootUri(packageRoot, 'stdio');
      gitConfig.writeAsStringSync('''
[url "$fleuryRepository"]
  insteadOf = https://github.com/danReynolds/fleury.git
[url "$stdioRepository"]
  insteadOf = https://github.com/danReynolds/stdio.git
[protocol "file"]
  allow = always
''');
      final environment = <String, String>{
        ...Platform.environment,
        'PUB_CACHE': pubCache.path,
        'GIT_CONFIG_GLOBAL': gitConfig.path,
        'GIT_CONFIG_NOSYSTEM': '1',
      };
      final activationRepository = Directory(
        '${tempDir.path}/fleury_activation_repository',
      );
      final activationPackage = Directory(
        '${activationRepository.path}/packages/fleury',
      );
      _copyPackageSource(Directory(packageRoot), activationPackage);
      await _initializeGitRepository(
        activationRepository,
        environment: environment,
      );
      final activationRepositoryUri = Uri.directory(
        activationRepository.path,
        windows: Platform.isWindows,
      );

      final activate = await Process.run(Platform.resolvedExecutable, <String>[
        'pub',
        'global',
        'activate',
        '--source',
        'git',
        activationRepositoryUri.toString(),
        '--git-path',
        'packages/fleury',
      ], environment: environment);
      expect(
        activate.exitCode,
        0,
        reason: 'stdout:\n${activate.stdout}\nstderr:\n${activate.stderr}',
      );

      final executable = Platform.isWindows
          ? '${pubCache.path}/bin/fleury.bat'
          : '${pubCache.path}/bin/fleury';
      expect(
        File(executable).existsSync(),
        isTrue,
        reason: 'global activation must install the public `fleury` shim',
      );

      final target = Directory('${tempDir.path}/activated_app');
      final create = await Process.run(
        executable,
        <String>['create', target.path, '--dependency-source=git'],
        environment: environment,
        runInShell: Platform.isWindows,
      );
      expect(
        create.exitCode,
        0,
        reason: 'stdout:\n${create.stdout}\nstderr:\n${create.stderr}',
      );
      expect(create.stdout, contains('Resolving dependencies...'));
      expect(create.stdout, contains('Created activated_app.'));
      expect(
        File('${target.path}/.dart_tool/package_config.json').existsSync(),
        isTrue,
        reason: 'the create command itself must run `dart pub get`',
      );
    },
    tags: const ['integration'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'compiled CLI uses the Dart SDK for create and contributor commands',
    () async {
      final pubCache = Directory('${tempDir.path}/compiled_pub_cache')
        ..createSync();
      final gitConfig = File('${tempDir.path}/compiled_gitconfig');
      final fleuryRepository = Uri.directory(
        repoRoot,
        windows: Platform.isWindows,
      );
      final stdioRepository = _packageRootUri(packageRoot, 'stdio');
      gitConfig.writeAsStringSync('''
[url "$fleuryRepository"]
  insteadOf = https://github.com/danReynolds/fleury.git
[url "$stdioRepository"]
  insteadOf = https://github.com/danReynolds/stdio.git
[protocol "file"]
  allow = always
''');
      final environment = <String, String>{
        ...Platform.environment,
        'PUB_CACHE': pubCache.path,
        'GIT_CONFIG_GLOBAL': gitConfig.path,
        'GIT_CONFIG_NOSYSTEM': '1',
      };

      final outputBase = '${tempDir.path}/compiled_fleury';
      final executable = Platform.isWindows ? '$outputBase.exe' : outputBase;
      final compile = await Process.run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        'bin/fleury.dart',
        '-o',
        executable,
      ], workingDirectory: packageRoot);
      expect(
        compile.exitCode,
        0,
        reason: 'stdout:\n${compile.stdout}\nstderr:\n${compile.stderr}',
      );
      expect(File(executable).existsSync(), isTrue);

      final target = Directory('${tempDir.path}/compiled_app');
      final create = await Process.run(executable, <String>[
        'create',
        target.path,
        '--dependency-source=git',
      ], environment: environment);
      expect(
        create.exitCode,
        0,
        reason: 'stdout:\n${create.stdout}\nstderr:\n${create.stderr}',
      );
      expect(create.stdout, isNot(contains('Unknown subcommand: pub')));
      expect(
        File('${target.path}/.dart_tool/package_config.json').existsSync(),
        isTrue,
      );

      final missingDartTarget = Directory(
        '${tempDir.path}/compiled_missing_dart_app',
      );
      final environmentWithoutDart = <String, String>{
        for (final entry in environment.entries)
          if (entry.key.toLowerCase() != 'path') entry.key: entry.value,
        'PATH': '',
      };
      final missingDart = await Process.run(executable, <String>[
        'create',
        missingDartTarget.path,
      ], environment: environmentWithoutDart);
      expect(missingDart.exitCode, 1);
      expect(missingDart.stderr, contains('could not run `dart pub get`'));
      expect(missingDart.stderr, contains('ensure `dart` is on PATH'));
      expect(missingDart.stderr, contains('`--no-pub`'));

      final devHelp = await Process.run(
        executable,
        const <String>['dev', '--help'],
        workingDirectory: repoRoot,
        environment: environment,
      );
      expect(
        devHelp.exitCode,
        0,
        reason: 'stdout:\n${devHelp.stdout}\nstderr:\n${devHelp.stderr}',
      );
      expect(devHelp.stdout, contains('Fleury local development launcher'));
    },
    tags: const ['integration'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'fresh project renders and accepts input over a real terminal',
    () async {
      final profilingRoot = '$repoRoot/profiling';
      final outBase = '${tempDir.path}/created_app_pty';
      final capture = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        '$profilingRoot/capture_pty.dart',
        '--out',
        outBase,
        '--timeout',
        '30',
        '--cols',
        '70',
        '--rows',
        '14',
        '--input-hex',
        '0d',
        '--input-after-output-ms',
        '1000',
        '--interrupt-after-output-ms',
        '2200',
        '--',
        Platform.resolvedExecutable,
        'bin/run_app.dart',
      ], workingDirectory: project.path);

      expect(
        capture.exitCode,
        0,
        reason: 'stdout:\n${capture.stdout}\nstderr:\n${capture.stderr}',
      );

      final metadata =
          jsonDecode(File('$outBase.json').readAsStringSync())
              as Map<String, Object?>;
      final output = latin1.decode(File('$outBase.bin').readAsBytesSync());
      expect(metadata['timedOut'], isFalse);
      expect(metadata['exitCode'], 0);
      expect(output, contains('Count: 0'));
      final afterFirstFrame = output.substring(output.indexOf('Count: 0'));
      expect(
        afterFirstFrame,
        matches(RegExp(r'\x1B\[[0-9]+;[0-9]+H1')),
        reason: 'the Enter key should repaint the counter cell from 0 to 1',
      );
      expect(output, isNot(contains('runApp needs an interactive terminal')));
      expect(output, contains('\x1B[?1049h'));
      expect(output, contains('\x1B[?1049l'));
      expect(
        output.lastIndexOf('\x1B[?1049l'),
        greaterThan(output.indexOf('\x1B[?1049h')),
      );
    },
    skip: skipPty,
    tags: const ['integration', 'pty'],
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<ProcessResult> _runDart(Directory workingDirectory, List<String> args) {
  return Process.run(
    Platform.resolvedExecutable,
    args,
    workingDirectory: workingDirectory.path,
  );
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/tool/fleury_dev.dart').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not find the Fleury repo root from ${start.path}.',
      );
    }
    current = parent;
  }
}

Uri _packageRootUri(String packageRoot, String packageName) {
  final configFile = File('$packageRoot/.dart_tool/package_config.json');
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final packages = config['packages']! as List<Object?>;
  final package = packages.cast<Map<String, Object?>>().singleWhere(
    (entry) => entry['name'] == packageName,
  );
  return configFile.uri.resolve(package['rootUri']! as String);
}

void _copyPackageSource(Directory source, Directory target) {
  target.createSync(recursive: true);
  final prefix = '${source.absolute.path}${Platform.pathSeparator}';
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = entity.absolute.path.substring(prefix.length);
    final firstSegment = relative.split(Platform.pathSeparator).first;
    if (firstSegment == '.dart_tool' || firstSegment == 'build') continue;

    final destination = '${target.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      File(destination).parent.createSync(recursive: true);
      entity.copySync(destination);
    }
  }
}

Future<void> _initializeGitRepository(
  Directory repository, {
  required Map<String, String> environment,
}) async {
  for (final command in const <List<String>>[
    <String>['init'],
    <String>['add', 'packages/fleury'],
    <String>[
      '-c',
      'user.name=Fleury Test',
      '-c',
      'user.email=fleury-test@example.com',
      'commit',
      '-m',
      'Fleury activation fixture',
    ],
  ]) {
    final result = await Process.run(
      'git',
      command,
      workingDirectory: repository.path,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'git ${command.join(' ')} failed (${result.exitCode})\n'
        'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }
  }
}
