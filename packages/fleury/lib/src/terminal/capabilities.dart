import 'package:meta/meta.dart';

import '../rendering/surface_capabilities.dart';
import '../rendering/width_policy.dart';
import 'terminal_probe.dart';

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
    this.measuredWidths = const WidthMeasurements.empty(),
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

  /// What the startup probe measured this terminal ACTUALLY drawing, per
  /// width-disagreement class — not what a table or a capability bit claims.
  ///
  /// Reported for diagnostics today rather than consumed by layout: the
  /// numbers have to be trustworthy before they are allowed to move glyphs.
  /// All-null when the terminal doesn't answer CPR, or the probe was skipped.
  final WidthMeasurements measuredWidths;

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
    WidthMeasurements? measuredWidths,
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
    measuredWidths: measuredWidths ?? this.measuredWidths,
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
        'measuredWidths=$measuredWidths, '
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

/// `FLEURY_EMOJI_WIDTH=narrow|wide` — explicit override for the bare
/// emoji-presentation width axis. Null when unset or unrecognized.
CellWidth? detectEmojiWidthFromEnvironment(Map<String, String> environment) =>
    _cellWidthFromEnv(environment['FLEURY_EMOJI_WIDTH']);

/// `FLEURY_VS16_WIDTH=narrow|wide` — explicit override for the simple emoji
/// variation-sequence axis. Independent of [detectEmojiWidthFromEnvironment]:
/// "bare emoji wide, sequence narrow" is the common combination in the field
/// and must be expressible (RFC 0019 §6.6). The env name keeps the operator
/// term of art; the policy axis is named for the sequence.
CellWidth? detectVs16WidthFromEnvironment(Map<String, String> environment) =>
    _cellWidthFromEnv(environment['FLEURY_VS16_WIDTH']);

/// `FLEURY_CLUSTER_MODE=joined|split` — explicit override for emoji ZWJ
/// lowering. `split` may force lowering past incomplete probe confidence.
ClusterLowering? detectClusterModeFromEnvironment(
  Map<String, String> environment,
) {
  final value = environment['FLEURY_CLUSTER_MODE']?.toLowerCase().trim();
  return switch (value) {
    'joined' => ClusterLowering.preserve,
    'split' => ClusterLowering.split,
    _ => null,
  };
}

CellWidth? _cellWidthFromEnv(String? raw) => switch (raw?.toLowerCase().trim()) {
  'narrow' => CellWidth.one,
  'wide' => CellWidth.two,
  _ => null,
};

/// The emoji ZWJ sequences in the probe battery, with their bare-probed
/// component ids and joiner counts — the inputs to the summing inequality.
const List<({String sequenceId, List<String> componentIds, int zwjCount})>
_zwjProbeSequences = [
  (
    sequenceId: 'familyZwj',
    componentIds: ['man', 'woman', 'boy'],
    zwjCount: 2,
  ),
  (
    sequenceId: 'healthWorkerZwj',
    componentIds: ['woman', 'medicalVs16'],
    zwjCount: 1,
  ),
];

/// Folds probe [measurements] and environment overrides into the one derived
/// [ResolvedTextPresentationPolicy] every geometry consumer shares
/// (RFC 0019 §6.2).
///
/// Per axis: an explicit `FLEURY_*` override wins outright; else agreeing
/// probe measurements decide; else the spec default stands and the axis is
/// recorded as [WidthDecisionSource.spec] — the `unknown` state, which
/// conservative consumers treat as "keep the safety net engaged".
///
/// Lowering follows RFC 0019 §6.4's two-step authorization: the observation
/// must be *summed* for every probed sequence (the measured inequality
/// `componentSum ≤ advance ≤ componentSum + zwjCount`), AND the width policy
/// must predict every measured component — otherwise splitting would trade
/// the joiner error for a component near-miss, so the action stays
/// [ClusterLowering.preserve] and the pin covers the sequence. A confidently
/// *joined* observation also records probe provenance: "this terminal
/// clusters" is evidence, not a default.
ResolvedTextPresentationPolicy deriveTextPresentationPolicy({
  WidthMeasurements measurements = const WidthMeasurements.empty(),
  Map<String, String> environment = const <String, String>{},
}) {
  final decisions = <WidthAxis, WidthDecisionSource>{};

  CellWidth? agreement(WidthProbeClass probeClass) {
    final widths = measurements.widthsIn(probeClass);
    if (widths.isEmpty || widths.any((w) => w == null)) return null;
    if (widths.every((w) => w == 1)) return CellWidth.one;
    if (widths.every((w) => w! >= 2)) return CellWidth.two;
    return null; // Disagreement — unknown, never a guess.
  }

  CellWidth resolveAxis(
    WidthAxis axis,
    CellWidth? override,
    WidthProbeClass probeClass,
    CellWidth specDefault,
  ) {
    if (override != null) {
      decisions[axis] = WidthDecisionSource.environment;
      return override;
    }
    final measured = agreement(probeClass);
    if (measured != null) {
      decisions[axis] = WidthDecisionSource.probe;
      return measured;
    }
    return specDefault;
  }

  final ambiguousOverride = switch (detectAmbiguousCharWidthFromEnvironment(
    environment,
  )) {
    AmbiguousCharWidth.narrow => CellWidth.one,
    AmbiguousCharWidth.wide => CellWidth.two,
    null => null,
  };
  final widths = CellWidthPolicy(
    ambiguous: resolveAxis(
      WidthAxis.ambiguous,
      ambiguousOverride,
      WidthProbeClass.ambiguous,
      CellWidth.one,
    ),
    emojiPresentation: resolveAxis(
      WidthAxis.emojiPresentation,
      detectEmojiWidthFromEnvironment(environment),
      WidthProbeClass.emojiPresentation,
      CellWidth.two,
    ),
    emojiVariationSequence: resolveAxis(
      WidthAxis.emojiVariationSequence,
      detectVs16WidthFromEnvironment(environment),
      WidthProbeClass.emojiVariationSequence,
      CellWidth.two,
    ),
  );

  var lowering = ClusterLowering.preserve;
  final loweringOverride = detectClusterModeFromEnvironment(environment);
  if (loweringOverride != null) {
    lowering = loweringOverride;
    decisions[WidthAxis.lowering] = WidthDecisionSource.environment;
  } else {
    final derived = _deriveLowering(measurements, widths);
    if (derived != null) {
      lowering = derived;
      decisions[WidthAxis.lowering] = WidthDecisionSource.probe;
    }
  }

  return ResolvedTextPresentationPolicy(
    policy: TextPresentationPolicy(widths: widths, lowering: lowering),
    decisions: Map.unmodifiable(decisions),
  );
}

/// The measured lowering observation → action, or null when unknown.
ClusterLowering? _deriveLowering(
  WidthMeasurements measurements,
  CellWidthPolicy widths,
) {
  if (measurements.isEmpty) return null;

  int predictedCells(String componentId) {
    final glyph = widthProbeBattery.firstWhere((g) => g.id == componentId);
    final axis = glyph.probeClass == WidthProbeClass.emojiVariationSequence
        ? widths.emojiVariationSequence
        : widths.emojiPresentation;
    return axis == CellWidth.two ? 2 : 1;
  }

  var allJoined = true;
  var allSummed = true;
  var componentsPredicted = true;
  for (final sequence in _zwjProbeSequences) {
    final advance = measurements.widthOf(sequence.sequenceId);
    if (advance == null) return null;
    final components = [
      for (final id in sequence.componentIds) measurements.widthOf(id),
    ];
    if (components.any((c) => c == null)) return null;
    final componentSum = components.fold<int>(0, (a, b) => a + b!);

    if (advance > 2) allJoined = false;
    final summed =
        componentSum <= advance && advance <= componentSum + sequence.zwjCount;
    if (!summed) allSummed = false;

    for (var i = 0; i < components.length; i++) {
      if (components[i] != predictedCells(sequence.componentIds[i])) {
        componentsPredicted = false;
      }
    }
  }

  if (allJoined) return ClusterLowering.preserve;
  if (allSummed && componentsPredicted) return ClusterLowering.split;
  // Summed but unpredicted components, or mixed joining across sequences:
  // unknown. Preserve without probe provenance — the pin keeps covering it.
  return null;
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
///
/// Order: `NO_COLOR` wins outright; then an explicit `FLEURY_COLOR_DEPTH`
/// override (`none`/`16`/`256`/`truecolor`) — the escape hatch for a
/// lying/misconfigured terminal and for deterministic recordings; then
/// `COLORTERM`/`TERM`; then `CLICOLOR_FORCE`/`CLICOLOR` when there is no `TERM`.
ColorMode detectColorModeFromEnvironment(Map<String, String> environment) {
  // NO_COLOR wins outright (https://no-color.org): any non-empty value
  // disables color, even over CLICOLOR_FORCE and FLEURY_COLOR_DEPTH — matching
  // prompt_toolkit, which also lets NO_COLOR win over its depth override.
  if ((environment['NO_COLOR'] ?? '').isNotEmpty) return ColorMode.none;

  // Explicit Fleury override. Same precedence idea as FLEURY_GLYPH_TIER: an
  // explicit value beats auto-detection (a terminal that claims truecolor but
  // renders it badly, a 256 terminal pinned to 16, or a forced depth in a
  // recording/CI run). `FleuryTester` already pins depth for goldens; this is
  // the user-facing counterpart.
  final override = _parseColorDepthOverride(environment['FLEURY_COLOR_DEPTH']);
  if (override != null) return override;

  final colorterm = environment['COLORTERM']?.toLowerCase() ?? '';
  final term = environment['TERM']?.toLowerCase() ?? '';
  if (colorterm.contains('truecolor') || colorterm.contains('24bit')) {
    return ColorMode.truecolor;
  }
  if (term.contains('256')) return ColorMode.indexed256;
  if (term.isNotEmpty) return ColorMode.ansi16;
  // No TERM, but the caller insists on color: CLICOLOR_FORCE, or a bare
  // non-zero CLICOLOR (the colorprofile/CLICOLOR convention).
  if ((environment['CLICOLOR_FORCE'] ?? '0') != '0' ||
      (environment['CLICOLOR'] ?? '0') != '0') {
    return ColorMode.ansi16;
  }
  return ColorMode.none;
}

/// Parses a `FLEURY_COLOR_DEPTH` value into a [ColorMode], or null when unset
/// or unrecognized. Case-insensitive; accepts friendly aliases.
ColorMode? _parseColorDepthOverride(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case 'none' || 'mono' || 'monochrome' || '1':
      return ColorMode.none;
    case '16' || 'ansi' || 'ansi16' || '4':
      return ColorMode.ansi16;
    case '256' || 'indexed' || 'indexed256' || '8':
      return ColorMode.indexed256;
    case 'truecolor' || 'true' || '24bit' || '24-bit' || 'rgb' || '24':
      return ColorMode.truecolor;
    case null || '':
      return null;
    default:
      return null;
  }
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
