// ListView: a keyboard-navigable list of items.
//
// Three pieces:
//   - ListController — a ChangeNotifier holding the active (selected)
//     index plus programmatic scroll commands. Optional; the widget
//     creates its own when none is supplied.
//   - ListView — the widget. Lays out items vertically, claims
//     arrow-up / arrow-down / home / end / enter via KeyDetector, and
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
// Items are measured at their natural height. The viewport keeps an item
// anchor and a row offset, so tall items can be read without skipping content.
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
import 'keyboard.dart';
import 'pointer.dart';
import 'scrollbar.dart';
import 'tui_binding.dart';

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

/// How scrollable widgets handle navigation or wheel input at an edge.
enum EdgeBehavior {
  /// The input is consumed (no-op) and stays in this scrollable. Opt in for a
  /// standalone/primary list that should keep focus at its edges.
  contain,

  /// The key is returned as `ignored` so ancestor `KeyBindings` can act on it
  /// — e.g. directional focus traversal moves to a sibling. Default: a list
  /// embedded among other widgets shouldn't trap the arrow keys (the
  /// boundary-escape convention, matching [moveOrEscape] for non-list widgets).
  bubble,
}

/// Selection and viewport state for a [ListView].
///
/// Selection changes reveal the new selection. Scrolling leaves selection alone,
/// and a rebuild preserves the viewport. Listeners receive changed viewport
/// metrics after the frame, when [visibleRange] describes the rendered content.
class ListController extends ChangeNotifier {
  ListController({
    int? selectedIndex = 0,
    bool followTail = false,
    @Deprecated('Use followTail instead.') bool? pinToBottom,
  }) : _selectedIndex = selectedIndex,
       _restoreSelectionWhenNonEmpty = selectedIndex != null,
       _followTail = pinToBottom ?? followTail,
       _isFollowing = pinToBottom ?? followTail,
       _pendingBottom = pinToBottom ?? followTail;

  int? _selectedIndex;
  int _itemCount = 0;
  bool _attached = false;
  bool _selectable = true;
  bool _restoreSelectionWhenNonEmpty;
  ({int first, int last})? _visibleRange;
  int _viewportExtent = 0;
  bool _atTop = true;
  bool _atBottom = true;
  double _scrollFraction = 0;
  double _visibleFraction = 1;
  int? _pendingJumpIndex;
  int? _pendingRevealIndex;
  int _pendingScrollRows = 0;
  double? _pendingFraction;
  bool _pendingBottom;
  bool _followTail;
  bool _isFollowing;
  int _unseenCount = 0;
  bool _disposed = false;
  TuiBinding? _binding;
  bool _metricsNotificationPending = false;
  int _attachment = 0;

  /// Whether new output should be followed while the viewport is at its end.
  /// Scrolling away pauses following without disabling this policy. Setting it
  /// false keeps it disabled even after returning to the end; true catches up.
  bool get followTail => _followTail;
  set followTail(bool value) {
    _checkNotDisposed();
    if (_followTail == value) return;
    _followTail = value;
    _isFollowing = value;
    if (!value) _pendingBottom = false;
    if (value) {
      _clearRequests();
      _pendingBottom = true;
      _unseenCount = 0;
    }
    notifyListeners();
  }

  /// Whether the viewport is currently following output. False while reading
  /// history, even when [followTail] remains enabled.
  bool get isFollowing => _isFollowing;

  @Deprecated(
    'Read isFollowing; set followTail to enable or disable following.',
  )
  bool get pinToBottom => isFollowing;
  @Deprecated('Use followTail instead.')
  set pinToBottom(bool value) {
    if (value && followTail) {
      jumpToBottom();
    } else {
      followTail = value;
    }
  }

  /// Whether the viewport includes the first / final row of content.
  bool get atTop => _atTop;
  bool get atBottom => _atBottom;

  /// Appended items not yet seen at the end of an ordered feed. Prepends do not
  /// count when stable item keys are provided. Mixed reorders and insertions are
  /// not a general unread-item diff. Cleared on reaching the end.
  int get unseenCount => _unseenCount;
  int get itemCount => _itemCount;

  /// Visible item indices, including partially visible items; null when empty
  /// or before layout. Items can occupy more than one terminal row.
  ({int first, int last})? get visibleRange => _visibleRange;

  /// Approximate scrollbar position in 0..1. Unmeasured items count equally;
  /// partial visible items contribute their measured fraction. The endpoints
  /// always correspond to the first and final content rows.
  double get scrollFraction => _scrollFraction;

  /// Fraction of the item collection visible, accounting for partial rows.
  /// This is an estimate for variable-height items not yet measured.
  double get visibleFraction => _visibleFraction;

  /// Logical selected index, independent of focus and scrolling. Defaults to
  /// zero; an explicit null starts without a selection. A non-selectable list
  /// keeps this null. Values clamp once attached to a list.
  int? get selectedIndex => _selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    if (!_selectable) return;
    _restoreSelectionWhenNonEmpty = value != null;
    final next = _clampSelection(value);
    if (next == _selectedIndex) return;
    _selectedIndex = next;
    _clearRequests();
    _pendingRevealIndex = next;
    // The completed viewport, not the selected index, decides whether to resume.
    _isFollowing = false;
    notifyListeners();
  }

  /// Places an item at the top, clamped to the final full viewport. Does not
  /// change selection. The resulting position survives unrelated rebuilds.
  void jumpToIndex(int index) {
    _checkNotDisposed();
    _clearRequests();
    _pendingJumpIndex = _itemCount == 0
        ? index
        : index.clamp(0, _itemCount - 1);
    _isFollowing = false;
    notifyListeners();
  }

  /// Scrolls by terminal rows, including within an oversized item.
  void scrollBy(int rows) {
    _checkNotDisposed();
    if (rows == 0) return;
    _pendingRevealIndex = null;
    _pendingBottom = false;
    _pendingScrollRows += rows;
    _isFollowing = false;
    notifyListeners();
  }

  /// Moves a scrollbar to an approximate fraction of the collection. Zero and
  /// one reach the actual content edges, including a single oversized item.
  void jumpToFraction(double fraction) {
    _checkNotDisposed();
    if (!fraction.isFinite) throw ArgumentError.value(fraction, 'fraction');
    _clearRequests();
    _pendingFraction = fraction.clamp(0.0, 1.0);
    _isFollowing = false;
    notifyListeners();
  }

  /// Shows the final content row. Resumes following only if [followTail] is
  /// enabled; a normal list does not become a live feed by jumping to its end.
  void jumpToBottom() {
    _checkNotDisposed();
    _clearRequests();
    _pendingBottom = true;
    _isFollowing = _followTail;
    _unseenCount = 0;
    notifyListeners();
  }

  void _clearRequests() {
    _pendingJumpIndex = null;
    _pendingRevealIndex = null;
    _pendingScrollRows = 0;
    _pendingFraction = null;
    _pendingBottom = false;
  }

  void _revealSelection() {
    if (_selectedIndex == null) return;
    _clearRequests();
    _pendingRevealIndex = _selectedIndex;
    _isFollowing = false;
    notifyListeners();
  }

  void _handleCountChange(
    int newCount, {
    int? selectedIndex,
    int? appendedCount,
    bool identityAware = false,
  }) {
    final before = (_itemCount, _selectedIndex, _unseenCount);
    final oldCount = _itemCount;
    _itemCount = newCount;
    if (newCount == 0) {
      if (oldCount > 0) _restoreSelectionWhenNonEmpty = _selectedIndex != null;
      _selectedIndex = null;
    } else if (identityAware) {
      _selectedIndex = _clampSelection(selectedIndex);
    } else {
      _selectedIndex = _clampSelection(_selectedIndex);
    }
    if (_selectable &&
        oldCount == 0 &&
        newCount > 0 &&
        _selectedIndex == null &&
        _restoreSelectionWhenNonEmpty) {
      _selectedIndex = 0;
      if (!_isFollowing) _pendingRevealIndex = 0;
    }
    final arrived =
        appendedCount ?? (newCount > oldCount ? newCount - oldCount : 0);
    if (arrived > 0) {
      if (_isFollowing) {
        _unseenCount = 0;
      } else {
        _unseenCount += arrived;
      }
    }
    if (before != (_itemCount, _selectedIndex, _unseenCount)) notifyListeners();
  }

  int? _clampSelection(int? value) {
    if (!_selectable || value == null) return null;
    if (_itemCount == 0) return _attached ? null : value;
    return value.clamp(0, _itemCount - 1);
  }

  void _applyViewport({
    required ({int first, int last})? range,
    required int extent,
    required bool atTop,
    required bool atBottom,
    required double scrollFraction,
    required double visibleFraction,
  }) {
    final before = (
      _visibleRange,
      _viewportExtent,
      _atTop,
      _atBottom,
      _scrollFraction,
      _visibleFraction,
      _isFollowing,
      _unseenCount,
    );
    _visibleRange = range;
    _viewportExtent = extent;
    _atTop = atTop;
    _atBottom = atBottom;
    _scrollFraction = scrollFraction;
    _visibleFraction = visibleFraction;
    _isFollowing = _followTail && atBottom;
    if (atBottom) _unseenCount = 0;
    if (before !=
        (
          _visibleRange,
          _viewportExtent,
          _atTop,
          _atBottom,
          _scrollFraction,
          _visibleFraction,
          _isFollowing,
          _unseenCount,
        )) {
      _notifyAfterFrame();
    }
  }

  void _notifyAfterFrame() {
    final binding = _binding;
    if (binding == null || _metricsNotificationPending) return;
    _metricsNotificationPending = true;
    final attachment = _attachment;
    binding.addPostFrameCallback((_) {
      if (_disposed || attachment != _attachment) return;
      _metricsNotificationPending = false;
      notifyListeners();
    });
  }

  void _detach() {
    _attachment++;
    _metricsNotificationPending = false;
    _binding = null;
    _attached = false;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('ListController has been disposed.');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detach();
    _clearRequests();
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
///   - `ListView.builder(itemCount: N, itemBuilder: (context, index, active) {})` —
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
/// active)` for every visible item. The `active` flag is the
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
    this.selectable = true,
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
  /// visible ones. Each item builder invocation receives an `active`
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
    this.selectable = true,
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
    this.selectable = true,
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
  /// [children]. Invoked with `(context, index, active)`.
  final Widget Function(BuildContext context, int index, bool active)?
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

  /// Whether rows have a selection cursor and can activate. False keeps the
  /// list scrollable by wheel and keyboard, without selecting rows. Interactive
  /// child widgets keep their own input behavior.
  final bool selectable;

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

  /// Called when the user activates an item with Enter or a completed click.
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
  Object? _pressedItem;
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
      _controller._detach();
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? ListController();
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
    if (widget.selectable != oldWidget.selectable) {
      _pressedItem = null;
      _controller._selectable = widget.selectable;
      _controller._restoreSelectionWhenNonEmpty = widget.selectable;
      _controller._selectedIndex =
          widget.selectable && widget.effectiveItemCount > 0 ? 0 : null;
      _controller._pendingRevealIndex = _controller._selectedIndex;
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
      // Track new arrivals and clamp selection without coupling it to following.
      _controller._handleCountChange(newCount);
    }
    _captureIdentitySnapshot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller._binding = TuiBinding.maybeOf(context);
  }

  void _initializeController(int count) {
    _controller._itemCount = count;
    _controller._attached = true;
    _controller._selectable = widget.selectable;
    _controller._selectedIndex = _controller._clampSelection(
      _controller._selectedIndex,
    );
    if (!widget.selectable) _controller._restoreSelectionWhenNonEmpty = false;
    if (!_controller._pendingBottom &&
        _controller._pendingJumpIndex == null &&
        _controller._pendingFraction == null &&
        _controller._pendingScrollRows == 0) {
      _controller._pendingRevealIndex = _controller._selectedIndex;
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
    if (oldCount == 0) return newCount;
    if (oldFirstKey == null || oldLastKey == null) return 0;

    final first = _validatedIndexForKey(oldFirstKey);
    final last = _validatedIndexForKey(oldLastKey);
    // The old tail is gone: whatever this was, it was not an append after it.
    if (last == null) return 0;

    if (first == null) {
      // Head eviction with the old tail surviving. A rolling window — drop
      // the oldest, append the newest, the shape of every capped transcript
      // or log — is exactly this, and it nets ZERO in the count. Classifying
      // by `newCount - oldCount` reported "no growth", and the keyed-reorder
      // guard in `_handleCountChange` then read the followed item's new,
      // second-to-last index as "left the tail" and disengaged following for
      // good — on the first eviction, silently, with `unseenCount` stuck at
      // zero. Everything after the surviving tail is the append. (An
      // eviction mixed with a reorder is ambiguous here; the follow-mode docs
      // already disclaim mixed updates for [unseenCount], and continuing to
      // follow is the safe reading for a transcript.)
      return newCount - 1 - last;
    }

    if (last < first) return 0;
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

  void _setUserSelection(int index, {bool reveal = true}) {
    if (!widget.selectable) return;
    final before = _controller.selectedIndex;
    _controller.selectedIndex = index;
    if (!reveal) {
      // The pressed item is already visible. Revealing its top would move a
      // partially visible row under the pointer before the click finishes.
      _controller._pendingRevealIndex = null;
    } else if (_controller.selectedIndex == before) {
      _controller._revealSelection();
    }
    final after = _controller.selectedIndex;
    if (after != null && after != before) {
      widget.onSelectionChanged?.call(after);
    }
  }

  /// Detector adapter: the list consumes only the navigation it can
  /// act on, so an edge key falls through to an ancestor.
  void _detectKey(KeyEvent event) {
    if (_handleKey(event) == KeyEventResult.handled) event.consume();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final code = event.code;
    final count = widget.effectiveItemCount;
    if (count == 0) return KeyEventResult.ignored;

    final selected = _controller.selectedIndex;
    if (!widget.selectable || selected == null) {
      switch (code) {
        case KeyCode.arrowUp:
          return _scrollBy(-1)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case KeyCode.arrowDown:
          return _scrollBy(1) ? KeyEventResult.handled : KeyEventResult.ignored;
        case KeyCode.pageUp:
          return _scrollBy(-_controller._viewportExtent)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case KeyCode.pageDown:
          return _scrollBy(_controller._viewportExtent)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case KeyCode.home:
          _controller.jumpToIndex(0);
          return KeyEventResult.handled;
        case KeyCode.end:
          _controller.jumpToBottom();
          return KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    }

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

  /// Viewport movement is independent of selection and never takes focus.
  bool _scrollBy(int delta) {
    if (delta == 0 ||
        (delta < 0 && _controller.atTop) ||
        (delta > 0 && _controller.atBottom)) {
      return widget.edgeBehavior == EdgeBehavior.contain;
    }
    _controller.scrollBy(delta);
    return true;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller._detach();
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Object _itemIdentity(int index) {
    final key =
        widget.itemKeyBuilder?.call(index) ?? widget.children?[index].key;
    return key == null ? (index: index) : (key: key);
  }

  void _handleItemDown(int index) {
    if (index < 0 || index >= widget.effectiveItemCount) return;
    _pressedItem = _itemIdentity(index);
    _setUserSelection(index, reveal: false);
    _focusNode.requestFocus();
  }

  void _handleItemTap(int index) {
    final pressed = _pressedItem;
    _pressedItem = null;
    if (!widget.selectable ||
        index < 0 ||
        index >= widget.effectiveItemCount ||
        pressed != _itemIdentity(index)) {
      return;
    }
    widget.onActivate?.call(index);
  }

  Widget _maybeBoundary(Widget item) =>
      widget.addRepaintBoundaries ? RepaintBoundary(child: item) : item;

  @override
  Widget build(BuildContext context) {
    _controller._binding = TuiBinding.maybeOf(context);
    final selected = _controller.selectedIndex;
    final Widget content = MouseRegion(
      onScroll: (details) => _scrollBy(details.delta.row),
      child: KeyDetector(
        onKey: _detectKey,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
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
                          onTapDown: (_) => _handleItemDown(i),
                          onTap: () => _handleItemTap(i),
                          onTapCancel: () => _pressedItem = null,
                          child: widget.children![i],
                        ),
                      ),
                  ],
                );
              }

              // Lazy: builder + count. Item subtrees are mounted on demand by
              // the render object during layout; wrap each so a press selects it.
              // `.separated` composes a non-selectable separator into the row
              // block below its item. Clicking the block selects its item;
              // separators never enter
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
                  // alone), so a tap on a separator row selects the item it
                  // trails. Its region, like every other piece of geometry, is
                  // derived from layout, so a scrolled-but-unchanged block
                  // whose RepaintBoundary blits its cached cells at the new row
                  // has its tap region follow for free.
                  return _maybeBoundary(
                    GestureDetector(
                      onTapDown: (_) => _handleItemDown(index),
                      onTap: () => _handleItemTap(index),
                      onTapCancel: () => _pressedItem = null,
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

/// Shared row-based viewport math for eager and lazy lists. Only measuring an
/// item can mount it; all walks stop at the viewport except an explicit jump or
/// scroll through intervening rows. No global height table is required.
class _ListViewportLayout {
  int anchor = 0;
  int rowOffset = 0;

  Map<int, int> layout({
    required ListController controller,
    required int count,
    required int rows,
    required int Function(int index) measure,
  }) {
    if (count == 0 || rows == 0) {
      // A temporarily collapsed viewport must not discard follow intent.
      if (rows == 0 && controller._isFollowing) {
        controller._pendingBottom = true;
      }
      if (count == 0) {
        anchor = 0;
        rowOffset = 0;
      }
      controller._applyViewport(
        range: null,
        extent: rows,
        atTop: count == 0,
        atBottom: count == 0,
        scrollFraction: 0,
        visibleFraction: count == 0 ? 1 : 0,
      );
      return {};
    }
    final heights = <int, int>{};
    int height(int index) => heights.putIfAbsent(index, () => measure(index));

    void normalize() {
      while (rowOffset < 0 && anchor > 0) {
        anchor--;
        rowOffset += height(anchor);
      }
      if (rowOffset < 0) rowOffset = 0;
      while (anchor < count - 1 &&
          rowOffset > 0 &&
          rowOffset >= height(anchor)) {
        rowOffset -= height(anchor);
        anchor++;
      }
      final lastHeight = height(anchor);
      if (anchor == count - 1 && rowOffset >= lastHeight) {
        rowOffset = lastHeight > 0 ? lastHeight - 1 : 0;
      }
    }

    void endAt(int index) {
      anchor = index;
      rowOffset = height(index) - rows;
      normalize();
    }

    var reachesEnd = false;
    Map<int, int> window() {
      final offsets = <int, int>{};
      var row = -rowOffset;
      var index = anchor;
      for (; index < count && row < rows; index++) {
        final extent = height(index);
        if (extent > 0) offsets[index] = row;
        row += extent;
      }
      reachesEnd = index == count && row <= rows;
      return offsets;
    }

    anchor = anchor.clamp(0, count - 1);
    final jump = controller._pendingJumpIndex;
    final fraction = controller._pendingFraction;
    final priorRange = controller.visibleRange;
    final selected = controller.selectedIndex;
    final keepSelectionOnResize =
        jump == null &&
        fraction == null &&
        !controller._pendingBottom &&
        controller._pendingScrollRows == 0 &&
        !controller._isFollowing &&
        controller._viewportExtent != rows &&
        selected != null &&
        priorRange != null &&
        selected >= priorRange.first &&
        selected <= priorRange.last;
    final reveal =
        controller._pendingRevealIndex ??
        (keepSelectionOnResize ? selected : null);
    final scroll = controller._pendingScrollRows;
    final bottom = controller._pendingBottom || controller._isFollowing;
    controller._clearRequests();

    if (bottom) {
      endAt(count - 1);
    } else if (jump != null) {
      anchor = jump.clamp(0, count - 1);
      rowOffset = 0;
    } else if (fraction != null) {
      if (fraction == 1) {
        endAt(count - 1);
      } else {
        final position = fraction * count * (1 - controller.visibleFraction);
        anchor = position.floor().clamp(0, count - 1);
        rowOffset = ((position - anchor) * height(anchor)).round();
      }
    }
    if (!bottom && jump == null && fraction == null) {
      // Preserve the anchor identity on reflow instead of interpreting an old
      // local offset as movement into a different item.
      final anchorHeight = height(anchor);
      rowOffset = rowOffset.clamp(0, anchorHeight > 0 ? anchorHeight - 1 : 0);
    }
    rowOffset += scroll;
    normalize();
    var offsets = window();

    if (reveal != null) {
      final target = reveal.clamp(0, count - 1);
      final top = offsets[target];
      if (top == null || top < 0 || top + height(target) > rows) {
        if (target <= anchor || height(target) > rows) {
          anchor = target;
          rowOffset = 0;
        } else {
          endAt(target);
        }
        offsets = window();
      }
    }
    // A shrink or resize can leave blank space at the end. Backfill without
    // changing selection, including a jump whose target has zero height.
    final end = offsets.isEmpty
        ? 0
        : offsets.values.last + height(offsets.keys.last);
    if (reachesEnd && end < rows && (anchor > 0 || rowOffset > 0)) {
      rowOffset -= rows - end;
      normalize();
      offsets = window();
    }
    final first = offsets.isEmpty ? null : offsets.keys.first;
    final last = offsets.isEmpty ? null : offsets.keys.last;
    final atTop = anchor == 0 && rowOffset == 0;
    final atBottom = reachesEnd;
    var visibleUnits = 0.0;
    for (final entry in offsets.entries) {
      final start = entry.value.clamp(0, rows);
      final end = (entry.value + height(entry.key)).clamp(0, rows);
      visibleUnits += (end - start) / height(entry.key);
    }
    final position =
        anchor + (height(anchor) == 0 ? 0.0 : rowOffset / height(anchor));
    final maxPosition = count - visibleUnits;
    controller._applyViewport(
      range: first == null ? null : (first: first, last: last!),
      extent: rows,
      atTop: atTop,
      atBottom: atBottom,
      scrollFraction: atTop
          ? 0
          : atBottom
          ? 1
          : (maxPosition <= 0 ? 0 : (position / maxPosition).clamp(0.0, 1.0)),
      visibleFraction: atTop && atBottom
          ? 1
          : (visibleUnits / count).clamp(0.0, 1.0),
    );
    return offsets;
  }
}

void _paintListViewport(
  CellBuffer buffer,
  CellOffset offset,
  CellSize size,
  Map<RenderObject, CellOffset> children,
) {
  final needsClip = children.entries.any(
    (entry) =>
        entry.value.row < 0 ||
        entry.value.row + entry.key.size.rows > size.rows,
  );
  if (!needsClip) {
    for (final entry in children.entries) {
      entry.key.paint(buffer, offset + entry.value);
    }
    return;
  }
  final scratch = CellBuffer(size);
  for (final entry in children.entries) {
    entry.key.paint(scratch, entry.value);
  }
  buffer.copyFrom(scratch, offset);
}

class _RenderListView extends RenderObject implements RenderObjectWithChildren {
  @override
  CellOffset childOffsetOf(RenderObject child) =>
      _childOffsets[child] ?? CellOffset.zero;

  @override
  bool presentsChild(RenderObject child) => _visibleChildren.contains(child);

  @override
  CellRect? childClipOf(RenderObject child) =>
      CellRect(offset: CellOffset.zero, size: size);

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
  final _viewport = _ListViewportLayout();

  @override
  List<RenderObject> get children => List.unmodifiable(_children);

  @override
  void visitRenderChildren(void Function(RenderObject child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

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
    final removedIndex = singleRemovedRenderChildIndex(_children, newChildren);
    if (removedIndex != null) {
      final removed = _children[removedIndex];
      dropChild(removed);
      _childOffsets.remove(removed);
      _visibleChildren.remove(removed);
      _children.removeAt(removedIndex);
      markNeedsLayout();
      return;
    }

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
    final count = _children.length;
    final rows = constraints.maxRows;
    if (rows == null && count > 0) _throwUnboundedListHeight();
    final offsets = _viewport.layout(
      controller: _controller,
      count: count,
      rows: rows ?? 0,
      measure: (index) => _children[index]
          .layout(CellConstraints(maxCols: constraints.maxCols))
          .rows,
    );
    _childOffsets.clear();
    _visibleChildren.clear();
    for (final entry in offsets.entries) {
      final child = _children[entry.key];
      _childOffsets[child] = CellOffset(0, entry.value);
      _visibleChildren.add(child);
    }
    return constraints.constrain(CellSize(constraints.maxCols ?? 0, rows ?? 0));
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) =>
      _paintListViewport(buffer, offset, size, _childOffsets);
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
    // `active` flag can re-render the highlight without us
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
/// Uses the shared row-offset viewport layout, measuring and mounting only the
/// rows it visits. It then unmounts items outside the final visible range.
/// Selection is revealed only on request; ordinary rebuilds keep the anchor.
class _RenderLazyListView extends RenderObject
    implements RenderObjectWithChildren {
  @override
  CellOffset childOffsetOf(RenderObject child) =>
      _childOffsets[child] ?? CellOffset.zero;

  @override
  bool presentsChild(RenderObject child) {
    final index = _indexByObject[child];
    return index != null && identical(_activeByIndex[index], child);
  }

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

  final _viewport = _ListViewportLayout();
  int get _scrollAnchor => _viewport.anchor;
  set _scrollAnchor(int value) => _viewport.anchor = value;
  Object? _scrollAnchorItemKey;

  @override
  List<RenderObject> get children => _activeByIndex.values.toList();

  @override
  void visitRenderChildren(void Function(RenderObject child) visitor) {
    for (final child in _activeByIndex.values) {
      visitor(child);
    }
  }

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
  CellRect? childClipOf(RenderObject child) =>
      CellRect(offset: CellOffset.zero, size: size);

  @override
  CellSize performLayout(CellConstraints constraints) {
    final rows = constraints.maxRows;
    final element = _element;
    final count = _controller._itemCount;
    if (rows == null && count > 0 && element != null) {
      _throwUnboundedListHeight();
    }
    final measured = <int, RenderObject>{};
    final offsets = _viewport.layout(
      controller: _controller,
      count: element == null ? 0 : count,
      rows: rows ?? 0,
      measure: (index) {
        final child = element!.createChild(index)!;
        measured[index] = child;
        return child.layout(CellConstraints(maxCols: constraints.maxCols)).rows;
      },
    );
    _activeByIndex.clear();
    _indexByObject.clear();
    _childOffsets.clear();
    for (final entry in offsets.entries) {
      final child = measured[entry.key]!;
      _activeByIndex[entry.key] = child;
      _indexByObject[child] = entry.key;
      _childOffsets[child] = CellOffset(0, entry.value);
    }
    if (element != null) {
      for (final index in element.mountedIndices) {
        if (!offsets.containsKey(index)) element.disposeChild(index);
      }
    }
    _scrollAnchorItemKey = count == 0
        ? null
        : element?.itemKeyAt(_scrollAnchor);
    return constraints.constrain(CellSize(constraints.maxCols ?? 0, rows ?? 0));
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) =>
      _paintListViewport(buffer, offset, size, _childOffsets);
}
