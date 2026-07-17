import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:fleury/fleury_core.dart';

/// Type of target exposed by [FileMentionPicker].
enum FileMentionKind { file, directory, symbol, url, other }

/// One file-like mention target for composer and developer-tool workflows.
final class FileMentionEntry {
  const FileMentionEntry({
    required this.path,
    this.label,
    this.detail,
    this.kind = FileMentionKind.file,
    this.language,
    this.line,
    this.column,
    this.mentionText,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
  }) : assert(line == null || line > 0),
       assert(column == null || column > 0);

  /// File path, symbol path, URL, or other target identifier.
  final String path;

  /// Optional display label; defaults to [path].
  final String? label;

  /// Optional secondary detail text.
  final String? detail;

  /// Kind of mention target represented by this entry.
  final FileMentionKind kind;

  /// Optional language identifier for file or symbol targets.
  final String? language;

  /// One-based line number for source targets.
  final int? line;

  /// One-based column number for source targets.
  final int? column;

  /// Text inserted/copied when this entry is picked.
  final String? mentionText;

  /// Whether this entry can be selected and picked.
  final bool enabled;

  /// App-specific semantic state carried by the entry.
  final Map<String, Object?> metadata;

  String get displayLabel => label ?? path;
  String get displayMention => mentionText ?? '@$path';
}

/// Predicate used by [buildFileMentionOrder].
typedef FileMentionMatcher =
    bool Function(FileMentionEntry entry, String query);

/// Controller for [FileMentionPicker] selection and viewport state.
class FileMentionPickerController extends ChangeNotifier {
  FileMentionPickerController({int selectedIndex = 0})
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
      throw StateError('FileMentionPickerController has been disposed.');
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

/// Clipboard/export behavior for [FileMentionPicker] selected-mention copy.
final class FileMentionCopyOptions {
  const FileMentionCopyOptions({
    this.copyMentionText = true,
    this.includeDetail = false,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  /// Whether copy uses [FileMentionEntry.displayMention] instead of the path.
  final bool copyMentionText;

  /// Whether copied text includes [FileMentionEntry.detail].
  final bool includeDetail;

  /// Clipboard write behavior for copied mention text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [FileMentionPicker] copies the selected mention.
final class FileMentionCopyResult {
  const FileMentionCopyResult({
    required this.entryIndex,
    required this.viewIndex,
    required this.entry,
    required this.text,
    required this.report,
  });

  final int entryIndex;
  final int viewIndex;
  final FileMentionEntry entry;
  final String text;
  final ClipboardWriteReport report;
}

/// Result delivered after [FileMentionPicker] picks a mention.
final class FileMentionPickResult {
  const FileMentionPickResult({
    required this.entryIndex,
    required this.viewIndex,
    required this.entry,
  });

  final int entryIndex;
  final int viewIndex;
  final FileMentionEntry entry;
}

/// Returns source entry indexes in display order after applying [query].
List<int> buildFileMentionOrder(
  List<FileMentionEntry> entries, {
  String query = '',
  FileMentionMatcher? matcher,
}) {
  final trimmed = _sanitizeMentionText(query).trim();
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
    switch (_mentionRank(entries[index], q)) {
      case _MentionRank.exact:
        exact.add(index);
      case _MentionRank.prefix:
        prefix.add(index);
      case _MentionRank.contains:
        contains.add(index);
      case _MentionRank.fuzzy:
        fuzzy.add(index);
      case null:
        break;
    }
  }
  return List<int>.unmodifiable([...exact, ...prefix, ...contains, ...fuzzy]);
}

/// Exports one [FileMentionEntry] as sanitized clipboard/debug text.
String exportFileMention(
  FileMentionEntry entry, {
  FileMentionCopyOptions options = const FileMentionCopyOptions(),
}) {
  final target = options.copyMentionText ? entry.displayMention : entry.path;
  final parts = <String>[
    _sanitizeMentionText(target),
    if (options.includeDetail && entry.detail != null)
      _sanitizeMentionText(entry.detail!),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' | ');
}

/// Queryable file/symbol mention picker for composers and developer tools.
class FileMentionPicker extends StatefulWidget {
  const FileMentionPicker({
    super.key,
    required this.entries,
    this.queryController,
    this.controller,
    this.matcher,
    this.semanticLabel = 'File mentions',
    this.placeholder = 'Mention file...',
    this.width = 60,
    this.maxVisible = 6,
    this.queryFocusNode,
    this.resultsFocusNode,
    this.autofocus = false,
    this.copySelection = true,
    this.copyOptions = const FileMentionCopyOptions(),
    this.onPick,
    this.onCopy,
  }) : assert(width > 0),
       assert(maxVisible > 0);

  /// Source mention entries to search, display, pick, and copy.
  final List<FileMentionEntry> entries;

  /// External controller for the query input.
  final TextEditingController? queryController;

  /// External controller for result selection and visible range.
  final FileMentionPickerController? controller;

  /// Optional app-owned matcher used instead of default ranked search.
  final FileMentionMatcher? matcher;

  /// Semantic label (the accessibility name; not rendered) for the picker.
  final String semanticLabel;

  /// Placeholder shown in the query input.
  final String placeholder;

  /// Width, in terminal cells, reserved for query and rows.
  final int width;

  /// Maximum visible rows before the list scrolls.
  final int maxVisible;

  /// Focus node used by the query input.
  final FocusNode? queryFocusNode;

  /// Focus node used by the results list.
  final FocusNode? resultsFocusNode;

  /// Whether the query input should request focus when mounted.
  final bool autofocus;

  /// Whether Ctrl+C and semantic copy export the selected mention.
  final bool copySelection;

  /// Clipboard/export options for selected-mention copy.
  final FileMentionCopyOptions copyOptions;

  /// Called when a mention is picked.
  final void Function(FileMentionPickResult result)? onPick;

  /// Called after a copy attempt completes.
  final void Function(FileMentionCopyResult result)? onCopy;

  @override
  State<FileMentionPicker> createState() => _FileMentionPickerState();
}

class _FileMentionPickerState extends State<FileMentionPicker> {
  late TextEditingController _query;
  late FileMentionPickerController _controller;
  late FocusNode _queryFocusNode;
  late FocusNode _resultsFocusNode;
  bool _ownsQuery = false;
  bool _ownsController = false;
  bool _ownsQueryFocusNode = false;
  bool _ownsResultsFocusNode = false;
  FocusManager? _focusManager;
  String? _pendingSelectedMentionPath;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _query = widget.queryController ?? TextEditingController();
    _ownsQuery = widget.queryController == null;
    _query.addListener(_onQueryChange);
    _controller = widget.controller ?? FileMentionPickerController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _queryFocusNode =
        widget.queryFocusNode ??
        FocusNode(debugLabel: 'FileMentionPicker query');
    _ownsQueryFocusNode = widget.queryFocusNode == null;
    _resultsFocusNode =
        widget.resultsFocusNode ??
        FocusNode(debugLabel: 'FileMentionPicker results');
    _ownsResultsFocusNode = widget.resultsFocusNode == null;
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
  void didUpdateWidget(covariant FileMentionPicker oldWidget) {
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
      _controller = widget.controller ?? FileMentionPickerController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.queryFocusNode != oldWidget.queryFocusNode) {
      if (_ownsQueryFocusNode) _queryFocusNode.dispose();
      _queryFocusNode =
          widget.queryFocusNode ??
          FocusNode(debugLabel: 'FileMentionPicker query');
      _ownsQueryFocusNode = widget.queryFocusNode == null;
    }
    if (widget.resultsFocusNode != oldWidget.resultsFocusNode) {
      if (_ownsResultsFocusNode) _resultsFocusNode.dispose();
      _resultsFocusNode =
          widget.resultsFocusNode ??
          FocusNode(debugLabel: 'FileMentionPicker results');
      _ownsResultsFocusNode = widget.resultsFocusNode == null;
    }
    if (widget.controller != oldWidget.controller) {
      _resetSelection(_currentOrder, preserveCurrent: true);
    } else if (widget.entries != oldWidget.entries ||
        widget.matcher != oldWidget.matcher) {
      final oldOrder = buildFileMentionOrder(
        oldWidget.entries,
        query: _query.text,
        matcher: oldWidget.matcher,
      );
      _syncSelectionAfterOrderUpdate(oldOrder, oldWidget.entries);
    }
  }

  List<int> get _currentOrder => buildFileMentionOrder(
    widget.entries,
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
    _pendingSelectedMentionPath = null;
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
    List<FileMentionEntry> oldEntries,
  ) {
    _selectionSyncGeneration++;
    _pendingSelectedMentionPath = null;
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
      final selectedPath = oldEntries[oldOrder[selectedIndex]].path;
      final nextIndex = order.indexWhere(
        (entryIndex) => widget.entries[entryIndex].path == selectedPath,
      );
      if (nextIndex != -1) {
        _selectIndexAfterListCountRefresh(selectedPath, nextIndex);
        return;
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(0, order.length - 1);
  }

  void _selectIndexAfterListCountRefresh(String selectedPath, int nextIndex) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedMentionPath = selectedPath;
    final generation = _selectionSyncGeneration;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyPendingSelection(generation, selectedPath);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyPendingSelection(generation, selectedPath);
    });
  }

  void _applyPendingSelection(int generation, String selectedPath) {
    if (!mounted || generation != _selectionSyncGeneration) return;
    if (_pendingSelectedMentionPath != selectedPath) return;
    final order = _currentOrder;
    final nextIndex = order.indexWhere(
      (entryIndex) => widget.entries[entryIndex].path == selectedPath,
    );
    if (nextIndex == -1) {
      _pendingSelectedMentionPath = null;
      return;
    }
    _pendingSelectedMentionPath = null;
    _controller.selectedIndex = nextIndex;
  }

  void _focusQuery() {
    _queryFocusNode.requestFocus();
    setState(() {});
  }

  void _focusResultsOrQuery() {
    if (_currentOrder.isEmpty) {
      _focusQuery();
      return;
    }
    _resultsFocusNode.requestFocus();
    setState(() {});
  }

  void _move(int delta) {
    final order = _currentOrder;
    if (order.isEmpty) return;
    final current = _controller.selectedIndex ?? 0;
    _controller.selectedIndex = (current + delta).clamp(0, order.length - 1);
  }

  _SelectedMention? _selectedMention(List<int> order) {
    if (order.isEmpty) return null;
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) return null;
    final viewIndex = selectedIndex.clamp(0, order.length - 1);
    final entryIndex = order[viewIndex];
    return _SelectedMention(
      viewIndex: viewIndex,
      entryIndex: entryIndex,
      entry: widget.entries[entryIndex],
    );
  }

  void _pickSelected() {
    final selected = _selectedMention(_currentOrder);
    if (selected == null || !selected.entry.enabled) return;
    widget.onPick?.call(
      FileMentionPickResult(
        entryIndex: selected.entryIndex,
        viewIndex: selected.viewIndex,
        entry: selected.entry,
      ),
    );
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection) return;
    final selected = _selectedMention(_currentOrder);
    if (selected == null) return;
    final text = exportFileMention(selected.entry, options: widget.copyOptions);
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      FileMentionCopyResult(
        entryIndex: selected.entryIndex,
        viewIndex: selected.viewIndex,
        entry: selected.entry,
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _handlePickerAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
        _focusQuery();
        return;
      case SemanticAction.navigate:
        _focusResultsOrQuery();
        return;
      case SemanticAction.submit:
        _pickSelected();
        return;
      case SemanticAction.copy:
        _focusResultsOrQuery();
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  Future<void> _pickAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _focusResultsOrQuery();
    _controller.selectedIndex = viewIndex;
    _pickSelected();
  }

  Future<void> _copyAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _focusResultsOrQuery();
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
    if (_ownsResultsFocusNode) _resultsFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = _currentOrder;
    final visible = order.isEmpty
        ? 1
        : (order.length > widget.maxVisible ? widget.maxVisible : order.length);
    final selected = _selectedMention(order);
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && selected != null;
    final canPick = widget.onPick != null;
    final panelFocused = _queryFocusNode.hasFocus || _resultsFocusNode.hasFocus;

    Widget panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextInput(
          controller: _query,
          focusNode: _queryFocusNode,
          placeholder: widget.placeholder,
          autofocus: widget.autofocus,
          onSubmit: (_) => _pickSelected(),
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: visible,
          child: order.isEmpty
              ? Text(
                  _query.text.trim().isEmpty
                      ? widget.placeholder
                      : 'No matching files',
                )
              : ListView.builder(
                  controller: _controller._listController,
                  focusNode: _resultsFocusNode,
                  selectionActive: panelFocused,
                  itemCount: order.length,
                  onActivate: (_) => _pickSelected(),
                  itemBuilder: (context, viewIndex, activeSelected) {
                    final entryIndex = order[viewIndex];
                    final selected = viewIndex == _controller.selectedIndex;
                    return _FileMentionRow(
                      entry: widget.entries[entryIndex],
                      entryIndex: entryIndex,
                      viewIndex: viewIndex,
                      selected: selected,
                      activeSelection: activeSelected,
                      canPick: canPick,
                      copyEnabled: copyEnabled,
                      onPick: () => _pickAt(viewIndex),
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
            label: 'Copy file mention',
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
        role: SemanticRole.fileMentionPicker,
        label: widget.semanticLabel,
        value: _query.text,
        focused: _queryFocusNode.hasFocus || _resultsFocusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (canPick) SemanticAction.submit,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handlePickerAction,
        state: SemanticState({
          'filterText': _query.text,
          'collectionRowCount': order.length,
          'totalMentionCount': widget.entries.length,
          'filteredMentionCount': order.length,
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null && order.isNotEmpty) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?_controller.selectedIndex,
          if (selected != null) ..._selectedMentionState(selected.entry),
        }),
        child: panel,
      ),
    );
  }
}

final class _SelectedMention {
  const _SelectedMention({
    required this.viewIndex,
    required this.entryIndex,
    required this.entry,
  });

  final int viewIndex;
  final int entryIndex;
  final FileMentionEntry entry;
}

class _FileMentionRow extends StatelessWidget {
  const _FileMentionRow({
    required this.entry,
    required this.entryIndex,
    required this.viewIndex,
    required this.selected,
    required this.activeSelection,
    required this.canPick,
    required this.copyEnabled,
    required this.onPick,
    required this.onCopy,
  });

  final FileMentionEntry entry;
  final int entryIndex;
  final int viewIndex;
  final bool selected;
  final bool activeSelection;
  final bool canPick;
  final bool copyEnabled;
  final Future<void> Function() onPick;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final label = _sanitizeMentionText(entry.displayLabel);
    final path = _sanitizeMentionText(entry.path);
    final detail = entry.detail == null
        ? null
        : _sanitizeMentionText(entry.detail!);
    final mentionText = _sanitizeMentionText(entry.displayMention);
    final language = entry.language == null
        ? null
        : _sanitizeMentionText(entry.language!);
    final rowText = _rowText(
      label: label,
      path: path,
      kind: entry.kind,
      language: language,
      activeSelection: activeSelection,
    );

    return Semantics(
      role: SemanticRole.fileMention,
      label: label,
      value: mentionText,
      hint: detail,
      selected: selected,
      enabled: entry.enabled,
      actions: {
        if (entry.enabled && canPick) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            if (entry.enabled && canPick) await onPick();
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
        'rowKey': path,
        'filePath': path,
        'fileKind': entry.kind.name,
        'fileLanguage': ?language,
        'mentionText': mentionText,
        'line': ?entry.line,
        'column': ?entry.column,
        'outputSanitized': _entryWasSanitized(entry),
      }),
      // Click an enabled mention to pick it (same as Enter on the selection).
      child: GestureDetector(
        onTap: (entry.enabled && canPick) ? () => unawaited(onPick()) : null,
        child: Text(
          rowText,
          style: _rowStyle(
            Theme.of(context),
            selected: selected,
            activeSelection: activeSelection,
            enabled: entry.enabled,
          ),
        ),
      ),
    );
  }
}

String _rowText({
  required String label,
  required String path,
  required FileMentionKind kind,
  required String? language,
  required bool activeSelection,
}) {
  final prefix = activeSelection ? '> ' : '  ';
  final meta = <String>[
    kind.name,
    if (language != null && language.isNotEmpty) language,
    if (path != label) path,
  ];
  return '$prefix$label  ${meta.join('  ')}';
}

Map<String, Object?> _selectedMentionState(FileMentionEntry entry) {
  final path = _sanitizeMentionText(entry.path);
  return <String, Object?>{
    'selectedKey': path,
    'selectedFilePath': path,
    'selectedMentionText': _sanitizeMentionText(entry.displayMention),
    'selectedFileKind': entry.kind.name,
    if (entry.language != null)
      'selectedFileLanguage': _sanitizeMentionText(entry.language!),
  };
}

enum _MentionRank { exact, prefix, contains, fuzzy }

_MentionRank? _mentionRank(FileMentionEntry entry, String query) {
  final fields = _mentionFields(entry);
  for (final field in fields) {
    if (field == query) return _MentionRank.exact;
  }
  for (final field in fields) {
    if (field.startsWith(query)) return _MentionRank.prefix;
  }
  final searchText = fields.join(' ');
  if (searchText.contains(query)) return _MentionRank.contains;
  if (_isSubsequence(query, searchText)) return _MentionRank.fuzzy;
  return null;
}

List<String> _mentionFields(FileMentionEntry entry) {
  return [
        entry.path,
        entry.displayLabel,
        entry.displayMention,
        entry.kind.name,
        if (entry.detail != null) entry.detail!,
        if (entry.language != null) entry.language!,
        if (entry.line != null) entry.line.toString(),
        if (entry.column != null) entry.column.toString(),
        for (final value in entry.metadata.values)
          if (value != null) value.toString(),
      ]
      .map(_sanitizeMentionText)
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

bool _entryWasSanitized(FileMentionEntry entry) {
  return _sanitizeMentionText(entry.path) != entry.path ||
      (entry.label != null &&
          _sanitizeMentionText(entry.label!) != entry.label) ||
      (entry.detail != null &&
          _sanitizeMentionText(entry.detail!) != entry.detail) ||
      (entry.mentionText != null &&
          _sanitizeMentionText(entry.mentionText!) != entry.mentionText);
}

String _sanitizeMentionText(String text) {
  return sanitizeSingleLine(text).replaceAll(RegExp(' +'), ' ').trim();
}

CellStyle _rowStyle(
  ThemeData theme, {
  required bool selected,
  required bool activeSelection,
  required bool enabled,
}) {
  if (!enabled) return theme.mutedStyle;
  if (activeSelection) return theme.selectionStyle;
  if (selected) return theme.mutedStyle;
  return CellStyle.empty;
}
