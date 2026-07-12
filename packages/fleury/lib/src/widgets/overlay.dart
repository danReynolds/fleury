// Overlay + OverlayEntry: the positioning primitive for widgets
// that float on top of the main content.
//
// Mirrors Flutter's Overlay/OverlayEntry pair. It is the floating-layer
// primitive: `runApp` installs one at the root and mounts the app's
// Navigator as its bottom entry. Modals are Navigator routes (see
// `present`), not overlay entries — this direct API is for non-route
// floating content: autocomplete dropdowns, toasts, tooltips, drag
// previews.
//
// Design notes
//
//   - Each OverlayEntry is its own ChangeNotifier so removing it
//     can notify the OverlayState to rebuild without us managing a
//     manual subscription model.
//   - Entries stack in insertion order; the last-inserted entry is
//     visually on top and receives input first via the focus chain
//     (a modal entry's FocusScope sits inside its builder).
//   - The `opaque` flag marks an entry as fully covering everything
//     below it; lower entries are still in the element tree (so
//     state survives) but skip paint. Useful for full-screen
//     takeover modals that don't need the background painted at
//     all.

import 'dart:async';

import '../foundation/change_notifier.dart';
import '../foundation/key.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/render_repaint_boundary.dart';
import 'basic.dart' show Stack;
import 'error_boundary.dart';
import 'framework.dart';

/// One renderable layer inside an [Overlay]. Holds a builder and a
/// handle for removing the layer when it's no longer needed.
///
/// Typical lifecycle:
///
///   final entry = OverlayEntry(builder: (ctx) => MyDropdown());
///   Overlay.of(context).insert(entry);
///   // ... later ...
///   entry.remove();
class OverlayEntry extends ChangeNotifier {
  OverlayEntry({
    required this.builder,
    bool opaque = false,
    this.maintainState = true,
  }) : _opaque = opaque;

  /// Builds the layer's widget tree. Called with the [BuildContext]
  /// of the [Overlay] hosting this entry.
  final Widget Function(BuildContext) builder;

  /// When true, the [Overlay] skips painting entries below this one.
  /// Useful for full-screen modals that fully cover the app.
  bool _opaque;
  bool get opaque => _opaque;
  set opaque(bool value) {
    _checkNotDisposed();
    if (_opaque == value) return;
    _opaque = value;
    _markNeedsRebuild();
  }

  /// When false, the entry's element subtree is unmounted whenever
  /// the entry is currently hidden by an opaque higher entry, and
  /// re-mounted when it becomes visible again. When true (the
  /// default) the subtree stays mounted regardless of visibility
  /// — its state survives, which is usually what apps want.
  final bool maintainState;

  OverlayState? _state;
  bool _disposed = false;

  /// Removes this entry from its [Overlay]. No-op if not currently
  /// inserted, or if already removed.
  void remove() {
    final state = _state;
    if (state == null) return;
    _state = null;
    state._removeEntry(this);
  }

  /// Asks the [Overlay] to rebuild this entry. Useful when the entry
  /// builder depends on state outside the widget tree that has
  /// changed.
  void markNeedsBuild() {
    _checkNotDisposed();
    _markNeedsRebuild();
  }

  void _markNeedsRebuild() {
    // Notify the OverlayState so it rebuilds just this entry.
    notifyListeners();
  }

  void _attach(OverlayState state) {
    _checkNotDisposed();
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    remove();
    _disposed = true;
    super.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('OverlayEntry has been disposed.');
    }
  }
}

/// Converges an [OverlayEntry]'s mountedness onto a predicate: mounted while
/// [shouldMount] returns true, removed while it returns false.
///
/// This is the lazy-layer primitive for entries that exist up front (so
/// their subtree state survives) but should only be MOUNTED while they have
/// something to show — the runtime error banner, a toast layer. An entry
/// that idles mounted-but-empty is not free: it keeps the host overlay
/// multi-entry, which keeps the adaptive per-entry repaint boundaries
/// engaged (see [Overlay.addRepaintBoundaries]) and taxes every app-dirty
/// frame with a full-screen cache write + blit.
///
/// Actual mountedness is derived from the entry's overlay attachment each
/// pass — never stored — so the helper cannot desync from the overlay's
/// lifecycle: a pass that finds no overlay (teardown, not yet mounted)
/// simply returns, and any later [sync] retries with nothing to repair.
/// The helper assumes it is the entry's only mount owner; don't also
/// insert/remove the entry by hand.
///
/// The entry is always inserted ON TOP (no above/below anchor), on purpose:
/// a lazily-mounted layer surfaces above whatever the app has stacked —
/// an error banner must show over an opaque takeover entry, not under it.
class OverlayEntryMountSync {
  OverlayEntryMountSync({
    required OverlayState? Function() resolveOverlay,
    required this.entry,
    required bool Function() shouldMount,
  }) : _resolveOverlay = resolveOverlay,
       _shouldMount = shouldMount;

  /// The entry whose mountedness this helper owns.
  final OverlayEntry entry;

  final OverlayState? Function() _resolveOverlay;
  final bool Function() _shouldMount;
  final List<Listenable> _attached = <Listenable>[];
  bool _syncPending = false;
  bool _disposed = false;

  /// Requests convergence a microtask from now.
  ///
  /// Coalesced: any number of calls before the microtask runs produce one
  /// pass, and the pass re-reads [shouldMount] — so a burst (an error storm,
  /// a report immediately dismissed) converges once, on the final state.
  /// The deferral makes this safe to call from anywhere, including mid-frame
  /// notifications (a contained render error reported during paint): frame
  /// bodies are fully synchronous, so the microtask runs strictly after the
  /// frame — never a setState-during-build. Use [syncNow] only from call
  /// sites where a synchronous setState is already legal.
  void sync() {
    if (_disposed || _syncPending) return;
    _syncPending = true;
    scheduleMicrotask(() {
      _syncPending = false;
      if (_disposed) return;
      _converge();
    });
  }

  /// Converges immediately instead of a microtask from now.
  ///
  /// For call sites where a synchronous `setState` is already legal (an
  /// event handler, a ticker callback) and same-turn mounting is the
  /// expected UX — a toast should be on screen by the very next pump.
  void syncNow() {
    if (_disposed) return;
    _converge();
  }

  /// Wires [sync] to [listenable]'s notifications; undone by [dispose].
  void attachTo(Listenable listenable) {
    if (_disposed) return;
    listenable.addListener(sync);
    _attached.add(listenable);
  }

  /// Detaches listeners and removes [entry] if currently mounted. The entry
  /// itself is not disposed — it remains the caller's to reuse or dispose.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final listenable in _attached) {
      listenable.removeListener(sync);
    }
    _attached.clear();
    entry.remove(); // no-op when not mounted
  }

  void _converge() {
    final overlay = _resolveOverlay();
    if (overlay == null) return;
    // Derived, not stored: the entry's attachment IS the mounted state.
    final mounted = entry._state != null;
    final desired = _shouldMount();
    if (desired == mounted) return;
    if (desired) {
      overlay.insert(entry);
    } else {
      entry.remove();
    }
  }
}

/// A region that hosts a stack of [OverlayEntry]s — modals,
/// popovers, toasts, tooltips — that render on top of the main
/// content.
///
/// Apps usually don't construct an `Overlay` themselves; `runApp`
/// installs one at the root of the tree so `Overlay.of(context)` is
/// always reachable.
class Overlay extends StatefulWidget {
  const Overlay({
    super.key,
    this.initialEntries = const <OverlayEntry>[],
    this.addRepaintBoundaries = true,
  });

  /// Entries to insert immediately after the overlay mounts, in
  /// stacking order (first is bottom-most, last is top-most). This
  /// is how `runApp` installs the user's root widget as the
  /// bottom-most entry.
  final List<OverlayEntry> initialEntries;

  /// Wrap each entry in a repaint boundary (default true) so one entry's
  /// churn — a toast sliding in, a palette filtering as the user types —
  /// repaints only that entry instead of re-walking the paint of every
  /// entry beneath it (a non-opaque floating entry leaves the entries below
  /// visible, so without boundaries they re-paint on every frame it
  /// animates). The boundary replays its pointer and semantic regions on
  /// cache-hit, so cached entries stay interactive and accessible.
  ///
  /// The boundaries engage only while MORE THAN ONE entry is visible: with
  /// a single visible entry there is no sibling churn to protect against,
  /// so the entry (typically an always-dirty full-screen app root) pays no
  /// per-frame cache-write + blit. The moment a second entry appears,
  /// engaging costs one warm-up repaint — on the insertion frame, which is
  /// layout-dirty anyway — and every later churn frame blits the clean
  /// entries from cache (see [RenderRepaintBoundary.cachingEnabled]). Turn
  /// this off only for an overlay whose co-visible entries are almost
  /// always all dirty at once: each then pays an extra cache-write + blit
  /// on top of its normal paint.
  final bool addRepaintBoundaries;

  @override
  OverlayState createState() => OverlayState();

  /// Returns the [OverlayState] of the nearest ancestor [Overlay].
  /// Throws if none exists (a missing overlay almost always means
  /// `runApp` wasn't used or the call site is outside the app's
  /// root).
  static OverlayState of(BuildContext context) {
    final state = context.findAncestorStateOfType<OverlayState>();
    if (state == null) {
      throw StateError(
        'No Overlay above this BuildContext. Make sure you started the '
        'app with runApp() (which installs a root Overlay), or wrap '
        'your widget tree manually in Overlay(initialEntries: [...]).',
      );
    }
    return state;
  }

  /// Variant of [of] that returns null instead of throwing.
  static OverlayState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<OverlayState>();
  }
}

/// Mutable state for an [Overlay]. Provides [insert] for adding
/// entries and is the type returned by [Overlay.of].
class OverlayState extends State<Overlay> {
  final List<OverlayEntry> _entries = <OverlayEntry>[];

  // The index of the first entry painted (the topmost opaque one).
  // Cached from the last build so [_onEntryChanged] can tell when a
  // dynamic `opaque` change actually alters occlusion.
  int _firstVisible = 0;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.initialEntries) {
      entry._attach(this);
      entry.addListener(_onEntryChanged);
      _entries.add(entry);
    }
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.removeListener(_onEntryChanged);
      entry._detach();
    }
    super.dispose();
  }

  int _computeFirstVisible() {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].opaque) return i;
    }
    return 0;
  }

  /// Fired when an entry notifies (opaque flip or markNeedsBuild). The
  /// entry's own widget rebuilds itself for content changes; here we
  /// only rebuild the overlay when the *occlusion* set would change
  /// (e.g. an entry became opaque/transparent), which the per-entry
  /// rebuild can't recompute.
  void _onEntryChanged() {
    if (!mounted) return;
    if (_computeFirstVisible() != _firstVisible) setState(() {});
  }

  /// Inserts [entry] into this overlay. If neither [above] nor
  /// [below] is supplied, the entry goes on top of the current
  /// stack.
  void insert(OverlayEntry entry, {OverlayEntry? above, OverlayEntry? below}) {
    assert(
      above == null || below == null,
      'Provide at most one of above / below.',
    );
    assert(entry._state == null, 'Entry is already inserted into an Overlay.');
    entry._attach(this);
    entry.addListener(_onEntryChanged);
    setState(() {
      if (above != null) {
        final index = _entries.indexOf(above);
        if (index == -1) {
          throw StateError(
            'insert(..., above: anchor) — anchor is not in this Overlay.',
          );
        }
        _entries.insert(index + 1, entry);
      } else if (below != null) {
        final index = _entries.indexOf(below);
        if (index == -1) {
          throw StateError(
            'insert(..., below: anchor) — anchor is not in this Overlay.',
          );
        }
        _entries.insert(index, entry);
      } else {
        _entries.add(entry);
      }
    });
  }

  void _removeEntry(OverlayEntry entry) {
    entry.removeListener(_onEntryChanged);
    setState(() {
      _entries.remove(entry);
    });
  }

  /// Snapshot of currently-mounted entries, in stacking order
  /// (bottom-first). Returned as an unmodifiable list.
  List<OverlayEntry> get entries => List.unmodifiable(_entries);

  @override
  Widget build(BuildContext context) {
    // Determine which entries are visible. An opaque entry hides
    // everything below it; non-opaque entries pass paint through.
    final firstVisibleIndex = _computeFirstVisible();
    _firstVisible = firstVisibleIndex;
    // Entry boundaries only pay while a visible sibling exists to be
    // protected from (see [Overlay.addRepaintBoundaries]); with one visible
    // entry they stay pass-through. Insert/remove/occlusion changes all
    // rebuild this widget, so the flag tracks structure with no extra
    // bookkeeping. Count-only on purpose: addRepaintBoundaries already
    // gates whether the boundary exists at all (the wrap in
    // _OverlayEntryWidget), so it has no business in the engagement rule.
    final cachingEnabled = _entries.length - firstVisibleIndex > 1;
    return Stack(
      children: <Widget>[
        for (var i = 0; i < _entries.length; i++)
          if (i >= firstVisibleIndex || _entries[i].maintainState)
            _OverlayEntryWidget(
              key: ValueKey<OverlayEntry>(_entries[i]),
              entry: _entries[i],
              visible: i >= firstVisibleIndex,
              addRepaintBoundary: widget.addRepaintBoundaries,
              cachingEnabled: cachingEnabled,
            ),
      ],
    );
  }
}

/// Wraps an [OverlayEntry] so its builder runs through a normal
/// widget element. Subscribing to the entry's [Listenable]
/// notifications gives `markNeedsBuild` a way to schedule a
/// rebuild.
class _OverlayEntryWidget extends StatefulWidget {
  const _OverlayEntryWidget({
    super.key,
    required this.entry,
    required this.visible,
    required this.addRepaintBoundary,
    required this.cachingEnabled,
  });

  final OverlayEntry entry;
  final bool visible;
  final bool addRepaintBoundary;
  final bool cachingEnabled;

  @override
  State<_OverlayEntryWidget> createState() => _OverlayEntryWidgetState();
}

class _OverlayEntryWidgetState extends State<_OverlayEntryWidget> {
  @override
  void initState() {
    super.initState();
    widget.entry.addListener(_onEntryNotify);
  }

  @override
  void didUpdateWidget(_OverlayEntryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entry, oldWidget.entry)) {
      oldWidget.entry.removeListener(_onEntryNotify);
      widget.entry.addListener(_onEntryNotify);
    }
  }

  @override
  void dispose() {
    widget.entry.removeListener(_onEntryNotify);
    super.dispose();
  }

  void _onEntryNotify() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // We always wrap the entry's content in _Visibility, regardless
    // of the current visible value. This keeps the immediate child
    // type stable across visibility flips so the subtree below
    // (the entry's actual content + any State it holds) survives
    // reconciliation. _Visibility only changes the RenderObject's
    // paint behavior — layout is unaffected, so siblings in the
    // Stack don't shift.
    //
    // The boundary wrap is equally stable: whether it's applied depends
    // only on the Overlay's addRepaintBoundaries flag, never on entry
    // count, visibility, or frame state — so the entry's subtree is never
    // reparented (which would drop its State). Entry count only flips the
    // boundary's cachingEnabled, a render-object property.
    final content = widget.entry.builder(context);
    return _Visibility(
      visible: widget.visible,
      // Implicit containment: a crashing overlay entry (a dialog, a
      // dropdown, a toast) renders the error presentation in its own
      // cells instead of taking down the entries beneath it. Outside the
      // repaint boundary so it also catches throws from the boundary's
      // cached repaint/blit.
      child: ErrorBoundary(
        child: widget.addRepaintBoundary
            ? _EntryRepaintBoundary(
                cachingEnabled: widget.cachingEnabled,
                child: content,
              )
            : content,
      ),
    );
  }
}

/// The per-entry repaint boundary. Private rather than a flag on the public
/// `RepaintBoundary` widget for two reasons: that widget mirrors Flutter's
/// API surface (which has no such knob), and its `WidgetUpdatePruner`
/// equivalence check would prune a rebuild whose only change is the flag —
/// the flip would never reach the render object. Here the render object
/// stays in the tree unconditionally (element-stable — an engagement flip
/// never reparents the entry's subtree) while
/// [RenderRepaintBoundary.cachingEnabled] switches the caching on and off
/// with overlay structure.
class _EntryRepaintBoundary extends SingleChildRenderObjectWidget {
  const _EntryRepaintBoundary({
    required this.cachingEnabled,
    required Widget super.child,
  });

  final bool cachingEnabled;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      RenderRepaintBoundary(cachingEnabled: cachingEnabled);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderRepaintBoundary renderObject,
  ) {
    renderObject.cachingEnabled = cachingEnabled;
  }
}

/// Layout the child normally; conditionally suppress paint.
///
/// Used by [Overlay] to hide entries that an opaque higher entry
/// covers, without unmounting them (so their State survives the
/// hide/show cycle). Distinct from collapsing to an empty box —
/// which would force the framework to unmount the entry's subtree
/// the moment it becomes invisible.
class _Visibility extends SingleChildRenderObjectWidget {
  const _Visibility({required this.visible, required Widget super.child});

  final bool visible;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderVisibility(visible: visible);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderVisibility renderObject,
  ) {
    renderObject.visible = visible;
  }
}

class _RenderVisibility extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderVisibility({required bool visible}) : _visible = visible;

  bool _visible;
  bool get visible => _visible;
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    markNeedsPaintOnly();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(const CellSize(0, 0));
    return c.layout(constraints);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (!_visible) return;
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}
