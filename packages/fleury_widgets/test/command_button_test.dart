import 'dart:async' show Completer, FutureOr, runZonedGuarded;

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _inspect = CommandId('packages.inspect');

AppCommand _command({
  String title = 'Inspect package',
  bool enabled = true,
  bool visible = true,
  FutureOr<void> Function(CommandContext)? run,
}) {
  return AppCommand(
    id: _inspect,
    title: title,
    enabled: (_) => enabled,
    visible: (_) => visible,
    run: run ?? (_) {},
  );
}

CommandRegistry _registry(AppCommand command) {
  return CommandRegistry(commands: [command]);
}

Widget _host(
  CommandRegistry registry, {
  String? label,
  bool autofocus = false,
}) {
  return CommandRegistryScope(
    registry: registry,
    child: CommandButton(command: _inspect, label: label, autofocus: autofocus),
  );
}

/// The errors [body] leaves uncaught. A throw from the body itself fails the
/// test instead of hanging it.
Future<List<Object>> _uncaught(Future<void> Function() body) {
  final errors = <Object>[];
  final done = Completer<List<Object>>();
  runZonedGuarded(() {
    body().then((_) => done.complete(errors), onError: done.completeError);
  }, (error, _) => errors.add(error));
  return done.future;
}

String _text(FleuryTester tester) => tester
    .renderToString(size: const CellSize(32, 1), emptyMark: ' ')
    .trimRight();

void main() {
  testWidgets('uses the active command title by default', (tester) {
    final registry = _registry(_command());
    addTearDown(registry.dispose);

    tester.pumpWidget(_host(registry));

    expect(_text(tester), '[ Inspect package ]');
    expect(
      tester.semantics().single(role: SemanticRole.button).label,
      'Inspect package',
    );
  });

  testWidgets('accepts a button-specific label override', (tester) {
    final registry = _registry(_command());
    addTearDown(registry.dispose);

    tester.pumpWidget(_host(registry, label: 'Inspect'));

    expect(_text(tester), '[ Inspect ]');
    expect(
      tester.semantics().single(role: SemanticRole.button).label,
      'Inspect',
    );
  });

  testWidgets('inherits the command enabled state', (tester) async {
    var calls = 0;
    final registry = _registry(
      _command(
        enabled: false,
        run: (_) {
          calls += 1;
        },
      ),
    );
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry));

    final node = tester.semantics().single(
      role: SemanticRole.button,
      label: 'Inspect package',
      enabled: false,
    );
    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: node,
      allowFailure: true,
    );

    expect(result.status, SemanticActionInvocationStatus.disabled);
    expect(calls, 0);
    expect(registry.lastResult, isNull);
  });

  testWidgets('invokes through the registry with its descendant context', (
    tester,
  ) async {
    CommandContext? invocationContext;
    final registry = _registry(
      _command(
        run: (context) {
          invocationContext = context;
        },
      ),
    );
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry, autofocus: true));

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    expect(invocationContext, isNotNull);
    final buildContext = invocationContext!.buildContext;
    expect(buildContext, isNotNull);
    expect(CommandRegistryScope.of(buildContext!), same(registry));
    expect(registry.lastResult?.status, CommandInvocationStatus.completed);
    expect(registry.lastResult?.command?.id, _inspect);
  });

  testWidgets('a command that throws when pressed throws there', (tester) {
    final registry = _registry(
      _command(run: (_) => throw StateError('registry offline')),
    );
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry, autofocus: true));

    // As any throwing key handler does; runApp shows it in its overlay.
    expect(
      () => tester.sendKey(const KeyEvent(KeyCode.enter)),
      throwsStateError,
    );
    expect(registry.lastResult?.status, CommandInvocationStatus.failed);
  });

  testWidgets('a command that fails after the press is reported', (
    tester,
  ) async {
    final registry = _registry(
      _command(run: (_) async => throw StateError('registry offline')),
    );
    addTearDown(registry.dispose);

    final errors = await _uncaught(() async {
      tester.pumpWidget(_host(registry, autofocus: true));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await Future<void>.delayed(Duration.zero);
    });

    expect(errors, [isA<StateError>()]);
    expect(registry.lastResult?.status, CommandInvocationStatus.failed);
  });

  testWidgets('a semantic press on a command that throws fails', (
    tester,
  ) async {
    final registry = _registry(
      _command(run: (_) => throw StateError('registry offline')),
    );
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry));

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      allowFailure: true,
    );

    expect(result.status, SemanticActionInvocationStatus.failed);
    expect(result.error, isA<StateError>());
  });

  testWidgets('a semantic press does not wait on the command', (tester) async {
    final registry = _registry(
      _command(run: (_) async => throw StateError('registry offline')),
    );
    addTearDown(registry.dispose);
    SemanticActionInvocationResult? result;

    final errors = await _uncaught(() async {
      tester.pumpWidget(_host(registry));
      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        allowFailure: true,
      );
      await Future<void>.delayed(Duration.zero);
    });

    // As with a key, its later failure reaches the zone (runApp's error
    // overlay).
    expect(result?.status, SemanticActionInvocationStatus.completed);
    expect(errors, [isA<StateError>()]);
    expect(registry.lastResult?.status, CommandInvocationStatus.failed);
  });

  testWidgets('a semantic press on a command disabled since the build is '
      'declined', (tester) async {
    var allowed = true;
    var runs = 0;
    final registry = CommandRegistry(
      commands: [
        AppCommand(
          id: _inspect,
          title: 'Inspect package',
          enabled: (_) => allowed,
          run: (_) => runs++,
        ),
      ],
    );
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry));
    allowed = false; // nothing rebuilds the button

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      allowFailure: true,
    );

    expect(result.status, SemanticActionInvocationStatus.unsupported);
    expect(runs, 0);
  });

  testWidgets('a semantic press on a command hidden since the build is '
      'declined', (tester) async {
    var shown = true;
    var runs = 0;
    final registry = CommandRegistry(
      commands: [
        AppCommand(
          id: _inspect,
          title: 'Inspect package',
          visible: (_) => shown,
          run: (_) => runs++,
        ),
      ],
    );
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry));
    shown = false; // nothing rebuilds the button

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      allowFailure: true,
    );

    expect(result.status, SemanticActionInvocationStatus.unsupported);
    expect(runs, 0);
  });

  testWidgets('Enter on a command disabled since the build is a no-op', (
    tester,
  ) async {
    var allowed = true;
    var runs = 0;
    final registry = CommandRegistry(
      commands: [
        AppCommand(
          id: _inspect,
          title: 'Inspect package',
          enabled: (_) => allowed,
          run: (_) => runs++,
        ),
      ],
    );
    addTearDown(registry.dispose);

    final errors = await _uncaught(() async {
      tester.pumpWidget(_host(registry, autofocus: true));
      allowed = false; // nothing rebuilds the button
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await Future<void>.delayed(Duration.zero);
    });

    expect(runs, 0);
    expect(errors, isEmpty);
  });

  testWidgets('dispatch reports a command that cannot run instead of '
      'throwing', (tester) async {
    // A custom command surface (a key binding, a click handler) can call
    // dispatch without guarding it.
    var allowed = false;
    var runs = 0;
    final registry = CommandRegistry(
      commands: [
        AppCommand(
          id: _inspect,
          title: 'Inspect package',
          enabled: (_) => allowed,
          run: (_) => runs++,
        ),
      ],
    );
    addTearDown(registry.dispose);
    final started = <bool>[];
    tester.pumpWidget(
      CommandRegistryScope(
        registry: registry,
        child: KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.ctrl.i,
              onTrigger: (_) => started.add(registry.dispatch(_inspect)),
            ),
          ],
          child: const Focus(autofocus: true, child: Text('packages')),
        ),
      ),
    );
    const ctrlI = KeyEvent(KeyCode.i, modifiers: {KeyModifier.ctrl});

    tester.sendKey(ctrlI);
    allowed = true;
    tester.sendKey(ctrlI);

    expect(started, [false, true]);
    expect(runs, 1);
    expect(registry.dispatch(const CommandId('packages.missing')), isFalse);
  });

  testWidgets('rebuilds when the registry command changes', (tester) async {
    var calls = 0;
    final registry = _registry(_command(title: 'Waiting', enabled: false));
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry, autofocus: true));

    expect(_text(tester), '[ Waiting ]');
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'Waiting')
          .enabled,
      isFalse,
    );

    registry.localCommands = [
      _command(
        title: 'Inspect now',
        run: (_) {
          calls += 1;
        },
      ),
    ];
    tester.pump();

    expect(_text(tester), '[ Inspect now ]');
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'Inspect now')
          .enabled,
      isTrue,
    );

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    expect(calls, 1);
    expect(registry.lastResult?.status, CommandInvocationStatus.completed);
    expect(registry.lastResult?.command?.title, 'Inspect now');
  });

  testWidgets('omits the button when its registered command is invisible', (
    tester,
  ) {
    final registry = _registry(_command(visible: false));
    addTearDown(registry.dispose);

    tester.pumpWidget(_host(registry));

    expect(_text(tester), isEmpty);
    expect(tester.semantics().byRole(SemanticRole.button), isEmpty);
  });

  testWidgets('tracks command visibility changes from the registry', (tester) {
    final registry = _registry(_command(visible: false));
    addTearDown(registry.dispose);
    tester.pumpWidget(_host(registry));

    expect(_text(tester), isEmpty);
    expect(tester.semantics().byRole(SemanticRole.button), isEmpty);

    registry.localCommands = [_command(title: 'Inspect now')];
    tester.pump();

    expect(_text(tester), '[ Inspect now ]');
    expect(
      tester.semantics().single(
        role: SemanticRole.button,
        label: 'Inspect now',
      ),
      isNotNull,
    );

    registry.localCommands = [_command(visible: false)];
    tester.pump();

    expect(_text(tester), isEmpty);
    expect(tester.semantics().byRole(SemanticRole.button), isEmpty);
  });

  testWidgets('fails clearly when the command is not registered', (tester) {
    final registry = CommandRegistry();
    addTearDown(registry.dispose);

    expect(
      () => tester.pumpWidget(_host(registry)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('could not find command "packages.inspect"'),
        ),
      ),
    );
  });
}
