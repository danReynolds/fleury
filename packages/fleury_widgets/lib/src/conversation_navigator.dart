import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury.dart';

/// Protocol-neutral lifecycle for a conversation/session row.
enum ConversationStatus {
  active,
  idle,
  waiting,
  streaming,
  complete,
  failed,
  archived,
}

/// One conversation, thread, or session exposed by [ConversationNavigator].
final class ConversationEntry {
  const ConversationEntry({
    required this.id,
    required this.title,
    this.subtitle,
    this.status = ConversationStatus.idle,
    this.latestMessage,
    this.author,
    this.timestamp,
    this.unreadCount = 0,
    this.messageCount = 0,
    this.pinned = false,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
  }) : assert(unreadCount >= 0),
       assert(messageCount >= 0);

  /// Stable identity used by semantics, selection, and callbacks.
  final Object id;

  final String title;
  final String? subtitle;
  final ConversationStatus status;
  final String? latestMessage;
  final String? author;
  final DateTime? timestamp;
  final int unreadCount;
  final int messageCount;
  final bool pinned;
  final bool enabled;
  final Map<String, Object?> metadata;

  String get displayId => id.toString();
}

/// Predicate used by [buildConversationOrder].
typedef ConversationMatcher =
    bool Function(ConversationEntry entry, String query);

/// Controller for [ConversationNavigator] selection and viewport state.
class ConversationNavigatorController extends ChangeNotifier {
  ConversationNavigatorController({int selectedIndex = 0})
    : _list = ListController(selectedIndex: selectedIndex) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ConversationNavigatorController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _list.removeListener(notifyListeners);
    _list.dispose();
    super.dispose();
  }
}

/// Clipboard/export behavior for [ConversationNavigator] selected-row copy.
final class ConversationNavigatorCopyOptions {
  const ConversationNavigatorCopyOptions({
    this.includeStatus = true,
    this.includeLatestMessage = true,
    this.maxLatestLength = 1000,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  }) : assert(maxLatestLength == null || maxLatestLength >= 0);

  final bool includeStatus;
  final bool includeLatestMessage;
  final int? maxLatestLength;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [ConversationNavigator] copies the selected row.
final class ConversationNavigatorCopyResult {
  const ConversationNavigatorCopyResult({
    required this.entryIndex,
    required this.viewIndex,
    required this.entry,
    required this.text,
    required this.report,
  });

  final int entryIndex;
  final int viewIndex;
  final ConversationEntry entry;
  final String text;
  final ClipboardWriteReport report;
}

/// Result delivered after [ConversationNavigator] activates a row.
final class ConversationNavigatorSelectResult {
  const ConversationNavigatorSelectResult({
    required this.entryIndex,
    required this.viewIndex,
    required this.entry,
  });

  final int entryIndex;
  final int viewIndex;
  final ConversationEntry entry;
}

/// Returns source entry indexes in display order after applying [query].
List<int> buildConversationOrder(
  List<ConversationEntry> entries, {
  String query = '',
  ConversationMatcher? matcher,
}) {
  final trimmed = _sanitizeConversationText(query).trim();
  if (trimmed.isEmpty) {
    return List<int>.unmodifiable(
      List<int>.generate(entries.length, (index) => index),
    );
  }
  if (matcher != null) {
    return List<int>.unmodifiable([
      for (var index = 0; index < entries.length; index++)
        if (matcher(entries[index], trimmed)) index,
    ]);
  }

  final q = trimmed.toLowerCase();
  final exact = <int>[];
  final prefix = <int>[];
  final contains = <int>[];
  final fuzzy = <int>[];
  for (var index = 0; index < entries.length; index++) {
    switch (_conversationRank(entries[index], q)) {
      case _ConversationRank.exact:
        exact.add(index);
      case _ConversationRank.prefix:
        prefix.add(index);
      case _ConversationRank.contains:
        contains.add(index);
      case _ConversationRank.fuzzy:
        fuzzy.add(index);
      case null:
        break;
    }
  }
  return List<int>.unmodifiable([...exact, ...prefix, ...contains, ...fuzzy]);
}

/// Exports one [ConversationEntry] as sanitized clipboard/debug text.
String exportConversation(
  ConversationEntry entry, {
  ConversationNavigatorCopyOptions options =
      const ConversationNavigatorCopyOptions(),
}) {
  final parts = <String>[
    _sanitizeConversationText(entry.title),
    if (options.includeStatus) entry.status.name,
    if (entry.unreadCount > 0) '${entry.unreadCount} unread',
    if (entry.messageCount > 0) '${entry.messageCount} messages',
    if (entry.pinned) 'pinned',
    if (options.includeLatestMessage && entry.latestMessage != null)
      _truncateGraphemes(
        _sanitizeConversationText(entry.latestMessage!),
        options.maxLatestLength,
      ),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' | ');
}

/// Queryable conversation/session list for agent and developer-tool surfaces.
class ConversationNavigator extends StatefulWidget {
  const ConversationNavigator({
    super.key,
    required this.conversations,
    this.queryController,
    this.controller,
    this.matcher,
    this.label = 'Conversations',
    this.placeholder = 'Search conversations...',
    this.width = 60,
    this.maxVisible = 6,
    this.queryFocusNode,
    this.listFocusNode,
    this.autofocus = false,
    this.copySelection = true,
    this.copyOptions = const ConversationNavigatorCopyOptions(),
    this.onSelect,
    this.onCopy,
  }) : assert(width > 0),
       assert(maxVisible > 0);

  final List<ConversationEntry> conversations;
  final TextEditingController? queryController;
  final ConversationNavigatorController? controller;
  final ConversationMatcher? matcher;
  final String label;
  final String placeholder;
  final int width;
  final int maxVisible;
  final FocusNode? queryFocusNode;
  final FocusNode? listFocusNode;
  final bool autofocus;
  final bool copySelection;
  final ConversationNavigatorCopyOptions copyOptions;
  final void Function(ConversationNavigatorSelectResult result)? onSelect;
  final void Function(ConversationNavigatorCopyResult result)? onCopy;

  @override
  State<ConversationNavigator> createState() => _ConversationNavigatorState();
}

class _ConversationNavigatorState extends State<ConversationNavigator> {
  late TextEditingController _query;
  late ConversationNavigatorController _controller;
  late FocusNode _queryFocusNode;
  late FocusNode _listFocusNode;
  bool _ownsQuery = false;
  bool _ownsController = false;
  bool _ownsQueryFocusNode = false;
  bool _ownsListFocusNode = false;
  FocusManager? _focusManager;
  Object? _pendingSelectedConversationId;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.queryController ?? TextEditingController();
    _ownsQuery = widget.queryController == null;
    _query.addListener(_onQueryChange);
    _controller = widget.controller ?? ConversationNavigatorController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _queryFocusNode =
        widget.queryFocusNode ??
        FocusNode(debugLabel: 'ConversationNavigator query');
    _ownsQueryFocusNode = widget.queryFocusNode == null;
    _listFocusNode =
        widget.listFocusNode ??
        FocusNode(debugLabel: 'ConversationNavigator list');
    _ownsListFocusNode = widget.listFocusNode == null;
    _resetSelection(_currentOrder, preserveCurrent: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context);
    if (identical(manager, _focusManager)) return;
    _focusManager?.removeListener(_onFocusChange);
    _focusManager = manager;
    _focusManager?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant ConversationNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queryController != oldWidget.queryController) {
      _query.removeListener(_onQueryChange);
      if (_ownsQuery) _query.dispose();
      _query = widget.queryController ?? TextEditingController();
      _ownsQuery = widget.queryController == null;
      _query.addListener(_onQueryChange);
    }
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? ConversationNavigatorController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.queryFocusNode != oldWidget.queryFocusNode) {
      if (_ownsQueryFocusNode) _queryFocusNode.dispose();
      _queryFocusNode =
          widget.queryFocusNode ??
          FocusNode(debugLabel: 'ConversationNavigator query');
      _ownsQueryFocusNode = widget.queryFocusNode == null;
    }
    if (widget.listFocusNode != oldWidget.listFocusNode) {
      if (_ownsListFocusNode) _listFocusNode.dispose();
      _listFocusNode =
          widget.listFocusNode ??
          FocusNode(debugLabel: 'ConversationNavigator list');
      _ownsListFocusNode = widget.listFocusNode == null;
    }
    if (widget.controller != oldWidget.controller) {
      _resetSelection(_currentOrder, preserveCurrent: true);
    } else if (widget.conversations != oldWidget.conversations ||
        widget.matcher != oldWidget.matcher) {
      final oldOrder = buildConversationOrder(
        oldWidget.conversations,
        query: _query.text,
        matcher: oldWidget.matcher,
      );
      _syncSelectionAfterOrderUpdate(oldOrder, oldWidget.conversations);
    }
  }

  List<int> get _currentOrder => buildConversationOrder(
    widget.conversations,
    query: _query.text,
    matcher: widget.matcher,
  );

  void _onQueryChange() {
    final previous = _controller.selectedIndex;
    _resetSelection(_currentOrder);
    if (_controller.selectedIndex == previous) setState(() {});
  }

  void _onControllerChange() => setState(() {});

  void _onFocusChange() => setState(() {});

  void _resetSelection(List<int> order, {bool preserveCurrent = false}) {
    _selectionSyncGeneration++;
    _pendingSelectedConversationId = null;
    if (order.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (preserveCurrent && selectedIndex != null) {
      _controller.selectedIndex = selectedIndex.clamp(0, order.length - 1);
      return;
    }
    _controller.selectedIndex = 0;
  }

  void _syncSelectionAfterOrderUpdate(
    List<int> oldOrder,
    List<ConversationEntry> oldEntries,
  ) {
    _selectionSyncGeneration++;
    _pendingSelectedConversationId = null;
    final order = _currentOrder;
    if (order.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) {
      _controller.selectedIndex = 0;
      return;
    }
    if (selectedIndex >= 0 && selectedIndex < oldOrder.length) {
      final selectedId = oldEntries[oldOrder[selectedIndex]].id;
      final nextIndex = order.indexWhere(
        (entryIndex) => widget.conversations[entryIndex].id == selectedId,
      );
      if (nextIndex != -1) {
        _selectIndexAfterListCountRefresh(selectedId, nextIndex);
        return;
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(0, order.length - 1);
  }

  void _selectIndexAfterListCountRefresh(Object selectedId, int nextIndex) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedConversationId = selectedId;
    final generation = _selectionSyncGeneration;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyPendingSelection(generation, selectedId);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyPendingSelection(generation, selectedId);
    });
  }

  void _applyPendingSelection(int generation, Object selectedId) {
    if (!mounted || generation != _selectionSyncGeneration) return;
    if (_pendingSelectedConversationId != selectedId) return;
    final order = _currentOrder;
    final nextIndex = order.indexWhere(
      (entryIndex) => widget.conversations[entryIndex].id == selectedId,
    );
    if (nextIndex == -1) {
      _pendingSelectedConversationId = null;
      return;
    }
    _pendingSelectedConversationId = null;
    _controller.selectedIndex = nextIndex;
  }

  void _focusQuery() {
    _queryFocusNode.requestFocus();
    setState(() {});
  }

  void _focusListOrQuery() {
    if (_currentOrder.isEmpty) {
      _focusQuery();
      return;
    }
    _listFocusNode.requestFocus();
    setState(() {});
  }

  void _move(int delta) {
    final order = _currentOrder;
    if (order.isEmpty) return;
    final current = _controller.selectedIndex ?? 0;
    _controller.selectedIndex = (current + delta).clamp(0, order.length - 1);
  }

  _SelectedConversation? _selectedConversation(List<int> order) {
    if (order.isEmpty) return null;
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) return null;
    final viewIndex = selectedIndex.clamp(0, order.length - 1);
    final entryIndex = order[viewIndex];
    return _SelectedConversation(
      viewIndex: viewIndex,
      entryIndex: entryIndex,
      entry: widget.conversations[entryIndex],
    );
  }

  void _selectCurrent() {
    final selected = _selectedConversation(_currentOrder);
    if (selected == null || !selected.entry.enabled) return;
    widget.onSelect?.call(
      ConversationNavigatorSelectResult(
        entryIndex: selected.entryIndex,
        viewIndex: selected.viewIndex,
        entry: selected.entry,
      ),
    );
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection) return;
    final selected = _selectedConversation(_currentOrder);
    if (selected == null) return;
    final text = exportConversation(
      selected.entry,
      options: widget.copyOptions,
    );
    final report = await Clipboard.instance.writeWithReport(
      text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    widget.onCopy?.call(
      ConversationNavigatorCopyResult(
        entryIndex: selected.entryIndex,
        viewIndex: selected.viewIndex,
        entry: selected.entry,
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _handleNavigatorAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
        _focusQuery();
        return;
      case SemanticAction.navigate:
        _focusListOrQuery();
        return;
      case SemanticAction.submit:
        _selectCurrent();
        return;
      case SemanticAction.copy:
        _focusListOrQuery();
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  Future<void> _selectAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _focusListOrQuery();
    _controller.selectedIndex = viewIndex;
    _selectCurrent();
  }

  Future<void> _copyAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _focusListOrQuery();
    _controller.selectedIndex = viewIndex;
    await _copySelection();
  }

  @override
  void dispose() {
    _query.removeListener(_onQueryChange);
    if (_ownsQuery) _query.dispose();
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    _focusManager?.removeListener(_onFocusChange);
    if (_ownsQueryFocusNode) _queryFocusNode.dispose();
    if (_ownsListFocusNode) _listFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = _currentOrder;
    final visible = order.isEmpty
        ? 1
        : (order.length > widget.maxVisible ? widget.maxVisible : order.length);
    final selected = _selectedConversation(order);
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && selected != null;
    final canSelect = widget.onSelect != null;
    final panelFocused = _queryFocusNode.hasFocus || _listFocusNode.hasFocus;

    Widget panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextInput(
          controller: _query,
          focusNode: _queryFocusNode,
          placeholder: widget.placeholder,
          autofocus: widget.autofocus,
          onSubmit: (_) => _selectCurrent(),
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: visible,
          child: order.isEmpty
              ? Text(
                  _query.text.trim().isEmpty
                      ? widget.placeholder
                      : 'No matching conversations',
                )
              : ListView.builder(
                  controller: _controller._listController,
                  focusNode: _listFocusNode,
                  selectionActive: panelFocused,
                  itemCount: order.length,
                  onSelect: (_) => _selectCurrent(),
                  itemBuilder: (context, viewIndex, activeSelected) {
                    final entryIndex = order[viewIndex];
                    final selected = viewIndex == _controller.selectedIndex;
                    return _ConversationRow(
                      entry: widget.conversations[entryIndex],
                      entryIndex: entryIndex,
                      viewIndex: viewIndex,
                      selected: selected,
                      activeSelection: activeSelected,
                      canSelect: canSelect,
                      copyEnabled: copyEnabled,
                      onSelect: () => _selectAt(viewIndex),
                      onCopy: () => _copyAt(viewIndex),
                    );
                  },
                ),
        ),
      ],
    );

    panel = SizedBox(width: widget.width, child: panel);

    if (copyEnabled) {
      panel = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy conversation',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: panel,
      );
    }

    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.key(KeyCode.arrowUp),
          onEvent: (_) => _move(-1),
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.key(KeyCode.arrowDown),
          onEvent: (_) => _move(1),
          hideFromHintBar: true,
        ),
      ],
      child: Semantics(
        role: SemanticRole.conversationNavigator,
        label: widget.label,
        value: _query.text,
        focused: _queryFocusNode.hasFocus || _listFocusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (canSelect) SemanticAction.submit,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleNavigatorAction,
        state: SemanticState({
          'filterText': _query.text,
          'collectionRowCount': order.length,
          'totalConversationCount': widget.conversations.length,
          'filteredConversationCount': order.length,
          'unreadConversationCount': widget.conversations.fold<int>(
            0,
            (total, entry) => total + (entry.unreadCount > 0 ? 1 : 0),
          ),
          'pinnedConversationCount': widget.conversations.fold<int>(
            0,
            (total, entry) => total + (entry.pinned ? 1 : 0),
          ),
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null && order.isNotEmpty) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?_controller.selectedIndex,
          if (selected != null) ..._selectedConversationState(selected.entry),
        }),
        child: panel,
      ),
    );
  }
}

final class _SelectedConversation {
  const _SelectedConversation({
    required this.viewIndex,
    required this.entryIndex,
    required this.entry,
  });

  final int viewIndex;
  final int entryIndex;
  final ConversationEntry entry;
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.entry,
    required this.entryIndex,
    required this.viewIndex,
    required this.selected,
    required this.activeSelection,
    required this.canSelect,
    required this.copyEnabled,
    required this.onSelect,
    required this.onCopy,
  });

  final ConversationEntry entry;
  final int entryIndex;
  final int viewIndex;
  final bool selected;
  final bool activeSelection;
  final bool canSelect;
  final bool copyEnabled;
  final Future<void> Function() onSelect;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final title = _sanitizeConversationText(entry.title);
    final subtitle = entry.subtitle == null
        ? null
        : _sanitizeConversationText(entry.subtitle!);
    final latest = entry.latestMessage == null
        ? null
        : _sanitizeConversationText(entry.latestMessage!);
    final author = entry.author == null
        ? null
        : _sanitizeConversationText(entry.author!);
    final id = _sanitizeConversationText(entry.displayId);
    final rowText = _rowText(
      title: title,
      status: entry.status,
      unreadCount: entry.unreadCount,
      pinned: entry.pinned,
      latestMessage: latest,
      activeSelection: activeSelection,
    );

    return Semantics(
      role: SemanticRole.conversation,
      label: title,
      value: latest,
      hint: subtitle,
      selected: selected,
      enabled: entry.enabled,
      busy: entry.status == ConversationStatus.streaming,
      actions: {
        if (entry.enabled && canSelect) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            if (entry.enabled && canSelect) await onSelect();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ...entry.metadata,
        'rowIndex': entryIndex,
        'viewIndex': viewIndex,
        'rowKey': id,
        'conversationId': id,
        'conversationStatus': entry.status.name,
        'conversationUnreadCount': entry.unreadCount,
        'conversationMessageCount': entry.messageCount,
        'pinned': entry.pinned,
        'author': ?author,
        if (entry.timestamp != null)
          'timestamp': entry.timestamp!.toIso8601String(),
        'outputSanitized': _entryWasSanitized(entry),
      }),
      child: Text(
        rowText,
        style: _rowStyle(
          Theme.of(context),
          selected: selected,
          activeSelection: activeSelection,
          entry: entry,
        ),
      ),
    );
  }
}

String _rowText({
  required String title,
  required ConversationStatus status,
  required int unreadCount,
  required bool pinned,
  required String? latestMessage,
  required bool activeSelection,
}) {
  final prefix = activeSelection ? '> ' : '  ';
  final meta = <String>[
    status.name,
    if (unreadCount > 0) '$unreadCount unread',
    if (pinned) 'pinned',
  ];
  final latest = latestMessage == null || latestMessage.isEmpty
      ? ''
      : '  ${_truncateGraphemes(latestMessage, 80)}';
  return '$prefix$title  ${meta.join('  ')}$latest';
}

Map<String, Object?> _selectedConversationState(ConversationEntry entry) {
  final id = _sanitizeConversationText(entry.displayId);
  return <String, Object?>{
    'selectedKey': id,
    'selectedConversationId': id,
    'selectedConversationStatus': entry.status.name,
    'selectedConversationUnreadCount': entry.unreadCount,
  };
}

enum _ConversationRank { exact, prefix, contains, fuzzy }

_ConversationRank? _conversationRank(ConversationEntry entry, String query) {
  final fields = _conversationFields(entry);
  for (final field in fields) {
    if (field == query) return _ConversationRank.exact;
  }
  for (final field in fields) {
    if (field.startsWith(query)) return _ConversationRank.prefix;
  }
  final searchText = fields.join(' ');
  if (searchText.contains(query)) return _ConversationRank.contains;
  if (_isSubsequence(query, searchText)) return _ConversationRank.fuzzy;
  return null;
}

List<String> _conversationFields(ConversationEntry entry) {
  return [
        entry.displayId,
        entry.title,
        entry.status.name,
        if (entry.subtitle != null) entry.subtitle!,
        if (entry.latestMessage != null) entry.latestMessage!,
        if (entry.author != null) entry.author!,
        if (entry.timestamp != null) entry.timestamp!.toIso8601String(),
        if (entry.unreadCount > 0) '${entry.unreadCount} unread',
        if (entry.messageCount > 0) '${entry.messageCount} messages',
        if (entry.pinned) 'pinned',
        for (final value in entry.metadata.values)
          if (value != null) value.toString(),
      ]
      .map(_sanitizeConversationText)
      .map((value) => value.toLowerCase())
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

bool _entryWasSanitized(ConversationEntry entry) {
  return _sanitizeConversationText(entry.displayId) != entry.displayId ||
      _sanitizeConversationText(entry.title) != entry.title ||
      (entry.subtitle != null &&
          _sanitizeConversationText(entry.subtitle!) != entry.subtitle) ||
      (entry.latestMessage != null &&
          _sanitizeConversationText(entry.latestMessage!) !=
              entry.latestMessage) ||
      (entry.author != null &&
          _sanitizeConversationText(entry.author!) != entry.author);
}

String _sanitizeConversationText(String text) {
  return sanitizeForDisplay(
    text.replaceAll(_conversationLineBreakPattern, ' '),
  ).replaceAll(RegExp(' +'), ' ').trim();
}

String _truncateGraphemes(String text, int? maxLength) {
  if (maxLength == null) return text;
  if (maxLength == 0) return '';
  final characters = text.characters;
  if (characters.length <= maxLength) return text;
  return characters.take(maxLength).toString();
}

final _conversationLineBreakPattern = RegExp(r'[\r\n\t]');

CellStyle _rowStyle(
  ThemeData theme, {
  required bool selected,
  required bool activeSelection,
  required ConversationEntry entry,
}) {
  if (!entry.enabled) return theme.mutedStyle;
  if (activeSelection) return theme.selectionStyle;
  if (selected) return theme.mutedStyle;
  return switch (entry.status) {
    ConversationStatus.waiting => const CellStyle(foreground: AnsiColor(11)),
    ConversationStatus.streaming => const CellStyle(foreground: AnsiColor(14)),
    ConversationStatus.failed => const CellStyle(foreground: AnsiColor(9)),
    ConversationStatus.archived => theme.mutedStyle,
    ConversationStatus.active ||
    ConversationStatus.idle ||
    ConversationStatus.complete => CellStyle.empty,
  };
}
