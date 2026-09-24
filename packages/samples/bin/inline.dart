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
          onOpenPager: args.contains('--handoff')
              ? (result) => _openPager(session, result)
              : null,
          onStepChanged: fullScreen
              ? null
              : (step) => unawaited(session.resizeInline(step.rows)),
          onComplete: (value) {
            result = value;
            requestExit();
          },
        ),
      ),
    ),
    mode: fullScreen
        ? const TerminalMode(mouse: true, mouseMotion: true)
        : TerminalMode(
            inlineRows: InlineSetupStep.configure.rows,
            mouse: true,
            mouseMotion: true,
          ),
    enableHotReload: false,
    debug: const DebugConfig(enabled: false),
  );
  stdout.writeln(result?.summary ?? 'Setup cancelled.');
  await stdout.flush();
  if (exit.signal != null)
    exitCode =
        128 +
        switch (exit.signal!) {
          AppSignal.interrupt => 2,
          AppSignal.terminate => 15,
          AppSignal.hangup => 1,
        };
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
