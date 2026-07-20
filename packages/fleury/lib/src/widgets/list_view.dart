// ListView: a keyboard-navigable list of items.
//
// Three pieces:
//   - ListController — a ChangeNotifier holding the active (selected)
//     index plus programmatic scroll commands. Optional; the widget
//     creates its own when none is supplied.
//   - ListView — the widget. Lays out items vertically, claims
//     arrow-up / arrow-down / home / end / enter via Focus.onKey, and
//     auto-scrolls to keep the selected item visible.
//   - _RenderListView — the render object. Lays out only items that
//     fit in the viewport starting from a scroll anchor, paints them,
//     and writes the resulting visible range back to the controller.
//
// Building modes:
//   - Eager — `ListView(children:)` builds every child up front; the
//     layout/paint pass still visits only the visible window.
//   - Lazy — `ListView.builder` / `ListView.separated` mount only the
//     items in the viewport, on demand during layout, so they scale to
//     tens of thousands of variable-height rows.
//
// Item heights are whatever the child reports at layout: multi-line
// rows are honored, and an item taller than the whole viewport is shown
// from its top (there is no intra-item scrolling — its lower rows stay
// clipped while it is the selection anchor).
//
// What's intentionally not here yet:
//   - Horizontal scrolling. Items are constrained to the viewport
//     width.

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_flex.dart';
import '../rendering/render_object.dart';
import '../input/events.dart';
import 'basic.dart';
import 'repaint_boundary.dart';
import 'focus.dart';
import 'framework.dart';
import 'pointer.dart';
import 'scrollbar.dart';

/// Returns the stable data identity for the item currently at [index].
///
/// The key belongs to the data item, not its current position. It must remain
/// equal when that item moves after a prepend, reorder, or filtered update.
typedef ListItemKeyBuilder = Object Function(int index);

/// Finds the current index for a stable item [key], or returns null when that
/// item is no longer present.
///
/// This is the lazy-list counterpart to Flutter's
/// `findChildIndexCallback`: a sparse list cannot inspect every off-screen
/// child to rediscover where a keyed item moved, so the data owner supplies
/// the reverse lookup. It should normally be map-backed/O(1): Fleury invokes it
/// once per mounted row when a parent supplies an updated list configuration.
typedef ListItemIndexCallback = int? Function(Object key);

/// How a [ListView] handles up/down at the first/last item.
enum EdgeBehavior {
  /// The key is consumed (no-op) and focus stays in the list. Opt in for a
  /// standalone/primary list that should keep focus at its edges.
  contain,

  /// The key is returned as `ignored` so ancestor `KeyBindings` can act on it
  /// — e.g. directional focus traversal moves to a sibling. Default: a list
  /// embedded among other widgets shouldn't trap the arrow keys (the
  /// boundary-escape convention, matching [moveOrEscape] for non-list widgets).
  bubble,
}

/// Mutable model for a [ListView]: the currently active item and a
/// pending programmatic scroll command.
///
/// `selectedIndex` is a code-clamped item index in `0..itemCount-1`,
/// or `null` for scroll-only mode (no cursor; the widget renders
/// items from the top and arrow chords are not consumed). The widget
/// updates [itemCount] before each build and writes the post-layout
/// [visibleRange] back here so listeners can observe what's on
/// screen without re-running layout themselves.
class ListController extends ChangeNotifier {
  ListController({int? selectedIndex, bool pinToBottom = false})
    : _selectedIndex = selectedIndex,
      _pinToBottom = pinToBottom,
      _followsCursor = pinToBottom;

  int? _selectedIndex;
  int _itemCount = 0;
  ({int first, int last})? _visibleRange;
  int? _pendingJumpIndex;
  bool _pinToBottom;
  // Whether this list *follows its cursor* to the tail (`less +F` / chat).
  // Latched true only by an explicit follow-enable — construction with
  // `pinToBottom: true`, the [pinToBottom] setter, or [jumpToBottom] — and
  // never cleared: disengaging (scrolling up) is temporary, so returning to
  // the tail can resume. It gates the selection→follow coupling in
  // [selectedIndex] so scroll-only and selection-only lists (a JSON tree, a
  // file picker, a chat with follow turned off) aren't dragged into follow
  // mode just by selecting their last row. The coupling's own pin writes do
  // NOT latch it, so a non-following list stays non-following.
  bool _followsCursor;
  bool _restoreSelectionWhenNonEmpty = true;
  int _unseenCount = 0;
  bool _disposed = false;

  /// Whether the list is *following the tail* (`less +F` / chat behaviour).
  ///
  /// While following, appended items advance the viewport — and the selection,
  /// when there is one — to stay on the newest item.
  ///
  /// On a **follow-capable** list, following engages and disengages
  /// **automatically with the cursor**: moving the selection off the last item
  /// (scrolling up to read history) stops following, so new arrivals no longer
  /// yank you down; returning to the last item resumes it. A list is
  /// follow-capable once following has been *explicitly* enabled — constructed
  /// with `pinToBottom: true`, or turned on later via this setter or
  /// [jumpToBottom]. A plain selection list (never follow-enabled) is **not**
  /// dragged into follow mode just by selecting its last row, so use
  /// `pinToBottom: true` (or the setter) to opt a chat/log into the coupling.
  /// Setting this manually snaps to the tail (`true`) or freezes in place
  /// (`false`); [jumpToBottom] is the explicit "catch up" action.
  ///
  /// For a scroll-only list (no selection) following advances the viewport to
  /// the last item on each append.
  ///
  /// With keyed lazy data, arrival tracking intentionally assumes an
  /// order-preserving feed, not an arbitrary collection diff. Selection,
  /// viewport, and row state still follow identity through reorders, but an
  /// update that mixes reordering with insertion should not rely on
  /// [unseenCount] to classify which rows are new.
  bool get pinToBottom => _pinToBottom;
  set pinToBottom(bool value) {
    _checkNotDisposed();
    if (_pinToBottom == value) return;
    _pinToBottom = value;
    if (value) {
      _followsCursor = true;
      _unseenCount = 0;
      _snapToTail();
    }
    notifyListeners();
  }

  /// Whether the tail is currently in view: the selection is on the last item
  /// (selection lists), the last item is visible (scroll-only lists), or the
  /// list is empty. When true, following is engaged.
  bool get atBottom {
    if (_itemCount == 0) return true;
    if (_selectedIndex != null) return _selectedIndex == _itemCount - 1;
    final last = _visibleRange?.last;
    return last == null || last >= _itemCount - 1;
  }

  /// Items appended while *not* following (unpinned) — the count behind a
  /// "N new ↓" affordance. Cleared when following re-engages or on
  /// [jumpToBottom].
  int get unseenCount => _unseenCount;

  /// Catches up to the newest item and resumes following, clearing
  /// [unseenCount]. The explicit action behind a "jump to latest" key or the
  /// "N new ↓" chip.
  void jumpToBottom() {
    _checkNotDisposed();
    _pinToBottom = true;
    _followsCursor = true;
    _unseenCount = 0;
    _snapToTail();
    notifyListeners();
  }

  /// Total number of items in the list. Set by [ListView] from its
  /// `itemCount` argument on every rebuild.
  int get itemCount => _itemCount;

  /// The first/last item indices currently visible in the viewport.
  /// Null when the list is empty or before the first layout pass.
  ({int first, int last})? get visibleRange => _visibleRange;

  /// Index of the active (highlighted) item, or `null` for a
  /// scroll-only list. Values outside `0..itemCount-1` are clamped on
  /// write.
  int? get selectedIndex => _selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _restoreSelectionWhenNonEmpty = value != null;
    final clamped = _clampSelection(value);
    var changed = _selectedIndex != clamped;
    _selectedIndex = clamped;
    // On a follow-capable list, follow-mode couples to cursor movement: landing
    // on the last item follows the tail, moving off it stops. Gated on
    // [_followsCursor] so a plain selection list (a JSON tree, a file picker, a
    // chat with follow turned off) isn't dragged into follow mode just by
    // selecting its last row. (Scroll-only lists keep pin explicit — internal
    // re-clamps go through [_clampSelection] directly, not here.)
    if (_followsCursor && clamped != null && _itemCount > 0) {
      final onTail = clamped == _itemCount - 1;
      if (_pinToBottom != onTail) {
        _pinToBottom = onTail;
        changed = true;
      }
      if (onTail && _unseenCount != 0) {
        _unseenCount = 0;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Scrolls the viewport so [index] is at the top. Selection is not
  /// changed. Indices outside `0..itemCount-1` are clamped.
  void jumpToIndex(int index) {
    _checkNotDisposed();
    final clamped = _itemCount == 0 ? 0 : index.clamp(0, _itemCount - 1);
    _pendingJumpIndex = clamped;
    notifyListeners();
  }

  /// Applies a new [itemCount] pushed by the [ListView] on rebuild, running the
  /// follow-mode state machine: while following, appends advance to the tail
  /// and clear [unseenCount]; while not following, appends only accumulate
  /// [unseenCount] (no viewport/selection movement). Identity-aware
  /// non-growth changes preserve the selected item and disengage following if
  /// that item no longer occupies the tail. In scroll-only mode there is no
  /// selected identity to preserve, so an explicit pin stays authoritative.
  /// Internal — the widget owns the count.
  void _handleCountChange(
    int newCount, {
    int? selectedIndex,
    int? appendedCount,
    bool identityAware = false,
  }) {
    final oldCount = _itemCount;
    final oldSelection = _selectedIndex;
    final oldUnseenCount = _unseenCount;
    final oldPinToBottom = _pinToBottom;
    _itemCount = newCount;
    final grew = newCount > oldCount && newCount > 0;
    final tailGrowth = appendedCount ?? (grew ? newCount - oldCount : 0);
    if (newCount == 0) {
      // Once attached, an empty list has no valid cursor. `_clampSelection`
      // preserves values while itemCount is still unknown during controller
      // construction, so the attached-empty case must be explicit here.
      _restoreSelectionWhenNonEmpty = oldSelection != null;
      _selectedIndex = null;
    } else if (identityAware) {
      _selectedIndex = _clampSelection(selectedIndex);
    }
    if (oldCount == 0 &&
        newCount > 0 &&
        _selectedIndex == null &&
        _restoreSelectionWhenNonEmpty) {
      _selectedIndex = _pinToBottom ? newCount - 1 : 0;
    }
    if (_pinToBottom && tailGrowth > 0) {
      _snapToTail();
      _unseenCount = 0;
    } else if (tailGrowth > 0) {
      _unseenCount += tailGrowth;
      _selectedIndex = _clampSelection(_selectedIndex);
    } else {
      _selectedIndex = _clampSelection(_selectedIndex);
    }
    if (identityAware && tailGrowth == 0 && _pinToBottom && newCount > 0) {
      if (_selectedIndex == null) {
        // Scroll-only lists have no selected identity whose preservation can
        // win over following, so keep the explicit pin truthful across keyed
        // reorders by targeting the current tail.
        _snapToTail();
      } else if (_selectedIndex != newCount - 1) {
        // A keyed reorder should not silently change which item is selected.
        // When the followed identity moves away from the tail, preserve that
        // identity and truthfully leave follow mode instead of claiming both
        // `pinToBottom` and `!atBottom`.
        _pinToBottom = false;
      }
    }
    if (oldCount != _itemCount ||
        oldSelection != _selectedIndex ||
        oldUnseenCount != _unseenCount ||
        oldPinToBottom != _pinToBottom) {
      notifyListeners();
    }
  }

  /// Moves the follow target to the newest item. When the list has a
  /// selection, advancing it is enough — the layout's selection-visibility
  /// pass then anchors the tail at the *bottom* of the viewport (the newest
  /// screenful). Only a scroll-only list (no selection) needs an explicit
  /// pending jump. Issuing a pending jump when there IS a selection would
  /// instead anchor the newest item at the *top* of the viewport and hide the
  /// screenful above it — a following chat/log would show only its last line.
  /// Callers own the follow flags and [unseenCount]; this only moves the
  /// target, and is a no-op on an empty list.
  void _snapToTail() {
    if (_itemCount == 0) return;
    if (_selectedIndex != null) {
      _selectedIndex = _itemCount - 1;
    } else {
      _pendingJumpIndex = _itemCount - 1;
    }
  }

  int? _clampSelection(int? value) {
    if (value == null) return null;
    // Before itemCount is known (no widget has attached yet), preserve
    // the caller's value verbatim. The widget calls back through this
    // setter once it has pushed itemCount, which is when real clamping
    // can happen.
    if (_itemCount == 0) return value;
    return value.clamp(0, _itemCount - 1);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ListController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingJumpIndex = null;
    super.dispose();
  }
}

/// A vertical, keyboard-navigable list of items.
///
/// Two ways to populate the list:
///
///   - `ListView(children: [...])` — eager. Every child widget is
///     built upfront on each rebuild; the layout/paint pass only
///     visits items that fit in the viewport. Best when you have a
///     bounded set of widgets you already constructed.
///   - `ListView.builder(itemCount: N, itemBuilder: (ctx, i, sel) {})` —
///     lazy. Only items currently within the viewport are mounted as
///     element subtrees; items scroll into/out of the mounted set as
///     the user navigates. Supports variable item heights. Best for
///     long lists where most items are off-screen (file pickers, log
///     viewers, completion menus).
///
/// When focused, the widget claims arrow-up, arrow-down, home, end,
/// and enter:
///   - Arrows / Home / End move the selected item; the viewport
///     auto-scrolls to keep it visible.
///   - Enter fires [onActivate] with the current selected index.
///   - Up at the first item / Down at the last item respects
///     [edgeBehavior]: `contain` consumes the key, `bubble` returns
///     it to the focus chain so an ancestor `KeyBindings` (e.g. one
///     coordinating sidebar + main pane focus traversal) can react.
///
/// [itemBuilder] (lazy form) is invoked with `(context, index,
/// selected)` for every visible item. The `selected` flag is the
/// active selected-row cue: by default it is true only while this
/// [ListView] has focus. The [ListController.selectedIndex] still
/// retains the logical selection while focus is elsewhere. Composite
/// widgets that should keep the list visually active while another
/// child owns focus can pass [selectionActive].
///
/// With `children:` (eager form), selection styling is the caller's
/// responsibility.
class ListView extends StatefulWidget {
  /// Eager constructor: build all items upfront from a fixed list
  /// of widgets. Use when you have a bounded set of widgets already
  /// constructed and selection styling is handled elsewhere (or not
  /// needed).
  const ListView({
    super.key,
    this.controller,
    this.focusNode,
    required List<Widget> this.children,
    this.autofocus = false,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.onActivate,
    this.onSelectionChanged,
    this.selectionActive,
    this.scrollbar = false,
    this.addRepaintBoundaries = true,
  }) : itemCount = null,
       itemBuilder = null,
       separatorBuilder = null,
       itemKeyBuilder = null,
       findChildIndexCallback = null;

  /// Lazy constructor: build items on demand by index, mount only the
  /// visible ones. Each item builder invocation receives a `selected`
  /// flag for styling the active row.
  const ListView.builder({
    super.key,
    this.controller,
    this.focusNode,
    required int this.itemCount,
    required Widget Function(BuildContext, int, bool) this.itemBuilder,
    this.itemKeyBuilder,
    this.findChildIndexCallback,
    this.autofocus = false,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.onActivate,
    this.onSelectionChanged,
    this.selectionActive,
    this.scrollbar = false,
    this.addRepaintBoundaries = true,
  }) : assert(itemCount >= 0, 'itemCount must be non-negative'),
       assert(
         (itemKeyBuilder == null) == (findChildIndexCallback == null),
         'itemKeyBuilder and findChildIndexCallback must be supplied together.',
       ),
       separatorBuilder = null,
       children = null;

  /// Lazy constructor with separators — the TUI analogue of Flutter's
  /// [ListView.separated]. [separatorBuilder] is called for each gap `i`
  /// — the space between item `i` and item `i + 1`, so `0 <= i <=
  /// itemCount - 2` — and may return `null` to omit that gap's separator
  /// (e.g. a day divider shown only when the day actually changes).
  ///
  /// Separators never take the cursor and hold no index of their own — the
  /// list still addresses exactly [itemCount] items, and arrow / Home / End
  /// navigation walks items only. Each is composed into the row block beneath
  /// its item (reusing [ListView.builder]'s well-tested item-index machinery),
  /// and the block is one tap target, so a mouse click on a separator selects
  /// the item it trails.
  const ListView.separated({
    super.key,
    this.controller,
    this.focusNode,
    required int this.itemCount,
    required Widget Function(BuildContext, int, bool) this.itemBuilder,
    required Widget? Function(BuildContext, int) this.separatorBuilder,
    this.itemKeyBuilder,
    this.findChildIndexCallback,
    this.autofocus = false,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.onActivate,
    this.onSelectionChanged,
    this.selectionActive,
    this.scrollbar = false,
    this.addRepaintBoundaries = true,
  }) : assert(itemCount >= 0, 'itemCount must be non-negative'),
       assert(
         (itemKeyBuilder == null) == (findChildIndexCallback == null),
         'itemKeyBuilder and findChildIndexCallback must be supplied together.',
       ),
       children = null;

  /// External controller. If null, the widget creates its own and
  /// disposes it on unmount.
  final ListController? controller;

  /// External [FocusNode]. Provide one when a parent needs to drive
  /// focus (e.g. Tab cycling between sidebar and main pane). If null,
  /// the widget creates its own and disposes it on unmount.
  final FocusNode? focusNode;

  /// Pre-built widgets (eager form). Mutually exclusive with
  /// [itemCount] / [itemBuilder].
  final List<Widget>? children;

  /// Number of items (lazy form). Mutually exclusive with [children].
  final int? itemCount;

  /// Per-index widget builder (lazy form). Mutually exclusive with
  /// [children]. Invoked with `(context, index, selected)`.
  final Widget Function(BuildContext context, int index, bool selected)?
  itemBuilder;

  /// Per-gap separator builder ([ListView.separated] form). Called with
  /// `(context, i)` for the gap between item `i` and item `i + 1`; may
  /// return `null` to omit that separator. Null for the eager and
  /// [ListView.builder] forms.
  final Widget? Function(BuildContext context, int index)? separatorBuilder;

  /// Stable data identity for lazy items.
  ///
  /// Supply this together with [findChildIndexCallback] when items can move.
  /// Fleury then preserves the selected item, viewport anchor, and mounted
  /// element state across prepends, removals, filters, and reorders. Keys must
  /// be unique within this list. This is data identity only: it does not install
  /// a Fleury `Key` on the row or create a semantic identifier. Add those at the
  /// item-widget layer when the application needs either contract.
  final ListItemKeyBuilder? itemKeyBuilder;

  /// Resolves a stable item key to its current index.
  ///
  /// Must be supplied together with [itemKeyBuilder]. Return null when the
  /// keyed item was removed. Returning an out-of-range index or an index whose
  /// key does not match is a contract error. Prefer a map-backed/O(1) lookup;
  /// reconciliation invokes it once per currently mounted row, never once per
  /// item in the full collection.
  final ListItemIndexCallback? findChildIndexCallback;

  /// Wrap each item in a [RepaintBoundary] (default true, Flutter-parity) so a
  /// localized update — one row's setState, a streaming-token line — repaints
  /// only that row instead of re-walking every item's paint. Paint CPU scales
  /// with the change, not the list size; the boundary replays its pointer and
  /// semantic regions on cache-hit so items stay interactive and accessible.
  /// Turn off only for a list of trivially-cheap items where the per-item
  /// boundary bookkeeping would outweigh the saved paint.
  final bool addRepaintBoundaries;

  /// Whether to request focus on first mount.
  final bool autofocus;

  /// What to do with up/down at the boundary of the list. See
  /// [EdgeBehavior].
  final EdgeBehavior edgeBehavior;

  /// When true, wrap the list in a [Scrollbar] gutter that reflects the
  /// visible item range and lets the mouse drag/click to scroll. A one-line
  /// opt-in: the bar shares this list's controller, so there is nothing extra
  /// to wire. See [Scrollbar.list].
  ///
  /// Needs a bounded width to anchor the right-edge gutter — under an unbounded
  /// width (e.g. a non-Expanded child of a Row) it throws a clear error rather
  /// than collapsing the list; wrap the list in an Expanded or a SizedBox.
  final bool scrollbar;

  /// Called when the user activates an item with Enter or a pointer press.
  /// Not invoked when the list is empty or there is no selection.
  final void Function(int index)? onActivate;

  /// Called when user input moves the selection cursor.
  ///
  /// Programmatic controller writes and identity-preserving data updates do
  /// not call this callback.
  final void Function(int index)? onSelectionChanged;

  /// Overrides whether the selected row should render as active.
  ///
  /// Null means "active while this list owns focus." Composite widgets
  /// can pass a broader focus-within signal so the list keeps its
  /// active row while a sibling control, such as a search input, owns
  /// focus inside the same component.
  final bool? selectionActive;

  /// Effective number of items, regardless of which constructor was
  /// used. Returns `children!.length` for eager, `itemCount!` for
  /// lazy.
  int get effectiveItemCount => children?.length ?? itemCount!;

  @override
  State<ListView> createState() => _ListViewState();
}

class _ListViewState extends State<ListView> {
  late ListController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  Object? _selectedItemKey;
  Object? _firstItemKey;
  Object? _lastItemKey;
  int _dataRevision = 0;

  @override
  void initState() {
    super.initState();
    final count = widget.effectiveItemCount;
    _controller = widget.controller ?? ListController();
    _ownsController = widget.controller == null;
    _initializeController(count);
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ListView');
    _ownsFocusNode = widget.focusNode == null;
    _captureIdentitySnapshot();
  }

  @override
  void didUpdateWidget(ListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dataRevision++;
    final oldCount = oldWidget.effectiveItemCount;
    final oldSelectedKey = _selectedItemKey;
    final oldFirstKey = _firstItemKey;
    final oldLastKey = _lastItemKey;
    var controllerChanged = false;
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller =
          widget.controller ??
          ListController(
            selectedIndex: widget.effectiveItemCount > 0 ? 0 : null,
          );
      _ownsController = widget.controller == null;
      _initializeController(widget.effectiveItemCount);
      _controller.addListener(_onControllerChange);
      controllerChanged = true;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ListView');
      _ownsFocusNode = widget.focusNode == null;
    }
    final newCount = widget.effectiveItemCount;
    final identityAware =
        !controllerChanged &&
        oldWidget.itemKeyBuilder != null &&
        widget.itemKeyBuilder != null &&
        widget.findChildIndexCallback != null;
    if (identityAware) {
      final remappedSelection = _remapSelectedIndex(
        oldSelectedKey,
        fallback: _controller.selectedIndex,
      );
      final appendedCount = _classifyTrailingGrowth(
        oldCount: oldCount,
        newCount: newCount,
        oldFirstKey: oldFirstKey,
        oldLastKey: oldLastKey,
      );
      _controller._handleCountChange(
        newCount,
        selectedIndex: remappedSelection,
        appendedCount: appendedCount,
        identityAware: true,
      );
    } else if (!controllerChanged && newCount != oldCount) {
      // Runs the follow-mode state machine (advance-to-tail while following,
      // accumulate unseenCount otherwise) and re-clamps the selection.
      _controller._handleCountChange(newCount);
    }
    _captureIdentitySnapshot();
  }

  void _initializeController(int count) {
    _controller._itemCount = count;
    // Attaching a controller establishes the current data snapshot; it is not
    // an arrival event and must not inflate unseenCount. Default the cursor
    // when items exist, otherwise clamp an explicit initial selection.
    if (count == 0) {
      _controller._selectedIndex = null;
    } else if (_controller._selectedIndex == null) {
      _controller._selectedIndex = _controller._pinToBottom ? count - 1 : 0;
    } else {
      _controller._selectedIndex = _controller._clampSelection(
        _controller._selectedIndex,
      );
    }
  }

  void _onControllerChange() {
    _captureSelectedItemKey();
    setState(() {});
  }

  void _captureIdentitySnapshot() {
    final keyBuilder = widget.itemKeyBuilder;
    final count = widget.effectiveItemCount;
    if (keyBuilder == null || count == 0) {
      _selectedItemKey = null;
      _firstItemKey = null;
      _lastItemKey = null;
      return;
    }
    _firstItemKey = keyBuilder(0);
    _lastItemKey = keyBuilder(count - 1);
    _captureSelectedItemKey();
  }

  void _captureSelectedItemKey() {
    final keyBuilder = widget.itemKeyBuilder;
    final selected = _controller.selectedIndex;
    final count = widget.effectiveItemCount;
    _selectedItemKey =
        keyBuilder != null &&
            selected != null &&
            selected >= 0 &&
            selected < count
        ? keyBuilder(selected)
        : null;
  }

  int? _remapSelectedIndex(Object? key, {required int? fallback}) {
    if (key == null) return fallback;
    return _validatedIndexForKey(key) ?? fallback;
  }

  int _classifyTrailingGrowth({
    required int oldCount,
    required int newCount,
    required Object? oldFirstKey,
    required Object? oldLastKey,
  }) {
    if (newCount <= oldCount) return 0;
    if (oldCount == 0) return newCount;
    if (oldFirstKey == null || oldLastKey == null) return 0;

    final first = _validatedIndexForKey(oldFirstKey);
    final last = _validatedIndexForKey(oldLastKey);
    if (first == null || last == null || last < first) return 0;

    // Only classify growth outside the old boundary span. If the old boundary
    // items no longer enclose exactly the old number of rows, the mutation is
    // ambiguous; preserving identity is still safe, but claiming "new at the
    // tail" is not.
    if (last - first + 1 != oldCount) return 0;
    final leading = first;
    final trailing = newCount - 1 - last;
    if (leading + trailing != newCount - oldCount) return 0;
    return trailing;
  }

  int? _validatedIndexForKey(Object key) {
    final findIndex = widget.findChildIndexCallback;
    final keyBuilder = widget.itemKeyBuilder;
    if (findIndex == null || keyBuilder == null) return null;
    final index = findIndex(key);
    if (index == null) return null;
    final count = widget.effectiveItemCount;
    if (index < 0 || index >= count) {
      throw StateError(
        'findChildIndexCallback returned $index for $key, outside the current '
        'ListView range 0..${count - 1}.',
      );
    }
    final resolvedKey = keyBuilder(index);
    if (resolvedKey != key) {
      throw StateError(
        'findChildIndexCallback returned index $index for $key, but '
        'itemKeyBuilder($index) returned $resolvedKey.',
      );
    }
    return index;
  }

  void _setUserSelection(int index) {
    final before = _controller.selectedIndex;
    _controller.selectedIndex = index;
    final after = _controller.selectedIndex;
    if (after != null && after != before) {
      widget.onSelectionChanged?.call(after);
    }
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final code = event.code;
    final count = widget.effectiveItemCount;
    if (count == 0) return KeyEventResult.ignored;

    final selected = _controller.selectedIndex;
    // Scroll-only mode is supported via the controller's jumpToIndex,
    // but arrow chords only operate when a selection cursor is present.
    if (selected == null) return KeyEventResult.ignored;

    switch (code) {
      case KeyCode.arrowUp:
        if (selected <= 0) return _edgeResult();
        _setUserSelection(selected - 1);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (selected >= count - 1) return _edgeResult();
        _setUserSelection(selected + 1);
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        if (selected <= 0) return _edgeResult();
        _setUserSelection((selected - _pageSize()).clamp(0, count - 1));
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        if (selected >= count - 1) return _edgeResult();
        _setUserSelection((selected + _pageSize()).clamp(0, count - 1));
        return KeyEventResult.handled;
      case KeyCode.home:
        _setUserSelection(0);
        return KeyEventResult.handled;
      case KeyCode.end:
        _setUserSelection(count - 1);
        return KeyEventResult.handled;
      case KeyCode.enter:
        widget.onActivate?.call(selected);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// Number of items currently visible in the viewport, used as the
  /// step size for PageUp / PageDown. Falls back to 1 before the
  /// first layout when `visibleRange` is still null.
  int _pageSize() {
    final visible = _controller.visibleRange;
    if (visible == null) return 1;
    final size = visible.last - visible.first + 1;
    return size < 1 ? 1 : size;
  }

  KeyEventResult _edgeResult() {
    return widget.edgeBehavior == EdgeBehavior.bubble
        ? KeyEventResult.ignored
        : KeyEventResult.handled;
  }

  /// Scroll-wheel handler — works whether or not the list is focused, so
  /// hovering an unfocused list and scrolling it just works. Moves the
  /// selection when there is one (the viewport follows it), otherwise
  /// jumps the scroll-only viewport.
  void _scrollBy(int delta) {
    final count = widget.effectiveItemCount;
    if (count == 0) return;
    final sel = _controller.selectedIndex;
    if (sel != null) {
      _setUserSelection((sel + delta).clamp(0, count - 1));
    } else {
      final first = _controller.visibleRange?.first ?? 0;
      _controller.jumpToIndex((first + delta).clamp(0, count - 1));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  /// Pointer press on an item: select it, take focus, and fire [onActivate] —
  /// the click-to-activate convention, so a mouse reaches the same outcome
  /// as moving the selection and pressing Enter.
  ///
  /// Acts on the press (tap-down), not the release: the press triggers a
  /// click-to-focus rebuild, and over the serve wire that rebuild lands
  /// between the down and up events — recreating the item's pointer region
  /// so a release-time identity match would miss. Selecting on press is
  /// robust to that and gives instant feedback.
  void _handleItemTap(int index) {
    final count = widget.effectiveItemCount;
    if (index < 0 || index >= count) return;
    _setUserSelection(index);
    _focusNode.requestFocus();
    widget.onActivate?.call(index);
  }

  /// Wraps an item in a [RepaintBoundary] when [ListView.addRepaintBoundaries]
  /// is on (the default). Kept as one seam so the eager and lazy item paths
  /// wrap identically.
  Widget _maybeBoundary(Widget item) =>
      widget.addRepaintBoundaries ? RepaintBoundary(child: item) : item;

  @override
  Widget build(BuildContext context) {
    final selected = _controller.selectedIndex;
    final Widget content = PointerScrollListener(
      router: PointerRouterScope.maybeOf(context),
      onScrollUp: () => _scrollBy(-1),
      onScrollDown: () => _scrollBy(1),
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKey: _handleKey,
        child: _ListSelectionHost(
          focusNode: _focusNode,
          selectionActive: widget.selectionActive,
          builder: (context, active) {
            if (widget.children != null) {
              // Eager: build all children upfront, render object picks the
              // visible window. Each is made tappable for pointer selection,
              // then wrapped in a RepaintBoundary so one item's change repaints
              // only that item (boundary outermost = Flutter parity; it replays
              // the item's pointer + semantic regions on cache-hit).
              return _ListViewBody(
                controller: _controller,
                children: <Widget>[
                  for (var i = 0; i < widget.children!.length; i++)
                    _maybeBoundary(
                      GestureDetector(
                        onTapDown: (_, _) => _handleItemTap(i),
                        child: widget.children![i],
                      ),
                    ),
                ],
              );
            }

            // Lazy: builder + count. Item subtrees are mounted on demand by
            // the render object during layout; wrap each so a press selects it.
            // `.separated` composes a non-selectable separator into the row
            // block below its item — the press target stays the item only (a
            // click on the separator does nothing), and separators never enter
            // the index math because they are sub-parts of an item's block.
            final separatorBuilder = widget.separatorBuilder;
            final itemCount = widget.itemCount!;
            return _LazyListBody(
              controller: _controller,
              itemCount: itemCount,
              dataRevision: _dataRevision,
              itemKeyBuilder: widget.itemKeyBuilder,
              findChildIndexCallback: widget.findChildIndexCallback,
              itemBuilder: (context, index, itemActive) {
                final built = widget.itemBuilder!(context, index, itemActive);
                // No separator after the last item, when none was requested, or
                // when the builder returns null for this gap.
                final separator =
                    separatorBuilder == null || index >= itemCount - 1
                    ? null
                    : separatorBuilder(context, index);
                final content = separator == null
                    ? built
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [built, separator],
                      );
                // The GestureDetector wraps the WHOLE block (not the item
                // alone): the lazy list threads screenOffset to item roots, so
                // the tap region lands at the item's true screen row even when
                // a tall block overflows the viewport and its inner Column
                // paints through the clip path (which drops screenOffset for its
                // own children). A tap on a separator row therefore selects the
                // item it trails.
                //
                // With the RepaintBoundary outermost, the boundary becomes the
                // block's render root — it passes the threaded screenOffset
                // through on repaint and replays the tap region at that same
                // screenOffset on cache-hit, so a scrolled-but-unchanged item
                // blits its cached cells at the new row AND its tap region
                // follows. Caching a lazy row across scroll is the bigger win
                // here; the eager path only saved localized in-place updates.
                return _maybeBoundary(
                  GestureDetector(
                    onTapDown: (_, _) => _handleItemTap(index),
                    child: content,
                  ),
                );
              },
              selectedIndex: selected,
              selectionActive: active,
            );
          },
        ),
      ),
    );
    if (!widget.scrollbar) return content;
    // Shares the list's own controller: the gutter reflects the visible item
    // range, and dragging/clicking it scrolls by item. (Needs a bounded width
    // to anchor the right-edge gutter — Scrollbar throws a clear error under
    // unbounded width rather than collapsing the list.)
    return Scrollbar.list(controller: _controller, child: content);
  }
}

class _ListSelectionHost extends StatefulWidget {
  const _ListSelectionHost({
    required this.focusNode,
    required this.selectionActive,
    required this.builder,
  });

  final FocusNode focusNode;
  final bool? selectionActive;
  final Widget Function(BuildContext context, bool selectionActive) builder;

  @override
  State<_ListSelectionHost> createState() => _ListSelectionHostState();
}

class _ListSelectionHostState extends State<_ListSelectionHost> {
  FocusManager? _manager;
  bool _active = false;

  bool get _resolvedActive =>
      widget.selectionActive ?? widget.focusNode.hasFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context);
    if (!identical(manager, _manager)) {
      _manager?.removeListener(_onFocusChange);
      _manager = manager;
      _manager?.addListener(_onFocusChange);
    }
    _active = _resolvedActive;
  }

  @override
  void didUpdateWidget(covariant _ListSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActive();
  }

  void _onFocusChange() => _syncActive();

  void _syncActive() {
    final next = _resolvedActive;
    if (next == _active) return;
    setState(() {
      _active = next;
    });
  }

  @override
  void dispose() {
    _manager?.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _active = _resolvedActive;
    return widget.builder(context, _active);
  }
}

class _ListViewBody extends MultiChildRenderObjectWidget {
  const _ListViewBody({required this.controller, required super.children});

  final ListController controller;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderListView(controller: controller);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderListView renderObject,
  ) {
    renderObject.controller = controller;
    // The controller is mutable; selection and pending jump changes are read
    // during layout even when the controller identity is stable.
    renderObject.markNeedsLayout();
  }
}

/// The diagnostic both list render objects raise when handed an unbounded main
/// axis. A [ListView] windows its items to the viewport height, so an unbounded
/// `maxRows` (a [ScrollView], or a `mainAxisSize: MainAxisSize.min` Column/Row
/// child) has no window to fill and would drop every item with no diagnostic.
/// Mirrors [Scrollbar]'s unbounded-width failure — loud and actionable rather
/// than a silently blank frame.
Never _throwUnboundedListHeight() {
  throw StateError(
    'ListView needs a bounded height to window its items, but was given an '
    'unbounded height (a ScrollView, or a Column/Row child with '
    'mainAxisSize.min, gets an unbounded main axis). Every item would be '
    'dropped. Give it a bounded height — wrap it in an Expanded or a '
    'SizedBox(height: ...).',
  );
}

/// Lays out a vertical stack of children with a movable scroll anchor.
///
/// Strategy:
///   1. Resolve the pending jump command (if any) into the scroll
///      anchor — the index of the first item that should be visible
///      at the top of the viewport.
///   2. If a selection exists and lies above the anchor, drop the
///      anchor to the selection (scroll up to reveal it).
///   3. Lay out items starting at the anchor, accumulating rows
///      until the viewport is full.
///   4. If the selection lies below the last item that fit, advance
///      the anchor so the selection becomes the last visible item,
///      then re-lay out.
///   5. Write `itemCount` and `visibleRange` back to the controller
///      without notifying — these are read-only mirrors of layout
///      state, not user-mutable fields, and notifying during layout
///      would loop.
class _RenderListView extends RenderObject implements RenderObjectWithChildren {
  _RenderListView({required ListController controller})
    : _controller = controller;

  ListController _controller;
  ListController get controller => _controller;
  set controller(ListController value) {
    if (identical(_controller, value)) return;
    _controller = value;
    markNeedsLayout();
  }

  final List<RenderObject> _children = <RenderObject>[];
  final Map<RenderObject, CellOffset> _childOffsets =
      <RenderObject, CellOffset>{};
  final Set<RenderObject> _visibleChildren = Set<RenderObject>.identity();

  /// Index of the first item that should appear at the top of the
  /// viewport. Persists across layouts so scroll position is stable
  /// when only selection / item count changes.
  int _scrollAnchor = 0;

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    // Same-order children are a no-op: skip the identity-set reconcile below.
    // Mirrors every other RenderObjectWithChildren (the element-side reconciler
    // in MultiChildRenderObjectElement no longer pre-checks order). This render
    // object relayouts on every rebuild anyway — updateRenderObject marks
    // needs-layout unconditionally to re-read mutable controller state — so the
    // guard is inert for layout today; it's kept for parity with the other
    // implementations and stays correct if that mark ever becomes conditional.
    if (hasSameRenderChildrenInOrder(_children, newChildren)) return;
    final newSet = Set<RenderObject>.identity()..addAll(newChildren);
    for (final c in List<RenderObject>.from(_children)) {
      if (!newSet.contains(c)) {
        dropChild(c);
        _childOffsets.remove(c);
        _visibleChildren.remove(c);
      }
    }
    final oldSet = Set<RenderObject>.identity()..addAll(_children);
    for (final c in newChildren) {
      if (!oldSet.contains(c)) {
        adoptChild(c);
      }
    }
    _children
      ..clear()
      ..addAll(newChildren);
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final maxRows = constraints.maxRows;
    final maxCols = constraints.maxCols;
    final count = _children.length;

    if (maxRows == null && count > 0) _throwUnboundedListHeight();

    if (count == 0 || maxRows == null || maxRows == 0) {
      _visibleChildren.clear();
      _controller._visibleRange = null;
      // itemCount mirror — the widget already pushed it pre-build,
      // but covering the empty-children case here keeps the field
      // consistent regardless of how the renderer was reached.
      _controller._itemCount = count;
      return constraints.constrain(CellSize(maxCols ?? 0, maxRows ?? 0));
    }

    // (1) Apply pending jump. When the user has explicitly asked to
    // jump, that intent wins over selection-follow — leaving the
    // selection off-screen until the user moves it is preferable to
    // silently undoing their scroll.
    final pending = _controller._pendingJumpIndex;
    final hadPendingJump = pending != null;
    if (hadPendingJump) {
      _scrollAnchor = pending.clamp(0, count - 1);
      _controller._pendingJumpIndex = null;
    }
    _scrollAnchor = _scrollAnchor.clamp(0, count - 1);

    final selected = _controller._selectedIndex;

    // (2) Selection above the anchor — pull the anchor up.
    if (!hadPendingJump && selected != null && selected < _scrollAnchor) {
      _scrollAnchor = selected;
    }

    final childCC = CellConstraints(maxCols: maxCols);
    final (firstVisible, lastVisible) = _layoutFromAnchor(
      _scrollAnchor,
      maxRows,
      childCC,
    );

    // (4) Selection below the last visible — recompute anchor so
    // selection is the bottom-most visible item, then re-layout.
    if (!hadPendingJump && selected != null && selected > lastVisible) {
      final newAnchor = _anchorThatEndsAt(selected, maxRows, childCC);
      if (newAnchor != _scrollAnchor) {
        _scrollAnchor = newAnchor;
        final (f, l) = _layoutFromAnchor(_scrollAnchor, maxRows, childCC);
        _controller._visibleRange = (first: f, last: l);
      } else {
        _controller._visibleRange = (first: firstVisible, last: lastVisible);
      }
    } else {
      _controller._visibleRange = (first: firstVisible, last: lastVisible);
    }
    _controller._itemCount = count;

    return constraints.constrain(CellSize(maxCols ?? 0, maxRows));
  }

  /// Lays out children starting at [anchor], placing each below the
  /// previous one until [maxRows] is reached. Updates [_childOffsets]
  /// and [_visibleChildren]. Returns the (first, last) visible index.
  (int, int) _layoutFromAnchor(
    int anchor,
    int maxRows,
    CellConstraints childCC,
  ) {
    _visibleChildren.clear();
    var row = 0;
    var last = anchor - 1;
    for (var i = anchor; i < _children.length; i++) {
      if (row >= maxRows) break;
      final child = _children[i];
      final remaining = maxRows - row;
      final cc = CellConstraints(maxCols: childCC.maxCols, maxRows: remaining);
      final size = child.layout(cc);
      _childOffsets[child] = CellOffset(0, row);
      _visibleChildren.add(child);
      row += size.rows;
      last = i;
    }
    return (anchor, last);
  }

  /// Computes the smallest anchor `a` such that laying out items
  /// from `a` forward keeps [target] within the viewport. Walks
  /// backwards from [target], laying each child out at the width the
  /// child would actually receive, summing heights until adding one
  /// more would exceed [maxRows]. The first child whose height
  /// doesn't fit is the boundary; the next one is the anchor.
  int _anchorThatEndsAt(int target, int maxRows, CellConstraints childCC) {
    var rows = 0;
    var anchor = target;
    for (var i = target; i >= 0; i--) {
      final child = _children[i];
      final cc = CellConstraints(maxCols: childCC.maxCols);
      final size = child.layout(cc);
      if (rows + size.rows > maxRows) break;
      rows += size.rows;
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
    for (final c in _children) {
      if (!_visibleChildren.contains(c)) continue;
      final co = _childOffsets[c] ?? CellOffset.zero;
      c.paint(
        buffer,
        offset + co,
        screenOffset: (screenOffset ?? offset) + co,
        clipRect: clipRect,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Lazy ListView.builder
// ---------------------------------------------------------------------------
//
// Implementation strategy (mirrors Flutter's SliverList):
//
//   - The widget tree only contains `_LazyListBody`; child item
//     subtrees are NOT in the tree at build time. They're created
//     by the render object during layout, on demand, and unmounted
//     when they scroll out of view.
//   - `_LazyListElement` holds a sparse Map<int, Element> of the
//     currently-mounted item subtrees. It exposes `createChild(i)`
//     and `disposeChild(i)` for the render object to call.
//   - `_RenderLazyListView` walks items forward from `_scrollAnchor`
//     during layout, asking the element to mount each one, laying
//     them out, accumulating rows until the viewport is full. Items
//     that were mounted but are no longer in the visible range get
//     unmounted at the end of layout.
//   - Build-during-layout means item heights aren't needed upfront;
//     the lazy mode handles variable-height items (chat messages,
//     wrapped text) without the caller specifying an `itemExtent`.

class _LazyListBody extends RenderObjectWidget {
  const _LazyListBody({
    required this.controller,
    required this.itemCount,
    required this.dataRevision,
    required this.itemBuilder,
    required this.itemKeyBuilder,
    required this.findChildIndexCallback,
    required this.selectedIndex,
    required this.selectionActive,
  });

  final ListController controller;
  final int itemCount;
  final int dataRevision;
  final Widget Function(BuildContext, int, bool) itemBuilder;
  final ListItemKeyBuilder? itemKeyBuilder;
  final ListItemIndexCallback? findChildIndexCallback;
  final int? selectedIndex;
  final bool selectionActive;

  @override
  _LazyListElement createElement() => _LazyListElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLazyListView(controller: controller);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderLazyListView renderObject,
  ) {
    renderObject.controller = controller;
    // The controller is mutable; selection and pending jump changes drive
    // visible child mounting during layout even when identity is stable.
    renderObject.markNeedsLayout();
  }
}

/// Element for a `_LazyListBody`. Manages the sparse set of mounted
/// item subtrees and the bidirectional bridge with
/// `_RenderLazyListView` (which calls `createChild` / `disposeChild`
/// during layout).
class _LazyListElement extends RenderObjectElement {
  _LazyListElement(_LazyListBody super.widget);

  /// Currently-mounted items keyed by their data index. Sparse: only
  /// indices visible during the most recent layout are in this map.
  // Keep insertion order aligned with data-index order. Element traversal is
  // also semantic traversal, so letting reused rows retain their old map order
  // would make accessibility and agent trees disagree with paint order after
  // a keyed reorder (or after mounting a lower index while scrolling up).
  final Map<int, Element> _mountedChildren = <int, Element>{};
  final Map<Element, Object> _itemKeyByElement = <Element, Object>{};

  @override
  _LazyListBody get widget => super.widget as _LazyListBody;

  @override
  _RenderLazyListView get renderObject =>
      super.renderObject as _RenderLazyListView;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    renderObject._element = this;
  }

  @override
  void unmount() {
    // Unmount every active child first; this triggers their render
    // objects to detach via `removeChildRenderObject`.
    for (final el in _mountedChildren.values.toList()) {
      el.unmount();
    }
    _mountedChildren.clear();
    _itemKeyByElement.clear();
    renderObject._element = null;
    super.unmount();
  }

  @override
  void update(covariant _LazyListBody newWidget) {
    if (newWidget.dataRevision != widget.dataRevision) {
      _reconcileDataIndices(newWidget);
    }
    super.update(newWidget);
  }

  void _reconcileDataIndices(_LazyListBody newWidget) {
    final findIndex = newWidget.findChildIndexCallback;
    final keyBuilder = newWidget.itemKeyBuilder;
    if (findIndex == null || keyBuilder == null) {
      if (_itemKeyByElement.isNotEmpty) {
        _itemKeyByElement.clear();
        renderObject._clearItemIdentity();
      }
      return;
    }

    final remapped = <int, Element>{};
    final oldToNew = <int, int>{};
    final removed = <({int index, Element element})>[];

    for (final entry in _mountedChildren.entries) {
      final oldIndex = entry.key;
      final element = entry.value;
      final itemKey = _itemKeyByElement[element];
      if (itemKey == null) {
        removed.add((index: oldIndex, element: element));
        continue;
      }
      final newIndex = findIndex(itemKey);
      if (newIndex == null) {
        removed.add((index: oldIndex, element: element));
        continue;
      }
      if (newIndex < 0 || newIndex >= newWidget.itemCount) {
        throw StateError(
          'findChildIndexCallback returned $newIndex for $itemKey, outside '
          'the current ListView range 0..${newWidget.itemCount - 1}.',
        );
      }
      final resolvedKey = keyBuilder(newIndex);
      if (resolvedKey != itemKey) {
        throw StateError(
          'findChildIndexCallback returned index $newIndex for $itemKey, but '
          'itemKeyBuilder($newIndex) returned $resolvedKey.',
        );
      }
      final collision = remapped[newIndex];
      if (collision != null) {
        throw StateError(
          'Multiple mounted ListView items resolved to index $newIndex. '
          'Stable item keys must be unique.',
        );
      }
      remapped[newIndex] = element;
      oldToNew[oldIndex] = newIndex;
    }

    for (final entry in removed) {
      _mountedChildren.remove(entry.index);
      _itemKeyByElement.remove(entry.element);
      entry.element.unmount();
    }

    renderObject._remapDataIndices(
      oldToNew,
      itemKeyBuilder: keyBuilder,
      findChildIndexCallback: findIndex,
      newItemCount: newWidget.itemCount,
    );
    _mountedChildren
      ..clear()
      ..addAll(remapped);
    _sortMountedChildrenByIndex();
  }

  void _sortMountedChildrenByIndex() {
    final sorted = _mountedChildren.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    _mountedChildren
      ..clear()
      ..addEntries(sorted);
  }

  Object? _validateNewItemIdentity(int index, {Element? replacing}) {
    final keyBuilder = widget.itemKeyBuilder;
    final findIndex = widget.findChildIndexCallback;
    if (keyBuilder == null || findIndex == null) return null;

    final itemKey = keyBuilder(index);
    final resolvedIndex = findIndex(itemKey);
    if (resolvedIndex != index) {
      throw StateError(
        'findChildIndexCallback returned $resolvedIndex for $itemKey, but the '
        'item is being mounted at index $index.',
      );
    }
    for (final entry in _itemKeyByElement.entries) {
      if (!identical(entry.key, replacing) && entry.value == itemKey) {
        throw StateError(
          'Duplicate ListView item key $itemKey at index $index. Stable item '
          'keys must be unique.',
        );
      }
    }
    return itemKey;
  }

  @override
  void performRebuild() {
    // Re-update each currently-mounted child with a freshly-built
    // widget from the (possibly new) itemBuilder. This is what
    // propagates a selectedIndex change to existing items so their
    // `selected` flag can re-render the highlight without us
    // having to unmount/remount.
    final maxValid = widget.itemCount;
    final toRemove = <int>[];

    // First pass: drop any mounted child whose index is no longer
    // valid (itemCount shrank).
    for (final i in _mountedChildren.keys) {
      if (i >= maxValid) toRemove.add(i);
    }
    for (final i in toRemove) {
      final removed = _mountedChildren.remove(i);
      if (removed != null) {
        _itemKeyByElement.remove(removed);
        removed.unmount();
      }
    }

    // Second pass: re-build & reconcile remaining children.
    for (final entry in _mountedChildren.entries.toList()) {
      final i = entry.key;
      final oldEl = entry.value;
      final newWidget = widget.itemBuilder(
        this,
        i,
        widget.selectionActive && i == widget.selectedIndex,
      );
      if (identical(oldEl.widget, newWidget)) continue;
      if (Widget.canUpdate(oldEl.widget, newWidget)) {
        oldEl.update(newWidget);
      } else {
        final itemKey = _validateNewItemIdentity(i, replacing: oldEl);
        oldEl.unmount();
        _itemKeyByElement.remove(oldEl);
        final fresh = newWidget.createElement();
        fresh.mount(this);
        _mountedChildren[i] = fresh;
        if (itemKey != null) _itemKeyByElement[fresh] = itemKey;
      }
    }
  }

  /// Mounts the item at [index] if not already mounted; returns its
  /// root render object. Called by the render object during layout.
  RenderObject? createChild(int index) {
    final existing = _mountedChildren[index];
    if (existing != null) {
      return _findRootRenderObject(existing);
    }
    final itemKey = _validateNewItemIdentity(index);
    final newWidget = widget.itemBuilder(
      this,
      index,
      widget.selectionActive && index == widget.selectedIndex,
    );
    final element = newWidget.createElement();
    element.mount(this);
    final priorLastIndex = _mountedChildren.isEmpty
        ? null
        : _mountedChildren.keys.last;
    _mountedChildren[index] = element;
    if (priorLastIndex != null && index < priorLastIndex) {
      _sortMountedChildrenByIndex();
    }
    if (itemKey != null) _itemKeyByElement[element] = itemKey;
    return _findRootRenderObject(element);
  }

  /// Unmounts the item at [index]. Called by the render object during
  /// layout when an item scrolls out of the visible range.
  void disposeChild(int index) {
    final el = _mountedChildren.remove(index);
    if (el != null) _itemKeyByElement.remove(el);
    el?.unmount();
  }

  Object? itemKeyAt(int index) => widget.itemKeyBuilder?.call(index);

  Set<int> get mountedIndices => _mountedChildren.keys.toSet();

  static RenderObject? _findRootRenderObject(Element element) {
    if (element is RenderObjectElement) return element.renderObject;
    RenderObject? found;
    element.visitChildren((child) {
      found ??= _findRootRenderObject(child);
    });
    return found;
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    for (final el in _mountedChildren.values) {
      visitor(el);
    }
  }

  @override
  void insertChildRenderObject(
    RenderObject child,
    RenderObjectElement element,
  ) {
    renderObject._adopt(child);
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    renderObject._drop(child);
  }
}

/// Render object for a lazy [ListView.builder]. Holds a sparse map
/// of currently-laid-out children keyed by data index, plus the
/// scroll anchor (top-of-viewport data index) that persists across
/// layouts.
///
/// Layout strategy:
///
///   1. Apply pending jump command from the controller (if any) by
///      moving the scroll anchor.
///   2. If a selection is active and lies above the anchor, drop the
///      anchor to the selection (pull viewport up).
///   3. Walk items forward from the anchor, asking the element to
///      `createChild(i)` for each, laying them out, accumulating
///      rows until the viewport is full.
///   4. If a selection lies below the last visible item, compute a
///      new anchor that brings the selection into view as the
///      bottom-most item, and re-walk.
///   5. Unmount any items that were active before this layout but
///      are no longer in the new visible range.
///   6. Write `itemCount` and `visibleRange` back to the controller
///      without notifying.
class _RenderLazyListView extends RenderObject
    implements RenderObjectWithChildren {
  _RenderLazyListView({required ListController controller})
    : _controller = controller;

  ListController _controller;
  ListController get controller => _controller;
  set controller(ListController value) {
    if (identical(_controller, value)) return;
    _controller = value;
    markNeedsLayout();
  }

  _LazyListElement? _element;

  /// Currently-laid-out children keyed by data index. Same indices
  /// the element has mounted in `_mountedChildren`; we mirror them
  /// here for paint and offset lookup.
  final Map<int, RenderObject> _activeByIndex = <int, RenderObject>{};

  /// Reverse mapping from render object to index, used when the
  /// element-level `removeChildRenderObject` hook fires during
  /// unmount and we need to clean up our per-render-object state.
  final Map<RenderObject, int> _indexByObject = <RenderObject, int>{};

  /// Paint offsets for the children that fit in the current viewport.
  final Map<RenderObject, CellOffset> _childOffsets =
      <RenderObject, CellOffset>{};

  /// All children we've adopted (whether currently in the layout
  /// window or not). Tracks parent-child render-object relationships
  /// so reparenting is well-defined.
  final Set<RenderObject> _adopted = Set<RenderObject>.identity();

  int _scrollAnchor = 0;
  Object? _scrollAnchorItemKey;

  @override
  List<RenderObject> get children => _activeByIndex.values.toList();

  @override
  void replaceAllChildren(List<RenderObject> newChildren) {
    // Lazy mode doesn't reconcile a list — children are mounted /
    // unmounted by the element on demand. This entry point is part
    // of the RenderObjectWithChildren interface but isn't used.
  }

  /// Called by [_LazyListElement.insertChildRenderObject] when an
  /// item's root render object is created (its element subtree just
  /// finished mounting). Adopts it so the parent-child link is
  /// well-formed before layout sees it.
  void _adopt(RenderObject child) {
    if (_adopted.add(child)) {
      adoptChild(child);
    }
  }

  /// Called by [_LazyListElement.removeChildRenderObject] when an
  /// item's element subtree is unmounted (either because it scrolled
  /// out of view or because the whole list is being torn down).
  void _drop(RenderObject child) {
    if (_adopted.remove(child)) {
      dropChild(child);
    }
    final i = _indexByObject.remove(child);
    if (i != null) _activeByIndex.remove(i);
    _childOffsets.remove(child);
  }

  void _clearItemIdentity() {
    _scrollAnchorItemKey = null;
  }

  void _remapDataIndices(
    Map<int, int> oldToNew, {
    required ListItemKeyBuilder itemKeyBuilder,
    required ListItemIndexCallback findChildIndexCallback,
    required int newItemCount,
  }) {
    final anchorKey = _scrollAnchorItemKey;
    if (anchorKey != null) {
      final remappedAnchor = findChildIndexCallback(anchorKey);
      if (remappedAnchor != null) {
        if (remappedAnchor < 0 || remappedAnchor >= newItemCount) {
          throw StateError(
            'findChildIndexCallback returned $remappedAnchor for $anchorKey, '
            'outside the current ListView range 0..${newItemCount - 1}.',
          );
        }
        final resolvedKey = itemKeyBuilder(remappedAnchor);
        if (resolvedKey != anchorKey) {
          throw StateError(
            'findChildIndexCallback returned index $remappedAnchor for '
            '$anchorKey, but itemKeyBuilder($remappedAnchor) returned '
            '$resolvedKey.',
          );
        }
        _scrollAnchor = remappedAnchor;
      }
    }

    if (_activeByIndex.isEmpty) return;
    final activeEntries = <MapEntry<int, RenderObject>>[];
    for (final entry in _activeByIndex.entries) {
      final newIndex = oldToNew[entry.key];
      if (newIndex == null) continue;
      activeEntries.add(MapEntry(newIndex, entry.value));
      _indexByObject[entry.value] = newIndex;
    }
    activeEntries.sort((a, b) => a.key.compareTo(b.key));
    _activeByIndex
      ..clear()
      ..addEntries(activeEntries);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final maxRows = constraints.maxRows;
    final maxCols = constraints.maxCols;
    final element = _element;
    final count = _controller._itemCount;

    if (maxRows == null && count > 0 && element != null) {
      _throwUnboundedListHeight();
    }

    if (element == null || count == 0 || maxRows == null || maxRows == 0) {
      // Unmount any leftovers from a previous non-empty layout.
      _unmountAllVisible(element);
      _controller._visibleRange = null;
      if (count == 0) _scrollAnchorItemKey = null;
      return constraints.constrain(CellSize(maxCols ?? 0, maxRows ?? 0));
    }

    // (1) Apply pending jump.
    final pending = _controller._pendingJumpIndex;
    final hadPendingJump = pending != null;
    if (hadPendingJump) {
      _scrollAnchor = pending.clamp(0, count - 1);
      _controller._pendingJumpIndex = null;
    }
    _scrollAnchor = _scrollAnchor.clamp(0, count - 1);

    final selected = _controller._selectedIndex;

    // (2) Selection above the anchor — pull the anchor up.
    if (!hadPendingJump && selected != null && selected < _scrollAnchor) {
      _scrollAnchor = selected;
    }

    final childCC = CellConstraints(maxCols: maxCols);
    // Rebuild the active map in final visual-index order on every layout.
    // Updating an existing Map key does not change insertion order; retaining
    // the prior order across a scroll or keyed reorder would make paint and
    // semantic traversal disagree with the newly-computed row offsets.
    _activeByIndex.clear();
    _indexByObject.clear();
    _childOffsets.clear();
    final newlyVisible = <int>{};

    var (firstVisible, lastVisible) = _layoutFromAnchor(
      element,
      _scrollAnchor,
      maxRows,
      childCC,
      newlyVisible,
    );

    // (4) Selection below the last visible — recompute anchor so the
    // selection becomes the bottom-most visible item, then re-walk.
    if (!hadPendingJump && selected != null && selected > lastVisible) {
      final newAnchor = _anchorThatEndsAt(element, selected, maxRows, childCC);
      if (newAnchor != _scrollAnchor) {
        _scrollAnchor = newAnchor;
        newlyVisible.clear();
        // We need to clear offsets / active map for the re-walk
        // because the second walk replays from a different anchor.
        _activeByIndex.clear();
        _childOffsets.clear();
        // Note: `_indexByObject` and `_adopted` stay populated; the
        // unmount-leftovers pass at the end will sweep anything that
        // didn't end up in `newlyVisible`.
        final result = _layoutFromAnchor(
          element,
          _scrollAnchor,
          maxRows,
          childCC,
          newlyVisible,
        );
        firstVisible = result.$1;
        lastVisible = result.$2;
      }
    }

    // (5) Unmount every mounted item that is not visible in the final window.
    // This includes transient children mounted by [_anchorThatEndsAt] while it
    // probes backwards for a variable-height selection anchor. Sweeping only
    // the previous active map leaves the first non-fitting probe mounted
    // forever because it was created during this layout but never made active.
    for (final i in element.mountedIndices) {
      if (!newlyVisible.contains(i)) {
        element.disposeChild(i);
      }
    }

    _controller._visibleRange = (first: firstVisible, last: lastVisible);
    _controller._itemCount = count;
    _scrollAnchorItemKey = element.itemKeyAt(_scrollAnchor);

    return constraints.constrain(CellSize(maxCols ?? 0, maxRows));
  }

  /// Walks items forward from [anchor], mounting each via
  /// [element.createChild] and laying it out, accumulating rows
  /// until [maxRows] is reached or `itemCount` runs out. Updates
  /// `_activeByIndex`, `_indexByObject`, `_childOffsets`, and the
  /// caller-provided [newlyVisible] set. Returns (first, last) data
  /// indices currently in the viewport.
  (int, int) _layoutFromAnchor(
    _LazyListElement element,
    int anchor,
    int maxRows,
    CellConstraints childCC,
    Set<int> newlyVisible,
  ) {
    var row = 0;
    var last = anchor - 1;
    final count = _controller._itemCount;
    for (var i = anchor; i < count; i++) {
      if (row >= maxRows) break;
      final remaining = maxRows - row;
      final child = element.createChild(i);
      if (child == null) break;
      final size = child.layout(
        CellConstraints(maxCols: childCC.maxCols, maxRows: remaining),
      );
      _activeByIndex[i] = child;
      _indexByObject[child] = i;
      _childOffsets[child] = CellOffset(0, row);
      newlyVisible.add(i);
      row += size.rows;
      last = i;
    }
    return (anchor, last);
  }

  /// Computes the smallest anchor `a` such that laying out items
  /// from `a` forward keeps [target] within the viewport. Walks
  /// backwards from [target], mounting each item, summing heights.
  /// Items mounted by this probe but not retained in the final
  /// window will be cleaned up by the caller's unmount-leftovers
  /// sweep at the end of layout.
  int _anchorThatEndsAt(
    _LazyListElement element,
    int target,
    int maxRows,
    CellConstraints childCC,
  ) {
    var rows = 0;
    var anchor = target;
    for (var i = target; i >= 0; i--) {
      final child = element.createChild(i);
      if (child == null) break;
      final size = child.layout(CellConstraints(maxCols: childCC.maxCols));
      if (rows + size.rows > maxRows) break;
      rows += size.rows;
      anchor = i;
    }
    return anchor;
  }

  void _unmountAllVisible(_LazyListElement? element) {
    if (element == null) {
      _activeByIndex.clear();
      _childOffsets.clear();
      return;
    }
    for (final i in _activeByIndex.keys.toList()) {
      element.disposeChild(i);
    }
    _activeByIndex.clear();
    _childOffsets.clear();
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    for (final child in _activeByIndex.values) {
      final co = _childOffsets[child] ?? CellOffset.zero;
      child.paint(
        buffer,
        offset + co,
        screenOffset: (screenOffset ?? offset) + co,
        clipRect: clipRect,
      );
    }
  }
}
