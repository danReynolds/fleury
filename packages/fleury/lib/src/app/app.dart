import 'dart:async' show unawaited;

import '../foundation/collections.dart';
import '../foundation/change_notifier.dart';
import '../semantics/semantics.dart';
import '../widgets/basic.dart';
import '../widgets/focus_traversal.dart';
import '../widgets/framework.dart';
import '../widgets/inherited_notifier.dart';
import '../widgets/key_bindings.dart';
import '../widgets/theme.dart';
import 'commands.dart';
import 'status.dart';

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
class FleuryAppController extends ChangeNotifier implements StatusHost {
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
  @override
  final StatusController status;

  String get title => _title;
  set title(String value) {
    _checkNotDisposed();
    if (_title == value) return;
    _title = value;
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FleuryAppController has been disposed.');
    }
  }
}

/// Shares a [FleuryAppController] with descendants.
class FleuryAppScope extends InheritedNotifier<FleuryAppController> {
  const FleuryAppScope({
    super.key,
    required FleuryAppController controller,
    required super.child,
  }) : super(notifier: controller);

  static FleuryAppController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw StateError('No FleuryAppScope found in context.');
    }
    return controller;
  }

  static FleuryAppController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FleuryAppScope>()
        ?.notifier;
  }
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

/// App-scale shell for commands, status, and app-level extension plumbing.
class FleuryApp extends StatefulWidget {
  const FleuryApp({
    super.key,
    required this.title,
    this.commands = const <AppCommand>[],
    this.extensions = const <Object>[],
    this.status,
    this.child,
  });

  final String title;
  final List<AppCommand> commands;
  final List<Object> extensions;
  final AppStatusBuilder? status;
  final Widget? child;

  static FleuryAppController of(BuildContext context) =>
      FleuryAppScope.of(context);

  static FleuryAppController? maybeOf(BuildContext context) =>
      FleuryAppScope.maybeOf(context);

  static T? maybeExtension<T extends Object>(BuildContext context) =>
      maybeOf(context)?.maybeExtension<T>();

  static T extension<T extends Object>(BuildContext context) {
    final extension = maybeExtension<T>(context);
    if (extension == null) {
      throw StateError('No Fleury app extension of type $T found in context.');
    }
    return extension;
  }

  static T? maybeDataSource<T extends Object>(BuildContext context) =>
      maybeOf(context)?.maybeDataSource<T>();

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
    _status.update(_appStatusItems(widget, _app));
  }

  List<KeyBinding> _bindings(BuildContext context) {
    final bindings = <KeyBinding>[];
    for (final command in _commands.localCommands) {
      if (command.shortcuts.isEmpty) continue;
      if (!_commandVisible(command, context)) continue;
      bindings.add(
        KeyBinding.list(
          command.shortcuts,
          label: command.title,
          enabled: _commandEnabled(command, context),
          onEvent: (_) {
            unawaited(_commands.invoke(command.id, buildContext: context));
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
    final body = widget.child ?? const EmptyBox();
    final app = CommandRegistryScope(
      registry: _commands,
      child: StatusHostScope(
        lookup: _app,
        child: FleuryAppScope(
          controller: _app,
          child: _ContextBuilder(
            builder: (innerContext) {
              return _FleuryAppSemantics(
                controller: _app,
                buildContext: innerContext,
                child: KeyBindings(
                  bindings: _bindings(innerContext),
                  child: FocusTraversalGroup(child: body),
                ),
              );
            },
          ),
        ),
      ),
    );
    return _AppExtensionTheme(app: widget, child: app);
  }
}

List<AppCommand> _appCommands(FleuryApp app) {
  final commands = <AppCommand>[...app.commands];
  for (final extension in app.extensions) {
    if (extension is FleuryAppExtension) {
      commands.addAll(extension.commands);
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

final class _AppExtensionTheme extends StatelessWidget {
  const _AppExtensionTheme({required this.app, required this.child});

  final FleuryApp app;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final extensionThemes = _appThemeExtensions(app);
    if (extensionThemes.isEmpty) return child;
    final base = Theme.of(context);
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
    required this.buildContext,
    required super.child,
  });

  final FleuryAppController controller;
  final BuildContext buildContext;

  @override
  _FleuryAppSemanticsElement createElement() {
    return _FleuryAppSemanticsElement(this);
  }
}

final class _FleuryAppSemanticsElement extends ComponentElement
    implements SemanticContributor, SemanticActionContributor {
  _FleuryAppSemanticsElement(_FleuryAppSemantics super.widget);

  @override
  _FleuryAppSemantics get widget => super.widget as _FleuryAppSemantics;

  @override
  void update(covariant _FleuryAppSemantics newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  Widget buildChild() => widget.child;

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    final commands = widget.controller.commands.localCommands;
    final commandNodes = <SemanticNode>[];
    for (final command in commands) {
      final context = _ScopedCommandContext(
        commands: widget.controller.commands,
        buildContext: widget.buildContext,
      );
      if (!command.visible(context)) continue;
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
          enabled: command.enabled(context),
          actions: <SemanticAction>{
            SemanticAction.activate,
            if (command.semanticAction != null) command.semanticAction!,
          },
          state: SemanticState(state),
        ),
      );
    }

    final lastCommand = widget.controller.commands.lastResult;
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
      await widget.controller.commands.invokeCommand(
        command,
        buildContext: widget.buildContext,
      );
      return true;
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
