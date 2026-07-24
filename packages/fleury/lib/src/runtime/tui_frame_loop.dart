import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/render_object.dart';

/// Paints one frame into [buffer].
typedef TuiFramePaintCallback = void Function(CellBuffer buffer);

/// Shared double-buffer frame loop state for Fleury hosts.
///
/// This is intentionally smaller than a full runtime: hosts still own mounting,
/// input dispatch, post-frame callbacks, debug surfaces, and output. The shared
/// part is the critical buffer/damage lifecycle that every host must keep
/// consistent:
///
/// 1. allocate front/back buffers for the current viewport;
/// 2. clear the back buffer without recording damage;
/// 3. enable paint damage tracking before the framework paints;
/// 4. collect paint damage plus conservative layout-damage signals;
/// 5. expose the previous/next buffers to the presenter;
/// 6. swap buffers only after the presenter has consumed the frame.
final class TuiFrameLoop {
  /// [renderDamage] should be the runtime's tracker
  /// (`TuiRuntime.renderDamageTracker`) so layout/conservative-paint
  /// invalidation from that runtime's render tree reaches this loop's frame
  /// damage. A loop constructed without one sees no layout-damage signal and
  /// conservatively treats every frame as requiring a full diff.
  TuiFrameLoop({RenderDamageTracker? renderDamage})
    : _renderDamage = renderDamage;

  final RenderDamageTracker? _renderDamage;

  /// Enables the debug oracle asserting that frame damage covers every changed
  /// cell (see [_damageCoversChanges]).
  ///
  /// Opt-in rather than always-on under `assert`: the check is O(cells) per
  /// frame, and benchmarks run with asserts enabled, so leaving it on would tax
  /// the very gates that guard this path. Tests exercising damage flip it on.
  static bool debugCheckDamageCoverage = false;

  CellBuffer? _frontBuffer;
  CellBuffer? _backBuffer;
  var _requireFullRepaint = true;

  // Paint damage of the render that produced the currently SHOWN front buffer,
  // plus the render in flight (promoted to "shown" on commit).
  //
  // [render] clears the back buffer WITHOUT damage tracking, so every cell the
  // shown frame painted that this frame does not repaint silently becomes empty
  // — a real change (content -> empty) carrying no paint damage of its own. A
  // retained presenter only re-applies damaged rows, so those cells keep stale
  // content: the ghost left behind when animated content moves or shrinks.
  //
  // Unioning the shown frame's painted set into this frame's damage restores the
  // invariant that damage covers every changed cell. It is exact, not merely
  // conservative: `shown \ current` IS the vacated set, and a cell painted in
  // neither frame was empty in both, so the union adds nothing else.
  CellRect? _shownPaintBounds;
  Set<int>? _shownPaintRows;
  CellRect? _pendingPaintBounds;
  Set<int>? _pendingPaintRows;

  /// Drops the buffer pool and forces the next frame to repaint from scratch.
  ///
  /// Use when viewport size changes or when a host knows the presenter cannot
  /// safely diff against the prior visible frame.
  void resetBuffers() {
    _frontBuffer = null;
    _backBuffer = null;
    _requireFullRepaint = true;
    _shownPaintBounds = null;
    _shownPaintRows = null;
    _pendingPaintBounds = null;
    _pendingPaintRows = null;
  }

  /// Forces the next rendered frame to be presented as a full repaint.
  void markFullRepaint() {
    _requireFullRepaint = true;
  }

  /// Whether [render] must run for [size] regardless of runtime dirt.
  ///
  /// True when the buffer pool is cold or sized differently, or a full
  /// repaint is forced. When false AND the runtime reports no frame work,
  /// the front buffer is still exact and the host may skip the frame.
  bool needsRender(CellSize size) {
    final front = _frontBuffer;
    return _requireFullRepaint || front == null || front.size != size;
  }

  /// Prepares and paints one frame.
  ///
  /// Returns null when [size] is empty. The caller must pass the returned frame
  /// to [commit] only after the presenter has consumed [TuiRenderedFrame.next].
  TuiRenderedFrame? render({
    required CellSize size,
    required TuiFramePaintCallback paint,
  }) {
    if (size.isEmpty) return null;
    if (_frontBuffer == null || _frontBuffer!.size != size) {
      _frontBuffer = CellBuffer(size);
      _backBuffer = CellBuffer(size);
      _requireFullRepaint = true;
      // A resized frame repaints fully; a painted set from the old geometry
      // would only carry stale row indexes into the union.
      _shownPaintBounds = null;
      _shownPaintRows = null;
    }

    final previous = _frontBuffer!;
    final next = _backBuffer!;
    final bufferPrepareStopwatch = Stopwatch()..start();
    next.withoutDamageTracking(next.clear);
    next.resetDamageTracking();
    bufferPrepareStopwatch.stop();

    paint(next);

    _renderDamage?.takeVisualChange();
    final paintBounds = next.takeDamageBounds();
    final paintRows = next.takeDamageRows();
    // Keep THIS frame's own painted set (not the union) for the next frame's
    // union — promoting the union instead would accumulate without bound.
    _pendingPaintBounds = paintBounds;
    _pendingPaintRows = paintRows;
    // Only complete a BOUNDED claim. A null bounds means "this frame did not
    // track what it mutated" — presenters already answer that with a full diff,
    // which catches vacated cells on its own. Unioning there would be actively
    // wrong: it would turn "unknown" into a bounded set and make the presenter
    // trust it, silently dropping untracked writes outside that set.
    final damage = TuiFrameDamage(
      fullRepaint: _requireFullRepaint,
      requiresFullDiff: _renderDamage?.takeRequiresFullDiff() ?? true,
      paintDamageBounds: paintBounds == null
          ? null
          : _unionBounds(paintBounds, _shownPaintBounds),
      paintDamageRows: paintBounds == null
          ? paintRows
          : _unionRows(paintRows, _shownPaintRows),
    );
    _requireFullRepaint = false;
    assert(
      !debugCheckDamageCoverage || _damageCoversChanges(previous, next, damage),
      'frame damage does not cover every changed cell: a retained presenter '
      'only re-applies damaged rows, so the uncovered cells will keep stale '
      'content on screen',
    );

    return TuiRenderedFrame._(
      previous: previous,
      next: next,
      damage: damage,
      bufferPrepareTime: bufferPrepareStopwatch.elapsed,
    );
  }

  /// Commits [frame] as the new visible frame after presentation.
  void commit(TuiRenderedFrame frame) {
    _backBuffer = frame.previous;
    _frontBuffer = frame.next;
    // What is on screen is now what this frame painted, so that becomes the
    // set the next frame must union against. An uncommitted (dropped) frame
    // deliberately leaves this alone: the screen still shows the older frame.
    _shownPaintBounds = _pendingPaintBounds;
    _shownPaintRows = _pendingPaintRows;
  }

  /// Whether [damage] accounts for every cell that differs between the shown
  /// frame and the new one — the contract every retained presenter relies on.
  ///
  /// A presenter re-applies only damaged rows and assumes the rest still match
  /// what is on screen. An uncovered change is therefore invisible to it and
  /// stays stale until something unrelated dirties that row.
  static bool _damageCoversChanges(
    CellBuffer previous,
    CellBuffer next,
    TuiFrameDamage damage,
  ) {
    // These modes tell presenters to diff or repaint everything, so they cover
    // any change by construction.
    if (damage.fullRepaint ||
        damage.requiresFullDiff ||
        damage.diffBounds == null ||
        previous.size != next.size) {
      return true;
    }
    final dirty = damage.dirtyRowsFor(next.size);
    if (dirty.isFull) return true;
    final covered = dirty.rows.toSet();
    for (var row = 0; row < next.size.rows; row++) {
      if (covered.contains(row)) continue;
      for (var col = 0; col < next.size.cols; col++) {
        if (previous.atColRow(col, row) != next.atColRow(col, row)) return false;
      }
    }
    return true;
  }

  static CellRect? _unionBounds(CellRect? current, CellRect? shown) {
    if (current == null) return shown;
    if (shown == null) return current;
    return current.union(shown);
  }

  /// [current] arrives fresh from `takeDamageRows()`, so an empty counterpart
  /// lets the union reuse a set instead of allocating a per-frame copy.
  static Set<int> _unionRows(Set<int> current, Set<int>? shown) {
    if (shown == null || shown.isEmpty) return current;
    if (current.isEmpty) return shown;
    return <int>{...current, ...shown};
  }
}

/// One frame produced by [TuiFrameLoop].
final class TuiRenderedFrame {
  const TuiRenderedFrame._({
    required this.previous,
    required this.next,
    required this.damage,
    required this.bufferPrepareTime,
  });

  /// The buffer representing the last committed frame.
  final CellBuffer previous;

  /// The newly painted frame.
  final CellBuffer next;

  /// Damage metadata captured while painting [next].
  final TuiFrameDamage damage;

  /// Time spent preparing [next] for painting.
  ///
  /// This is intentionally separate from framework build/layout/paint timing:
  /// hosts need to distinguish buffer lifecycle cost from widget work when a
  /// retained presenter still misses a frame budget.
  final Duration bufferPrepareTime;
}

/// Paint damage and conservative full-diff state for one frame.
final class TuiFrameDamage {
  const TuiFrameDamage({
    required this.fullRepaint,
    required this.requiresFullDiff,
    required this.paintDamageBounds,
    this.paintDamageRows,
  });

  /// Whether the presenter should treat this as a full repaint.
  final bool fullRepaint;

  /// Whether layout/conservative damage invalidates paint bounds.
  final bool requiresFullDiff;

  /// Conservative bounds of cells mutated by paint.
  final CellRect? paintDamageBounds;

  /// The exact rows mutated by paint, when tracked.
  ///
  /// Unlike [paintDamageBounds] (a single union rect), scattered writes stay
  /// disjoint: five separated dirty rows are five rows here, not the tall
  /// rect spanning them. Null/empty falls back to the rect.
  final Set<int>? paintDamageRows;

  /// Bounds safe to pass to a diffing presenter.
  ///
  /// A null value means "do not bound the presenter diff"; hosts should pass
  /// null through to presenters rather than treating it as "no work".
  CellRect? get diffBounds =>
      fullRepaint || requiresFullDiff ? null : paintDamageBounds;

  /// Converts the current cell-rect damage signal into presenter dirty rows.
  ///
  /// This is the Phase 1 adapter from Fleury's current union damage bounds to
  /// the row-oriented shape a DOM presenter needs. It is intentionally
  /// conservative: a null [diffBounds] means all rows must be considered dirty,
  /// not that no rows changed.
  TuiDirtyRows dirtyRowsFor(CellSize size) {
    final bounds = diffBounds;
    if (bounds == null) return TuiDirtyRows.full(size.rows);
    final rows = paintDamageRows;
    if (rows != null && rows.isNotEmpty) {
      return TuiDirtyRows.fromRows(rows, rowCount: size.rows);
    }
    return TuiDirtyRows.range(bounds.top, bounds.bottom, rowCount: size.rows);
  }
}

/// Row-oriented damage for presenters.
///
/// The type is separate from [CellRect] so per-row or multi-range damage can
/// evolve without forcing presenters to consume cell-rect internals.
final class TuiDirtyRows {
  const TuiDirtyRows._({required this.isFull, required this.ranges});

  /// All visible rows are dirty.
  factory TuiDirtyRows.full(int rowCount) {
    if (rowCount <= 0) return const TuiDirtyRows.none();
    return TuiDirtyRows._(
      isFull: true,
      ranges: List.unmodifiable([TuiDirtyRowRange(0, rowCount)]),
    );
  }

  /// A single dirty row range clipped to [rowCount].
  factory TuiDirtyRows.range(
    int startRow,
    int endRow, {
    required int rowCount,
  }) {
    final clippedStart = _clipRow(startRow, rowCount);
    final clippedEnd = _clipRow(endRow, rowCount);
    if (clippedStart >= clippedEnd) return const TuiDirtyRows.none();
    // A range covering every row IS full damage; report it as such so
    // full-damage consumers (scroll detection, coverage) see the truth.
    if (clippedStart == 0 && clippedEnd == rowCount) {
      return TuiDirtyRows.full(rowCount);
    }
    return TuiDirtyRows._(
      isFull: false,
      ranges: List.unmodifiable([TuiDirtyRowRange(clippedStart, clippedEnd)]),
    );
  }

  /// Dirty rows from arbitrary row indexes, collapsed into sorted ranges.
  factory TuiDirtyRows.fromRows(Iterable<int> rows, {required int rowCount}) {
    if (rowCount <= 0) return const TuiDirtyRows.none();
    final sorted =
        rows.where((row) => row >= 0 && row < rowCount).toSet().toList()
          ..sort();
    if (sorted.isEmpty) return const TuiDirtyRows.none();
    if (sorted.length == rowCount) return TuiDirtyRows.full(rowCount);

    final ranges = <TuiDirtyRowRange>[];
    var start = sorted.first;
    var previous = start;
    for (final row in sorted.skip(1)) {
      if (row == previous + 1) {
        previous = row;
        continue;
      }
      ranges.add(TuiDirtyRowRange(start, previous + 1));
      start = row;
      previous = row;
    }
    ranges.add(TuiDirtyRowRange(start, previous + 1));

    return TuiDirtyRows._(isFull: false, ranges: List.unmodifiable(ranges));
  }

  /// No rows are dirty.
  const TuiDirtyRows.none() : this._(isFull: false, ranges: const []);

  /// Whether the damage represents every row in the frame.
  final bool isFull;

  /// Dirty ranges using `[startRow, endRow)` coordinates.
  final List<TuiDirtyRowRange> ranges;

  /// Whether no rows need presentation.
  bool get isEmpty => ranges.isEmpty;

  /// Number of dirty rows represented by [ranges].
  int get dirtyRowCount => ranges.fold(0, (sum, range) => sum + range.rowCount);

  /// Iterates dirty row indexes in ascending order.
  Iterable<int> get rows sync* {
    for (final range in ranges) {
      for (var row = range.startRow; row < range.endRow; row++) {
        yield row;
      }
    }
  }

  static int _clipRow(int row, int rowCount) {
    if (row < 0) return 0;
    if (row > rowCount) return rowCount;
    return row;
  }
}

/// A half-open dirty row range: `[startRow, endRow)`.
final class TuiDirtyRowRange {
  const TuiDirtyRowRange(this.startRow, this.endRow)
    : assert(startRow >= 0, 'startRow must be non-negative'),
      assert(endRow >= startRow, 'endRow must be >= startRow');

  /// First dirty row, inclusive.
  final int startRow;

  /// Last dirty row, exclusive.
  final int endRow;

  /// Number of rows in this range.
  int get rowCount => endRow - startRow;

  /// Whether [row] is included in this range.
  bool contains(int row) => row >= startRow && row < endRow;
}
