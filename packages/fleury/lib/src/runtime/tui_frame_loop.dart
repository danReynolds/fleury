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

  /// The region in which the retired buffer differs from the committed frame,
  /// or null when that is unknown (a full repaint, a resize, a dropped frame)
  /// and the whole grid has to be copied to carry forward.
  CellRect? _staleRegion;
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
  ///
  /// Only the flag is set here; the shown buffer is blanked by [render] when
  /// the mark is consumed. Blanking at mark time acts on whichever buffer is
  /// front *right now* — wrong whenever the mark lands between [render] and
  /// [commit], where the front buffer is the outgoing frame and the freshly
  /// painted one becomes front with its content intact. It also mutates a
  /// buffer other consumers alias (the semantics pipeline keeps a reference
  /// to the last presented buffer). Consume time has neither problem.
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
    bool paintsIncrementally = false,
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
    // Carrying the previous frame forward changes this loop's contract with its
    // painter. The default contract is "you are handed a cleared buffer; paint
    // everything you want shown", and it is what makes a vacated cell
    // observable: the cell held content, the clear emptied it, the diff sees a
    // change. A painter that opts in takes on the other half — it must erase
    // what it stops painting — and only the render tree can, because only it
    // knows which node vacated which rectangle. A raw callback cannot, so it
    // keeps the cleared buffer.
    // A forced full repaint means the buffers are new or the screen is about to
    // be wiped: there is no previous frame to carry, and a subtree whose
    // geometry happens to be unchanged would skip into an empty buffer. Take
    // the cleared path and let everything repaint.
    if (IncrementalPaint.enabled && paintsIncrementally) {
      IncrementalPaint.beginPass();
    }
    if (IncrementalPaint.enabled &&
        paintsIncrementally &&
        !_requireFullRepaint) {
      // Carry the previous frame forward rather than clearing. The buffer the
      // loop already keeps becomes a cache of the whole screen, so a subtree
      // whose cells are still valid where they sit needs no cache of its own
      // and no blit — it is simply not painted.
      // Copy only where the two buffers actually differ. [next] holds the
      // frame BEFORE last, and the only cells in which it differs from [previous]
      // are the ones last frame changed — which last frame's own diff already
      // bounded. Blitting the whole grid to carry it forward cost as much as
      // clearing it did, on every frame; this makes carrying proportional to
      // what moved, like everything else here.
      final stale = _staleRegion;
      if (stale == null) {
        next.copyFrom(previous, CellOffset.zero);
      } else if (!stale.size.isEmpty) {
        next.copyRectFrom(previous, stale, stale.offset);
      }
      next.carriesPreviousFrame = true;
      // Arm tracking for the paint walk: with the previous frame carried
      // forward, what each node WRITES is how the walk measures the cells it
      // owns — geometry cannot answer that for a node whose composite puts
      // cells somewhere other than where it sits. Reset after the copy so the
      // copy itself is not counted.
      next.resetDamageTracking();
    } else {
      next.clear();
      next.carriesPreviousFrame = false;
      next.resetDamageTracking();
    }
    // Until this frame is committed, [next] is not a reference for anything,
    // and a rendered-but-dropped frame would leave the OTHER buffer stale in a
    // region no diff described. Cleared here and set from this frame's own
    // diff at commit.
    _staleRegion = null;
    next.isFrameBuffer = true;
    previous.isFrameBuffer = true;
    // A forced full repaint means the presenter wipes the screen before
    // drawing, so `previous` must describe that wiped screen — otherwise the
    // diff skips every cell that "matches" content the wipe just destroyed,
    // and re-emits nothing. Blanked here, when the mark is consumed, because
    // this is the one point where `previous` is definitely the buffer the
    // wipe will invalidate and nothing else can observe the blank (render →
    // present → commit is synchronous).
    if (_requireFullRepaint) previous.clear();
    bufferPrepareStopwatch.stop();

    paint(next);

    _renderDamage?.takeVisualChange();
    _renderDamage?.takeRequiresFullDiff();
    // Damage is DERIVED, not reported: comparing the two buffers is ground
    // truth, so nothing upstream can under-report by failing to declare what it
    // touched — and no conservative fallback is needed for when it does.
    // A carried frame started as a copy of [previous], so the only cells that
    // can differ are the ones this frame wrote or erased — and the buffer
    // recorded exactly those. An empty window means nothing was written, which
    // is a real answer (the frame is unchanged), not "no window".
    final CellRect? scanWindow = next.carriesPreviousFrame
        ? (next.takeDamageBounds() ?? CellRect.fromLTWH(0, 0, 0, 0))
        : null;
    final diff = next.diffAgainst(previous, within: scanWindow);
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
    final bounds = diff.bounds;
    final TuiFrameDamage damage;
    if (_requireFullRepaint || !diff.isComparable) {
      damage = const FrameFullRepaint();
    } else if (bounds == null) {
      damage = const FrameUnchanged();
    } else {
      final scrollUpRows = diff.dirtyCells < size.cols
          ? null
          : detectBeneficialScrollUp(previous, next, diff.stats);
      damage = scrollUpRows == null
          ? FrameChanged(rows: diff.rows, bounds: bounds)
          : FrameScrolled(
              scrollUpRows: scrollUpRows,
              rows: diff.rows,
              bounds: bounds,
            );
    }
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
    // What the next frame has to copy to carry this one forward: the buffer it
    // will paint into is the one just retired, and it differs from this frame
    // exactly where this frame's diff said.
    // `diffBounds` is null both for "nothing changed" and for "everything may
    // have": the first needs no copy at all, the second needs the whole grid.
    final damage = frame.damage;
    _staleRegion = damage is FrameUnchanged
        ? CellRect.fromLTWH(0, 0, 0, 0)
        : damage.diffBounds;
    // Only now are the cells this pass painted the reference. A rendered but
    // uncommitted frame must not let the tree believe its output was kept.
    if (IncrementalPaint.enabled && frame.next.isFrameBuffer) {
      IncrementalPaint.commitPass();
    }
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

/// What a presenter must do to bring the screen up to date with a frame.
///
/// A sealed union rather than flags plus nullable fields, because the flag
/// shape kept expressing states it did not mean. `dirtyBounds == null` said
/// both "repaint everything" and "nothing changed" — opposite instructions
/// told apart only by a documented convention — and `scrollUpRows` was an
/// optional a consumer could ignore without noticing, which is precisely what
/// happened: the terminal presenter silently stopped scrolling and every test
/// still passed. Here the states are distinct types, so a presenter that
/// switches gets exhaustiveness from the compiler instead of from a convention.
///
/// Presenters needing only "which rows" can stay on [dirtyRowsFor] and
/// [diffBounds] without switching at all.
sealed class TuiFrameDamage {
  const TuiFrameDamage();

  /// The rows a row-oriented presenter must re-apply.
  TuiDirtyRows dirtyRowsFor(CellSize size);

  /// Bounds a diffing presenter may restrict itself to, or null when no bound
  /// is useful (everything, or nothing, changed — which variant says which).
  CellRect? get diffBounds;
}

/// No comparable previous frame — a cold buffer pool or a resize. Present
/// everything. Not a fallback for damage the loop failed to compute; the loop
/// always computes it.
final class FrameFullRepaint extends TuiFrameDamage {
  const FrameFullRepaint();

  @override
  TuiDirtyRows dirtyRowsFor(CellSize size) => TuiDirtyRows.full(size.rows);

  @override
  CellRect? get diffBounds => null;
}

/// The two frames render identically. Present nothing.
final class FrameUnchanged extends TuiFrameDamage {
  const FrameUnchanged();

  @override
  TuiDirtyRows dirtyRowsFor(CellSize size) => const TuiDirtyRows.none();

  @override
  CellRect? get diffBounds => null;
}

/// Cells changed; [rows] and [bounds] locate them exactly.
///
/// [rows] stays disjoint where [bounds] cannot: five separated dirty rows are
/// five rows here, not the tall rect spanning them.
final class FrameChanged extends TuiFrameDamage {
  const FrameChanged({required this.rows, required this.bounds});

  final Set<int> rows;
  final CellRect bounds;

  @override
  TuiDirtyRows dirtyRowsFor(CellSize size) =>
      TuiDirtyRows.fromRows(rows, rowCount: size.rows);

  @override
  CellRect? get diffBounds => bounds;
}

/// The frame is a beneficial upward scroll: shift what is already on screen up
/// by [scrollUpRows], then repaint the residue.
///
/// [rows] is NOT that residue — it is the TRUE dirty set, every row the shift
/// moves. Consumers that do not shift (the wire's dirty-row hint, semantic
/// coverage) need all of them, and a presenter that does shift derives the
/// smaller residual set itself, as `FramePresentationPlanner` does. Handing
/// the residue here instead would leave every moved row unaccounted for
/// everywhere else.
///
/// A distinct variant rather than a nullable field on [FrameChanged] so that a
/// presenter acting on scrolling cannot quietly omit the case — the omission is
/// a missing switch arm, not a passing test suite.
final class FrameScrolled extends TuiFrameDamage {
  const FrameScrolled({
    required this.scrollUpRows,
    required this.rows,
    required this.bounds,
  }) : assert(scrollUpRows > 0, 'a scroll by zero rows is not a scroll');

  final int scrollUpRows;
  final Set<int> rows;
  final CellRect bounds;

  @override
  TuiDirtyRows dirtyRowsFor(CellSize size) =>
      TuiDirtyRows.fromRows(rows, rowCount: size.rows);

  @override
  CellRect? get diffBounds => bounds;
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
