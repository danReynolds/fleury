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
/// "Warp garble"). Detected by the internal opt-in startup Cursor-Position
/// probe (`probeAmbiguousWidth`); [wide] is the safe default when unknown, so the
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

  /// True when a driver reports that its output path can carry tmux
  /// passthrough envelopes.
  ///
  /// Passive environment detection does not enable passthrough. Built-in
  /// drivers use cell art under multiplexers because transport alone does not
  /// make host-side raster lifecycle safe across redraw, resize, detach, or
  /// pane transitions. Explicit custom drivers retain control of this value.
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
  final detectedImageProtocol = detectImageProtocolFromEnvironment(environment);
  return TerminalCapabilities(
    colorMode: detectColorModeFromEnvironment(environment),
    glyphTier: detectGlyphTierFromEnvironment(environment),
    imageProtocol: resolveImageProtocolForEnvironment(
      detectedImageProtocol,
      environment,
    ),
    tmuxPassthrough: false,
    ambiguousCharWidth:
        detectAmbiguousCharWidthFromEnvironment(environment) ??
        AmbiguousCharWidth.wide,
    hyperlinks: detectHyperlinksFromEnvironment(environment),
  );
}

/// Applies Fleury's multiplexer policy to a detected or actively probed image
/// protocol.
///
/// Kept separate from passive detection so a later active probe cannot bypass
/// the same policy when it upgrades an otherwise inconclusive environment.
/// This is internal implementation surface and is not exported by
/// `package:fleury/fleury.dart`.
ImageProtocol resolveImageProtocolForEnvironment(
  ImageProtocol detected,
  Map<String, String> environment,
) {
  return _effectiveImageProtocol(
    detected,
    multiplexer: detectTerminalMultiplexerFromEnvironment(environment),
  );
}

ImageProtocol _effectiveImageProtocol(
  ImageProtocol detected, {
  required bool multiplexer,
}) {
  if (!multiplexer) return detected;
  return ImageProtocol.halfBlock;
}

/// Why the terminal does or doesn't get OSC 8 hyperlinks — the reason behind
/// [TerminalCapabilities.hyperlinks], surfaced by `fleury diagnose`. Computed
/// from the FULL environment picture at detection time (see
/// [detectHyperlinkSupportFromEnvironment]); the plain bool can't reconstruct
/// these after the fact, which is why the reason must not be re-derived from a
/// lossy `(hyperlinks, tmuxPassthrough)` snapshot downstream.
enum HyperlinkSupport {
  /// Allow-listed (and version-checked) and actively emitting OSC 8. Also the
  /// state for an explicit `FLEURY_HYPERLINKS=1` force, even under a
  /// multiplexer.
  supported('supported'),

  /// The outer terminal WOULD support OSC 8, but a multiplexer suppresses it
  /// and no `FLEURY_HYPERLINKS=1` overrode that. Escaping tmux (or opting into
  /// its `terminal-features`) would enable links — actionable advice, so it is
  /// reported ONLY when the outer terminal is genuinely capable.
  suppressedUnderTmux('suppressed-under-tmux'),

  /// Explicitly disabled with `FLEURY_HYPERLINKS=0`, regardless of terminal.
  disabledByOverride('disabled-by-override'),

  /// Not a known-supporting terminal (whether or not under a multiplexer):
  /// escaping tmux would NOT help, so this must never be mislabeled as
  /// tmux-suppressed.
  unsupported('unsupported');

  const HyperlinkSupport(this.diagnoseLabel);

  /// Stable machine-readable string for `fleury diagnose --json`
  /// (`capabilities.osc8Hyperlinks`).
  final String diagnoseLabel;
}

/// Detects OSC 8 support AND the reason from the environment. See
/// [HyperlinkSupport] for the four outcomes.
///
/// Order:
///   1. `FLEURY_HYPERLINKS` override wins outright: on → [HyperlinkSupport.supported]
///      (even under a multiplexer); off → [HyperlinkSupport.disabledByOverride].
///   2. Otherwise classify the OUTER terminal against the allow-list, applying a
///      version threshold where the environment exposes one: `VTE_VERSION >=
///      5000` (OSC 8 landed in VTE 0.50; `VTE_VERSION` is `MMmmpp`, so 5000 =
///      0.50.0) and iTerm via `TERM_PROGRAM_VERSION >= 3.1` (OSC 8 shipped in
///      iTerm2 3.1). Terminals that expose no version stay presence-based:
///      Kitty (`KITTY_WINDOW_ID` / `TERM=xterm-kitty`), WezTerm and ghostty
///      (`TERM_PROGRAM`), Windows Terminal (`WT_SESSION`).
///   3. An allow-listed terminal is [HyperlinkSupport.suppressedUnderTmux] under
///      a multiplexer, else [HyperlinkSupport.supported]; anything else is
///      [HyperlinkSupport.unsupported].
///
/// Centralized here (like [detectGlyphTierFromEnvironment]) so every driver
/// honors the same allow-list, version thresholds, and tmux suppression.
/// Passive/env-only for now; an active DA/OSC probe (which would also cover the
/// version-less terminals above) is a later refinement (RFC 0017, Stage 3).
HyperlinkSupport detectHyperlinkSupportFromEnvironment(
  Map<String, String> environment,
) {
  final override = parseEnvFlag(environment['FLEURY_HYPERLINKS']);
  if (override == true) return HyperlinkSupport.supported; // force wins
  if (override == false) return HyperlinkSupport.disabledByOverride;

  if (!_terminalAllowsHyperlinks(environment)) {
    return HyperlinkSupport.unsupported;
  }
  return detectTerminalMultiplexerFromEnvironment(environment)
      ? HyperlinkSupport.suppressedUnderTmux
      : HyperlinkSupport.supported;
}

/// Whether the OUTER terminal is a known OSC 8 emitter (ignoring multiplexers
/// and overrides), applying a version threshold where the env exposes one.
bool _terminalAllowsHyperlinks(Map<String, String> environment) {
  final program = environment['TERM_PROGRAM']?.toLowerCase().trim() ?? '';
  if (program == 'iterm.app') {
    return _termProgramVersionAtLeast(environment, major: 3, minor: 1);
  }
  if (program == 'wezterm' || program == 'ghostty') return true;

  // VTE terminals expose a numeric VTE_VERSION; a present-but-too-old one is a
  // real answer (unsupported), not a fall-through to the presence checks below.
  final vte = int.tryParse((environment['VTE_VERSION'] ?? '').trim());
  if (vte != null) return vte >= 5000;

  if ((environment['KITTY_WINDOW_ID'] ?? '').trim().isNotEmpty) return true;
  if ((environment['TERM']?.toLowerCase().trim() ?? '') == 'xterm-kitty') {
    return true;
  }
  if ((environment['WT_SESSION'] ?? '').trim().isNotEmpty) return true;
  return false;
}

/// Whether `TERM_PROGRAM_VERSION` (e.g. `3.4.19`) is at least [major].[minor].
/// Missing or unparseable → false (conservative: never emit a link we can't
/// confirm the terminal renders, so a pre-OSC-8 build isn't fed `\x1b]8;;`).
bool _termProgramVersionAtLeast(
  Map<String, String> environment, {
  required int major,
  required int minor,
}) {
  final raw = (environment['TERM_PROGRAM_VERSION'] ?? '').trim();
  if (raw.isEmpty) return false;
  final parts = raw.split('.');
  final gotMajor = int.tryParse(parts[0]);
  if (gotMajor == null) return false;
  if (gotMajor != major) return gotMajor > major;
  final gotMinor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return gotMinor >= minor;
}

/// Detects whether OSC 8 hyperlinks are supported and safe to emit here — the
/// emission gate that the renderer/projection/feature read. The DIAGNOSE reason
/// is [detectHyperlinkSupportFromEnvironment].
bool detectHyperlinksFromEnvironment(Map<String, String> environment) =>
    detectHyperlinkSupportFromEnvironment(environment) ==
    HyperlinkSupport.supported;

/// Parses a boolean environment flag: `1`/`true`/`yes`/`on` → true,
/// `0`/`false`/`no`/`off` → false, and null for unset or any unrecognized value
/// (so the caller keeps its default). Case- and whitespace-insensitive. The one
/// source of truth for the accepted on/off vocabulary across `FLEURY_*` boolean
/// flags.
bool? parseEnvFlag(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case '1' || 'true' || 'yes' || 'on':
      return true;
    case '0' || 'false' || 'no' || 'off':
      return false;
    default:
      return null;
  }
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

  if (parseEnvFlag(environment['FLEURY_ASCII']) == true) {
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

/// Detects whether output is routed through a known terminal multiplexer.
bool detectTerminalMultiplexerFromEnvironment(Map<String, String> environment) {
  if ((environment['TMUX'] ?? '').isNotEmpty) return true;
  if ((environment['STY'] ?? '').isNotEmpty) return true;
  if ((environment['ZELLIJ'] ?? '').isNotEmpty) return true;
  if ((environment['ZELLIJ_SESSION_NAME'] ?? '').isNotEmpty) return true;
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
