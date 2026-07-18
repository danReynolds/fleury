import 'dart:async' show unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury.dart';

import 'component_theme.dart';

/// Severity attached to a [LogEntry].
enum LogSeverity { trace, debug, info, warning, error, success }

/// One logical row in a [LogRegion].
final class LogEntry {
  const LogEntry({
    required this.message,
    this.id,
    this.severity = LogSeverity.info,
    this.source,
    this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  /// Stable identity used by semantics and copy callbacks.
  final Object? id;

  /// Severity used for styling, filtering, and aggregate semantics.
  final LogSeverity severity;

  /// Optional source label such as `stdout`, `stderr`, or a subsystem name.
  final String? source;

  /// Optional timestamp associated with the entry.
  final DateTime? timestamp;

  /// Sanitized display message for the row.
  final String message;

  /// App-specific semantic state carried by the row.
  final Map<String, Object?> metadata;
}

/// Filter applied to [LogRegion] source entries.
final class LogRegionFilterDescriptor {
  const LogRegionFilterDescriptor({
    this.query = '',
    this.sources,
    this.severities,
    this.caseSensitive = false,
  });

  /// Text query matched against message, source, severity, and metadata.
  final String query;

  /// Optional set of source labels to include.
  final Set<String>? sources;

  /// Optional set of severities to include.
  final Set<LogSeverity>? severities;

  /// Whether query matching preserves case.
  final bool caseSensitive;

  bool get isEmpty =>
      query.trim().isEmpty &&
      (sources == null || sources!.isEmpty) &&
      (severities == null || severities!.isEmpty);
}

/// Options for exporting [LogEntry] rows.
final class LogRegionExportOptions {
  const LogRegionExportOptions({
    this.includePrefix = true,
    this.startIndex = 0,
    this.maxEntries,
    this.maxLineLength = 1000,
  }) : assert(startIndex >= 0),
       assert(maxEntries == null || maxEntries >= 0),
       assert(maxLineLength == null || maxLineLength >= 0);

  /// Whether exported rows include timestamp/severity/source prefixes.
  final bool includePrefix;

  /// First filtered entry to export.
  final int startIndex;

  /// Maximum number of entries to export.
  final int? maxEntries;

  /// Maximum message length per exported row.
  final int? maxLineLength;
}

/// Result of exporting [LogEntry] rows.
final class LogRegionExportResult {
  const LogRegionExportResult({
    required this.text,
    required this.entryCount,
    required this.startIndex,
    required this.truncated,
  });

  final String text;
  final int entryCount;
  final int startIndex;
  final bool truncated;
}

/// Clipboard behavior for [LogRegion] selected-entry copy.
final class LogRegionCopyOptions {
  const LogRegionCopyOptions({
    this.includePrefix = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  /// Whether copied rows include timestamp/severity/source prefixes.
  final bool includePrefix;

  /// Clipboard write behavior for copied log text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [LogRegion] copies the selected entry.
final class LogRegionCopyResult {
  const LogRegionCopyResult({
    required this.entryIndex,
    required this.viewIndex,
    required this.entry,
    required this.text,
    required this.report,
  });

  /// Index in the source [LogRegion.entries] list.
  final int entryIndex;

  /// Index in the current filtered/logical view.
  final int viewIndex;

  final LogEntry entry;
  final String text;
  final ClipboardWriteReport report;
}

/// Controller for [LogRegion] selection and tail-follow behavior.
class LogRegionController extends ChangeNotifier {
  LogRegionController({int? selectedIndex, bool followTail = true})
    : _list = ListController(
        selectedIndex:
            selectedIndex ?? (followTail ? _tailSelectionSentinel : 0),
        pinToBottom: followTail,
      ) {
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

  bool get followTail => _list.pinToBottom;
  set followTail(bool value) {
    _checkNotDisposed();
    if (_list.pinToBottom == value) return;
    _list.pinToBottom = value;
    if (value && _list.itemCount > 0) {
      _list.selectedIndex = _list.itemCount - 1;
    }
    notifyListeners();
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    followTail = false;
    // Move the selection onto the target too, not just the scroll anchor. The
    // pending jump is consumed by a single layout; on the next relayout (every
    // streamed append re-lays the list) the selection-visibility pass would
    // otherwise re-anchor the viewport back onto the old selection, silently
    // reverting the jump. Anchoring the selection here keeps the target in
    // view across relayouts. Writing a non-tail index keeps follow disengaged.
    _list.selectedIndex = index;
    _list.jumpToIndex(index);
  }

  void scrollToBottom() {
    _checkNotDisposed();
    followTail = true;
    if (_list.itemCount > 0) _list.selectedIndex = _list.itemCount - 1;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('LogRegionController has been disposed.');
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

const _tailSelectionSentinel = 1 << 30;

/// Exports log entries as sanitized newline-delimited text.
LogRegionExportResult exportLogEntries(
  List<LogEntry> entries, {
  LogRegionFilterDescriptor? filter,
  LogRegionExportOptions options = const LogRegionExportOptions(),
}) {
  final order = buildLogRegionEntryOrder(entries, filter: filter);
  final start = options.startIndex > order.length
      ? order.length
      : options.startIndex;
  final available = order.length - start;
  final limit = options.maxEntries == null || options.maxEntries! > available
      ? available
      : options.maxEntries!;
  final rows = <String>[];
  for (var offset = 0; offset < limit; offset++) {
    final sourceIndex = order[start + offset];
    rows.add(
      _formatLogLine(
        entries[sourceIndex],
        includePrefix: options.includePrefix,
        maxLineLength: options.maxLineLength,
      ).text,
    );
  }
  return LogRegionExportResult(
    text: rows.join('\n'),
    entryCount: rows.length,
    startIndex: start,
    truncated: start + limit < order.length,
  );
}

/// Returns source entry indexes in display order after applying [filter].
List<int> buildLogRegionEntryOrder(
  List<LogEntry> entries, {
  LogRegionFilterDescriptor? filter,
}) {
  if (filter == null || filter.isEmpty) {
    return List<int>.generate(entries.length, (index) => index);
  }
  final compiled = _CompiledLogRegionFilter(filter);
  final order = <int>[];
  for (var index = 0; index < entries.length; index++) {
    if (_entryMatchesFilter(entries[index], compiled)) order.add(index);
  }
  return List<int>.unmodifiable(order);
}

/// Keyboard-navigable, tail-following log/output region.
class LogRegion extends StatefulWidget {
  const LogRegion({
    super.key,
    required this.entries,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Logs',
    this.showPrefix = true,
    this.maxLineLength = 1000,
    this.filter,
    this.searchIndex,
    this.copySelection = true,
    this.copyOptions = const LogRegionCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0);

  /// Source log rows to render, filter, and copy.
  final List<LogEntry> entries;

  /// External selection and tail-follow controller.
  final LogRegionController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the region should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the region.
  final String semanticLabel;

  /// Whether rows render severity/source/timestamp prefixes.
  final bool showPrefix;

  /// Maximum displayed message length per row.
  final int? maxLineLength;

  /// Optional filter applied before rendering rows.
  final LogRegionFilterDescriptor? filter;

  /// Optional prebuilt search index for large log collections.
  final LogRegionSearchIndex? searchIndex;

  /// Whether Ctrl+C and semantic copy export the selected row.
  final bool copySelection;

  /// Clipboard/export options for the selected row.
  final LogRegionCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(LogRegionCopyResult result)? onCopy;

  @override
  State<LogRegion> createState() => _LogRegionState();
}

class _LogRegionState extends State<LogRegion> {
  late LogRegionController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;
  List<LogEntry>? _cachedOrderEntries;
  int _cachedOrderLength = -1;
  LogRegionFilterDescriptor? _cachedOrderFilter;
  List<int>? _cachedOrder;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? LogRegionController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'LogRegion');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant LogRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? LogRegionController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'LogRegion');
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  void _onControllerChange() => setState(() {});

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  List<int> _entryOrder() {
    final entries = widget.entries;
    final filter = widget.filter;
    if (filter == null || filter.isEmpty) {
      _cachedOrderEntries = null;
      _cachedOrderFilter = null;
      _cachedOrder = null;
      return List<int>.generate(entries.length, (index) => index);
    }

    final cachedOrder = _cachedOrder;
    if (cachedOrder != null &&
        identical(_cachedOrderEntries, entries) &&
        _cachedOrderLength == entries.length &&
        _sameFilter(_cachedOrderFilter, filter)) {
      return cachedOrder;
    }

    final searchIndex = widget.searchIndex;
    final order = searchIndex != null && identical(searchIndex.entries, entries)
        ? searchIndex.entryOrder(filter)
        : buildLogRegionEntryOrder(entries, filter: filter);
    _cachedOrderEntries = entries;
    _cachedOrderLength = entries.length;
    _cachedOrderFilter = filter;
    _cachedOrder = order;
    return order;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection || widget.entries.isEmpty) return;
    final order = _entryOrder();
    if (order.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      order.length - 1,
    );
    final sourceIndex = order[selected];
    final entry = widget.entries[sourceIndex];
    final line = _formatLogLine(
      entry,
      includePrefix: widget.copyOptions.includePrefix,
      maxLineLength: widget.maxLineLength,
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(line.text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      LogRegionCopyResult(
        entryIndex: sourceIndex,
        viewIndex: selected,
        entry: entry,
        text: line.text,
        report: report,
      ),
    );
  }

  Future<void> _handleLogAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _entryOrder();
    final visibleRange = _controller.visibleRange;
    final selectedIndex = _controller.selectedIndex;
    final copyEnabled = widget.copySelection && order.isNotEmpty;
    final selectedEntry =
        selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= order.length
        ? null
        : widget.entries[order[selectedIndex]];

    Widget list = ListView.builder(
      controller: _controller._listController,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      itemCount: order.length,
      itemBuilder: (context, viewIndex, activeSelected) {
        final sourceIndex = order[viewIndex];
        final selected = viewIndex == _controller.selectedIndex;
        return _LogRow(
          entry: widget.entries[sourceIndex],
          sourceIndex: sourceIndex,
          viewIndex: viewIndex,
          selected: selected,
          activeSelection: activeSelected,
          showPrefix: widget.showPrefix,
          maxLineLength: widget.maxLineLength,
          copyEnabled: copyEnabled,
          onActivate: () {
            _focusNode.requestFocus();
            _controller.followTail = false;
            _controller.selectedIndex = viewIndex;
          },
          onCopy: _copySelection,
        );
      },
    );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy log entry',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.log,
        label: widget.semanticLabel,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleLogAction,
        state: SemanticState({
          'collectionRowCount': order.length,
          'totalEntryCount': widget.entries.length,
          'filteredEntryCount': order.length,
          ..._filterState(widget.filter),
          'followTail': _controller.followTail,
          'copyEnabled': copyEnabled,
          'copyIncludesPrefix': widget.copyOptions.includePrefix,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          ..._lastEntryState(widget.entries, order),
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          ..._selectedIndexState(selectedIndex),
          ..._selectedEntryState(selectedEntry),
        }),
        child: list,
      ),
    );
  }
}

Map<String, Object?> _selectedIndexState(int? selectedIndex) {
  if (selectedIndex == null) return const <String, Object?>{};
  return <String, Object?>{'selectedIndex': selectedIndex};
}

Map<String, Object?> _filterState(LogRegionFilterDescriptor? filter) {
  if (filter == null || filter.isEmpty) {
    return const <String, Object?>{'filterActive': false};
  }
  final state = <String, Object?>{'filterActive': true};
  final query = filter.query.trim();
  if (query.isNotEmpty) state['filterText'] = query;
  final sources = filter.sources;
  if (sources != null && sources.isNotEmpty) {
    state['filterSources'] = (sources.toList()..sort()).join(',');
  }
  final severities = filter.severities;
  if (severities != null && severities.isNotEmpty) {
    final names = [for (final severity in severities) severity.name]..sort();
    state['filterSeverities'] = names.join(',');
  }
  state['filterCaseSensitive'] = filter.caseSensitive;
  return state;
}

Map<String, Object?> _lastEntryState(List<LogEntry> entries, List<int> order) {
  if (entries.isEmpty || order.isEmpty) return const <String, Object?>{};
  final entry = entries[order.last];
  final state = <String, Object?>{'severity': entry.severity.name};
  final source = entry.source;
  if (source != null) state['source'] = source;
  final id = entry.id;
  if (id != null) state['lastKey'] = id;
  return state;
}

bool _entryMatchesFilter(LogEntry entry, _CompiledLogRegionFilter filter) {
  final severities = filter.descriptor.severities;
  if (severities != null &&
      severities.isNotEmpty &&
      !severities.contains(entry.severity)) {
    return false;
  }

  if (!filter.sourceMatches(entry.source)) return false;

  final matcher = filter.matcher;
  if (matcher == null) return true;
  if (entry.id != null && matcher.matches(entry.id.toString())) return true;
  if (entry.source != null && matcher.matches(entry.source!)) return true;
  if (matcher.matches(_severityLabel(entry.severity))) return true;
  return matcher.matches(_sanitizeLogMessage(entry.message));
}

final class _CompiledLogRegionFilter {
  _CompiledLogRegionFilter(this.descriptor)
    : matcher = descriptor.query.trim().isEmpty
          ? null
          : _TextMatcher(
              descriptor.query.trim(),
              caseSensitive: descriptor.caseSensitive,
            ),
      _foldedSources = descriptor.caseSensitive
          ? null
          : descriptor.sources
                ?.where((source) => source.isNotEmpty)
                .map((source) => source.toLowerCase())
                .toSet();

  final LogRegionFilterDescriptor descriptor;
  final _TextMatcher? matcher;
  final Set<String>? _foldedSources;

  bool sourceMatches(String? source) {
    final sources = descriptor.sources;
    if (sources == null || sources.isEmpty) return true;
    if (source == null) return false;
    if (descriptor.caseSensitive) return sources.contains(source);
    return _foldedSources?.contains(source.toLowerCase()) ?? false;
  }
}

/// Reusable search index for large [LogRegion] entry lists.
///
/// The index owns sanitized search tokens for each entry so interactive filter
/// updates can use postings instead of repeatedly sanitizing retained log
/// lines. Keep the [entries] list stable and call [refresh] after appending or
/// replacing entries.
final class LogRegionSearchIndex {
  LogRegionSearchIndex(this.entries) {
    appendFrom(0);
  }

  /// Creates an empty index for [entries].
  ///
  /// Call [appendFrom], [refresh], [appendFromCooperatively], or
  /// [refreshCooperatively] before using it for queries.
  LogRegionSearchIndex.empty(this.entries);

  /// Builds a [LogRegionSearchIndex] cooperatively under [context].
  ///
  /// Use this from a [TaskController] or [DebouncedTaskController] when a
  /// retained log buffer is large enough that synchronous index construction
  /// would be visible to input/render responsiveness.
  static Future<LogRegionSearchIndex> buildCooperatively(
    List<LogEntry> entries, {
    required TaskContext context,
    TaskYieldPolicy yieldPolicy = const TaskYieldPolicy(),
    String progressLabel = 'indexing logs',
  }) async {
    final index = LogRegionSearchIndex.empty(entries);
    await index.appendFromCooperatively(
      0,
      context: context,
      yieldPolicy: yieldPolicy,
      progressLabel: progressLabel,
    );
    return index;
  }

  final List<LogEntry> entries;
  final List<_IndexedLogEntry> _items = <_IndexedLogEntry>[];
  final Map<String, List<int>> _tokenIndex = <String, List<int>>{};

  int get length => _items.length;

  bool currentPrefixMatches() {
    if (_items.length > entries.length) return false;
    for (var index = 0; index < _items.length; index++) {
      if (!identical(_items[index].entry, entries[index])) return false;
    }
    return true;
  }

  void refresh() {
    if (currentPrefixMatches()) {
      if (_items.length < entries.length) appendFrom(_items.length);
      return;
    }
    appendFrom(0);
  }

  Future<void> refreshCooperatively({
    required TaskContext context,
    TaskYieldPolicy yieldPolicy = const TaskYieldPolicy(),
    String progressLabel = 'indexing logs',
  }) async {
    if (currentPrefixMatches()) {
      if (_items.length < entries.length) {
        await appendFromCooperatively(
          _items.length,
          context: context,
          yieldPolicy: yieldPolicy,
          progressLabel: progressLabel,
        );
      } else {
        context.reportProgress(
          current: _items.length,
          total: entries.length,
          label: '$progressLabel complete',
        );
      }
      return;
    }
    await appendFromCooperatively(
      0,
      context: context,
      yieldPolicy: yieldPolicy,
      progressLabel: progressLabel,
    );
  }

  void appendFrom(int start) {
    if (start < _items.length) {
      _items.removeRange(start, _items.length);
      _tokenIndex.clear();
      start = 0;
    }
    for (var index = start; index < entries.length; index++) {
      _appendEntry(index);
    }
  }

  Future<void> appendFromCooperatively(
    int start, {
    required TaskContext context,
    TaskYieldPolicy yieldPolicy = const TaskYieldPolicy(),
    String progressLabel = 'indexing logs',
  }) async {
    if (start < _items.length) {
      _items.removeRange(start, _items.length);
      _tokenIndex.clear();
      start = 0;
    }
    final checkpoint = yieldPolicy.start(context);
    for (var index = start; index < entries.length; index++) {
      _appendEntry(index);
      await checkpoint.tick(
        current: index + 1,
        total: entries.length,
        label: '$progressLabel ${index + 1}/${entries.length}',
      );
    }
    context.reportProgress(
      current: _items.length,
      total: entries.length,
      label: '$progressLabel complete',
    );
  }

  void _appendEntry(int index) {
    final item = _IndexedLogEntry(index, entries[index]);
    _items.add(item);
    final searchText = _searchTextFor(entries[index]).toLowerCase();
    for (final token in _logSearchTokens(searchText)) {
      final postings = _tokenIndex[token] ??= <int>[];
      if (postings.isEmpty || postings.last != index) postings.add(index);
    }
  }

  List<int> entryOrder(LogRegionFilterDescriptor filter) {
    refresh();
    final compiled = _CompiledLogRegionFilter(filter);
    final indexedOrder = _indexedEntryOrder(compiled);
    if (indexedOrder != null) return indexedOrder;
    final order = <int>[];
    for (final item in _items) {
      if (item.matches(compiled)) order.add(item.index);
    }
    return List<int>.unmodifiable(order);
  }

  List<int>? _indexedEntryOrder(_CompiledLogRegionFilter filter) {
    final matcher = filter.matcher;
    if (matcher == null || matcher.caseSensitive) return null;
    final query = matcher.query;
    if (!_isLogTokenQuery(query)) return null;

    final included = <int>{};
    for (final entry in _tokenIndex.entries) {
      if (!entry.key.contains(query)) continue;
      included.addAll(entry.value);
    }
    if (included.isEmpty) return const <int>[];

    final order = included.toList()..sort();
    return List<int>.unmodifiable([
      for (final index in order)
        if (_items[index].matchesMetadata(filter)) index,
    ]);
  }
}

final class _IndexedLogEntry {
  const _IndexedLogEntry(this.index, this.entry);

  final int index;
  final LogEntry entry;

  bool matches(_CompiledLogRegionFilter filter) {
    return _entryMatchesFilter(entry, filter);
  }

  bool matchesMetadata(_CompiledLogRegionFilter filter) {
    final severities = filter.descriptor.severities;
    if (severities != null &&
        severities.isNotEmpty &&
        !severities.contains(entry.severity)) {
      return false;
    }
    if (!filter.sourceMatches(entry.source)) return false;
    return true;
  }
}

String _searchTextFor(LogEntry entry) {
  return [
    if (entry.id != null) entry.id.toString(),
    if (entry.source != null) entry.source!,
    _severityLabel(entry.severity),
    _sanitizeLogMessage(entry.message),
  ].join('\u{0}');
}

bool _sameFilter(LogRegionFilterDescriptor? a, LogRegionFilterDescriptor? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.query == b.query &&
      a.caseSensitive == b.caseSensitive &&
      _sameSet(a.sources, b.sources) &&
      _sameSet(a.severities, b.severities);
}

bool _sameSet<T>(Set<T>? a, Set<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (final value in a) {
    if (!b.contains(value)) return false;
  }
  return true;
}

Iterable<String> _logSearchTokens(String text) sync* {
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    if (_isLogTokenCodeUnit(codeUnit)) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      yield text.substring(start, i);
      start = -1;
    }
  }
  if (start >= 0) yield text.substring(start);
}

bool _isLogTokenQuery(String query) {
  if (query.isEmpty) return false;
  for (var i = 0; i < query.length; i++) {
    if (!_isLogTokenCodeUnit(query.codeUnitAt(i))) return false;
  }
  return true;
}

bool _isLogTokenCodeUnit(int codeUnit) {
  return (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      codeUnit == 0x5f ||
      codeUnit == 0x2d ||
      codeUnit == 0x3a;
}

final class _TextMatcher {
  _TextMatcher(String query, {required this.caseSensitive})
    : query = caseSensitive ? query : query.toLowerCase(),
      _asciiCaseInsensitive = !caseSensitive && _isAscii(query);

  final String query;
  final bool caseSensitive;
  final bool _asciiCaseInsensitive;

  bool matches(String text) {
    if (caseSensitive) return text.contains(query);
    if (_asciiCaseInsensitive) {
      return _containsAsciiCaseInsensitive(text, query);
    }
    return text.toLowerCase().contains(query);
  }

  bool matchesIndexed({
    required String caseSensitiveText,
    required String foldedText,
  }) {
    if (caseSensitive) return caseSensitiveText.contains(query);
    return foldedText.contains(query);
  }
}

bool _isAscii(String text) {
  for (final codeUnit in text.codeUnits) {
    if (codeUnit > 0x7f) return false;
  }
  return true;
}

bool _containsAsciiCaseInsensitive(String text, String query) {
  if (query.isEmpty) return true;
  final lastStart = text.length - query.length;
  if (lastStart < 0) return false;
  final firstQueryUnit = query.codeUnitAt(0);
  for (var start = 0; start <= lastStart; start++) {
    if (_foldAscii(text.codeUnitAt(start)) != firstQueryUnit) continue;
    var matched = true;
    for (var offset = 1; offset < query.length; offset++) {
      if (_foldAscii(text.codeUnitAt(start + offset)) !=
          query.codeUnitAt(offset)) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

int _foldAscii(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5a) return codeUnit + 0x20;
  return codeUnit;
}

Map<String, Object?> _selectedEntryState(LogEntry? entry) {
  if (entry == null) return const <String, Object?>{};
  final state = <String, Object?>{'selectedSeverity': entry.severity.name};
  final source = entry.source;
  if (source != null) state['selectedSource'] = source;
  final id = entry.id;
  if (id != null) state['selectedKey'] = id;
  return state;
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.entry,
    required this.sourceIndex,
    required this.viewIndex,
    required this.selected,
    required this.activeSelection,
    required this.showPrefix,
    required this.maxLineLength,
    required this.copyEnabled,
    required this.onActivate,
    required this.onCopy,
  });

  final LogEntry entry;
  final int sourceIndex;
  final int viewIndex;
  final bool selected;
  final bool activeSelection;
  final bool showPrefix;
  final int? maxLineLength;
  final bool copyEnabled;
  final VoidCallback onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final line = _formatLogLine(
      entry,
      includePrefix: showPrefix,
      maxLineLength: maxLineLength,
    );
    final style = _styleForSeverity(entry.severity, widgetTheme, theme).merge(
      activeSelection
          ? theme.selectionStyle
          : selected
          ? theme.mutedStyle
          : CellStyle.empty,
    );
    return Semantics(
      role: SemanticRole.listItem,
      label: line.message,
      value: line.text,
      selected: selected,
      actions: {
        SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            onActivate();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': sourceIndex,
        'viewIndex': viewIndex,
        if (entry.id != null) 'rowKey': entry.id,
        'severity': entry.severity.name,
        if (entry.source != null) 'source': entry.source,
        if (entry.timestamp != null)
          'timestamp': entry.timestamp!.toIso8601String(),
        'outputSanitized': line.sanitized,
        'outputTruncated': line.truncated,
        'outputOriginalLength': line.originalLength,
        ...entry.metadata,
      }),
      child: Text(line.text, style: style),
    );
  }
}

final class _FormattedLogLine {
  const _FormattedLogLine({
    required this.text,
    required this.message,
    required this.sanitized,
    required this.truncated,
    required this.originalLength,
  });

  final String text;
  final String message;
  final bool sanitized;
  final bool truncated;
  final int originalLength;
}

_FormattedLogLine _formatLogLine(
  LogEntry entry, {
  required bool includePrefix,
  required int? maxLineLength,
}) {
  final original = entry.message;
  final sanitized = _sanitizeLogMessage(original);
  final truncatedMessage = _truncateGraphemes(sanitized, maxLineLength);
  final prefix = includePrefix ? _prefixFor(entry) : '';
  return _FormattedLogLine(
    text: '$prefix$truncatedMessage',
    message: truncatedMessage,
    sanitized: sanitized != original,
    truncated: truncatedMessage != sanitized,
    originalLength: original.length,
  );
}

String _sanitizeLogMessage(String original) {
  if (!_needsLogSanitization(original)) return original;
  return sanitizeSingleLine(original);
}

bool _needsLogSanitization(String text) {
  for (final codeUnit in text.codeUnits) {
    if (codeUnit == 0x1b ||
        codeUnit == 0x9b ||
        codeUnit == 0x9d ||
        codeUnit == 0x90 ||
        codeUnit == 0x98 ||
        codeUnit == 0x9e ||
        codeUnit == 0x9f ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d ||
        codeUnit == 0x09) {
      return true;
    }
  }
  return false;
}

String _truncateGraphemes(String text, int? maxLineLength) {
  if (maxLineLength == null) return text;
  if (maxLineLength == 0) return '';
  final characters = text.characters;
  if (characters.length <= maxLineLength) return text;
  return characters.take(maxLineLength).toString();
}

String _prefixFor(LogEntry entry) {
  final parts = <String>[
    if (entry.timestamp != null) entry.timestamp!.toIso8601String(),
    _severityLabel(entry.severity),
    if (entry.source != null && entry.source!.isNotEmpty) entry.source!,
  ];
  return parts.isEmpty ? '' : '[${parts.join(' ')}] ';
}

String _severityLabel(LogSeverity severity) {
  return switch (severity) {
    LogSeverity.trace => 'TRACE',
    LogSeverity.debug => 'DEBUG',
    LogSeverity.info => 'INFO',
    LogSeverity.warning => 'WARN',
    LogSeverity.error => 'ERROR',
    LogSeverity.success => 'OK',
  };
}

CellStyle _styleForSeverity(
  LogSeverity severity,
  FleuryWidgetTheme widgetTheme,
  ThemeData theme,
) {
  return switch (severity) {
    LogSeverity.trace => widgetTheme.resolveLogTrace(theme),
    LogSeverity.debug => widgetTheme.resolveLogDebug(theme),
    LogSeverity.info => widgetTheme.resolveLogInfo(theme),
    LogSeverity.warning => widgetTheme.resolveLogWarning(theme),
    LogSeverity.error => widgetTheme.resolveLogError(theme),
    LogSeverity.success => widgetTheme.resolveLogSuccess(theme),
  };
}
