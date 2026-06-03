import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TaskController', () {
    test('reports progress, output, and success result', () async {
      final controller = TaskController<String>(
        id: 'index',
        label: 'Index workspace',
      );

      final result = await controller.start((context) {
        context.reportProgress(current: 1, total: 4, label: 'scanning');
        context.write('started', source: 'worker');
        return 'done';
      });

      expect(result.succeeded, isTrue);
      expect(result.value, 'done');
      expect(controller.status, TaskStatus.succeeded);
      expect(controller.value, 'done');
      expect(controller.progress?.fraction, closeTo(0.25, 0.0001));
      expect(controller.progress?.label, 'scanning');
      expect(controller.output, hasLength(1));
      expect(controller.output.single.sequence, 1);
      expect(controller.output.single.source, 'worker');
      expect(controller.output.single.text, 'started');
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.started,
        TaskEventKind.progress,
        TaskEventKind.output,
        TaskEventKind.succeeded,
      ]);
      expect(controller.events.map((event) => event.sequence), [1, 2, 3, 4]);
      expect(controller.events.map((event) => event.runId).toSet(), {1});
      expect(controller.events[1].progress?.label, 'scanning');
      expect(controller.events[2].output?.text, 'started');
      expect(controller.events.last.value, 'done');

      controller.dispose();
    });

    test('captures failure and stack trace', () async {
      final controller = TaskController<void>(id: 'deploy');

      final result = await controller.start((context) {
        throw StateError('boom');
      });

      expect(result.failed, isTrue);
      expect(result.error, isA<StateError>());
      expect(result.stackTrace, isNotNull);
      expect(controller.status, TaskStatus.failed);
      expect(controller.error, isA<StateError>());
      expect(controller.stackTrace, isNotNull);
      expect(controller.events.last.kind, TaskEventKind.failed);
      expect(controller.events.last.error, isA<StateError>());
      expect(controller.events.last.stackTrace, isNotNull);

      controller.dispose();
    });

    test('cancellation updates UI state and ignores late output', () async {
      final controller = TaskController<void>(id: 'slow');
      final started = Completer<void>();
      final finish = Completer<void>();

      final future = controller.start((context) async {
        context.reportProgress(current: 1, total: 10, label: 'running');
        context.write('before cancel');
        started.complete();
        await finish.future;
        context.reportProgress(current: 10, total: 10, label: 'late');
        context.write('after cancel');
        context.checkCancellation();
      });

      await started.future;
      expect(controller.status, TaskStatus.running);
      expect(controller.canCancel, isTrue);

      controller.cancel();

      expect(controller.status, TaskStatus.canceled);
      expect(controller.canCancel, isFalse);

      final result = await future;
      expect(result.canceled, isTrue);

      finish.complete();
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, TaskStatus.canceled);
      expect(controller.progress?.label, 'running');
      expect(controller.output.map((entry) => entry.text), ['before cancel']);
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.started,
        TaskEventKind.progress,
        TaskEventKind.output,
        TaskEventKind.canceled,
      ]);

      controller.dispose();
    });

    test('dispose cancels active run and ignores late task writes', () async {
      final controller = TaskController<void>(id: 'dispose-active');
      final started = Completer<void>();
      final finish = Completer<void>();

      final future = controller.start((context) async {
        context.reportProgress(current: 1, total: 10, label: 'before dispose');
        context.write('before dispose');
        started.complete();
        await finish.future;
        context.reportProgress(current: 10, total: 10, label: 'after dispose');
        context.write('after dispose');
      });

      await started.future;
      controller.dispose();

      final result = await future;
      expect(result.canceled, isTrue);
      expect(controller.status, TaskStatus.canceled);
      expect(controller.canCancel, isFalse);
      expect(controller.progress?.label, 'before dispose');
      expect(controller.output.map((entry) => entry.text), ['before dispose']);
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.started,
        TaskEventKind.progress,
        TaskEventKind.output,
        TaskEventKind.canceled,
      ]);

      finish.complete();
      await Future<void>.delayed(Duration.zero);

      expect(controller.progress?.label, 'before dispose');
      expect(controller.output.map((entry) => entry.text), ['before dispose']);
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.started,
        TaskEventKind.progress,
        TaskEventKind.output,
        TaskEventKind.canceled,
      ]);
    });

    test(
      'start and reset throw after dispose while cancel stays idempotent',
      () {
        final controller = TaskController<void>(id: 'disposed');

        controller.dispose();
        controller.cancel();

        expect(
          () => controller.start((context) {}),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'TaskController has been disposed.',
            ),
          ),
        );
        expect(
          controller.reset,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'TaskController has been disposed.',
            ),
          ),
        );
        controller.dispose();
      },
    );

    test('restart cancels stale runs and preserves newer result', () async {
      final controller = TaskController<String>(id: 'restartable');
      final slowStarted = Completer<void>();
      final slowFinish = Completer<void>();

      final slow = controller.start((context) async {
        context.write('slow');
        slowStarted.complete();
        await slowFinish.future;
        throw StateError('stale failure');
      });

      await slowStarted.future;

      final fast = await controller.start((context) {
        context.write('fast');
        return 'newer';
      });
      slowFinish.complete();
      final stale = await slow;

      expect(stale.canceled, isTrue);
      expect(fast.succeeded, isTrue);
      expect(controller.status, TaskStatus.succeeded);
      expect(controller.value, 'newer');
      expect(controller.output.map((entry) => entry.text), ['fast']);
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.started,
        TaskEventKind.output,
        TaskEventKind.canceled,
        TaskEventKind.started,
        TaskEventKind.output,
        TaskEventKind.succeeded,
      ]);
      expect(controller.events.last.runId, 2);

      controller.dispose();
    });

    test('reset returns to idle and clears run state', () async {
      final controller = TaskController<String>(id: 'resettable');

      await controller.start((context) {
        context.reportProgress(current: 1, total: 1, label: 'done');
        context.write('line');
        return 'value';
      });

      controller.reset();

      expect(controller.status, TaskStatus.idle);
      expect(controller.value, isNull);
      expect(controller.error, isNull);
      expect(controller.progress, isNull);
      expect(controller.output, isEmpty);
      expect(controller.events.last.kind, TaskEventKind.reset);
      expect(controller.events.last.status, TaskStatus.idle);

      controller.dispose();
    });

    test('keeps bounded event history', () async {
      final controller = TaskController<void>(
        id: 'bounded',
        maxEventEntries: 3,
      );

      await controller.start((context) {
        context.reportProgress(current: 1, total: 2);
        context.write('line');
      });

      expect(controller.events, hasLength(3));
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.progress,
        TaskEventKind.output,
        TaskEventKind.succeeded,
      ]);
      expect(controller.events.map((event) => event.sequence), [2, 3, 4]);

      controller.dispose();
    });
  });

  group('TaskYieldPolicy', () {
    test('reports progress and yields between cooperative batches', () async {
      final controller = TaskController<int>(id: 'cooperative');

      final result = await controller.start((context) async {
        final checkpoint = const TaskYieldPolicy(
          itemBudget: 1,
          elapsedBudget: Duration(days: 1),
        ).start(context);
        for (var i = 0; i < 3; i++) {
          await checkpoint.tick(
            current: i + 1,
            total: 3,
            label: 'chunk ${i + 1}',
          );
        }
        return 3;
      });

      expect(result.succeeded, isTrue);
      expect(controller.value, 3);
      expect(controller.progress?.current, 3);
      expect(controller.progress?.total, 3);
      expect(controller.progress?.label, 'chunk 3');
      expect(
        controller.events.where(
          (event) => event.kind == TaskEventKind.progress,
        ),
        hasLength(3),
      );

      controller.dispose();
    });

    test('observes cancellation after yielding', () async {
      final controller = TaskController<int>(id: 'cancel-cooperative');
      final started = Completer<void>();
      var processed = 0;

      final future = controller.start((context) async {
        final checkpoint = const TaskYieldPolicy(
          itemBudget: 1,
          elapsedBudget: Duration(days: 1),
        ).start(context);
        for (var i = 0; i < 10; i++) {
          processed += 1;
          if (processed == 1) started.complete();
          await checkpoint.tick(current: processed, total: 10);
        }
        return processed;
      });

      await started.future;
      controller.cancel();
      final result = await future;

      expect(result.canceled, isTrue);
      expect(processed, lessThan(10));
      expect(controller.status, TaskStatus.canceled);

      controller.dispose();
    });
  });

  group('DebouncedTaskController', () {
    test(
      'dispose is idempotent, cancels pending work, and keeps state readable',
      () async {
        final controller = DebouncedTaskController<String>(
          delay: const Duration(milliseconds: 30),
          id: 'search-index',
        );
        var runs = 0;

        final pending = controller.schedule((context) {
          runs += 1;
          return 'late';
        });
        expect(controller.isPending, isTrue);
        expect(controller.canCancel, isTrue);

        controller.dispose();
        controller.dispose();

        final result = await pending;
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(result.canceled, isTrue);
        expect(runs, 0);
        expect(controller.isPending, isFalse);
        expect(controller.isRunning, isFalse);
        expect(controller.canCancel, isFalse);
        expect(controller.status, TaskStatus.idle);
        expect(controller.progress, isNull);
        expect(controller.value, isNull);
        expect(controller.error, isNull);
        expect(controller.output, isEmpty);
        expect(controller.events, isEmpty);
      },
    );

    test('mutating after dispose throws a lifecycle error', () {
      final controller = DebouncedTaskController<String>(
        delay: const Duration(milliseconds: 10),
      )..dispose();

      const message = 'DebouncedTaskController has been disposed.';
      expect(
        () => controller.schedule((context) => 'late'),
        _stateError(message),
      );
      expect(() => controller.runNow((context) => 'now'), _stateError(message));
      expect(controller.reset, _stateError(message));
      expect(controller.cancel, returnsNormally);
    });

    test(
      'disposing an external task controller only detaches the wrapper',
      () async {
        final taskController = TaskController<String>(id: 'external-task');
        final controller = DebouncedTaskController<String>(
          delay: Duration.zero,
          taskController: taskController,
        );

        controller.dispose();

        final result = await taskController.start(
          (context) => 'external result',
        );
        expect(result.succeeded, isTrue);
        expect(result.value, 'external result');
        expect(taskController.status, TaskStatus.succeeded);
        expect(controller.status, TaskStatus.succeeded);

        taskController.dispose();
      },
    );

    test('coalesces pending starts into the latest task', () async {
      final controller = DebouncedTaskController<String>(
        delay: const Duration(milliseconds: 10),
        id: 'search-index',
      );
      var runs = 0;

      final first = controller.schedule((context) {
        runs += 1;
        return 'first';
      });
      expect(controller.isPending, isTrue);
      expect(controller.canCancel, isTrue);

      final second = controller.schedule((context) {
        runs += 1;
        context.reportProgress(current: 1, total: 1, label: 'indexed');
        return 'second';
      });

      final firstResult = await first;
      expect(firstResult.canceled, isTrue);

      final secondResult = await second;
      expect(secondResult.succeeded, isTrue);
      expect(secondResult.value, 'second');
      expect(runs, 1);
      expect(controller.isPending, isFalse);
      expect(controller.status, TaskStatus.succeeded);
      expect(controller.progress?.label, 'indexed');
      expect(controller.events.map((event) => event.kind), [
        TaskEventKind.started,
        TaskEventKind.progress,
        TaskEventKind.succeeded,
      ]);

      controller.dispose();
    });

    test('cancel prevents pending work from starting', () async {
      final controller = DebouncedTaskController<void>(
        delay: const Duration(milliseconds: 10),
      );
      var runs = 0;

      final pending = controller.schedule((context) {
        runs += 1;
      });
      controller.cancel();

      final result = await pending;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result.canceled, isTrue);
      expect(runs, 0);
      expect(controller.isPending, isFalse);
      expect(controller.status, TaskStatus.idle);

      controller.dispose();
    });

    test('new schedules cancel running work and keep latest result', () async {
      final controller = DebouncedTaskController<String>(
        delay: Duration.zero,
        id: 'typeahead',
      );
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();

      final first = controller.schedule((context) async {
        firstStarted.complete();
        await releaseFirst.future;
        context.checkCancellation();
        return 'old';
      });
      await firstStarted.future;
      expect(controller.isRunning, isTrue);

      final second = controller.schedule((context) => 'new');
      final secondResult = await second;
      releaseFirst.complete();
      final firstResult = await first;

      expect(firstResult.canceled, isTrue);
      expect(secondResult.succeeded, isTrue);
      expect(secondResult.value, 'new');
      expect(controller.status, TaskStatus.succeeded);
      expect(controller.value, 'new');

      controller.dispose();
    });

    test('runNow skips pending debounce', () async {
      final controller = DebouncedTaskController<String>(
        delay: const Duration(milliseconds: 50),
      );
      var pendingRan = false;

      final pending = controller.schedule((context) {
        pendingRan = true;
        return 'pending';
      });
      final immediate = await controller.runNow((context) => 'now');
      final pendingResult = await pending;

      expect(pendingResult.canceled, isTrue);
      expect(immediate.succeeded, isTrue);
      expect(immediate.value, 'now');
      expect(pendingRan, isFalse);
      expect(controller.value, 'now');

      controller.dispose();
    });
  });

  group('TaskStatusView', () {
    testWidgets('exposes semantic task state', (tester) async {
      final controller = TaskController<void>(
        id: 'semantic-task',
        label: 'Semantic task',
      );
      final finish = Completer<void>();

      tester.pumpWidget(
        TaskStatusView<void>(
          controller: controller,
          child: const Text('task body'),
        ),
      );

      var task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Semantic task',
      );
      expect(task.value, 'idle');
      expect(task.state.taskId, 'semantic-task');
      expect(task.state.taskStatus, 'idle');
      expect(task.state.taskEventCount, 0);
      expect(task.actions, isNot(contains(SemanticAction.cancel)));

      final future = controller.start((context) async {
        context.reportProgress(current: 2, total: 4, label: 'half');
        context.write(
          'streamed chunk',
          source: 'worker',
          severity: TaskOutputSeverity.warning,
        );
        await finish.future;
      });
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Semantic task',
        busy: true,
        action: SemanticAction.cancel,
      );
      expect(task.value, 'running');
      expect(task.state.taskStatus, 'running');
      expect(task.state.taskEventCount, 3);
      expect(task.state.lastTaskEventKind, 'output');
      expect(task.state.progressCurrent, 2);
      expect(task.state.progressTotal, 4);
      expect(task.state.progressLabel, 'half');
      expect(task.state.outputCount, 1);
      expect(task.state.source, 'worker');
      expect(task.state.severity, 'warning');
      expect(task.state.outputSanitized, isFalse);
      expect(task.state.outputTruncated, isFalse);

      finish.complete();
      await future;
      tester.pump();

      task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Semantic task',
      );
      expect(task.value, 'succeeded');
      expect(task.busy, isFalse);
      expect(task.state.lastTaskEventKind, 'succeeded');

      controller.dispose();
    });

    testWidgets('semantic cancel dispatches to the task controller', (
      tester,
    ) async {
      final controller = TaskController<void>(
        id: 'cancelable-task',
        label: 'Cancelable task',
      );
      final finish = Completer<void>();

      tester.pumpWidget(
        TaskStatusView<void>(
          controller: controller,
          child: const Text('task body'),
        ),
      );

      final future = controller.start((context) async {
        context.reportProgress(current: 1, total: 2, label: 'running');
        await finish.future;
      });
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      final result = await tester.invokeSemanticAction(
        SemanticAction.cancel,
        role: SemanticRole.task,
        label: 'Cancelable task',
      );

      expect(result.completed, isTrue);
      expect(controller.status, TaskStatus.canceled);
      expect(controller.canCancel, isFalse);
      expect(controller.events.last.kind, TaskEventKind.canceled);
      final canceled = await future;
      expect(canceled.canceled, isTrue);

      finish.complete();
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      final task = tester.semantics().single(
        role: SemanticRole.task,
        label: 'Cancelable task',
      );
      expect(task.value, 'canceled');
      expect(task.busy, isFalse);
      expect(task.actions, isNot(contains(SemanticAction.cancel)));
      expect(task.state.lastTaskEventKind, 'canceled');

      controller.dispose();
    });
  });
}
