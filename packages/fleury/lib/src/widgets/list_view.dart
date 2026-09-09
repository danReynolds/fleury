// An eager or lazy one-axis list. Both renderers share item-anchor viewport
// calculations; only measurement and offsets depend on the scrolling axis.

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/cell.dart';
import '../rendering/layout.dart';
import '../rendering/scroll_axis.dart';
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
import 'theme.dart';

/// Returns the stable data identity for the item currently at [index].
///
/// The key belongs to the data item, not its current position. It must remain
/// equal when that item moves after a prepend, reorder, or filtered update.
typedef ListItemKeyBuilder = Object Function(int index);

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

/// Navigation cursor and viewport state for a [ListView].
///
/// Moving the cursor reveals its item. Scrolling leaves the cursor alone,
/// and a rebuild preserves the viewport. Listeners receive changed viewport
/// metrics after the frame, when [visibleRange] describes the rendered content.
class ListController extends ChangeNotifier {
  /// Starts with [initialIndex] as the current row and reveals it on mount.
  /// The index is clamped to the available items. This does not select the row
  /// or take keyboard focus; use [ListView.autofocus] to request focus.
  /// An explicit viewport request or [followTail] takes precedence over reveal.
  ListController({
    int? initialIndex = 0,
    bool followTail = false,
    @Deprecated('Use followTail instead.') bool? pinToBottom,
  }) : _currentIndex = initialIndex,
       _restoreCurrentWhenNonEmpty = initialIndex != null,
       _followTail = pinToBottom ?? followTail,
       _isFollowing = pinToBottom ?? followTail,
       _pendingBottom = pinToBottom ?? followTail;

  int? _currentIndex;
  int _itemCount = 0;
  bool _attached = false;
  bool _selectable = true;
  bool _restoreCurrentWhenNonEmpty;
  ({int first, int last})? _visibleRange;
  int _viewportExtent = 0;
  bool _atTop = true;
  bool _atBottom = true;
  double _scrollFraction = 0;
  double _visibleFraction = 1;
  int? _pendingJumpIndex;
  int? _pendingRevealIndex;
  int _pendingScrollCells = 0;
  double? _pendingFraction;
  bool _pendingBottom;
  bool _followTail;
  bool _isFollowing;
  int _unseenCount = 0;
  bool _disposed = false;
  Object? _owner;

  void _attach(Object owner) {
    _checkNotDisposed();
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError(
        'ListController can attach to only one owning view at a time.',
      );
    }
    _owner = owner;
  }

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

  /// Whether the viewport includes the start / end of the content.
  bool get atStart => _atTop;
  bool get atEnd => _atBottom;

  /// Vertical spelling of [atStart].
  bool get atTop => atStart;

  /// Vertical spelling of [atEnd].
  bool get atBottom => atEnd;

  /// Appended items not yet seen at the end of an ordered feed. Prepends do not
  /// count when stable item keys are provided. Mixed reorders and insertions are
  /// not a general unread-item diff. Cleared on reaching the end.
  int get unseenCount => _unseenCount;
  int get itemCount => _itemCount;

  /// Visible item indices, including partially visible items; null when empty
  /// or before layout. Items can span multiple cells along the scrolling axis.
  ({int first, int last})? get visibleRange => _visibleRange;

  /// Approximate scrollbar position in 0..1. Unmeasured items count equally;
  /// partial visible items contribute their measured fraction. The endpoints
  /// always correspond to the start and end of the content.
  double get scrollFraction => _scrollFraction;

  /// Fraction of the item collection visible, accounting for partially visible items.
  /// This is an estimate for variable-size items not yet measured.
  double get visibleFraction => _visibleFraction;

  /// Remembered cursor index, independent of keyboard focus and scrolling.
  /// Defaults to zero; an explicit null starts without a cursor. A non-selectable list
  /// keeps this null. Values clamp once attached to a list.
  int? get currentIndex => _currentIndex;
  set currentIndex(int? value) {
    _checkNotDisposed();
    if (!_selectable) return;
    _restoreCurrentWhenNonEmpty = value != null;
    final next = _clampCurrentIndex(value);
    if (next == _currentIndex) return;
    _currentIndex = next;
    _clearRequests();
    _pendingRevealIndex = next;
    // The completed viewport, not the current index, decides whether to resume.
    _isFollowing = false;
    notifyListeners();
  }

  /// Places an item at the viewport start, clamped to the final full viewport. Does not
  /// change the cursor. The resulting position survives unrelated rebuilds.
  void jumpToIndex(int index) {
    _checkNotDisposed();
    _clearRequests();
    // A realized zero-row layout with items (collapsed pane) cannot show a
    // jump. Drop it rather than stash a target that would scroll away from
    // the still-current selection on expand. Distinguish from pre-first-
    // layout (defaults keep visibleFraction at 1) so jump-before-render
    // still works. Empty lists still stash — restore+reveal keep selection
    // on-screen after refill.
    if (_viewportExtent == 0 && _itemCount > 0 && _visibleFraction == 0) {
      _isFollowing = false;
      notifyListeners();
      return;
    }
    _pendingJumpIndex = _itemCount == 0
        ? index
        : index.clamp(0, _itemCount - 1);
    _isFollowing = false;
    notifyListeners();
  }

  /// Scrolls by cells along the list's axis, including within an oversized item.
  void scrollBy(int delta) {
    _checkNotDisposed();
    if (delta == 0) return;
    _pendingRevealIndex = null;
    _pendingBottom = false;
    _pendingScrollCells += delta;
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

  /// Shows the end of the final item. Resumes following only if [followTail] is
  /// enabled; a normal list does not become a live feed by jumping to its end.
  void jumpToEnd() {
    _checkNotDisposed();
    _clearRequests();
    _pendingBottom = true;
    _isFollowing = _followTail;
    _unseenCount = 0;
    notifyListeners();
  }

  /// Vertical spelling of [jumpToEnd].
  void jumpToBottom() => jumpToEnd();

  void _clearRequests() {
    _pendingJumpIndex = null;
    _pendingRevealIndex = null;
    _pendingScrollCells = 0;
    _pendingFraction = null;
    _pendingBottom = false;
  }

  void _revealCurrentItem() {
    if (_currentIndex == null) return;
    _clearRequests();
    _pendingRevealIndex = _currentIndex;
    _isFollowing = false;
    notifyListeners();
  }

  void _handleCountChange(
    int newCount, {
    int? currentIndex,
    int? appendedCount,
    bool identityAware = false,
  }) {
    final before = (_itemCount, _currentIndex, _unseenCount);
    final oldCount = _itemCount;
    _itemCount = newCount;
    if (newCount == 0) {
      if (oldCount > 0) _restoreCurrentWhenNonEmpty = _currentIndex != null;
      _currentIndex = null;
    } else if (identityAware) {
      _currentIndex = _clampCurrentIndex(currentIndex);
    } else {
      _currentIndex = _clampCurrentIndex(_currentIndex);
    }
    if (_selectable &&
        oldCount == 0 &&
        newCount > 0 &&
        _currentIndex == null &&
        _restoreCurrentWhenNonEmpty) {
      _currentIndex = 0;
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
    if (before != (_itemCount, _currentIndex, _unseenCount)) notifyListeners();
  }

  int? _clampCurrentIndex(int? value) {
    if (!_attached) return value;
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

  void _detach([Object? owner]) {
    if (owner != null && !identical(_owner, owner)) return;
    _owner = null;
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
///   - `ListView.builder(itemCount: N, itemBuilder: (context, index, highlighted) {})` —
///     lazy. Only items currently within the viewport are mounted as
///     element subtrees; items scroll into/out of the mounted set as
///     the user navigates. Supports variable sizes along the scrolling axis.
///     Best for long lists where most items are off-screen (file pickers, log
///     viewers, completion menus).
///
/// When focused, the widget claims the main-axis arrows, Home, End,
/// and enter:
///   - Arrows / Home / End move the current item and report [onFocusedItemChanged];
///     the viewport scrolls to keep it visible.
///   - Enter or a completed click selects the current item via [onSelect].
///   - Up at the first item / Down at the last item respects
///     [edgeBehavior]: `contain` consumes the key, `bubble` returns
///     it to the focus chain so an ancestor `KeyBindings` (e.g. one
///     coordinating sidebar + main pane focus traversal) can react.
///
/// [itemBuilder] receives `(context, index, highlighted)` for each visible item.
/// The current item remains highlighted when keyboard focus leaves the list.
/// The controller's [ListController.currentIndex] identifies that item.
/// Setting it moves the cursor without selecting an item or taking focus.
///
/// All constructors apply the theme's selection style to the current row's
/// text. Plain Text children need no cursor styling. Explicit child styles
/// override that default; the builder flag is available for custom decoration.
class ListView extends StatefulWidget {
  /// Eager constructor: build all items upfront from a fixed list
  /// of widgets. Use when you have a bounded set of widgets already
  /// constructed. The current row is highlighted automatically.
  const ListView({
    super.key,
    this.controller,
    this.focusNode,
    required List<Widget> this.children,
    this.autofocus = false,
    this.selectable = true,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.onSelect,
    this.onFocusedItemChanged,
    this.scrollbar = false,
    this.scrollDirection = Axis.vertical,
    this.addRepaintBoundaries = true,
  }) : itemCount = null,
       itemBuilder = null,
       separatorBuilder = null,
       itemKeyBuilder = null;

  /// Lazy constructor: build items on demand by index, mount only the
  /// visible ones. Each item builder invocation receives a `highlighted`
  /// flag for styling the current row.
  const ListView.builder({
    super.key,
    this.controller,
    this.focusNode,
    required int this.itemCount,
    required Widget Function(BuildContext, int, bool) this.itemBuilder,
    this.itemKeyBuilder,
    this.autofocus = false,
    this.selectable = true,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.onSelect,
    this.onFocusedItemChanged,
    this.scrollbar = false,
    this.scrollDirection = Axis.vertical,
    this.addRepaintBoundaries = true,
  }) : assert(itemCount >= 0, 'itemCount must be non-negative'),
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
  /// navigation walks items only. Each follows its item along [scrollDirection],
  /// and only the item is a tap target. A separator cannot move the cursor or
  /// select the item it trails.
  const ListView.separated({
    super.key,
    this.controller,
    this.focusNode,
    required int this.itemCount,
    required Widget Function(BuildContext, int, bool) this.itemBuilder,
    required Widget? Function(BuildContext, int) this.separatorBuilder,
    this.itemKeyBuilder,
    this.autofocus = false,
    this.selectable = true,
    this.edgeBehavior = EdgeBehavior.bubble,
    this.onSelect,
    this.onFocusedItemChanged,
    this.scrollbar = false,
    this.scrollDirection = Axis.vertical,
    this.addRepaintBoundaries = true,
  }) : assert(itemCount >= 0, 'itemCount must be non-negative'),
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
  /// [children]. Invoked with `(context, index, highlighted)`.
  final Widget Function(BuildContext context, int index, bool highlighted)?
  itemBuilder;

  /// Per-gap separator builder ([ListView.separated] form). Called with
  /// `(context, i)` for the gap between item `i` and item `i + 1`; may
  /// return `null` to omit that separator. Null for the eager and
  /// [ListView.builder] forms.
  final Widget? Function(BuildContext context, int index)? separatorBuilder;

  /// Stable data identity for lazy items.
  ///
  /// Supply this when items can move.
  /// Fleury then preserves the current item, viewport anchor, and mounted
  /// element state across prepends, removals, filters, and reorders. Keys must
  /// be unique within this list. This is data identity only: it does not install
  /// a Fleury `Key` on the row or create a semantic identifier. Add those at the
  /// item-widget layer when the application needs either contract.
  ///
  /// Fleury reads all item keys once on mount and whenever the parent supplies
  /// an updated ListView, building its own reverse lookup in O(itemCount) time
  /// and space. The row widgets are still built and laid out only as needed.
  /// Keys must have stable equality and hash codes; duplicates are an error.
  final ListItemKeyBuilder? itemKeyBuilder;

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

  /// Whether the list owns a row cursor and selects rows with click or Enter.
  /// False keeps it scrollable without a row cursor. Interactive
  /// child widgets keep their own input behavior.
  final bool selectable;

  /// How main-axis arrows and wheel gestures behave at an edge.
  /// Cross-axis input can reach other controls or a surrounding scroll view.
  final EdgeBehavior edgeBehavior;

  /// When true, wrap the list in a [Scrollbar] gutter that reflects the
  /// visible item range and lets the mouse drag/click to scroll. A one-line
  /// opt-in: the bar shares this list's controller, so there is nothing extra
  /// to wire. See [Scrollbar.list].
  ///
  /// The gutter needs a bounded cross axis: width for a vertical list,
  /// height for a horizontal list. The list itself needs a bounded main axis.
  final bool scrollbar;

  /// Layout and scrolling axis. Items are measured at their natural extent
  /// along this axis and constrained to the viewport on the other axis.
  final Axis scrollDirection;

  /// Selects an item on Enter or a completed click, including repeated choices.
  /// Browsing, scrolling, and controller writes do not call this. Empty lists
  /// and lists without a cursor cannot select an item.
  final void Function(int index)? onSelect;

  /// Reports user input moving the cursor to a different item.
  ///
  /// Programmatic controller writes and identity-preserving data updates do
  /// not call this callback.
  final void Function(int index)? onFocusedItemChanged;

  /// Effective number of items, regardless of which constructor was
  /// used. Returns `children!.length` for eager, `itemCount!` for
  /// lazy.
  int get effectiveItemCount => children?.length ?? itemCount!;

  @override
  State<ListView> createState() => _ListViewState();
}

/// A single data revision's identities; widget creation stays lazy.
class _ListItemIdentities {
  _ListItemIdentities(this.keys, this.indexByKey);

  final List<Object> keys;
  final Map<Object, int> indexByKey;

  static _ListItemIdentities? capture(ListView widget) {
    final keyBuilder = widget.itemKeyBuilder;
    if (keyBuilder == null) return null;
    final keys = <Object>[];
    final indexByKey = <Object, int>{};
    for (var index = 0; index < widget.effectiveItemCount; index++) {
      final key = keyBuilder(index);
      final previous = indexByKey[key];
      if (previous != null) {
        throw StateError(
          'Duplicate ListView item key $key at indices $previous and $index. '
          'itemKeyBuilder must return a unique, stable key for each item.',
        );
      }
      keys.add(key);
      indexByKey[key] = index;
    }
    return _ListItemIdentities(keys, indexByKey);
  }
}

class _ListViewState extends State<ListView> {
  late ListController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  Object? _pressedItem;
  Object? _currentItemKey;
  Object? _firstItemKey;
  Object? _lastItemKey;
  int _dataRevision = 0;
  _ListItemIdentities? _identities;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ListView');
    _ownsFocusNode = widget.focusNode == null;
    final count = widget.effectiveItemCount;
    _controller = widget.controller ?? ListController();
    _ownsController = widget.controller == null;
    _initializeController(count);
    _controller.addListener(_onControllerChange);
    _identities = _ListItemIdentities.capture(widget);
    _captureIdentitySnapshot();
  }

  @override
  void didUpdateWidget(ListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _identities = _ListItemIdentities.capture(widget);
    _dataRevision++;
    final oldCount = oldWidget.effectiveItemCount;
    final oldCurrentKey = _currentItemKey;
    final oldFirstKey = _firstItemKey;
    final oldLastKey = _lastItemKey;
    var controllerChanged = false;
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      _controller._detach(this);
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
      _controller._restoreCurrentWhenNonEmpty = widget.selectable;
      _controller._currentIndex =
          widget.selectable && widget.effectiveItemCount > 0 ? 0 : null;
      _controller._pendingRevealIndex = _controller._currentIndex;
    }
    final newCount = widget.effectiveItemCount;
    final identityAware =
        !controllerChanged &&
        oldWidget.itemKeyBuilder != null &&
        _identities != null;
    if (identityAware) {
      final remappedCurrent = _remapCurrentIndex(
        oldCurrentKey,
        fallback: _controller.currentIndex,
      );
      final appendedCount = _classifyTrailingGrowth(
        oldCount: oldCount,
        newCount: newCount,
        oldFirstKey: oldFirstKey,
        oldLastKey: oldLastKey,
      );
      _controller._handleCountChange(
        newCount,
        currentIndex: remappedCurrent,
        appendedCount: appendedCount,
        identityAware: true,
      );
    } else if (!controllerChanged && newCount != oldCount) {
      // Track new arrivals and clamp cursor without coupling it to following.
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
    _controller._attach(this);
    _controller._itemCount = count;
    _controller._attached = true;
    _controller._selectable = widget.selectable;
    _controller._currentIndex = _controller._clampCurrentIndex(
      _controller._currentIndex,
    );
    if (!widget.selectable) _controller._restoreCurrentWhenNonEmpty = false;
    if (!_controller._pendingBottom &&
        _controller._pendingJumpIndex == null &&
        _controller._pendingFraction == null &&
        _controller._pendingScrollCells == 0) {
      _controller._pendingRevealIndex = _controller._currentIndex;
    }
  }

  void _onControllerChange() {
    _captureCurrentItemKey();
    setState(() {});
  }

  void _captureIdentitySnapshot() {
    final keys = _identities?.keys;
    if (keys == null || keys.isEmpty) {
      _currentItemKey = null;
      _firstItemKey = null;
      _lastItemKey = null;
      return;
    }
    _firstItemKey = keys.first;
    _lastItemKey = keys.last;
    _captureCurrentItemKey();
  }

  void _captureCurrentItemKey() {
    final keys = _identities?.keys;
    final current = _controller.currentIndex;
    _currentItemKey =
        keys != null && current != null && current >= 0 && current < keys.length
        ? keys[current]
        : null;
  }

  int? _remapCurrentIndex(Object? key, {required int? fallback}) {
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

  int? _validatedIndexForKey(Object key) => _identities?.indexByKey[key];

  void _moveCurrentItem(int index, {bool reveal = true}) {
    if (!widget.selectable) return;
    final before = _controller.currentIndex;
    _controller.currentIndex = index;
    if (!reveal) {
      // The pressed item is already visible. Revealing its top would move a
      // partially visible row under the pointer before the click finishes.
      _controller._pendingRevealIndex = null;
    } else if (_controller.currentIndex == before) {
      _controller._revealCurrentItem();
    }
    final after = _controller.currentIndex;
    if (after != null && after != before) {
      widget.onFocusedItemChanged?.call(after);
    }
  }

  /// Detector adapter: the list consumes only the navigation it can
  /// act on, so an edge key falls through to an ancestor.
  void _detectKey(KeyEvent event) {
    if (_handleKey(event) == KeyEventResult.handled) event.consume();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final code = widget.scrollDirection.navigationKey(event.code);
    if (code == null) return KeyEventResult.ignored;
    final count = widget.effectiveItemCount;
    if (count == 0) return KeyEventResult.ignored;

    final current = _controller.currentIndex;
    if (!widget.selectable || current == null) {
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
          _controller.jumpToEnd();
          return KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    }

    switch (code) {
      case KeyCode.arrowUp:
        if (current <= 0) return _edgeResult();
        _moveCurrentItem(current - 1);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (current >= count - 1) return _edgeResult();
        _moveCurrentItem(current + 1);
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        if (current <= 0) return _edgeResult();
        _moveCurrentItem((current - _pageSize()).clamp(0, count - 1));
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        if (current >= count - 1) return _edgeResult();
        _moveCurrentItem((current + _pageSize()).clamp(0, count - 1));
        return KeyEventResult.handled;
      case KeyCode.home:
        _moveCurrentItem(0);
        return KeyEventResult.handled;
      case KeyCode.end:
        _moveCurrentItem(count - 1);
        return KeyEventResult.handled;
      case KeyCode.enter:
        widget.onSelect?.call(current);
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

  /// Viewport movement is independent of cursor and never takes focus.
  bool _scrollBy(int delta) {
    if (delta == 0 ||
        (delta < 0 && _controller.atStart) ||
        (delta > 0 && _controller.atEnd)) {
      return widget.edgeBehavior == EdgeBehavior.contain;
    }
    _controller.scrollBy(delta);
    return true;
  }

  @override
  void deactivate() {
    _controller.removeListener(_onControllerChange);
    _controller._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _controller._attach(this);
    _controller._attached = true;
    _controller._binding = TuiBinding.maybeOf(context);
    _controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller._detach(this);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Object _itemIdentity(int index) {
    final key = _identities?.keys[index] ?? widget.children?[index].key;
    return key == null ? (index: index) : (key: key);
  }

  void _handleItemDown(int index) {
    if (index < 0 || index >= widget.effectiveItemCount) return;
    _pressedItem = _itemIdentity(index);
    _moveCurrentItem(index, reveal: false);
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
    widget.onSelect?.call(index);
  }

  Widget _styleItem(Widget item, bool highlighted) => DefaultTextStyle.merge(
    style: highlighted ? Theme.of(context).selectionStyle : CellStyle.none,
    child: item,
  );

  Widget _maybeBoundary(Widget item) =>
      widget.addRepaintBoundaries ? RepaintBoundary(child: item) : item;

  @override
  Widget build(BuildContext context) {
    _controller._binding = TuiBinding.maybeOf(context);
    final Widget content = MouseRegion(
      onScroll: (details) {
        final delta = widget.scrollDirection.position(details.delta);
        return delta != 0 && _scrollBy(delta);
      },
      child: KeyDetector(
        onKey: _detectKey,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          child: _buildBody(context),
        ),
      ),
    );
    if (!widget.scrollbar) return content;
    // The gutter shares this list's controller and axis.
    return Scrollbar.list(
      controller: _controller,
      scrollDirection: widget.scrollDirection,
      child: content,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.children != null) {
      // Eager: build all children upfront, render object picks the
      // visible window. Each is made tappable for pointer navigation,
      // then wrapped in a RepaintBoundary so one item's change repaints
      // only that item (boundary outermost = Flutter parity; it replays
      // the item's pointer + semantic regions on cache-hit).
      return _ListViewBody(
        controller: _controller,
        scrollDirection: widget.scrollDirection,
        children: <Widget>[
          for (var i = 0; i < widget.children!.length; i++)
            _maybeBoundary(
              GestureDetector(
                onTapDown: (_) => _handleItemDown(i),
                onTap: () => _handleItemTap(i),
                onTapCancel: () => _pressedItem = null,
                child: _styleItem(
                  widget.children![i],
                  i == _controller.currentIndex,
                ),
              ),
            ),
        ],
      );
    }

    // Lazy: builder + count. Item subtrees are mounted on demand by
    // the render object during layout; a completed click selects an item.
    // `.separated` composes a non-selectable separator after each item along the scrolling axis. Only the item participates in the click gesture;
    // separators never enter the index math.
    final separatorBuilder = widget.separatorBuilder;
    final itemCount = widget.itemCount!;
    return _LazyListBody(
      controller: _controller,
      scrollDirection: widget.scrollDirection,
      itemCount: itemCount,
      dataRevision: _dataRevision,
      identities: _identities,
      itemBuilder: (context, index, itemActive) {
        final built = _styleItem(
          widget.itemBuilder!(context, index, itemActive),
          itemActive,
        );
        // No separator after the last item, when none was requested, or
        // when the builder returns null for this gap.
        final separator = separatorBuilder == null || index >= itemCount - 1
            ? null
            : separatorBuilder(context, index);
        final item = GestureDetector(
          onTapDown: (_) => _handleItemDown(index),
          onTap: () => _handleItemTap(index),
          onTapCancel: () => _pressedItem = null,
          child: built,
        );
        // Geometry follows the item through scrolling and cached repaint.
        // Releasing over a separator cancels the item's click gesture.
        return _maybeBoundary(
          separator == null
              ? item
              : Flex(
                  direction: widget.scrollDirection,
                  mainAxisSize: MainAxisSize.min,
                  children: [item, separator],
                ),
        );
      },
      currentIndex: _controller.currentIndex,
    );
  }
}

class _ListViewBody extends MultiChildRenderObjectWidget {
  const _ListViewBody({
    required this.controller,
    required this.scrollDirection,
    required super.children,
  });

  final ListController controller;
  final Axis scrollDirection;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderListView(
      controller: controller,
      scrollDirection: scrollDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderListView renderObject,
  ) {
    renderObject.controller = controller;
    renderObject.scrollDirection = scrollDirection;
    // The controller is mutable; cursor and pending jump changes are read
    // during layout even when the controller identity is stable.
    renderObject.markNeedsLayout();
  }
}

/// Both list renderers require a bounded main axis to know which items to mount.
Never _throwUnboundedListExtent(Axis direction) {
  final dimension = direction == Axis.vertical ? 'height' : 'width';
  throw StateError(
    'ListView needs a bounded $dimension to window its items, but was given an '
    'unbounded $dimension (a ScrollView, or a Column/Row child with '
    'mainAxisSize.min, gets an unbounded main axis). Every item would be '
    'dropped. Give it a bounded $dimension — wrap it in an Expanded or a '
    'SizedBox($dimension: ...).',
  );
}

/// Shared one-dimensional viewport math for eager and lazy lists. Only measuring
/// an item can mount it. No global table of item extents is required.
class _ListViewportLayout {
  int anchor = 0;
  int itemOffset = 0;
  bool _axisChanged = false;

  void changeAxis() {
    itemOffset = 0;
    _axisChanged = true;
  }

  Map<int, int> layout({
    required ListController controller,
    required int count,
    required int viewportExtent,
    required int Function(int index) measure,
  }) {
    if (count == 0 || viewportExtent == 0) {
      // A temporarily collapsed viewport must not discard follow intent.
      if (viewportExtent == 0 && controller._isFollowing) {
        controller._pendingBottom = true;
      }
      // Zero-row (collapsed pane): a jump cannot be realized. Drop it so
      // expand does not scroll the window away from the still-current
      // selection and leave the cursor stranded off-screen. Empty lists
      // keep a stashed jump — restore+reveal keep selection on-screen.
      if (rows == 0) {
        controller._pendingJumpIndex = null;
      }
      if (count == 0) {
        anchor = 0;
        itemOffset = 0;
      }
      controller._applyViewport(
        range: null,
        extent: viewportExtent,
        atTop: count == 0,
        atBottom: count == 0,
        scrollFraction: 0,
        visibleFraction: count == 0 ? 1 : 0,
      );
      return {};
    }
    final extents = <int, int>{};
    int itemExtent(int index) =>
        extents.putIfAbsent(index, () => measure(index));

    void normalize() {
      while (itemOffset < 0 && anchor > 0) {
        anchor--;
        itemOffset += itemExtent(anchor);
      }
      if (itemOffset < 0) itemOffset = 0;
      while (anchor < count - 1 &&
          itemOffset > 0 &&
          itemOffset >= itemExtent(anchor)) {
        itemOffset -= itemExtent(anchor);
        anchor++;
      }
      final lastExtent = itemExtent(anchor);
      if (anchor == count - 1 && itemOffset >= lastExtent) {
        itemOffset = lastExtent > 0 ? lastExtent - 1 : 0;
      }
    }

    void endAt(int index) {
      anchor = index;
      itemOffset = itemExtent(index) - viewportExtent;
      normalize();
    }

    var reachesEnd = false;
    Map<int, int> window() {
      final offsets = <int, int>{};
      var positionInViewport = -itemOffset;
      var index = anchor;
      for (; index < count && positionInViewport < viewportExtent; index++) {
        final extent = itemExtent(index);
        if (extent > 0) offsets[index] = positionInViewport;
        positionInViewport += extent;
      }
      reachesEnd = index == count && positionInViewport <= viewportExtent;
      return offsets;
    }

    anchor = anchor.clamp(0, count - 1);
    final jump = controller._pendingJumpIndex;
    final fraction = controller._pendingFraction;
    final priorRange = controller.visibleRange;
    final current = controller.currentIndex;
    final keepSelectionOnResize =
        jump == null &&
        fraction == null &&
        !controller._pendingBottom &&
        controller._pendingScrollCells == 0 &&
        !controller._isFollowing &&
        (_axisChanged || controller._viewportExtent != viewportExtent) &&
        current != null &&
        priorRange != null &&
        current >= priorRange.first &&
        current <= priorRange.last;
    _axisChanged = false;
    final reveal =
        controller._pendingRevealIndex ??
        (keepSelectionOnResize ? current : null);
    final scroll = controller._pendingScrollCells;
    final bottom = controller._pendingBottom || controller._isFollowing;
    controller._clearRequests();

    if (bottom) {
      endAt(count - 1);
    } else if (jump != null) {
      anchor = jump.clamp(0, count - 1);
      itemOffset = 0;
    } else if (fraction != null) {
      if (fraction == 1) {
        endAt(count - 1);
      } else {
        final position = fraction * count * (1 - controller.visibleFraction);
        anchor = position.floor().clamp(0, count - 1);
        itemOffset = ((position - anchor) * itemExtent(anchor)).round();
      }
    }
    if (!bottom && jump == null && fraction == null) {
      // Preserve the anchor identity on reflow instead of interpreting an old
      // local offset as movement into a different item.
      final anchorExtent = itemExtent(anchor);
      itemOffset = itemOffset.clamp(0, anchorExtent > 0 ? anchorExtent - 1 : 0);
    }
    itemOffset += scroll;
    normalize();
    var offsets = window();

    if (reveal != null) {
      final target = reveal.clamp(0, count - 1);
      final top = offsets[target];
      if (top == null || top < 0 || top + itemExtent(target) > viewportExtent) {
        if (target <= anchor || itemExtent(target) > viewportExtent) {
          anchor = target;
          itemOffset = 0;
        } else {
          endAt(target);
        }
        offsets = window();
      }
    }
    // A shrink or resize can leave blank space at the end. Backfill without
    // changing cursor, including a jump whose target has zero extent.
    final end = offsets.isEmpty
        ? 0
        : offsets.values.last + itemExtent(offsets.keys.last);
    if (reachesEnd && end < viewportExtent && (anchor > 0 || itemOffset > 0)) {
      itemOffset -= viewportExtent - end;
      normalize();
      offsets = window();
    }
    final first = offsets.isEmpty ? null : offsets.keys.first;
    final last = offsets.isEmpty ? null : offsets.keys.last;
    final atTop = anchor == 0 && itemOffset == 0;
    final atBottom = reachesEnd;
    var visibleUnits = 0.0;
    for (final entry in offsets.entries) {
      final start = entry.value.clamp(0, viewportExtent);
      final end = (entry.value + itemExtent(entry.key)).clamp(
        0,
        viewportExtent,
      );
      visibleUnits += (end - start) / itemExtent(entry.key);
    }
    final position =
        anchor +
        (itemExtent(anchor) == 0 ? 0.0 : itemOffset / itemExtent(anchor));
    final maxPosition = count - visibleUnits;
    controller._applyViewport(
      range: first == null ? null : (first: first, last: last!),
      extent: viewportExtent,
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
        entry.value.col < 0 ||
        entry.value.col + entry.key.size.cols > size.cols ||
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

  _RenderListView({
    required ListController controller,
    required Axis scrollDirection,
  }) : _controller = controller,
       _scrollDirection = scrollDirection;

  Axis _scrollDirection;
  set scrollDirection(Axis value) {
    if (_scrollDirection == value) return;
    _scrollDirection = value;
    _viewport.changeAxis();
    markNeedsLayout();
  }

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
  /// when only cursor / item count changes.
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
    final extent = _scrollDirection.maxExtent(constraints);
    if (extent == null && count > 0) {
      _throwUnboundedListExtent(_scrollDirection);
    }
    final offsets = _viewport.layout(
      controller: _controller,
      count: count,
      viewportExtent: extent ?? 0,
      measure: (index) => _scrollDirection.extent(
        _children[index].layout(_scrollDirection.childConstraints(constraints)),
      ),
    );
    _childOffsets.clear();
    _visibleChildren.clear();
    for (final entry in offsets.entries) {
      final child = _children[entry.key];
      _childOffsets[child] = _scrollDirection.offset(entry.value);
      _visibleChildren.add(child);
    }
    return constraints.constrain(
      _scrollDirection.size(
        extent ?? 0,
        _scrollDirection.maxCrossExtent(constraints) ??
            _childOffsets.keys.fold<int>(0, (extent, child) {
              final childExtent = _scrollDirection.crossExtent(child.size);
              return childExtent > extent ? childExtent : extent;
            }),
      ),
    );
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
    required this.scrollDirection,
    required this.itemCount,
    required this.dataRevision,
    required this.itemBuilder,
    required this.identities,
    required this.currentIndex,
  });

  final ListController controller;
  final Axis scrollDirection;
  final int itemCount;
  final int dataRevision;
  final Widget Function(BuildContext, int, bool) itemBuilder;
  final _ListItemIdentities? identities;
  final int? currentIndex;

  @override
  _LazyListElement createElement() => _LazyListElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLazyListView(
      controller: controller,
      scrollDirection: scrollDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderLazyListView renderObject,
  ) {
    renderObject.controller = controller;
    renderObject.scrollDirection = scrollDirection;
    // The controller is mutable; cursor and pending jump changes drive
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
    final identities = newWidget.identities;
    if (identities == null) {
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
      final newIndex = identities.indexByKey[itemKey];
      if (newIndex == null) {
        removed.add((index: oldIndex, element: element));
        continue;
      }
      remapped[newIndex] = element;
      oldToNew[oldIndex] = newIndex;
    }

    for (final entry in removed) {
      _mountedChildren.remove(entry.index);
      _itemKeyByElement.remove(entry.element);
      entry.element.unmount();
    }

    renderObject._remapDataIndices(oldToNew, identities: identities);
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

  @override
  void performRebuild() {
    // Re-update each currently-mounted child with a freshly-built
    // widget from the (possibly new) itemBuilder. This is what
    // propagates a currentIndex change to existing items so their
    // `highlighted` flag can re-render the highlight without us
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
      final newWidget = widget.itemBuilder(this, i, i == widget.currentIndex);
      if (identical(oldEl.widget, newWidget)) continue;
      if (Widget.canUpdate(oldEl.widget, newWidget)) {
        oldEl.update(newWidget);
      } else {
        final itemKey = itemKeyAt(i);
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
    final itemKey = itemKeyAt(index);
    final newWidget = widget.itemBuilder(
      this,
      index,
      index == widget.currentIndex,
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

  Object? itemKeyAt(int index) => widget.identities?.keys[index];

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
/// Uses the shared item-offset viewport layout, measuring and mounting only the
/// items it visits. It then unmounts items outside the final visible range.
/// Cursor is revealed only on request; ordinary rebuilds keep the anchor.
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

  _RenderLazyListView({
    required ListController controller,
    required Axis scrollDirection,
  }) : _controller = controller,
       _scrollDirection = scrollDirection;

  Axis _scrollDirection;
  set scrollDirection(Axis value) {
    if (_scrollDirection == value) return;
    _scrollDirection = value;
    _viewport.changeAxis();
    markNeedsLayout();
  }

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
    required _ListItemIdentities identities,
  }) {
    final remappedAnchor = identities.indexByKey[_scrollAnchorItemKey];
    if (remappedAnchor != null) _scrollAnchor = remappedAnchor;

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
    final extent = _scrollDirection.maxExtent(constraints);
    final element = _element;
    final count = _controller._itemCount;
    if (extent == null && count > 0 && element != null) {
      _throwUnboundedListExtent(_scrollDirection);
    }
    final measured = <int, RenderObject>{};
    final offsets = _viewport.layout(
      controller: _controller,
      count: element == null ? 0 : count,
      viewportExtent: extent ?? 0,
      measure: (index) {
        final child = element!.createChild(index)!;
        measured[index] = child;
        return _scrollDirection.extent(
          child.layout(_scrollDirection.childConstraints(constraints)),
        );
      },
    );
    _activeByIndex.clear();
    _indexByObject.clear();
    _childOffsets.clear();
    for (final entry in offsets.entries) {
      final child = measured[entry.key]!;
      _activeByIndex[entry.key] = child;
      _indexByObject[child] = entry.key;
      _childOffsets[child] = _scrollDirection.offset(entry.value);
    }
    if (element != null) {
      for (final index in element.mountedIndices) {
        if (!offsets.containsKey(index)) element.disposeChild(index);
      }
    }
    _scrollAnchorItemKey = count == 0
        ? null
        : element?.itemKeyAt(_scrollAnchor);
    return constraints.constrain(
      _scrollDirection.size(
        extent ?? 0,
        _scrollDirection.maxCrossExtent(constraints) ??
            _childOffsets.keys.fold<int>(0, (extent, child) {
              final childExtent = _scrollDirection.crossExtent(child.size);
              return childExtent > extent ? childExtent : extent;
            }),
      ),
    );
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) =>
      _paintListViewport(buffer, offset, size, _childOffsets);
}
