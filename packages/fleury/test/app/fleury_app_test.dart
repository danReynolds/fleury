import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

const _goRuns = CommandId('go.runs');
const _refresh = CommandId('refresh');
const _diagnose = CommandId('diagnose');
const _openWorkspace = CommandId('workspace.open');

final class _WorkspaceExtension {
  const _WorkspaceExtension(this.root);

  final String root;

  @override
  bool operator ==(Object other) {
    return other is _WorkspaceExtension && other.root == root;
  }

  @override
  int get hashCode => root.hashCode;
}

final class _AgentExtension {
  const _AgentExtension(this.name);

  final String name;
}

final class _WorkspaceTheme {
  const _WorkspaceTheme(this.root);

  final String root;

  @override
  bool operator ==(Object other) {
    return other is _WorkspaceTheme && other.root == root;
  }

  @override
  int get hashCode => root.hashCode;
}

final class _WorkspaceSearchSource {
  const _WorkspaceSearchSource(this.root);

  final String root;

  String resultFor(String query) => '$root:$query';

  @override
  bool operator ==(Object other) {
    return other is _WorkspaceSearchSource && other.root == root;
  }

  @override
  int get hashCode => root.hashCode;
}

final class _WorkspacePackageExtension extends FleuryAppExtension {
  const _WorkspacePackageExtension(this.root, {this.onOpen});

  final String root;
  final void Function(String root)? onOpen;

  @override
  List<AppCommand> get commands => [
    AppCommand(
      id: _openWorkspace,
      title: 'Open Workspace',
      category: 'Workspace',
      shortcuts: [KeyChord.ctrl.o],
      semanticAction: SemanticAction.activate,
      run: (context) {
        final extension = context.appExtension<_WorkspacePackageExtension>();
        extension.onOpen?.call(extension.root);
      },
    ),
  ];

  @override
  List<StatusItem> status(FleuryAppController app) => [
    StatusItem.text(
      'Workspace',
      id: 'workspace',
      value: root,
      action: _openWorkspace,
    ),
  ];

  @override
  List<Object> get themeExtensions => [_WorkspaceTheme(root)];

  @override
  List<Object> get dataSources => [_WorkspaceSearchSource(root)];
}

final class _Capture extends StatelessWidget {
  const _Capture(this.sink);

  final void Function(BuildContext context) sink;

  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('capture');
  }
}

final class _ScreenShell extends StatefulWidget {
  const _ScreenShell({super.key});

  @override
  State<_ScreenShell> createState() => _ScreenShellState();
}

final class _ScreenShellState extends State<_ScreenShell> {
  String active = 'overview';
  var overviewRefreshes = 0;
  var runRefreshes = 0;

  void openScreen(String screenId) {
    if (active == screenId) return;
    setState(() {
      active = screenId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = active == 'runs'
        ? _ScreenPane(
            id: 'runs',
            title: 'Runs',
            selected: true,
            commands: [
              AppCommand(
                id: _refresh,
                title: 'Refresh Runs',
                shortcuts: [KeyChord.ctrl.f],
                run: (_) {
                  runRefreshes += 1;
                },
              ),
            ],
            child: const Focus(autofocus: true, child: Text('Runs body')),
          )
        : _ScreenPane(
            id: 'overview',
            title: 'Overview',
            selected: true,
            commands: [
              AppCommand(
                id: _refresh,
                title: 'Refresh Overview',
                shortcuts: [KeyChord.ctrl.f],
                run: (_) {
                  overviewRefreshes += 1;
                },
              ),
            ],
            child: const Focus(autofocus: true, child: Text('Overview body')),
          );

    return Column(
      children: [
        Semantics(
          role: SemanticRole.navigation,
          label: 'Shell navigation',
          state: SemanticState({'screenCount': 2, 'activeScreenId': active}),
          child: Row(
            children: [
              _ScreenNavItem(
                id: 'overview',
                title: 'Overview',
                selected: active == 'overview',
                onActivate: openScreen,
              ),
              _ScreenNavItem(
                id: 'runs',
                title: 'Runs',
                selected: active == 'runs',
                onActivate: openScreen,
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

final class _ScreenNavItem extends StatelessWidget {
  const _ScreenNavItem({
    required this.id,
    required this.title,
    required this.selected,
    required this.onActivate,
  });

  final String id;
  final String title;
  final bool selected;
  final void Function(String id) onActivate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.listItem,
      label: title,
      selected: selected,
      actions: const {SemanticAction.navigate},
      state: SemanticState({'screenId': id}),
      onAction: (action) {
        if (action == SemanticAction.navigate) {
          onActivate(id);
        }
      },
      child: Text(title),
    );
  }
}

final class _ScreenPane extends StatelessWidget {
  const _ScreenPane({
    required this.id,
    required this.title,
    required this.selected,
    required this.commands,
    required this.child,
  });

  final String id;
  final String title;
  final bool selected;
  final List<AppCommand> commands;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      id: SemanticNodeId('screen:$id'),
      role: SemanticRole.screen,
      label: title,
      selected: selected,
      actions: const {SemanticAction.navigate},
      state: SemanticState({'screenId': id}),
      child: CommandScope(
        commands: commands,
        label: '$title commands',
        child: child,
      ),
    );
  }
}

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('StatusController', () {
    test('updates status items and skips equal updates', () {
      final controller = StatusController();
      var fires = 0;
      controller.addListener(() => fires += 1);

      controller.update([
        StatusItem.text('Screen', id: 'screen', value: 'Overview'),
      ]);
      controller.update([
        StatusItem.text('Screen', id: 'screen', value: 'Overview'),
      ]);
      controller.update([
        StatusItem.warning('Fallback', id: 'fallback', value: 'ascii'),
      ]);

      expect(fires, 2);
      expect(controller.length, 1);
      expect(controller.items.single.id, 'fallback');

      controller.dispose();
    });

    test('post-dispose status updates throw', () {
      final controller = StatusController();

      controller.dispose();
      controller.dispose();

      expect(
        () => controller.update([
          StatusItem.text('Screen', id: 'screen', value: 'Overview'),
        ]),
        _stateError('StatusController has been disposed.'),
      );
    });
  });

  group('FleuryAppController', () {
    test(
      'post-dispose app mutations throw and child listeners are removed',
      () {
        final commands = CommandRegistry();
        final status = StatusController();
        final controller = FleuryAppController(
          title: 'Ops Console',
          commands: commands,
          status: status,
        );
        var notifications = 0;
        controller.addListener(() => notifications += 1);

        controller.dispose();
        controller.dispose();
        status.update([StatusItem.text('Screen', value: 'Runs')]);

        expect(notifications, 0);
        expect(
          () => controller.title = 'Other',
          _stateError('FleuryAppController has been disposed.'),
        );
        expect(
          () => controller.updateExtensions(const <Object>[]),
          _stateError('FleuryAppController has been disposed.'),
        );

        commands.dispose();
        status.dispose();
      },
    );
  });

  testWidgets('FleuryApp renders child content and app semantics', (tester) {
    tester.pumpWidget(
      FleuryApp(title: 'Ops Console', child: const _ScreenShell()),
    );

    expect(tester.exists(text('Overview body')), isTrue);
    expect(tester.exists(text('Runs body')), isFalse);

    final app = tester.semantics().single(
      role: SemanticRole.app,
      label: 'Ops Console',
    );
    final screen = tester.semantics().single(
      role: SemanticRole.screen,
      label: 'Overview',
      selected: true,
    );

    expect(app.state.screenCount, 2);
    expect(app.state.activeScreenId, 'overview');
    expect(screen.state.screenId, 'overview');
  });

  testWidgets('FleuryApp exposes typed extensions to descendants', (tester) {
    late FleuryAppController controller;
    _WorkspaceExtension? workspace;
    _AgentExtension? agent;

    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        extensions: const <Object>[_WorkspaceExtension('/repo/fleury')],
        child: _Capture((context) {
          controller = FleuryApp.of(context);
          workspace = FleuryApp.extension<_WorkspaceExtension>(context);
          agent = FleuryApp.maybeExtension<_AgentExtension>(context);
        }),
      ),
    );

    expect(workspace, const _WorkspaceExtension('/repo/fleury'));
    expect(agent, isNull);
    expect(controller.extension<_WorkspaceExtension>(), same(workspace));
    expect(controller.maybeExtension<_AgentExtension>(), isNull);
    expect(controller.extensions, [const _WorkspaceExtension('/repo/fleury')]);
    expect(
      () => controller.extensions.add(const _AgentExtension('assistant')),
      throwsUnsupportedError,
    );
  });

  testWidgets('FleuryApp updates extensions without recreating the app shell', (
    tester,
  ) {
    var builds = 0;
    _WorkspaceExtension? workspace;

    FleuryApp buildApp(String root) {
      return FleuryApp(
        title: 'Ops Console',
        extensions: <Object>[_WorkspaceExtension(root)],
        child: _Capture((context) {
          builds += 1;
          workspace = FleuryApp.extension<_WorkspaceExtension>(context);
        }),
      );
    }

    tester.pumpWidget(buildApp('/repo/one'));
    expect(workspace, const _WorkspaceExtension('/repo/one'));

    tester.pumpWidget(buildApp('/repo/two'));
    expect(workspace, const _WorkspaceExtension('/repo/two'));
    expect(builds, greaterThanOrEqualTo(2));
  });

  testWidgets('commands can read app extensions from command context', (
    tester,
  ) async {
    _WorkspaceExtension? workspace;
    _AgentExtension? agent;

    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        extensions: const <Object>[_WorkspaceExtension('/repo/fleury')],
        commands: [
          AppCommand(
            id: _refresh,
            title: 'Refresh',
            run: (context) {
              workspace = context.appExtension<_WorkspaceExtension>();
              agent = context.maybeAppExtension<_AgentExtension>();
            },
          ),
        ],
        child: const Focus(autofocus: true, child: Text('Body')),
      ),
    );

    final result = await tester.invokeCommand(_refresh);

    expect(result.completed, isTrue);
    expect(workspace, const _WorkspaceExtension('/repo/fleury'));
    expect(agent, isNull);
  });

  testWidgets('app extensions can contribute commands', (tester) async {
    var opened = '';
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        extensions: <Object>[
          _WorkspacePackageExtension(
            '/repo/fleury',
            onOpen: (root) {
              opened = root;
            },
          ),
        ],
        child: const Focus(autofocus: true, child: Text('Body')),
      ),
    );

    // Hint-bar display of extension commands is covered by
    // key_hint_bar_test.dart in fleury_widgets.
    final result = await tester.invokeCommand(_openWorkspace);

    expect(result.completed, isTrue);
    expect(result.command?.title, 'Open Workspace');
    expect(opened, '/repo/fleury');
    final command = tester.semantics().single(
      role: SemanticRole.command,
      label: 'Open Workspace',
    );
    expect(command.state.commandId, 'workspace.open');
    expect(command.state['commandCategory'], 'Workspace');
  });

  testWidgets('app commands override extension command IDs', (tester) async {
    final calls = <String>[];
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        extensions: <Object>[
          _WorkspacePackageExtension(
            '/repo/fleury',
            onOpen: (_) {
              calls.add('extension');
            },
          ),
        ],
        commands: [
          AppCommand(
            id: _openWorkspace,
            title: 'Open Workspace Override',
            run: (_) {
              calls.add('app');
            },
          ),
        ],
        child: const Focus(autofocus: true, child: Text('Body')),
      ),
    );

    final result = await tester.invokeCommand(_openWorkspace);

    expect(result.completed, isTrue);
    expect(result.command?.title, 'Open Workspace Override');
    expect(calls, ['app']);
  });

  testWidgets('app extensions can contribute status items', (tester) {
    FleuryApp buildApp(String root) {
      return FleuryApp(
        title: 'Ops Console',
        extensions: <Object>[_WorkspacePackageExtension(root)],
        status: (_) => [StatusItem.text('Mode', id: 'mode', value: 'dev')],
        child: const AppStatusBar(),
      );
    }

    tester.pumpWidget(buildApp('/repo/one'));

    expect(tester.exists(text('Mode: dev')), isTrue);
    expect(tester.exists(text('Workspace: /repo/one')), isTrue);
    final app = tester.semantics().single(
      role: SemanticRole.app,
      label: 'Ops Console',
    );
    final statusBar = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Status',
    );
    final workspace = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Workspace',
    );
    expect(app.state.statusCount, 2);
    expect(statusBar.state.statusCount, 2);
    expect(workspace.value, '/repo/one');
    expect(workspace.state.commandId, 'workspace.open');

    tester.pumpWidget(buildApp('/repo/two'));

    expect(tester.exists(text('Workspace: /repo/two')), isTrue);
    expect(tester.exists(text('Workspace: /repo/one')), isFalse);
  });

  testWidgets('app extensions can contribute theme extensions', (tester) {
    _WorkspaceTheme? workspaceTheme;

    FleuryApp buildApp(String root) {
      return FleuryApp(
        title: 'Theme',
        extensions: <Object>[_WorkspacePackageExtension(root)],
        child: _Capture((context) {
          workspaceTheme = Theme.of(context).extension<_WorkspaceTheme>();
        }),
      );
    }

    tester.pumpWidget(buildApp('/repo/fleury'));
    expect(workspaceTheme?.root, '/repo/fleury');

    tester.pumpWidget(buildApp('/repo/dune'));
    expect(workspaceTheme?.root, '/repo/dune');
  });

  testWidgets('host theme extensions override app extension theme defaults', (
    tester,
  ) {
    _WorkspaceTheme? workspaceTheme;

    tester.pumpWidget(
      Theme(
        data: ThemeData(extensions: const [_WorkspaceTheme('/host')]),
        child: FleuryApp(
          title: 'Theme',
          extensions: const <Object>[
            _WorkspacePackageExtension('/package-default'),
          ],
          child: _Capture((context) {
            workspaceTheme = Theme.of(context).extension<_WorkspaceTheme>();
          }),
        ),
      ),
    );

    expect(workspaceTheme?.root, '/host');
  });

  testWidgets('app extensions can contribute data sources', (tester) async {
    _WorkspaceSearchSource? widgetSource;
    FleuryAppController? controller;
    String? commandResult;

    FleuryApp buildApp(String root) {
      return FleuryApp(
        title: 'Search',
        extensions: <Object>[_WorkspacePackageExtension(root)],
        commands: [
          AppCommand(
            id: _refresh,
            title: 'Search Workspace',
            run: (context) {
              commandResult = context
                  .appDataSource<_WorkspaceSearchSource>()
                  .resultFor('index');
            },
          ),
        ],
        child: _Capture((context) {
          controller = FleuryApp.of(context);
          widgetSource = FleuryApp.dataSource<_WorkspaceSearchSource>(context);
        }),
      );
    }

    tester.pumpWidget(buildApp('/repo/fleury'));

    expect(widgetSource?.resultFor('docs'), '/repo/fleury:docs');
    expect(
      controller?.dataSource<_WorkspaceSearchSource>().resultFor('runs'),
      '/repo/fleury:runs',
    );
    expect(controller?.dataSources, [
      const _WorkspaceSearchSource('/repo/fleury'),
    ]);
    expect(
      () => controller!.dataSources.add(const _WorkspaceSearchSource('/other')),
      throwsUnsupportedError,
    );

    final result = await tester.invokeCommand(_refresh);
    expect(result.completed, isTrue);
    expect(commandResult, '/repo/fleury:index');

    tester.pumpWidget(buildApp('/repo/dune'));
    expect(widgetSource?.resultFor('docs'), '/repo/dune:docs');
    expect(controller?.maybeDataSource<_AgentExtension>(), isNull);
  });

  testWidgets('global command shortcut can activate app-owned navigation', (
    tester,
  ) {
    final shellKey = GlobalKey<_ScreenShellState>();
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        commands: [
          AppCommand(
            id: _goRuns,
            title: 'Go to Runs',
            shortcuts: [KeyChord.ctrl.r],
            semanticAction: SemanticAction.navigate,
            run: (_) {
              shellKey.currentState!.openScreen('runs');
            },
          ),
        ],
        child: _ScreenShell(key: shellKey),
      ),
    );

    tester.sendKey(const KeyEvent(char: 'r', modifiers: {KeyModifier.ctrl}));

    expect(tester.exists(text('Overview body')), isFalse);
    expect(tester.exists(text('Runs body')), isTrue);

    final app = tester.semantics().single(
      role: SemanticRole.app,
      label: 'Ops Console',
    );
    final command = tester.semantics().single(
      role: SemanticRole.command,
      label: 'Go to Runs',
    );

    expect(app.state.activeScreenId, 'runs');
    expect(command.state.commandId, 'go.runs');
    expect(command.state.shortcut, 'Ctrl+R');
    expect(command.actions, contains(SemanticAction.navigate));
  });

  testWidgets('semantic command action invokes app command', (tester) async {
    final shellKey = GlobalKey<_ScreenShellState>();
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        commands: [
          AppCommand(
            id: _goRuns,
            title: 'Go to Runs',
            semanticAction: SemanticAction.navigate,
            run: (_) {
              shellKey.currentState!.openScreen('runs');
            },
          ),
        ],
        child: _ScreenShell(key: shellKey),
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.command,
      label: 'Go to Runs',
    );

    expect(result.status, SemanticActionInvocationStatus.completed);
    expect(tester.exists(text('Runs body')), isTrue);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.completed);
  });

  testWidgets('semantic screen navigation is owned by the app shell', (
    tester,
  ) async {
    tester.pumpWidget(
      FleuryApp(title: 'Ops Console', child: const _ScreenShell()),
    );

    final runs = tester.semantics().single(
      role: SemanticRole.listItem,
      label: 'Runs',
      selected: false,
    );
    final result = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      node: runs,
    );

    expect(result.completed, isTrue);
    expect(tester.exists(text('Runs body')), isTrue);
  });

  testWidgets('focused scoped commands shadow app commands', (tester) async {
    final calls = <String>[];
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        commands: [
          AppCommand(
            id: _refresh,
            title: 'Global Refresh',
            run: (_) {
              calls.add('global');
            },
          ),
        ],
        child: CommandScope(
          commands: [
            AppCommand(
              id: _refresh,
              title: 'Refresh Local',
              run: (_) {
                calls.add('local');
              },
            ),
          ],
          child: const Focus(autofocus: true, child: Text('Local')),
        ),
      ),
    );

    final result = await tester.invokeCommand(_refresh);

    expect(result.status, CommandInvocationStatus.completed);
    expect(result.command?.title, 'Refresh Local');
    expect(calls, ['local']);
  });

  testWidgets('active app-owned screen command scope follows navigation', (
    tester,
  ) {
    final shellKey = GlobalKey<_ScreenShellState>();
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        commands: [
          AppCommand(
            id: _goRuns,
            title: 'Go to Runs',
            shortcuts: [KeyChord.ctrl.r],
            run: (_) {
              shellKey.currentState!.openScreen('runs');
            },
          ),
        ],
        child: _ScreenShell(key: shellKey),
      ),
    );

    tester.sendKey(const KeyEvent(char: 'f', modifiers: {KeyModifier.ctrl}));
    tester.sendKey(const KeyEvent(char: 'r', modifiers: {KeyModifier.ctrl}));
    tester.sendKey(const KeyEvent(char: 'f', modifiers: {KeyModifier.ctrl}));

    expect(shellKey.currentState!.overviewRefreshes, 1);
    expect(shellKey.currentState!.runRefreshes, 1);
  });

  testWidgets('FleuryApp status builder renders and exposes semantics', (
    tester,
  ) async {
    var active = 'Overview';
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        status: (_) => [
          StatusItem.text('Screen', id: 'active-screen', value: active),
          StatusItem.warning(
            'Fallback',
            id: 'capability-fallback',
            value: 'ascii',
            action: _diagnose,
          ),
        ],
        commands: [
          AppCommand(
            id: _goRuns,
            title: 'Go to Runs',
            shortcuts: [KeyChord.ctrl.r],
            run: (_) {
              active = 'Runs';
            },
          ),
          AppCommand(id: _diagnose, title: 'Diagnose Terminal', run: (_) {}),
        ],
        child: const Column(
          children: [
            Expanded(child: Focus(autofocus: true, child: Text('Body'))),
            AppStatusBar(),
          ],
        ),
      ),
    );

    expect(tester.exists(text('Screen: Overview')), isTrue);

    final app = tester.semantics().single(
      role: SemanticRole.app,
      label: 'Ops Console',
    );
    final statusBar = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Status',
    );
    final fallback = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Fallback',
    );

    expect(app.state.statusCount, 2);
    expect(statusBar.state.statusCount, 2);
    expect(fallback.value, 'ascii');
    expect(fallback.state.statusId, 'capability-fallback');
    expect(fallback.state.severity, 'warning');
    expect(fallback.state.commandId, 'diagnose');
    expect(fallback.actions, contains(SemanticAction.activate));

    await tester.invokeCommand(_goRuns);
    tester.pump();

    expect(tester.exists(text('Screen: Runs')), isTrue);
  });

  testWidgets('semantic status activation invokes linked command', (
    tester,
  ) async {
    var diagnoses = 0;
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        status: (_) => [
          StatusItem.warning(
            'Fallback',
            id: 'capability-fallback',
            value: 'ascii',
            action: _diagnose,
          ),
        ],
        commands: [
          AppCommand(
            id: _diagnose,
            title: 'Diagnose Terminal',
            run: (_) {
              diagnoses += 1;
            },
          ),
        ],
        child: const AppStatusBar(),
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.status,
      label: 'Fallback',
    );

    expect(result.completed, isTrue);
    expect(diagnoses, 1);
  });

  testWidgets('commands can update status through command context', (tester) {
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        commands: [
          AppCommand(
            id: _refresh,
            title: 'Refresh',
            shortcuts: [KeyChord.ctrl.f],
            run: (context) {
              context.status!.update([
                StatusItem.success('Task', id: 'task', value: 'done'),
              ]);
            },
          ),
        ],
        child: const Column(
          children: [
            Expanded(child: Focus(autofocus: true, child: Text('Body'))),
            AppStatusBar(emptyText: 'Idle'),
          ],
        ),
      ),
    );

    expect(tester.exists(text('Idle')), isTrue);

    tester.sendKey(const KeyEvent(char: 'f', modifiers: {KeyModifier.ctrl}));

    expect(tester.exists(text('Task: done')), isTrue);
    final task = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Task',
    );
    expect(task.state.statusId, 'task');
    expect(task.state.severity, 'success');
  });

  testWidgets('tester invokes commands by id and records results', (
    tester,
  ) async {
    final shellKey = GlobalKey<_ScreenShellState>();
    tester.pumpWidget(
      FleuryApp(
        title: 'Ops Console',
        commands: [
          AppCommand(
            id: _goRuns,
            title: 'Go to Runs',
            run: (_) {
              shellKey.currentState!.openScreen('runs');
            },
          ),
        ],
        child: _ScreenShell(key: shellKey),
      ),
    );

    final result = await tester.invokeCommand(_goRuns);

    expect(result.status, CommandInvocationStatus.completed);
    expect(tester.lastCommandResult, same(result));
    expect(tester.exists(text('Runs body')), isTrue);
    final app = tester.semantics().single(
      role: SemanticRole.app,
      label: 'Ops Console',
    );
    expect(app.state.lastCommandId, 'go.runs');
    expect(app.state.lastCommandStatus, 'completed');
    expect(app.state.activeScreenId, 'runs');
  });

  testWidgets('app shell provides root focus traversal', (tester) {
    final right = FocusNode(debugLabel: 'right pane');
    addTearDown(right.dispose);

    tester.pumpWidget(
      FleuryApp(
        title: 'Traversal',
        child: Row(
          children: [
            SizedBox(
              width: 8,
              child: Focus(autofocus: true, child: const Text('Left')),
            ),
            const SizedBox(width: 2),
            Focus(focusNode: right, child: const Text('Right')),
          ],
        ),
      ),
    );

    tester.render(size: const CellSize(24, 3));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.pump();

    expect(right.hasFocus, isTrue);
  });
}
