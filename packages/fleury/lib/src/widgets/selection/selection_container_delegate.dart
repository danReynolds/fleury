// SelectionContainerDelegate: routes SelectionEvents to the
// registered Selectables in screen-reading order, handling
// cross-boundary handoff via SelectionResult.
//
// One per SelectionArea. Owns the live `Selection` (anchor + cursor
// in screen-space cells), the registered Selectable list, and the
// reading-order resolver. Doesn't own gestures, paint, or clipboard
// — those live in SelectionArea / its render object.

import 'dart:collection' show UnmodifiableListView;

import '../../foundation/change_notifier.dart';
import '../../foundation/geometry.dart';
import 'selectable.dart';
import 'selection.dart';
import 'selection_event.dart';

/// Coordinates a set of [Selectable] children behind one parent
/// [SelectionRegistrar].
///
/// **Reading-order routing.** When a [SelectionEvent] arrives, the
/// delegate iterates its children sorted by [Selectable.cellBounds]
/// (row, then column), dispatches the event, and inspects the
/// returned [SelectionResult] to decide where the live edge wound
/// up. Two-edge events (start/end) result in:
///
///   - All children before the start edge: no selection.
///   - The child holding the start edge: selection from the edge
///     onward through its content (or up to the end edge if both fall
///     here).
///   - Children between the start and end edges: fully selected.
///   - The child holding the end edge: selection from its first
///     character up to the edge.
///   - All children after the end edge: no selection.
///
/// **Stale geometry.** A Selectable that hasn't painted yet (or has
/// been hidden) returns null `cellBounds`. Those are silently skipped
/// — they don't appear in reading order until they next paint.
class SelectionContainerDelegate extends ChangeNotifier
    implements SelectionRegistrar {
  final List<Selectable> _selectables = <Selectable>[];
  bool _disposed = false;
  Selection? _selection;
  CellOffset? _pendingStartEdge;
  CellOffset? _pendingEndEdge;

  /// The live selection in screen-space cell coordinates, or null
  /// when nothing is selected.
  Selection? get selection => _selection;

  /// The moving edge (cursor) in screen-space cell coordinates, or
  /// null when no selection is active. Equivalent to
  /// `selection?.end` — exposed so keyboard extenders (Shift+Arrow,
  /// Shift+Home, Shift+End) can compute the next edge position.
  CellOffset? get cursor => _pendingEndEdge;

  /// Moves the moving edge to [position] without altering the
  /// anchor. The caller is responsible for ensuring an anchor
  /// already exists; if no selection is in flight the cursor update
  /// is a no-op (Shift+Arrow with nothing selected does nothing).
  void moveCursorTo(CellOffset position) {
    if (_pendingStartEdge == null) return;
    dispatchSelectionEvent(
      SelectionEdgeUpdateEvent(globalPosition: position, isStart: false),
    );
  }

  /// Asks Selectables in reading order for the screen-space cell
  /// position one full grapheme away from [from] in (dCol, dRow).
  /// Returns null when no Selectable can step from there — the
  /// caller (typically Shift+Arrow) leaves the cursor in place.
  ///
  /// This walks graphemes properly: wide CJK / emoji / ZWJ sequences
  /// are crossed in one step instead of leaving the cursor on a
  /// continuation cell.
  CellOffset? findNextGraphemeBoundary(CellOffset from, int dCol, int dRow) {
    for (final s in _selectablesInReadingOrder()) {
      final candidate = s.nextGraphemeBoundary(from, dCol, dRow);
      if (candidate != null) return candidate;
    }
    return null;
  }

  /// Number of registered Selectables. Exposed for diagnostics
  /// and tests.
  int get selectableCount => _selectables.length;

  /// Read-only view of registered Selectables. Iteration order is
  /// registration order — NOT screen reading order. Use this when
  /// you need to visit every registered Selectable without caring
  /// about position (e.g. SelectionArea's auto-scroll computing the
  /// union of visible bounds). For reading-order traversal, the
  /// delegate handles it internally via [getSelectedText] and the
  /// like.
  ///
  /// Backed by an [UnmodifiableListView] so callers can't mutate the
  /// underlying list, and there's no per-call allocation — important
  /// for hot paths like the auto-scroll edge check.
  Iterable<Selectable> get selectables => _selectablesView;
  late final Iterable<Selectable> _selectablesView =
      UnmodifiableListView<Selectable>(_selectables);

  @override
  void add(Selectable selectable) {
    _checkNotDisposed();
    if (_selectables.contains(selectable)) return;
    _selectables.add(selectable);
    selectable.addListener(_onSelectableChanged);
    // If a selection was already in flight when this Selectable
    // mounted (e.g. a new row scrolled into view), re-dispatch the
    // active edges so the newcomer can paint its share.
    _reapplyActiveEdgesTo(selectable);
  }

  @override
  void remove(Selectable selectable) {
    if (_disposed) return;
    if (_selectables.remove(selectable)) {
      selectable.removeListener(_onSelectableChanged);
    }
  }

  /// Pushes [event] to every Selectable in reading order. Used by the
  /// gesture machine in `SelectionArea` whenever a user action
  /// produces an event.
  ///
  /// Tracks the active edges internally so a newly-mounted Selectable
  /// can pick up the in-flight selection.
  void dispatchSelectionEvent(SelectionEvent event) {
    _checkNotDisposed();
    switch (event) {
      case SelectionEdgeUpdateEvent(:final isStart, :final globalPosition):
        if (isStart) {
          _pendingStartEdge = globalPosition;
        } else {
          _pendingEndEdge = globalPosition;
        }
      case SelectionClearEvent():
        _pendingStartEdge = null;
        _pendingEndEdge = null;
      case SelectionGranularEvent():
        // Granular events position both edges in one shot. The
        // affected Selectable returns SelectionResult.end and pushes
        // a SelectionGeometry that pins both edges to its bounds.
        break;
    }

    final sorted = _selectablesInReadingOrder();
    for (final s in sorted) {
      s.dispatchSelectionEvent(event);
    }

    _recomputeSelectionFromEdges();
    notifyListeners();
  }

  /// Sorted view of registered selectables, top-to-bottom then
  /// left-to-right. Selectables without `cellBounds` go to the end —
  /// they haven't painted, so we can't place them, but we don't drop
  /// them either (they might paint next frame).
  List<Selectable> _selectablesInReadingOrder() {
    final list = List<Selectable>.of(_selectables);
    list.sort((a, b) {
      final ra = a.cellBounds;
      final rb = b.cellBounds;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      // Compare by top, then left.
      if (ra.offset.row != rb.offset.row) {
        return ra.offset.row.compareTo(rb.offset.row);
      }
      return ra.offset.col.compareTo(rb.offset.col);
    });
    return list;
  }

  /// When a Selectable's geometry changes (e.g. its repaint settled),
  /// notify the area so it can repaint highlights and emit
  /// `onSelectionChanged`. The change came FROM a Selectable so we
  /// don't bounce the event back through `dispatchSelectionEvent`.
  void _onSelectableChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Re-applies the in-flight edge updates to a newly-added
  /// Selectable so it can compute its share of the live selection
  /// without waiting for the next user action.
  void _reapplyActiveEdgesTo(Selectable s) {
    final start = _pendingStartEdge;
    final end = _pendingEndEdge;
    if (start != null) {
      s.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent(globalPosition: start, isStart: true),
      );
    }
    if (end != null) {
      s.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent(globalPosition: end, isStart: false),
      );
    }
  }

  void _recomputeSelectionFromEdges() {
    final start = _pendingStartEdge;
    final end = _pendingEndEdge;
    if (start == null || end == null) {
      _selection = null;
      return;
    }
    _selection = Selection(start: start, end: end);
  }

  /// Concatenates the selected portions of all Selectables (in
  /// reading order) into one user-facing string. Empty when no
  /// Selectable reports any selected content.
  ///
  /// Inserts a `\n` between portions whose Selectables live on
  /// different screen rows — so selecting across two paragraphs
  /// produces a multiline string the user can paste back as
  /// separated paragraphs. Portions on the same row are joined
  /// without a separator (continuing inline text).
  String getSelectedText() {
    final buf = StringBuffer();
    int? lastRow;
    for (final s in _selectablesInReadingOrder()) {
      final c = s.getSelectedContent();
      if (c == null) continue;
      final myRow = s.cellBounds?.offset.row;
      if (lastRow != null && myRow != null && myRow != lastRow) {
        buf.write('\n');
      }
      buf.write(c.plainText);
      if (myRow != null) lastRow = myRow;
    }
    return buf.toString();
  }

  /// Drops the selection state entirely. Equivalent to dispatching
  /// a [SelectionClearEvent].
  void clear() {
    dispatchSelectionEvent(const SelectionClearEvent());
  }

  @override
  void dispose() {
    if (_disposed) return;
    for (final s in _selectables) {
      s.removeListener(_onSelectableChanged);
    }
    _selectables.clear();
    _disposed = true;
    super.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('SelectionContainerDelegate has been disposed.');
    }
  }
}
