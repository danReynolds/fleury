import 'dart:async' show FutureOr, unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'component_theme.dart';
import 'table.dart' show FixedColumnWidth, FlexColumnWidth, TableColumnWidth;

/// Direction for an app-provided [DataTable] sort state.
enum DataTableSortDirection { ascending, descending }

/// Selection model used by [DataTable].
enum DataTableSelectionMode {
  /// Select whole rows. This preserves the original DataTable behavior.
  row,

  /// Select a focused cell and optional rectangular cell range.
  cell,
}

/// Export encoding for [DataTable] row data.
enum DataTableExportFormat { tsv, csv }

/// A rectangular range of table cells.
final class DataTableSelectionRange {
  const DataTableSelectionRange({
    required this.anchorRow,
    required this.anchorColumn,
    required this.focusRow,
    required this.focusColumn,
  });

  factory DataTableSelectionRange.row({
    required int rowIndex,
    required int columnCount,
  }) {
    final endColumn = columnCount <= 0 ? 0 : columnCount - 1;
    return DataTableSelectionRange(
      anchorRow: rowIndex,
      anchorColumn: 0,
      focusRow: rowIndex,
      focusColumn: endColumn,
    );
  }

  final int anchorRow;
  final int anchorColumn;
  final int focusRow;
  final int focusColumn;

  int get startRow => anchorRow < focusRow ? anchorRow : focusRow;
  int get endRow => anchorRow > focusRow ? anchorRow : focusRow;
  int get startColumn =>
      anchorColumn < focusColumn ? anchorColumn : focusColumn;
  int get endColumn => anchorColumn > focusColumn ? anchorColumn : focusColumn;
  int get rowCount => endRow - startRow + 1;
  int get columnCount => endColumn - startColumn + 1;

  bool containsCell(int rowIndex, int columnIndex) {
    return rowIndex >= startRow &&
        rowIndex <= endRow &&
        columnIndex >= startColumn &&
        columnIndex <= endColumn;
  }

  DataTableSelectionRange clamp({
    required int rowCount,
    required int columnCount,
  }) {
    final maxRow = rowCount <= 0 ? 0 : rowCount - 1;
    final maxColumn = columnCount <= 0 ? 0 : columnCount - 1;
    return DataTableSelectionRange(
      anchorRow: anchorRow.clamp(0, maxRow),
      anchorColumn: anchorColumn.clamp(0, maxColumn),
      focusRow: focusRow.clamp(0, maxRow),
      focusColumn: focusColumn.clamp(0, maxColumn),
    );
  }
}

/// Options for exporting [DataTable] rows.
final class DataTableExportOptions {
  const DataTableExportOptions({
    this.format = DataTableExportFormat.tsv,
    this.includeHeader = true,
    this.startRow = 0,
    this.startColumn = 0,
    this.maxRows,
    this.maxColumns,
  }) : assert(startRow >= 0),
       assert(startColumn >= 0),
       assert(maxColumns == null || maxColumns >= 0),
       assert(maxRows == null || maxRows >= 0);

  final DataTableExportFormat format;
  final bool includeHeader;
  final int startRow;
  final int startColumn;
  final int? maxRows;
  final int? maxColumns;
}

/// Result of exporting [DataTable] rows.
final class DataTableExportResult {
  const DataTableExportResult({
    required this.text,
    required this.rowCount,
    required this.columnCount,
    required this.startRow,
    required this.startColumn,
    required this.format,
    required this.truncated,
  });

  final String text;
  final int rowCount;
  final int columnCount;
  final int startRow;
  final int startColumn;
  final DataTableExportFormat format;
  final bool truncated;
}

/// Clipboard behavior for [DataTable] selected-row copy.
final class DataTableCopyOptions {
  const DataTableCopyOptions({
    this.format = DataTableExportFormat.tsv,
    this.includeHeader = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final DataTableExportFormat format;
  final bool includeHeader;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after a [DataTable] selected-row copy completes.
final class DataTableCopyResult {
  const DataTableCopyResult({
    required this.rowIndex,
    required this.rowKey,
    required this.selection,
    required this.export,
    required this.report,
  });

  final int rowIndex;
  final Object? rowKey;
  final DataTableSelectionRange selection;
  final DataTableExportResult export;
  final ClipboardWriteReport report;

  String get text => export.text;
}

/// Sort behavior for [buildDataTableRowOrder].
final class DataTableSortDescriptor {
  const DataTableSortDescriptor({
    required this.columnId,
    this.direction = DataTableSortDirection.ascending,
    this.caseSensitive = false,
    this.compare,
  });

  final String columnId;
  final DataTableSortDirection direction;
  final bool caseSensitive;
  final int Function(String a, String b)? compare;
}

/// Filter behavior for [buildDataTableRowOrder].
final class DataTableFilterDescriptor {
  const DataTableFilterDescriptor({
    required this.query,
    this.columnIds,
    this.caseSensitive = false,
  });

  final String query;
  final Set<String>? columnIds;
  final bool caseSensitive;
}

/// Builds a source-row order after applying framework-owned filter/sort rules.
///
/// This helper lets apps keep [DataTable] virtualized while still getting
/// consistent first-party filtering and sorting behavior. The returned list
/// contains source row indexes in the order the app should expose them to the
/// table's `rowKeyBuilder` and `cellBuilder`.
List<int> buildDataTableRowOrder({
  required int rowCount,
  required List<DataTableColumn> columns,
  required DataTableCellBuilder cellBuilder,
  DataTableFilterDescriptor? filter,
  DataTableSortDescriptor? sort,
}) {
  final safeRowCount = rowCount < 0 ? 0 : rowCount;
  final rows = <int>[];
  for (var row = 0; row < safeRowCount; row++) {
    if (_rowMatchesFilter(row, columns, cellBuilder, filter)) rows.add(row);
  }

  if (sort != null) {
    final sortKeyByRow = <int, String>{
      for (final row in rows) row: _sortKeyForRow(row, sort, cellBuilder),
    };
    final compare = sort.compare ?? _compareCellText;
    rows.sort((a, b) {
      var result = compare(sortKeyByRow[a]!, sortKeyByRow[b]!);
      if (result == 0) result = a.compareTo(b);
      return sort.direction == DataTableSortDirection.ascending
          ? result
          : -result;
    });
  }

  return List<int>.unmodifiable(rows);
}

String _sortKeyForRow(
  int row,
  DataTableSortDescriptor sort,
  DataTableCellBuilder cellBuilder,
) {
  final value = _sanitizeExportField(cellBuilder(row, sort.columnId));
  return sort.caseSensitive ? value : value.toLowerCase();
}

/// Exports row data without mounting cells as widgets.
DataTableExportResult exportDataTableRows({
  required int rowCount,
  required List<DataTableColumn> columns,
  required DataTableCellBuilder cellBuilder,
  DataTableExportOptions options = const DataTableExportOptions(),
}) {
  final safeRowCount = rowCount < 0 ? 0 : rowCount;
  final startColumn = options.startColumn > columns.length
      ? columns.length
      : options.startColumn;
  final availableColumns = columns.length - startColumn;
  final columnLimit =
      options.maxColumns == null || options.maxColumns! > availableColumns
      ? availableColumns
      : options.maxColumns!;
  final exportColumns = columns
      .skip(startColumn)
      .take(columnLimit)
      .toList(growable: false);
  if (exportColumns.isEmpty || safeRowCount == 0 && !options.includeHeader) {
    return DataTableExportResult(
      text: '',
      rowCount: 0,
      columnCount: exportColumns.length,
      startRow: options.startRow,
      startColumn: startColumn,
      format: options.format,
      truncated: options.startRow < safeRowCount,
    );
  }

  final start = options.startRow > safeRowCount
      ? safeRowCount
      : options.startRow;
  final available = safeRowCount - start;
  final limit = options.maxRows == null || options.maxRows! > available
      ? available
      : options.maxRows!;
  final output = StringBuffer();
  var wroteLine = false;

  void writeLine(Iterable<String> fields) {
    if (wroteLine) output.writeln();
    output.write(_formatExportLine(fields, options.format));
    wroteLine = true;
  }

  if (options.includeHeader) {
    writeLine(exportColumns.map((column) => column.title));
  }
  for (var offset = 0; offset < limit; offset++) {
    final rowIndex = start + offset;
    writeLine(exportColumns.map((column) => cellBuilder(rowIndex, column.id)));
  }

  return DataTableExportResult(
    text: output.toString(),
    rowCount: limit,
    columnCount: exportColumns.length,
    startRow: start,
    startColumn: startColumn,
    format: options.format,
    truncated:
        start + limit < safeRowCount ||
        startColumn + columnLimit < columns.length,
  );
}

final _ansiEscapePattern = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-_])',
);

String _formatExportLine(
  Iterable<String> fields,
  DataTableExportFormat format,
) {
  return fields.map((field) => _formatExportField(field, format)).join(
    switch (format) {
      DataTableExportFormat.tsv => '\t',
      DataTableExportFormat.csv => ',',
    },
  );
}

String _formatExportField(String field, DataTableExportFormat format) {
  final sanitized = _sanitizeExportField(field);
  return switch (format) {
    DataTableExportFormat.tsv => sanitized,
    DataTableExportFormat.csv => _quoteCsvField(sanitized),
  };
}

String _sanitizeExportField(String field) {
  final withoutAnsi = field.replaceAll(_ansiEscapePattern, '');
  return sanitizeSingleLine(withoutAnsi);
}

String _quoteCsvField(String field) {
  if (!field.contains(',') && !field.contains('"')) return field;
  return '"${field.replaceAll('"', '""')}"';
}

bool _rowMatchesFilter(
  int row,
  List<DataTableColumn> columns,
  DataTableCellBuilder cellBuilder,
  DataTableFilterDescriptor? filter,
) {
  if (filter == null) return true;
  final rawQuery = filter.query.trim();
  if (rawQuery.isEmpty) return true;
  final tokens = rawQuery
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .map((token) => filter.caseSensitive ? token : token.toLowerCase())
      .toList(growable: false);
  if (tokens.isEmpty) return true;
  final columnIds = filter.columnIds;
  final haystack = StringBuffer();
  for (final column in columns) {
    if (columnIds != null && !columnIds.contains(column.id)) continue;
    if (haystack.isNotEmpty) haystack.write(' ');
    final value = _sanitizeExportField(cellBuilder(row, column.id));
    haystack.write(filter.caseSensitive ? value : value.toLowerCase());
  }
  final text = haystack.toString();
  return tokens.every(text.contains);
}

int _compareCellText(String a, String b) => a.compareTo(b);

Map<String, Object?> _clipboardSemanticState(DataTableCopyOptions options) {
  final resolution = resolveCapabilityRequirement(
    const CapabilityRequirement(
      feature: TerminalFeature.clipboardWrite,
      level: CapabilityLevel.preferred,
      reason: 'Copy selected table row.',
      fallback: CapabilityFallback(label: 'in-process register'),
    ),
    TerminalCapabilities.defaultCapabilities,
  );
  return <String, Object?>{
    'copyEnabled': true,
    'copyFormat': options.format.name,
    'copyIncludesHeader': options.includeHeader,
    'clipboardPolicy': options.clipboardPolicy.name,
    'clipboardCapability': resolution.feature.name,
    'clipboardCapabilityResolution': resolution.state.name,
    if (resolution.fallbackLabel != null)
      'clipboardFallback': resolution.fallbackLabel,
    'clipboardRedacted': false,
  };
}

/// A column in a [DataTable].
final class DataTableColumn {
  const DataTableColumn({
    required this.id,
    required this.title,
    this.width = const FlexColumnWidth(),
    this.style = CellStyle.empty,
    this.headerStyle = const CellStyle(bold: true),
  });

  /// Stable column identifier passed to [DataTableCellBuilder].
  final String id;

  /// Header label shown at the top of the column.
  final String title;

  /// Layout policy for this column's cell width.
  final TableColumnWidth width;

  /// Default style applied to body cells in this column.
  final CellStyle style;

  /// Style applied to this column's header cell.
  final CellStyle headerStyle;
}

/// Builds the text for one [DataTable] cell.
typedef DataTableCellBuilder = String Function(int rowIndex, String columnId);

/// Builds a stable semantic key for one [DataTable] row.
typedef DataTableRowKeyBuilder = Object Function(int rowIndex);

/// Selected-row controller for [DataTable].
class DataTableController extends ChangeNotifier {
  DataTableController({int selectedIndex = 0, int selectedColumnIndex = 0})
    : _selectedIndex = selectedIndex,
      _selectedColumnIndex = selectedColumnIndex,
      _anchorRow = selectedIndex,
      _anchorColumn = selectedColumnIndex;

  int _selectedIndex;
  int _selectedColumnIndex;
  int _anchorRow;
  int _anchorColumn;
  int _rowCount = 0;
  int _columnCount = 0;
  bool _disposed = false;

  int get selectedIndex => _selectedIndex;
  set selectedIndex(int value) {
    _checkNotDisposed();
    final clamped = _clamp(value);
    if (_selectedIndex == clamped) return;
    _selectedIndex = clamped;
    _anchorRow = clamped;
    _anchorColumn = _selectedColumnIndex;
    notifyListeners();
  }

  int get selectedColumnIndex => _selectedColumnIndex;
  set selectedColumnIndex(int value) {
    _checkNotDisposed();
    final clamped = _clampColumn(value);
    if (_selectedColumnIndex == clamped) return;
    _selectedColumnIndex = clamped;
    _anchorRow = _selectedIndex;
    _anchorColumn = clamped;
    notifyListeners();
  }

  /// Total row / column counts, so callers can tell when the selection sits on
  /// an edge (e.g. to bubble an arrow key for boundary focus escape).
  int get rowCount => _rowCount;
  int get columnCount => _columnCount;

  DataTableSelectionRange get selectionRange => DataTableSelectionRange(
    anchorRow: _anchorRow,
    anchorColumn: _anchorColumn,
    focusRow: _selectedIndex,
    focusColumn: _selectedColumnIndex,
  ).clamp(rowCount: _rowCount, columnCount: _columnCount);

  void selectCell(int rowIndex, int columnIndex, {bool extend = false}) {
    _checkNotDisposed();
    final row = _clamp(rowIndex);
    final column = _clampColumn(columnIndex);
    final changed = row != _selectedIndex || column != _selectedColumnIndex;
    final anchorChanged =
        !extend && (_anchorRow != row || _anchorColumn != column);
    _selectedIndex = row;
    _selectedColumnIndex = column;
    if (!extend) {
      _anchorRow = row;
      _anchorColumn = column;
    }
    if (changed || anchorChanged) notifyListeners();
  }

  void moveSelection({
    int rowDelta = 0,
    int columnDelta = 0,
    bool extend = false,
  }) {
    _checkNotDisposed();
    selectCell(
      _selectedIndex + rowDelta,
      _selectedColumnIndex + columnDelta,
      extend: extend,
    );
  }

  void _setRowCount(int value) {
    _checkNotDisposed();
    _rowCount = value < 0 ? 0 : value;
    final clamped = _clamp(_selectedIndex);
    final anchor = _clamp(_anchorRow);
    if (_selectedIndex == clamped && _anchorRow == anchor) return;
    _selectedIndex = clamped;
    _anchorRow = anchor;
    notifyListeners();
  }

  void _setColumnCount(int value) {
    _checkNotDisposed();
    _columnCount = value < 0 ? 0 : value;
    final clamped = _clampColumn(_selectedColumnIndex);
    final anchor = _clampColumn(_anchorColumn);
    if (_selectedColumnIndex == clamped && _anchorColumn == anchor) return;
    _selectedColumnIndex = clamped;
    _anchorColumn = anchor;
    notifyListeners();
  }

  int _clamp(int value) {
    if (_rowCount <= 0) return 0;
    return value.clamp(0, _rowCount - 1);
  }

  int _clampColumn(int value) {
    if (_columnCount <= 0) return 0;
    return value.clamp(0, _columnCount - 1);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DataTableController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// Render-island table for large, text-shaped data sets.
///
/// Unlike `Table`, this widget does not mount every cell as a widget. It asks
/// [cellBuilder] only for the visible body rows, paints those directly into the
/// cell buffer, and contributes visible-row semantics from the render object.
class DataTable extends StatefulWidget {
  const DataTable({
    super.key,
    required this.rowCount,
    required this.columns,
    required this.cellBuilder,
    this.rowKeyBuilder,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.typeahead = true,
    this.selectionMode = DataTableSelectionMode.row,
    this.copySelectedRow = true,
    this.copyOptions = const DataTableCopyOptions(),
    this.onCopy,
    this.columnSpacing = 1,
    this.headerSeparator = true,
    this.separatorStyle,
    this.selectedStyle,
    this.sortColumnId,
    this.sortDirection,
    this.onSort,
    this.filterText,
    this.semanticLabel = 'Data table',
  });

  /// Number of source rows available to the table.
  final int rowCount;

  /// Column definitions, in display order.
  final List<DataTableColumn> columns;

  /// Returns the display text for a visible cell.
  final DataTableCellBuilder cellBuilder;

  /// Optional stable row identity used by semantics and copy callbacks.
  final DataTableRowKeyBuilder? rowKeyBuilder;

  /// External selection controller. If omitted, the table owns one.
  final DataTableController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the table should request focus when mounted.
  final bool autofocus;

  /// Called when the focused row is activated.
  final void Function(int rowIndex)? onSelect;

  /// Whether typing a printable character jumps the selection to the next
  /// row whose first-column cell starts with it (grid type-ahead). On by
  /// default. Turn it off when the surrounding app binds bare printables
  /// (a vim-style command key, a `q` quit): a focused table with
  /// type-ahead on consumes every printable before those bindings see it.
  final bool typeahead;

  /// Whether keyboard selection targets whole rows or individual cells.
  final DataTableSelectionMode selectionMode;

  /// Whether Ctrl+C and semantic copy export the current selection.
  final bool copySelectedRow;

  /// Export and clipboard options used when copying table data.
  final DataTableCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(DataTableCopyResult result)? onCopy;

  /// Empty cells inserted between adjacent columns.
  final int columnSpacing;

  /// Whether to draw a separator below the header row.
  final bool headerSeparator;

  /// Style used for header and row separators.
  final CellStyle? separatorStyle;

  /// Style merged onto the focused row or focused cell.
  final CellStyle? selectedStyle;

  /// App-owned sort column identifier exposed through semantics.
  final String? sortColumnId;

  /// App-owned sort direction exposed through semantics.
  final DataTableSortDirection? sortDirection;

  /// Called with a column's id when an agent activates its header cell, so the
  /// app can (re)sort. The header is custom-painted (no per-cell widget), so
  /// this is the semantic-layer trigger — the synthetic header cells carry the
  /// `columnId`. When non-null, header cells advertise `activate`.
  final void Function(String columnId)? onSort;

  /// App-owned filter text exposed through semantics.
  final String? filterText;

  /// Semantic label for the table.
  final String? semanticLabel;

  @override
  State<DataTable> createState() => _DataTableState();
}

class _DataTableState extends State<DataTable> {
  late DataTableController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  int _visibleRows = 1;
  DataTableViewportMetrics _viewport = DataTableViewportMetrics.empty;
  _DataTablePointerHit? _pendingPointerHit;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DataTableController();
    _ownsController = widget.controller == null;
    _controller
      .._setRowCount(widget.rowCount)
      .._setColumnCount(widget.columns.length)
      ..addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'DataTable');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(DataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? DataTableController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'DataTable');
      _ownsFocusNode = widget.focusNode == null;
    }
    _controller._setRowCount(widget.rowCount);
    _controller._setColumnCount(widget.columns.length);
  }

  void _onChange() => setState(() {});

  void _onFocusWithinChange(bool focused) => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelection() async {
    if (widget.columns.isEmpty || widget.rowCount <= 0) return;
    final focusRow = _controller.selectedIndex;
    final selection = _copyRangeForCurrentMode();
    final rowKeyBuilder = widget.rowKeyBuilder;
    final rowKey = rowKeyBuilder == null ? focusRow : rowKeyBuilder(focusRow);
    final export = exportDataTableRows(
      rowCount: widget.rowCount,
      columns: widget.columns,
      cellBuilder: widget.cellBuilder,
      options: DataTableExportOptions(
        format: widget.copyOptions.format,
        includeHeader: widget.copyOptions.includeHeader,
        startRow: selection.startRow,
        startColumn: selection.startColumn,
        maxRows: selection.rowCount,
        maxColumns: selection.columnCount,
      ),
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(export.text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      DataTableCopyResult(
        rowIndex: focusRow,
        rowKey: rowKey,
        selection: selection,
        export: export,
        report: report,
      ),
    );
  }

  Future<bool> _handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  ) async {
    switch (action) {
      case SemanticAction.focus:
        _focusNode.requestFocus();
        return true;
      case SemanticAction.select:
        _focusNode.requestFocus();
        return _selectSemanticTarget(target);
      case SemanticAction.activate:
        // A header cell activate is a sort request, not a row selection.
        if (target.state['header'] == true) {
          final columnId = target.state['columnId'];
          if (widget.onSort != null && columnId is String) {
            widget.onSort!(columnId);
            return true;
          }
          return false;
        }
        if (widget.onSelect == null) return false;
        _focusNode.requestFocus();
        _selectSemanticTarget(target);
        widget.onSelect!.call(_controller.selectedIndex);
        return true;
      case SemanticAction.copy:
        if (!widget.copySelectedRow) return false;
        await _copySelection();
        return true;
      case _:
        return false;
    }
  }

  /// `setValue` on the table node jumps the windowed row range to a target row
  /// INDEX (0-based) — the off-window reach an agent can't otherwise get
  /// without growing the whole grid. The window follows the selection, so the
  /// target row then appears in the next snapshot. Clamped to the row range;
  /// does not fire `onSelect` (it's navigation, not a row action).
  bool _handleSemanticSetValue(SemanticNode target, Object? value) {
    if (target.role != SemanticRole.table || widget.rowCount <= 0) return false;
    final index = coerceSemanticInt(value);
    if (index == null) return false;
    _focusNode.requestFocus();
    _controller.selectedIndex = index.clamp(0, widget.rowCount - 1);
    return true;
  }

  bool _selectSemanticTarget(SemanticNode target) {
    final rowIndex = target.state['rowIndex'];
    if (rowIndex is! int || rowIndex < 0) {
      return target.role == SemanticRole.table;
    }
    final columnIndex = target.state['columnIndex'];
    if (widget.selectionMode == DataTableSelectionMode.cell &&
        columnIndex is int &&
        columnIndex >= 0) {
      _controller.selectCell(rowIndex, columnIndex);
    } else {
      _controller.selectedIndex = rowIndex;
    }
    return true;
  }

  DataTableSelectionRange _copyRangeForCurrentMode() {
    final range = widget.selectionMode == DataTableSelectionMode.row
        ? DataTableSelectionRange.row(
            rowIndex: _controller.selectedIndex,
            columnCount: widget.columns.length,
          )
        : _controller.selectionRange;
    return range.clamp(
      rowCount: widget.rowCount,
      columnCount: widget.columns.length,
    );
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (widget.rowCount <= 0) return KeyEventResult.ignored;
    if (widget.copySelectedRow &&
        widget.columns.isNotEmpty &&
        event.hasCtrl &&
        event.char?.toLowerCase() == 'c') {
      unawaited(_copySelection());
      return KeyEventResult.handled;
    }
    final extend = event.hasShift;
    switch (event.keyCode) {
      // Boundary escape: an arrow at the grid edge bubbles so focus can leave
      // the table (Tab/Shift+Tab and Esc also leave). Shift-extends never
      // escape — they're an editing gesture, not navigation.
      case KeyCode.arrowUp:
        return moveOrEscape(
          atEdge: !extend && _controller.selectedIndex <= 0,
          move: () => _controller.moveSelection(rowDelta: -1, extend: extend),
        );
      case KeyCode.arrowDown:
        return moveOrEscape(
          atEdge:
              !extend && _controller.selectedIndex >= _controller.rowCount - 1,
          move: () => _controller.moveSelection(rowDelta: 1, extend: extend),
        );
      case KeyCode.arrowLeft:
        if (widget.selectionMode != DataTableSelectionMode.cell) {
          return KeyEventResult.ignored;
        }
        return moveOrEscape(
          atEdge: !extend && _controller.selectedColumnIndex <= 0,
          move: () =>
              _controller.moveSelection(columnDelta: -1, extend: extend),
        );
      case KeyCode.arrowRight:
        if (widget.selectionMode != DataTableSelectionMode.cell) {
          return KeyEventResult.ignored;
        }
        return moveOrEscape(
          atEdge:
              !extend &&
              _controller.selectedColumnIndex >= _controller.columnCount - 1,
          move: () => _controller.moveSelection(columnDelta: 1, extend: extend),
        );
      case KeyCode.pageUp:
        _controller.moveSelection(rowDelta: -_visibleRows, extend: extend);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        _controller.moveSelection(rowDelta: _visibleRows, extend: extend);
        return KeyEventResult.handled;
      case KeyCode.home:
        // Ctrl+Home → first cell (0,0) in cell mode; plain Home → top row,
        // same column (WAI-ARIA grid).
        final homeColumn =
            event.hasCtrl && widget.selectionMode == DataTableSelectionMode.cell
            ? 0
            : _controller.selectedColumnIndex;
        _controller.selectCell(0, homeColumn);
        return KeyEventResult.handled;
      case KeyCode.end:
        final endColumn =
            event.hasCtrl && widget.selectionMode == DataTableSelectionMode.cell
            ? _controller.columnCount - 1
            : _controller.selectedColumnIndex;
        _controller.selectCell(widget.rowCount - 1, endColumn);
        return KeyEventResult.handled;
      case KeyCode.enter:
        widget.onSelect?.call(_controller.selectedIndex);
        return KeyEventResult.handled;
      default:
        final ch = event.char;
        if (widget.typeahead &&
            ch != null &&
            ch.length == 1 &&
            ch.codeUnitAt(0) >= 0x21 &&
            !event.hasCtrl &&
            !event.hasAlt &&
            widget.columns.isNotEmpty) {
          return _typeahead(ch);
        }
        return KeyEventResult.ignored;
    }
  }

  /// Jump the selection to the next row whose first-column cell starts with
  /// [ch] (wrapping) — spreadsheet/grid type-ahead.
  KeyEventResult _typeahead(String ch) {
    final columnId = widget.columns.first.id;
    final lower = ch.toLowerCase();
    final start = _controller.selectedIndex + 1;
    for (var k = 0; k < widget.rowCount; k++) {
      final i = (start + k) % widget.rowCount;
      if (widget.cellBuilder(i, columnId).toLowerCase().startsWith(lower)) {
        _controller.selectCell(i, _controller.selectedColumnIndex);
        break;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final selectedStyle = _focusNode.hasFocus
        ? widget.selectedStyle ?? widgetTheme.resolveDataSelected(theme)
        : theme.mutedStyle;
    final table = _DataTableRenderWidget(
      rowCount: widget.rowCount < 0 ? 0 : widget.rowCount,
      columns: widget.columns,
      cellBuilder: widget.cellBuilder,
      semanticLabel: widget.semanticLabel,
      rowKeyBuilder: widget.rowKeyBuilder,
      selectedRow: _controller.selectedIndex,
      selectedColumn: _controller.selectedColumnIndex,
      selectionRange: _controller.selectionRange,
      selectionMode: widget.selectionMode,
      focusNode: _focusNode,
      columnSpacing: widget.columnSpacing,
      headerSeparator: widget.headerSeparator,
      separatorStyle:
          widget.separatorStyle ?? widgetTheme.resolveDataSeparator(theme),
      selectedStyle: selectedStyle,
      sortColumnId: widget.sortColumnId,
      sortDirection: widget.sortDirection,
      filterText: widget.filterText,
      copySelectedRow: widget.copySelectedRow,
      copyOptions: widget.copyOptions,
      onViewport: (viewport) {
        _viewport = viewport;
        _visibleRows = viewport.visibleRows < 1 ? 1 : viewport.visibleRows;
      },
      onSelect: widget.onSelect,
      sortable: widget.onSort != null,
      onSemanticAction: _handleSemanticAction,
      onSemanticSetValue: _handleSemanticSetValue,
    );
    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKey: _onKey,
        // Wheel over the table scrolls the row window by moving the selection
        // (the window follows the selected row; selection changes don't fire
        // onSelect, so scrolling never triggers a row action).
        child: PointerScrollListener(
          router: PointerRouterScope.maybeOf(context),
          onScrollUp: () => _scrollBy(-1),
          onScrollDown: () => _scrollBy(1),
          child: GestureDetector(
            onTapDownWithModifiers: (col, row, modifiers) {
              _pendingPointerHit = _hitTestPointer(col, row, modifiers);
            },
            onTap: () {
              final hit = _pendingPointerHit;
              _pendingPointerHit = null;
              if (hit == null) return;
              _focusNode.requestFocus();
              if (widget.selectionMode == DataTableSelectionMode.cell &&
                  hit.columnIndex != null) {
                _controller.selectCell(
                  hit.rowIndex,
                  hit.columnIndex!,
                  extend: hit.extend,
                );
              } else {
                _controller.selectedIndex = hit.rowIndex;
              }
            },
            child: table,
          ),
        ),
      ),
    );
  }

  /// Wheel scroll moves the selection (the row window follows it). Selection
  /// changes don't fire onSelect — that's reserved for Enter / activate.
  void _scrollBy(int delta) {
    final count = _controller.rowCount;
    if (count == 0) return;
    final next = (_controller.selectedIndex + delta).clamp(0, count - 1);
    if (next != _controller.selectedIndex) _controller.selectedIndex = next;
  }

  _DataTablePointerHit? _hitTestPointer(
    int col,
    int row,
    Set<KeyModifier> modifiers,
  ) {
    final rect = _focusNode.rect;
    if (rect == null || !_viewport.hasBodyRows) return null;
    final localCol = col - rect.left;
    final localRow = row - rect.top;
    if (localCol < 0 ||
        localCol >= _viewport.tableWidth ||
        localRow < _viewport.bodyTop ||
        localRow >= _viewport.bodyTop + _viewport.visibleRows) {
      return null;
    }
    final rowIndex = _viewport.visibleFirst + localRow - _viewport.bodyTop;
    if (rowIndex < 0 || rowIndex >= widget.rowCount) return null;
    final columnIndex = _viewport.columnAt(localCol);
    if (widget.selectionMode == DataTableSelectionMode.cell &&
        columnIndex == null) {
      return null;
    }
    return _DataTablePointerHit(
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      extend: modifiers.contains(KeyModifier.shift),
    );
  }
}

final class _DataTablePointerHit {
  const _DataTablePointerHit({
    required this.rowIndex,
    required this.columnIndex,
    required this.extend,
  });

  final int rowIndex;
  final int? columnIndex;
  final bool extend;
}

/// Current viewport geometry for a rendered [DataTable].
///
/// [DataTable] uses these metrics to keep mouse hit selection aligned with
/// the rows and columns that the render island actually painted.
final class DataTableViewportMetrics {
  const DataTableViewportMetrics({
    required this.visibleFirst,
    required this.visibleRows,
    required this.bodyTop,
    required this.columnStarts,
    required this.columnWidths,
    required this.tableWidth,
  });

  /// Empty viewport used before layout or when no rows are visible.
  static const empty = DataTableViewportMetrics(
    visibleFirst: 0,
    visibleRows: 0,
    bodyTop: 0,
    columnStarts: <int>[],
    columnWidths: <int>[],
    tableWidth: 0,
  );

  final int visibleFirst;
  final int visibleRows;
  final int bodyTop;
  final List<int> columnStarts;
  final List<int> columnWidths;
  final int tableWidth;

  /// Whether the current viewport contains hit-testable body rows.
  bool get hasBodyRows => visibleRows > 0 && tableWidth > 0;

  /// Returns the rendered column at [localCol], or null when the pointer is in
  /// a spacing gap or outside all column bodies.
  int? columnAt(int localCol) {
    for (var i = 0; i < columnStarts.length; i++) {
      final start = columnStarts[i];
      final end = start + columnWidths[i];
      if (localCol >= start && localCol < end) return i;
    }
    return null;
  }
}

class _DataTableRenderWidget extends LeafRenderObjectWidget {
  const _DataTableRenderWidget({
    required this.rowCount,
    required this.columns,
    required this.cellBuilder,
    required this.semanticLabel,
    required this.rowKeyBuilder,
    required this.selectedRow,
    required this.selectedColumn,
    required this.selectionRange,
    required this.selectionMode,
    required this.focusNode,
    required this.columnSpacing,
    required this.headerSeparator,
    required this.separatorStyle,
    required this.selectedStyle,
    required this.onViewport,
    required this.onSelect,
    required this.sortable,
    required this.onSemanticAction,
    required this.onSemanticSetValue,
    required this.copySelectedRow,
    required this.copyOptions,
    this.sortColumnId,
    this.sortDirection,
    this.filterText,
  });

  final int rowCount;
  final List<DataTableColumn> columns;
  final DataTableCellBuilder cellBuilder;
  final String? semanticLabel;
  final DataTableRowKeyBuilder? rowKeyBuilder;
  final int selectedRow;
  final int selectedColumn;
  final DataTableSelectionRange selectionRange;
  final DataTableSelectionMode selectionMode;
  final FocusNode focusNode;
  final int columnSpacing;
  final bool headerSeparator;
  final CellStyle separatorStyle;
  final CellStyle selectedStyle;
  final void Function(DataTableViewportMetrics viewport) onViewport;
  final void Function(int rowIndex)? onSelect;
  final bool sortable;
  final FutureOr<bool> Function(SemanticNode target, SemanticAction action)
  onSemanticAction;
  final FutureOr<bool> Function(SemanticNode target, Object? value)
  onSemanticSetValue;
  final bool copySelectedRow;
  final DataTableCopyOptions copyOptions;
  final String? sortColumnId;
  final DataTableSortDirection? sortDirection;
  final String? filterText;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderDataTable(
      rowCount: rowCount,
      columns: columns,
      cellBuilder: cellBuilder,
      selectedRow: selectedRow,
      selectionRange: selectionRange,
      selectionMode: selectionMode,
      columnSpacing: columnSpacing,
      headerSeparator: headerSeparator,
      separatorStyle: separatorStyle,
      selectedStyle: selectedStyle,
      onViewport: onViewport,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDataTable renderObject,
  ) {
    renderObject
      ..rowCount = rowCount
      ..columns = columns
      ..cellBuilder = cellBuilder
      ..selectedRow = selectedRow
      ..selectionRange = selectionRange
      ..selectionMode = selectionMode
      ..columnSpacing = columnSpacing
      ..headerSeparator = headerSeparator
      ..separatorStyle = separatorStyle
      ..selectedStyle = selectedStyle
      ..onViewport = onViewport;
  }

  @override
  LeafRenderObjectElement createElement() => _DataTableElement(this);
}

class _DataTableElement extends LeafRenderObjectElement
    implements
        SemanticContributor,
        SemanticActionContributor,
        SemanticValueContributor {
  _DataTableElement(_DataTableRenderWidget super.widget);

  @override
  _DataTableRenderWidget get widget => super.widget as _DataTableRenderWidget;

  @override
  RenderDataTable get renderObject => super.renderObject as RenderDataTable;

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    // Stable id anchor folded from the table's keyed ancestors (e.g.
    // DataTable(key:)), so row/cell ids survive rebuilds and reorders instead
    // of churning on the element's hashCode. Falls back to the element hash
    // only when the table has no keyed ancestor at all. Genuinely positional
    // segments (index-keyed rows, column index) carry a `~` so the stale guard
    // protects exactly them.
    final scope = semanticAnchorOf(this) ?? 'element-$hashCode';
    final visibleFirst = renderObject.visibleFirst;
    final visibleRows = renderObject.visibleRows;
    final visibleEnd = widget.rowCount == 0 || visibleRows == 0
        ? -1
        : (visibleFirst + visibleRows - 1).clamp(
            visibleFirst,
            widget.rowCount - 1,
          );
    final selected = widget.selectedRow.clamp(
      0,
      widget.rowCount <= 0 ? 0 : widget.rowCount - 1,
    );
    final selectedColumn = widget.selectedColumn.clamp(
      0,
      widget.columns.isEmpty ? 0 : widget.columns.length - 1,
    );
    final range = _effectiveSelectionRange(selected);
    final rowKeyBuilder = widget.rowKeyBuilder;
    final selectedKey = widget.rowCount == 0
        ? null
        : rowKeyBuilder == null
        ? selected
        : rowKeyBuilder(selected);
    final selectedColumnId = widget.columns.isEmpty
        ? null
        : widget.columns[selectedColumn].id;
    return SemanticNode(
      id: SemanticNodeId('$scope/table'),
      role: SemanticRole.table,
      label: widget.semanticLabel,
      value: selectedKey,
      focused: widget.focusNode.hasFocus,
      selected: widget.rowCount > 0,
      actions: <SemanticAction>{
        SemanticAction.focus,
        SemanticAction.select,
        if (widget.onSelect != null) SemanticAction.activate,
        // Jump the windowed row range to a target row INDEX — the off-window
        // reach an agent otherwise can't get without resizing the whole grid.
        if (widget.rowCount > 0) SemanticAction.setValue,
        if (widget.copySelectedRow &&
            widget.rowCount > 0 &&
            widget.columns.isNotEmpty)
          SemanticAction.copy,
      },
      state: SemanticState({
        'collectionRowCount': widget.rowCount,
        'collectionColumnCount': widget.columns.length,
        'hasHeader': true,
        'virtualized': true,
        'visibleRangeStart': visibleFirst,
        'visibleRangeEnd': visibleEnd,
        'selectedKey': selectedKey,
        'selectionMode': widget.selectionMode.name,
        'selectedColumnIndex': selectedColumn,
        'selectedColumnId': selectedColumnId,
        'selectionStartRow': range.startRow,
        'selectionEndRow': range.endRow,
        'selectionStartColumn': range.startColumn,
        'selectionEndColumn': range.endColumn,
        'selectionRowCount': range.rowCount,
        'selectionColumnCount': range.columnCount,
        if (widget.sortColumnId != null) 'sortColumn': widget.sortColumnId,
        if (widget.sortDirection != null)
          'sortDirection': widget.sortDirection!.name,
        if (widget.filterText != null) 'filterText': widget.filterText,
        if (widget.copySelectedRow &&
            widget.rowCount > 0 &&
            widget.columns.isNotEmpty)
          ..._clipboardSemanticState(widget.copyOptions),
      }),
      children: <SemanticNode>[
        SemanticNode(
          id: SemanticNodeId('$scope/table/header'),
          role: SemanticRole.tableRow,
          label: 'Header',
          state: const SemanticState({'rowIndex': -1, 'header': true}),
          children: [
            for (var col = 0; col < widget.columns.length; col++)
              SemanticNode(
                id: SemanticNodeId('$scope/table/header/~$col'),
                role: SemanticRole.tableCell,
                label: _sanitizeExportField(widget.columns[col].title),
                value: _sanitizeExportField(widget.columns[col].title),
                // Activating a sortable column's header asks the app to sort by
                // it (the app owns the data + the direction toggle).
                actions: <SemanticAction>{
                  if (widget.sortable) SemanticAction.activate,
                },
                state: SemanticState({
                  'rowIndex': -1,
                  'columnIndex': col,
                  'columnId': widget.columns[col].id,
                  'header': true,
                  if (widget.sortColumnId == widget.columns[col].id &&
                      widget.sortDirection != null)
                    'sortDirection': widget.sortDirection!.name,
                }),
              ),
          ],
        ),
        for (var i = 0; i < visibleRows; i++)
          if (visibleFirst + i < widget.rowCount)
            _semanticRow(scope, visibleFirst + i, selected, range),
      ],
    );
  }

  DataTableSelectionRange _effectiveSelectionRange(int selected) {
    final range = widget.selectionMode == DataTableSelectionMode.row
        ? DataTableSelectionRange.row(
            rowIndex: selected,
            columnCount: widget.columns.length,
          )
        : widget.selectionRange;
    return range.clamp(
      rowCount: widget.rowCount,
      columnCount: widget.columns.length,
    );
  }

  SemanticNode _semanticRow(
    String scope,
    int rowIndex,
    int selected,
    DataTableSelectionRange range,
  ) {
    final key = widget.rowKeyBuilder == null
        ? rowIndex
        : widget.rowKeyBuilder!(rowIndex);
    // No rowKeyBuilder ⇒ the "key" is the row index — positional, so mark it
    // `~` (version-fragile). A real row key is stable and identifies the row
    // wherever it scrolls/reorders; escape it so a key containing `/` or `~`
    // can't inject a segment or be misread as positional.
    final rowId = widget.rowKeyBuilder == null
        ? '$scope/table/row/~$key'
        : '$scope/table/row/${escapeSemanticIdSegment('$key')}';
    final rowSelected = rowIndex == selected;
    return SemanticNode(
      id: SemanticNodeId(rowId),
      role: SemanticRole.tableRow,
      label: key.toString(),
      selected: rowSelected,
      actions: <SemanticAction>{
        SemanticAction.select,
        if (widget.onSelect != null) SemanticAction.activate,
        if (widget.copySelectedRow &&
            widget.columns.isNotEmpty &&
            rowIndex == selected)
          SemanticAction.copy,
      },
      state: SemanticState({
        'rowIndex': rowIndex,
        'rowKey': key,
        if (range.startRow <= rowIndex && range.endRow >= rowIndex)
          'selectionIntersectsRow': true,
      }),
      children: [
        for (var col = 0; col < widget.columns.length; col++)
          _semanticCell(rowId, rowIndex, key, col, selected, range),
      ],
    );
  }

  SemanticNode _semanticCell(
    String rowId,
    int rowIndex,
    Object key,
    int columnIndex,
    int selected,
    DataTableSelectionRange range,
  ) {
    final column = widget.columns[columnIndex];
    final text = _sanitizeExportField(widget.cellBuilder(rowIndex, column.id));
    final selectedCell = widget.selectionMode == DataTableSelectionMode.row
        ? rowIndex == selected
        : range.containsCell(rowIndex, columnIndex);
    return SemanticNode(
      id: SemanticNodeId('$rowId/cell/~$columnIndex'),
      role: SemanticRole.tableCell,
      label: text,
      value: text,
      selected: selectedCell,
      actions: <SemanticAction>{
        SemanticAction.select,
        if (widget.onSelect != null) SemanticAction.activate,
        if (widget.copySelectedRow && widget.columns.isNotEmpty && selectedCell)
          SemanticAction.copy,
      },
      state: SemanticState({
        'rowIndex': rowIndex,
        'rowKey': key,
        'columnIndex': columnIndex,
        'columnId': column.id,
        'header': false,
        if (selectedCell) 'selectedCell': true,
      }),
    );
  }

  // Action dispatch resolves a target id to its owning element via the semantic
  // tree's id→element map (built in the same walk that mints the ids), so these
  // handlers are only ever called for *this* table's own nodes — no per-widget
  // ownership self-check is needed (a sibling table can't be handed our action).
  @override
  FutureOr<bool> handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  ) {
    return widget.onSemanticAction(target, action);
  }

  @override
  FutureOr<bool> handleSemanticSetValue(SemanticNode target, Object? value) {
    return widget.onSemanticSetValue(target, value);
  }
}

class RenderDataTable extends RenderObject {
  RenderDataTable({
    required int rowCount,
    required List<DataTableColumn> columns,
    required DataTableCellBuilder cellBuilder,
    required int selectedRow,
    required DataTableSelectionRange selectionRange,
    required DataTableSelectionMode selectionMode,
    required int columnSpacing,
    required bool headerSeparator,
    required CellStyle separatorStyle,
    required CellStyle selectedStyle,
    required void Function(DataTableViewportMetrics viewport) onViewport,
  }) : _rowCount = rowCount,
       _columns = columns,
       _cellBuilder = cellBuilder,
       _selectedRow = selectedRow,
       _selectionRange = selectionRange,
       _selectionMode = selectionMode,
       _columnSpacing = columnSpacing,
       _headerSeparator = headerSeparator,
       _separatorStyle = separatorStyle,
       _selectedStyle = selectedStyle,
       _onViewport = onViewport;

  static const _widthResolver = DefaultWidthResolver();
  static const _profile = TerminalProfile.standard;

  int _rowCount;
  List<DataTableColumn> _columns;
  DataTableCellBuilder _cellBuilder;
  int _selectedRow;
  DataTableSelectionRange _selectionRange;
  DataTableSelectionMode _selectionMode;
  int _columnSpacing;
  bool _headerSeparator;
  CellStyle _separatorStyle;
  CellStyle _selectedStyle;
  void Function(DataTableViewportMetrics) _onViewport;

  List<int> _columnWidths = const [];
  int _visibleFirst = 0;
  int _visibleRows = 0;
  int _tableWidth = 0;

  int get visibleFirst => _visibleFirst;
  int get visibleRows => _visibleRows;

  set rowCount(int value) {
    final clamped = value < 0 ? 0 : value;
    if (_rowCount == clamped) return;
    _rowCount = clamped;
    markNeedsLayout();
  }

  set columns(List<DataTableColumn> value) {
    if (identical(_columns, value)) return;
    _columns = value;
    markNeedsLayout();
  }

  set cellBuilder(DataTableCellBuilder value) {
    if (identical(_cellBuilder, value)) return;
    _cellBuilder = value;
    markNeedsPaintOnly();
  }

  set selectedRow(int value) {
    if (_selectedRow == value) return;
    final needsWindowUpdate = !_rowVisible(value);
    _selectedRow = value;
    if (needsWindowUpdate) {
      markNeedsLayout();
    } else {
      markNeedsPaintOnly();
    }
  }

  set selectionRange(DataTableSelectionRange value) {
    if (_selectionRange == value) return;
    _selectionRange = value;
    markNeedsPaintOnly();
  }

  set selectionMode(DataTableSelectionMode value) {
    if (_selectionMode == value) return;
    _selectionMode = value;
    markNeedsPaintOnly();
  }

  set columnSpacing(int value) {
    final clamped = value < 0 ? 0 : value;
    if (_columnSpacing == clamped) return;
    _columnSpacing = clamped;
    markNeedsLayout();
  }

  set headerSeparator(bool value) {
    if (_headerSeparator == value) return;
    _headerSeparator = value;
    markNeedsLayout();
  }

  set separatorStyle(CellStyle value) {
    if (_separatorStyle == value) return;
    _separatorStyle = value;
    markNeedsPaintOnly();
  }

  set selectedStyle(CellStyle value) {
    if (_selectedStyle == value) return;
    _selectedStyle = value;
    markNeedsPaintOnly();
  }

  set onViewport(void Function(DataTableViewportMetrics) value) =>
      _onViewport = value;

  bool _rowVisible(int row) {
    if (_visibleRows <= 0 || _rowCount <= 0) return false;
    return row >= _visibleFirst && row < _visibleFirst + _visibleRows;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    if (_columns.isEmpty) {
      _visibleFirst = 0;
      _visibleRows = 0;
      _onViewport(DataTableViewportMetrics.empty);
      return constraints.constrain(CellSize.zero);
    }
    _columnWidths = _resolveColumnWidths(constraints.maxCols);
    _tableWidth =
        _columnWidths.fold<int>(0, (sum, width) => sum + width) +
        _columnSpacing * (_columns.length - 1);
    final headerRows = 1 + (_headerSeparator ? 1 : 0);
    final maxRows = constraints.maxRows;
    final bodyRows = maxRows == null
        ? _rowCount
        : (maxRows - headerRows).clamp(0, maxRows);
    _syncVisibleRange(bodyRows);
    _syncViewport(headerRows);
    final naturalRows = headerRows + (maxRows == null ? _rowCount : bodyRows);
    return constraints.constrain(CellSize(_tableWidth, naturalRows));
  }

  List<int> _resolveColumnWidths(int? maxCols) {
    final count = _columns.length;
    final widths = List<int>.filled(count, 0);
    final flexFactors = List<int>.filled(count, 0);
    var rigid = 0;
    var flexTotal = 0;
    for (var i = 0; i < count; i++) {
      switch (_columns[i].width) {
        case FixedColumnWidth(:final width):
          widths[i] = width < 0 ? 0 : width;
          rigid += widths[i];
        case FlexColumnWidth(:final flex):
          final safeFlex = flex < 1 ? 1 : flex;
          flexFactors[i] = safeFlex;
          flexTotal += safeFlex;
        default:
          widths[i] = _titleWidth(_columns[i].title);
          rigid += widths[i];
      }
    }
    if (flexTotal > 0) {
      final gaps = _columnSpacing * (count - 1);
      final available = maxCols ?? rigid + gaps + flexTotal * 8;
      var remaining = available - rigid - gaps;
      if (remaining < 0) remaining = 0;
      var distributed = 0;
      for (var i = 0; i < count; i++) {
        if (flexFactors[i] == 0) continue;
        widths[i] = remaining * flexFactors[i] ~/ flexTotal;
        distributed += widths[i];
      }
      var leftover = remaining - distributed;
      for (var i = 0; i < count && leftover > 0; i++) {
        if (flexFactors[i] == 0) continue;
        widths[i] += 1;
        leftover -= 1;
      }
    }
    return widths;
  }

  int _titleWidth(String text) {
    final sanitized = sanitizeForDisplay(text);
    final width = _widthResolver.widthOfText(sanitized, _profile);
    return width < 1 ? 1 : width;
  }

  void _syncVisibleRange(int bodyRows) {
    if (_rowCount <= 0 || bodyRows <= 0) {
      _visibleFirst = 0;
      _visibleRows = 0;
      return;
    }
    final selected = _selectedRow.clamp(0, _rowCount - 1);
    var first = _visibleFirst.clamp(0, _rowCount - 1);
    if (selected < first) first = selected;
    if (selected >= first + bodyRows) first = selected - bodyRows + 1;
    final maxFirst = (_rowCount - bodyRows).clamp(0, _rowCount - 1);
    if (first > maxFirst) first = maxFirst;
    _visibleFirst = first;
    _visibleRows = bodyRows > _rowCount ? _rowCount : bodyRows;
    if (_visibleFirst + _visibleRows > _rowCount) {
      _visibleRows = _rowCount - _visibleFirst;
    }
  }

  void _syncViewport(int bodyTop) {
    final columnStarts = List<int>.filled(_columns.length, 0);
    var x = 0;
    for (var col = 0; col < _columns.length; col++) {
      columnStarts[col] = x;
      x += _columnWidths[col] + _columnSpacing;
    }
    _onViewport(
      DataTableViewportMetrics(
        visibleFirst: _visibleFirst,
        visibleRows: _visibleRows,
        bodyTop: bodyTop,
        columnStarts: List<int>.unmodifiable(columnStarts),
        columnWidths: List<int>.unmodifiable(_columnWidths),
        tableWidth: _tableWidth,
      ),
    );
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (_columns.isEmpty || size.cols <= 0 || size.rows <= 0) return;
    final colX = List<int>.filled(_columns.length, 0);
    var x = 0;
    for (var col = 0; col < _columns.length; col++) {
      colX[col] = x;
      x += _columnWidths[col] + _columnSpacing;
    }
    for (var col = 0; col < _columns.length; col++) {
      _writeCell(
        buffer,
        offset + CellOffset(colX[col], 0),
        _columns[col].title,
        _columnWidths[col],
        _columns[col].headerStyle,
      );
    }
    var bodyTop = 1;
    if (_headerSeparator && size.rows > 1) {
      _writeRule(buffer, offset + const CellOffset(0, 1));
      bodyTop = 2;
    }
    final selectionRange = _effectiveSelectionRange();
    for (var visible = 0; visible < _visibleRows; visible++) {
      final rowIndex = _visibleFirst + visible;
      final y = bodyTop + visible;
      if (y >= size.rows) break;
      final selectedRow =
          _selectionMode == DataTableSelectionMode.row &&
          rowIndex == _selectedRow;
      if (selectedRow) _fillRow(buffer, offset + CellOffset(0, y));
      for (var col = 0; col < _columns.length; col++) {
        final text = _cellBuilder(rowIndex, _columns[col].id);
        final selectedCell =
            selectedRow ||
            (_selectionMode == DataTableSelectionMode.cell &&
                selectionRange.containsCell(rowIndex, col));
        final style = selectedCell
            ? _columns[col].style.merge(_selectedStyle)
            : _columns[col].style;
        _writeCell(
          buffer,
          offset + CellOffset(colX[col], y),
          text,
          _columnWidths[col],
          style,
        );
      }
    }
  }

  DataTableSelectionRange _effectiveSelectionRange() {
    final range = _selectionMode == DataTableSelectionMode.row
        ? DataTableSelectionRange.row(
            rowIndex: _selectedRow,
            columnCount: _columns.length,
          )
        : _selectionRange;
    return range.clamp(rowCount: _rowCount, columnCount: _columns.length);
  }

  void _writeRule(CellBuffer buffer, CellOffset offset) {
    final maxCols = _tableWidth < size.cols ? _tableWidth : size.cols;
    for (var col = 0; col < maxCols; col++) {
      _safeWrite(buffer, offset + CellOffset(col, 0), '─', _separatorStyle);
    }
  }

  void _fillRow(CellBuffer buffer, CellOffset offset) {
    final maxCols = _tableWidth < size.cols ? _tableWidth : size.cols;
    for (var col = 0; col < maxCols; col++) {
      _safeWrite(buffer, offset + CellOffset(col, 0), ' ', _selectedStyle);
    }
  }

  void _writeCell(
    CellBuffer buffer,
    CellOffset offset,
    String text,
    int width,
    CellStyle style,
  ) {
    if (width <= 0) return;
    final clipped = _clipToWidth(text, width);
    if (clipped.isEmpty) return;
    if (offset.row < 0 || offset.row >= buffer.size.rows) return;
    if (offset.col < 0 || offset.col >= buffer.size.cols) return;
    buffer.writeText(
      offset,
      clipped,
      style: style,
      widthResolver: _widthResolver,
      profile: _profile,
    );
  }

  String _clipToWidth(String text, int width) {
    final sanitized = sanitizeForDisplay(
      // Collapse breaks to spaces BEFORE sanitizing — sanitizeForDisplay would
      // otherwise turn \r\n into U+FFFD first, making this replace a no-op.
      text.replaceAll(RegExp(r'[\r\n]'), ' '),
    );
    var used = 0;
    final out = StringBuffer();
    for (final grapheme in sanitized.characters) {
      final next = _widthResolver.widthOfGrapheme(grapheme, _profile);
      if (next <= 0) continue;
      if (used + next > width) break;
      out.write(grapheme);
      used += next;
    }
    return out.toString();
  }

  void _safeWrite(
    CellBuffer buffer,
    CellOffset offset,
    String grapheme,
    CellStyle style,
  ) {
    if (offset.row < 0 ||
        offset.row >= buffer.size.rows ||
        offset.col < 0 ||
        offset.col >= buffer.size.cols) {
      return;
    }
    buffer.writeGrapheme(offset, grapheme, style: style);
  }
}
