import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('frame failures fail the pending invocation instead of hanging', (
    tester,
  ) async {
    final broken = ValueNotifier(false);
    addTearDown(broken.dispose);
    tester.pumpWidget(
      FleuryApp(
        title: 'Broken',
        commands: [
          AppCommand(
            id: const CommandId('break'),
            title: 'Break',
            run: (_) {
              broken.value = true;
              return Completer<void>().future;
            },
          ),
        ],
        home: NotifierBuilder(
          notifier: broken,
          builder: (_, _) {
            if (broken.value) throw StateError('pending frame failed');
            return const Text('Ready');
          },
        ),
      ),
    );
    await expectLater(
      tester
          .invokeCommand(const CommandId('break'))
          .timeout(const Duration(seconds: 1)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'pending frame failed',
        ),
      ),
    );
  });

  testWidgets(
    'another action can answer a pending invocation without advancing time',
    (tester) async {
      final answer = Completer<void>();
      final waiting = Completer<void>();
      tester.pumpWidget(
        FleuryApp(
          title: 'Confirm',
          commands: [
            AppCommand(
              id: const CommandId('ask'),
              title: 'Ask',
              run: (_) async {
                tester.binding.addPostFrameCallback((_) => waiting.complete());
                await answer.future;
                final done = Completer<void>();
                tester.binding.addPostFrameCallback((_) => done.complete());
                await done.future;
              },
            ),
            AppCommand(
              id: const CommandId('answer'),
              title: 'Answer',
              run: (_) => answer.complete(),
            ),
          ],
          home: const Text('Confirm'),
        ),
      );
      final pending = tester.invokeCommand(const CommandId('ask'));
      await waiting.future.timeout(const Duration(seconds: 1));
      expect(answer.isCompleted, isFalse);
      expect(
        (await tester.invokeCommand(const CommandId('answer'))).status,
        CommandInvocationStatus.completed,
      );
      expect(
        (await pending.timeout(const Duration(seconds: 1))).status,
        CommandInvocationStatus.completed,
      );
      expect(tester.clock.now, Duration.zero);
    },
  );

  testWidgets('disposing a tester releases pending action waits', (
    tester,
  ) async {
    tester.pumpWidget(
      FleuryApp(
        title: 'Pending',
        commands: [
          AppCommand(
            id: const CommandId('wait'),
            title: 'Wait',
            run: (_) => Completer<void>().future,
          ),
        ],
        home: const Text('Pending'),
      ),
    );
    final result = tester.invokeCommand(const CommandId('wait'));
    final expectation = expectLater(result, throwsStateError);
    tester.dispose();
    await expectation;
  });

  for (final semantic in [false, true]) {
    testWidgets(
      '${semantic ? "semantic action" : "command"} can dispose during startup',
      (tester) async {
        Future<void> run() {
          tester.dispose();
          return Completer<void>().future;
        }

        tester.pumpWidget(
          FleuryApp(
            title: 'Dispose',
            commands: [
              AppCommand(
                id: const CommandId('dispose'),
                title: 'Dispose',
                run: (_) => run(),
              ),
            ],
            home: Semantics(
              role: SemanticRole.button,
              label: 'Dispose',
              actions: const {SemanticAction.activate},
              onAction: (_) => run(),
              child: const Text('Dispose'),
            ),
          ),
        );
        final Future<Object?> result = semantic
            ? tester.invokeSemanticAction(
                SemanticAction.activate,
                role: SemanticRole.button,
                label: 'Dispose',
              )
            : tester.invokeCommand(const CommandId('dispose'));
        await expectLater(
          result.timeout(const Duration(seconds: 1)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'FleuryTester disposed during an action.',
            ),
          ),
        );
      },
    );
  }

  testWidgets('a failed command after a frame preserves its outcome', (
    tester,
  ) async {
    tester.pumpWidget(
      FleuryApp(
        title: 'Failed',
        commands: [
          AppCommand(
            id: const CommandId('fail'),
            title: 'Fail',
            run: (_) async {
              final done = Completer<void>();
              tester.binding.addPostFrameCallback((_) => done.complete());
              await done.future;
              throw StateError('validation failed');
            },
          ),
        ],
        home: const Text('Failed'),
      ),
    );
    final result = await tester
        .invokeCommand(const CommandId('fail'))
        .timeout(const Duration(seconds: 1));
    expect(result.status, CommandInvocationStatus.failed);
    expect(result.error, isA<StateError>());
    var fired = false;
    tester.binding.addPostFrameCallback((_) => fired = true);
    await Future<void>.delayed(Duration.zero);
    expect(
      fired,
      isFalse,
      reason: 'automatic pumping stops when the invocation ends',
    );
    tester.pump();
    expect(fired, isTrue);
  });

  for (final semantic in [false, true]) {
    testWidgets(
      '${semantic ? "semantic action" : "command"} pumps chained frame waits',
      (tester) async {
        final frames = <int>[];
        Future<void> run() async {
          for (var i = 0; i < 3; i++) {
            final done = Completer<void>();
            tester.binding.addPostFrameCallback((_) {
              frames.add(i);
              done.complete();
            });
            await done.future;
          }
        }

        tester.pumpWidget(
          FleuryApp(
            title: 'Frames',
            commands: [
              AppCommand(
                id: const CommandId('wait'),
                title: 'Wait',
                run: (_) => run(),
              ),
            ],
            home: Semantics(
              role: SemanticRole.button,
              label: 'Wait for frames',
              actions: const {SemanticAction.activate},
              onAction: (_) => run(),
              child: const Text('Wait'),
            ),
          ),
        );
        if (semantic) {
          final result = await tester
              .invokeSemanticAction(
                SemanticAction.activate,
                role: SemanticRole.button,
                label: 'Wait for frames',
              )
              .timeout(const Duration(seconds: 1));
          expect(result.completed, isTrue);
        } else {
          final result = await tester
              .invokeCommand(const CommandId('wait'))
              .timeout(const Duration(seconds: 1));
          expect(result.status, CommandInvocationStatus.completed);
        }
        expect(frames, [0, 1, 2]);
        expect(
          tester.clock.now,
          Duration.zero,
          reason: 'frame pumping does not advance test time',
        );
      },
    );
  }
}
