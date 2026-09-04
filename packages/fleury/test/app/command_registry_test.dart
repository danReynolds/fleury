import 'dart:async';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

const _save = CommandId('save');
const _open = CommandId('open');
const _hidden = CommandId('hidden');
const _disabled = CommandId('disabled');
const _missing = CommandId('missing');

void main() {
  group('CommandRegistry', () {
    test('rejects duplicate command IDs within one scope', () {
      final duplicateCommands = [
        AppCommand(id: _save, title: 'Save first', run: (_) {}),
        AppCommand(id: _save, title: 'Save second', run: (_) {}),
      ];

      expect(
        () => CommandRegistry(commands: duplicateCommands),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate command ID "save"'),
          ),
        ),
      );
    });

    test('rejects duplicate IDs without replacing existing commands', () {
      final registry = CommandRegistry(
        commands: [AppCommand(id: _save, title: 'Save', run: (_) {})],
      );
      addTearDown(registry.dispose);

      expect(
        () => registry.localCommands = [
          AppCommand(id: _open, title: 'Open first', run: (_) {}),
          AppCommand(id: _open, title: 'Open second', run: (_) {}),
        ],
        throwsA(isA<ArgumentError>()),
      );
      expect(registry.localCommands.single.id, _save);
    });

    test('activeCommands resolves local commands before parent commands', () {
      final parent = CommandRegistry(
        commands: [
          AppCommand(id: _save, title: 'Parent save', run: (_) {}),
          AppCommand(id: _open, title: 'Open', run: (_) {}),
        ],
      );
      final child = CommandRegistry(
        parent: parent,
        commands: [
          AppCommand(id: _save, title: 'Child save', run: (_) {}),
          AppCommand(
            id: _hidden,
            title: 'Hidden',
            visible: (_) => false,
            run: (_) {},
          ),
        ],
      );

      final active = child.activeCommands();

      expect(active.map((command) => command.title), ['Child save', 'Open']);
      expect(child.command(_save)?.title, 'Child save');
      expect(child.command(_hidden), isNull);

      child.dispose();
      parent.dispose();
    });

    test(
      'invoke reports completed, disabled, notFound, and failed states',
      () async {
        var calls = 0;
        final registry = CommandRegistry(
          commands: [
            AppCommand(
              id: _save,
              title: 'Save',
              run: (_) {
                calls += 1;
              },
            ),
            AppCommand(
              id: _disabled,
              title: 'Disabled',
              enabled: (_) => false,
              run: (_) {
                calls += 10;
              },
            ),
            AppCommand(
              id: _open,
              title: 'Open',
              run: (_) {
                throw StateError('boom');
              },
            ),
          ],
        );

        final completed = await registry.invoke(_save);
        expect(completed.status, CommandInvocationStatus.completed);
        expect(completed.completed, isTrue);
        expect(calls, 1);
        expect(registry.lastResult, completed);

        final disabled = await registry.invoke(_disabled);
        expect(disabled.status, CommandInvocationStatus.disabled);
        expect(calls, 1);

        final missing = await registry.invoke(_missing);
        expect(missing.status, CommandInvocationStatus.notFound);

        final failed = await registry.invoke(_open);
        expect(failed.status, CommandInvocationStatus.failed);
        expect(failed.error, isA<StateError>());

        registry.dispose();
      },
    );

    test(
      'invoke awaits asynchronous commands before recording completion',
      () async {
        final gate = Completer<void>();
        final registry = CommandRegistry(
          commands: [
            AppCommand(id: _save, title: 'Save', run: (_) => gate.future),
          ],
        );

        final pending = registry.invoke(_save);
        await Future<void>.delayed(Duration.zero);

        expect(registry.lastResult, isNull);

        gate.complete();
        final result = await pending;

        expect(result.status, CommandInvocationStatus.completed);
        expect(registry.lastResult, same(result));

        registry.dispose();
      },
    );

    test('invoke records asynchronous command failures', () async {
      final registry = CommandRegistry(
        commands: [
          AppCommand(
            id: _open,
            title: 'Open',
            run: (_) async {
              await Future<void>.delayed(Duration.zero);
              throw StateError('async boom');
            },
          ),
        ],
      );

      final result = await registry.invoke(_open);

      expect(result.status, CommandInvocationStatus.failed);
      expect(result.error, isA<StateError>());
      expect(registry.lastResult, same(result));

      registry.dispose();
    });

    test(
      'dispose during async invocation returns result without recording it',
      () async {
        final gate = Completer<void>();
        final registry = CommandRegistry(
          commands: [
            AppCommand(id: _save, title: 'Save', run: (_) => gate.future),
          ],
        );

        final pending = registry.invoke(_save);
        await Future<void>.delayed(Duration.zero);

        registry.dispose();
        gate.complete();

        final result = await pending;
        expect(result.status, CommandInvocationStatus.completed);
        expect(registry.lastResult, isNull);

        registry.dispose();
      },
    );

    test('post-dispose command mutations and invocations throw', () async {
      final registry = CommandRegistry(
        commands: [AppCommand(id: _save, title: 'Save', run: (_) {})],
      );

      registry.dispose();
      registry.dispose();
      final unusedParent = CommandRegistry();

      expect(
        () => registry.localCommands = const <AppCommand>[],
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'CommandRegistry has been disposed.',
          ),
        ),
      );
      expect(
        () => registry.parent = unusedParent,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'CommandRegistry has been disposed.',
          ),
        ),
      );
      unusedParent.dispose();
      await expectLater(
        registry.invoke(_save),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'CommandRegistry has been disposed.',
          ),
        ),
      );
      await expectLater(
        registry.invokeCommand(
          AppCommand(id: _open, title: 'Open', run: (_) {}),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'CommandRegistry has been disposed.',
          ),
        ),
      );
    });

    test('invokeCommand runs the concrete command instance', () async {
      final calls = <String>[];
      final registry = CommandRegistry(
        commands: [
          AppCommand(
            id: _save,
            title: 'Registry save',
            run: (_) {
              calls.add('registry');
            },
          ),
        ],
      );
      final resolvedElsewhere = AppCommand(
        id: _save,
        title: 'Screen save',
        run: (_) {
          calls.add('screen');
        },
      );

      final result = await registry.invokeCommand(resolvedElsewhere);

      expect(result.status, CommandInvocationStatus.completed);
      expect(result.command, same(resolvedElsewhere));
      expect(calls, ['screen']);

      registry.dispose();
    });
  });

  group('CommandScope', () {
    testWidgets('contributes command semantics', (tester) {
      tester.pumpWidget(
        CommandScope(
          commands: [
            AppCommand(
              id: _save,
              title: 'Save',
              description: 'Write current file',
              category: 'File',
              shortcuts: [KeySequence.ctrl.s],
              semanticAction: SemanticAction.submit,
              run: (_) {},
            ),
          ],
          child: const Text('Body'),
        ),
      );

      final command = tester.semantics().single(
        role: SemanticRole.command,
        label: 'Save',
        action: SemanticAction.activate,
      );
      final scope = tester.semantics().single(
        role: SemanticRole.region,
        label: 'Command scope',
      );

      expect(command.value, 'Write current file');
      expect(command.enabled, isTrue);
      expect(command.actions, contains(SemanticAction.submit));
      expect(command.state.commandId, 'save');
      expect(command.state.shortcut, 'Ctrl+S');
      expect(command.state.commandCategory, 'File');
      expect(scope.state.commandCount, 1);
    });

    testWidgets(
      'nested overrides keep distinct semantic identities and actions',
      (tester) async {
        var parentCalls = 0;
        var childCalls = 0;
        tester.pumpWidget(
          CommandScope(
            commands: [
              AppCommand(
                id: _save,
                title: 'Parent save',
                run: (_) {
                  parentCalls += 1;
                },
              ),
            ],
            child: CommandScope(
              commands: [
                AppCommand(
                  id: _save,
                  title: 'Child save',
                  run: (_) {
                    childCalls += 1;
                  },
                ),
              ],
              child: const Text('Body'),
            ),
          ),
        );

        final tree = tester.semantics();
        final parent = tree.single(
          role: SemanticRole.command,
          label: 'Parent save',
        );
        final child = tree.single(
          role: SemanticRole.command,
          label: 'Child save',
        );

        expect(parent.id, isNot(child.id));
        expect(parent.state.commandId, 'save');
        expect(child.state.commandId, 'save');
        expect(tree.nodesById[parent.id], same(parent));
        expect(tree.nodesById[child.id], same(child));
        expect(tree.elementById(parent.id), isNotNull);
        expect(tree.elementById(child.id), isNotNull);
        expect(
          tree.elementById(parent.id),
          isNot(same(tree.elementById(child.id))),
        );

        final parentResult = await tester.invokeSemanticAction(
          SemanticAction.activate,
          id: parent.id,
        );
        final childResult = await tester.invokeSemanticAction(
          SemanticAction.activate,
          id: child.id,
        );

        expect(parentResult.completed, isTrue);
        expect(childResult.completed, isTrue);
        expect(parentCalls, 1);
        expect(childCalls, 1);
      },
    );

    testWidgets('omits invisible commands from semantics', (tester) {
      tester.pumpWidget(
        CommandScope(
          commands: [
            AppCommand(
              id: _hidden,
              title: 'Hidden',
              visible: (_) => false,
              run: (_) {},
            ),
          ],
          child: const Text('Body'),
        ),
      );

      expect(tester.semantics().byRole(SemanticRole.command), isEmpty);
    });

    testWidgets('invokes enabled shortcuts through KeyBindings', (tester) {
      var calls = 0;
      tester.pumpWidget(
        CommandScope(
          commands: [
            AppCommand(
              id: _save,
              title: 'Save',
              shortcuts: [KeySequence.ctrl.s],
              run: (_) {
                calls += 1;
              },
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      tester.sendKey(
        const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
      );

      expect(calls, 1);
    });

    testWidgets('does not invoke disabled shortcuts', (tester) {
      var calls = 0;
      tester.pumpWidget(
        CommandScope(
          commands: [
            AppCommand(
              id: _disabled,
              title: 'Disabled',
              shortcuts: [KeySequence.ctrl.s],
              enabled: (_) => false,
              run: (_) {
                calls += 1;
              },
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      tester.sendKey(
        const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
      );

      expect(calls, 0);
      final command = tester.semantics().single(
        role: SemanticRole.command,
        label: 'Disabled',
      );
      expect(command.enabled, isFalse);
    });

    testWidgets('shortcut-triggered async commands record after completion', (
      tester,
    ) async {
      final gate = Completer<void>();
      tester.pumpWidget(
        CommandScope(
          commands: [
            AppCommand(
              id: _save,
              title: 'Save',
              shortcuts: [KeySequence.ctrl.s],
              run: (_) => gate.future,
            ),
          ],
          child: const Focus(autofocus: true, child: EmptyBox()),
        ),
      );

      final registry = tester.commandRegistry();
      tester.sendKey(
        const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(registry.lastResult, isNull);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      expect(registry.lastResult?.status, CommandInvocationStatus.completed);
      expect(tester.lastCommandResult, same(registry.lastResult));
    });
  });
}
