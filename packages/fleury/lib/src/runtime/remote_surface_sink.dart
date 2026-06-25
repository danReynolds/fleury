import '../rendering/cell_buffer.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import 'frame_presentation.dart';

/// Handles an inbound semantic-action request from the peer (the browser or an
/// agent activating a node in its accessible DOM). [value] is the optional
/// payload carried by [SemanticAction.setValue]; null for every other action.
typedef RemoteSemanticActionHandler =
    void Function(SemanticNodeId id, SemanticAction action, Object? value);

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

  /// Presents the current frame's semantic [snapshot], so a served session
  /// stays agent-drivable and accessible. The sink diffs it against the last
  /// sent snapshot and ships only what changed — a full frame once per peer,
  /// patches after — because a full resend stops compressing past DEFLATE's
  /// 32 KiB window. Called when the semantic tree changed.
  void presentSemantics(SemanticInspectionSnapshot snapshot);

  /// Registers a handler for inbound semantic-action requests from the peer —
  /// the browser activating a node in its accessible DOM (a screen reader or
  /// agent driving the a11y tree, not the visual grid). The host invokes the
  /// action against the live tree. Set to null to clear. Completes the round
  /// trip that [presentSemantics] starts.
  set onSemanticAction(RemoteSemanticActionHandler? handler);
}
