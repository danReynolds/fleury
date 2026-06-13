import '../rendering/cell_buffer.dart';
import 'frame_presentation.dart';

/// A driver that wants structured frames instead of ANSI bytes.
///
/// When [runTui]'s resolved driver implements this and
/// [wantsPresentationPlans] is true, the render loop hands it each frame's
/// buffers (and the computed plan) here instead of diffing to ANSI — the
/// path that lets a served session render through the fleury web surface
/// rather than a terminal emulator. The driver builds the compact wire
/// frame (changed cells only) from [prev]/[next]. A driver that returns
/// false (or doesn't implement this) gets the ordinary ANSI byte path,
/// byte-for-byte unchanged.
abstract interface class RemoteSurfaceSink {
  /// Whether this driver should receive frames rather than ANSI this
  /// session. Typically gated on the negotiated remote protocol version.
  bool get wantsPresentationPlans;

  /// Presents one rendered frame. Called on the visual frame, in place of
  /// the ANSI diff write. [prev]/[next] are the committed and new buffers;
  /// [plan] carries the damage classification (full-repaint, scroll).
  void presentFrame(CellBuffer prev, CellBuffer next, FramePresentationPlan plan);

  /// Sends the semantic snapshot ([json] = UTF-8 of the
  /// `SemanticInspectionSnapshot` JSON) for the current frame, so a served
  /// session stays agent-drivable and accessible. Called only when the
  /// semantic tree changed.
  void presentSemantics(List<int> json);
}
