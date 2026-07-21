import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

const _start = CommandId('process.doctor.start');
const _cancel = CommandId('process.doctor.cancel');

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
  group('ProcessCommandRunner', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'fleury_process_command_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates start and cancel app commands around a process task', () {
      final controller = ProcessTaskController(id: 'Doctor Run');
      final runner = ProcessCommandRunner(
        controller: controller,
        command: const ProcessTaskCommand('dart', ['--version']),
        shortcuts: [KeySequence.ctrl.r],
        cancelShortcuts: [KeySequence.ctrl.x],
      );

      expect(runner.startCommandId.value, 'process.doctor-run.start');
      expect(runner.cancelCommandId.value, 'process.doctor-run.cancel');
      expect(runner.startCommand.title, 'Run dart --version');
      expect(runner.startCommand.primaryShortcutLabel, 'Ctrl+R');
      expect(runner.startCommand.semanticAction, SemanticAction.start);
      expect(runner.cancelCommand.title, 'Cancel dart --version');
      expect(runner.cancelCommand.primaryShortcutLabel, 'Ctrl+X');
      expect(runner.cancelCommand.semanticAction, SemanticAction.cancel);
      expect(runner.commands.map((command) => command.id), [
        runner.startCommandId,
        runner.cancelCommandId,
      ]);

      controller.dispose();
    });

    test(
      'start command launches process without blocking invocation',
      () async {
        final script = await _script(tempDir, 'slow', '''
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  stdout.writeln('ready');
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
        final controller = ProcessTaskController(id: 'doctor');
        final command = _dartScript(script);
        final runner = ProcessCommandRunner(
          controller: controller,
          command: command,
          startCommandId: _start,
          cancelCommandId: _cancel,
          title: 'Run Doctor',
          cancelTitle: 'Cancel Doctor',
        );
        final registry = CommandRegistry(commands: runner.commands);

        final startResult = await registry.invoke(_start);
        expect(startResult.status, CommandInvocationStatus.completed);
        expect(controller.status, TaskStatus.running);
        expect(controller.command, same(command));

        await _waitForOutput(controller, (entry) => entry.text == 'ready');
        expect(
          registry.command(_start)!.enabled(_FakeCommandContext(registry)),
          isFalse,
        );
        expect(
          registry.command(_cancel)!.enabled(_FakeCommandContext(registry)),
          isTrue,
        );

        final process = controller.process;
        final cancelResult = await registry.invoke(_cancel);
        expect(cancelResult.status, CommandInvocationStatus.completed);
        expect(controller.status, TaskStatus.canceled);
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
        registry.dispose();
      },
    );

    test('direct start returns the process task result', () async {
      final script = await _script(tempDir, 'success', '''
import 'dart:io';

void main() {
  stdout.writeln('done');
}
''');
      final controller = ProcessTaskController(id: 'doctor');
      final command = _dartScript(script);
      final runner = ProcessCommandRunner(
        controller: controller,
        command: command,
      );

      final result = await runner.start();

      expect(result.succeeded, isTrue);
      expect(result.value?.exitCode, 0);
      expect(controller.status, TaskStatus.succeeded);
      expect(controller.output.single.text, 'done');
      expect(controller.command, same(command));

      controller.dispose();
    });

    testWidgets('ProcessCommandScope refreshes command semantics', (
      tester,
    ) async {
      final controller = ProcessTaskController(id: 'doctor');
      final runner = ProcessCommandRunner(
        controller: controller,
        command: const ProcessTaskCommand('dart', ['--version']),
        startCommandId: _start,
        cancelCommandId: _cancel,
        title: 'Run Doctor',
        cancelTitle: 'Cancel Doctor',
      );
      final finish = Completer<void>();

      tester.pumpWidget(
        ProcessCommandScope(
          runner: runner,
          child: const Focus(autofocus: true, child: Text('body')),
        ),
      );

      var tree = tester.semantics();
      var start = tree.single(role: SemanticRole.command, label: 'Run Doctor');
      var cancel = tree.single(
        role: SemanticRole.command,
        label: 'Cancel Doctor',
      );
      expect(start.enabled, isTrue);
      expect(cancel.enabled, isFalse);

      final future = controller.start((context) async {
        context.write('running');
        await finish.future;
        context.checkCancellation();
        return const ProcessTaskResult(
          command: ProcessTaskCommand('dart', ['--version']),
          exitCode: 0,
        );
      });
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      tree = tester.semantics();
      start = tree.single(role: SemanticRole.command, label: 'Run Doctor');
      cancel = tree.single(role: SemanticRole.command, label: 'Cancel Doctor');
      expect(start.enabled, isFalse);
      expect(cancel.enabled, isTrue);

      controller.cancel();
      final result = await future;
      expect(result.canceled, isTrue);
      finish.complete();
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      tree = tester.semantics();
      start = tree.single(role: SemanticRole.command, label: 'Run Doctor');
      cancel = tree.single(role: SemanticRole.command, label: 'Cancel Doctor');
      expect(start.enabled, isTrue);
      expect(cancel.enabled, isFalse);

      controller.dispose();
    });
  });
}

final class _FakeCommandContext implements CommandContext {
  const _FakeCommandContext(this.commands);

  @override
  final CommandRegistry commands;

  @override
  BuildContext? get buildContext => null;
}
