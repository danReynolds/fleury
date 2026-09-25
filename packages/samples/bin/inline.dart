import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

Future<void> main(List<String> args) => runInlineSetup(args);

/// Native host: the shared form returns data; the command owns the terminal
/// mode, changing the region's height, and printing after runApp restores it.
Future<void> runInlineSetup(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    print(
      'Inline project setup demo\n'
      'Usage: dart run packages/samples/bin/inline.dart [--full-screen] [--handoff] [--repeat]\n'
      '--repeat opens another UI after a CLI prompt (macOS/Linux terminals).\n'
      'Generates a configuration in memory. No project files are written.',
    );
    return;
  }
  if (args.contains('--repeat') &&
      (!(Platform.isMacOS || Platform.isLinux) ||
          !stdin.hasTerminal ||
          !stdout.hasTerminal)) {
    stderr.writeln('--repeat requires macOS/Linux terminal input and output.');
    exitCode = 64;
    return;
  }
  stdout.writeln('Project setup demo · Configuration is generated in memory.');
  await stdout.flush();
  do {
    if (!await _showSetup(args) || !args.contains('--repeat')) return;
    stdout.write('\nOpen setup again? [y/N] ');
    await stdout.flush();
    // Fleury has returned stdin: an ordinary CLI prompt can read it before
    // the next runApp starts. No shared driver or global initialization.
  } while (stdin.readLineSync()?.trim().toLowerCase() == 'y');
}

Future<bool> _showSetup(List<String> args) async {
  final fullScreen = args.contains('--full-screen');
  InlineSetupResult? result;
  final exit = await runApp(
    FleuryApp(
      title: 'Project setup',
      home: _SetupHost(
        pager: args.contains('--handoff'),
        onComplete: (value) {
          result = value;
          exitApp();
        },
      ),
    ),
    mode: fullScreen
        ? const TerminalMode.fullScreen(mouse: true, mouseMotion: true)
        : TerminalMode.inline(
            rows: InlineSetupStep.configure.rows,
            mouse: true,
            mouseMotion: true,
          ),
    enableHotReload: false,
    debug: const DebugConfig(enabled: false),
  );
  if (exit.signal case final signal?) {
    exitCode = switch (signal) {
      AppSignal.interrupt => 130,
      AppSignal.terminate => 143,
      AppSignal.hangup => 129,
    };
    return false;
  }
  stdout.writeln(result?.summary ?? 'Setup cancelled.');
  await stdout.flush();
  return result != null;
}

class _SetupHost extends StatelessWidget {
  const _SetupHost({required this.pager, required this.onComplete});

  final bool pager;
  final void Function(InlineSetupResult?) onComplete;

  @override
  Widget build(BuildContext context) {
    final session = context.scope<TerminalSession>();
    return InlineSetup(
      onOpenPager: pager && session.supportsHandoff
          ? (result) => _openPager(session, result)
          : null,
      onStepChanged: session.isInline
          ? (step) => unawaited(session.resizeInline(step.rows))
          : null,
      onComplete: onComplete,
    );
  }
}

Future<void> _openPager(
  TerminalSession session,
  InlineSetupResult result,
) async {
  final directory = await Directory.systemTemp.createTemp('fleury-preview-');
  try {
    final file = File('${directory.path}/pubspec.yaml');
    await file.writeAsString('${result.manifest}\n');
    await session.runWithHandoff(() async {
      final pager = await Process.start(
        'less',
        ['--', file.path],
        mode: ProcessStartMode.inheritStdio,
        // Always keep the pager open for the demo, including a short manifest.
        environment: {'LESS': '', 'LESSOPEN': ''},
      );
      if (await pager.exitCode != 0)
        throw StateError('less exited unsuccessfully');
    });
  } finally {
    await directory.delete(recursive: true);
  }
}
