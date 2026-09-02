import '../foundation/geometry.dart';
import '../input/keyboard_state.dart';
import '../rendering/surface_capabilities.dart';
import '../terminal/capabilities.dart';
import 'remote_protocol.dart';

/// The INIT `fleury serve` sends an app the moment it connects in bridge
/// mode — before any browser exists.
///
/// It is [InitFrame.provisional]: a greeting, not a handshake. The app learns
/// that a supervisor owns the socket and waits for the browser's own INIT
/// without its silent-peer fuse firing; the size and capabilities here are
/// placeholders the driver never adopts (they restate the bundled client
/// for readability).
///
/// [debugWire] carries the operator's `--debug` decision: bridge mode cannot
/// set the app's environment, so this frame is how the supervisor owns that
/// default.
InitFrame buildServeProvisionalInitFrame({required bool debugWire}) {
  return InitFrame(
    size: const CellSize(80, 24),
    colorMode: ColorMode.truecolor,
    imageProtocol: ImageProtocol.halfBlock,
    tmuxPassthrough: false,
    images: InlineImageSupport.placements,
    hyperlinks: true,
    keyboard: KeyboardCapabilities.full,
    protocolVersion: remoteProtocolVersion,
    provisional: true,
    debugWire: debugWire,
  );
}
