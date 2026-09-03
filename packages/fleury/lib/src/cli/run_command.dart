/// `fleury run [vm options] <script.dart> [app args]` — argument shape only;
/// the launcher itself is `DevBootstrap.launch`.
///
/// Everything before the first non-flag argument is a VM option for the app's
/// process (`--enable-asserts`, `--define=…`), the first non-flag argument is
/// the entrypoint, and everything after it is the app's own argv, verbatim.
/// `--` ends option parsing early, so an app whose first argument starts with
/// a dash can still be launched: `fleury run -- app.dart --flag`.
library;

final class RunCommandInvocation {
  const RunCommandInvocation({
    required this.scriptPath,
    this.vmOptions = const [],
    this.args = const [],
  });

  final String scriptPath;
  final List<String> vmOptions;
  final List<String> args;
}

/// Parses `fleury run` arguments; returns null (with [usage] to print) when
/// there is no script to run.
RunCommandInvocation? parseRunCommand(List<String> args) {
  final vmOptions = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') {
      if (i + 1 >= args.length) return null;
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
  return null;
}

const String runCommandUsage = '''
usage: fleury run [vm options] <script.dart> [app args...]

Runs a Fleury app with hot reload from a launcher that never compiles it, so
the app is compiled once instead of twice. Save a source file to reload; press
F5 in the app to restart. VM options before the script go to the app's VM
(for example --enable-asserts or --define=KEY=value).
''';
