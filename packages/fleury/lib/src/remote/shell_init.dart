import '../foundation/geometry.dart';
import '../input/keyboard_state.dart';
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
  KeyboardCapabilities? keyboard,
}) {
  return InitFrame(
    size: size,
    colorMode: capabilities.colorMode,
    glyphTier: capabilities.glyphTier,
    imageProtocol: capabilities.imageProtocol,
    tmuxPassthrough: capabilities.tmuxPassthrough,
    hyperlinks: capabilities.hyperlinks,
    // What the user's REAL terminal confirmed, probed by the shell before it
    // starts relaying bytes. Without this the app behind the relay sees a
    // press-only keyboard no matter what the emulator can do — the exact
    // silent-disappearance this file exists to prevent.
    keyboard: keyboard,
    protocolVersion: remoteAnsiProtocolVersion,
  );
}
