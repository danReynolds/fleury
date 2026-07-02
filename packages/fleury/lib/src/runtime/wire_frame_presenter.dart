// WireFramePresenter: the structured serve write phase — hands each
// rendered frame's buffers and damage plan to the RemoteSurfaceSink,
// which encodes only the changed cells for the peer's mirror.

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
    DebugInvalidations.reset();
  }
}
