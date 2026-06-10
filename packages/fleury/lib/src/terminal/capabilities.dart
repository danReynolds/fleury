import 'package:meta/meta.dart';

/// Maximum color fidelity the terminal can render.
///
/// Detected at startup by the driver from `$COLORTERM`, `$TERM`, and
/// (eventually) terminal capability queries. The renderer downsamples
/// styled cells to whatever the driver reports here. P0 detects only
/// the boundaries clearly indicated by env vars; richer probing lands
/// with the P1 capabilities work.
enum ColorMode { none, ansi16, indexed256, truecolor }

/// Image-rendering protocol the terminal supports. Decided at startup
/// from env vars (`KITTY_WINDOW_ID`, `TERM_PROGRAM`, `TERM`); runtime
/// DA1 probes for Sixel are a later refinement.
///
/// Ordered roughly by fidelity — higher values supersede lower. The
/// `Image` widget renders via the highest-supported protocol.
enum ImageProtocol {
  /// No native image protocol. Render via ANSI half-block art.
  halfBlock,

  /// DEC Sixel — older, broadly supported by xterm, foot, mlterm,
  /// Windows Terminal (1.22+), mintty.
  sixel,

  /// iTerm2 inline-image protocol — OSC 1337 with base64 PNG payload.
  /// Supported by iTerm2, WezTerm, mintty, and a growing set of
  /// terminals that adopted the de-facto standard.
  iterm2,

  /// Kitty graphics protocol — modern, supported by Kitty, Ghostty,
  /// WezTerm, Konsole 22.04+.
  kitty,
}

/// Static snapshot of what the terminal supports.
@immutable
final class TerminalCapabilities {
  const TerminalCapabilities({
    this.colorMode = ColorMode.ansi16,
    this.imageProtocol = ImageProtocol.halfBlock,
    this.supportsAlternateScreen = true,
    this.supportsHidingCursor = true,
    this.tmuxPassthrough = false,
  });

  /// Conservative default for unknown terminals: 16-color ANSI, alt
  /// screen and cursor hiding assumed to work, half-block image
  /// rendering only.
  static const TerminalCapabilities defaultCapabilities =
      TerminalCapabilities();

  final ColorMode colorMode;
  final ImageProtocol imageProtocol;
  final bool supportsAlternateScreen;
  final bool supportsHidingCursor;

  /// True when we're running inside tmux (`$TMUX` is set). Image
  /// protocols (Kitty / Sixel / iTerm2) emit DCS / APC sequences that
  /// tmux drops by default; wrappers re-emit them through tmux's own
  /// passthrough envelope (`ESC P tmux ; <doubled-ESC payload> ESC \\`).
  /// tmux 3.3+ users can also opt out by setting
  /// `allow-passthrough on` directly.
  final bool tmuxPassthrough;

  @override
  String toString() {
    return 'TerminalCapabilities(colorMode=$colorMode, '
        'imageProtocol=$imageProtocol, '
        'altScreen=$supportsAlternateScreen, '
        'hideCursor=$supportsHidingCursor, '
        'tmuxPassthrough=$tmuxPassthrough)';
  }
}

/// Detects the terminal capability summary from environment variables.
///
/// This is intentionally static/env-derived for Phase 1. Active terminal
/// probing belongs behind an explicit diagnostics/probe step because some
/// probes write escape sequences, can be slow, and behave differently under
/// tmux, SSH, or IDE consoles.
TerminalCapabilities detectTerminalCapabilitiesFromEnvironment(
  Map<String, String> environment,
) {
  return TerminalCapabilities(
    colorMode: detectColorModeFromEnvironment(environment),
    imageProtocol: detectImageProtocolFromEnvironment(environment),
    tmuxPassthrough: detectTerminalMultiplexerFromEnvironment(environment),
  );
}

/// Detects maximum color fidelity from conventional terminal environment.
ColorMode detectColorModeFromEnvironment(Map<String, String> environment) {
  // NO_COLOR wins outright (https://no-color.org): any non-empty value
  // disables color, even over CLICOLOR_FORCE.
  if ((environment['NO_COLOR'] ?? '').isNotEmpty) return ColorMode.none;

  final colorterm = environment['COLORTERM']?.toLowerCase() ?? '';
  final term = environment['TERM']?.toLowerCase() ?? '';
  if (colorterm.contains('truecolor') || colorterm.contains('24bit')) {
    return ColorMode.truecolor;
  }
  if (term.contains('256')) return ColorMode.indexed256;
  if (term.isNotEmpty) return ColorMode.ansi16;
  if ((environment['CLICOLOR_FORCE'] ?? '0') != '0') {
    // No TERM, but the caller insists on color.
    return ColorMode.ansi16;
  }
  return ColorMode.none;
}

/// Detects the best known image protocol from terminal environment.
ImageProtocol detectImageProtocolFromEnvironment(
  Map<String, String> environment,
) {
  final term = environment['TERM']?.toLowerCase() ?? '';
  final program = environment['TERM_PROGRAM']?.toLowerCase() ?? '';
  final lcTerminal = environment['LC_TERMINAL']?.toLowerCase() ?? '';

  if (environment['KITTY_WINDOW_ID']?.isNotEmpty ?? false) {
    return ImageProtocol.kitty;
  }
  if (term == 'xterm-kitty') return ImageProtocol.kitty;
  if (program == 'wezterm' || program == 'ghostty') {
    return ImageProtocol.kitty;
  }
  if (program == 'iterm.app' || lcTerminal == 'iterm2' || program == 'mintty') {
    return ImageProtocol.iterm2;
  }
  if (term.contains('sixel')) return ImageProtocol.sixel;
  return ImageProtocol.halfBlock;
}

/// Detects whether a terminal multiplexer is likely to need passthrough.
bool detectTerminalMultiplexerFromEnvironment(Map<String, String> environment) {
  if ((environment['TMUX'] ?? '').isNotEmpty) return true;
  final term = environment['TERM']?.toLowerCase() ?? '';
  if (term.startsWith('screen') || term.startsWith('tmux')) return true;
  return false;
}
