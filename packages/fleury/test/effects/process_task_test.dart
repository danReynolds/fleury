import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<File> _script(Directory dir, String name, String source) async {
  final file = File('${dir.path}/$name.dart');
  await file.writeAsString(source);
  return file;
}

ProcessTaskCommand _dartScript(File file) {
  return ProcessTaskCommand(Platform.resolvedExecutable, [file.path]);
}

Future<void> _waitForOutput(
  ProcessTaskController controller,
  bool Function(TaskOutput entry) predicate,
) {
  final completer = Completer<void>();
  void listener() {
    if (completer.isCompleted) return;
    if (controller.output.any(predicate)) {
      controller.removeListener(listener);
      completer.complete();
    }
  }

  controller.addListener(listener);
  listener();
  return completer.future.timeout(const Duration(seconds: 5));
}

void main() {
  group('ProcessTaskController', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fleury_process_task_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('captures stdout, stderr, and successful exit code', () async {
      final script = await _script(tempDir, 'success', '''
import 'dart:io';

void main() {
  stdout.writeln('out-line');
  stderr.writeln('err-line');
}
''');
      final controller = ProcessTaskController(id: 'process');
      final command = _dartScript(script);

      final result = await controller.startProcess(command);

      expect(result.succeeded, isTrue);
      expect(result.value?.exitCode, 0);
      expect(controller.command, command);
      expect(controller.status, TaskStatus.succeeded);
      expect(
        controller.output.map((entry) => '${entry.source}:${entry.text}'),
        containsAll(['stdout:out-line', 'stderr:err-line']),
      );
      expect(
        controller.output
            .singleWhere((entry) => entry.source == 'stderr')
            .severity,
        TaskOutputSeverity.error,
      );
      expect(
        controller.events.map((event) => event.kind),
        containsAllInOrder([
          TaskEventKind.started,
          TaskEventKind.progress,
          TaskEventKind.output,
          TaskEventKind.output,
          TaskEventKind.progress,
          TaskEventKind.succeeded,
        ]),
      );
      expect(controller.events.last.value?.exitCode, 0);

      controller.dispose();
    });

    test(
      'tracks command metadata while running and clears it on reset',
      () async {
        final script = await _script(tempDir, 'command_metadata', '''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('ready');
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
        final controller = ProcessTaskController(id: 'process');
        final command = _dartScript(script);

        final future = controller.startProcess(command);
        await _waitForOutput(controller, (entry) => entry.text == 'ready');

        expect(controller.command, command);
        expect(controller.status, TaskStatus.running);

        controller.reset();
        expect(controller.command, isNull);
        expect(controller.status, TaskStatus.idle);

        final result = await future;
        expect(result.canceled, isTrue);

        controller.dispose();
      },
    );

    test(
      'marks non-zero exit as a failed task with process metadata',
      () async {
        final script = await _script(tempDir, 'failure', '''
import 'dart:io';

void main() {
  stderr.writeln('bad exit');
  exitCode = 7;
}
''');
        final controller = ProcessTaskController(id: 'process');

        final result = await controller.startProcess(_dartScript(script));

        expect(result.failed, isTrue);
        expect(controller.status, TaskStatus.failed);
        expect(controller.error, isA<ProcessTaskException>());
        final error = controller.error! as ProcessTaskException;
        expect(error.result.exitCode, 7);
        expect(
          controller.output.map((entry) => entry.text),
          contains('bad exit'),
        );
        expect(controller.events.last.kind, TaskEventKind.failed);
        expect(controller.events.last.error, isA<ProcessTaskException>());

        controller.dispose();
      },
    );

    test(
      'sanitizes terminal control sequences before task output storage',
      () async {
        final script = await _script(tempDir, 'unsafe', r'''
import 'dart:io';

void main() {
  stdout.writeln('\x1B[31mred\x1B[0m');
}
''');
        final controller = ProcessTaskController(
          id: 'process',
          maxOutputLineLength: 80,
        );

        final result = await controller.startProcess(_dartScript(script));

        expect(result.succeeded, isTrue);
        final output = controller.output.single;
        expect(output.text, '${replacementCharacter}red$replacementCharacter');
        expect(output.text.contains('\x1B'), isFalse);
        expect(output.text, isNot(contains('[31m')));
        expect(output.sanitized, isTrue);
        expect(output.truncated, isFalse);
        expect(output.originalLength, 12);
        expect(
          controller.events
              .singleWhere((event) {
                return event.kind == TaskEventKind.output;
              })
              .output
              ?.sanitized,
          isTrue,
        );

        controller.dispose();
      },
    );

    test('redacts OSC clipboard payloads before task output storage', () async {
      final script = await _script(tempDir, 'osc52', r'''
import 'dart:io';

void main() {
  stdout.write('\x1B]52;c;U0VDUkVUX1RPS0VO');
  stdout.add([0x07]);
  stdout.writeln('after');
}
''');
      final controller = ProcessTaskController(
        id: 'process',
        maxOutputLineLength: 80,
      );

      final result = await controller.startProcess(_dartScript(script));

      expect(result.succeeded, isTrue);
      final output = controller.output.single;
      expect(output.text, '${replacementCharacter}after');
      expect(output.text, isNot(contains('U0VDUkVUX1RPS0VO')));
      expect(output.sanitized, isTrue);
      expect(output.truncated, isFalse);
      expect(output.originalLength, 29);

      controller.dispose();
    });

    test('tolerates malformed UTF-8 process output', () async {
      final script = await _script(tempDir, 'malformed_utf8', '''
import 'dart:io';

Future<void> main() async {
  stdout.add([0x66, 0x6f, 0xff, 0x6f, 0x0a]);
  await stdout.flush();
}
''');
      final controller = ProcessTaskController(id: 'process');

      final result = await controller.startProcess(_dartScript(script));

      expect(result.succeeded, isTrue);
      expect(controller.output.single.text, 'fo${replacementCharacter}o');
      expect(controller.status, TaskStatus.succeeded);

      controller.dispose();
    });

    test('caps long process output lines before storing events', () async {
      final script = await _script(tempDir, 'huge', '''
import 'dart:io';

void main() {
  stdout.writeln('0123456789abcdef');
}
''');
      final controller = ProcessTaskController(
        id: 'process',
        maxOutputLineLength: 8,
      );

      final result = await controller.startProcess(_dartScript(script));

      expect(result.succeeded, isTrue);
      final output = controller.output.single;
      expect(output.text, '01234567');
      expect(output.sanitized, isFalse);
      expect(output.truncated, isTrue);
      expect(output.originalLength, 16);
      final event = controller.events.singleWhere((event) {
        return event.kind == TaskEventKind.output;
      });
      expect(event.output?.text, '01234567');
      expect(event.output?.truncated, isTrue);

      controller.dispose();
    });

    test('bounds subprocess output that never writes a newline', () async {
      final script = await _script(tempDir, 'unterminated', '''
import 'dart:io';

void main() {
  stdout.write('x' * 70000);
}
''');
      final controller = ProcessTaskController(
        id: 'process',
        maxOutputLineLength: 8,
      );

      final result = await controller.startProcess(_dartScript(script));

      expect(result.succeeded, isTrue);
      expect(controller.output, hasLength(2));
      expect(
        controller.output.every((entry) => entry.text == 'xxxxxxxx'),
        isTrue,
      );
      expect(controller.output.every((entry) => entry.truncated), isTrue);
      expect(controller.output.map((entry) => entry.originalLength), [
        64 * 1024,
        70000 - 64 * 1024,
      ]);

      controller.dispose();
    });

    test('cancels the subprocess and settles the task promptly', () async {
      final script = await _script(tempDir, 'slow', '''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('ready');
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
      final controller = ProcessTaskController(id: 'process');

      final future = controller.startProcess(_dartScript(script));
      await _waitForOutput(controller, (entry) => entry.text == 'ready');
      final process = controller.process;

      controller.cancel();
      final result = await future;

      expect(result.canceled, isTrue);
      expect(controller.status, TaskStatus.canceled);
      expect(controller.output.map((entry) => entry.text), contains('ready'));
      expect(controller.events.last.kind, TaskEventKind.canceled);
      if (process != null) {
        await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }

      controller.dispose();
    });

    test('runs inheritStdio processes without touching stdio pipes', () async {
      final script = await _script(tempDir, 'inherit_stdio', '''
void main() {}
''');
      final controller = ProcessTaskController(id: 'process');

      final result = await controller.startProcess(
        _dartScript(script),
        mode: ProcessStartMode.inheritStdio,
      );

      expect(result.succeeded, isTrue);
      expect(result.value?.exitCode, 0);
      expect(controller.status, TaskStatus.succeeded);
      expect(controller.output, isEmpty);
      expect(controller.process, isNull);

      controller.dispose();
    });

    test('reports inheritStdio non-zero exits as task failures', () async {
      final script = await _script(tempDir, 'inherit_stdio_fail', '''
import 'dart:io';

void main() {
  exitCode = 9;
}
''');
      final controller = ProcessTaskController(id: 'process');

      final result = await controller.startProcess(
        _dartScript(script),
        mode: ProcessStartMode.inheritStdio,
      );

      expect(result.failed, isTrue);
      expect(controller.status, TaskStatus.failed);
      expect(controller.error, isA<ProcessTaskException>());
      final error = controller.error! as ProcessTaskException;
      expect(error.result.exitCode, 9);

      controller.dispose();
    });

    test('rejects detached start modes before spawning', () async {
      final controller = ProcessTaskController(id: 'process');
      const command = ProcessTaskCommand('dart', ['--version']);

      expect(
        () => controller.startProcess(command, mode: ProcessStartMode.detached),
        throwsArgumentError,
      );
      expect(
        () => controller.startProcess(
          command,
          mode: ProcessStartMode.detachedWithStdio,
        ),
        throwsArgumentError,
      );

      // Rejection happens before any state mutation or spawn.
      expect(controller.status, TaskStatus.idle);
      expect(controller.process, isNull);
      expect(controller.command, isNull);
      expect(controller.events, isEmpty);

      controller.dispose();
    });

    test('runs inheritStdio processes through terminal handoff', () async {
      final script = await _script(tempDir, 'inherit_handoff', '''
void main() {}
''');
      final driver = FakeTerminalDriver();
      await driver.enter(TerminalMode.interactive);
      final controller = ProcessTaskController(id: 'process');

      final result = await controller.startProcess(
        _dartScript(script),
        terminalDriver: driver,
        handoffTerminal: true,
        mode: ProcessStartMode.inheritStdio,
      );

      expect(result.succeeded, isTrue);
      expect(controller.status, TaskStatus.succeeded);
      expect(driver.handoffCallCount, 1);
      expect(driver.handoffSuspendCallCount, 1);
      expect(driver.handoffResumeCallCount, 1);
      expect(driver.isActive, isTrue);

      controller.dispose();
      await driver.dispose();
    });

    test(
      'restart during the spawn window kills the superseded child',
      () async {
        final script = await _script(tempDir, 'spawn_window', '''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('ready');
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
        final controller = _GatedSpawnController(id: 'process');
        addTearDown(() {
          for (final process in controller.spawnedProcesses) {
            process.kill(ProcessSignal.sigkill);
          }
        });
        final command = _dartScript(script);
        final hold = controller.holdNextSpawn();

        final first = controller.startProcess(command);
        final second = controller.startProcess(command);

        final firstResult = await first;
        expect(firstResult.canceled, isTrue);

        // The superseded spawn has completed at the OS level but has not yet
        // returned to the controller; the current run is live alongside it.
        final staleProcess = await hold.spawned.timeout(
          const Duration(seconds: 5),
        );
        await _waitForOutput(controller, (entry) => entry.text == 'ready');
        final currentProcess = controller.process;
        expect(currentProcess, isNotNull);
        expect(identical(currentProcess, staleProcess), isFalse);

        hold.release();

        const orphaned = 0x7fffffff;
        final staleExit = await staleProcess.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            staleProcess.kill(ProcessSignal.sigkill);
            return orphaned;
          },
        );
        expect(
          staleExit,
          isNot(orphaned),
          reason: 'a run superseded during spawn must kill its child',
        );
        expect(
          controller.process,
          same(currentProcess),
          reason: 'a stale spawn must not clobber the current process handle',
        );

        controller.cancel();
        final currentExit = await currentProcess!.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            currentProcess.kill(ProcessSignal.sigkill);
            return orphaned;
          },
        );
        expect(currentExit, isNot(orphaned));
        final secondResult = await second.timeout(const Duration(seconds: 5));
        expect(secondResult.canceled, isTrue);

        controller.dispose();
      },
    );

    test('dispose kills the running subprocess', () async {
      final script = await _script(tempDir, 'dispose_slow', '''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('ready');
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
      final controller = ProcessTaskController(id: 'process');

      final future = controller.startProcess(_dartScript(script));
      await _waitForOutput(controller, (entry) => entry.text == 'ready');
      final process = controller.process;
      expect(process, isNotNull);

      controller.dispose();

      const orphaned = 0x7fffffff;
      final exitCode = await process!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return orphaned;
        },
      );
      expect(
        exitCode,
        isNot(orphaned),
        reason: 'dispose() must kill the running child process',
      );
      expect(controller.process, isNull);
      expect(controller.status, TaskStatus.canceled);

      final result = await future;
      expect(result.canceled, isTrue);
    });

    test('can run through terminal handoff when requested', () async {
      final script = await _script(tempDir, 'handoff', '''
import 'dart:io';

void main() {
  stdout.writeln('handoff output');
}
''');
      final driver = FakeTerminalDriver();
      await driver.enter(TerminalMode.interactive);
      final controller = ProcessTaskController(id: 'process');

      final result = await controller.startProcess(
        _dartScript(script),
        terminalDriver: driver,
        handoffTerminal: true,
      );

      expect(result.succeeded, isTrue);
      expect(driver.handoffCallCount, 1);
      expect(driver.handoffSuspendCallCount, 1);
      expect(driver.handoffResumeCallCount, 1);
      expect(driver.isActive, isTrue);
      expect(
        controller.output.map((entry) => entry.text),
        contains('handoff output'),
      );

      controller.dispose();
      await driver.dispose();
    });
  });
}

/// One spawn held open by [_GatedSpawnController.holdNextSpawn].
final class _HeldSpawn {
  final Completer<void> _release = Completer<void>();
  final Completer<Process> _spawnedProcess = Completer<Process>();

  /// Resolves with the real process once the held spawn completes at the OS
  /// level (while the controller still sees the spawn as pending).
  Future<Process> get spawned => _spawnedProcess.future;

  /// Lets the held spawn return to the controller.
  void release() => _release.complete();
}

/// Spawns real processes but can hold a spawn's completion so tests can
/// deterministically exercise the restart-during-spawn window.
final class _GatedSpawnController extends ProcessTaskController {
  _GatedSpawnController({super.id});

  final List<_HeldSpawn> _holds = [];
  final List<Process> spawnedProcesses = [];

  _HeldSpawn holdNextSpawn() {
    final hold = _HeldSpawn();
    _holds.add(hold);
    return hold;
  }

  @override
  Future<Process> spawnProcess(
    ProcessTaskCommand command,
    ProcessStartMode mode,
  ) async {
    // Claim the hold synchronously at entry so it binds to startProcess CALL
    // order; claiming after the await would bind by OS-spawn-completion
    // order, which can invert under load and gate the wrong run.
    final hold = _holds.isNotEmpty ? _holds.removeAt(0) : null;
    final process = await super.spawnProcess(command, mode);
    spawnedProcesses.add(process);
    if (hold != null) {
      hold._spawnedProcess.complete(process);
      await hold._release.future;
    }
    return process;
  }
}
