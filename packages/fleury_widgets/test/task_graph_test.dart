import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<TaskGraphNode> _nodes() {
  return const [
    TaskGraphNode(
      id: 'plan',
      title: 'Create plan',
      status: TaskGraphStatus.succeeded,
    ),
    TaskGraphNode(
      id: 'run',
      title: 'Run checks',
      description: 'dart test\x1b]52;c;secret\x07\nnext',
      status: TaskGraphStatus.running,
      dependsOn: ['plan'],
      progressCurrent: 1,
      progressTotal: 3,
    ),
    TaskGraphNode(
      id: 'ship',
      title: 'Ship',
      status: TaskGraphStatus.pending,
      dependsOn: ['run'],
    ),
  ];
}

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TaskGraph', () {
    group('controller lifecycle', () {
      test('dispose is idempotent and keeps final readable state', () {
        final controller = TaskGraphController(selectedIndex: 2);

        controller.dispose();
        controller.dispose();

        expect(controller.selectedIndex, 2);
        expect(controller.visibleRange, isNull);
      });

      test('mutating after dispose throws a lifecycle error', () {
        final controller = TaskGraphController()..dispose();

        const message = 'TaskGraphController has been disposed.';
        expect(() => controller.selectedIndex = 1, _stateError(message));
        expect(() => controller.jumpToIndex(1), _stateError(message));
      });
    });

    testWidgets('a known total with unknown current renders "— / N"', (tester) {
      tester.pumpWidget(
        TaskGraph(
          nodes: const [
            TaskGraphNode(
              id: 'build',
              title: 'Build',
              status: TaskGraphStatus.running,
              progressTotal: 5,
            ),
          ],
        ),
      );
      final output = tester.renderToString(
        size: const CellSize(60, 4),
        emptyMark: ' ',
      );
      expect(output, contains('Progress: — / 5'));
      expect(output, isNot(contains('Progress: pending')));
    });

    testWidgets('renders sanitized tasks with graph semantics', (tester) {
      final controller = TaskGraphController(selectedIndex: 1);
      tester.pumpWidget(
        TaskGraph(
          semanticLabel: 'Release plan',
          controller: controller,
          nodes: _nodes(),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(80, 6),
        emptyMark: ' ',
      );

      expect(output, contains('[x] Create plan'));
      expect(output, contains('[>] Run checks'));
      expect(output, contains('dart test'));
      expect(output, contains('next'));
      expect(output, contains('Progress: 1 / 3'));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final graph = tester.semantics().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
      );
      expect(graph.state.collectionRowCount, 3);
      expect(graph.state['taskCount'], 3);
      expect(graph.state['runningTaskCount'], 1);
      expect(graph.state['succeededTaskCount'], 1);
      expect(graph.state['pendingTaskCount'], 1);
      expect(graph.state.selectedTaskId, 'run');
      expect(graph.state.selectedTaskStatus, 'running');

      final task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Run checks',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(task.busy, isTrue);
      expect(task.state.taskId, 'run');
      expect(task.state.taskStatus, 'running');
      expect(task.state['dependencyCount'], 1);
      expect(task.state.progressCurrent, 1);
      expect(task.state.progressTotal, 3);
      expect(task.validationError, isNull);
    });

    testWidgets('semantic copy copies selected task', (tester) async {
      TaskGraphCopyResult? copied;
      try {
        final controller = TaskGraphController(selectedIndex: 1);
        tester.pumpWidget(
          TaskGraph(
            controller: controller,
            nodes: _nodes(),
            copyOptions: const TaskGraphCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        );

        tester.render(size: const CellSize(80, 6));
        final result = await tester.invokeSemanticAction(
          SemanticAction.copy,
          role: SemanticRole.task,
          label: 'Run checks',
          selected: true,
        );

        expect(result.completed, isTrue);
        expect(tester.clipboard.readInProcess(), contains('[>] Run checks'));
        expect(tester.clipboard.readInProcess(), contains('Status: running'));
        expect(tester.clipboard.readInProcess(), contains('Depends on: plan'));
        expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
        expect(copied?.node.id, 'run');
        expect(copied?.report.policy.name, 'inProcessOnly');
      } finally {
        // clipboard is tester-scoped; nothing to restore
      }
    });

    testWidgets('semantic focus and activation focus the task graph', (
      tester,
    ) async {
      final controller = TaskGraphController(selectedIndex: 0);
      tester.pumpWidget(
        TaskGraph(
          semanticLabel: 'Release plan',
          controller: controller,
          nodes: _nodes(),
        ),
      );

      tester.render(size: const CellSize(80, 6));
      var graph = tester.semantics().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
        action: SemanticAction.focus,
      );
      expect(graph.focused, isFalse);
      expect(graph.actions, contains(SemanticAction.navigate));

      var result = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.taskGraph,
        label: 'Release plan',
      );
      expect(result.completed, isTrue);

      tester.render(size: const CellSize(80, 6));
      graph = tester.semantics().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
        focused: true,
      );
      expect(graph.state.selectedTaskId, 'plan');

      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.task,
        label: 'Run checks',
      );
      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 1);

      tester.render(size: const CellSize(80, 6));
      final task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Run checks',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(task.state.taskId, 'run');

      graph = tester.semantics().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
        focused: true,
      );
      expect(graph.state.selectedTaskId, 'run');
      expect(graph.state['selectedIndex'], 1);
    });

    testWidgets('semantic activate selects a task node', (tester) async {
      final controller = TaskGraphController(selectedIndex: 0);
      tester.pumpWidget(
        TaskGraph(
          semanticLabel: 'Release plan',
          controller: controller,
          nodes: _nodes(),
        ),
      );

      tester.render(size: const CellSize(80, 6));
      var task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Run checks',
        action: SemanticAction.activate,
      );
      expect(task.selected, isFalse);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.task,
        label: 'Run checks',
      );

      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 1);

      tester.render(size: const CellSize(80, 6));
      task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Run checks',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(task.state.taskId, 'run');

      final graph = tester.semantics().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
      );
      expect(graph.state.selectedTaskId, 'run');
    });

    testWidgets('preserves selected task identity across node refresh', (
      tester,
    ) {
      final controller = TaskGraphController(selectedIndex: 2);
      tester.pumpWidget(
        TaskGraph(
          semanticLabel: 'Release plan',
          controller: controller,
          nodes: _nodes(),
        ),
      );
      tester.render(size: const CellSize(80, 6));

      tester.pumpWidget(
        TaskGraph(
          semanticLabel: 'Release plan',
          controller: controller,
          nodes: const [
            TaskGraphNode(
              id: 'plan',
              title: 'Create plan',
              status: TaskGraphStatus.succeeded,
            ),
            TaskGraphNode(
              id: 'review',
              title: 'Review plan',
              status: TaskGraphStatus.succeeded,
              dependsOn: ['plan'],
            ),
            TaskGraphNode(
              id: 'run',
              title: 'Run checks',
              status: TaskGraphStatus.succeeded,
              dependsOn: ['review'],
            ),
            TaskGraphNode(
              id: 'ship',
              title: 'Ship',
              status: TaskGraphStatus.running,
              dependsOn: ['run'],
              progressCurrent: 1,
              progressTotal: 2,
            ),
          ],
        ),
      );
      tester.render(size: const CellSize(80, 7));
      tester.pump();
      tester.render(size: const CellSize(80, 7));

      expect(controller.selectedIndex, 3);
      final graph = tester.semantics().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
      );
      expect(graph.state.selectedTaskId, 'ship');
      expect(graph.state.selectedTaskStatus, 'running');

      final selected = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Ship',
        selected: true,
      );
      expect(selected.state.taskId, 'ship');
      expect(selected.state.progressCurrent, 1);
      expect(selected.state.progressTotal, 2);
    });

    test('exportTaskGraphNode sanitizes task details', () {
      final text = exportTaskGraphNode(_nodes()[1]);

      expect(text, contains('[>] Run checks'));
      expect(text, contains('Status: running'));
      expect(text, contains('Description: dart test'));
      expect(text, contains('Depends on: plan'));
      expect(text, contains('Progress: 1 / 3'));
      expect(text, isNot(contains('secret')));
    });

    testWidgets('accessibility snapshot describes task graph state', (tester) {
      tester.pumpWidget(TaskGraph(semanticLabel: 'Release plan', nodes: _nodes()));
      tester.render(size: const CellSize(80, 6));

      final graph = tester.accessibilitySnapshot().single(
        role: SemanticRole.taskGraph,
        label: 'Release plan',
      );
      expect(
        graph.states,
        contains(
          'task graph 3 tasks, 1 running, 1 succeeded, 1 pending, selected plan',
        ),
      );

      final task = tester.accessibilitySnapshot().single(
        role: SemanticRole.task,
        label: 'Run checks',
      );
      expect(task.states, contains('task run, running, 1 dependencies'));
    });
  });
}
