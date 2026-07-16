import 'dart:async' show unawaited;

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

const _inspectRoute = CommandId('route.inspect');
const _shortcutRoute = CommandId('route.shortcut');
const _semanticRoute = CommandId('route.semantic');
const _replaceRoute = CommandId('route.replace');
const _afterReplacement = CommandId('route.after-replacement');

final class _AppThemeToken {
  const _AppThemeToken(this.value);

  final String value;
}

final class _PackageThemeToken {
  const _PackageThemeToken(this.value);

  final String value;
}

final class _RouteDataSource {
  const _RouteDataSource(this.value);

  final String value;
}

final class _RouteServices extends FleuryAppExtension {
  const _RouteServices({required this.onInspect});

  final void Function(CommandContext context) onInspect;

  @override
  List<AppCommand> get commands => <AppCommand>[
    AppCommand(id: _inspectRoute, title: 'Inspect Route', run: onInspect),
  ];

  @override
  List<StatusItem> status(FleuryAppController app) => <StatusItem>[
    StatusItem.success('Package', id: 'package', value: 'ready'),
  ];

  @override
  List<Object> get themeExtensions => const <Object>[
    _PackageThemeToken('package'),
  ];

  @override
  List<Object> get dataSources => const <Object>[_RouteDataSource('workspace')];
}

final class _ScopeSnapshot {
  BuildContext? context;
  FleuryAppController? app;
  CommandRegistry? commands;
  ThemeData? theme;
  NavigatorState? navigator;
  NavigatorState? rootNavigator;
  _RouteServices? extension;
  _RouteDataSource? dataSource;

  void capture(BuildContext context) {
    this.context = context;
    app = FleuryApp.of(context);
    commands = CommandRegistryScope.of(context);
    theme = Theme.of(context);
    navigator = Navigator.of(context);
    rootNavigator = Navigator.of(context, rootNavigator: true);
    extension = FleuryApp.extension<_RouteServices>(context);
    dataSource = FleuryApp.dataSource<_RouteDataSource>(context);
  }
}

final class _ScopeProbe extends StatelessWidget {
  const _ScopeProbe({required this.snapshot, required this.label, this.child});

  final _ScopeSnapshot snapshot;
  final String label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    snapshot.capture(context);
    return child ?? Text(label);
  }
}

void main() {
  test('FleuryApp requires exactly one standard or custom shell', () {
    expect(
      () => FleuryApp(title: 'Missing shell'),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => FleuryApp(
        title: 'Ambiguous shell',
        home: const Text('home'),
        child: const Text('custom'),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('home routes retain every FleuryApp scope and root navigator', (
    tester,
  ) async {
    final home = _ScopeSnapshot();
    final detail = _ScopeSnapshot();
    FleuryAppController? commandApp;
    StatusController? commandStatus;
    _RouteServices? commandExtension;
    _RouteDataSource? commandDataSource;
    ThemeData? commandTheme;

    late final _RouteServices services;
    services = _RouteServices(
      onInspect: (context) {
        commandApp = context.app;
        commandStatus = context.status;
        commandExtension = context.appExtension<_RouteServices>();
        commandDataSource = context.appDataSource<_RouteDataSource>();
        commandTheme = Theme.of(context.buildContext!);
      },
    );

    tester.pumpWidget(
      FleuryApp(
        title: 'Scoped App',
        theme: ThemeData.light(
          extensions: const <Object>[_AppThemeToken('app')],
        ),
        extensions: <Object>[services],
        status: (_) => <StatusItem>[
          StatusItem.text('Mode', id: 'mode', value: 'launch'),
        ],
        home: _ScopeProbe(snapshot: home, label: 'Home'),
      ),
    );

    expect(home.app, isNotNull);
    expect(home.navigator, same(home.rootNavigator));
    expect(home.navigator?.depth, 1);
    expect(home.extension, same(services));
    expect(home.dataSource?.value, 'workspace');
    expect(home.commands?.command(_inspectRoute), isNotNull);
    expect(home.app?.status.items, <StatusItem>[
      StatusItem.text('Mode', id: 'mode', value: 'launch'),
      StatusItem.success('Package', id: 'package', value: 'ready'),
    ]);
    expect(home.theme?.brightness, Brightness.light);
    expect(home.theme?.extension<_AppThemeToken>()?.value, 'app');
    expect(home.theme?.extension<_PackageThemeToken>()?.value, 'package');

    home.navigator!.push<void>(
      _ScopeProbe(
        snapshot: detail,
        label: 'Detail',
        child: const Column(children: <Widget>[Text('Detail'), AppStatusBar()]),
      ),
      transition: RouteTransition.none,
    );
    tester.pump();

    expect(tester.exists(text('Detail')), isTrue);
    expect(tester.exists(text('Mode: launch')), isTrue);
    expect(tester.exists(text('Package: ready')), isTrue);
    expect(detail.app, same(home.app));
    expect(detail.commands, same(home.commands));
    expect(detail.theme, same(home.theme));
    expect(detail.navigator, same(home.navigator));
    expect(detail.rootNavigator, same(home.rootNavigator));
    expect(detail.navigator?.depth, 2);
    expect(detail.extension, same(home.extension));
    expect(detail.dataSource, same(home.dataSource));

    final result = await detail.commands!.invoke(
      _inspectRoute,
      buildContext: detail.context,
    );

    expect(result.status, CommandInvocationStatus.completed);
    expect(commandApp, same(detail.app));
    expect(commandStatus, same(detail.app?.status));
    expect(commandExtension, same(services));
    expect(commandDataSource, same(detail.dataSource));
    expect(commandTheme, same(detail.theme));
  });

  testWidgets('app shortcut and semantics commands receive route context', (
    tester,
  ) async {
    BuildContext? homeContext;

    void push(CommandContext command, String label) {
      unawaited(
        command.buildContext!.push<void>(
          Text(label),
          transition: RouteTransition.none,
        ),
      );
    }

    void replace(CommandContext command, String label) {
      unawaited(
        command.buildContext!.pushReplacement<void>(
          Text(label),
          transition: RouteTransition.none,
        ),
      );
    }

    tester.pumpWidget(
      FleuryApp(
        title: 'Navigation Commands',
        commands: <AppCommand>[
          AppCommand(
            id: _shortcutRoute,
            title: 'Shortcut Route',
            shortcuts: <KeyChord>[KeyChord.ctrl.n],
            run: (context) => push(context, 'Shortcut detail'),
          ),
          AppCommand(
            id: _semanticRoute,
            title: 'Semantic Route',
            semanticAction: SemanticAction.navigate,
            run: (context) => push(context, 'Semantic detail'),
          ),
          AppCommand(
            id: _replaceRoute,
            title: 'Replace Route',
            semanticAction: SemanticAction.navigate,
            run: (context) => replace(context, 'Non-focusable replacement'),
          ),
          AppCommand(
            id: _afterReplacement,
            title: 'Navigate After Replacement',
            semanticAction: SemanticAction.navigate,
            run: (context) => push(context, 'After replacement'),
          ),
        ],
        home: _Capture((context) {
          homeContext = context;
        }),
      ),
    );

    tester.sendKey(
      const KeyEvent(char: 'n', modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.value();
    tester.pump();

    expect(tester.exists(text('Shortcut detail')), isTrue);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.completed);
    expect(homeContext!.navigator, same(homeContext!.rootNavigator));

    homeContext!.navigator.pop();
    tester.pump();

    final semanticResult = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.command,
      label: 'Semantic Route',
    );

    expect(semanticResult.completed, isTrue);
    expect(tester.exists(text('Semantic detail')), isTrue);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.completed);
    expect(homeContext!.navigator.depth, 2);

    homeContext!.navigator.pop();
    tester.pump();
    final navigator = homeContext!.navigator;

    final replaceResult = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.command,
      label: 'Replace Route',
    );

    expect(replaceResult.completed, isTrue);
    expect(tester.exists(text('Non-focusable replacement')), isTrue);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.completed);
    expect(navigator.depth, 1);

    final afterReplacementResult = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.command,
      label: 'Navigate After Replacement',
    );

    expect(afterReplacementResult.completed, isTrue);
    expect(tester.exists(text('After replacement')), isTrue);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.completed);
    expect(navigator.depth, 2);
  });

  testWidgets('home updates from its parent without resetting route stack', (
    tester,
  ) {
    final hostKey = GlobalKey<_UpdatingHomeHostState>();
    tester.pumpWidget(_UpdatingHomeHost(key: hostKey));

    final navigator = hostKey.currentState!.navigator!;
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.route, selected: true)
          .state
          .routeName,
      '_TypedHome',
    );
    navigator.push<void>(
      const Text('Pushed detail'),
      transition: RouteTransition.none,
    );
    tester.pump();

    expect(tester.exists(text('Home 1')), isTrue);
    expect(tester.exists(text('Pushed detail')), isTrue);
    expect(navigator.depth, 2);

    hostKey.currentState!.updateHome();
    tester.pump();

    expect(tester.exists(text('Home 1')), isFalse);
    expect(tester.exists(text('Home 2')), isTrue);
    expect(tester.exists(text('Pushed detail')), isTrue);
    expect(navigator.depth, 2);

    navigator.push<void>(
      const Text('Top detail'),
      transition: RouteTransition.none,
    );
    tester.pump();
    expect(navigator.depth, 3);

    navigator.popUntil<_TypedHome>();
    tester.pump();

    expect(tester.exists(text('Home 2')), isTrue);
    expect(navigator.depth, 1);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.route, selected: true)
          .state
          .routeName,
      '_TypedHome',
    );
  });

  testWidgets('home delegates focus traversal to its Navigator route', (
    tester,
  ) {
    final right = FocusNode(debugLabel: 'right');
    addTearDown(right.dispose);

    tester.pumpWidget(
      FleuryApp(
        title: 'Traversal',
        home: Row(
          children: <Widget>[
            const SizedBox(
              width: 8,
              child: Focus(autofocus: true, child: Text('Left')),
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

  testWidgets('child remains an explicit custom shell without navigation', (
    tester,
  ) {
    BuildContext? childContext;
    FleuryAppController? app;
    ThemeData? theme;

    tester.pumpWidget(
      FleuryApp(
        title: 'Custom Shell',
        theme: ThemeData.light(),
        child: _Capture((context) {
          childContext = context;
          app = FleuryApp.of(context);
          theme = Theme.of(context);
        }),
      ),
    );

    expect(app?.title, 'Custom Shell');
    expect(theme?.brightness, Brightness.light);
    expect(Navigator.maybeOf(childContext!), isNull);
    expect(Navigator.maybeOf(childContext!, rootNavigator: true), isNull);
  });

  testWidgets('custom-shell commands use the active route before focus lands', (
    tester,
  ) async {
    NavigatorState? navigator;
    BuildContext? semanticContext;
    BuildContext? shortcutContext;

    void push(CommandContext command, String label) {
      final context = command.buildContext!;
      unawaited(
        context.push<void>(Text(label), transition: RouteTransition.none),
      );
    }

    tester.pumpWidget(
      FleuryApp(
        title: 'Custom Navigation Shell',
        commands: <AppCommand>[
          AppCommand(
            id: _semanticRoute,
            title: 'Custom Semantic Route',
            semanticAction: SemanticAction.navigate,
            run: (command) {
              semanticContext = command.buildContext;
              push(command, 'Custom semantic detail');
            },
          ),
          AppCommand(
            id: _shortcutRoute,
            title: 'Custom Shortcut Route',
            shortcuts: <KeyChord>[KeyChord.ctrl.n],
            run: (command) {
              shortcutContext = command.buildContext;
              push(command, 'Custom shortcut detail');
            },
          ),
        ],
        child: Navigator(
          home: _Capture((context) {
            navigator = Navigator.of(context);
          }),
        ),
      ),
    );

    final initialRouteContext = navigator!.activeRouteContext;
    expect(initialRouteContext, isNotNull);
    expect(Focus.maybeOf(initialRouteContext!)?.focusedNode, isNull);

    final semanticResult = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.command,
      label: 'Custom Semantic Route',
    );

    expect(semanticResult.completed, isTrue);
    expect(semanticContext, same(initialRouteContext));
    expect(Navigator.maybeOf(semanticContext!), same(navigator));
    expect(tester.exists(text('Custom semantic detail')), isTrue);
    expect(navigator!.depth, 2);

    navigator!.pop();
    tester.pump();
    final shortcutRouteContext = navigator!.activeRouteContext;
    expect(shortcutRouteContext, isNotNull);

    tester.sendKey(
      const KeyEvent(char: 'n', modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.value();
    tester.pump();

    expect(shortcutContext, same(shortcutRouteContext));
    expect(Navigator.maybeOf(shortcutContext!), same(navigator));
    expect(tester.exists(text('Custom shortcut detail')), isTrue);
    expect(tester.lastCommandResult?.status, CommandInvocationStatus.completed);
    expect(navigator!.depth, 2);
  });

  testWidgets('app shortcut predicates follow mounted routes without focus', (
    tester,
  ) async {
    const rootOnly = CommandId('route.root-only');
    const detailOnly = CommandId('route.detail-only');
    NavigatorState? navigator;
    var rootCalls = 0;
    var detailCalls = 0;

    int? routeDepth(CommandContext command) {
      final context = command.buildContext;
      if (context == null || !context.mounted) return null;
      return Navigator.maybeOf(context)?.depth;
    }

    tester.pumpWidget(
      FleuryApp(
        title: 'Route Predicates',
        commands: <AppCommand>[
          AppCommand(
            id: rootOnly,
            title: 'Root Only',
            shortcuts: <KeyChord>[KeyChord.ctrl.r],
            visible: (command) => routeDepth(command) == 1,
            run: (_) {
              rootCalls += 1;
            },
          ),
          AppCommand(
            id: detailOnly,
            title: 'Detail Only',
            shortcuts: <KeyChord>[KeyChord.ctrl.d],
            enabled: (command) => (routeDepth(command) ?? 0) > 1,
            run: (_) {
              detailCalls += 1;
            },
          ),
        ],
        home: _Capture((context) {
          navigator = Navigator.of(context);
        }),
      ),
    );
    await tester.settle();

    expect(navigator, isNotNull);
    expect(navigator!.activeRouteContext, isNotNull);
    expect(tester.focusManager.focusedNode, isNull);
    expect(
      tester.semantics().single(role: SemanticRole.command, label: 'Root Only'),
      isNotNull,
    );
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.command, label: 'Detail Only')
          .enabled,
      isFalse,
    );

    tester.sendKey(
      const KeyEvent(char: 'r', modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    tester.sendKey(
      const KeyEvent(char: 'd', modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.value();
    expect(rootCalls, 1);
    expect(detailCalls, 0);

    navigator!.push<void>(
      const Text('Detail'),
      transition: RouteTransition.none,
    );
    await tester.settle();

    expect(tester.focusManager.focusedNode, isNull);
    expect(
      tester.semantics().where(role: SemanticRole.command, label: 'Root Only'),
      isEmpty,
    );
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.command, label: 'Detail Only')
          .enabled,
      isTrue,
    );
    tester.sendKey(
      const KeyEvent(char: 'd', modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.value();
    expect(detailCalls, 1);

    navigator!.pop();
    await tester.settle();

    expect(tester.focusManager.focusedNode, isNull);
    expect(
      tester.semantics().single(role: SemanticRole.command, label: 'Root Only'),
      isNotNull,
    );
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.command, label: 'Detail Only')
          .enabled,
      isFalse,
    );

    navigator!.push<void>(
      const Text('Detail before reset'),
      transition: RouteTransition.none,
    );
    await tester.settle();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.command, label: 'Detail Only')
          .enabled,
      isTrue,
    );

    navigator!.pushAndClear<void>(const Text('Reset root'));
    await tester.settle();

    expect(navigator!.depth, 1);
    expect(tester.focusManager.focusedNode, isNull);
    expect(
      tester.semantics().single(role: SemanticRole.command, label: 'Root Only'),
      isNotNull,
    );
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.command, label: 'Detail Only')
          .enabled,
      isFalse,
    );
  });
}

final class _Capture extends StatelessWidget {
  const _Capture(this.capture);

  final void Function(BuildContext context) capture;

  @override
  Widget build(BuildContext context) {
    capture(context);
    return const Text('Custom');
  }
}

final class _UpdatingHomeHost extends StatefulWidget {
  const _UpdatingHomeHost({super.key});

  @override
  State<_UpdatingHomeHost> createState() => _UpdatingHomeHostState();
}

final class _UpdatingHomeHostState extends State<_UpdatingHomeHost> {
  int revision = 1;
  NavigatorState? navigator;

  void updateHome() {
    setState(() {
      revision += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FleuryApp(
      title: 'Updating Home',
      home: _TypedHome(
        revision: revision,
        capture: (context) {
          navigator = Navigator.of(context);
        },
      ),
    );
  }
}

final class _TypedHome extends StatelessWidget {
  const _TypedHome({required this.revision, required this.capture});

  final int revision;
  final void Function(BuildContext context) capture;

  @override
  Widget build(BuildContext context) {
    capture(context);
    return Text('Home $revision');
  }
}
