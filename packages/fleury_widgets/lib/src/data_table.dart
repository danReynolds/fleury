import 'dart:async' show FutureOr, unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'component_theme.dart';
import 'table.dart' show FixedColumnWidth, FlexColumnWidth, TableColumnWidth;
import 'tabular_export.dart';

/// Direction for an app-provided [DataTable] sort state.
enum DataTableSortDirection { ascending, descending }

/// Interaction model used by [DataTable].
enum DataTableSelectionMode {
  /// Browse rows, then confirm a choice with click or Enter.
  row,

  /// Navigate cells independently of a rectangular selection for copying.
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

  @override
  bool operator ==(Object other) =>
      other is DataTableSelectionRange &&
      anchorRow == other.anchorRow &&
      anchorColumn == other.anchorColumn &&
      focusRow == other.focusRow &&
      focusColumn == other.focusColumn;

  @override
  int get hashCode =>
      Object.hash(anchorRow, anchorColumn, focusRow, focusColumn);

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

String _formatExportLine(
  Iterable<String> fields,
  DataTableExportFormat format,
) => formatExportLine(fields, csv: format == DataTableExportFormat.csv);

String _sanitizeExportField(String field) => sanitizeExportField(field);

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
    const CapabilityTruth(
      feature: TerminalFeature.clipboardWrite,
      support: CapabilitySupport.supported,
      enablement: CapabilityEnablement.notApplicable,
      delivery: CapabilityDelivery.notApplicable,
      evidence: <CapabilityEvidence>[
        CapabilityEvidence(
          source: CapabilityEvidenceSource.fallback,
          detail: 'The in-process clipboard register is available.',
        ),
      ],
    ),
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
    this.style = CellStyle.none,
    this.headerStyle = const CellStyle(bold: true),
    this.sortable = false,
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

  /// Whether this header may request an app-owned sort through
  /// [DataTable.onSort].
  ///
  /// Sortability is column-specific even though the callback lives on the
  /// table: the column declares eligibility, then [DataTable.onSort] receives
  /// its [id]. The app still owns the data, comparator, and direction toggle.
  final bool sortable;
}

/// Builds the text for one [DataTable] cell.
typedef DataTableCellBuilder = String Function(int rowIndex, String columnId);

/// Builds a stable semantic key for one [DataTable] row.
typedef DataTableRowKeyBuilder = Object Function(int rowIndex);

/// Navigation and range-selection state for [DataTable].
class DataTableController extends ChangeNotifier {
  DataTableController({int initialRowIndex = 0, int initialColumnIndex = 0})
    : _currentRowIndex = initialRowIndex,
      _currentColumnIndex = initialColumnIndex,
      _anchorRow = initialRowIndex,
      _anchorColumn = initialColumnIndex,
      _rangeRow = initialRowIndex,
      _rangeColumn = initialColumnIndex;

  int _currentRowIndex;
  int _currentColumnIndex;
  int _anchorRow;
  int _anchorColumn;
  int _rangeRow;
  int _rangeColumn;
  int _rowCount = 0;
  int _columnCount = 0;
  bool _disposed = false;
  Object? _owner;

  void _attach(Object owner) {
    _checkNotDisposed();
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError(
        'DataTableController can attach to only one owning view at a time.',
      );
    }
    _owner = owner;
  }

  void _detach(Object owner) {
    if (identical(_owner, owner)) _owner = null;
  }

  /// Remembered navigation row, independent of the selected cell range.
  int get currentRowIndex => _currentRowIndex;
  set currentRowIndex(int value) => _moveCurrentTo(value, _currentColumnIndex);

  /// Remembered navigation column, independent of the selected cell range.
  int get currentColumnIndex => _currentColumnIndex;
  set currentColumnIndex(int value) => _moveCurrentTo(_currentRowIndex, value);

  void _moveCurrentTo(int rowIndex, int columnIndex) {
    _checkNotDisposed();
    _currentRowIndex = _clamp(rowIndex);
    _currentColumnIndex = _clampColumn(columnIndex);
    // An explicit navigation request also reveals an unchanged current row
    // after the user has scrolled it out of view.
    notifyListeners();
  }

  /// Total row / column counts, so callers can tell when the cursor sits on
  /// an edge (e.g. to bubble an arrow key for boundary focus escape).
  int get rowCount => _rowCount;
  int get columnCount => _columnCount;

  /// Selected cells, independent of the navigation cursor.
  DataTableSelectionRange get selectionRange => DataTableSelectionRange(
    anchorRow: _anchorRow,
    anchorColumn: _anchorColumn,
    focusRow: _rangeRow,
    focusColumn: _rangeColumn,
  ).clamp(rowCount: _rowCount, columnCount: _columnCount);

  /// Selects and reveals a cell. With [extend], keeps the existing range anchor.
  void selectCell(int rowIndex, int columnIndex, {bool extend = false}) {
    _checkNotDisposed();
    final row = _clamp(rowIndex);
    final column = _clampColumn(columnIndex);
    _currentRowIndex = row;
    _currentColumnIndex = column;
    _rangeRow = row;
    _rangeColumn = column;
    if (!extend) {
      _anchorRow = row;
      _anchorColumn = column;
    }
    // Also notify for an explicit reveal of the same selected cell.
    notifyListeners();
  }

  /// Selects a cell relative to the cursor, optionally extending the range.
  void moveSelection({
    int rowDelta = 0,
    int columnDelta = 0,
    bool extend = false,
  }) {
    _checkNotDisposed();
    selectCell(
      _currentRowIndex + rowDelta,
      _currentColumnIndex + columnDelta,
      extend: extend,
    );
  }

  // Publish dimensions, cursor, and both range endpoints as one coherent state.
  void _updateDimensions({
    required int rowCount,
    required int columnCount,
    int? currentRowIndex,
  }) {
    _checkNotDisposed();
    final rows = rowCount < 0 ? 0 : rowCount;
    final columns = columnCount < 0 ? 0 : columnCount;
    final maxRow = rows <= 0 ? 0 : rows - 1;
    final maxColumn = columns <= 0 ? 0 : columns - 1;
    final row = (currentRowIndex ?? _currentRowIndex).clamp(0, maxRow);
    final column = _currentColumnIndex.clamp(0, maxColumn);
    final anchorRow = _anchorRow.clamp(0, maxRow);
    final anchorColumn = _anchorColumn.clamp(0, maxColumn);
    final rangeRow = _rangeRow.clamp(0, maxRow);
    final rangeColumn = _rangeColumn.clamp(0, maxColumn);
    if (_rowCount == rows &&
        _columnCount == columns &&
        _currentRowIndex == row &&
        _currentColumnIndex == column &&
        _anchorRow == anchorRow &&
        _anchorColumn == anchorColumn &&
        _rangeRow == rangeRow &&
        _rangeColumn == rangeColumn) {
      return;
    }
    _rowCount = rows;
    _columnCount = columns;
    _currentRowIndex = row;
    _currentColumnIndex = column;
    _anchorRow = anchorRow;
    _anchorColumn = anchorColumn;
    _rangeRow = rangeRow;
    _rangeColumn = rangeColumn;
    notifyListeners();
  }

  int _clamp(int value) {
    if (_owner == null) return value < 0 ? 0 : value;
    if (_rowCount <= 0) return 0;
    return value.clamp(0, _rowCount - 1);
  }

  int _clampColumn(int value) {
    if (_owner == null) return value < 0 ? 0 : value;
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

/// A virtualized table for large collections of text rows.
///
/// Row mode uses arrows to browse and click or Enter to choose. Cell mode
/// keeps the navigation cursor separate from a range selected for copying;
/// Enter or double-click runs a row command. The wheel only scrolls.
/// Ctrl+C copies the current row or selected cell range as TSV or CSV.
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
    this.currentRowIndex,
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.onAction,
    this.onFocusedItemChanged,
    this.onRangeChanged,
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
  }) : assert(
         controller == null || currentRowIndex == null,
         'Use either controller or currentRowIndex to own the row cursor.',
       ),
       assert(
         selectionMode == DataTableSelectionMode.row || onSelect == null,
         'Use onAction for a row command in cell mode.',
       ),
       assert(
         selectionMode == DataTableSelectionMode.cell || onAction == null,
         'Use onSelect to confirm a row in row mode.',
       ),
       assert(
         selectionMode == DataTableSelectionMode.cell || onRangeChanged == null,
         'onRangeChanged is available in cell mode.',
       );

  /// Number of source rows available to the table.
  final int rowCount;

  /// Column definitions, in display order.
  final List<DataTableColumn> columns;

  /// Returns the display text for a visible cell.
  final DataTableCellBuilder cellBuilder;

  /// Optional stable row identity used by semantics and copy callbacks.
  final DataTableRowKeyBuilder? rowKeyBuilder;

  /// External navigation and range controller. If omitted, the table owns one.
  final DataTableController? controller;

  /// Parent-owned browsing row. Supply [onFocusedItemChanged] to accept input
  /// requests by rebuilding with the requested row. Ignored requests leave the
  /// cursor at this value. Out-of-range values are clamped to the available rows.
  ///
  /// Update this and [rowCount] together when filtering or replacing data. This
  /// live value cannot be combined with [controller]. If omitted, the supplied
  /// controller or an internal controller owns navigation. It does not invoke
  /// [onSelect] or change the independently selected cell range.
  final int? currentRowIndex;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the table should request focus when mounted.
  final bool autofocus;

  /// Confirms a row on a completed click, Enter, or semantic select/press.
  /// Available in row mode. Reconfirming the same row calls this again.
  final void Function(int rowIndex)? onSelect;

  /// Runs a row command on Enter, a completed double-click, or semantic press.
  /// Available in cell mode; selecting a cell range does not invoke it.
  final void Function(int rowIndex)? onAction;

  /// Reports user navigation to a different row, including pointer and semantic
  /// input. Column-only movement, scrolling, and controller writes do not fire it.
  final void Function(int rowIndex)? onFocusedItemChanged;

  /// Reports a changed cell range after user selection, including semantic
  /// selection. Navigation alone and programmatic controller writes do not fire
  /// it. Available in cell mode.
  final void Function(DataTableSelectionRange range)? onRangeChanged;

  /// Whether typing a printable character moves the cursor to the next
  /// row whose first-column cell starts with it (grid type-ahead). On by
  /// default. Turn it off when the surrounding app binds bare printables
  /// (a vim-style command key, a `q` quit): a focused table with
  /// type-ahead on consumes every printable before those bindings see it.
  final bool typeahead;

  /// Choose rows with click/Enter, or select cell ranges and invoke a separate
  /// row command with double-click/Enter.
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

  /// Style merged onto the current row in row mode or selected cells in cell mode.
  final CellStyle? selectedStyle;

  /// App-owned sort column identifier exposed through semantics.
  final String? sortColumnId;

  /// App-owned sort direction exposed through semantics.
  final DataTableSortDirection? sortDirection;

  /// Called with an eligible column's id when its header is clicked or
  /// semantically activated, so the app can (re)sort.
  ///
  /// A column is eligible only when its [DataTableColumn.sortable] flag is
  /// true. The app owns the data, comparator, and direction toggle; update
  /// [sortColumnId] and [sortDirection] to paint and expose the resulting sort
  /// state.
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
  bool _syncingController = false;

  int _visibleRows = 1;
  DataTableViewportMetrics _viewport = DataTableViewportMetrics.empty;
  _DataTablePointerHit? _pendingPointerHit;
  CellOffset? _pressPosition;
  Object? _pressKey;
  int _firstRow = 0;
  int _revealRevision = 0;
  final Stopwatch _clickClock = Stopwatch()..start();
  Duration? _lastClickAt;
  CellOffset? _lastClickPosition;
  Object? _lastClickKey;
  int? _lastClickColumn;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'DataTable');
    _ownsFocusNode = widget.focusNode == null;
    _controller = widget.controller ?? DataTableController();
    _ownsController = widget.controller == null;
    _controller._attach(this);
    _syncController();
    _controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(DataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionMode != oldWidget.selectionMode ||
        widget.rowCount != oldWidget.rowCount ||
        !_sameColumnIds(widget.columns, oldWidget.columns)) {
      _cancelPointer();
    }
    if (widget.controller != oldWidget.controller) {
      _revealRevision++;
      _cancelPointer();
      _controller.removeListener(_onChange);
      _controller._detach(this);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? DataTableController();
      _ownsController = widget.controller == null;
      _controller._attach(this);
      _controller.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'DataTable');
      _ownsFocusNode = widget.focusNode == null;
    }
    _syncController();
  }

  bool _sameColumnIds(List<DataTableColumn> a, List<DataTableColumn> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _syncController() {
    final row = _controller.currentRowIndex;
    final column = _controller.currentColumnIndex;
    _syncingController = true;
    try {
      _controller._updateDimensions(
        rowCount: widget.rowCount,
        columnCount: widget.columns.length,
        currentRowIndex: widget.currentRowIndex,
      );
      if (row != _controller.currentRowIndex ||
          column != _controller.currentColumnIndex) {
        _revealRevision++;
      }
    } finally {
      _syncingController = false;
    }
  }

  void _prepareCurrent() {
    // Each interaction starts from the parent's accepted cursor.
    if (widget.currentRowIndex != null) _syncController();
  }

  void _onChange() {
    if (!_syncingController) setState(() => _revealRevision++);
  }

  void _onFocusDetectorChange(bool focused) => setState(() {});

  @override
  void deactivate() {
    _controller.removeListener(_onChange);
    _controller._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _controller._attach(this);
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller._detach(this);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelection() async {
    _prepareCurrent();
    if (widget.columns.isEmpty || widget.rowCount <= 0) return;
    final focusRow = widget.selectionMode == DataTableSelectionMode.row
        ? _controller.currentRowIndex
        : _controller.selectionRange.focusRow;
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

  void _interact(void Function() update) {
    final controller = _controller;
    final row = controller.currentRowIndex;
    final range = controller.selectionRange;
    update();
    if (!mounted || !identical(controller, _controller)) return;
    final nextRow = controller.currentRowIndex;
    final nextRange = controller.selectionRange;
    if (row != nextRow) widget.onFocusedItemChanged?.call(nextRow);
    if (!mounted ||
        !identical(controller, _controller) ||
        controller.currentRowIndex != nextRow ||
        controller.selectionRange != nextRange) {
      return;
    }
    if (widget.selectionMode == DataTableSelectionMode.cell &&
        range != nextRange) {
      widget.onRangeChanged?.call(nextRange);
    }
  }

  void _confirmCurrent() {
    if (!mounted || widget.rowCount <= 0 || widget.columns.isEmpty) return;
    final callback = widget.selectionMode == DataTableSelectionMode.row
        ? widget.onSelect
        : widget.onAction;
    callback?.call(_controller.currentRowIndex);
  }

  bool _moveTo(
    int row,
    int column, {
    bool extend = false,
    bool select = false,
    bool keyboard = false,
  }) {
    final controller = _controller;
    final mode = widget.selectionMode;
    final nextRow = controller._clamp(row);
    final nextColumn = controller._clampColumn(column);
    final key = _rowKey(nextRow);
    final columnId = widget.columns[nextColumn].id;
    _interact(() {
      if (widget.selectionMode == DataTableSelectionMode.cell &&
          (extend || select)) {
        if (keyboard &&
            extend &&
            (controller._rangeRow != controller.currentRowIndex ||
                controller._rangeColumn != controller.currentColumnIndex)) {
          // Start a new keyboard range from the cursor after plain navigation.
          controller._anchorRow = controller.currentRowIndex;
          controller._anchorColumn = controller.currentColumnIndex;
        }
        controller.selectCell(row, column, extend: extend);
      } else {
        controller._moveCurrentTo(row, column);
      }
    });
    // A preview/range callback may replace the table or move the cursor. Never
    // turn that into a command on a different row than the input addressed.
    return mounted &&
        identical(controller, _controller) &&
        widget.selectionMode == mode &&
        nextRow < widget.rowCount &&
        nextColumn < widget.columns.length &&
        controller.currentRowIndex == nextRow &&
        controller.currentColumnIndex == nextColumn &&
        _rowKey(nextRow) == key &&
        widget.columns[nextColumn].id == columnId;
  }

  void _moveBy({int rowDelta = 0, int columnDelta = 0, bool extend = false}) =>
      _moveTo(
        _controller.currentRowIndex + rowDelta,
        _controller.currentColumnIndex + columnDelta,
        extend: extend,
        keyboard: true,
      );

  Future<bool> _handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  ) async {
    _prepareCurrent();
    final header = target.state['header'] == true;
    if (header) {
      final columnId = target.state['columnId'];
      if (action == SemanticAction.activate &&
          columnId is String &&
          _canSortColumn(columnId)) {
        widget.onSort!(columnId);
        return true;
      }
      return false;
    }
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.select:
      case SemanticAction.activate:
        _resetClickSeries();
        if (widget.rowCount <= 0 || widget.columns.isEmpty) {
          if (action != SemanticAction.focus) return false;
          _focusNode.requestFocus();
          return true;
        }
        final row = target.state['rowIndex'];
        final column = target.state['columnIndex'];
        _focusNode.requestFocus();
        if (!mounted) return false;
        final moved = _moveTo(
          row is int ? row : _controller.currentRowIndex,
          column is int ? column : _controller.currentColumnIndex,
          select: action == SemanticAction.select,
        );
        if (moved &&
            (action == SemanticAction.activate ||
                (action == SemanticAction.select &&
                    widget.selectionMode == DataTableSelectionMode.row))) {
          _confirmCurrent();
        }
        return true;
      case SemanticAction.copy:
        if (!widget.copySelectedRow) return false;
        await _copySelection();
        return true;
      case _:
        return false;
    }
  }

  /// Navigate to a row index without confirming it or changing a cell range.
  bool _handleSemanticSetValue(SemanticNode target, Object? value) {
    _prepareCurrent();
    if (target.role != SemanticRole.table || widget.rowCount <= 0) return false;
    final index = coerceSemanticInt(value);
    if (index == null) return false;
    _resetClickSeries();
    _focusNode.requestFocus();
    _moveTo(index, _controller.currentColumnIndex);
    return true;
  }

  DataTableSelectionRange _copyRangeForCurrentMode() {
    final range = widget.selectionMode == DataTableSelectionMode.row
        ? DataTableSelectionRange.row(
            rowIndex: _controller.currentRowIndex,
            columnCount: widget.columns.length,
          )
        : _controller.selectionRange;
    return range.clamp(
      rowCount: widget.rowCount,
      columnCount: widget.columns.length,
    );
  }

  bool _canSortColumn(String columnId) {
    if (widget.onSort == null) return false;
    for (final column in widget.columns) {
      if (column.id == columnId) return column.sortable;
    }
    return false;
  }

  KeyEventResult _onKey(KeyEvent event) {
    _prepareCurrent();
    _resetClickSeries();
    if (widget.rowCount <= 0 || widget.columns.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (widget.copySelectedRow &&
        widget.columns.isNotEmpty &&
        event.hasCtrl &&
        event.code.character?.toLowerCase() == 'c') {
      unawaited(_copySelection());
      return KeyEventResult.handled;
    }
    final extend = event.hasShift;
    switch (event.code) {
      // Boundary escape: an arrow at the grid edge bubbles so focus can leave
      // the table (Tab/Shift+Tab and Esc also leave). Shift-extends never
      // escape — they're an editing gesture, not navigation.
      case KeyCode.arrowUp:
        return moveOrEscape(
          atEdge: !extend && _controller.currentRowIndex <= 0,
          move: () => _moveBy(rowDelta: -1, extend: extend),
        );
      case KeyCode.arrowDown:
        return moveOrEscape(
          atEdge:
              !extend &&
              _controller.currentRowIndex >= _controller.rowCount - 1,
          move: () => _moveBy(rowDelta: 1, extend: extend),
        );
      case KeyCode.arrowLeft:
        if (widget.selectionMode != DataTableSelectionMode.cell) {
          return KeyEventResult.ignored;
        }
        return moveOrEscape(
          atEdge: !extend && _controller.currentColumnIndex <= 0,
          move: () => _moveBy(columnDelta: -1, extend: extend),
        );
      case KeyCode.arrowRight:
        if (widget.selectionMode != DataTableSelectionMode.cell) {
          return KeyEventResult.ignored;
        }
        return moveOrEscape(
          atEdge:
              !extend &&
              _controller.currentColumnIndex >= _controller.columnCount - 1,
          move: () => _moveBy(columnDelta: 1, extend: extend),
        );
      case KeyCode.pageUp:
        _moveBy(rowDelta: -_visibleRows, extend: extend);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        _moveBy(rowDelta: _visibleRows, extend: extend);
        return KeyEventResult.handled;
      case KeyCode.home:
        // Ctrl+Home → first cell (0,0) in cell mode; plain Home → top row,
        // same column (WAI-ARIA grid).
        final homeColumn =
            event.hasCtrl && widget.selectionMode == DataTableSelectionMode.cell
            ? 0
            : _controller.currentColumnIndex;
        _moveTo(0, homeColumn, extend: extend, keyboard: true);
        return KeyEventResult.handled;
      case KeyCode.end:
        final endColumn =
            event.hasCtrl && widget.selectionMode == DataTableSelectionMode.cell
            ? _controller.columnCount - 1
            : _controller.currentColumnIndex;
        _moveTo(widget.rowCount - 1, endColumn, extend: extend, keyboard: true);
        return KeyEventResult.handled;
      case const KeyCode.char(' '):
        if (widget.selectionMode != DataTableSelectionMode.cell) {
          return KeyEventResult.ignored;
        }
        _moveTo(
          _controller.currentRowIndex,
          _controller.currentColumnIndex,
          select: true,
        );
        return KeyEventResult.handled;
      case KeyCode.enter:
        _confirmCurrent();
        return KeyEventResult.handled;
      default:
        final ch = event.code.character;
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

  /// Move the cursor to the next row whose first-column cell starts with
  /// [ch] (wrapping) — spreadsheet/grid type-ahead.
  KeyEventResult _typeahead(String ch) {
    final columnId = widget.columns.first.id;
    final lower = ch.toLowerCase();
    final start = _controller.currentRowIndex + 1;
    for (var k = 0; k < widget.rowCount; k++) {
      final i = (start + k) % widget.rowCount;
      if (widget.cellBuilder(i, columnId).toLowerCase().startsWith(lower)) {
        _moveTo(i, _controller.currentColumnIndex);
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
      selectedRow: widget.currentRowIndex == null
          ? _controller.currentRowIndex
          : _controller._clamp(widget.currentRowIndex!),
      selectedColumn: _controller.currentColumnIndex,
      viewportStart: _firstRow,
      revealRevision: _revealRevision,
      currentStyle: _focusNode.hasFocus
          ? theme.focusedStyle.merge(const CellStyle(underline: true))
          : CellStyle.none,
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
        _firstRow = viewport.visibleFirst;
        _visibleRows = viewport.visibleRows < 1 ? 1 : viewport.visibleRows;
      },
      onSelect: widget.selectionMode == DataTableSelectionMode.row
          ? widget.onSelect
          : widget.onAction,
      sortingEnabled: widget.onSort != null,
      onSemanticAction: _handleSemanticAction,
      onSemanticSetValue: _handleSemanticSetValue,
    );
    return FocusDetector(
      onFocusChange: _onFocusDetectorChange,
      child: KeyDetector(
        onKey: (event) {
          if (_onKey(event) == KeyEventResult.handled) event.consume();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          child: MouseRegion(
            onScroll: (details) =>
                details.delta.row != 0 && _scrollBy(details.delta.row),
            child: GestureDetector(
              onTapDown: (details) {
                _pressPosition = details.globalPosition;
                _pendingPointerHit = _hitTestPointer(
                  details.globalPosition.col,
                  details.globalPosition.row,
                  details.modifiers,
                );
                final row = _pendingPointerHit?.rowIndex;
                _pressKey = row == null ? null : _rowKey(row);
              },
              onTapUp: _completeClick,
              onTapCancel: _cancelPointer,
              onDragStart: (_) => _cancelPointer(),
              child: table,
            ),
          ),
        ),
      ),
    );
  }

  Object _rowKey(int row) => widget.rowKeyBuilder?.call(row) ?? row;

  void _resetClickSeries() {
    _lastClickAt = null;
    _lastClickPosition = null;
    _lastClickKey = null;
    _lastClickColumn = null;
  }

  void _cancelPointer() {
    _pendingPointerHit = null;
    _pressPosition = null;
    _pressKey = null;
    _resetClickSeries();
  }

  void _completeClick(PointerDetails details) {
    _prepareCurrent();
    final hit = _pendingPointerHit;
    final pressedAt = _pressPosition;
    final key = _pressKey;
    _pendingPointerHit = null;
    _pressPosition = null;
    _pressKey = null;
    final released = _hitTestPointer(
      details.globalPosition.col,
      details.globalPosition.row,
      details.modifiers,
    );
    if (hit == null ||
        released == null ||
        pressedAt != details.globalPosition ||
        hit.rowIndex != released.rowIndex ||
        hit.columnIndex != released.columnIndex ||
        hit.sortColumnId != released.sortColumnId ||
        (hit.rowIndex != null && key != _rowKey(hit.rowIndex!))) {
      _resetClickSeries();
      return;
    }
    _focusNode.requestFocus();
    if (!mounted) return;
    final sortColumn = hit.sortColumnId;
    if (sortColumn != null) {
      _resetClickSeries();
      if (_canSortColumn(sortColumn)) widget.onSort!(sortColumn);
      return;
    }
    final row = hit.rowIndex!;
    final now = _clickClock.elapsed;
    final doubleClick =
        !hit.extend &&
        _lastClickAt != null &&
        now - _lastClickAt! < const Duration(milliseconds: 500) &&
        _lastClickPosition == details.globalPosition &&
        _lastClickKey == key &&
        _lastClickColumn == hit.columnIndex;
    if (hit.extend || doubleClick) {
      _resetClickSeries();
    } else {
      _lastClickAt = now;
      _lastClickPosition = details.globalPosition;
      _lastClickKey = key;
      _lastClickColumn = hit.columnIndex;
    }
    // The second click invokes the command without collapsing a selected range.
    final moved = _moveTo(
      row,
      hit.columnIndex ?? _controller.currentColumnIndex,
      extend: hit.extend,
      select: !doubleClick,
    );
    if (moved &&
        (widget.selectionMode == DataTableSelectionMode.row || doubleClick)) {
      _confirmCurrent();
    }
  }

  bool _scrollBy(int delta) {
    _cancelPointer();
    final count = widget.rowCount < 0 ? 0 : widget.rowCount;
    final maxFirst = (count - _visibleRows).clamp(0, count);
    final next = (_firstRow + delta).clamp(0, maxFirst);
    if (next == _firstRow) return false;
    setState(() => _firstRow = next);
    return true;
  }

  _DataTablePointerHit? _hitTestPointer(
    int col,
    int row,
    Set<KeyModifier> modifiers,
  ) {
    final rect = _focusNode.rect;
    if (rect == null) return null;
    final localCol = col - rect.left;
    final localRow = row - rect.top;
    if (localCol < 0 || localCol >= _viewport.tableWidth || localRow < 0) {
      return null;
    }
    final columnIndex = _viewport.columnAt(localCol);
    if (localRow == 0) {
      if (columnIndex == null) return null;
      final column = widget.columns[columnIndex];
      if (!_canSortColumn(column.id)) return null;
      return _DataTablePointerHit.header(column.id);
    }
    if (!_viewport.hasBodyRows ||
        localRow < _viewport.bodyTop ||
        localRow >= _viewport.bodyTop + _viewport.visibleRows) {
      return null;
    }
    final rowIndex = _viewport.visibleFirst + localRow - _viewport.bodyTop;
    if (rowIndex < 0 || rowIndex >= widget.rowCount) return null;
    if (widget.selectionMode == DataTableSelectionMode.cell &&
        columnIndex == null) {
      return null;
    }
    return _DataTablePointerHit.body(
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      extend: modifiers.contains(KeyModifier.shift),
    );
  }
}

final class _DataTablePointerHit {
  const _DataTablePointerHit.body({
    required this.rowIndex,
    required this.columnIndex,
    required this.extend,
  }) : sortColumnId = null;

  const _DataTablePointerHit.header(String columnId)
    : rowIndex = null,
      columnIndex = null,
      extend = false,
      sortColumnId = columnId;

  final int? rowIndex;
  final int? columnIndex;
  final bool extend;
  final String? sortColumnId;
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
    required this.viewportStart,
    required this.revealRevision,
    required this.currentStyle,
    required this.selectionRange,
    required this.selectionMode,
    required this.focusNode,
    required this.columnSpacing,
    required this.headerSeparator,
    required this.separatorStyle,
    required this.selectedStyle,
    required this.onViewport,
    required this.onSelect,
    required this.sortingEnabled,
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
  final int viewportStart;
  final int revealRevision;
  final CellStyle currentStyle;
  final DataTableSelectionRange selectionRange;
  final DataTableSelectionMode selectionMode;
  final FocusNode focusNode;
  final int columnSpacing;
  final bool headerSeparator;
  final CellStyle separatorStyle;
  final CellStyle selectedStyle;
  final void Function(DataTableViewportMetrics viewport) onViewport;
  final void Function(int rowIndex)? onSelect;
  final bool sortingEnabled;
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
      policy: MediaQuery.textPolicyOf(context).widths,
      rowCount: rowCount,
      columns: columns,
      cellBuilder: cellBuilder,
      selectedRow: selectedRow,
      currentColumn: selectedColumn,
      viewportStart: viewportStart,
      revealRevision: revealRevision,
      currentStyle: currentStyle,
      selectionRange: selectionRange,
      selectionMode: selectionMode,
      columnSpacing: columnSpacing,
      headerSeparator: headerSeparator,
      separatorStyle: separatorStyle,
      selectedStyle: selectedStyle,
      sortColumnId: sortColumnId,
      sortDirection: sortDirection,
      onViewport: onViewport,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDataTable renderObject,
  ) {
    renderObject
      ..policy = MediaQuery.textPolicyOf(context).widths
      ..rowCount = rowCount
      ..columns = columns
      ..cellBuilder = cellBuilder
      ..selectedRow = selectedRow
      ..currentColumn = selectedColumn
      ..viewportStart = viewportStart
      ..revealRevision = revealRevision
      ..currentStyle = currentStyle
      ..selectionRange = selectionRange
      ..selectionMode = selectionMode
      ..columnSpacing = columnSpacing
      ..headerSeparator = headerSeparator
      ..separatorStyle = separatorStyle
      ..selectedStyle = selectedStyle
      ..sortColumnId = sortColumnId
      ..sortDirection = sortDirection
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
        if (widget.rowCount > 0 && widget.columns.isNotEmpty) ...{
          SemanticAction.select,
          if (widget.onSelect != null) SemanticAction.activate,
        },
        // Jump the windowed row range to a target row INDEX — the off-window
        // reach an agent otherwise can't get without resizing the whole grid.
        if (widget.rowCount > 0 && widget.columns.isNotEmpty)
          SemanticAction.setValue,
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
        'currentKey': selectedKey,
        'currentRowIndex': selected,
        if (widget.selectionMode == DataTableSelectionMode.row)
          'selectedKey': selectedKey,
        'selectionMode': widget.selectionMode.name,
        'currentColumnIndex': selectedColumn,
        'currentColumnId': selectedColumnId,
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
                  if (widget.sortingEnabled && widget.columns[col].sortable)
                    SemanticAction.activate,
                },
                state: SemanticState({
                  'rowIndex': -1,
                  'columnIndex': col,
                  'columnId': widget.columns[col].id,
                  'header': true,
                  'sortable':
                      widget.sortingEnabled && widget.columns[col].sortable,
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
    final rowSelected = widget.selectionMode == DataTableSelectionMode.row
        ? rowIndex == selected
        : range.startRow <= rowIndex && rowIndex <= range.endRow;
    return SemanticNode(
      id: SemanticNodeId(rowId),
      role: SemanticRole.tableRow,
      label: key.toString(),
      selected: rowSelected,
      focused: widget.focusNode.hasFocus && rowIndex == selected,
      actions: <SemanticAction>{
        SemanticAction.focus,
        SemanticAction.select,
        if (widget.onSelect != null) SemanticAction.activate,
        if (widget.copySelectedRow && widget.columns.isNotEmpty && rowSelected)
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
      focused:
          widget.focusNode.hasFocus &&
          rowIndex == selected &&
          columnIndex == widget.selectedColumn,
      actions: <SemanticAction>{
        SemanticAction.focus,
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
    CellWidthPolicy policy = CellWidthPolicy.spec,
    required int rowCount,
    required List<DataTableColumn> columns,
    required DataTableCellBuilder cellBuilder,
    required int selectedRow,
    required int currentColumn,
    required int viewportStart,
    required int revealRevision,
    required CellStyle currentStyle,
    required DataTableSelectionRange selectionRange,
    required DataTableSelectionMode selectionMode,
    required int columnSpacing,
    required bool headerSeparator,
    required CellStyle separatorStyle,
    required CellStyle selectedStyle,
    required String? sortColumnId,
    required DataTableSortDirection? sortDirection,
    required void Function(DataTableViewportMetrics viewport) onViewport,
  }) : _rowCount = rowCount,
       _columns = columns,
       _cellBuilder = cellBuilder,
       _selectedRow = selectedRow,
       _currentColumn = currentColumn,
       _visibleFirst = viewportStart,
       _revealRevision = revealRevision,
       _currentStyle = currentStyle,
       _selectionRange = selectionRange,
       _selectionMode = selectionMode,
       _columnSpacing = columnSpacing,
       _headerSeparator = headerSeparator,
       _separatorStyle = separatorStyle,
       _selectedStyle = selectedStyle,
       _sortColumnId = sortColumnId,
       _sortDirection = sortDirection,
       _onViewport = onViewport,
       _policy = policy;

  static const _widthResolver = DefaultWidthResolver();

  /// The surface's width policy — ambient, passed in by the widget so column
  /// measurement agrees with every other geometry consumer (RFC 0019 §6.3).
  CellWidthPolicy _policy;

  set policy(CellWidthPolicy value) {
    if (_policy == value) return;
    _policy = value;
    markNeedsLayout();
  }

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
  String? _sortColumnId;
  DataTableSortDirection? _sortDirection;
  void Function(DataTableViewportMetrics) _onViewport;

  List<int> _columnWidths = const [];
  int _visibleFirst;
  int _revealRevision;
  int _currentColumn;
  CellStyle _currentStyle;
  bool _revealCurrent = true;
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

  set viewportStart(int value) {
    if (_visibleFirst == value) return;
    _visibleFirst = value;
    _revealCurrent = false;
    markNeedsLayout();
  }

  set revealRevision(int value) {
    if (_revealRevision == value) return;
    _revealRevision = value;
    _revealCurrent = true;
    if (!_rowVisible(_selectedRow)) markNeedsLayout();
  }

  set currentColumn(int value) {
    if (_currentColumn == value) return;
    _currentColumn = value;
    markNeedsPaintOnly();
  }

  set currentStyle(CellStyle value) {
    if (_currentStyle == value) return;
    _currentStyle = value;
    markNeedsPaintOnly();
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

  set sortColumnId(String? value) {
    if (_sortColumnId == value) return;
    _sortColumnId = value;
    markNeedsPaintOnly();
  }

  set sortDirection(DataTableSortDirection? value) {
    if (_sortDirection == value) return;
    _sortDirection = value;
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
          widths[i] =
              _titleWidth(_columns[i].title) +
              (_columns[i].sortable ? _sortIndicatorWidth : 0);
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
    final width = _widthResolver.widthOfText(sanitized, _policy);
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
    if (_revealCurrent) {
      if (selected < first) first = selected;
      if (selected >= first + bodyRows) first = selected - bodyRows + 1;
      _revealCurrent = false;
    }
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
  void performPaint(CellBuffer buffer, CellOffset offset) {
    if (_columns.isEmpty || size.cols <= 0 || size.rows <= 0) return;
    final colX = List<int>.filled(_columns.length, 0);
    // Each column's PAINTED width: its resolved width, cut at the table's own
    // right edge. Fixed and title-sized columns are never shrunk by layout, so
    // `_tableWidth` can exceed `size.cols`; every write below must stay inside
    // `size` — the invariant damage tracking, repaint caches and the serve
    // wire's damage bounds rely on. `_writeRule`/`_fillRow` clamp the same way.
    final colW = List<int>.filled(_columns.length, 0);
    var x = 0;
    for (var col = 0; col < _columns.length; col++) {
      colX[col] = x;
      final room = size.cols - x;
      colW[col] = room < _columnWidths[col]
          ? (room < 0 ? 0 : room)
          : _columnWidths[col];
      x += _columnWidths[col] + _columnSpacing;
    }
    for (var col = 0; col < _columns.length; col++) {
      if (colW[col] <= 0) continue;
      _writeHeaderCell(
        buffer,
        offset + CellOffset(colX[col], 0),
        _columns[col],
        colW[col],
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
        if (colW[col] <= 0) continue;
        final text = _cellBuilder(rowIndex, _columns[col].id);
        final selectedCell =
            selectedRow ||
            (_selectionMode == DataTableSelectionMode.cell &&
                selectionRange.containsCell(rowIndex, col));
        var style = selectedCell
            ? _columns[col].style.merge(_selectedStyle)
            : _columns[col].style;
        if (rowIndex == _selectedRow &&
            (_selectionMode == DataTableSelectionMode.row ||
                col == _currentColumn)) {
          style = style.merge(_currentStyle);
        }
        _writeCell(
          buffer,
          offset + CellOffset(colX[col], y),
          text,
          colW[col],
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

  static const int _sortIndicatorWidth = 2;

  void _writeHeaderCell(
    CellBuffer buffer,
    CellOffset offset,
    DataTableColumn column,
    int width,
  ) {
    if (!column.sortable) {
      _writeCell(buffer, offset, column.title, width, column.headerStyle);
      return;
    }
    final indicator = _sortIndicatorFor(column);
    if (width < _sortIndicatorWidth) {
      _writeCell(
        buffer,
        offset,
        indicator ?? column.title,
        width,
        column.headerStyle,
      );
      return;
    }
    _writeCell(
      buffer,
      offset,
      column.title,
      width - _sortIndicatorWidth,
      column.headerStyle,
    );
    if (indicator == null) return;
    _safeWrite(
      buffer,
      offset + CellOffset(width - 1, 0),
      indicator,
      column.headerStyle,
    );
  }

  String? _sortIndicatorFor(DataTableColumn column) {
    if (_sortColumnId != column.id || _sortDirection == null) return null;
    return switch (_sortDirection!) {
      DataTableSortDirection.ascending =>
        _policy.ambiguous == CellWidth.two ? '^' : '▲',
      DataTableSortDirection.descending =>
        _policy.ambiguous == CellWidth.two ? 'v' : '▼',
    };
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
      policy: _policy,
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
      final next = _widthResolver.widthOfGrapheme(grapheme, _policy);
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
    // These are one-cell decorations, not column text. Keep their reserved
    // geometry when the terminal measures box rules / triangles as wide.
    final narrow = _widthResolver.widthOfGrapheme(grapheme, _policy) == 1;
    buffer.writeGrapheme(
      offset,
      narrow
          ? grapheme
          : switch (grapheme) {
              '▲' => '^',
              '▼' => 'v',
              _ => '-',
            },
      style: style,
      policy: _policy,
    );
  }
}
