import 'dart:async' show unawaited;
import 'dart:typed_data' show Uint32List;

import 'package:fleury/fleury_host.dart';

import 'component_theme.dart';
import 'data_table.dart' show DataTableColumn, DataTableExportFormat;
import 'table.dart' show FixedColumnWidth, FlexColumnWidth;

/// One durable node in a [TreeTable].
final class TreeTableNode<T> {
  const TreeTableNode({
    required this.key,
    required this.label,
    this.value,
    this.cells = const <String, String>{},
    this.children = const [],
    this.metadata = const <String, Object?>{},
  });

  /// Stable row identity used by expansion, selection, copy, and semantics.
  final Object key;

  /// Text rendered in the tree column.
  final String label;

  /// Optional app payload.
  final T? value;

  /// Optional column values used when no [TreeTable.cellBuilder] is supplied.
  final Map<String, String> cells;

  final List<TreeTableNode<T>> children;
  final Map<String, Object?> metadata;

  bool get isBranch => children.isNotEmpty;
}

/// A visible flattened row in a [TreeTable].
final class TreeTableRow<T> {
  const TreeTableRow({
    required this.node,
    required this.depth,
    required this.path,
    this.parentKey,
  });

  final TreeTableNode<T> node;
  final int depth;
  final String path;
  final Object? parentKey;

  Object get key => node.key;
}

/// Builds a column value for one tree-table node.
typedef TreeTableCellBuilder<T> =
    String Function(TreeTableNode<T> node, String columnId);

/// Matching behavior for [TreeTableFilterDescriptor].
enum TreeTableFilterMode {
  /// Case-aware contains plus subsequence matching.
  fuzzy,

  /// Match a complete sanitized token, useful for large ID/path/symbol lookup.
  exactToken,

  /// Match a sanitized token prefix, useful for indexed ID/path/symbol
  /// typeahead without scanning every row.
  prefixToken,
}

/// Filter applied to [TreeTable] source nodes.
final class TreeTableFilterDescriptor {
  const TreeTableFilterDescriptor({
    this.query = '',
    this.columnIds,
    this.caseSensitive = false,
    this.mode = TreeTableFilterMode.fuzzy,
  });

  final String query;
  final Set<String>? columnIds;
  final bool caseSensitive;
  final TreeTableFilterMode mode;

  bool get isEmpty => query.trim().isEmpty;
}

/// Precomputed searchable text for a large [TreeTable].
///
/// Small trees can rely on [buildTreeTableRows] scanning nodes directly. Large
/// retained hierarchies should build one search index when the data changes and
/// pass it to [TreeTable.searchIndex] or [buildTreeTableRows.searchIndex] so
/// repeated filter queries do not rebuild and sanitize every searchable field.
final class TreeTableSearchIndex<T> {
  TreeTableSearchIndex._({
    required List<_TreeTableSearchEntry<T>> entries,
    required Map<String, List<int>> tokenIndex,
    required List<String> sortedTokens,
    required Map<String, int> columnIndexes,
    required this.treeColumnId,
    required String textBlob,
    required Uint32List spans,
    required List<DataTableColumn> columns,
    required TreeTableCellBuilder<T>? cellBuilder,
  }) : _entries = entries,
       _tokenIndex = tokenIndex,
       _sortedTokens = sortedTokens,
       _columnIndexes = columnIndexes,
       _textBlob = textBlob,
       _spans = spans,
       _columns = columns,
       _cellBuilder = cellBuilder;

  factory TreeTableSearchIndex.build({
    required List<TreeTableNode<T>> roots,
    required List<DataTableColumn> columns,
    String? treeColumnId,
    TreeTableCellBuilder<T>? cellBuilder,
  }) {
    final builder = _TreeTableIndexBuilder<T>(
      columns: columns,
      treeColumnId: treeColumnId ?? _firstColumnId(columns),
      cellBuilder: cellBuilder,
      expectedRows: _countTreeTableNodes(roots),
    );

    void visit(TreeTableNode<T> node, int depth, int ordinal, int? parent) {
      final index = builder.addNode(
        node,
        depth: depth,
        ordinal: ordinal,
        parentIndex: parent,
      );
      for (var i = 0; i < node.children.length; i++) {
        visit(node.children[i], depth + 1, i, index);
      }
    }

    for (var i = 0; i < roots.length; i++) {
      visit(roots[i], 0, i, null);
    }
    return builder.finish();
  }

  /// Builds a [TreeTableSearchIndex] cooperatively under [context].
  ///
  /// This preserves the same row order and token semantics as [build], while
  /// allowing large hierarchy indexing to report progress, observe
  /// cancellation, and yield between batches.
  static Future<TreeTableSearchIndex<T>> buildCooperatively<T>({
    required List<TreeTableNode<T>> roots,
    required List<DataTableColumn> columns,
    required TaskContext context,
    String? treeColumnId,
    TreeTableCellBuilder<T>? cellBuilder,
    TaskYieldPolicy yieldPolicy = const TaskYieldPolicy(),
    String progressLabel = 'indexing tree',
  }) async {
    final builder = _TreeTableIndexBuilder<T>(
      columns: columns,
      treeColumnId: treeColumnId ?? _firstColumnId(columns),
      cellBuilder: cellBuilder,
    );
    final stack = <_TreeTableBuildFrame<T>>[];

    for (var i = roots.length - 1; i >= 0; i--) {
      stack.add(
        _TreeTableBuildFrame<T>(
          node: roots[i],
          depth: 0,
          ordinal: i,
          parentIndex: null,
        ),
      );
    }

    final checkpoint = yieldPolicy.start(context);
    while (stack.isNotEmpty) {
      final frame = stack.removeLast();
      final index = builder.addNode(
        frame.node,
        depth: frame.depth,
        ordinal: frame.ordinal,
        parentIndex: frame.parentIndex,
      );
      for (var i = frame.node.children.length - 1; i >= 0; i--) {
        stack.add(
          _TreeTableBuildFrame<T>(
            node: frame.node.children[i],
            depth: frame.depth + 1,
            ordinal: i,
            parentIndex: index,
          ),
        );
      }
      await checkpoint.tick(
        current: builder.length,
        label: '$progressLabel ${builder.length} rows',
      );
    }

    context.reportProgress(
      current: builder.length,
      total: builder.length,
      label: '$progressLabel complete',
    );
    return builder.finish();
  }

  final List<_TreeTableSearchEntry<T>> _entries;
  final Map<String, List<int>> _tokenIndex;
  final List<String> _sortedTokens;
  final Map<String, int> _columnIndexes;

  /// All searchable text, lowercase and sanitized, one region per row
  /// terminated by a newline (which sanitization removes from content, so
  /// in-range matches cannot cross rows). The index retains this ONE shared
  /// string plus integer spans instead of per-row text and row objects —
  /// at 100k rows that is the difference between ~60 MiB and ~25 MiB of
  /// index overhead.
  final String _textBlob;

  /// Per-row `[start, end)` offsets into [_textBlob]. Slot 0 is the row's
  /// full joined text, slot 1 the key, slots `2..2+N-1` the N columns, and
  /// slot `2+N` the metadata. Empty fields store `[0, 0)`.
  final Uint32List _spans;

  final List<DataTableColumn> _columns;
  final TreeTableCellBuilder<T>? _cellBuilder;

  /// Tree column used when this index was built.
  final String treeColumnId;

  /// Number of indexed tree rows, including descendants hidden by expansion.
  int get rowCount => _entries.length;

  int get _spanStride => (3 + _columns.length) * 2;

  List<TreeTableRow<T>> filter(TreeTableFilterDescriptor filter) {
    if (filter.isEmpty) {
      final paths = <int, String>{};
      return List<TreeTableRow<T>>.unmodifiable([
        for (var i = 0; i < _entries.length; i++) _rowAt(i, paths),
      ]);
    }
    final sanitizedQuery = _sanitizeTreeTableText(filter.query.trim());
    final query = filter.caseSensitive
        ? sanitizedQuery
        : sanitizedQuery.toLowerCase();
    if (!filter.caseSensitive && filter.columnIds == null) {
      switch (filter.mode) {
        case TreeTableFilterMode.exactToken:
          final exactTokenMatches = _tokenIndex[query];
          return exactTokenMatches == null
              ? const []
              : _rowsWithAncestors(exactTokenMatches);
        case TreeTableFilterMode.prefixToken:
          return _rowsWithAncestors(_tokenPrefixMatches(query));
        case TreeTableFilterMode.fuzzy:
          break;
      }
    }
    final matches = <int>[];
    for (var i = 0; i < _entries.length; i++) {
      if (_entryMatches(i, filter, query)) matches.add(i);
    }
    return _rowsWithAncestors(matches);
  }

  Iterable<int> _tokenPrefixMatches(String query) sync* {
    if (query.isEmpty) {
      for (var i = 0; i < _entries.length; i++) {
        yield i;
      }
      return;
    }
    var index = _lowerBoundToken(query);
    while (index < _sortedTokens.length) {
      final token = _sortedTokens[index];
      if (!token.startsWith(query)) break;
      yield* _tokenIndex[token]!;
      index += 1;
    }
  }

  int _lowerBoundToken(String query) {
    var low = 0;
    var high = _sortedTokens.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (_sortedTokens[mid].compareTo(query) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  List<TreeTableRow<T>> _rowsWithAncestors(Iterable<int> matches) {
    final included = <int>{};
    for (final index in matches) {
      var current = index;
      while (true) {
        if (!included.add(current)) break;
        final parent = _entries[current].parentIndex;
        if (parent == null) break;
        current = parent;
      }
    }
    if (included.isEmpty) return const [];
    final paths = <int, String>{};
    return List<TreeTableRow<T>>.unmodifiable([
      for (var i = 0; i < _entries.length; i++)
        if (included.contains(i)) _rowAt(i, paths),
    ]);
  }

  /// Materializes the row for [index]. Rows are not retained by the index;
  /// they are rebuilt for result sets only. Ancestor paths memoize into
  /// [paths] — callers iterate ascending, and entries are preorder, so an
  /// included row's parent is already memoized; [_pathOf] covers the rest.
  TreeTableRow<T> _rowAt(int index, Map<int, String> paths) {
    final entry = _entries[index];
    final parent = entry.parentIndex;
    final path = parent == null
        ? '${entry.ordinal}'
        : '${paths[parent] ?? _pathOf(parent, paths)}.${entry.ordinal}';
    paths[index] = path;
    return TreeTableRow<T>(
      node: entry.node,
      depth: entry.depth,
      path: path,
      parentKey: parent == null ? null : _entries[parent].node.key,
    );
  }

  String _pathOf(int index, Map<int, String> paths) {
    final memoized = paths[index];
    if (memoized != null) return memoized;
    final entry = _entries[index];
    final parent = entry.parentIndex;
    final path = parent == null
        ? '${entry.ordinal}'
        : '${_pathOf(parent, paths)}.${entry.ordinal}';
    paths[index] = path;
    return path;
  }

  bool _entryMatches(
    int index,
    TreeTableFilterDescriptor filter,
    String query,
  ) {
    if (query.isEmpty) return true;
    final base = index * _spanStride;
    final columnIds = filter.columnIds;
    if (columnIds == null) {
      if (!filter.caseSensitive) {
        final from = _spans[base];
        final to = _spans[base + 1];
        return switch (filter.mode) {
          TreeTableFilterMode.exactToken => _rangeContainsToken(
            _textBlob,
            from,
            to,
            query,
          ),
          TreeTableFilterMode.prefixToken => _rangeContainsTokenPrefix(
            _textBlob,
            from,
            to,
            query,
          ),
          TreeTableFilterMode.fuzzy =>
            _rangeContains(_textBlob, from, to, query) ||
                _rangeIsSubsequence(query, _textBlob, from, to),
        };
      }
      // Original-case text is not retained; derive it for this scan.
      final texts = _entryTexts(index);
      final all = _joinTreeTableFields([
        texts.keyText,
        ...texts.columnText,
        texts.metadataText,
      ]);
      return _matchesTreeTableQuery(all, query, filter.mode);
    }
    final fields = <String>[];
    if (!filter.caseSensitive) {
      fields.add(_spanText(base, 1));
      fields.add(_spanText(base, 2 + _columns.length));
      for (final id in columnIds) {
        final column = _columnIndexes[id];
        fields.add(column == null ? '' : _spanText(base, 2 + column));
      }
    } else {
      final texts = _entryTexts(index);
      fields.add(texts.keyText);
      fields.add(texts.metadataText);
      for (final id in columnIds) {
        final column = _columnIndexes[id];
        fields.add(column == null ? '' : texts.columnText[column]);
      }
    }
    return _matchesTreeTableQuery(fields.join(' '), query, filter.mode);
  }

  String _spanText(int base, int slot) {
    final start = _spans[base + slot * 2];
    final end = _spans[base + slot * 2 + 1];
    return start == end ? '' : _textBlob.substring(start, end);
  }

  ({String keyText, String metadataText, List<String> columnText}) _entryTexts(
    int index,
  ) => _treeTableEntryTexts(
    _entries[index].node,
    _columns,
    treeColumnId,
    _cellBuilder,
  );
}

/// Accumulates entries, token postings, and the shared text blob for both
/// [TreeTableSearchIndex.build] paths.
final class _TreeTableIndexBuilder<T> {
  /// [expectedRows] sizes the span buffer exactly (the eager build path
  /// pre-counts nodes), keeping peak memory at the retained size instead of
  /// a growable list plus a final copy — at 100k rows that transient was
  /// ~19 MiB of peak RSS.
  _TreeTableIndexBuilder({
    required this.columns,
    required this.treeColumnId,
    required this.cellBuilder,
    int expectedRows = 0,
  }) : columnIds = [for (final column in columns) column.id],
       _spans = Uint32List(
         (expectedRows > 0 ? expectedRows : 16) * (3 + columns.length) * 2,
       );

  final List<DataTableColumn> columns;
  final String treeColumnId;
  final TreeTableCellBuilder<T>? cellBuilder;
  final List<String> columnIds;

  final List<_TreeTableSearchEntry<T>> _entries = [];
  final Map<String, List<int>> _tokenIndex = {};
  final StringBuffer _blob = StringBuffer();
  Uint32List _spans;
  int _spanCount = 0;

  int get length => _entries.length;

  void _spanAdd(int value) {
    if (_spanCount == _spans.length) {
      final grown = Uint32List(_spans.length * 2);
      grown.setRange(0, _spanCount, _spans);
      _spans = grown;
    }
    _spans[_spanCount++] = value;
  }

  int addNode(
    TreeTableNode<T> node, {
    required int depth,
    required int ordinal,
    required int? parentIndex,
  }) {
    final index = _entries.length;
    _entries.add(
      _TreeTableSearchEntry<T>(
        node: node,
        parentIndex: parentIndex,
        depth: depth,
        ordinal: ordinal,
      ),
    );
    final texts = _treeTableEntryTexts(
      node,
      columns,
      treeColumnId,
      cellBuilder,
    );
    final spanBase = _spanCount;
    final allStart = _blob.length;
    _spanAdd(0);
    _spanAdd(0);

    void appendField(String text) {
      final lower = _lowerTreeTableField(text);
      if (lower.isEmpty) {
        _spanAdd(0);
        _spanAdd(0);
        return;
      }
      if (_blob.length > allStart) _blob.write(' ');
      final start = _blob.length;
      _blob.write(lower);
      _spanAdd(start);
      _spanAdd(_blob.length);
      _addTokens(lower, index);
    }

    appendField(texts.keyText);
    for (final text in texts.columnText) {
      appendField(text);
    }
    appendField(texts.metadataText);
    _spans[spanBase] = allStart;
    _spans[spanBase + 1] = _blob.length;
    _blob.write('\n');
    return index;
  }

  /// Direct-loop tokenizer (no generator): called once per field per node,
  /// so iterator allocation would show up at 100k-row build scale.
  void _addTokens(String lower, int index) {
    var start = -1;
    for (var i = 0; i < lower.length; i++) {
      if (_isTreeTableTokenCodeUnit(lower.codeUnitAt(i))) {
        if (start < 0) start = i;
        continue;
      }
      if (start >= 0) {
        (_tokenIndex[lower.substring(start, i)] ??= <int>[]).add(index);
        start = -1;
      }
    }
    if (start >= 0) {
      (_tokenIndex[lower.substring(start)] ??= <int>[]).add(index);
    }
  }

  TreeTableSearchIndex<T> finish() {
    final sortedTokens = _tokenIndex.keys.toList(growable: false)..sort();
    return TreeTableSearchIndex<T>._(
      entries: _entries,
      tokenIndex: _tokenIndex,
      sortedTokens: List<String>.unmodifiable(sortedTokens),
      columnIndexes: {
        for (var i = 0; i < columnIds.length; i++) columnIds[i]: i,
      },
      treeColumnId: treeColumnId,
      textBlob: _blob.toString(),
      spans: _spanCount == _spans.length
          ? _spans
          : (Uint32List(_spanCount)..setRange(0, _spanCount, _spans)),
      columns: columns,
      cellBuilder: cellBuilder,
    );
  }
}

int _countTreeTableNodes<T>(List<TreeTableNode<T>> roots) {
  var count = 0;
  void visit(TreeTableNode<T> node) {
    count++;
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final root in roots) {
    visit(root);
  }
  return count;
}

final class _TreeTableBuildFrame<T> {
  const _TreeTableBuildFrame({
    required this.node,
    required this.depth,
    required this.ordinal,
    required this.parentIndex,
  });

  final TreeTableNode<T> node;
  final int depth;
  final int ordinal;
  final int? parentIndex;
}

/// One indexed row: just tree structure. Searchable text lives in the
/// index's shared blob; [TreeTableRow]s are materialized per result set.
final class _TreeTableSearchEntry<T> {
  const _TreeTableSearchEntry({
    required this.node,
    required this.parentIndex,
    required this.depth,
    required this.ordinal,
  });

  final TreeTableNode<T> node;
  final int? parentIndex;
  final int depth;
  final int ordinal;
}

/// Sanitized searchable text for one node, in indexed-column order.
({String keyText, String metadataText, List<String> columnText})
_treeTableEntryTexts<T>(
  TreeTableNode<T> node,
  List<DataTableColumn> columns,
  String treeColumnId,
  TreeTableCellBuilder<T>? cellBuilder,
) {
  final keyText = _sanitizeTreeTableText(node.key.toString());
  final metadataBuffer = StringBuffer();
  for (final value in node.metadata.values) {
    if (value == null) continue;
    final sanitized = _sanitizeTreeTableText(value.toString());
    if (sanitized.isEmpty) continue;
    if (metadataBuffer.length > 0) metadataBuffer.write(' ');
    metadataBuffer.write(sanitized);
  }
  final columnText = List<String>.filled(columns.length, '', growable: false);
  for (var i = 0; i < columns.length; i++) {
    final column = columns[i];
    final raw = column.id == treeColumnId
        ? node.label
        : cellBuilder?.call(node, column.id) ?? node.cells[column.id] ?? '';
    columnText[i] = _sanitizeTreeTableText(raw);
  }
  return (
    keyText: keyText,
    metadataText: metadataBuffer.toString(),
    columnText: columnText,
  );
}

bool _rangeContains(String text, int from, int to, String query) {
  if (query.isEmpty) return true;
  // No String.indexOf here: it has no end bound, so a non-matching row
  // would scan the rest of the shared blob. startsWith early-exits on the
  // first mismatched character, keeping this O(range) in practice.
  final last = to - query.length;
  for (var i = from; i <= last; i++) {
    if (text.startsWith(query, i)) return true;
  }
  return false;
}

bool _rangeIsSubsequence(String needle, String text, int from, int to) {
  var i = 0;
  for (var j = from; j < to && i < needle.length; j++) {
    if (text.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
  }
  return i == needle.length;
}

bool _rangeContainsToken(String text, int from, int to, String query) {
  if (query.isEmpty) return true;
  var start = -1;
  for (var i = from; i < to; i++) {
    if (_isTreeTableTokenCodeUnit(text.codeUnitAt(i))) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      if (i - start == query.length && text.startsWith(query, start)) {
        return true;
      }
      start = -1;
    }
  }
  return start >= 0 &&
      to - start == query.length &&
      text.startsWith(query, start);
}

bool _rangeContainsTokenPrefix(String text, int from, int to, String query) {
  if (query.isEmpty) return true;
  var start = -1;
  for (var i = from; i < to; i++) {
    if (_isTreeTableTokenCodeUnit(text.codeUnitAt(i))) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      if (i - start >= query.length && text.startsWith(query, start)) {
        return true;
      }
      start = -1;
    }
  }
  return start >= 0 &&
      to - start >= query.length &&
      text.startsWith(query, start);
}

String _lowerTreeTableField(String value) =>
    value.isEmpty ? '' : value.toLowerCase();

String _joinTreeTableFields(Iterable<String> fields) {
  final buffer = StringBuffer();
  for (final field in fields) {
    if (field.isEmpty) continue;
    if (buffer.length > 0) buffer.write(' ');
    buffer.write(field);
  }
  return buffer.toString();
}

/// Export behavior for [TreeTable] rows.
final class TreeTableExportOptions {
  const TreeTableExportOptions({
    this.format = DataTableExportFormat.tsv,
    this.includeHeader = true,
    this.includeTreeIndent = true,
    this.startRow = 0,
    this.maxRows,
  }) : assert(startRow >= 0),
       assert(maxRows == null || maxRows >= 0);

  final DataTableExportFormat format;
  final bool includeHeader;
  final bool includeTreeIndent;
  final int startRow;
  final int? maxRows;
}

/// Result of exporting [TreeTable] rows.
final class TreeTableExportResult {
  const TreeTableExportResult({
    required this.text,
    required this.rowCount,
    required this.columnCount,
    required this.startRow,
    required this.format,
    required this.truncated,
  });

  final String text;
  final int rowCount;
  final int columnCount;
  final int startRow;
  final DataTableExportFormat format;
  final bool truncated;
}

/// Clipboard behavior for [TreeTable] selected-row copy.
final class TreeTableCopyOptions {
  const TreeTableCopyOptions({
    this.format = DataTableExportFormat.tsv,
    this.includeHeader = true,
    this.includeTreeIndent = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final DataTableExportFormat format;
  final bool includeHeader;
  final bool includeTreeIndent;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [TreeTable] copies the selected row.
final class TreeTableCopyResult<T> {
  const TreeTableCopyResult({
    required this.rowIndex,
    required this.rowKey,
    required this.row,
    required this.export,
    required this.report,
  });

  final int rowIndex;
  final Object rowKey;
  final TreeTableRow<T> row;
  final TreeTableExportResult export;
  final ClipboardWriteReport report;

  String get text => export.text;
}

/// Controller for [TreeTable] expansion, selection, and visible range.
class TreeTableController extends ChangeNotifier {
  TreeTableController({
    int? selectedIndex,
    Iterable<Object> expandedKeys = const <Object>[],
  }) : _list = ListController(selectedIndex: selectedIndex ?? 0),
       _expandedKeys = Set<Object>.of(expandedKeys) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  final Set<Object> _expandedKeys;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  Set<Object> get expandedKeys => Set<Object>.unmodifiable(_expandedKeys);

  bool isExpanded(Object key) => _expandedKeys.contains(key);

  void expand(Object key) {
    _checkNotDisposed();
    if (!_expandedKeys.add(key)) return;
    notifyListeners();
  }

  void collapse(Object key) {
    _checkNotDisposed();
    if (!_expandedKeys.remove(key)) return;
    notifyListeners();
  }

  void toggle(Object key) {
    _checkNotDisposed();
    if (!_expandedKeys.remove(key)) {
      _expandedKeys.add(key);
    }
    notifyListeners();
  }

  void collapseAll() {
    _checkNotDisposed();
    if (_expandedKeys.isEmpty) return;
    _expandedKeys.clear();
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TreeTableController has been disposed.');
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

/// Builds visible rows for a [TreeTable].
///
/// Without a filter, only descendants of expanded nodes are returned. With a
/// filter, matching rows and their ancestors are returned regardless of current
/// expansion so collapsed matches remain discoverable.
List<TreeTableRow<T>> buildTreeTableRows<T>({
  required List<TreeTableNode<T>> roots,
  required List<DataTableColumn> columns,
  Set<Object> expandedKeys = const <Object>{},
  String? treeColumnId,
  TreeTableCellBuilder<T>? cellBuilder,
  TreeTableFilterDescriptor? filter,
  TreeTableSearchIndex<T>? searchIndex,
}) {
  final effectiveTreeColumnId = treeColumnId ?? _firstColumnId(columns);
  final effectiveFilter = filter ?? const TreeTableFilterDescriptor();
  if (effectiveFilter.isEmpty) {
    final rows = <TreeTableRow<T>>[];
    void visit(
      TreeTableNode<T> node,
      int depth,
      String path,
      Object? parentKey,
    ) {
      rows.add(
        TreeTableRow<T>(
          node: node,
          depth: depth,
          path: path,
          parentKey: parentKey,
        ),
      );
      if (!expandedKeys.contains(node.key)) return;
      for (var i = 0; i < node.children.length; i++) {
        visit(node.children[i], depth + 1, '$path.$i', node.key);
      }
    }

    for (var i = 0; i < roots.length; i++) {
      visit(roots[i], 0, '$i', null);
    }
    return List<TreeTableRow<T>>.unmodifiable(rows);
  }

  if (searchIndex != null) {
    return searchIndex.filter(effectiveFilter);
  }

  final query = effectiveFilter.caseSensitive
      ? _sanitizeTreeTableText(effectiveFilter.query.trim())
      : _sanitizeTreeTableText(effectiveFilter.query.trim()).toLowerCase();
  final rows = <TreeTableRow<T>>[];

  bool visitFiltered(
    TreeTableNode<T> node,
    int depth,
    String path,
    Object? parentKey,
  ) {
    final row = TreeTableRow<T>(
      node: node,
      depth: depth,
      path: path,
      parentKey: parentKey,
    );
    final childRows = <TreeTableRow<T>>[];
    var childMatched = false;
    for (var i = 0; i < node.children.length; i++) {
      final before = rows.length;
      if (visitFiltered(node.children[i], depth + 1, '$path.$i', node.key)) {
        childMatched = true;
        childRows.addAll(rows.sublist(before));
      }
      rows.removeRange(before, rows.length);
    }
    final matched = _rowMatchesFilter(
      row,
      columns,
      effectiveTreeColumnId,
      cellBuilder,
      effectiveFilter,
      query,
    );
    if (!matched && !childMatched) return false;
    rows.add(row);
    rows.addAll(childRows);
    return true;
  }

  for (var i = 0; i < roots.length; i++) {
    visitFiltered(roots[i], 0, '$i', null);
  }
  return List<TreeTableRow<T>>.unmodifiable(rows);
}

/// Exports tree-table rows as sanitized TSV/CSV.
TreeTableExportResult exportTreeTableRows<T>({
  required List<TreeTableRow<T>> rows,
  required List<DataTableColumn> columns,
  String? treeColumnId,
  TreeTableCellBuilder<T>? cellBuilder,
  TreeTableExportOptions options = const TreeTableExportOptions(),
}) {
  final start = options.startRow > rows.length ? rows.length : options.startRow;
  final available = rows.length - start;
  final limit = options.maxRows == null || options.maxRows! > available
      ? available
      : options.maxRows!;
  final output = StringBuffer();
  final delimiter = options.format == DataTableExportFormat.tsv ? '\t' : ',';

  void writeLine(List<String> fields) {
    if (output.isNotEmpty) output.write('\n');
    output.write(
      fields
          .map((field) => _encodeField(field, options.format))
          .join(delimiter),
    );
  }

  if (options.includeHeader) {
    writeLine([
      for (final column in columns) _sanitizeTreeTableText(column.title),
    ]);
  }
  final effectiveTreeColumnId = treeColumnId ?? _firstColumnId(columns);
  for (var offset = 0; offset < limit; offset++) {
    final row = rows[start + offset];
    writeLine([
      for (final column in columns)
        _cellText(
          row,
          column.id,
          effectiveTreeColumnId,
          cellBuilder,
          includeTreeIndent: options.includeTreeIndent,
          includeTreeMarker: false,
        ),
    ]);
  }

  return TreeTableExportResult(
    text: output.toString(),
    rowCount: limit,
    columnCount: columns.length,
    startRow: start,
    format: options.format,
    truncated: start + limit < rows.length,
  );
}

/// Hierarchical data table with expandable rows and semantic tree items.
class TreeTable<T> extends StatefulWidget {
  const TreeTable({
    super.key,
    required this.roots,
    required this.columns,
    this.treeColumnId,
    this.cellBuilder,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'Tree table',
    this.maxVisible = 12,
    this.filter,
    this.searchIndex,
    this.onSelect,
    this.copySelectedRow = true,
    this.copyOptions = const TreeTableCopyOptions(),
    this.onCopy,
    this.columnSpacing = 1,
    this.headerSeparator = true,
    this.separatorStyle,
    this.selectedStyle,
  }) : assert(maxVisible > 0),
       assert(columnSpacing >= 0);

  final List<TreeTableNode<T>> roots;
  final List<DataTableColumn> columns;
  final String? treeColumnId;
  final TreeTableCellBuilder<T>? cellBuilder;
  final TreeTableController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String label;
  final int maxVisible;
  final TreeTableFilterDescriptor? filter;
  final TreeTableSearchIndex<T>? searchIndex;
  final void Function(TreeTableRow<T> row)? onSelect;
  final bool copySelectedRow;
  final TreeTableCopyOptions copyOptions;
  final void Function(TreeTableCopyResult<T> result)? onCopy;
  final int columnSpacing;
  final bool headerSeparator;
  final CellStyle? separatorStyle;
  final CellStyle? selectedStyle;

  @override
  State<TreeTable<T>> createState() => _TreeTableState<T>();
}

class _TreeTableState<T> extends State<TreeTable<T>> {
  late TreeTableController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TreeTableController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TreeTable');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant TreeTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TreeTableController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TreeTable');
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

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  String get _treeColumnId =>
      widget.treeColumnId ?? _firstColumnId(widget.columns);

  List<TreeTableRow<T>> get _rows => buildTreeTableRows<T>(
    roots: widget.roots,
    columns: widget.columns,
    expandedKeys: _controller.expandedKeys,
    treeColumnId: _treeColumnId,
    cellBuilder: widget.cellBuilder,
    filter: widget.filter,
    searchIndex: widget.searchIndex,
  );

  TreeTableRow<T>? _selectedRow(List<TreeTableRow<T>> rows) {
    if (rows.isEmpty) return null;
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) return null;
    return rows[selectedIndex.clamp(0, rows.length - 1)];
  }

  int _selectedIndex(List<TreeTableRow<T>> rows) {
    if (rows.isEmpty) return 0;
    return (_controller.selectedIndex ?? 0).clamp(0, rows.length - 1);
  }

  void _activateSelected(List<TreeTableRow<T>> rows) {
    if (rows.isEmpty) return;
    final row = rows[_selectedIndex(rows)];
    if (row.node.isBranch) {
      _controller.toggle(row.key);
    } else {
      widget.onSelect?.call(row);
    }
  }

  void _openRow(List<TreeTableRow<T>> rows, int index) {
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    final row = rows[index];
    if (!row.node.isBranch) return;
    _controller.expand(row.key);
  }

  void _activateRow(List<TreeTableRow<T>> rows, int index) {
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    final row = rows[index];
    if (row.node.isBranch) {
      _controller.expand(row.key);
    } else {
      widget.onSelect?.call(row);
    }
  }

  Future<void> _copyRow(List<TreeTableRow<T>> rows, int index) async {
    if (index < 0 || index >= rows.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection(rows);
  }

  Future<void> _handleTreeAction(
    SemanticAction action,
    List<TreeTableRow<T>> rows,
  ) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.open:
        _openRow(rows, _selectedIndex(rows));
        return;
      case SemanticAction.copy:
        await _copySelection(rows);
        return;
      case _:
        return;
    }
  }

  KeyEventResult _expandOrEnter(List<TreeTableRow<T>> rows) {
    final row = _selectedRow(rows);
    if (row == null || !row.node.isBranch) return KeyEventResult.ignored;
    final index = _selectedIndex(rows);
    if (!_controller.isExpanded(row.key)) {
      _controller.expand(row.key);
      return KeyEventResult.handled;
    }
    if (index + 1 < rows.length && rows[index + 1].depth > row.depth) {
      _controller.selectedIndex = index + 1;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _collapseOrParent(List<TreeTableRow<T>> rows) {
    final row = _selectedRow(rows);
    if (row == null) return KeyEventResult.ignored;
    final index = _selectedIndex(rows);
    if (row.node.isBranch && _controller.isExpanded(row.key)) {
      _controller.collapse(row.key);
      return KeyEventResult.handled;
    }
    for (var i = index - 1; i >= 0; i--) {
      if (rows[i].depth < row.depth) {
        _controller.selectedIndex = i;
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copySelection(List<TreeTableRow<T>> rows) async {
    if (!widget.copySelectedRow || rows.isEmpty || widget.columns.isEmpty) {
      return;
    }
    final selectedIndex = _selectedIndex(rows);
    final export = exportTreeTableRows<T>(
      rows: rows,
      columns: widget.columns,
      treeColumnId: _treeColumnId,
      cellBuilder: widget.cellBuilder,
      options: TreeTableExportOptions(
        format: widget.copyOptions.format,
        includeHeader: widget.copyOptions.includeHeader,
        includeTreeIndent: widget.copyOptions.includeTreeIndent,
        startRow: selectedIndex,
        maxRows: 1,
      ),
    );
    final report = await Clipboard.instance.writeWithReport(
      export.text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    final row = rows[selectedIndex];
    widget.onCopy?.call(
      TreeTableCopyResult<T>(
        rowIndex: selectedIndex,
        rowKey: row.key,
        row: row,
        export: export,
        report: report,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final rows = _rows;
    final visible = rows.isEmpty
        ? 1
        : (rows.length > widget.maxVisible ? widget.maxVisible : rows.length);
    final selected = _selectedRow(rows);
    final visibleRange = _controller.visibleRange;
    final filter = widget.filter;
    final filterText = filter == null
        ? ''
        : _sanitizeTreeTableText(filter.query);
    final copyEnabled =
        widget.copySelectedRow && rows.isNotEmpty && widget.columns.isNotEmpty;
    final selectedStyle =
        widget.selectedStyle ?? widgetTheme.resolveDataSelected(theme);
    final separatorStyle =
        widget.separatorStyle ?? widgetTheme.resolveDataSeparator(theme);
    final emptyStyle = widgetTheme.resolveDataEmpty(theme);

    Widget list = rows.isEmpty
        ? Text('  (empty)', style: emptyStyle)
        : Focus(
            canRequestFocus: false,
            onKey: (event) => switch (event.keyCode) {
              KeyCode.arrowRight => _expandOrEnter(rows),
              KeyCode.arrowLeft => _collapseOrParent(rows),
              _ => KeyEventResult.ignored,
            },
            child: ListView.builder(
              controller: _controller._listController,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              itemCount: rows.length,
              onSelect: (_) => _activateSelected(rows),
              itemBuilder: (context, index, activeSelected) {
                final row = rows[index];
                final selected = index == _controller.selectedIndex;
                return _TreeTableRowWidget<T>(
                  row: row,
                  rowIndex: index,
                  columns: widget.columns,
                  treeColumnId: _treeColumnId,
                  cellBuilder: widget.cellBuilder,
                  selected: selected,
                  activeSelection: activeSelected,
                  expanded: _isVisiblyExpanded(rows, index),
                  selectedStyle: selectedStyle,
                  columnSpacing: widget.columnSpacing,
                  onSelectEnabled: widget.onSelect != null,
                  copyEnabled: copyEnabled,
                  onOpen: () => _openRow(rows, index),
                  onActivate: () => _activateRow(rows, index),
                  onCopy: () => _copyRow(rows, index),
                );
              },
            ),
          );

    list = SizedBox(height: visible, child: list);
    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy tree row',
            onEvent: (_) => unawaited(_copySelection(rows)),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.tree,
        label: widget.label,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (selected != null && selected.node.isBranch) SemanticAction.open,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: (action) => _handleTreeAction(action, rows),
        state: SemanticState({
          'collectionRowCount': rows.length,
          'collectionColumnCount': widget.columns.length,
          'rootCount': widget.roots.length,
          'expandedCount': _controller.expandedKeys.length,
          'treeColumnId': _treeColumnId,
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (filterText.isNotEmpty) 'filterText': filterText,
          if (filter != null) 'filterCaseSensitive': filter.caseSensitive,
          if (visibleRange != null && rows.isNotEmpty) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          if (_controller.selectedIndex != null)
            'selectedIndex': _controller.selectedIndex,
          if (selected != null) ...{
            'selectedKey': selected.key,
            'selectedDepth': selected.depth,
            'selectedIsBranch': selected.node.isBranch,
          },
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TreeTableLine(
              columns: widget.columns,
              columnSpacing: widget.columnSpacing,
              cells: [
                for (final column in widget.columns)
                  Text(
                    _sanitizeTreeTableText(column.title),
                    style: column.headerStyle,
                  ),
              ],
            ),
            if (widget.headerSeparator)
              Text(
                _separatorText(widget.columns, widget.columnSpacing),
                style: separatorStyle,
              ),
            list,
          ],
        ),
      ),
    );
  }

  bool _isVisiblyExpanded(List<TreeTableRow<T>> rows, int index) {
    final row = rows[index];
    if (!row.node.isBranch) return false;
    if (_controller.isExpanded(row.key)) return true;
    return index + 1 < rows.length && rows[index + 1].depth > row.depth;
  }
}

class _TreeTableRowWidget<T> extends StatelessWidget {
  const _TreeTableRowWidget({
    required this.row,
    required this.rowIndex,
    required this.columns,
    required this.treeColumnId,
    required this.cellBuilder,
    required this.selected,
    required this.activeSelection,
    required this.expanded,
    required this.selectedStyle,
    required this.columnSpacing,
    required this.onSelectEnabled,
    required this.copyEnabled,
    required this.onOpen,
    required this.onActivate,
    required this.onCopy,
  });

  final TreeTableRow<T> row;
  final int rowIndex;
  final List<DataTableColumn> columns;
  final String treeColumnId;
  final TreeTableCellBuilder<T>? cellBuilder;
  final bool selected;
  final bool activeSelection;
  final bool expanded;
  final CellStyle selectedStyle;
  final int columnSpacing;
  final bool onSelectEnabled;
  final bool copyEnabled;
  final void Function() onOpen;
  final void Function() onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final label = _sanitizeTreeTableText(row.node.label);
    return Semantics(
      role: SemanticRole.treeItem,
      label: label,
      value: row.key.toString(),
      selected: selected,
      enabled: true,
      actions: {
        if (row.node.isBranch) SemanticAction.open,
        if (!row.node.isBranch && onSelectEnabled) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.open:
            if (row.node.isBranch) onOpen();
            return;
          case SemanticAction.activate:
            if (!row.node.isBranch && onSelectEnabled) onActivate();
            return;
          case SemanticAction.copy:
            if (copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ...row.node.metadata,
        'rowIndex': rowIndex,
        'rowKey': row.key,
        'path': row.path,
        'depth': row.depth,
        'isBranch': row.node.isBranch,
        'expanded': expanded,
        'childCount': row.node.children.length,
        'outputSanitized': label != row.node.label,
      }),
      child: _TreeTableLine(
        columns: columns,
        columnSpacing: columnSpacing,
        cells: [
          for (var columnIndex = 0; columnIndex < columns.length; columnIndex++)
            _TreeTableCell<T>(
              row: row,
              rowIndex: rowIndex,
              column: columns[columnIndex],
              columnIndex: columnIndex,
              treeColumnId: treeColumnId,
              cellBuilder: cellBuilder,
              selected: selected,
              activeSelection: activeSelection,
              expanded: expanded,
              selectedStyle: selectedStyle,
            ),
        ],
      ),
    );
  }
}

class _TreeTableCell<T> extends StatelessWidget {
  const _TreeTableCell({
    required this.row,
    required this.rowIndex,
    required this.column,
    required this.columnIndex,
    required this.treeColumnId,
    required this.cellBuilder,
    required this.selected,
    required this.activeSelection,
    required this.expanded,
    required this.selectedStyle,
  });

  final TreeTableRow<T> row;
  final int rowIndex;
  final DataTableColumn column;
  final int columnIndex;
  final String treeColumnId;
  final TreeTableCellBuilder<T>? cellBuilder;
  final bool selected;
  final bool activeSelection;
  final bool expanded;
  final CellStyle selectedStyle;

  @override
  Widget build(BuildContext context) {
    final isTreeColumn = column.id == treeColumnId;
    final text = _cellText(
      row,
      column.id,
      treeColumnId,
      cellBuilder,
      includeTreeIndent: true,
      includeTreeMarker: true,
      expanded: expanded,
    );
    final style = activeSelection
        ? column.style.merge(selectedStyle)
        : selected
        ? column.style.merge(Theme.of(context).mutedStyle)
        : column.style;
    return Semantics(
      role: SemanticRole.tableCell,
      label: text,
      selected: selected && isTreeColumn,
      state: SemanticState({
        'rowIndex': rowIndex,
        'rowKey': row.key,
        'columnIndex': columnIndex,
        'columnId': column.id,
        'treeDepth': row.depth,
        'treeColumn': isTreeColumn,
        'outputSanitized': _cellWasSanitized(
          row,
          column.id,
          treeColumnId,
          cellBuilder,
        ),
      }),
      child: Text(text, style: style),
    );
  }
}

class _TreeTableLine extends StatelessWidget {
  const _TreeTableLine({
    required this.columns,
    required this.cells,
    required this.columnSpacing,
  });

  final List<DataTableColumn> columns;
  final List<Widget> cells;
  final int columnSpacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < columns.length; i++) {
      if (i > 0 && columnSpacing > 0) {
        children.add(SizedBox(width: columnSpacing));
      }
      children.add(_sizedCell(columns[i], cells[i]));
    }
    return Row(children: children);
  }
}

Widget _sizedCell(DataTableColumn column, Widget child) {
  final width = column.width;
  if (width is FixedColumnWidth) {
    return SizedBox(width: width.width, child: child);
  }
  if (width is FlexColumnWidth) {
    return Expanded(flex: width.flex, child: child);
  }
  return Flexible(child: child);
}

String _firstColumnId(List<DataTableColumn> columns) {
  return columns.isEmpty ? '' : columns.first.id;
}

String _cellText<T>(
  TreeTableRow<T> row,
  String columnId,
  String treeColumnId,
  TreeTableCellBuilder<T>? cellBuilder, {
  required bool includeTreeIndent,
  required bool includeTreeMarker,
  bool expanded = false,
}) {
  final raw = columnId == treeColumnId
      ? row.node.label
      : cellBuilder?.call(row.node, columnId) ?? row.node.cells[columnId] ?? '';
  final sanitized = _sanitizeTreeTableText(raw);
  if (columnId != treeColumnId || !includeTreeIndent) return sanitized;
  final marker = row.node.isBranch ? (expanded ? '▾ ' : '▸ ') : '  ';
  return '${'  ' * row.depth}${includeTreeMarker ? marker : ''}$sanitized';
}

bool _cellWasSanitized<T>(
  TreeTableRow<T> row,
  String columnId,
  String treeColumnId,
  TreeTableCellBuilder<T>? cellBuilder,
) {
  final raw = columnId == treeColumnId
      ? row.node.label
      : cellBuilder?.call(row.node, columnId) ?? row.node.cells[columnId] ?? '';
  return raw != _sanitizeTreeTableText(raw);
}

bool _rowMatchesFilter<T>(
  TreeTableRow<T> row,
  List<DataTableColumn> columns,
  String treeColumnId,
  TreeTableCellBuilder<T>? cellBuilder,
  TreeTableFilterDescriptor filter,
  String query,
) {
  if (query.isEmpty) return true;
  final columnIds = filter.columnIds;
  final fields = <String>[
    row.key.toString(),
    if (columnIds == null || columnIds.contains(treeColumnId)) row.node.label,
    for (final column in columns)
      if (columnIds == null || columnIds.contains(column.id))
        column.id == treeColumnId
            ? row.node.label
            : cellBuilder?.call(row.node, column.id) ??
                  row.node.cells[column.id] ??
                  '',
    for (final value in row.node.metadata.values)
      if (value != null) value.toString(),
  ];
  final text = fields.map(_sanitizeTreeTableText).join(' ');
  final hay = filter.caseSensitive ? text : text.toLowerCase();
  return _matchesTreeTableQuery(hay, query, filter.mode);
}

bool _matchesTreeTableQuery(
  String text,
  String query,
  TreeTableFilterMode mode,
) {
  return switch (mode) {
    TreeTableFilterMode.exactToken => _treeTableContainsSearchToken(
      text,
      query,
    ),
    TreeTableFilterMode.prefixToken => _treeTableContainsSearchTokenPrefix(
      text,
      query,
    ),
    TreeTableFilterMode.fuzzy =>
      text.contains(query) || _isSubsequence(query, text),
  };
}

bool _treeTableContainsSearchToken(String text, String query) {
  if (query.isEmpty) return true;
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    if (_isTreeTableTokenCodeUnit(text.codeUnitAt(i))) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      if (i - start == query.length && text.substring(start, i) == query) {
        return true;
      }
      start = -1;
    }
  }
  return start >= 0 &&
      text.length - start == query.length &&
      text.substring(start) == query;
}

bool _treeTableContainsSearchTokenPrefix(String text, String query) {
  if (query.isEmpty) return true;
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    if (_isTreeTableTokenCodeUnit(text.codeUnitAt(i))) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      if (text.substring(start, i).startsWith(query)) {
        return true;
      }
      start = -1;
    }
  }
  return start >= 0 && text.substring(start).startsWith(query);
}

bool _isTreeTableTokenCodeUnit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      codeUnit == 0x5f ||
      codeUnit == 0x3a ||
      codeUnit == 0x2d;
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

String _separatorText(List<DataTableColumn> columns, int columnSpacing) {
  final parts = [
    for (final column in columns)
      switch (column.width) {
        FixedColumnWidth(:final width) => '─' * width,
        _ => '─' * _sanitizeTreeTableText(column.title).length.clamp(3, 12),
      },
  ];
  return parts.join(' ' * columnSpacing);
}

String _encodeField(String value, DataTableExportFormat format) {
  final sanitized = _sanitizeTreeTableText(value);
  if (format == DataTableExportFormat.tsv) {
    return sanitized.replaceAll('\t', ' ');
  }
  final needsQuote =
      sanitized.contains(',') ||
      sanitized.contains('"') ||
      sanitized.contains('\n') ||
      sanitized.contains('\r');
  final escaped = sanitized.replaceAll('"', '""');
  return needsQuote ? '"$escaped"' : escaped;
}

final _treeTableLineBreakPattern = RegExp(r'[\r\n\t]');

String _sanitizeTreeTableText(String text) {
  return sanitizeForDisplay(text.replaceAll(_treeTableLineBreakPattern, ' '));
}
