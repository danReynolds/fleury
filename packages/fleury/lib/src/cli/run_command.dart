/// `fleury run [vm options] [script.dart] [app args]` — argument shape and
/// entrypoint lookup; the launcher itself is `DevBootstrap.launch`.
///
/// Everything before the first non-flag argument is a VM option for the app's
/// process (`--enable-asserts`, `--define=…`), the first non-flag argument is
/// the entrypoint, and everything after it is the app's own argv, verbatim.
/// `--` ends option parsing early, so an app whose first argument starts with
/// a dash can still be launched: `fleury run -- app.dart --flag`. With no
/// script at all, [resolveRunEntrypoint] picks the project's entrypoint from
/// `bin/`, so the everyday command is just `fleury run`.
library;

import 'dart:io';

final class RunCommandInvocation {
  const RunCommandInvocation({
    this.scriptPath,
    this.vmOptions = const [],
    this.args = const [],
  });

  /// Null when no script was given: the caller resolves one from `bin/`.
  final String? scriptPath;
  final List<String> vmOptions;
  final List<String> args;
}

/// Parses `fleury run` arguments; returns null (print [runCommandUsage]) only
/// for an explicit help flag. No script is a valid invocation.
RunCommandInvocation? parseRunCommand(List<String> args) {
  final vmOptions = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') {
      if (i + 1 >= args.length) {
        return RunCommandInvocation(vmOptions: vmOptions);
      }
      return RunCommandInvocation(
        scriptPath: args[i + 1],
        vmOptions: vmOptions,
        args: args.sublist(i + 2),
      );
    }
    if (arg == '-h' || arg == '--help') return null;
    if (arg.startsWith('-')) {
      vmOptions.add(arg);
      continue;
    }
    return RunCommandInvocation(
      scriptPath: arg,
      vmOptions: vmOptions,
      args: args.sublist(i + 1),
    );
  }
  return RunCommandInvocation(vmOptions: vmOptions);
}

/// The script `fleury run` starts when none was named, looked up under
/// [projectDir]/bin: the only Dart file there, else `main.dart`, else
/// `run_app.dart`, else the file named after the package in `pubspec.yaml`.
///
/// Returns the path, or an error message that names what was found so the
/// user can pick.
({String? path, String? error}) resolveRunEntrypoint(Directory projectDir) {
  final bin = Directory('${projectDir.path}/bin');
  if (!bin.existsSync()) {
    return (
      path: null,
      error:
          'fleury run: no bin/ directory in ${projectDir.path}; '
          'name the script to run: fleury run path/to/main.dart',
    );
  }
  final candidates =
      bin
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList()
        ..sort();
  if (candidates.isEmpty) {
    return (
      path: null,
      error:
          'fleury run: no Dart files in ${bin.path}; '
          'name the script to run: fleury run path/to/main.dart',
    );
  }
  if (candidates.length == 1) return (path: candidates.single, error: null);
  final preferred = [
    'main.dart',
    'run_app.dart',
    if (_packageName(projectDir) case final name?) '$name.dart',
  ];
  for (final name in preferred) {
    final match = '${bin.path}/$name';
    if (candidates.contains(match)) return (path: match, error: null);
  }
  final names = candidates
      .map((p) => p.substring(bin.path.length + 1))
      .join(', ');
  return (
    path: null,
    error:
        'fleury run: several entrypoints in bin/ ($names) and none is '
        'main.dart or run_app.dart; name the one to run: '
        'fleury run bin/<file>.dart',
  );
}

String? _packageName(Directory projectDir) {
  final pubspec = File('${projectDir.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^name:\s*([A-Za-z0-9_]+)\s*$').firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

const String runCommandUsage = '''
usage: fleury run [vm options] [script.dart] [app args...]

Runs a Fleury app with hot reload from a launcher that never compiles it, so
the app is compiled once instead of twice. Save a source file to reload; press
F5 in the app to restart. With no script, runs the project's entrypoint from
bin/ (its only Dart file, else main.dart, else run_app.dart). VM options
before the script go to the app's VM (for example --enable-asserts or
--define=KEY=value).
''';
