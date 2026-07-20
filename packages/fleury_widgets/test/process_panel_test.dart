import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessPanel', () {
    test('maps task output to log entries with sanitizer metadata', () {
      final entries = buildProcessOutputLogEntries(const [
        TaskOutput(sequence: 1, source: 'stdout', text: 'ok'),
        TaskOutput(
          sequence: 2,
          source: 'stderr',
          text: 'bad',
          severity: TaskOutputSeverity.error,
          sanitized: true,
          truncated: true,
          originalLength: 80,
        ),
      ]);

      expect(entries, hasLength(2));
      expect(entries.first.id, 1);
      expect(entries.first.severity, LogSeverity.info);
      expect(entries.last.source, 'stderr');
      expect(entries.last.severity, LogSeverity.error);
      expect(entries.last.metadata['outputSanitized'], isTrue);
      expect(entries.last.metadata['outputTruncated'], isTrue);
      expect(entries.last.metadata['outputOriginalLength'], 80);
    });

    testWidgets('renders process status and output semantics', (tester) async {
      final command = ProcessTaskCommand('dart', ['--version']);
      final controller = ProcessTaskController(id: 'doctor', label: 'Doctor');

      await controller.start((context) {
        context.reportProgress(current: 1, total: 2, label: 'checking');
        context.write('ok', source: 'stdout');
        context.write(
          'warn',
          source: 'stderr',
          severity: TaskOutputSeverity.error,
          sanitized: true,
          originalLength: 12,
        );
        return ProcessTaskResult(command: command, exitCode: 0);
      });

      tester.pumpWidget(
        SizedBox(
          width: 80,
          height: 8,
          child: ProcessPanel(
            controller: controller,
            command: command,
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(80, 8),
        emptyMark: ' ',
      );

      expect(output, contains('Doctor: succeeded - dart --version'));
      expect(output, contains('checking'));
      expect(output, contains('[INFO stdout] ok'));
      expect(output, contains('[ERROR stderr] warn'));

      final tree = tester.semantics();
      final task = tree.single(role: SemanticRole.task);
      expect(task.label, 'Doctor');
      expect(task.value, 'succeeded');
      expect(task.state.taskId, 'doctor');
      expect(task.state.taskLabel, 'Doctor');
      expect(task.state.taskStatus, 'succeeded');
      expect(task.state.outputCount, 2);
      expect(task.state['command'], 'dart --version');
      expect(task.state['exitCode'], 0);
      expect(task.state['processSucceeded'], isTrue);
      expect(task.state.source, 'stderr');
      expect(task.state.outputSanitized, isTrue);
      expect(task.state.outputOriginalLength, 12);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.task,
        label: 'Doctor',
      );
      expect(
        fallback.states.join('\n'),
        contains(
          'task doctor, succeeded, 5 events, last succeeded, 2 outputs, '
          'command dart --version, exit 0, process succeeded',
        ),
      );

      final log = tree.single(role: SemanticRole.log);
      expect(log.label, 'Doctor output');
      expect(log.state.collectionRowCount, 2);

      final stderr = tree
          .byRole(SemanticRole.listItem)
          .singleWhere((node) => node.state.source == 'stderr');
      expect(stderr.state['taskOutputSequence'], 2);
      expect(stderr.state.outputSanitized, isTrue);
      expect(stderr.state.outputOriginalLength, 12);

      controller.dispose();
    });

    testWidgets('filters output and copies the selected visible entry', (
      tester,
    ) async {
      final command = ProcessTaskCommand('tool', ['run']);
      final controller = ProcessTaskController(id: 'build');
      LogRegionCopyResult? copied;

      await controller.start((context) {
        context.write('compile ok', source: 'stdout');
        context.write(
          'deploy failed',
          source: 'stderr',
          severity: TaskOutputSeverity.error,
        );
        return ProcessTaskResult(command: command, exitCode: 0);
      });

      tester.pumpWidget(
        SizedBox(
          width: 70,
          height: 6,
          child: ProcessPanel(
            controller: controller,
            command: command,
            autofocus: true,
            outputFilter: const LogRegionFilterDescriptor(query: 'deploy'),
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(70, 6),
        emptyMark: ' ',
      );

      expect(output, contains('[ERROR stderr] deploy failed'));
      expect(output, isNot(contains('compile ok')));

      final log = tester.semantics().single(role: SemanticRole.log);
      expect(log.state.collectionRowCount, 1);
      expect(log.state['filterActive'], isTrue);
      expect(log.state.filterText, 'deploy');

      tester.sendKey(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '[ERROR stderr] deploy failed');
      expect(copied, isNotNull);
      expect(copied!.entryIndex, 1);
      expect(copied!.viewIndex, 0);

      controller.dispose();
    });

    testWidgets('running process exposes cancel action and Escape cancels', (
      tester,
    ) async {
      final controller = ProcessTaskController(
        id: 'slow',
        label: 'Slow process',
      );
      final started = Completer<void>();
      final finish = Completer<void>();

      final future = controller.start((context) async {
        context.write('ready', source: 'stdout');
        started.complete();
        await finish.future;
        context.checkCancellation();
        return ProcessTaskResult(
          command: const ProcessTaskCommand('slow'),
          exitCode: 0,
        );
      });
      await started.future;

      tester.pumpWidget(
        SizedBox(
          width: 70,
          height: 6,
          child: ProcessPanel(controller: controller, autofocus: true),
        ),
      );
      tester.render(size: const CellSize(70, 6));

      var task = tester.semantics().single(role: SemanticRole.task);
      expect(task.busy, isTrue);
      expect(task.actions, contains(SemanticAction.cancel));
      expect(task.state['canCancel'], isTrue);

      tester.sendKey(const KeyEvent(KeyCode.escape));
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, TaskStatus.canceled);
      final result = await future;
      expect(result.canceled, isTrue);

      finish.complete();
      await Future<void>.delayed(Duration.zero);

      task = tester.semantics().single(role: SemanticRole.task);
      expect(task.value, 'canceled');
      expect(task.actions, isNot(contains(SemanticAction.cancel)));
      expect(task.state['canCancel'], isFalse);

      controller.dispose();
    });

    testWidgets('semantic cancel uses the running task cancellation path', (
      tester,
    ) async {
      final controller = ProcessTaskController(
        id: 'semantic-slow',
        label: 'Semantic slow process',
      );
      final started = Completer<void>();
      final finish = Completer<void>();

      final future = controller.start((context) async {
        context.write('ready', source: 'stdout');
        started.complete();
        await finish.future;
        context.checkCancellation();
        return ProcessTaskResult(
          command: const ProcessTaskCommand('slow'),
          exitCode: 0,
        );
      });
      await started.future;

      tester.pumpWidget(
        SizedBox(
          width: 70,
          height: 6,
          child: ProcessPanel(controller: controller),
        ),
      );
      tester.render(size: const CellSize(70, 6));

      final result = await tester.invokeSemanticAction(
        SemanticAction.cancel,
        role: SemanticRole.task,
        label: 'Semantic slow process',
      );

      expect(result.completed, isTrue);
      expect(controller.status, TaskStatus.canceled);
      expect((await future).canceled, isTrue);
      finish.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.task, label: 'Semantic slow process')
            .actions,
        isNot(contains(SemanticAction.cancel)),
      );

      controller.dispose();
    });
  });
}
