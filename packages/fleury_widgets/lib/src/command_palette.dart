import 'dart:async' show unawaited;

import 'package:fleury/fleury.dart';

/// One entry in a [CommandPalette].
class Command {
  const Command({
    required this.label,
    required this.onInvoke,
    this.id,
    this.description,
    this.category,
    this.shortcut,
    this.enabled = true,
  });

  /// Stable command ID used by semantics and registry-backed palettes.
  final String? id;

  /// Text shown (and matched against the query).
  final String label;

  /// Optional secondary text shown after the label.
  final String? description;

  /// Optional grouping label.
  final String? category;

  /// Optional shortcut label.
  final String? shortcut;

  /// Whether this command can currently run.
  final bool enabled;

  /// Run when the command is chosen.
  final void Function() onInvoke;
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

List<_CommandEntry> _buildCommandEntries(List<Command> commands) {
  return [
    for (final command in commands)
      _CommandEntry(command: command, searchFields: _searchFields(command)),
  ];
}

List<_CommandEntry> _match(List<_CommandEntry> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  final exact = <_CommandEntry>[];
  final prefix = <_CommandEntry>[];
  final contains = <_CommandEntry>[];
  final fuzzy = <_CommandEntry>[];
  for (final entry in all) {
    switch (_matchRank(entry, q)) {
      case 0:
        exact.add(entry);
      case 1:
        prefix.add(entry);
      case 2:
        contains.add(entry);
      case 3:
        fuzzy.add(entry);
      case null:
        break;
    }
  }
  return <_CommandEntry>[...exact, ...prefix, ...contains, ...fuzzy];
}

int? _matchRank(_CommandEntry entry, String query) {
  for (final field in entry.searchFields) {
    if (field == query) return 0;
  }
  for (final field in entry.searchFields) {
    if (field.startsWith(query)) return 1;
  }
  if (entry.searchText.contains(query)) return 2;
  if (_isSubsequence(query, entry.searchText)) return 3;
  return null;
}

List<String> _searchFields(Command command) {
  return [
    if (command.id != null) command.id!.toLowerCase(),
    command.label,
    if (command.description != null) command.description!,
    if (command.category != null) command.category!,
    if (command.shortcut != null) command.shortcut!,
  ].map((value) => value.toLowerCase()).toList(growable: false);
}

final class _CommandEntry {
  _CommandEntry({required this.command, required this.searchFields})
    : searchText = searchFields.join(' ');

  final Command command;
  final List<String> searchFields;
  final String searchText;
}

/// A fuzzy command palette: a filter input above a live-filtered list.
/// Type to narrow (case-insensitive subsequence match), Up/Down to move,
/// Enter to run the highlighted command. It is plain modal content — show
/// it like any modal — `present` it — and it closes itself on invoke:
///
/// ```dart
/// context.present<void>(CommandPalette(commands: [
///   Command(label: 'Open File', onInvoke: openFile),
///   Command(label: 'Quit', onInvoke: quit),
/// ]));
/// ```
///
/// (Esc dismissal comes from the modal route; the palette adds nothing
/// there.) Built on core primitives — `TextInput` for the query,
/// `ListView` for the results — so there's no bespoke "show" entry point.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    this.placeholder = 'Search commands…',
    this.width = 50,
    this.maxVisible = 8,
  });

  final List<Command> commands;
  final String placeholder;
  final int width;
  final int maxVisible;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// Registry-backed command palette for [FleuryApp] and [CommandScope].
///
/// This is the app-kernel bridge over the simple callback palette: command
/// discovery, enabled state, IDs, categories, shortcuts, and invocation all
/// come from the active [CommandRegistry].
class AppCommandPalette extends StatelessWidget {
  const AppCommandPalette({
    super.key,
    this.placeholder = 'Search commands…',
    this.width = 50,
    this.maxVisible = 8,
  });

  final String placeholder;
  final int width;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final registry = CommandRegistryScope.of(context);
    return ListenableBuilder(
      animation: registry,
      builder: (context, _) {
        final commands = _activePaletteCommands(context, registry);
        return CommandPalette(
          commands: commands,
          placeholder: placeholder,
          width: width,
          maxVisible: maxVisible,
        );
      },
    );
  }
}

List<Command> _activePaletteCommands(
  BuildContext context,
  CommandRegistry registry,
) {
  final commands = <Command>[];
  final seen = <CommandId>{};

  void add(AppCommand command) {
    if (seen.contains(command.id)) return;
    if (!registry.isVisible(command, buildContext: context)) return;
    seen.add(command.id);
    commands.add(
      Command(
        id: command.id.value,
        label: command.title,
        description: command.description,
        category: command.category,
        shortcut: command.primaryShortcutLabel,
        enabled: registry.isEnabled(command, buildContext: context),
        onInvoke: () {
          unawaited(registry.invokeCommand(command, buildContext: context));
        },
      ),
    );
  }

  final app = FleuryApp.maybeOf(context);
  if (app != null && app.screens.hasScreens) {
    for (final command in app.screens.activeScreen.commands) {
      add(command);
    }
  }
  for (final command in registry.activeCommands(buildContext: context)) {
    add(command);
  }

  return commands;
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode(debugLabel: 'command-palette-query');
  final _list = ListController(selectedIndex: 0);
  late List<_CommandEntry> _entries = _buildCommandEntries(widget.commands);
  late List<_CommandEntry> _filtered = _entries;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
  }

  @override
  void didUpdateWidget(covariant CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commands != oldWidget.commands) {
      _entries = _buildCommandEntries(widget.commands);
      _filtered = _match(_entries, _query.text);
      _list.selectedIndex = _filtered.isEmpty ? null : 0;
    }
  }

  void _onQuery() {
    setState(() {
      _filtered = _match(_entries, _query.text);
      _list.selectedIndex = _filtered.isEmpty ? null : 0;
    });
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    final current = _list.selectedIndex ?? 0;
    setState(() {
      _list.selectedIndex = (current + delta).clamp(0, _filtered.length - 1);
    });
  }

  void _invoke() {
    final i = _list.selectedIndex;
    if (i == null || i < 0 || i >= _filtered.length) return;
    _invokeCommand(_filtered[i].command);
  }

  void _invokeCommand(Command command) {
    if (!command.enabled) return;
    Navigator.maybeOf(context)?.pop();
    command.onInvoke();
  }

  void _dismiss() {
    Navigator.maybeOf(context)?.pop();
  }

  @override
  void dispose() {
    _query.removeListener(_onQuery);
    _query.dispose();
    _queryFocus.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleRange = _list.visibleRange;
    final visible = _filtered.isEmpty
        ? 1
        : (_visibleCountFor(_filtered.length, widget.maxVisible));
    final visibleRangeStart = visibleRange?.first ?? 0;
    final visibleRangeEnd = visibleRange?.last ?? (visible - 1);
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.key(KeyCode.arrowUp),
          onEvent: (_) {
            _move(-1);
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.key(KeyCode.arrowDown),
          onEvent: (_) {
            _move(1);
          },
          hideFromHintBar: true,
        ),
      ],
      // The palette owns its own frame — present() supplies no chrome.
      child: Semantics(
        role: SemanticRole.commandPalette,
        label: 'Command palette',
        value: _query.text,
        focused: _queryFocus.hasFocus,
        actions: const <SemanticAction>{
          SemanticAction.focus,
          SemanticAction.submit,
          SemanticAction.dismiss,
        },
        onAction: (action) {
          if (action == SemanticAction.focus) {
            _queryFocus.requestFocus();
          } else if (action == SemanticAction.submit) {
            _invoke();
          } else if (action == SemanticAction.dismiss) {
            _dismiss();
          }
        },
        state: SemanticState({
          'filterText': _query.text,
          'collectionRowCount': _filtered.length,
          if (_list.selectedIndex != null) 'selectedKey': _list.selectedIndex,
          'visibleRangeStart': visibleRangeStart,
          'visibleRangeEnd': visibleRangeEnd,
        }),
        child: Container(
          border: BoxBorder(style: theme.borderStyle),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextInput(
                  controller: _query,
                  focusNode: _queryFocus,
                  placeholder: widget.placeholder,
                  autofocus: true,
                  onSubmit: (_) => _invoke(),
                ),
                const SizedBox(height: 1),
                SizedBox(
                  height: visible,
                  child: _filtered.isEmpty
                      ? Text(
                          _query.text.isEmpty
                              ? widget.placeholder
                              : 'No matching commands',
                        )
                      : ListView.builder(
                          controller: _list,
                          itemCount: _filtered.length,
                          itemBuilder: (context, index, selected) =>
                              _CommandRow(
                                command: _filtered[index].command,
                                index: index,
                                selected: selected,
                                onActivate: _invokeCommand,
                              ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _visibleCountFor(int itemCount, int maxVisible) {
  if (itemCount <= 0) return 1;
  return itemCount > maxVisible ? maxVisible : itemCount;
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.index,
    required this.selected,
    required this.onActivate,
  });

  final Command command;
  final int index;
  final bool selected;
  final void Function(Command command) onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = command.description;
    final shortcut = command.shortcut;
    final category = command.category;
    final meta = <String>[];
    if (shortcut != null) {
      meta.add(shortcut);
    }
    if (category != null) {
      meta.add(category);
    }
    if (desc != null) {
      meta.add(desc);
    }
    final label = meta.isEmpty
        ? command.label
        : '${command.label}  ${meta.join('  ')}';
    final state = <String, Object?>{
      'commandId': command.id ?? command.label,
      'rowIndex': index,
    };
    if (shortcut != null) {
      state['shortcut'] = shortcut;
    }
    if (category != null) {
      state['commandCategory'] = category;
    }
    return Semantics(
      role: SemanticRole.command,
      label: command.label,
      value: desc,
      hint: desc,
      enabled: command.enabled,
      selected: selected,
      actions: const <SemanticAction>{SemanticAction.activate},
      onAction: (action) {
        if (action == SemanticAction.activate) {
          onActivate(command);
        }
      },
      state: SemanticState(state),
      child: Text(
        '${selected ? '› ' : '  '}$label',
        style: _commandStyle(
          theme,
          selected: selected,
          enabled: command.enabled,
        ),
      ),
    );
  }
}

CellStyle _commandStyle(
  ThemeData theme, {
  required bool selected,
  required bool enabled,
}) {
  final style = selected ? theme.selectionStyle : CellStyle.empty;
  return enabled ? style : style.merge(const CellStyle(dim: true));
}
