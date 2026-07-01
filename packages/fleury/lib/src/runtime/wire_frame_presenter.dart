// WireFramePresenter: the structured serve write phase — hands each
// rendered frame's buffers and damage plan to the RemoteSurfaceSink,
// which encodes only the changed cells for the peer's mirror.

import '../debug/debug_invalidation.dart';
import 'frame_driver.dart';
import 'remote_surface_sink.dart';
import 'tui_frame_loop.dart';

/// Presents rendered frames as wire plans through a [RemoteSurfaceSink].
final class WireFramePresenter implements FramePresenter {
  WireFramePresenter(this._sink);

  final RemoteSurfaceSink _sink;

  @override
  bool get wantsPresentationPlan => true;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    _sink.presentFrame(frame.previous, frame.next, info.plan!);
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {
    DebugInvalidations.reset();
  }
}
