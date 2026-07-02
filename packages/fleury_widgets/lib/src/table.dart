import 'package:fleury/fleury_core.dart';

/// How a [Table] column is sized.
sealed class TableColumnWidth {
  const TableColumnWidth();
}

/// Sizes the column to the widest cell in it (the default).
final class IntrinsicColumnWidth extends TableColumnWidth {
  const IntrinsicColumnWidth();
}

/// Sizes the column to an exact [width] in cells.
final class FixedColumnWidth extends TableColumnWidth {
  const FixedColumnWidth(this.width);
  final int width;
}

/// Takes a [flex] share of the width left after fixed/intrinsic columns
/// (and gaps). With several flex columns, space splits proportionally.
/// Falls back to intrinsic sizing when the table has no width bound.
final class FlexColumnWidth extends TableColumnWidth {
  const FlexColumnWidth([this.flex = 1]);
  final int flex;
}

/// Selected-row state for an interactive [Table]. Optional — the table
/// creates its own when none is supplied. `rowCount` is set by the widget
/// on each build, so the selection stays clamped to the visible rows.
class TableController extends ChangeNotifier {
  TableController({int? selectedIndex}) : _selectedIndex = selectedIndex;

  int? _selectedIndex;
  int _rowCount = 0;
  bool _disposed = false;

  /// Index of the highlighted body row, or null when nothing is
  /// selected. Writes outside `0..rowCount-1` are clamped.
  int? get selectedIndex => _selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    final clamped = _clamp(value);
    if (_selectedIndex == clamped) return;
    _selectedIndex = clamped;
    notifyListeners();
  }

  int? _clamp(int? value) {
    if (value == null) return null;
    if (_rowCount == 0) return value;
    return value.clamp(0, _rowCount - 1);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TableController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// A grid of cells with columns aligned across every row — the one thing
/// `Row`/`Column` can't do, since they size each row independently.
///
/// Each column's width is negotiated once over all rows (and the header),
/// per [columnWidths]; cells then lay out into those shared widths so
/// columns line up. Supply [header] for a styled top row with a rule
/// beneath it.
///
/// Cells should be content-sized (e.g. [Text]). Intrinsic columns measure
/// cells with unbounded width, so a greedy cell that fills its main axis
/// (a `Column`/`Row` with `MainAxisSize.max`) isn't a valid cell — wrap it
/// in a `SizedBox` if you need fixed dimensions.
///
/// ```dart
/// Table(
///   header: [Text('Name', style: CellStyle(bold: true)), Text('Age')],
///   columnWidths: const [IntrinsicColumnWidth(), FixedColumnWidth(3)],
///   rows: [
///     [Text('Ada'), Text('36')],
///     [Text('Linus'), Text('54')],
///   ],
/// );
/// ```
///
/// ### Selection and scrolling
///
/// Set [selectable] (or pass a [controller] / [onSelect]) to make the
/// table keyboard-navigable: Up/Down move a highlighted row, Home/End
/// jump, PageUp/PageDown page, and Enter fires [onSelect]. When the table
/// is given a bounded height (e.g. inside an `Expanded` or `SizedBox`) and
/// the body is taller than the viewport, it scrolls — the header stays
/// pinned while the body window follows the selection. Column widths are
/// still negotiated over *all* rows, so columns never jitter as you
/// scroll.
class Table extends StatefulWidget {
  Table({
    super.key,
    required this.rows,
    this.header,
    this.columnWidths,
    this.columnSpacing = 1,
    this.headerSeparator = true,
    this.separatorStyle = CellStyle.empty,
    this.selectable = false,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.selectedStyle,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.label = 'Table',
  }) : columnCount =
           header?.length ?? (rows.isNotEmpty ? rows.first.length : 0);

  /// Body rows; each is a list of cell widgets. Short rows are padded and
  /// long rows trimmed to the column count.
  final List<List<Widget>> rows;

  /// Optional header cells (style them yourself). Drawn as the top row
  /// and included in column-width negotiation.
  final List<Widget>? header;

  /// Per-column sizing. Defaults to all-intrinsic.
  final List<TableColumnWidth>? columnWidths;

  /// Blank cells between columns.
  final int columnSpacing;

  /// Draw a horizontal rule under the header (when a header is present).
  final bool headerSeparator;

  /// Style for the header rule.
  final CellStyle separatorStyle;

  /// The header column the data is sorted by (renders nothing on its own —
  /// supply a `▲`/`▼` in your header cell — but exposes the sort state in the
  /// header cell's semantics so assistive tech / the serve bridge can announce
  /// it, the WAI-ARIA `aria-sort` analog).
  final int? sortColumnIndex;

  /// Direction of [sortColumnIndex]: ascending when true, descending otherwise.
  final bool sortAscending;

  /// Whether the table is keyboard-navigable with a highlighted row.
  /// Implied when a [controller] or [onSelect] is supplied.
  final bool selectable;

  /// External selection state. If null and the table is interactive, one
  /// is created and disposed internally.
  final TableController? controller;

  /// External focus node for the interactive table.
  final FocusNode? focusNode;

  /// Request focus on first mount (interactive tables only).
  final bool autofocus;

  /// Called with the body-row index when Enter activates a row.
  final void Function(int index)? onSelect;

  /// Style merged into the highlighted row. Defaults to the theme's
  /// selection style (inverse video).
  final CellStyle? selectedStyle;

  /// Label exposed through the semantic app graph.
  final String? label;

  /// Columns, inferred from the header or first row.
  final int columnCount;

  bool get _interactive => selectable || controller != null || onSelect != null;

  @override
  State<Table> createState() => _TableState();
}

class _TableState extends State<Table> {
  TableController? _controller;
  FocusNode? _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  // Mirror of the last laid-out visible row count, for PageUp/PageDown.
  // Written from layout without notifying; read on the next key.
  int _visibleFirst = 0;
  int _visibleRows = 1;

  bool get _interactive => widget._interactive;

  @override
  void initState() {
    super.initState();
    if (_interactive) _attachInteractive();
  }

  void _attachInteractive() {
    _controller = widget.controller ?? TableController(selectedIndex: 0);
    _ownsController = widget.controller == null;
    _controller!._rowCount = widget.rows.length;
    if (_controller!._selectedIndex == null && widget.rows.isNotEmpty) {
      _controller!._selectedIndex = 0;
    } else {
      _controller!.selectedIndex = _controller!._selectedIndex;
    }
    _controller!.addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Table');
    _ownsFocusNode = widget.focusNode == null;
  }

  void _detachInteractive() {
    _controller?.removeListener(_onChange);
    if (_ownsController) _controller?.dispose();
    if (_ownsFocusNode) _focusNode?.dispose();
    _controller = null;
    _focusNode = null;
    _ownsController = false;
    _ownsFocusNode = false;
  }

  @override
  void didUpdateWidget(Table oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interactive) {
      if (_controller != null) _detachInteractive();
      return;
    }
    if (_controller == null) {
      _attachInteractive();
      return;
    }
    if (widget.controller != oldWidget.controller) {
      _controller!.removeListener(_onChange);
      if (_ownsController) _controller!.dispose();
      _controller = widget.controller ?? TableController(selectedIndex: 0);
      _ownsController = widget.controller == null;
      _controller!.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode!.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Table');
      _ownsFocusNode = widget.focusNode == null;
    }
    _controller!._rowCount = widget.rows.length;
    _controller!.selectedIndex = _controller!._selectedIndex;
  }

  void _onChange() => setState(() {});

  void _onFocusWithinChange(bool focused) {
    if (!_interactive) return;
    setState(() {});
  }

  @override
  void dispose() {
    _detachInteractive();
    super.dispose();
  }

  /// Wheel scroll moves the selection (and the window follows it, since the
  /// body window is derived from the selected row). Selection changes don't
  /// fire onSelect — that's reserved for Enter / activate — so scrolling never
  /// triggers row actions.
  void _scrollBy(int delta) {
    final controller = _controller;
    final count = widget.rows.length;
    if (controller == null || count == 0) return;
    final selected = controller.selectedIndex ?? 0;
    final next = (selected + delta).clamp(0, count - 1);
    if (next != selected) controller.selectedIndex = next;
  }

  KeyEventResult _onKey(KeyEvent event) {
    final controller = _controller;
    final count = widget.rows.length;
    if (controller == null || count == 0) return KeyEventResult.ignored;
    final selected = controller.selectedIndex;
    if (selected == null) return KeyEventResult.ignored;
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        if (selected <= 0) return KeyEventResult.handled;
        controller.selectedIndex = selected - 1;
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (selected >= count - 1) return KeyEventResult.handled;
        controller.selectedIndex = selected + 1;
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        controller.selectedIndex = (selected - _visibleRows).clamp(
          0,
          count - 1,
        );
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        controller.selectedIndex = (selected + _visibleRows).clamp(
          0,
          count - 1,
        );
        return KeyEventResult.handled;
      case KeyCode.home:
        controller.selectedIndex = 0;
        return KeyEventResult.handled;
      case KeyCode.end:
        controller.selectedIndex = count - 1;
        return KeyEventResult.handled;
      case KeyCode.enter:
        widget.onSelect?.call(selected);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.columnCount;
    if (c == 0) {
      return Semantics(
        role: SemanticRole.table,
        label: widget.label,
        state: const SemanticState({
          'collectionRowCount': 0,
          'collectionColumnCount': 0,
          'hasHeader': false,
        }),
        child: const EmptyBox(),
      );
    }
    final widths =
        widget.columnWidths ?? List.filled(c, const IntrinsicColumnWidth());
    final fittedHeader = widget.header == null
        ? null
        : _fitRow(widget.header!, c);
    final fittedRows = [for (final row in widget.rows) _fitRow(row, c)];
    final cells = <Widget>[
      if (fittedHeader != null)
        for (var col = 0; col < c; col++)
          _semanticCell(
            fittedHeader[col],
            rowIndex: -1,
            columnIndex: col,
            header: true,
          ),
      for (var row = 0; row < widget.rows.length; row++)
        for (var col = 0; col < c; col++)
          _semanticCell(
            fittedRows[row][col],
            rowIndex: row,
            columnIndex: col,
            selected: _interactive && _controller?.selectedIndex == row,
          ),
    ];
    final selectedStyle = (_focusNode?.hasFocus ?? false)
        ? widget.selectedStyle ?? Theme.of(context).selectionStyle
        : Theme.of(context).mutedStyle;
    final body = _TableBody(
      columnCount: c,
      columnWidths: widths,
      columnSpacing: widget.columnSpacing,
      hasHeader: widget.header != null,
      headerSeparator: widget.header != null && widget.headerSeparator,
      separatorStyle: widget.separatorStyle,
      selectedRow: _interactive ? _controller?.selectedIndex : null,
      selectedStyle: selectedStyle,
      onVisibleRange: (first, count) {
        _visibleFirst = first;
        _visibleRows = count < 1 ? 1 : count;
      },
      children: cells,
    );
    final selectedIndex = _controller?.selectedIndex;
    final visibleEnd = _visibleEnd();
    final state = <String, Object?>{
      'collectionRowCount': widget.rows.length,
      'collectionColumnCount': c,
      'hasHeader': widget.header != null,
    };
    if (selectedIndex != null) {
      state['selectedKey'] = selectedIndex;
    }
    if (_interactive) {
      state['visibleRangeStart'] = _visibleFirst;
    }
    if (visibleEnd != null) {
      state['visibleRangeEnd'] = visibleEnd;
    }

    final table = Semantics(
      role: SemanticRole.table,
      label: widget.label,
      value: selectedIndex,
      focused: _focusNode?.hasFocus ?? false,
      actions: _interactive
          ? <SemanticAction>{
              SemanticAction.focus,
              SemanticAction.select,
              if (widget.onSelect != null) SemanticAction.activate,
            }
          : const <SemanticAction>{},
      state: SemanticState(state),
      onAction: _interactive ? _handleTableAction : null,
      child: body,
    );
    if (!_interactive) return table;
    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKey: _onKey,
        // Wheel over the table scrolls the row window by moving the selection.
        child: PointerScrollListener(
          router: PointerRouterScope.maybeOf(context),
          onScrollUp: () => _scrollBy(-1),
          onScrollDown: () => _scrollBy(1),
          child: table,
        ),
      ),
    );
  }

  int? _visibleEnd() {
    if (!_interactive || widget.rows.isEmpty) return null;
    var end = _visibleFirst + _visibleRows - 1;
    if (end < _visibleFirst) end = _visibleFirst;
    final max = widget.rows.length - 1;
    if (end > max) end = max;
    return end;
  }

  static List<Widget> _fitRow(List<Widget> row, int c) {
    if (row.length == c) return row;
    if (row.length > c) return row.sublist(0, c);
    // Pad with a zero-size box (not EmptyBox, which produces no render
    // object) so the grid stays rectangular for the render object.
    return [
      ...row,
      for (var i = row.length; i < c; i++) const SizedBox(width: 0, height: 0),
    ];
  }

  void _handleTableAction(SemanticAction action) {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.select:
        _focusNode?.requestFocus();
        return;
      case SemanticAction.activate:
        final selected = _controller?.selectedIndex;
        if (selected != null) widget.onSelect?.call(selected);
        return;
      case _:
        return;
    }
  }

  void _handleCellAction(int rowIndex, SemanticAction action) {
    if (rowIndex < 0) return;
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.select:
        _focusNode?.requestFocus();
        _controller?.selectedIndex = rowIndex;
        return;
      case SemanticAction.activate:
        _focusNode?.requestFocus();
        _controller?.selectedIndex = rowIndex;
        widget.onSelect?.call(rowIndex);
        return;
      case _:
        return;
    }
  }

  Widget _semanticCell(
    Widget child, {
    required int rowIndex,
    required int columnIndex,
    bool header = false,
    bool selected = false,
  }) {
    final interactiveBodyCell = _interactive && !header && rowIndex >= 0;
    return Semantics(
      role: SemanticRole.tableCell,
      focused:
          interactiveBodyCell && selected && (_focusNode?.hasFocus ?? false),
      selected: selected,
      actions: interactiveBodyCell
          ? <SemanticAction>{
              SemanticAction.focus,
              SemanticAction.select,
              if (widget.onSelect != null) SemanticAction.activate,
            }
          : const <SemanticAction>{},
      state: SemanticState({
        'rowIndex': rowIndex,
        'columnIndex': columnIndex,
        'header': header,
        if (header && widget.sortColumnIndex == columnIndex) ...{
          'sortActive': true,
          'sortDirection': widget.sortAscending ? 'ascending' : 'descending',
        },
      }),
      onAction: interactiveBodyCell
          ? (action) => _handleCellAction(rowIndex, action)
          : null,
      // Click a body cell to select its row (focus + select) — the same select
      // the keyboard performs; Enter / the activate action still activates.
      child: interactiveBodyCell
          ? GestureDetector(
              onTap: () => _handleCellAction(rowIndex, SemanticAction.select),
              child: child,
            )
          : child,
    );
  }
}

class _TableBody extends MultiChildRenderObjectWidget {
  const _TableBody({
    required this.columnCount,
    required this.columnWidths,
    required this.columnSpacing,
    required this.hasHeader,
    required this.headerSeparator,
    required this.separatorStyle,
    required this.selectedRow,
    required this.selectedStyle,
    required this.onVisibleRange,
    required super.children,
  });

  final int columnCount;
  final List<TableColumnWidth> columnWidths;
  final int columnSpacing;
  final bool hasHeader;
  final bool headerSeparator;
  final CellStyle separatorStyle;
  final int? selectedRow;
  final CellStyle selectedStyle;
  final void Function(int visibleFirst, int visibleRows) onVisibleRange;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTable(
    columnCount: columnCount,
    columnWidths: columnWidths,
    columnSpacing: columnSpacing,
    hasHeader: hasHeader,
    headerSeparator: headerSeparator,
    separatorStyle: separatorStyle,
    selectedRow: selectedRow,
    selectedStyle: selectedStyle,
    onVisibleRange: onVisibleRange,
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderTable r) {
    r
      ..columnCount = columnCount
      ..columnWidths = columnWidths
      ..columnSpacing = columnSpacing
      ..hasHeader = hasHeader
      ..headerSeparator = headerSeparator
      ..separatorStyle = separatorStyle
      ..selectedRow = selectedRow
      ..selectedStyle = selectedStyle
      ..onVisibleRange = onVisibleRange;
  }
}

/// Lays cells into a grid with shared, negotiated column widths and
/// per-row heights, optionally ruling under the header row. When
/// [selectedRow] is set the body scrolls within a bounded height (header
/// pinned) and the selected row is highlighted.
class RenderTable extends RenderObject implements RenderObjectWithChildren {
  RenderTable({
    required int columnCount,
    required List<TableColumnWidth> columnWidths,
    required int columnSpacing,
    required bool hasHeader,
    required bool headerSeparator,
    required CellStyle separatorStyle,
    required int? selectedRow,
    required CellStyle selectedStyle,
    required void Function(int, int) onVisibleRange,
  }) : _columnCount = columnCount,
       _columnWidths = columnWidths,
       _columnSpacing = columnSpacing,
       _hasHeader = hasHeader,
       _headerSeparator = headerSeparator,
       _separatorStyle = separatorStyle,
       _selectedRow = selectedRow,
       _selectedStyle = selectedStyle,
       _onVisibleRange = onVisibleRange;

  int _columnCount;
  set columnCount(int v) {
    if (_columnCount == v) return;
    _columnCount = v;
    markNeedsLayout();
  }

  List<TableColumnWidth> _columnWidths;
  set columnWidths(List<TableColumnWidth> v) {
    if (_sameColumnWidths(_columnWidths, v)) return;
    _columnWidths = v;
    markNeedsLayout();
  }

  int _columnSpacing;
  set columnSpacing(int v) {
    if (_columnSpacing == v) return;
    _columnSpacing = v;
    markNeedsLayout();
  }

  bool _hasHeader;
  set hasHeader(bool v) {
    if (_hasHeader == v) return;
    _hasHeader = v;
    markNeedsLayout();
  }

  bool _headerSeparator;
  set headerSeparator(bool v) {
    if (_headerSeparator == v) return;
    _headerSeparator = v;
    markNeedsLayout();
  }

  CellStyle _separatorStyle;
  set separatorStyle(CellStyle v) {
    if (_separatorStyle == v) return;
    _separatorStyle = v;
    markNeedsPaintOnly();
  }

  int? _selectedRow;
  set selectedRow(int? v) {
    if (_selectedRow == v) return;
    final needsLayout = _selectedRowChangeNeedsLayout(v);
    _selectedRow = v;
    if (needsLayout) {
      markNeedsLayout();
    } else {
      markNeedsPaintOnly();
    }
  }

  CellStyle _selectedStyle;
  set selectedStyle(CellStyle v) {
    if (_selectedStyle == v) return;
    _selectedStyle = v;
    markNeedsPaintOnly();
  }

  void Function(int, int) _onVisibleRange;
  set onVisibleRange(void Function(int, int) v) => _onVisibleRange = v;

  final List<RenderObject> _children = <RenderObject>[];
  final Map<RenderObject, CellOffset> _offsets = <RenderObject, CellOffset>{};

  // Painted after layout.
  int _separatorRow = -1;
  int _ownWidth = 0;
  int _naturalHeight = 0;
  int _headerBlock = 0; // header row height + separator
  List<int> _rowY = const []; // natural top of each grid row
  List<int> _rowHeight = const [];
  int _bodyAnchor = 0; // first visible body row (persists across layouts)
  int _visibleFirst = 0;
  int _visibleRows = 0;
  bool _windowing = false;

  int get _headerOffset => _hasHeader ? 1 : 0;

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    if (_hasSameRenderChildrenInOrder(_children, newChildren)) return;
    final newSet = Set<RenderObject>.identity()..addAll(newChildren);
    for (final c in List<RenderObject>.from(_children)) {
      if (!newSet.contains(c)) {
        dropChild(c);
        _offsets.remove(c);
      }
    }
    final oldSet = Set<RenderObject>.identity()..addAll(_children);
    for (final c in newChildren) {
      if (!oldSet.contains(c)) adoptChild(c);
    }
    _children
      ..clear()
      ..addAll(newChildren);
    markNeedsLayout();
  }

  bool _selectedRowChangeNeedsLayout(int? next) {
    if (_rowHeight.isEmpty) return true;
    if (_selectedRow == null || next == null) return true;
    if (!_windowing) return false;
    final bodyCount = _rowHeight.length - _headerOffset;
    if (bodyCount <= 0) return false;
    final selected = next.clamp(0, bodyCount - 1);
    final last = _visibleFirst + _visibleRows - 1;
    return selected < _visibleFirst || selected > last;
  }

  TableColumnWidth _specFor(int column) => column < _columnWidths.length
      ? _columnWidths[column]
      : const IntrinsicColumnWidth();

  int _intrinsicColumnWidth(int column, int gridRows) {
    var width = 0;
    for (var r = 0; r < gridRows; r++) {
      final size = _children[r * _columnCount + column].layout(
        const CellConstraints(),
      );
      if (size.cols > width) width = size.cols;
    }
    return width;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _columnCount;
    if (c == 0 || _children.isEmpty) {
      _separatorRow = -1;
      _ownWidth = 0;
      _naturalHeight = 0;
      _windowing = false;
      return constraints.constrain(CellSize.zero);
    }
    final gridRows = _children.length ~/ c;

    // 1. Resolve column widths: fixed + intrinsic now, flex from the
    //    leftover (proportional), or intrinsic when width is unbounded.
    final widths = List<int>.filled(c, 0);
    final flexFactors = List<int>.filled(c, 0);
    var rigidSum = 0;
    var flexTotal = 0;
    for (var col = 0; col < c; col++) {
      switch (_specFor(col)) {
        case FixedColumnWidth(:final width):
          widths[col] = width;
          rigidSum += width;
        case IntrinsicColumnWidth():
          widths[col] = _intrinsicColumnWidth(col, gridRows);
          rigidSum += widths[col];
        case FlexColumnWidth(:final flex):
          flexFactors[col] = flex;
          flexTotal += flex;
      }
    }
    final totalGap = _columnSpacing * (c - 1);
    if (flexTotal > 0) {
      final maxCols = constraints.maxCols;
      if (maxCols != null) {
        var remaining = maxCols - rigidSum - totalGap;
        if (remaining < 0) remaining = 0;
        var distributed = 0;
        for (var col = 0; col < c; col++) {
          if (flexFactors[col] > 0) {
            widths[col] = remaining * flexFactors[col] ~/ flexTotal;
            distributed += widths[col];
          }
        }
        var leftover = remaining - distributed;
        for (var col = 0; col < c && leftover > 0; col++) {
          if (flexFactors[col] > 0) {
            widths[col] += 1;
            leftover -= 1;
          }
        }
      } else {
        for (var col = 0; col < c; col++) {
          if (flexFactors[col] > 0) {
            widths[col] = _intrinsicColumnWidth(col, gridRows);
          }
        }
      }
    }

    // Clamp to the available width so cells are never laid out wider
    // than the table can paint.
    final maxCols = constraints.maxCols;
    if (maxCols != null) {
      var remaining = maxCols - totalGap;
      if (remaining < 0) remaining = 0;
      for (var col = 0; col < c; col++) {
        if (widths[col] > remaining) widths[col] = remaining;
        remaining -= widths[col];
      }
    }

    // 2. Column x-offsets.
    final colX = List<int>.filled(c, 0);
    var x = 0;
    for (var col = 0; col < c; col++) {
      colX[col] = x;
      x += widths[col] + _columnSpacing;
    }
    _ownWidth = x - _columnSpacing; // drop the trailing gap
    if (_ownWidth < 0) _ownWidth = 0;

    // 3. Lay out every cell into its column width; row height = tallest.
    final rowHeight = List<int>.filled(gridRows, 0);
    for (var r = 0; r < gridRows; r++) {
      for (var col = 0; col < c; col++) {
        final size = _children[r * _columnCount + col].layout(
          CellConstraints(maxCols: widths[col]),
        );
        if (size.rows > rowHeight[r]) rowHeight[r] = size.rows;
      }
    }

    // 4. Stack rows; the header rule (if any) takes one row after row 0.
    _separatorRow = -1;
    final rowY = List<int>.filled(gridRows, 0);
    var y = 0;
    for (var r = 0; r < gridRows; r++) {
      rowY[r] = y;
      for (var col = 0; col < c; col++) {
        _offsets[_children[r * _columnCount + col]] = CellOffset(colX[col], y);
      }
      y += rowHeight[r];
      if (r == 0 && _headerSeparator) {
        _separatorRow = y;
        y += 1;
      }
    }
    _naturalHeight = y;
    _rowY = rowY;
    _rowHeight = rowHeight;
    _headerBlock = _hasHeader ? rowHeight[0] + (_headerSeparator ? 1 : 0) : 0;

    // 5. Resolve the scrolling window for the interactive body.
    final bodyCount = gridRows - _headerOffset;
    _windowing = false;
    if (_selectedRow != null && maxCols != null) {
      final maxRows = constraints.maxRows;
      if (maxRows != null) {
        final viewport = (maxRows - _headerBlock).clamp(0, maxRows);
        _windowing = _naturalHeight > maxRows && viewport > 0 && bodyCount > 0;
        final selected = _selectedRow!.clamp(0, bodyCount - 1);
        _bodyAnchor = _bodyAnchor.clamp(0, bodyCount - 1);
        if (selected < _bodyAnchor) _bodyAnchor = selected;
        var (first, last) = _bodyWindow(_bodyAnchor, viewport, bodyCount);
        if (selected > last) {
          _bodyAnchor = _anchorEndingAt(selected, viewport);
          (first, last) = _bodyWindow(_bodyAnchor, viewport, bodyCount);
        }
        _visibleFirst = first;
        _visibleRows = last - first + 1;
        _onVisibleRange(first, last - first + 1);
      } else {
        _bodyAnchor = 0;
        _visibleFirst = 0;
        _visibleRows = bodyCount;
        _onVisibleRange(0, bodyCount);
      }
    } else {
      _bodyAnchor = 0;
      _visibleFirst = 0;
      _visibleRows = 0;
    }

    final height = _windowing ? constraints.maxRows! : _naturalHeight;
    return constraints.constrain(CellSize(_ownWidth, height));
  }

  /// Visible body-row range starting at [anchor] that fits [viewport]
  /// rows, always including the anchor row.
  (int, int) _bodyWindow(int anchor, int viewport, int bodyCount) {
    if (bodyCount == 0) return (0, -1);
    var rows = 0;
    var last = anchor;
    for (var i = anchor; i < bodyCount; i++) {
      final h = _rowHeight[i + _headerOffset];
      if (i > anchor && rows + h > viewport) break;
      rows += h;
      last = i;
      if (rows >= viewport) break;
    }
    return (anchor, last);
  }

  /// Smallest anchor that keeps [target] the bottom-most visible row.
  int _anchorEndingAt(int target, int viewport) {
    var rows = 0;
    var anchor = target;
    for (var i = target; i >= 0; i--) {
      final h = _rowHeight[i + _headerOffset];
      if (rows + h > viewport) break;
      rows += h;
      anchor = i;
    }
    return anchor;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (_naturalHeight == 0 || _ownWidth == 0) return;

    // Natural-mode fast path: when the table fits in its allotted size,
    // paint children directly to the real buffer (no scratch allocation).
    if (_selectedRow == null &&
        size.rows >= _naturalHeight &&
        size.cols >= _ownWidth) {
      _paintNatural(buffer, offset);
      return;
    }

    // Otherwise: paint to a scratch buffer at the table's natural size,
    // then blit only the visible region. The "no selection" branch
    // would otherwise paint children at row indices that exceed the
    // real buffer and trip CellBuffer's bounds check — the selected
    // branch already had this scratch+blit shape; this unifies them.
    final scratch = CellBuffer(CellSize(_ownWidth, _naturalHeight));
    _paintNatural(scratch, CellOffset.zero);

    final outRows = size.rows;
    final outCols = size.cols;
    final int bodyScrollTopY;
    final int selTop;
    final int selBot;
    if (_selectedRow != null) {
      final anchorGridRow = _visibleFirst + _headerOffset;
      bodyScrollTopY = anchorGridRow < _rowY.length
          ? _rowY[anchorGridRow]
          : _headerBlock;
      final selGrid = _selectedRow! + _headerOffset;
      selTop = selGrid < _rowY.length ? _rowY[selGrid] : -1;
      selBot = selGrid < _rowHeight.length ? selTop + _rowHeight[selGrid] : -1;
    } else {
      bodyScrollTopY = _headerBlock;
      selTop = -1;
      selBot = -1;
    }

    final maxCol = outCols < _ownWidth ? outCols : _ownWidth;
    for (var oy = 0; oy < outRows; oy++) {
      final int ny;
      if (oy < _headerBlock) {
        ny = oy;
      } else {
        ny = bodyScrollTopY + (oy - _headerBlock);
      }
      if (ny < 0 || ny >= _naturalHeight) continue;
      final tgtRow = offset.row + oy;
      if (tgtRow < 0 || tgtRow >= buffer.size.rows) continue;

      final isSel =
          oy >= _headerBlock && selTop >= 0 && ny >= selTop && ny < selBot;
      if (isSel) {
        for (var col = 0; col < maxCol; col++) {
          final tgtCol = offset.col + col;
          if (tgtCol < 0 || tgtCol >= buffer.size.cols) continue;
          buffer.writeGrapheme(
            CellOffset(tgtCol, tgtRow),
            ' ',
            style: _selectedStyle,
          );
        }
      }
      for (var col = 0; col < maxCol; col++) {
        final cell = scratch.atColRow(col, ny);
        if (cell.role != CellRole.leading) continue;
        final tgtCol = offset.col + col;
        if (tgtCol < 0 || tgtCol >= buffer.size.cols) continue;
        buffer.writeGrapheme(
          CellOffset(tgtCol, tgtRow),
          cell.grapheme!,
          style: isSel ? cell.style.merge(_selectedStyle) : cell.style,
        );
      }
    }
  }

  void _paintNatural(CellBuffer buffer, CellOffset offset) {
    for (final child in _children) {
      final o = _offsets[child] ?? CellOffset.zero;
      child.paint(buffer, offset + o);
    }
    if (_separatorRow >= 0) {
      final row = offset.row + _separatorRow;
      if (row < 0 || row >= buffer.size.rows) return;
      for (var col = 0; col < _ownWidth; col++) {
        final c = offset.col + col;
        if (c < 0 || c >= buffer.size.cols) continue;
        buffer.writeGrapheme(CellOffset(c, row), '─', style: _separatorStyle);
      }
    }
  }
}

bool _hasSameRenderChildrenInOrder(
  List<RenderObject> current,
  List<RenderObject> next,
) {
  if (current.length != next.length) return false;
  for (var i = 0; i < current.length; i++) {
    if (!identical(current[i], next[i])) return false;
  }
  return true;
}

bool _sameColumnWidths(List<TableColumnWidth> a, List<TableColumnWidth> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (!_sameColumnWidth(a[i], b[i])) return false;
  }
  return true;
}

bool _sameColumnWidth(TableColumnWidth a, TableColumnWidth b) {
  if (identical(a, b)) return true;
  return switch ((a, b)) {
    (IntrinsicColumnWidth(), IntrinsicColumnWidth()) => true,
    (FixedColumnWidth(width: final aw), FixedColumnWidth(width: final bw)) =>
      aw == bw,
    (FlexColumnWidth(flex: final af), FlexColumnWidth(flex: final bf)) =>
      af == bf,
    _ => false,
  };
}
