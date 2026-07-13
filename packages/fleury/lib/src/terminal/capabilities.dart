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
    this.hyperlinks = false,
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

  /// Whether OSC 8 hyperlinks are supported and safe to emit here. Detected
  /// from the environment and SUPPRESSED under tmux (see
  /// [detectHyperlinksFromEnvironment]); default false for unknown terminals.
  /// Projected into [SurfaceCapabilities.hyperlinks] and gates the ANSI
  /// renderer's OSC 8 emission.
  final bool hyperlinks;

  TerminalCapabilities copyWith({
    ColorMode? colorMode,
    GlyphTier? glyphTier,
    ImageProtocol? imageProtocol,
    bool? supportsAlternateScreen,
    bool? supportsHidingCursor,
    bool? tmuxPassthrough,
    AmbiguousCharWidth? ambiguousCharWidth,
    bool? hyperlinks,
  }) => TerminalCapabilities(
    colorMode: colorMode ?? this.colorMode,
    glyphTier: glyphTier ?? this.glyphTier,
    imageProtocol: imageProtocol ?? this.imageProtocol,
    supportsAlternateScreen:
        supportsAlternateScreen ?? this.supportsAlternateScreen,
    supportsHidingCursor: supportsHidingCursor ?? this.supportsHidingCursor,
    tmuxPassthrough: tmuxPassthrough ?? this.tmuxPassthrough,
    ambiguousCharWidth: ambiguousCharWidth ?? this.ambiguousCharWidth,
    hyperlinks: hyperlinks ?? this.hyperlinks,
  );

  @override
  String toString() {
    return 'TerminalCapabilities(colorMode=$colorMode, '
        'glyphTier=$glyphTier, '
        'imageProtocol=$imageProtocol, '
        'altScreen=$supportsAlternateScreen, '
        'hideCursor=$supportsHidingCursor, '
        'tmuxPassthrough=$tmuxPassthrough, '
        'ambiguousCharWidth=${ambiguousCharWidth.name}, '
        'hyperlinks=$hyperlinks)';
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
    ambiguousCharWidth:
        detectAmbiguousCharWidthFromEnvironment(environment) ??
        AmbiguousCharWidth.wide,
    hyperlinks: detectHyperlinksFromEnvironment(environment),
  );
}

/// Detects whether OSC 8 hyperlinks are supported and safe to emit here.
///
/// Order:
///   1. An explicit `FLEURY_HYPERLINKS=1` (or `true`/`yes`/`on`) forces links
///      ON — even under tmux — and `0` (or `false`/`no`/`off`) forces them OFF.
///      The override wins outright.
///   2. Otherwise SUPPRESS under any detected multiplexer (tmux/screen),
///      REGARDLESS of the outer terminal: OSC 8 in tmux needs an explicit
///      `terminal-features` opt-in and is unreliable in the wild, so
///      default-deny is safer than emitting links a passthrough may mangle.
///   3. Otherwise enable for a known-supporting outer terminal:
///      `TERM_PROGRAM` ∈ {iterm.app, wezterm, ghostty}, a present `VTE_VERSION`
///      (GNOME/VTE terminals), Kitty (`KITTY_WINDOW_ID` or `TERM=xterm-kitty`),
///      or Windows Terminal (`WT_SESSION`).
///   4. Default false when unknown.
///
/// Centralized here (like [detectGlyphTierFromEnvironment]) so every driver
/// honors the same allow-list and the same tmux suppression. Passive/env-only
/// for now; an active probe is a later refinement (RFC 0017, Stage 3).
bool detectHyperlinksFromEnvironment(Map<String, String> environment) {
  final override = environment['FLEURY_HYPERLINKS']?.toLowerCase().trim();
  if (override == '1' ||
      override == 'true' ||
      override == 'yes' ||
      override == 'on') {
    return true; // explicit force-on wins, even under tmux
  }
  if (override == '0' ||
      override == 'false' ||
      override == 'no' ||
      override == 'off') {
    return false;
  }

  // Suppress under a multiplexer regardless of the outer terminal.
  if (detectTerminalMultiplexerFromEnvironment(environment)) return false;

  final program = environment['TERM_PROGRAM']?.toLowerCase().trim() ?? '';
  if (program == 'iterm.app' || program == 'wezterm' || program == 'ghostty') {
    return true;
  }
  if ((environment['VTE_VERSION'] ?? '').trim().isNotEmpty) return true;
  if ((environment['KITTY_WINDOW_ID'] ?? '').trim().isNotEmpty) return true;
  if ((environment['TERM']?.toLowerCase().trim() ?? '') == 'xterm-kitty') {
    return true;
  }
  if ((environment['WT_SESSION'] ?? '').trim().isNotEmpty) return true;
  return false;
}

/// Reads an explicit ambiguous-width override from the environment:
/// `FLEURY_AMBIGUOUS_WIDTH=narrow|wide`. Returns null when unset, so the caller
/// keeps the safe `wide` default until a startup probe measures the terminal.
///
/// Centralized here (like [detectGlyphTierFromEnvironment]) so every driver —
/// not just the POSIX one that runs the probe — honors the override. The
/// `0`/`off`/`false` value is deliberately NOT handled here: that disables the
/// probe (a driver concern), and leaving it null keeps the `wide` default.
AmbiguousCharWidth? detectAmbiguousCharWidthFromEnvironment(
  Map<String, String> environment,
) {
  final value = environment['FLEURY_AMBIGUOUS_WIDTH']?.toLowerCase().trim();
  return switch (value) {
    'narrow' => AmbiguousCharWidth.narrow,
    'wide' => AmbiguousCharWidth.wide,
    _ => null,
  };
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
      hyperlinks: hyperlinks,
      pointer: PointerPrecision.cell,
    );
  }
}
