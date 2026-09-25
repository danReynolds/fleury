// Integrated native ownership proof, driven by tool/check_sequential_sessions.py.
// Intentionally exits naturally: an orphaned input worker must fail the check.
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--throwing-hook-report')) {
    final report = File(args[args.indexOf('--throwing-hook-report') + 1]);
    var calls = 0;
    final outcome = await runApp(
      const Text('HOOK READY'),
      enableHotReload: false,
      debug: const DebugConfig(enabled: false),
      onStrayOutput: (line) {
        calls++;
        if (line.text == 'HOOK FAILURE TRIGGER') {
          throw StateError('stray hook failed');
        }
      },
      onEvent: (event) {
        if (event is KeyEvent && event.code == KeyCode.enter) {
          stdout.writeln('HOOKED BEFORE FAILURE');
          stdout.writeln('HOOK FAILURE TRIGGER');
        }
        return null;
      },
    );
    report.writeAsStringSync(
      jsonEncode({'signal': outcome.signal?.name, 'calls': calls}),
    );
    return;
  }
  if (args.contains('--slow-cleanup-report')) {
    await slowHandoffCleanup(
      File(args[args.indexOf('--slow-cleanup-report') + 1]),
    );
    return;
  }
  if (args.contains('--hangup-report')) {
    final report = File(args[args.indexOf('--hangup-report') + 1]);
    Object result;
    try {
      final outcome = await runApp(
        const Text('HANGUP READY'),
        mode: args.contains('--inline')
            ? const TerminalMode.inline(rows: 3)
            : TerminalMode.interactive,
        enableHotReload: false,
        debug: const DebugConfig(enabled: false),
      );
      result = {'signal': outcome.signal?.name};
    } catch (error) {
      result = {'error': '$error'};
    }
    report.writeAsStringSync(jsonEncode(result));
    return;
  }
  Future<void> step(String label, TerminalMode mode) async {
    var text = '';
    await runApp(
      Text('$label READY'),
      mode: mode,
      enableHotReload: false,
      debug: const DebugConfig(enabled: false),
      onEvent: (event) {
        if (event is TextInputEvent) text += event.text;
        if (event is PasteEvent) text += event.text;
        if (event is KeyEvent && event.code == KeyCode.enter) {
          return const ExitRequested();
        }
        return null;
      },
    );
    if (text != 'héllo中') throw StateError('$label received: $text');
    stdout.writeln('$label DONE');
    await stdout.flush();
  }

  await step('INLINE-A', const TerminalMode.inline(rows: 5));
  stdout.writeln('PLAIN READY');
  await stdout.flush();
  if (stdin.readLineSync() != 'plain') throw StateError('Plain prompt failed');
  final child = await Process.start('/bin/sh', [
    '-c',
    r'''printf 'CHILD READY\n'; IFS= read -r answer; test "$answer" = child''',
  ], mode: ProcessStartMode.inheritStdio);
  if (await child.exitCode != 0) {
    throw StateError('Inherited child input failed');
  }
  await step('FULL-B', TerminalMode.interactive);
  var childFinished = false;
  await runApp(
    ScopeBuilder<TerminalSession>(
      builder: (_, session) => KeyBindings(
        bindings: [
          KeyBinding(
            KeySequence.ctrl.o,
            onTrigger: (_) async {
              await session.runWithHandoff(() async {
                // Begin UI teardown while the child still owns the terminal.
                // runApp must not return (or reopen another UI) until it exits.
                exitApp();
                final child = await Process.start('/bin/sh', [
                  '-c',
                  r'''printf 'BORROW READY\n'; IFS= read -r answer; test "$answer" = borrow''',
                ], mode: ProcessStartMode.inheritStdio);
                if (await child.exitCode != 0) {
                  throw StateError('Handoff input failed');
                }
                childFinished = true;
              });
            },
          ),
        ],
        child: const Text('HANDOFF READY'),
      ),
    ),
    mode: const TerminalMode.inline(rows: 3),
    enableHotReload: false,
    debug: const DebugConfig(enabled: false),
  );
  if (!childFinished) {
    throw StateError('runApp returned while input was borrowed');
  }
  stdout.writeln('HANDOFF CLOSED');
  await stdout.flush();
  await step('INLINE-C', const TerminalMode.inline(rows: 3));
  // Dart stdin has never been subscribed to. A caller can still take its first
  // async subscription after the native sessions and sync/inherited prompts.
  stdout.writeln('ASYNC READY');
  await stdout.flush();
  final line = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  if (line != 'async') throw StateError('Dart stdin was consumed by Fleury');
  stdout.writeln('SEQUENTIAL PASS');
  await stdout.flush();
}

// Keep the child alive beyond teardown reporting deadlines. Capture must
// remain usable for handoff completion and replay, even after runApp has failed.
Future<void> slowHandoffCleanup(File report) async {
  final result = <String, Object?>{};
  final childDone = Completer<void>();
  var handoffStarted = false;
  try {
    await runApp(
      ScopeBuilder<TerminalSession>(
        builder: (_, session) => KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.o,
              onTrigger: (_) async {
                if (handoffStarted) return;
                handoffStarted = true;
                stdout.writeln('CAPTURE BEFORE SLOW CHILD');
                await stdout.flush();
                try {
                  await session.runWithHandoff(() async {
                    exitApp();
                    final child = await Process.start('/bin/sh', [
                      '-c',
                      r'''printf 'SLOW CHILD READY\n'; IFS= read -r answer; test "$answer" = finish''',
                    ], mode: ProcessStartMode.inheritStdio);
                    if (await child.exitCode != 0) {
                      throw StateError('Slow child input failed');
                    }
                  });
                  result['handoff'] = 'completed';
                } catch (error) {
                  result['handoff'] = '$error';
                } finally {
                  childDone.complete();
                }
              },
            ),
          ],
          child: const Text('SLOW HANDOFF READY'),
        ),
      ),
      mode: const TerminalMode.inline(rows: 3),
      enableHotReload: false,
      debug: const DebugConfig(enabled: false),
    );
    result['first'] = 'unexpected success';
  } on FleuryError catch (error) {
    result['first'] = error.details;
  }
  try {
    await runApp(
      const Text('must not enter'),
      enableHotReload: false,
      debug: const DebugConfig(enabled: false),
    );
    result['blocked'] = false;
  } on StateError {
    result['blocked'] = true;
  }
  // The PTY harness releases the child only after reading this result.
  final pendingReport = File('${report.path}.pending');
  pendingReport.writeAsStringSync(jsonEncode(result));
  pendingReport.renameSync(report.path);
  await childDone.future;

  // Handoff completion releases its borrow; driver/capture restoration still
  // has to settle. Try fresh invocations until admission acknowledges that.
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    try {
      await runApp(
        const Text('RECOVERED READY'),
        mode: const TerminalMode.inline(rows: 3),
        enableHotReload: false,
        debug: const DebugConfig(enabled: false),
        onEvent: (event) => event is KeyEvent && event.code == KeyCode.enter
            ? const ExitRequested()
            : null,
      );
      result['second'] = 'completed';
      break;
    } on StateError catch (error) {
      if (DateTime.now().isAfter(deadline)) rethrow;
      if (!error.message.contains('terminal cleanup')) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
  report.writeAsStringSync(jsonEncode(result));
  stdout.writeln('SLOW CLEANUP PASS');
  await stdout.flush();
}
