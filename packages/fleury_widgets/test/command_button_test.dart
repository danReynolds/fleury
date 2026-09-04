import 'dart:async' show FutureOr;

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

    tester.pumpWidget(_host(registry));

    expect(
      tester.renderToString(size: const CellSize(100, 6), emptyMark: ' '),
      contains('could not find command "packages.inspect"'),
    );
  });
}
