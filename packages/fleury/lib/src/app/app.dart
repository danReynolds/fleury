import '../foundation/collections.dart';
import '../foundation/change_notifier.dart';
import '../semantics/semantics.dart';
import '../widgets/focus.dart';
import '../widgets/focus_traversal.dart';
import '../widgets/framework.dart';
import '../widgets/key_bindings.dart';
import '../widgets/navigator.dart';
import '../widgets/theme.dart';
import '../widgets/tui_binding.dart';
import 'commands.dart';
import 'status.dart';

/// Builds an app's status items from its controller; see [FleuryApp.status].
typedef AppStatusBuilder = List<StatusItem> Function(FleuryAppController app);

/// Optional convention for app-level extension objects.
///
/// Ordinary objects registered through [FleuryApp.extensions] remain valid and
/// are only available through typed lookup. Objects that extend
/// [FleuryAppExtension] may also contribute app-level commands, status items,
/// package-owned theme extensions, and typed data sources. This is
/// intentionally a static contribution contract, not plugin discovery,
/// package loading, or lifecycle management.
abstract class FleuryAppExtension {
  const FleuryAppExtension();

  /// App-level commands contributed by this extension.
  ///
  /// Host app commands are registered before extension commands, so app-owned
  /// commands win if an extension and app use the same [CommandId].
  List<AppCommand> get commands => const <AppCommand>[];

  /// App-level status items contributed by this extension.
  ///
  /// These are appended after [FleuryApp.status] items.
  List<StatusItem> status(FleuryAppController app) => const <StatusItem>[];

  /// Theme extensions contributed by this app extension.
  ///
  /// These are appended after the ambient [ThemeData.extensions], so host app
  /// theme entries win if both provide an extension assignable to the same
  /// type.
  List<Object> get themeExtensions => const <Object>[];

  /// Typed data/read-model objects contributed by this app extension.
  ///
  /// These are plain app-owned objects. Fleury provides typed lookup only; it
  /// does not create, dispose, cache, refresh, page, or serialize data sources.
  List<Object> get dataSources => const <Object>[];
}

/// Root controller installed by [FleuryApp].
class FleuryAppController extends Notifier {
  FleuryAppController({
    required String title,
    required this.commands,
    required this.status,
    List<Object> extensions = const <Object>[],
  }) : _title = title,
       _extensions = List<Object>.unmodifiable(extensions) {
    commands.addListener(_notifyChanged);
    status.addListener(_notifyChanged);
  }

  String _title;
  List<Object> _extensions;
  bool _disposed = false;
  final CommandRegistry commands;
  final StatusController status;

  String get title => _title;
  set title(String value) {
    _checkNotDisposed();
    if (_title == value) return;
    _title = value;
    notify();
  }

  /// App-level extension objects registered by the host application.
  ///
  /// Extensions are intentionally plain typed objects. They give domain
  /// packages and integration packages a stable app-kernel seam without
  /// making core Fleury own plugin loading, provider lifecycles, or protocol
  /// adapters.
  List<Object> get extensions => _extensions;

  /// Returns the first registered app extension assignable to [T], if present.
  T? maybeExtension<T extends Object>() {
    for (final extension in _extensions) {
      if (extension is T) return extension;
    }
    return null;
  }

  /// Returns the first registered app extension assignable to [T].
  ///
  /// Throws if no matching extension is registered on the current app.
  T extension<T extends Object>() {
    final extension = maybeExtension<T>();
    if (extension == null) {
      throw StateError('No Fleury app extension of type $T is registered.');
    }
    return extension;
  }

  /// Data/read-model objects contributed by registered [FleuryAppExtension]s.
  List<Object> get dataSources {
    return List<Object>.unmodifiable(_appExtensionDataSources(_extensions));
  }

  /// Returns the first contributed app data source assignable to [T], if
  /// present.
  T? maybeDataSource<T extends Object>() {
    for (final dataSource in _appExtensionDataSources(_extensions)) {
      if (dataSource is T) return dataSource;
    }
    return null;
  }

  /// Returns the first contributed app data source assignable to [T].
  ///
  /// Throws if no matching data source is registered on the current app.
  T dataSource<T extends Object>() {
    final dataSource = maybeDataSource<T>();
    if (dataSource == null) {
      throw StateError('No Fleury app data source of type $T is registered.');
    }
    return dataSource;
  }

  void updateExtensions(List<Object> extensions) {
    _checkNotDisposed();
    if (listEquals(_extensions, extensions)) return;
    _extensions = List<Object>.unmodifiable(extensions);
    notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    commands.removeListener(_notifyChanged);
    status.removeListener(_notifyChanged);
    super.dispose();
  }

  void _notifyChanged() {
    if (_disposed) return;
    notify();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FleuryAppController has been disposed.');
    }
  }
}

/// Shares a [FleuryAppController] with descendants — a
/// `Scope<FleuryAppController>` installed by [FleuryApp].
class FleuryAppScope extends Scope<FleuryAppController> {
  const FleuryAppScope({
    super.key,
    required FleuryAppController controller,
    required super.child,
  }) : super(controller);

  static FleuryAppController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw StateError('No FleuryAppScope found in context.');
    }
    return controller;
  }

  static FleuryAppController? maybeOf(BuildContext context) =>
      dependOnScope<FleuryAppController>(context);
}

extension FleuryCommandContext on CommandContext {
  FleuryAppController? get app {
    final context = buildContext;
    return context == null ? null : FleuryAppScope.maybeOf(context);
  }

  StatusController? get status {
    final context = buildContext;
    return context == null ? null : FleuryAppScope.maybeOf(context)?.status;
  }

  T? maybeAppExtension<T extends Object>() => app?.maybeExtension<T>();

  T appExtension<T extends Object>() {
    final extension = maybeAppExtension<T>();
    if (extension == null) {
      throw StateError(
        'No Fleury app extension of type $T is available for this command.',
      );
    }
    return extension;
  }

  T? maybeAppDataSource<T extends Object>() => app?.maybeDataSource<T>();

  T appDataSource<T extends Object>() {
    final dataSource = maybeAppDataSource<T>();
    if (dataSource == null) {
      throw StateError(
        'No Fleury app data source of type $T is available for this command.',
      );
    }
    return dataSource;
  }
}

/// The app-scale shell: it installs the app's [theme], its [commands] with
/// their keyboard shortcuts, a [StatusController] for [status] items, typed
/// [extensions], focus traversal, and the app's semantic node, labeled
/// [title]; then it shows [home] in a root [Navigator], or your own [child]
/// shell.
///
/// Pass [home] for the standard app shell. Fleury installs a root [Navigator]
/// below every app-owned scope, so all pushed routes retain the same theme,
/// commands, status, extensions, and data sources.
///
/// Pass [child] instead when the app owns a custom shell, including its own
/// navigation. Exactly one of [home] and [child] must be provided.
///
/// Descendants reach the app through [FleuryApp.of], which returns its
/// [FleuryAppController].
class FleuryApp extends StatefulWidget {
  const FleuryApp({
    super.key,
    required this.title,
    this.commands = const <AppCommand>[],
    this.extensions = const <Object>[],
    this.status,
    this.theme,
    this.home,
    this.child,
  }) : assert(
         (home == null) != (child == null),
         'Exactly one of home or child must be provided.',
       );

  /// The app's name, used as the label of the app's semantic node
  /// ([SemanticRole.app]), which is how agents and tests identify the app. It
  /// isn't shown in the app's UI, and it doesn't set the terminal's window or
  /// tab title.
  ///
  /// `setTerminalTitle` sets the window title. Code can read the name as
  /// [FleuryAppController.title]; rebuilding with a new title updates both.
  final String title;

  /// App-wide commands: named actions that shortcuts, command palettes,
  /// agents, and tests can run on any screen.
  ///
  /// Each command's [AppCommand.shortcuts] are bound at the app root and run
  /// it only while it is visible and enabled; otherwise the key passes on.
  /// While a presented dialog is on top, keys it doesn't handle stop at the
  /// dialog, so app shortcuts wait until it closes. Each visible command also
  /// appears as a `command` node under the app's semantic node, which an
  /// agent or test can activate. A shortcut or semantic activation runs the
  /// command with [CommandContext.buildContext] set to the focused widget's
  /// context when focus is inside the app, else to the active route's when
  /// there is one.
  ///
  /// Ids must be unique within the list; a duplicate throws an
  /// [ArgumentError]. Commands contributed by [FleuryAppExtension]s follow
  /// these, and one with the same id as a command here is dropped. A
  /// [CommandScope] adds screen-level commands. A lookup by id from inside
  /// it, as a registry-backed command palette or [CommandRegistry.command]
  /// makes, finds the scope's command before an app command with the same id.
  /// The app's own shortcut and semantic node still run the app's command; a
  /// scope command bound to the same shortcut takes the key first, as a
  /// deeper binding does. Rebuilding with a new list replaces the commands.
  final List<AppCommand> commands;

  /// App-owned objects that descendants and commands look up by type, such
  /// as a workspace or a service client: [FleuryApp.extension] in a widget,
  /// [FleuryCommandContext.appExtension] in a command. The first entry
  /// assignable to the requested type wins.
  ///
  /// An entry that extends [FleuryAppExtension] also contributes to the app:
  /// commands (after [commands], which win on a matching id), status items
  /// (after those [status] builds), theme extensions (after the theme's own,
  /// which win on a matching type), and data sources for
  /// [FleuryApp.dataSource]. Fleury only looks these objects up; it never
  /// creates, disposes, or refreshes them. Rebuilding with a new list updates
  /// the running app in place.
  final List<Object> extensions;

  /// Builds the status items the app derives from its own state, such as the
  /// current branch or a connection's health. An [AppStatusBar] placed in the
  /// app displays them; FleuryApp draws none itself.
  ///
  /// Items from [FleuryAppExtension]s follow these. Fleury calls the builder
  /// when the app starts, whenever its parent rebuilds it, and after each
  /// command run through the app's [CommandRegistry], not when the state it
  /// reads changes. Report state that changes on its own, such as a task's
  /// progress, with [StatusController.put] on `FleuryApp.of(context).status`;
  /// an item put there replaces the built item with the same id.
  final AppStatusBuilder? status;

  /// App-wide theme installed above the standard or custom shell.
  ///
  /// When omitted, Fleury preserves the ambient theme. Theme extensions
  /// contributed through [extensions] are appended as package defaults;
  /// entries in this theme (or the ambient theme) win on matching types.
  final ThemeData? theme;

  /// Initial route for Fleury's standard root [Navigator].
  final Widget? home;

  /// Explicit custom shell escape hatch.
  ///
  /// Fleury does not install a [Navigator] around this widget. Use this when
  /// the app supplies its own navigation or intentionally has none. A custom
  /// shell that needs global root navigation should expose one top-level
  /// [Navigator] and place any pane-local navigators beneath it; sibling root
  /// navigators have no unambiguous app-wide target.
  final Widget? child;

  /// The controller of the nearest [FleuryApp] above [context].
  ///
  /// [context] rebuilds whenever the controller notifies, which includes each
  /// change to the title, extensions, commands, or status, and each command
  /// run through the app's registry. Throws a [StateError] when there is no
  /// [FleuryApp] above.
  static FleuryAppController of(BuildContext context) =>
      FleuryAppScope.of(context);

  /// Like [of], but null when there is no [FleuryApp] above [context].
  static FleuryAppController? maybeOf(BuildContext context) =>
      FleuryAppScope.maybeOf(context);

  /// The first of the nearest app's [extensions] assignable to [T], or null
  /// when none is or there is no [FleuryApp] above [context].
  static T? maybeExtension<T extends Object>(BuildContext context) =>
      maybeOf(context)?.maybeExtension<T>();

  /// Like [maybeExtension], but throws a [StateError] when no extension
  /// matches.
  static T extension<T extends Object>(BuildContext context) {
    final extension = maybeExtension<T>(context);
    if (extension == null) {
      throw StateError('No Fleury app extension of type $T found in context.');
    }
    return extension;
  }

  /// The first data source assignable to [T] among those the nearest app's
  /// [FleuryAppExtension]s contribute, or null when none is or there is no
  /// [FleuryApp] above [context].
  static T? maybeDataSource<T extends Object>(BuildContext context) =>
      maybeOf(context)?.maybeDataSource<T>();

  /// Like [maybeDataSource], but throws a [StateError] when no data source
  /// matches.
  static T dataSource<T extends Object>(BuildContext context) {
    final dataSource = maybeDataSource<T>(context);
    if (dataSource == null) {
      throw StateError(
        'No Fleury app data source of type $T found in context.',
      );
    }
    return dataSource;
  }

  @override
  State<FleuryApp> createState() => _FleuryAppState();
}

class _FleuryAppState extends State<FleuryApp> {
  late final CommandRegistry _commands;
  late final StatusController _status;
  late final FleuryAppController _app;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _commands = CommandRegistry(commands: _appCommands(widget));
    _status = StatusController();
    _app = FleuryAppController(
      title: widget.title,
      commands: _commands,
      status: _status,
      extensions: widget.extensions,
    );
    _commands.addListener(_syncStatus);
    _syncStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _commands.parent = CommandRegistryScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant FleuryApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _app.title = widget.title;
    _app.updateExtensions(widget.extensions);
    _commands.localCommands = _appCommands(widget);
    _syncStatus();
  }

  void _syncStatus() {
    _status.updateDerived(_appStatusItems(widget, _app));
  }

  List<KeyBinding> _bindings(BuildContext context) {
    final bindings = <KeyBinding>[];
    for (final command in _commands.localCommands) {
      if (command.shortcuts.isEmpty) continue;
      bindings.add(
        // The predicates read app state, and this root rarely rebuilds, so
        // the shortcut asks them when its key is pressed — against the
        // source that invoke uses — and a disabled one lets the key bubble.
        KeyBinding.live(
          command.shortcuts.first,
          aliases: command.shortcuts.skip(1).toList(),
          label: command.title,
          isEnabled: () {
            final source = _commandSourceContext(context);
            return _commandVisible(command, source) &&
                _commandEnabled(command, source);
          },
          availability: command.availability,
          onTrigger: (_) {
            _commands.dispatch(
              command.id,
              buildContext: _commandSourceContext(context),
            );
          },
        ),
      );
    }
    return bindings;
  }

  bool _commandVisible(AppCommand command, BuildContext context) {
    return command.visible(
      _ScopedCommandContext(commands: _commands, buildContext: context),
    );
  }

  bool _commandEnabled(AppCommand command, BuildContext context) {
    return command.enabled(
      _ScopedCommandContext(commands: _commands, buildContext: context),
    );
  }

  // Reads, not dependencies: this runs from a shortcut's predicate, a key's
  // dispatch and a command's invocation. A dependency would rebuild the app's
  // bindings on every focus move, and subscribe every element that held focus
  // to the app controller, which notifies on every command result and status
  // change.
  BuildContext _commandSourceContext(BuildContext fallback) {
    final focused = FocusManager.maybeOfWithoutDependency(
      fallback,
    )?.focusedNode?.context;
    if (_isCurrentAppContext(focused)) return focused!;
    final route = _navigatorKey.currentState?.activeRouteContext;
    if (_isCurrentAppContext(route)) return route!;
    final rootRoute = readScope<TuiBinding>(
      fallback,
    )?.rootNavigator?.activeRouteContext;
    if (_isCurrentAppContext(rootRoute)) return rootRoute!;
    return fallback;
  }

  bool _isCurrentAppContext(BuildContext? context) {
    return context != null &&
        context.mounted &&
        identical(readScope<FleuryAppController>(context), _app);
  }

  @override
  void dispose() {
    _commands.removeListener(_syncStatus);
    _app.dispose();
    _commands.dispose();
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final command in _commands.localCommands) {
      final source = command.availability;
      if (source != null) context.listen(source);
    }
    final Widget body;
    if (widget.home != null) {
      body = Navigator(key: _navigatorKey, home: widget.home!);
    } else {
      body = widget.child!;
    }
    final app = CommandRegistryScope(
      registry: _commands,
      child: Scope<StatusController>(
        _app.status,
        child: FleuryAppScope(
          controller: _app,
          child: _ContextBuilder(
            builder: (innerContext) {
              return _FleuryAppSemantics(
                controller: _app,
                commandContext: () => _commandSourceContext(innerContext),
                child: KeyBindings(
                  bindings: _bindings(innerContext),
                  child: widget.home != null
                      ? body
                      : FocusTraversalGroup(child: body),
                ),
              );
            },
          ),
        ),
      ),
    );
    return _AppTheme(app: widget, child: app);
  }
}

List<AppCommand> _appCommands(FleuryApp app) {
  final commands = <AppCommand>[...app.commands];
  final appCommandIds = app.commands.map((command) => command.id).toSet();
  for (final extension in app.extensions) {
    if (extension is FleuryAppExtension) {
      for (final command in extension.commands) {
        // Extension commands are defaults. A host-owned command with the same
        // ID replaces that default before the combined list reaches the
        // registry's same-scope duplicate validation.
        if (!appCommandIds.contains(command.id)) commands.add(command);
      }
    }
  }
  return commands;
}

List<StatusItem> _appStatusItems(FleuryApp app, FleuryAppController state) {
  final items = <StatusItem>[];
  final builder = app.status;
  if (builder != null) {
    items.addAll(builder(state));
  }
  for (final extension in state.extensions) {
    if (extension is FleuryAppExtension) {
      items.addAll(extension.status(state));
    }
  }
  return items;
}

List<Object> _appThemeExtensions(FleuryApp app) {
  final extensions = <Object>[];
  for (final extension in app.extensions) {
    if (extension is FleuryAppExtension) {
      extensions.addAll(extension.themeExtensions);
    }
  }
  return extensions;
}

List<Object> _appExtensionDataSources(List<Object> extensions) {
  final dataSources = <Object>[];
  for (final extension in extensions) {
    if (extension is FleuryAppExtension) {
      dataSources.addAll(extension.dataSources);
    }
  }
  return dataSources;
}

final class _AppTheme extends StatelessWidget {
  const _AppTheme({required this.app, required this.child});

  final FleuryApp app;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final extensionThemes = _appThemeExtensions(app);
    final configuredTheme = app.theme;
    if (configuredTheme == null && extensionThemes.isEmpty) return child;
    final base = configuredTheme ?? Theme.of(context);
    return Theme(
      data: base.copyWith(
        extensions: <Object>[...base.extensions, ...extensionThemes],
      ),
      child: child,
    );
  }
}

final class _ScopedCommandContext implements CommandContext {
  const _ScopedCommandContext({
    required this.commands,
    required this.buildContext,
  });

  @override
  final CommandRegistry commands;

  @override
  final BuildContext buildContext;
}

final class _ContextBuilder extends StatelessWidget {
  const _ContextBuilder({required this.builder});

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

final class _FleuryAppSemantics extends ProxyWidget {
  const _FleuryAppSemantics({
    required this.controller,
    required this.commandContext,
    required super.child,
  });

  final FleuryAppController controller;
  final BuildContext Function() commandContext;

  @override
  _FleuryAppSemanticsElement createElement() {
    return _FleuryAppSemanticsElement(this);
  }
}

final class _FleuryAppSemanticsElement extends ComponentElement
    implements SemanticContributor, SemanticActionContributor {
  _FleuryAppSemanticsElement(_FleuryAppSemantics super.widget);

  final _observedAvailability = CommandAvailabilitySnapshot();

  @override
  _FleuryAppSemantics get widget => super.widget as _FleuryAppSemantics;

  @override
  void update(covariant _FleuryAppSemantics newWidget) {
    _observedAvailability.clear();
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  Widget buildChild() => widget.child;

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    final commands = widget.controller.commands.localCommands;
    final commandNodes = <SemanticNode>[];
    final buildContext = widget.commandContext();
    for (final command in commands) {
      final context = _ScopedCommandContext(
        commands: widget.controller.commands,
        buildContext: buildContext,
      );
      final availability = _observedAvailability.read(command, context);
      if (!availability.visible) continue;
      final shortcut = command.primaryShortcutLabel;
      final category = command.category;
      final state = <String, Object?>{'commandId': command.id.value};
      if (shortcut != null) {
        state['shortcut'] = shortcut;
      }
      if (category != null) {
        state['commandCategory'] = category;
      }
      commandNodes.add(
        SemanticNode(
          id: SemanticNodeId('app-command:${command.id.value}'),
          role: SemanticRole.command,
          label: command.title,
          value: command.description,
          hint: command.description,
          enabled: availability.enabled,
          actions: <SemanticAction>{
            SemanticAction.activate,
            if (command.semanticAction != null) command.semanticAction!,
          },
          state: SemanticState(state),
        ),
      );
    }

    // The latest command visible from where the app's commands run — a
    // screen's scoped command included, as FleuryTester.lastCommandResult
    // reports it. Read, not depended on: this runs on every semantic walk.
    final lastCommand =
        readScope<CommandRegistry>(buildContext)?.latestVisibleResult ??
        widget.controller.commands.lastResult;
    final screenSummary = _screenSummary(children);
    return SemanticNode(
      id: const SemanticNodeId('app'),
      role: SemanticRole.app,
      label: widget.controller.title,
      children: <SemanticNode>[...commandNodes, ...children],
      state: SemanticState({
        if (screenSummary.screenCount > 0)
          'screenCount': screenSummary.screenCount,
        if (screenSummary.activeScreenId != null)
          'activeScreenId': screenSummary.activeScreenId,
        'commandCount': commandNodes.length,
        'statusCount': widget.controller.status.length,
        if (lastCommand != null) 'lastCommandId': lastCommand.id.value,
        if (lastCommand != null) 'lastCommandStatus': lastCommand.status.name,
      }),
    );
  }

  _ScreenSemanticSummary _screenSummary(List<SemanticNode> children) {
    final ids = <String>{};
    String? activeId;
    for (final child in children) {
      for (final node in child.selfAndDescendants) {
        final screenId = node.state.screenId;
        if (screenId == null) continue;
        ids.add(screenId);
        if (activeId == null && node.selected) {
          activeId = screenId;
        }
      }
    }
    return _ScreenSemanticSummary(
      screenCount: ids.length,
      activeScreenId: activeId,
    );
  }

  @override
  Future<bool> handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  ) async {
    if (target.role != SemanticRole.command) return false;
    final commandId = target.state.commandId;
    if (commandId == null) return false;
    for (final command in widget.controller.commands.localCommands) {
      if (command.id.value != commandId) continue;
      if (action != SemanticAction.activate &&
          command.semanticAction != action) {
        return false;
      }
      return semanticOutcomeOf(
        await widget.controller.commands.invokeCommand(
          command,
          buildContext: widget.commandContext(),
        ),
      );
    }
    return false;
  }
}

final class _ScreenSemanticSummary {
  const _ScreenSemanticSummary({
    required this.screenCount,
    required this.activeScreenId,
  });

  final int screenCount;
  final String? activeScreenId;
}
