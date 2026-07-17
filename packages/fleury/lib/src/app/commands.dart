import 'dart:async' show FutureOr, unawaited;

import '../foundation/change_notifier.dart';
import '../semantics/semantics.dart';
import '../widgets/framework.dart';
import '../widgets/inherited_notifier.dart';
import '../widgets/key_bindings.dart';

/// Stable identifier for an app command.
final class CommandId {
  const CommandId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is CommandId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Runtime context passed to app commands and predicates.
abstract interface class CommandContext {
  CommandRegistry get commands;
  BuildContext? get buildContext;
}

bool _alwaysCommandPredicate(CommandContext context) => true;

typedef AppCommandCallback = FutureOr<void> Function(CommandContext context);
typedef AppCommandPredicate = bool Function(CommandContext context);

/// A named application action with metadata, shortcuts, and invocation policy.
final class AppCommand {
  const AppCommand({
    required this.id,
    required this.title,
    required this.run,
    this.description,
    this.category,
    this.shortcuts = const <KeyChord>[],
    this.enabled = _alwaysCommandPredicate,
    this.visible = _alwaysCommandPredicate,
    this.showInPalette = true,
    this.semanticAction,
  });

  final CommandId id;
  final String title;
  final AppCommandCallback run;
  final String? description;
  final String? category;
  final List<KeyChord> shortcuts;
  final AppCommandPredicate enabled;

  /// Whether the command participates in its scope at all.
  ///
  /// Invisible commands cannot be found, invoked, exposed semantically, or
  /// installed as shortcuts. To keep a command and its shortcuts active while
  /// omitting it only from command palettes, use [showInPalette].
  final AppCommandPredicate visible;

  /// Whether command palettes should list this command.
  ///
  /// This does not affect registry lookup, invocation, semantics, or shortcut
  /// installation. It is useful for commands that open the palette itself or
  /// actions discoverable through a more appropriate dedicated surface.
  final bool showInPalette;

  final SemanticAction? semanticAction;

  String? get primaryShortcutLabel =>
      shortcuts.isEmpty ? null : shortcuts.first.hintLabel;
}

enum CommandInvocationStatus { completed, disabled, notFound, failed }

/// Result of a programmatic command invocation.
final class CommandInvocationResult {
  const CommandInvocationResult._({
    required this.id,
    required this.status,
    this.command,
    this.error,
    this.stackTrace,
  });

  factory CommandInvocationResult.completed(
    CommandId id, {
    required AppCommand command,
  }) {
    return CommandInvocationResult._(
      id: id,
      status: CommandInvocationStatus.completed,
      command: command,
    );
  }

  factory CommandInvocationResult.disabled(
    CommandId id, {
    required AppCommand command,
  }) {
    return CommandInvocationResult._(
      id: id,
      status: CommandInvocationStatus.disabled,
      command: command,
    );
  }

  factory CommandInvocationResult.notFound(CommandId id) {
    return CommandInvocationResult._(
      id: id,
      status: CommandInvocationStatus.notFound,
    );
  }

  factory CommandInvocationResult.failed(
    CommandId id, {
    required AppCommand command,
    required Object error,
    required StackTrace stackTrace,
  }) {
    return CommandInvocationResult._(
      id: id,
      status: CommandInvocationStatus.failed,
      command: command,
      error: error,
      stackTrace: stackTrace,
    );
  }

  final CommandId id;
  final CommandInvocationStatus status;
  final AppCommand? command;
  final Object? error;
  final StackTrace? stackTrace;

  bool get completed => status == CommandInvocationStatus.completed;

  @override
  String toString() => 'CommandInvocationResult($id, $status)';
}

final class _CommandInvocationContext implements CommandContext {
  const _CommandInvocationContext({
    required this.commands,
    required this.buildContext,
  });

  @override
  final CommandRegistry commands;

  @override
  final BuildContext? buildContext;
}

/// Scoped registry for active app commands.
///
/// Registries can form a parent chain. Local commands win over parent commands
/// with the same ID, matching the app-kernel rule that nearer scopes have
/// higher priority.
class CommandRegistry extends ChangeNotifier {
  CommandRegistry({
    CommandRegistry? parent,
    List<AppCommand> commands = const <AppCommand>[],
  }) : _commands = List<AppCommand>.of(commands) {
    this.parent = parent;
  }

  CommandRegistry? _parent;
  List<AppCommand> _commands;
  CommandInvocationResult? _lastResult;
  bool _disposed = false;

  CommandRegistry? get parent => _parent;
  set parent(CommandRegistry? value) {
    _checkNotDisposed();
    if (identical(_parent, value)) return;
    _parent?.removeListener(_notifyParentChanged);
    _parent = value;
    _parent?.addListener(_notifyParentChanged);
    notifyListeners();
  }

  List<AppCommand> get localCommands =>
      List<AppCommand>.unmodifiable(_commands);

  set localCommands(List<AppCommand> value) {
    _checkNotDisposed();
    _commands = List<AppCommand>.of(value);
    notifyListeners();
  }

  CommandInvocationResult? get lastResult => _lastResult;

  List<AppCommand> activeCommands({BuildContext? buildContext}) {
    final context = _context(buildContext);
    final active = <AppCommand>[];
    final seen = <CommandId>{};

    for (final command in _commands) {
      if (!command.visible(context)) continue;
      active.add(command);
      seen.add(command.id);
    }

    final parentCommands = _parent?.activeCommands(buildContext: buildContext);
    if (parentCommands != null) {
      for (final command in parentCommands) {
        if (seen.contains(command.id)) continue;
        active.add(command);
        seen.add(command.id);
      }
    }

    return List<AppCommand>.unmodifiable(active);
  }

  AppCommand? command(CommandId id, {BuildContext? buildContext}) {
    final context = _context(buildContext);
    for (final command in _commands) {
      if (command.id == id && command.visible(context)) return command;
    }
    return _parent?.command(id, buildContext: buildContext);
  }

  bool isEnabled(AppCommand command, {BuildContext? buildContext}) {
    return command.enabled(_context(buildContext));
  }

  bool isVisible(AppCommand command, {BuildContext? buildContext}) {
    return command.visible(_context(buildContext));
  }

  Future<CommandInvocationResult> invoke(
    CommandId id, {
    BuildContext? buildContext,
  }) async {
    _checkNotDisposed();
    final command = this.command(id, buildContext: buildContext);
    if (command == null) {
      return _record(CommandInvocationResult.notFound(id));
    }

    return invokeCommand(command, buildContext: buildContext);
  }

  /// Invokes a concrete command instance while still applying registry policy.
  ///
  /// This supports command surfaces that already resolved priority, such as a
  /// shell-level command palette that includes active screen commands before
  /// app-global commands.
  Future<CommandInvocationResult> invokeCommand(
    AppCommand command, {
    BuildContext? buildContext,
  }) async {
    _checkNotDisposed();
    final context = _context(buildContext);
    if (!command.visible(context)) {
      return _record(CommandInvocationResult.notFound(command.id));
    }

    if (!command.enabled(context)) {
      return _record(
        CommandInvocationResult.disabled(command.id, command: command),
      );
    }

    try {
      await command.run(context);
      return _record(
        CommandInvocationResult.completed(command.id, command: command),
      );
    } catch (error, stackTrace) {
      return _record(
        CommandInvocationResult.failed(
          command.id,
          command: command,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  _CommandInvocationContext _context(BuildContext? buildContext) {
    return _CommandInvocationContext(
      commands: this,
      buildContext: buildContext,
    );
  }

  CommandInvocationResult _record(CommandInvocationResult result) {
    if (_disposed) return result;
    _lastResult = result;
    notifyListeners();
    return result;
  }

  void _notifyParentChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('CommandRegistry has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _parent?.removeListener(_notifyParentChanged);
    _parent = null;
    super.dispose();
  }
}

/// Shares a [CommandRegistry] with descendants.
class CommandRegistryScope extends InheritedNotifier<CommandRegistry> {
  const CommandRegistryScope({
    super.key,
    required CommandRegistry registry,
    required super.child,
  }) : super(notifier: registry);

  static CommandRegistry of(BuildContext context) {
    final registry = maybeOf(context);
    if (registry == null) {
      throw StateError('No CommandRegistryScope found in context.');
    }
    return registry;
  }

  static CommandRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CommandRegistryScope>()
        ?.notifier;
  }
}

/// Adds commands to the active app command scope.
///
/// The scope also emits shortcut [KeyBinding]s for its local commands so
/// keyboard input still flows through the existing dispatcher.
class CommandScope extends StatefulWidget {
  const CommandScope({
    super.key,
    required this.commands,
    required this.child,
    this.label = 'Command scope',
    this.enabled = true,
  });

  final List<AppCommand> commands;
  final Widget child;
  final String label;
  final bool enabled;

  @override
  State<CommandScope> createState() => _CommandScopeState();
}

class _CommandScopeState extends State<CommandScope> {
  CommandRegistry? _registry;
  CommandRegistry? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRegistryParent();
  }

  @override
  void didUpdateWidget(covariant CommandScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registry?.localCommands = _effectiveCommands;
  }

  List<AppCommand> get _effectiveCommands =>
      widget.enabled ? widget.commands : const <AppCommand>[];

  void _syncRegistryParent() {
    final parent = CommandRegistryScope.maybeOf(context);
    if (_registry == null || !identical(parent, _parent)) {
      _registry?.dispose();
      _parent = parent;
      _registry = CommandRegistry(parent: parent, commands: _effectiveCommands);
    }
  }

  List<KeyBinding> _bindings(CommandRegistry registry) {
    final bindings = <KeyBinding>[];
    for (final command in registry.localCommands) {
      if (command.shortcuts.isEmpty) continue;
      final context = _CommandInvocationContext(
        commands: registry,
        buildContext: this.context,
      );
      if (!command.visible(context)) continue;
      bindings.add(
        KeyBinding.list(
          command.shortcuts,
          label: command.title,
          enabled: command.enabled(context),
          onEvent: (_) {
            unawaited(registry.invoke(command.id, buildContext: this.context));
          },
        ),
      );
    }
    return bindings;
  }

  @override
  void dispose() {
    _registry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = _registry;
    if (registry == null) {
      throw StateError('CommandScope built before dependencies were resolved.');
    }
    return CommandRegistryScope(
      registry: registry,
      child: _CommandScopeSemantics(
        registry: registry,
        buildContext: context,
        label: widget.label,
        child: KeyBindings(bindings: _bindings(registry), child: widget.child),
      ),
    );
  }
}

final class _CommandScopeSemantics extends ProxyWidget {
  const _CommandScopeSemantics({
    required this.registry,
    required this.buildContext,
    required this.label,
    required super.child,
  });

  final CommandRegistry registry;
  final BuildContext buildContext;
  final String label;

  @override
  _CommandScopeSemanticsElement createElement() {
    return _CommandScopeSemanticsElement(this);
  }
}

final class _CommandScopeSemanticsElement extends ComponentElement
    implements SemanticContributor, SemanticActionContributor {
  _CommandScopeSemanticsElement(_CommandScopeSemantics super.widget);

  @override
  _CommandScopeSemantics get widget => super.widget as _CommandScopeSemantics;

  @override
  void update(covariant _CommandScopeSemantics newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  Widget buildChild() => widget.child;

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    final commandNodes = <SemanticNode>[];
    final context = _CommandInvocationContext(
      commands: widget.registry,
      buildContext: widget.buildContext,
    );
    for (final command in widget.registry.localCommands) {
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
          id: SemanticNodeId('command:${command.id.value}'),
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
    return SemanticNode(
      id: SemanticNodeId('command-scope:$hashCode'),
      role: SemanticRole.region,
      label: widget.label,
      children: <SemanticNode>[...commandNodes, ...children],
      state: SemanticState({'commandCount': commandNodes.length}),
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
    for (final command in widget.registry.localCommands) {
      if (command.id.value != commandId) continue;
      if (action != SemanticAction.activate &&
          command.semanticAction != action) {
        return false;
      }
      await widget.registry.invokeCommand(
        command,
        buildContext: widget.buildContext,
      );
      return true;
    }
    return false;
  }
}
