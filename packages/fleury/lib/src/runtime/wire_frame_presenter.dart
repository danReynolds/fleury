// WireFramePresenter: the structured serve write phase — hands each
// rendered frame's buffers and damage plan to the RemoteSurfaceSink,
// which encodes only the changed cells for the peer's mirror.

import '../debug/debug_events.dart';
import '../debug/debug_invalidation.dart';
import '../foundation/geometry.dart';
import 'frame_driver.dart';
import 'remote_surface_sink.dart';
import 'tui_frame_loop.dart';

/// Presents rendered frames as wire plans through a [RemoteSurfaceSink].
final class WireFramePresenter implements FramePresenter {
  WireFramePresenter(this._sink, {CellRect? Function()? readCaret})
    : _readCaret = readCaret;

  final RemoteSurfaceSink _sink;
  final CellRect? Function()? _readCaret;
  CellRect? _lastCaret;
  var _sentCaret = false;
  int _frameCounter = 0;

  @override
  bool get wantsPresentationPlan => true;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    _sink.presentFrame(frame.previous, frame.next, info.plan!);
    final readCaret = _readCaret;
    if (readCaret != null) {
      // The peer positions its hidden IME element at the caret; ship the
      // rect only when it changes (or first becomes known).
      final caret = readCaret();
      if (!_sentCaret || caret != _lastCaret) {
        _sentCaret = true;
        _lastCaret = caret;
        _sink.presentCaret(caret);
      }
    }
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {
    if (!info.debugWatching) {
      DebugInvalidations.reset();
      return;
    }
    // A debug consumer is watching (the panel, or an agent pulling read_frames
    // over the wire): emit the same per-frame telemetry the ANSI presenter does
    // so the debug channel carries real frame stats over the serve / agent path
    // too — not just in a local terminal. Gated on debugWatching, so a release
    // serve (debug off) pays nothing.
    _frameCounter++;
    // The plan is always built for this presenter (wantsPresentationPlan).
    final plan = info.plan!;
    final bounds = plan.damage.dirtyBounds;
    // The wire path works in rows/spans, not a per-cell tally. Prefer the
    // dirty bounding box; when it's absent — the COMMON case, since any
    // markNeedsLayout publishes requiresFullDiff and nulls diffBounds — fall
    // back to the plan's own per-row diff (dirtyRowCount × width), not the
    // full viewport: the planner ran a real row diff for exactly these
    // frames, so a one-row change reports ~one row, not a full screen.
    final dirtyCells = bounds != null
        ? bounds.size.cols * bounds.size.rows
        : plan.damage.dirtyRows.dirtyRowCount * frame.next.size.cols;
    DebugEvents.emitFrame(
      FrameEvent(
        frameNumber: _frameCounter,
        reason: info.reason,
        build: info.phaseBuild,
        layout: info.phaseLayout,
        paint: info.phasePaint,
        // On the wire the "diff" phase is building the change plan: the row
        // diff plus span construction.
        diff: plan.dirtyRowDiffTime + plan.spanBuildTime,
        dirtyCells: dirtyCells,
        dirtyBounds: bounds,
        dirtySources: DebugInvalidations.drain(),
        layoutStats: info.layoutStats,
        repaintBoundaries: info.repaintBoundaryStats,
        bufferSize: frame.next.size,
      ),
    );
  }
}
