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

  CellBuffer? _frontBuffer;
  CellBuffer? _backBuffer;
  var _requireFullRepaint = true;

  /// Drops the buffer pool and forces the next frame to repaint from scratch.
  ///
  /// Use when viewport size changes or when a host knows the presenter cannot
  /// safely diff against the prior visible frame.
  void resetBuffers() {
    _frontBuffer = null;
    _backBuffer = null;
    _requireFullRepaint = true;
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
    }

    final previous = _frontBuffer!;
    final next = _backBuffer!;
    final bufferPrepareStopwatch = Stopwatch()..start();
    next.withoutDamageTracking(next.clear);
    next.resetDamageTracking();
    bufferPrepareStopwatch.stop();

    paint(next);

    _renderDamage?.takeVisualChange();
    final damage = TuiFrameDamage(
      fullRepaint: _requireFullRepaint,
      requiresFullDiff: _renderDamage?.takeRequiresFullDiff() ?? true,
      paintDamageBounds: next.takeDamageBounds(),
      paintDamageRows: next.takeDamageRows(),
    );
    _requireFullRepaint = false;

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
