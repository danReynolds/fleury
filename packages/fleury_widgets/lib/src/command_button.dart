import 'dart:async' show unawaited;

import 'package:fleury/fleury_core.dart';

import 'controls.dart';

/// A [Button] backed by an [AppCommand] in the active command registry.
///
/// The command supplies the default label, enabled state, and action. This
/// keeps a dedicated button consistent with command palettes, shortcuts,
/// semantics, and programmatic invocation without repeating command policy.
///
/// The button must be below the [CommandScope] or app that registers [command].
/// Missing commands throw a [StateError] during build. A registered command
/// whose visibility predicate is false omits the button from the tree, just as
/// it is omitted from shortcuts, semantics, and palettes.
class CommandButton extends StatelessWidget {
  const CommandButton({
    super.key,
    required this.command,
    this.label,
    this.variant = ButtonVariant.normal,
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// ID of the active command this button presents.
  final CommandId command;

  /// Optional visual label. Defaults to the command's title.
  final String? label;

  /// Accent applied to the underlying button.
  final ButtonVariant variant;

  /// Focus node for the underlying button.
  final FocusNode? focusNode;

  /// Whether the underlying button requests focus when mounted.
  final bool autofocus;

  /// Base styling for the underlying button.
  final CellStyle? style;

  @override
  Widget build(BuildContext context) {
    final registry = CommandRegistryScope.maybeOf(context);
    if (registry == null) {
      throw StateError(
        'CommandButton($command) requires an active CommandRegistryScope. '
        'Place it below FleuryApp or CommandScope.',
      );
    }

    final resolved = registry.command(command, buildContext: context);
    if (resolved == null) {
      if (_isDeclared(registry, command)) return const EmptyBox();
      throw StateError(
        'CommandButton could not find command "$command" in the '
        'active CommandRegistry. Register it in an ancestor CommandScope.',
      );
    }

    final enabled = registry.isEnabled(resolved, buildContext: context);
    return Button(
      label: label ?? resolved.title,
      variant: variant,
      focusNode: focusNode,
      autofocus: autofocus,
      style: style,
      onPressed: enabled
          ? () {
              unawaited(registry.invoke(command, buildContext: context));
            }
          : null,
    );
  }
}

bool _isDeclared(CommandRegistry registry, CommandId id) {
  CommandRegistry? current = registry;
  while (current != null) {
    if (current.localCommands.any((command) => command.id == id)) return true;
    current = current.parent;
  }
  return false;
}
