import 'dart:async' show unawaited;

import 'package:fleury/fleury.dart';

/// One result rendered by [SearchPanel].
final class SearchResult {
  const SearchResult({
    required this.title,
    this.id,
    this.subtitle,
    this.category,
    this.source,
    this.detail,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
  });

  /// Stable result identity used by semantics and copy callbacks.
  final Object? id;

  /// Primary row text.
  final String title;

  /// Secondary row text.
  final String? subtitle;

  /// Optional grouping/category text.
  final String? category;

  /// Optional source or origin label.
  final String? source;

  /// Optional longer detail text. Included in search and copy, but not
  /// rendered in the compact row by default.
  final String? detail;

  /// Whether this result can be activated.
  final bool enabled;

  /// App-specific semantic state carried by the row.
  final Map<String, Object?> metadata;
}

/// Predicate used by [SearchResultIndex] and [buildSearchResultOrder].
typedef SearchResultMatcher = bool Function(SearchResult result, String query);

/// Cached, sanitized search index for [SearchResult] collections.
///
/// The index returns source-result indexes instead of reordered result objects
/// so callers can preserve stable selection, activation, copy, and semantic
/// state from their original list. Default matching is ranked as exact,
/// prefix, contains, then fuzzy subsequence. Passing a custom [matcher] keeps
/// caller-owned source-order filtering semantics.
final class SearchResultIndex {
  SearchResultIndex(List<SearchResult> results)
    : _entries = List<_SearchResultEntry>.unmodifiable([
        for (var index = 0; index < results.length; index++)
          _SearchResultEntry(
            sourceIndex: index,
            result: results[index],
            searchFields: _searchResultFields(results[index]),
          ),
      ]);

  final List<_SearchResultEntry> _entries;

  /// Number of indexed source results.
  int get length => _entries.length;

  /// Returns source result indexes in display order after applying [query].
  List<int> order({String query = '', SearchResultMatcher? matcher}) {
    final trimmed = _sanitizeSearchText(query).trim();
    if (trimmed.isEmpty) {
      return List<int>.unmodifiable(_entries.map((entry) => entry.sourceIndex));
    }

    if (matcher != null) {
      return List<int>.unmodifiable([
        for (final entry in _entries)
          if (matcher(entry.result, trimmed)) entry.sourceIndex,
      ]);
    }

    final q = trimmed.toLowerCase();
    final exact = <int>[];
    final prefix = <int>[];
    final contains = <int>[];
    final fuzzy = <int>[];
    for (final entry in _entries) {
      switch (_searchResultRank(entry, q)) {
        case _SearchResultRank.exact:
          exact.add(entry.sourceIndex);
        case _SearchResultRank.prefix:
          prefix.add(entry.sourceIndex);
        case _SearchResultRank.contains:
          contains.add(entry.sourceIndex);
        case _SearchResultRank.fuzzy:
          fuzzy.add(entry.sourceIndex);
        case null:
          break;
      }
    }
    return List<int>.unmodifiable([...exact, ...prefix, ...contains, ...fuzzy]);
  }
}

/// Clipboard/export behavior for [SearchPanel] selected-result copy.
final class SearchPanelCopyOptions {
  const SearchPanelCopyOptions({
    this.includeSubtitle = true,
    this.includeCategory = true,
    this.includeSource = true,
    this.includeDetail = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final bool includeSubtitle;
  final bool includeCategory;
  final bool includeSource;
  final bool includeDetail;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [SearchPanel] copies the selected result.
final class SearchPanelCopyResult {
  const SearchPanelCopyResult({
    required this.resultIndex,
    required this.viewIndex,
    required this.result,
    required this.text,
    required this.report,
  });

  /// Index in the source [SearchPanel.results] list.
  final int resultIndex;

  /// Index in the current filtered/logical view.
  final int viewIndex;

  final SearchResult result;
  final String text;
  final ClipboardWriteReport report;
}

/// Returns source result indexes in display order after applying [query].
List<int> buildSearchResultOrder(
  List<SearchResult> results, {
  String query = '',
  SearchResultMatcher? matcher,
}) {
  return SearchResultIndex(results).order(query: query, matcher: matcher);
}

/// Exports one [SearchResult] as sanitized single-line clipboard text.
String exportSearchResult(
  SearchResult result, {
  SearchPanelCopyOptions options = const SearchPanelCopyOptions(),
}) {
  final parts = <String>[
    result.title,
    if (options.includeSubtitle && result.subtitle != null) result.subtitle!,
    if (options.includeCategory && result.category != null) result.category!,
    if (options.includeSource && result.source != null) result.source!,
    if (options.includeDetail && result.detail != null) result.detail!,
  ];
  return parts
      .map(_sanitizeSearchText)
      .where((part) => part.trim().isNotEmpty)
      .join(' | ');
}

/// Search input plus keyboard-navigable result list.
///
/// The widget owns only presentation, selection, activation, copy, and
/// semantics. Callers can pass already-ranked [results], or use [matcher] to
/// narrow a larger list with a custom predicate.
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.results,
    this.queryController,
    this.controller,
    this.matcher,
    this.label = 'Search',
    this.placeholder = 'Search...',
    this.width = 60,
    this.maxVisible = 10,
    this.fillHeight = false,
    this.queryFocusNode,
    this.resultsFocusNode,
    this.autofocus = false,
    this.copySelection = true,
    this.copyOptions = const SearchPanelCopyOptions(),
    this.onActivate,
    this.onCopy,
  }) : assert(width > 0),
       assert(maxVisible > 0);

  final List<SearchResult> results;
  final TextEditingController? queryController;
  final ListController? controller;
  final SearchResultMatcher? matcher;
  final String label;
  final String placeholder;
  final int width;

  /// Cap on the number of result rows when [fillHeight] is false. When
  /// [fillHeight] is true this is ignored and the list grows to fill the
  /// available vertical space.
  final int maxVisible;

  /// When true the result list expands to fill the height handed down by the
  /// parent (e.g. an [Expanded] panel slot) instead of being capped at
  /// [maxVisible] rows. Requires a bounded-height parent.
  final bool fillHeight;
  final FocusNode? queryFocusNode;
  final FocusNode? resultsFocusNode;
  final bool autofocus;
  final bool copySelection;
  final SearchPanelCopyOptions copyOptions;
  final void Function(SearchResult result, int resultIndex)? onActivate;
  final void Function(SearchPanelCopyResult result)? onCopy;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  late TextEditingController _query;
  late ListController _list;
  late FocusNode _queryFocusNode;
  late FocusNode _resultsFocusNode;
  bool _ownsQuery = false;
  bool _ownsList = false;
  bool _ownsQueryFocusNode = false;
  bool _ownsResultsFocusNode = false;
  FocusManager? _focusManager;
  List<SearchResult>? _indexedResults;
  SearchResultIndex? _searchIndex;

  @override
  void initState() {
    super.initState();
    _query = widget.queryController ?? TextEditingController();
    _ownsQuery = widget.queryController == null;
    _query.addListener(_onQueryChange);
    _list = widget.controller ?? ListController(selectedIndex: 0);
    _ownsList = widget.controller == null;
    _queryFocusNode =
        widget.queryFocusNode ?? FocusNode(debugLabel: 'SearchPanel query');
    _ownsQueryFocusNode = widget.queryFocusNode == null;
    _resultsFocusNode =
        widget.resultsFocusNode ?? FocusNode(debugLabel: 'SearchPanel results');
    _ownsResultsFocusNode = widget.resultsFocusNode == null;
    _resetSelectionForOrder(_currentOrder);
    _list.addListener(_onListChange);
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
  void didUpdateWidget(covariant SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queryController != oldWidget.queryController) {
      _query.removeListener(_onQueryChange);
      if (_ownsQuery) _query.dispose();
      _query = widget.queryController ?? TextEditingController();
      _ownsQuery = widget.queryController == null;
      _query.addListener(_onQueryChange);
    }
    if (widget.controller != oldWidget.controller) {
      _list.removeListener(_onListChange);
      if (_ownsList) _list.dispose();
      _list = widget.controller ?? ListController(selectedIndex: 0);
      _ownsList = widget.controller == null;
    }
    if (widget.queryFocusNode != oldWidget.queryFocusNode) {
      if (_ownsQueryFocusNode) _queryFocusNode.dispose();
      _queryFocusNode =
          widget.queryFocusNode ?? FocusNode(debugLabel: 'SearchPanel query');
      _ownsQueryFocusNode = widget.queryFocusNode == null;
    }
    if (widget.resultsFocusNode != oldWidget.resultsFocusNode) {
      if (_ownsResultsFocusNode) _resultsFocusNode.dispose();
      _resultsFocusNode =
          widget.resultsFocusNode ??
          FocusNode(debugLabel: 'SearchPanel results');
      _ownsResultsFocusNode = widget.resultsFocusNode == null;
    }
    if (widget.results != oldWidget.results ||
        widget.matcher != oldWidget.matcher) {
      final previousResult = _selectedResultFor(
        oldWidget.results,
        SearchResultIndex(
          oldWidget.results,
        ).order(query: _query.text, matcher: oldWidget.matcher),
      )?.result;
      if (widget.results != oldWidget.results) {
        _indexedResults = null;
        _searchIndex = null;
      }
      _preserveSelectionForOrder(_currentOrder, previousResult);
    }
    if (widget.controller != oldWidget.controller) {
      _resetSelectionForOrder(_currentOrder);
      _list.addListener(_onListChange);
    }
  }

  void _onQueryChange() {
    final previous = _list.selectedIndex;
    _resetSelectionForOrder(_currentOrder);
    if (_list.selectedIndex == previous) setState(() {});
  }

  void _onListChange() => setState(() {});

  void _onFocusChange() => setState(() {});

  SearchResultIndex get _resultIndex {
    final index = _searchIndex;
    if (index != null && identical(_indexedResults, widget.results)) {
      return index;
    }
    final next = SearchResultIndex(widget.results);
    _indexedResults = widget.results;
    _searchIndex = next;
    return next;
  }

  List<int> get _currentOrder =>
      _resultIndex.order(query: _query.text, matcher: widget.matcher);

  void _resetSelectionForOrder(List<int> order) {
    _list.selectedIndex = order.isEmpty ? null : 0;
  }

  void _preserveSelectionForOrder(
    List<int> order,
    SearchResult? previousResult,
  ) {
    if (order.isEmpty) {
      _list.selectedIndex = null;
      return;
    }

    if (previousResult != null) {
      final preserved = _matchingViewIndex(order, previousResult);
      if (preserved != null) {
        _list.selectedIndex = preserved;
        return;
      }
    }

    final selectedIndex = _list.selectedIndex;
    _list.selectedIndex = selectedIndex == null
        ? 0
        : selectedIndex.clamp(0, order.length - 1);
  }

  void _move(int delta) {
    final order = _currentOrder;
    if (order.isEmpty) return;
    final current = _list.selectedIndex ?? 0;
    _list.selectedIndex = (current + delta).clamp(0, order.length - 1);
  }

  void _activateSelected() {
    final selected = _selectedResult(_currentOrder);
    if (selected == null || !selected.result.enabled) return;
    widget.onActivate?.call(selected.result, selected.sourceIndex);
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection) return;
    final selected = _selectedResult(_currentOrder);
    if (selected == null) return;
    final text = exportSearchResult(
      selected.result,
      options: widget.copyOptions,
    );
    final report = await Clipboard.instance.writeWithReport(
      text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    widget.onCopy?.call(
      SearchPanelCopyResult(
        resultIndex: selected.sourceIndex,
        viewIndex: selected.viewIndex,
        result: selected.result,
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _handlePanelSemanticAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
        _queryFocusNode.requestFocus();
        return;
      case SemanticAction.submit:
        _activateSelected();
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  Future<void> _activateResultAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _list.selectedIndex = viewIndex;
    _activateSelected();
  }

  Future<void> _copyResultAt(int viewIndex) async {
    final order = _currentOrder;
    if (viewIndex < 0 || viewIndex >= order.length) return;
    _list.selectedIndex = viewIndex;
    await _copySelection();
  }

  _SelectedSearchResult? _selectedResult(List<int> order) {
    return _selectedResultFor(widget.results, order);
  }

  _SelectedSearchResult? _selectedResultFor(
    List<SearchResult> results,
    List<int> order,
  ) {
    if (order.isEmpty) return null;
    final selectedIndex = _list.selectedIndex;
    if (selectedIndex == null) return null;
    final viewIndex = selectedIndex.clamp(0, order.length - 1);
    final sourceIndex = order[viewIndex];
    return _SelectedSearchResult(
      viewIndex: viewIndex,
      sourceIndex: sourceIndex,
      result: results[sourceIndex],
    );
  }

  int? _matchingViewIndex(List<int> order, SearchResult previousResult) {
    for (var viewIndex = 0; viewIndex < order.length; viewIndex++) {
      final result = widget.results[order[viewIndex]];
      if (_sameSearchResultIdentity(result, previousResult)) {
        return viewIndex;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _query.removeListener(_onQueryChange);
    if (_ownsQuery) _query.dispose();
    _list.removeListener(_onListChange);
    if (_ownsList) _list.dispose();
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
    final visibleRange = _list.visibleRange;
    final selected = _selectedResult(order);
    final copyEnabled = widget.copySelection && selected != null;
    final canActivate = widget.onActivate != null;
    final panelFocused = _queryFocusNode.hasFocus || _resultsFocusNode.hasFocus;

    final Widget listArea = order.isEmpty
        ? Text(
            _query.text.trim().isEmpty
                ? widget.placeholder
                : 'No matching results',
          )
        : ListView.builder(
            controller: _list,
            focusNode: _resultsFocusNode,
            itemCount: order.length,
            selectionActive: panelFocused,
            onSelect: (_) => _activateSelected(),
            itemBuilder: (context, viewIndex, activeSelected) {
              final sourceIndex = order[viewIndex];
              final selected = viewIndex == _list.selectedIndex;
              return _SearchResultRow(
                result: widget.results[sourceIndex],
                sourceIndex: sourceIndex,
                viewIndex: viewIndex,
                selected: selected,
                activeSelection: activeSelected,
                copyEnabled: copyEnabled,
                canActivate: canActivate,
                onActivate: () => _activateResultAt(viewIndex),
                onCopy: () => _copyResultAt(viewIndex),
              );
            },
          );

    Widget panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextInput(
          controller: _query,
          focusNode: _queryFocusNode,
          placeholder: widget.placeholder,
          autofocus: widget.autofocus,
          onSubmit: (_) => _activateSelected(),
        ),
        const SizedBox(height: 1),
        if (widget.fillHeight)
          Expanded(child: listArea)
        else
          SizedBox(height: visible, child: listArea),
      ],
    );

    panel = SizedBox(width: widget.width, child: panel);

    if (copyEnabled) {
      panel = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy search result',
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
        role: SemanticRole.region,
        label: widget.label,
        value: _query.text,
        focused: _queryFocusNode.hasFocus || _resultsFocusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          if (canActivate) SemanticAction.submit,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handlePanelSemanticAction,
        state: SemanticState({
          'filterText': _query.text,
          'collectionRowCount': order.length,
          'totalResultCount': widget.results.length,
          'filteredResultCount': order.length,
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null && order.isNotEmpty) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          if (_list.selectedIndex != null) 'selectedIndex': _list.selectedIndex,
          if (selected != null) ..._selectedResultState(selected.result),
        }),
        child: panel,
      ),
    );
  }
}

final class _SelectedSearchResult {
  const _SelectedSearchResult({
    required this.viewIndex,
    required this.sourceIndex,
    required this.result,
  });

  final int viewIndex;
  final int sourceIndex;
  final SearchResult result;
}

bool _sameSearchResultIdentity(SearchResult a, SearchResult b) {
  if (identical(a, b)) return true;
  if (a.id != null || b.id != null) return a.id == b.id;
  return a.title == b.title &&
      a.subtitle == b.subtitle &&
      a.category == b.category &&
      a.source == b.source &&
      a.detail == b.detail;
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.result,
    required this.sourceIndex,
    required this.viewIndex,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.canActivate,
    required this.onActivate,
    required this.onCopy,
  });

  final SearchResult result;
  final int sourceIndex;
  final int viewIndex;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final bool canActivate;
  final Future<void> Function() onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final title = _sanitizeSearchText(result.title);
    final subtitle = _sanitizeOptionalSearchText(result.subtitle);
    final category = _sanitizeOptionalSearchText(result.category);
    final source = _sanitizeOptionalSearchText(result.source);
    final detail = _sanitizeOptionalSearchText(result.detail);
    final rowText = _rowText(
      title: title,
      subtitle: subtitle,
      category: category,
      source: source,
      activeSelection: activeSelection,
    );
    final style = _searchResultStyle(
      Theme.of(context),
      selected: selected,
      activeSelection: activeSelection,
      enabled: result.enabled,
    );
    return Semantics(
      role: SemanticRole.listItem,
      label: title,
      value: subtitle ?? detail,
      hint: detail,
      selected: selected,
      enabled: result.enabled,
      actions: {
        if (result.enabled && canActivate) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            if (result.enabled && canActivate) await onActivate();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ...result.metadata,
        'rowIndex': sourceIndex,
        'viewIndex': viewIndex,
        'rowKey': ?result.id,
        'resultCategory': ?category,
        'resultSource': ?source,
        'outputSanitized': _resultWasSanitized(result),
      }),
      child: Text(rowText, style: style),
    );
  }
}

String _rowText({
  required String title,
  required String? subtitle,
  required String? category,
  required String? source,
  required bool activeSelection,
}) {
  final meta = <String>[
    if (category != null && category.isNotEmpty) category,
    if (source != null && source.isNotEmpty) source,
    if (subtitle != null && subtitle.isNotEmpty) subtitle,
  ];
  final prefix = activeSelection ? '> ' : '  ';
  if (meta.isEmpty) return '$prefix$title';
  return '$prefix$title  ${meta.join('  ')}';
}

Map<String, Object?> _selectedResultState(SearchResult result) {
  return <String, Object?>{
    if (result.id != null) 'selectedKey': result.id,
    if (result.category != null)
      'selectedCategory': _sanitizeSearchText(result.category!),
    if (result.source != null)
      'selectedSource': _sanitizeSearchText(result.source!),
  };
}

enum _SearchResultRank { exact, prefix, contains, fuzzy }

_SearchResultRank? _searchResultRank(_SearchResultEntry entry, String query) {
  for (final field in entry.searchFields) {
    if (field == query) return _SearchResultRank.exact;
  }
  for (final field in entry.searchFields) {
    if (field.startsWith(query)) return _SearchResultRank.prefix;
  }
  if (entry.searchText.contains(query)) return _SearchResultRank.contains;
  if (_isSubsequence(query, entry.searchText)) return _SearchResultRank.fuzzy;
  return null;
}

List<String> _searchResultFields(SearchResult result) {
  return [
        if (result.id != null) result.id.toString(),
        result.title,
        if (result.subtitle != null) result.subtitle!,
        if (result.category != null) result.category!,
        if (result.source != null) result.source!,
        if (result.detail != null) result.detail!,
        for (final value in result.metadata.values)
          if (value != null) value.toString(),
      ]
      .map(_sanitizeSearchText)
      .map((value) => value.toLowerCase())
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
}

final class _SearchResultEntry {
  _SearchResultEntry({
    required this.sourceIndex,
    required this.result,
    required this.searchFields,
  }) : searchText = searchFields.join(' ');

  final int sourceIndex;
  final SearchResult result;
  final List<String> searchFields;
  final String searchText;
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

String? _sanitizeOptionalSearchText(String? text) {
  if (text == null) return null;
  return _sanitizeSearchText(text);
}

final _searchLineBreakPattern = RegExp(r'[\r\n\t]');

String _sanitizeSearchText(String text) {
  return sanitizeForDisplay(text.replaceAll(_searchLineBreakPattern, ' '));
}

bool _resultWasSanitized(SearchResult result) {
  return result.title != _sanitizeSearchText(result.title) ||
      (result.subtitle != null &&
          result.subtitle != _sanitizeSearchText(result.subtitle!)) ||
      (result.category != null &&
          result.category != _sanitizeSearchText(result.category!)) ||
      (result.source != null &&
          result.source != _sanitizeSearchText(result.source!)) ||
      (result.detail != null &&
          result.detail != _sanitizeSearchText(result.detail!));
}

CellStyle _searchResultStyle(
  ThemeData theme, {
  required bool selected,
  required bool activeSelection,
  required bool enabled,
}) {
  final style = activeSelection
      ? theme.selectionStyle
      : selected
      ? theme.mutedStyle
      : CellStyle.empty;
  return enabled ? style : style.merge(const CellStyle(dim: true));
}
