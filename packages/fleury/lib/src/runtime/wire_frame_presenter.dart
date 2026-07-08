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
    final plan = info.plan;
    final bounds = plan?.damage.dirtyBounds;
    DebugEvents.emitFrame(
      FrameEvent(
        frameNumber: _frameCounter,
        reason: info.reason,
        build: info.phaseBuild,
        layout: info.phaseLayout,
        paint: info.phasePaint,
        // On the wire the "diff" phase is building the change plan: the row
        // diff plus span construction.
        diff:
            (plan?.dirtyRowDiffTime ?? Duration.zero) +
            (plan?.spanBuildTime ?? Duration.zero),
        // The wire path works in rows/spans, not a per-cell tally, so this is
        // the dirty bounding-box area rather than an exact changed-cell count.
        dirtyCells: bounds == null
            ? frame.next.size.cols * frame.next.size.rows
            : bounds.size.cols * bounds.size.rows,
        dirtyBounds: bounds,
        dirtySources: DebugInvalidations.drain(),
        layoutStats: info.layoutStats,
        repaintBoundaries: info.repaintBoundaryStats,
        bufferSize: frame.next.size,
      ),
    );
  }
}
