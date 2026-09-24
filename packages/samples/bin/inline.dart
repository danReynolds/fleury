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
      'Usage: dart run packages/samples/bin/inline.dart [--full-screen] [--handoff]\n'
      'Generates a configuration in memory. No project files are written.',
    );
    return;
  }
  final fullScreen = args.contains('--full-screen');
  InlineSetupResult? result;
  stdout.writeln('Project setup demo · Configuration is generated in memory.');
  await stdout.flush();
  final exit = await runApp(
    FleuryApp(
      title: 'Project setup',
      home: ScopeBuilder<TerminalSession>(
        builder: (_, session) => InlineSetup(
          onOpenPager: args.contains('--handoff') && session.supportsHandoff
              ? (result) => _openPager(session, result)
              : null,
          onStepChanged: session.isInline
              ? (step) => unawaited(session.resizeInline(step.rows))
              : null,
          onComplete: (value) {
            result = value;
            requestExit();
          },
        ),
      ),
    ),
    mode: fullScreen
        ? const TerminalMode(mouse: true, mouseMotion: true)
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
    return;
  }
  stdout.writeln(result?.summary ?? 'Setup cancelled.');
  await stdout.flush();
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
