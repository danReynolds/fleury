// A command that throws is not a no-op. Every gesture that runs a command
// (a shortcut here; buttons and palette rows share the path) reports the
// error to the calling zone, which runApp shows in its error overlay as it
// does a throwing key binding. A semantic activation reports it `failed`,
// not `completed`, so tests and agents are not told a failed save
// succeeded.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

const _save = CommandId('file.save');
const _format = CommandId('editor.format');

Widget _app() => FleuryApp(
  title: 'Editor',
  commands: [
    AppCommand(
      id: _save,
      title: 'Save',
      shortcuts: [KeySequence.ctrl.s],
      run: (_) => throw StateError('disk full'),
    ),
  ],
  home: CommandScope(
    commands: [
      AppCommand(
        id: _format,
        title: 'Format',
        run: (_) async => throw const FormatException('bad input'),
      ),
    ],
    child: const Focus(autofocus: true, child: Text('doc')),
  ),
);

void main() {
  testWidgets('a command that throws from its shortcut is reported', (
    tester,
  ) async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      tester.pumpWidget(_app());
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(errors, [isA<StateError>()]);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.failed);
  });

  testWidgets('a scoped command that throws from its shortcut is reported', (
    tester,
  ) async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      tester.pumpWidget(
        CommandScope(
          commands: [
            AppCommand(
              id: _format,
              title: 'Format',
              shortcuts: [KeySequence.ctrl.f],
              run: (_) => throw const FormatException('bad input'),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('doc')),
        ),
      );
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.f, modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(errors, [isA<FormatException>()]);
  });

  testWidgets('a command hidden since the tree was read is not completed', (
    tester,
  ) async {
    var shown = true;
    var saves = 0;
    tester.pumpWidget(
      FleuryApp(
        title: 'Editor',
        commands: [
          AppCommand(
            id: _save,
            title: 'Save',
            visible: (_) => shown,
            run: (_) => saves++,
          ),
        ],
        home: const Focus(autofocus: true, child: Text('doc')),
      ),
    );
    tester.pump();
    final tree = tester.semantics();
    final save = tree.single(role: SemanticRole.command, label: 'Save');
    shown = false;

    final result = await invokeSemanticActionFromElement(
      tree: tree,
      id: save.id,
      action: SemanticAction.activate,
    );

    expect(saves, 0);
    expect(result.status, SemanticActionInvocationStatus.unsupported);
  });

  for (final (label, error) in [
    ('Save', isA<StateError>()),
    ('Format', isA<FormatException>()),
  ]) {
    testWidgets('activating $label by semantics reports it failed', (
      tester,
    ) async {
      tester.pumpWidget(_app());
      tester.pump();

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.command,
        label: label,
      );

      expect(result.status, SemanticActionInvocationStatus.failed);
      expect(result.error, error);
    });
  }

  testWidgets('a command disabled since the tree was read is not completed', (
    tester,
  ) async {
    var allowed = true;
    var saves = 0;
    tester.pumpWidget(
      FleuryApp(
        title: 'Editor',
        commands: [
          AppCommand(
            id: _save,
            title: 'Save',
            enabled: (_) => allowed,
            run: (_) => saves++,
          ),
        ],
        home: const Focus(autofocus: true, child: Text('doc')),
      ),
    );
    tester.pump();
    // An agent acts on the tree it read; the app disabled Save since.
    final tree = tester.semantics();
    final save = tree.single(role: SemanticRole.command, label: 'Save');
    allowed = false;

    final result = await invokeSemanticActionFromElement(
      tree: tree,
      id: save.id,
      action: SemanticAction.activate,
    );

    expect(saves, 0);
    expect(result.status, SemanticActionInvocationStatus.unsupported);
  });

  testWidgets('activating a status item whose command fails reports it', (
    tester,
  ) async {
    tester.pumpWidget(
      FleuryApp(
        title: 'Editor',
        status: (_) => [
          StatusItem.error('Build', value: 'broken', action: _save),
        ],
        commands: [
          AppCommand(
            id: _save,
            title: 'Rebuild',
            run: (_) => throw StateError('disk full'),
          ),
        ],
        child: const Column(
          children: [
            Expanded(child: Focus(autofocus: true, child: Text('doc'))),
            AppStatusBar(),
          ],
        ),
      ),
    );
    tester.pump();

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.status,
      label: 'Build',
    );

    expect(result.status, SemanticActionInvocationStatus.failed);
    expect(result.error, isA<StateError>());
  });

  group('a semantic action reports what the command did', () {
    Future<SemanticActionInvocationStatus> activateStatus(
      FleuryTester tester, {
      required List<AppCommand> commands,
    }) async {
      tester.pumpWidget(
        FleuryApp(
          title: 'Editor',
          status: (_) => [StatusItem.text('Build', value: 'x', action: _save)],
          commands: commands,
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('doc'))),
              AppStatusBar(),
            ],
          ),
        ),
      );
      tester.pump();
      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.status,
        label: 'Build',
      );
      return result.status;
    }

    testWidgets('a status item whose command is disabled is not completed', (
      tester,
    ) async {
      var ran = 0;
      final status = await activateStatus(
        tester,
        commands: [
          AppCommand(
            id: _save,
            title: 'Save',
            enabled: (_) => false,
            run: (_) => ran++,
          ),
        ],
      );

      expect(ran, 0);
      expect(status, SemanticActionInvocationStatus.unsupported);
    });

    testWidgets('a status item whose command is gone is not completed', (
      tester,
    ) async {
      final status = await activateStatus(tester, commands: const []);

      expect(status, SemanticActionInvocationStatus.unsupported);
    });

    testWidgets('a dismissal a PopScope refuses is not completed', (
      tester,
    ) async {
      late BuildContext context;
      tester.pumpWidget(Navigator(home: _Capture((c) => context = c)));
      unawaited(
        Navigator.of(context).present<void>(
          const PopScope(
            canPop: false,
            child: Focus(autofocus: true, child: Text('unsaved')),
          ),
        ),
      );
      tester.pump(const Duration(milliseconds: 300));

      final result = await tester.invokeSemanticAction(
        SemanticAction.dismiss,
        role: SemanticRole.route,
        label: 'PopScope',
      );

      expect(result.status, SemanticActionInvocationStatus.unsupported);
      expect(Navigator.of(context).depth, 2, reason: 'the route stayed');
    });

    for (final (label, run, enabled, expected) in [
      (
        'fails',
        (CommandContext _) => throw StateError('disk full'),
        true,
        SemanticActionInvocationStatus.failed,
      ),
      (
        'is disabled',
        (CommandContext _) {},
        false,
        SemanticActionInvocationStatus.unsupported,
      ),
      (
        'completes',
        (CommandContext _) {},
        true,
        SemanticActionInvocationStatus.completed,
      ),
    ]) {
      testWidgets('a custom surface reports a command that $label', (
        tester,
      ) async {
        tester.pumpWidget(
          CommandScope(
            commands: [
              AppCommand(
                id: _save,
                title: 'Save',
                enabled: (_) => enabled,
                run: run,
              ),
            ],
            child: _SaveSurface(),
          ),
        );
        tester.pump();

        final result = await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Save now',
        );

        expect(result.status, expected);
      });
    }
  });
}

final class _Capture extends StatelessWidget {
  const _Capture(this.onBuild);

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const Text('home');
  }
}

/// A command surface built on the public API, as app code writes one.
final class _SaveSurface extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticRole.button,
    label: 'Save now',
    actions: const {SemanticAction.activate},
    onAction: (_) => CommandRegistryScope.of(
      context,
    ).invokeFromSemantics(_save, buildContext: context),
    child: const Text('Save now'),
  );
}
