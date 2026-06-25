// `fleury_mcp [--cols=<n>] [--rows=<n>] [--] <command ...>`
//
// Runs a Model Context Protocol server (JSON-RPC over stdio) that drives the
// spawned app through its semantic tree. The app's render frames travel over a
// private socket; stdout stays a clean JSON-RPC channel (app logs and
// diagnostics go to stderr).
//
//   fleury_mcp -- dart run my_app.dart

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury_core.dart' show CellSize;
import 'package:fleury_mcp/fleury_mcp.dart';

Future<void> main(List<String> args) async {
  exit(await _run(args));
}

Future<int> _run(List<String> args) async {
  var cols = 80;
  var rows = 24;
  List<String>? command;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') {
      command = args.sublist(i + 1);
      break;
    } else if (arg.startsWith('--cols=')) {
      final value = int.tryParse(arg.substring('--cols='.length));
      if (value == null || value < 1) {
        stderr.writeln('--cols must be a positive integer.');
        return 2;
      }
      cols = value;
    } else if (arg.startsWith('--rows=')) {
      final value = int.tryParse(arg.substring('--rows='.length));
      if (value == null || value < 1) {
        stderr.writeln('--rows must be a positive integer.');
        return 2;
      }
      rows = value;
    } else if (arg == '-h' || arg == '--help') {
      _printUsage();
      return 0;
    } else if (arg.startsWith('-')) {
      stderr.writeln('Unknown option: $arg');
      _printUsage();
      return 2;
    } else {
      // First bare token starts the app command (the `--` separator is optional
      // but recommended when the command takes its own flags).
      command = args.sublist(i);
      break;
    }
  }

  if (command == null || command.isEmpty) {
    stderr.writeln(
      'fleury_mcp requires a command to run the app, e.g. '
      '`fleury_mcp -- dart run my_app.dart`.',
    );
    return 2;
  }

  if (_isColdRunCommand(command)) {
    // The bridge spawns whatever command it's given, so it can't AOT-compile
    // the app itself — point the user at the fast path instead.
    stderr.writeln(
      'fleury_mcp: launching via `dart run` JIT-compiles the app on startup '
      '(seconds). For a faster, repeatable launch, AOT-compile once '
      '(`dart compile exe my_app.dart -o my_app`) and run `fleury_mcp -- '
      './my_app`.',
    );
  }

  final FleuryAppBridge bridge;
  try {
    bridge = await FleuryAppBridge.spawn(
      command: command,
      viewport: CellSize(cols, rows),
    );
  } on FleuryAppBridgeException catch (e) {
    stderr.writeln('fleury_mcp: ${e.message}');
    return 1;
  } on ProcessException catch (e) {
    stderr.writeln('fleury_mcp: could not start ${command.first}: ${e.message}');
    return 1;
  }

  final exitCode = Completer<int>();
  Future<void> finish(int code) async {
    await bridge.close();
    if (!exitCode.isCompleted) exitCode.complete(code);
  }

  // The host closes our stdin (or its pipe) to disconnect; the app exiting ends
  // the session too. Either way, tear down and exit.
  unawaited(
    runMcpServer(bridge: bridge, input: stdin, output: stdout).then(
      (_) => finish(0),
      onError: (Object error, StackTrace _) {
        stderr.writeln('fleury_mcp: $error');
        return finish(1);
      },
    ),
  );
  unawaited(bridge.done.then((_) => finish(0)));

  // Tear the spawned app down on a host-initiated stop. The primary path is the
  // host closing our stdin (handled by runMcpServer above); SIGINT/SIGTERM are
  // what a host escalates to — without cleanup the app subprocess is orphaned.
  final signalSubs = <StreamSubscription<ProcessSignal>>[];
  Future<void> onSignal(int code) async {
    for (final sub in signalSubs) {
      await sub.cancel();
    }
    await finish(code);
  }

  signalSubs.add(ProcessSignal.sigint.watch().listen((_) => onSignal(130)));
  if (!Platform.isWindows) {
    // SIGTERM isn't watchable on Windows; SIGINT covers the Ctrl-C path there.
    signalSubs.add(ProcessSignal.sigterm.watch().listen((_) => onSignal(143)));
  }

  return exitCode.future;
}

/// True when [command] launches the app through the Dart VM's JIT path
/// (`dart run …` or `dart path/to/app.dart`), which cold-compiles on spawn.
/// An AOT executable or other launcher returns false.
bool _isColdRunCommand(List<String> command) {
  if (command.isEmpty) return false;
  final exe = command.first.split(Platform.pathSeparator).last;
  if (exe != 'dart' && exe != 'dart.exe') return false;
  return command.skip(1).any((a) => a == 'run' || a.endsWith('.dart'));
}

void _printUsage() {
  stderr.writeln(
    'fleury_mcp [--cols=<n>] [--rows=<n>] -- <command ...>',
  );
  stderr.writeln('');
  stderr.writeln(
    'Runs an MCP (Model Context Protocol) server over stdio that drives a '
    'Fleury app',
  );
  stderr.writeln(
    'through its semantic tree, so an MCP host can read and operate it.',
  );
  stderr.writeln('');
  stderr.writeln('Example: fleury_mcp -- dart run my_app.dart');
}
