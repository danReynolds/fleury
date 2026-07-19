import '../foundation/geometry.dart';
import '../terminal/capabilities.dart';
import 'remote_protocol.dart';

/// Projects the local terminal into the INIT frame sent by `fleury shell`.
///
/// Keeping this projection together prevents newly negotiated capabilities
/// from working in the native driver but silently disappearing through the
/// shell proxy.
InitFrame buildShellInitFrame({
  required CellSize size,
  required TerminalCapabilities capabilities,
}) {
  return InitFrame(
    size: size,
    colorMode: capabilities.colorMode,
    glyphTier: capabilities.glyphTier,
    imageProtocol: capabilities.imageProtocol,
    tmuxPassthrough: capabilities.tmuxPassthrough,
    hyperlinks: capabilities.hyperlinks,
    protocolVersion: remoteAnsiProtocolVersion,
  );
}
