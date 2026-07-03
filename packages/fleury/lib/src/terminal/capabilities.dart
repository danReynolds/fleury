import 'package:meta/meta.dart';

import '../rendering/surface_capabilities.dart';

export '../rendering/surface_capabilities.dart' show ColorMode, GlyphTier;

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

/// How the terminal renders East-Asian *Ambiguous*-width glyphs — the box
/// drawing, block elements, bullets, and arrows Fleury draws widgets with
/// (`─ │ █ ▁ • →`, all UAX #11 "Ambiguous"). Some terminals/fonts render them
/// one column wide, others two, and there is no universal default.
///
/// Fleury lays them out as one column. When a terminal renders them two columns
/// wide, its cursor advances further than Fleury's model and rows desync (the
/// "Warp garble"). Detected by an opt-in startup Cursor-Position probe
/// ([probeAmbiguousWidth]); [wide] is the safe default when unknown, so the
/// renderer defensively pins each ambiguous cell with an absolute reposition —
/// correct on any terminal, at a per-cell cursor-byte cost. A confirmed [narrow]
/// lets the renderer emit compact contiguous runs instead.
enum AmbiguousCharWidth { narrow, wide }

/// Static snapshot of what the terminal supports.
@immutable
final class TerminalCapabilities {
  const TerminalCapabilities({
    this.colorMode = ColorMode.ansi16,
    this.glyphTier = GlyphTier.unicode,
    this.imageProtocol = ImageProtocol.halfBlock,
    this.supportsAlternateScreen = true,
    this.supportsHidingCursor = true,
    this.tmuxPassthrough = false,
    this.ambiguousCharWidth = AmbiguousCharWidth.wide,
  });

  /// Conservative default for unknown terminals: 16-color ANSI, alt
  /// screen and cursor hiding assumed to work, half-block image
  /// rendering only.
  static const TerminalCapabilities defaultCapabilities =
      TerminalCapabilities();

  final ColorMode colorMode;

  /// Whether Unicode drawing glyphs are safe, or output must stay 7-bit ASCII.
  final GlyphTier glyphTier;
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

  /// How the terminal sizes ambiguous-width glyphs. Defaults to the safe
  /// [AmbiguousCharWidth.wide] until a startup probe confirms otherwise.
  final AmbiguousCharWidth ambiguousCharWidth;

  TerminalCapabilities copyWith({
    ColorMode? colorMode,
    GlyphTier? glyphTier,
    ImageProtocol? imageProtocol,
    bool? supportsAlternateScreen,
    bool? supportsHidingCursor,
    bool? tmuxPassthrough,
    AmbiguousCharWidth? ambiguousCharWidth,
  }) => TerminalCapabilities(
    colorMode: colorMode ?? this.colorMode,
    glyphTier: glyphTier ?? this.glyphTier,
    imageProtocol: imageProtocol ?? this.imageProtocol,
    supportsAlternateScreen:
        supportsAlternateScreen ?? this.supportsAlternateScreen,
    supportsHidingCursor: supportsHidingCursor ?? this.supportsHidingCursor,
    tmuxPassthrough: tmuxPassthrough ?? this.tmuxPassthrough,
    ambiguousCharWidth: ambiguousCharWidth ?? this.ambiguousCharWidth,
  );

  @override
  String toString() {
    return 'TerminalCapabilities(colorMode=$colorMode, '
        'glyphTier=$glyphTier, '
        'imageProtocol=$imageProtocol, '
        'altScreen=$supportsAlternateScreen, '
        'hideCursor=$supportsHidingCursor, '
        'tmuxPassthrough=$tmuxPassthrough, '
        'ambiguousCharWidth=${ambiguousCharWidth.name})';
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
    glyphTier: detectGlyphTierFromEnvironment(environment),
    imageProtocol: detectImageProtocolFromEnvironment(environment),
    tmuxPassthrough: detectTerminalMultiplexerFromEnvironment(environment),
  );
}

/// Detects whether Unicode drawing glyphs are safe to use, or output should
/// stay 7-bit ASCII.
///
/// Order: an explicit `FLEURY_GLYPH_TIER=ascii|unicode` (or the boolean
/// `FLEURY_ASCII`) wins; then `TERM=dumb`/`linux`; then a `C`/`POSIX` or
/// non-UTF-8 locale (`LC_ALL` > `LC_CTYPE` > `LANG`). Defaults to Unicode.
GlyphTier detectGlyphTierFromEnvironment(Map<String, String> environment) {
  final override = environment['FLEURY_GLYPH_TIER']?.toLowerCase().trim();
  if (override == 'ascii') return GlyphTier.ascii;
  if (override == 'unicode') return GlyphTier.unicode;

  final asciiOverride = environment['FLEURY_ASCII']?.toLowerCase().trim();
  if (asciiOverride == '1' ||
      asciiOverride == 'true' ||
      asciiOverride == 'yes' ||
      asciiOverride == 'on') {
    return GlyphTier.ascii;
  }

  final term = environment['TERM']?.toLowerCase().trim() ?? '';
  if (term == 'dumb' || term == 'linux') return GlyphTier.ascii;

  for (final name in const ['LC_ALL', 'LC_CTYPE', 'LANG']) {
    final locale = environment[name]?.trim();
    if (locale == null || locale.isEmpty) continue;
    final normalized = locale.toUpperCase().replaceAll('-', '');
    if (normalized == 'C' || normalized == 'POSIX') return GlyphTier.ascii;
    return normalized.contains('UTF8') ? GlyphTier.unicode : GlyphTier.ascii;
  }

  return GlyphTier.unicode;
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

/// Projects the terminal's capability snapshot into the backend-neutral
/// [SurfaceCapabilities] widgets read through MediaQuery. The terminal is
/// one projection; browser hosts construct theirs first-class. Escape
/// protocols and tmux passthrough deliberately do not survive projection —
/// they are presenter concerns.
extension TerminalSurfaceCapabilities on TerminalCapabilities {
  SurfaceCapabilities toSurfaceCapabilities() {
    return SurfaceCapabilities(
      colorMode: colorMode,
      glyphTier: glyphTier,
      images: imageProtocol == ImageProtocol.halfBlock
          ? InlineImageSupport.none
          : InlineImageSupport.placements,
      hyperlinks: false,
      pointer: PointerPrecision.cell,
    );
  }
}
