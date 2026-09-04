import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:fleury/fleury_core.dart';

/// One callback-backed row in a fixed-list [CommandPalette].
///
/// This type is only for palettes that own a static list of callbacks. For
/// application actions shared by buttons, shortcuts, semantics, and command
/// palettes, register [AppCommand]s and open a registry-backed palette with
/// [CommandPalette.open].
class CommandPaletteItem {
  const CommandPaletteItem({
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

/// Deprecated source-compatible name for [CommandPaletteItem].
@Deprecated('Use CommandPaletteItem instead.')
typedef Command = CommandPaletteItem;

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

List<_CommandEntry> _buildCommandEntries(List<CommandPaletteItem> commands) {
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

List<String> _searchFields(CommandPaletteItem command) {
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

  final CommandPaletteItem command;
  final List<String> searchFields;
  final String searchText;
}

/// A fuzzy command palette.
///
/// When [commands] is provided, the palette is a fixed-list UI over callback
/// commands:
///
/// ```dart
/// context.present<void>(CommandPalette(commands: [
///   CommandPaletteItem(label: 'Open File', onInvoke: openFile),
///   CommandPaletteItem(label: 'Quit', onInvoke: quit),
/// ]));
/// ```
///
/// Without [commands], the palette reads the active [CommandRegistry] and
/// surfaces [AppCommand]s from the source command scope:
///
/// ```dart
/// CommandPalette.open(context);
/// ```
///
/// Apps that want a keyboard shortcut for the palette should register a normal
/// [AppCommand] that calls [CommandPalette.open] with its command context and
/// sets [AppCommand.showInPalette] to false so the opener does not list itself.
///
/// Type to narrow (case-insensitive subsequence match), Up/Down to move, and
/// Enter to run the highlighted command. Esc dismissal comes from the modal
/// route; the palette adds nothing there.
class CommandPalette extends StatelessWidget {
  const CommandPalette({
    super.key,
    this.commands,
    this.sourceRegistry,
    this.sourceContext,
    this.placeholder = 'Search commands…',
    this.width = 50,
    this.maxVisible = 8,
  }) : assert(
         commands == null || (sourceRegistry == null && sourceContext == null),
         'sourceRegistry/sourceContext are only used by registry-backed '
         'palettes. Omit commands to use the active command registry.',
       );

  /// Fixed callback commands to show.
  ///
  /// When null, the palette uses the active [CommandRegistry] instead.
  final List<CommandPaletteItem>? commands;

  /// Registry to inspect for command rows.
  ///
  /// This is normally supplied by [open] so a palette rendered in an overlay
  /// can still surface commands from the widget tree that opened it.
  final CommandRegistry? sourceRegistry;

  /// Context used for command visibility, enabled state, and invocation.
  ///
  /// This is intentionally separate from the palette's overlay context. The
  /// overlay is only where the palette renders; [sourceContext] is where the
  /// user was acting when the palette opened.
  final BuildContext? sourceContext;

  /// Hint shown in the palette's search field while it is empty.
  final String placeholder;

  /// Total palette width in terminal cells.
  final int width;

  /// Maximum number of matching command rows shown before scrolling.
  final int maxVisible;

  /// Opens a registry-backed command palette for the active source context.
  ///
  /// The source context defaults to the currently focused widget, falling back
  /// to [context]. This lets a global "Open Command Palette" command discover
  /// scoped commands owned by the active tab, sidebar, editor, or table while
  /// still presenting the palette through a navigator.
  static Future<void> open(
    BuildContext context, {
    bool rootNavigator = false,
    Alignment alignment = Alignment.center,
    RouteTransition? transition,
    String placeholder = 'Search commands…',
    int width = 50,
    int maxVisible = 8,
  }) async {
    final sourceContext = _defaultCommandSourceContext(context);
    final sourceRegistry = CommandRegistryScope.of(sourceContext);
    final navigator =
        Navigator.maybeOf(sourceContext, rootNavigator: rootNavigator) ??
        Navigator.maybeOf(context, rootNavigator: rootNavigator) ??
        Navigator.of(sourceContext, rootNavigator: true);
    await navigator.present<void>(
      CommandPalette(
        sourceRegistry: sourceRegistry,
        sourceContext: sourceContext,
        placeholder: placeholder,
        width: width,
        maxVisible: maxVisible,
      ),
      alignment: alignment,
      transition: transition,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fixedCommands = commands;
    if (fixedCommands != null) {
      return _CommandPaletteView(
        commands: fixedCommands,
        placeholder: placeholder,
        width: width,
        maxVisible: maxVisible,
      );
    }

    final resolvedSourceContext = _resolvedCommandSourceContext(
      context,
      sourceContext: sourceContext,
    );
    final registry = _resolvedCommandRegistry(
      context: resolvedSourceContext,
      sourceRegistry: sourceRegistry,
      sourceContext: sourceContext,
    );
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final activeSourceContext = _resolvedCommandSourceContext(
          context,
          sourceContext: sourceContext,
        );
        final activeRegistry = _resolvedCommandRegistry(
          context: activeSourceContext,
          sourceRegistry: sourceRegistry,
          sourceContext: sourceContext,
        );
        final commands = _activePaletteCommands(
          activeSourceContext,
          activeRegistry,
        );
        return _CommandPaletteView(
          commands: commands,
          placeholder: placeholder,
          width: width,
          maxVisible: maxVisible,
        );
      },
    );
  }
}

BuildContext _defaultCommandSourceContext(BuildContext context) {
  final focused = Focus.maybeOf(context)?.focusedNode?.context;
  if (focused != null &&
      focused.mounted &&
      CommandRegistryScope.maybeOf(focused) != null) {
    return focused;
  }
  return context;
}

BuildContext _resolvedCommandSourceContext(
  BuildContext overlayContext, {
  BuildContext? sourceContext,
}) {
  final source = sourceContext;
  if (source == null || !source.mounted) return overlayContext;
  return source;
}

CommandRegistry _resolvedCommandRegistry({
  required BuildContext context,
  required CommandRegistry? sourceRegistry,
  required BuildContext? sourceContext,
}) {
  if (sourceRegistry != null &&
      (sourceContext == null || sourceContext.mounted)) {
    return sourceRegistry;
  }
  return CommandRegistryScope.of(context);
}

List<CommandPaletteItem> _activePaletteCommands(
  BuildContext context,
  CommandRegistry registry,
) {
  final commands = <CommandPaletteItem>[];
  final seen = <CommandId>{};

  void add(AppCommand command) {
    if (seen.contains(command.id)) return;
    if (!registry.isVisible(command, buildContext: context)) return;
    if (!command.showInPalette) return;
    seen.add(command.id);
    commands.add(
      CommandPaletteItem(
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

  for (final command in registry.activeCommands(buildContext: context)) {
    add(command);
  }

  return commands;
}

class _CommandPaletteView extends StatefulWidget {
  const _CommandPaletteView({
    required this.commands,
    required this.placeholder,
    required this.width,
    required this.maxVisible,
  });

  final List<CommandPaletteItem> commands;
  final String placeholder;
  final int width;
  final int maxVisible;

  @override
  State<_CommandPaletteView> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPaletteView> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode(debugLabel: 'command-palette-query');
  final _list = ListController(selectedIndex: 0);
  late List<_CommandEntry> _entries = _buildCommandEntries(widget.commands);
  late List<_CommandEntry> _filtered = _entries;
  int? _pendingSelectedIndex;
  int _selectionRefreshGeneration = 0;

  int? get _selectedIndex => _pendingSelectedIndex ?? _list.selectedIndex;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
  }

  @override
  void didUpdateWidget(covariant _CommandPaletteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commands != oldWidget.commands) {
      final previousIndex = _selectedIndex;
      final selectedId =
          previousIndex != null &&
              previousIndex >= 0 &&
              previousIndex < _filtered.length
          ? _filtered[previousIndex].command.id
          : null;
      _entries = _buildCommandEntries(widget.commands);
      _filtered = _match(_entries, _query.text);
      _syncSelectionAfterRefresh(
        _selectionAfterRefresh(
          _filtered,
          selectedId: selectedId,
          previousIndex: previousIndex,
        ),
      );
    }
  }

  void _syncSelectionAfterRefresh(int? nextIndex) {
    final generation = ++_selectionRefreshGeneration;
    _pendingSelectedIndex = null;
    final knownItemCount = _list.itemCount;
    if (nextIndex == null ||
        knownItemCount == 0 ||
        nextIndex < knownItemCount) {
      _list.selectedIndex = nextIndex;
      return;
    }

    // ListController clamps writes against the row count from the currently
    // mounted ListView. When a refresh inserts rows before the selection, the
    // selected command can move beyond that old count. Keep the intended
    // index for this build, then commit it once ListView has received the new
    // count at the end of the frame.
    _pendingSelectedIndex = nextIndex;
    void applyPendingSelection() {
      if (!mounted || generation != _selectionRefreshGeneration) return;
      final pending = _pendingSelectedIndex;
      if (pending == null) return;
      setState(() {
        _pendingSelectedIndex = null;
        _list.selectedIndex = pending;
      });
    }

    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(applyPendingSelection);
    } else {
      binding.addPostFrameCallback((_) => applyPendingSelection());
    }
  }

  void _onQuery() {
    setState(() {
      _selectionRefreshGeneration++;
      _pendingSelectedIndex = null;
      _filtered = _match(_entries, _query.text);
      _list.selectedIndex = _filtered.isEmpty ? null : 0;
    });
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    final current = _selectedIndex ?? 0;
    final n = _filtered.length;
    setState(() {
      _selectionRefreshGeneration++;
      _pendingSelectedIndex = null;
      // Wrap top↔bottom like fzf / VS Code / Textual — after filtering the
      // list is short, so cycling beats stopping dead at an end.
      _list.selectedIndex = ((current + delta) % n + n) % n;
    });
  }

  void _invoke() {
    final i = _selectedIndex;
    if (i == null || i < 0 || i >= _filtered.length) return;
    _invokeCommand(_filtered[i].command);
  }

  void _invokeCommand(CommandPaletteItem command) {
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
    // Show the selected command's description in a footer rather than on its
    // row. Only reserve the footer when some command actually has one, so a
    // plain callback palette (file menu, etc.) stays as compact as before.
    final hasDescriptions = _entries.any(
      (entry) => entry.command.description != null,
    );
    final selIndex = _selectedIndex;
    final selectedDescription =
        (selIndex != null && selIndex >= 0 && selIndex < _filtered.length)
        ? _filtered[selIndex].command.description
        : null;
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.arrowUp,
          onTrigger: (_) {
            _move(-1);
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyCode.arrowDown,
          onTrigger: (_) {
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
          'selectedKey': ?selIndex,
          'visibleRangeStart': visibleRangeStart,
          'visibleRangeEnd': visibleRangeEnd,
        }),
        // Container.framed makes the floating palette opaque the same way
        // every other stock overlay does, so interior lines don't have to be
        // hand-padded to full width to keep the content beneath from bleeding
        // through. (Rows still pad via `_fitWidth` — that spans the selection
        // highlight, which is a look, not an opacity trick.) Height is bound
        // to the content so the box doesn't stretch to fill the viewport the
        // centering Align hands it. SelectionArea.disabled says the command
        // list is chrome: the palette is often presented inline (a Stack over
        // the app), where it DOES inherit the root selection scope.
        child: SelectionArea.disabled(
          child: Container.framed(
            border: BoxBorder(style: theme.borderStyle),
            child: SizedBox(
              width: widget.width,
              height: visible + 2 + (hasDescriptions ? 2 : 0),
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
                            style: theme.mutedStyle,
                          )
                        : ListView.builder(
                            controller: _list,
                            selectionActive: true,
                            itemCount: _filtered.length,
                            itemBuilder: (context, index, _) => _CommandRow(
                              command: _filtered[index].command,
                              index: index,
                              selected: index == selIndex,
                              width: widget.width,
                              onActivate: _invokeCommand,
                            ),
                          ),
                  ),
                  if (hasDescriptions) ...[
                    const SizedBox(height: 1),
                    SizedBox(
                      height: 1,
                      child: Text(
                        _fitWidth(selectedDescription ?? '', widget.width),
                        style: theme.mutedStyle,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int? _selectionAfterRefresh(
  List<_CommandEntry> entries, {
  required String? selectedId,
  required int? previousIndex,
}) {
  if (entries.isEmpty) return null;

  if (selectedId != null) {
    final matchingIndex = entries.indexWhere(
      (entry) => entry.command.id == selectedId,
    );
    if (matchingIndex >= 0) return matchingIndex;
  }

  if (previousIndex == null || previousIndex < 0) return 0;
  if (previousIndex >= entries.length) return entries.length - 1;
  return previousIndex;
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
    required this.width,
    required this.onActivate,
  });

  final CommandPaletteItem command;
  final int index;
  final bool selected;

  /// Total row width in cells. The label region is padded to fill it (less the
  /// shortcut) so every cell is written — which is what keeps the floating
  /// palette opaque over the content beneath it (a `Text` only paints the
  /// cells it occupies, and the theme background is "terminal default").
  final int width;
  final void Function(CommandPaletteItem command) onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = command.description;
    final shortcut = command.shortcut;
    final category = command.category;
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
    final labelStyle = _commandStyle(
      theme,
      selected: selected,
      enabled: command.enabled,
    );
    // The shortcut is a trailing, right-aligned key hint (VS Code / fzf style),
    // not inline text — so the row reads as "command … keys" instead of one
    // run-on string. Category and description stay off the row on purpose:
    // repeating the category on every line is noise, and a wrapping description
    // is exactly what made the list look like one text block. The description
    // surfaces once, for the selected row, in the palette footer.
    final shortcutStyle = selected
        ? theme.selectionStyle
        : (command.enabled
              ? theme.mutedStyle
              : theme.mutedStyle.merge(const CellStyle(dim: true)));
    final labelRegion = (width - (shortcut?.length ?? 0)).clamp(0, width);
    final labelText = _fitWidth(
      '${selected ? '› ' : '  '}${command.label}',
      labelRegion,
    );
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
      // Click an enabled command to run it (same as Enter on the selection).
      child: GestureDetector(
        onTap: command.enabled ? () => onActivate(command) : null,
        child: Row(
          children: <Widget>[
            Text(labelText, style: labelStyle, maxLines: 1),
            if (shortcut != null)
              Text(shortcut, style: shortcutStyle, maxLines: 1),
          ],
        ),
      ),
    );
  }
}

/// Truncates [text] to [width] cells (with an ellipsis) or pads it with spaces
/// to exactly [width], so the returned string fills its row — writing every
/// cell keeps the floating palette opaque in any theme. Command labels are
/// short ASCII, so a code-unit measure matches display width here.
String _fitWidth(String text, int width) {
  if (width <= 0) return '';
  if (text.length > width) {
    return width == 1 ? '…' : '${text.substring(0, width - 1)}…';
  }
  return text.padRight(width);
}

CellStyle _commandStyle(
  ThemeData theme, {
  required bool selected,
  required bool enabled,
}) {
  final style = selected ? theme.selectionStyle : CellStyle.none;
  return enabled ? style : style.merge(const CellStyle(dim: true));
}
