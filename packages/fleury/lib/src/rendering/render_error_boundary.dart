// Per-boundary error containment for the layout/paint phases.
//
// Build errors were always contained per-element (ErrorWidget); this
// gives layout and paint the same property. A RenderErrorBoundary absorbs
// exceptions thrown by its subtree's layout or paint and substitutes the
// cell-space error presentation, so a data-dependent constraint violation
// in one panel degrades to a red panel instead of killing the session.
// The framework installs implicit boundaries at Navigator route roots and
// OverlayEntry roots; apps add explicit ErrorBoundary widgets for finer
// grain; the frame driver's root backstop is the outermost edge.
//
// The invariants this leans on (verified against the pipeline, pinned by
// error_containment_test):
//   - The throw path stays layout-dirty by construction (`layout()` only
//     clears `_needsLayout` after `performLayout` succeeds), so a retry
//     after new subtree dirt genuinely re-runs the failing node — no
//     force-dirtying needed.
//   - The frame buffer is cleared each frame and the presentation writes
//     every cell of the boundary's rect, so paint atomicity and
//     write-recorded damage need no special-casing.
//   - Pointer regions register during paint; an errored subtree doesn't
//     paint, so its interactive regions vanish — fail-closed hit-testing.
//   - While errored with no new dirt, the boundary's own layout memoizes:
//     retained error state costs nothing per frame beyond repainting the
//     fill.

import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'error_presentation.dart';
import 'layout.dart';
import 'render_object.dart';

/// Which phase the contained exception escaped from.
enum FrameContainmentPhase { layout, paint }

/// A contained layout/paint failure: the error, where it escaped, and the
/// screen region the error presentation occupies.
final class FrameContainmentError {
  const FrameContainmentError({
    required this.error,
    required this.stack,
    required this.phase,
    this.paintedRegion,
  });

  final Object error;
  final StackTrace stack;
  final FrameContainmentPhase phase;

  /// Where the presentation painted, in screen cells — the semantic
  /// `errorBoundary` node's bounds. Null before the first errored paint.
  final CellRect? paintedRegion;

  FrameContainmentError _withRegion(CellRect region) => FrameContainmentError(
    error: error,
    stack: stack,
    phase: phase,
    paintedRegion: region,
  );
}

/// Implemented by render objects that absorb subtree layout/paint
/// exceptions. The semantics walk consults it to project a single
/// `errorBoundary` node (and drop the invisible descendants).
abstract interface class RenderErrorContainment {
  /// The currently contained failure, or null when the subtree is healthy.
  FrameContainmentError? get containedError;
}

/// The containment render object. See the library comment for the model.
class RenderErrorBoundary extends RenderObject
    implements RenderObjectWithSingleChild, RenderErrorContainment {
  RenderObject? _child;

  /// When true, contained exceptions are rethrown instead of absorbed —
  /// the test harness's default, so a widget test with a layout bug fails
  /// the test instead of silently rendering a red panel.
  bool rethrowContained = false;

  /// Reports each newly contained failure exactly once (per error-state
  /// entry), so a persistently failing subtree doesn't spam the log every
  /// frame. Hosts wire this to their error reporter.
  void Function(FrameContainmentError error)? onContained;

  FrameContainmentError? _containedError;
  CellSize? _lastGoodSize;

  @override
  FrameContainmentError? get containedError => _containedError;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    final old = _child;
    if (old != null) dropChild(old);
    _child = value;
    // A new subtree is a fresh start: clear any retained error so the
    // next layout attempts it.
    _containedError = null;
    if (value != null) adoptChild(value);
  }

  /// The size the parent sees while the subtree is errored, in priority
  /// order: the last successfully laid-out size re-constrained (minimal
  /// layout shift), else the full allocated slot when bounded, else a
  /// minimal 3×1 badge — an errored child inside a scrollable must not
  /// claim unbounded extent, but must stay visible.
  CellSize _erroredSize(CellConstraints constraints) {
    final lastGood = _lastGoodSize;
    if (lastGood != null) return constraints.constrain(lastGood);
    if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
      // Claim the allocated slot; the parent budgeted it anyway.
      return CellSize(constraints.maxCols!, constraints.maxRows!);
    }
    return constraints.constrain(const CellSize(3, 1));
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) {
      _containedError = null;
      return constraints.constrain(const CellSize(0, 0));
    }
    try {
      final laidOut = constraints.constrain(c.layout(constraints));
      _recover();
      _lastGoodSize = laidOut;
      return laidOut;
    } catch (error, stack) {
      if (rethrowContained) rethrow;
      _contain(error, stack, FrameContainmentPhase.layout);
      return _erroredSize(constraints);
    }
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final contained = _containedError;
    if (contained != null) {
      // Layout already failed: never paint (or hit-test-register) the
      // inconsistent subtree; present the failure instead.
      _paintPresentation(buffer, offset, contained, screenOffset, clipRect);
      return;
    }
    final c = _child;
    if (c == null) return;
    try {
      c.paint(buffer, offset, screenOffset: screenOffset, clipRect: clipRect);
    } catch (error, stack) {
      if (rethrowContained) rethrow;
      _contain(error, stack, FrameContainmentPhase.paint);
      // Atomicity: overwrite the whole rect, burying any partial child
      // writes from the throw.
      _paintPresentation(
        buffer,
        offset,
        _containedError!,
        screenOffset,
        clipRect,
      );
    }
  }

  void _paintPresentation(
    CellBuffer buffer,
    CellOffset offset,
    FrameContainmentError contained,
    CellOffset? screenOffset,
    CellRect? clipRect,
  ) {
    paintCellErrorPresentation(
      buffer,
      offset,
      size,
      contained.error,
      clipRect: clipRect,
    );
    _containedError = contained._withRegion(
      CellRect(offset: screenOffset ?? offset, size: size),
    );
  }

  void _contain(Object error, StackTrace stack, FrameContainmentPhase phase) {
    final alreadyErrored = _containedError != null;
    _containedError = FrameContainmentError(
      error: error,
      stack: stack,
      phase: phase,
    );
    // The dropped subtree is a structural semantics change (descendants
    // vanish from the projected tree); leaf replacement can't express it.
    markSemanticsStructureDirty();
    if (!alreadyErrored) onContained?.call(_containedError!);
  }

  void _recover() {
    if (_containedError == null) return;
    _containedError = null;
    markSemanticsStructureDirty();
  }

  /// Escalates the semantic dirty tracker to a full rebuild; overridden
  /// hook so the widget layer can wire the per-runtime tracker without a
  /// rendering→semantics dependency.
  void Function()? onSemanticsStructureChanged;

  void markSemanticsStructureDirty() => onSemanticsStructureChanged?.call();
}
