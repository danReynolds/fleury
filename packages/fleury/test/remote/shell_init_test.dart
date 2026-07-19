import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/shell_init.dart';
import 'package:fleury/src/terminal/capabilities.dart';
import 'package:test/test.dart';

void main() {
  test('shell INIT projects every negotiated terminal capability', () {
    const capabilities = TerminalCapabilities(
      colorMode: ColorMode.truecolor,
      glyphTier: GlyphTier.unicode,
      imageProtocol: ImageProtocol.kitty,
      tmuxPassthrough: true,
      hyperlinks: true,
    );

    final frame = buildShellInitFrame(
      size: const CellSize(132, 41),
      capabilities: capabilities,
    );

    expect(frame.size, const CellSize(132, 41));
    expect(frame.colorMode, capabilities.colorMode);
    expect(frame.glyphTier, capabilities.glyphTier);
    expect(frame.imageProtocol, capabilities.imageProtocol);
    expect(frame.tmuxPassthrough, isTrue);
    expect(frame.hyperlinks, isTrue);
    expect(frame.protocolVersion, remoteAnsiProtocolVersion);
  });
}
