import 'frame_presentation.dart';

/// A driver that wants structured presentation plans instead of ANSI bytes.
///
/// When [runTui]'s resolved driver implements this and
/// [wantsPresentationPlans] is true, the render loop builds a
/// [FramePresentationPlan] per frame and hands it here instead of diffing
/// the cell buffer to ANSI — the path that lets a served session render
/// through the fleury web surface rather than a terminal emulator. A
/// driver that returns false (or doesn't implement this) gets the ordinary
/// ANSI byte path, byte-for-byte unchanged.
abstract interface class RemoteSurfaceSink {
  /// Whether this driver should receive plans rather than ANSI this session.
  /// Typically gated on the negotiated remote protocol version.
  bool get wantsPresentationPlans;

  /// Presents one frame's plan. Called on the visual frame, in place of the
  /// ANSI diff write.
  void presentPlan(FramePresentationPlan plan);
}
