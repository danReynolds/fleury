import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/render_object.dart';
import '../rendering/scroll_detection.dart';

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
/// 2. clear the back buffer;
/// 3. let the framework paint into it;
/// 4. DERIVE the frame's damage by comparing it against the shown buffer;
/// 5. expose the previous/next buffers to the presenter;
/// 6. swap buffers only after the presenter has consumed the frame.
///
/// Step 4 is the load-bearing one. Damage used to be REPORTED — every writer
/// declared what it touched — which meant any writer that stayed silent made a
/// real change invisible to the presenter, and stale cells stayed on screen.
/// Comparing the buffers is ground truth, so nothing can be forgotten.
final class TuiFrameLoop {
  /// [renderDamage] is the runtime's tracker
  /// (`TuiRuntime.renderDamageTracker`). The loop drains its per-frame signals
  /// so they do not leak across frames; it no longer needs them to decide what
  /// to present, because the frame's damage is derived from the buffers.
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
    // No damage tracking is armed on the frame buffer: nothing reads it. That
    // leaves _recordDamageRect inert for every write this frame, so paint stops
    // paying for bookkeeping the presenter no longer consumes. A repaint
    // boundary still arms tracking on its OWN cache, where the question really
    // is "what did I paint" rather than "what must be presented".
    next.clear();
    bufferPrepareStopwatch.stop();

    paint(next);

    _renderDamage?.takeVisualChange();
    _renderDamage?.takeRequiresFullDiff();
    // Damage is DERIVED, not reported: comparing the two buffers is ground
    // truth, so nothing upstream can under-report by failing to declare what it
    // touched — and no conservative fallback is needed for when it does.
    final diff = next.diffAgainst(previous);
    // Scroll detection used to ride on "damage is unbounded", which every
    // relayout published. Exact damage is never unbounded, so the trigger has
    // to be explicit or the terminal's ESC[S path and the surface's row-shift
    // both go unreachable. Deciding it here also means the detector reuses the
    // counts the diff already produced instead of rescanning.
    // Detection is gated on at least a full row's worth of changed cells.
    // The most a scroll can ever save is rewriting [dirtyCells] cells, while
    // the detector is O(rows^2 x cols) worst case on repeated-row screens —
    // a uniform grid pattern with one blinking cell measured 18.8x the diff
    // cost ungated, and any genuine scroll dirties at least a row. (The serve
    // codec still runs its own detection against its OWN mirror: under
    // backpressure coalescing the wire's previous frame is not the loop's,
    // so this decision cannot be handed down; the duplication is confined to
    // genuine scroll frames, where one detector run is small next to encode.)
    final scrollUpRows =
        (_requireFullRepaint ||
            !diff.isComparable ||
            diff.dirtyCells < size.cols)
        ? null
        : detectBeneficialScrollUp(previous, next, diff.stats);
    final damage = TuiFrameDamage(
      fullRepaint: _requireFullRepaint || !diff.isComparable,
      dirtyBounds: diff.bounds,
      dirtyRows: diff.rows,
      scrollUpRows: scrollUpRows,
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

/// The exact set of cells that changed in one frame.
final class TuiFrameDamage {
  const TuiFrameDamage({
    required this.fullRepaint,
    required this.dirtyBounds,
    required this.dirtyRows,
    this.scrollUpRows,
  });

  /// Whether the presenter should treat this as a full repaint.
  ///
  /// Set when there is no comparable previous frame — a cold buffer pool or a
  /// resize — not as a fallback for damage the loop failed to compute.
  final bool fullRepaint;

  /// Bounding rect of every changed cell, or null when nothing changed.
  final CellRect? dirtyBounds;

  /// Exactly the rows containing a changed cell.
  ///
  /// Unlike [dirtyBounds] (a single union rect), scattered changes stay
  /// disjoint: five separated dirty rows are five rows here, not the tall rect
  /// spanning them. Required, so it can never disagree with [dirtyBounds] about
  /// how much changed.
  final Set<int> dirtyRows;

  /// When non-null, the frame is a beneficial upward scroll by this many rows:
  /// presenters may shift what they already hold and repaint only the residue.
  ///
  /// Computed once here, where both buffers are in hand and the diff has
  /// already counted the cells the detector needs.
  final int? scrollUpRows;

  /// Whether anything at all changed.
  bool get isEmpty => !fullRepaint && dirtyBounds == null;

  /// Bounds a diffing presenter may safely restrict itself to.
  ///
  /// Null on a full repaint (present everything) or when nothing changed;
  /// [fullRepaint] and [isEmpty] distinguish the two. Callers that treat null
  /// as "scan the whole screen" must check [isEmpty] first.
  CellRect? get diffBounds => fullRepaint ? null : dirtyBounds;

  /// The rows a row-oriented presenter must re-apply.
  TuiDirtyRows dirtyRowsFor(CellSize size) {
    if (fullRepaint) return TuiDirtyRows.full(size.rows);
    if (dirtyRows.isEmpty) return const TuiDirtyRows.none();
    return TuiDirtyRows.fromRows(dirtyRows, rowCount: size.rows);
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
