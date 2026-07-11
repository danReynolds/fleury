import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../remote/remote_protocol.dart' show RemoteClipboardStatus;
import '../remote/remote_semantics.dart' show SemanticWireDelta;
import '../rendering/cell_buffer.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import 'frame_presentation.dart';

/// Handles an inbound semantic-action request from the peer (the browser or an
/// agent activating a node in its accessible DOM). [value] is the optional
/// payload carried by [SemanticAction.setValue]; null for every other action.
typedef RemoteSemanticActionHandler =
    void Function(SemanticNodeId id, SemanticAction action, Object? value);

/// Handles an inbound debug query from the peer (an agent bridge or a future
/// browser DevTools panel asking for recent frame stats / error records).
/// Implementations answer via [RemoteSurfaceSink.presentDebugResponse] with
/// the same [seq].
typedef RemoteDebugRequestHandler =
    void Function(int seq, String kind, int limit);

/// A driver that wants structured frames instead of ANSI bytes.
///
/// When [runApp]'s resolved driver implements this and
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
  void presentFrame(
    CellBuffer prev,
    CellBuffer next,
    FramePresentationPlan plan,
  );

  /// Presents the current frame's semantic [snapshot], so a served session
  /// stays agent-drivable and accessible. The sink diffs it against the last
  /// sent snapshot and ships only what changed — a full frame once per peer,
  /// patches after — because a full resend stops compressing past DEFLATE's
  /// 32 KiB window. Called when the semantic tree changed. [delta] optionally
  /// names the nodes whose wire form may have changed (from `SemanticsOwner`'s
  /// per-frame diff), letting the encoder re-serialize only those; a null delta
  /// falls back to a full flatten + structural compare.
  void presentSemantics(
    SemanticInspectionSnapshot snapshot, {
    SemanticWireDelta? delta,
  });

  /// Ships the focused editable's caret rect (or its absence) so the peer
  /// can position its hidden IME capture element at the caret. Callers
  /// dedupe; implementations just transmit.
  void presentCaret(CellRect? caret);

  /// Asks the peer to place [text] on the PEER's clipboard, tagged with
  /// [seq] so the answer can be matched.
  void sendClipboardWrite(int seq, String text);

  /// Registers the handler for the peer's clipboard-write answers. Set to
  /// null to clear.
  set onClipboardResult(
    void Function(int seq, RemoteClipboardStatus status)? handler,
  );

  /// Reports the invocation status for a peer's semantic-action request back
  /// to the peer, so an agent or AT mirror can distinguish "handler ran",
  /// "disabled", "not found", "unsupported", and "handler threw" instead of
  /// inferring success from tree diffs.
  void presentSemanticActionResult(
    SemanticNodeId id,
    SemanticAction action,
    SemanticActionInvocationStatus status,
  );

  /// Registers a handler for inbound semantic-action requests from the peer —
  /// the browser activating a node in its accessible DOM (a screen reader or
  /// agent driving the a11y tree, not the visual grid). The host invokes the
  /// action against the live tree. Set to null to clear. Completes the round
  /// trip that [presentSemantics] starts.
  set onSemanticAction(RemoteSemanticActionHandler? handler);

  /// Registers a handler for the peer's pull-style debug queries ("send me
  /// your recent frame stats / errors"). `runApp` wires this to its debug
  /// providers when debug tooling is enabled; null (the default) leaves
  /// requests unanswered and the peer's timeout reports the app as not
  /// debuggable.
  set onDebugRequest(RemoteDebugRequestHandler? handler);

  /// Answers a debug query: [seq] echoes the request, [kind] names the
  /// record type, [json] is the UTF-8 JSON document of records.
  void presentDebugResponse(int seq, String kind, Uint8List json);
}
