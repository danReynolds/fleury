// SurfaceCapabilities: the backend-neutral description of what the
// presenting surface can do — the vocabulary widgets read through
// MediaQuery. Terminals, DOM grids, and future surfaces all project into
// this; terminal-only concerns (escape protocols, tmux passthrough,
// alternate screen) stay on TerminalCapabilities in the terminal layer
// and never reach widget code.
//
// ColorMode and GlyphTier live here (moved from the terminal layer):
// they were always neutral concepts — a DOM grid has a color depth and a
// glyph repertoire too.

import 'package:meta/meta.dart';

/// Maximum color fidelity the surface can render.
///
/// Terminals detect this at startup from `$COLORTERM`/`$TERM`; browser
/// surfaces are truecolor. The renderer downsamples styled cells to
/// whatever the surface reports here.
enum ColorMode { none, ansi16, indexed256, truecolor }

/// Glyph repertoire the surface/font combination can render safely.
///
/// [unicode] enables box-drawing, braille, block elements, and common
/// ornaments. [ascii] keeps drawing output to 7-bit characters for legacy
/// consoles, `TERM=dumb`/`linux`, non-UTF-8 locales, or an explicit user
/// override. It changes how primitives *draw*, never their semantic state.
enum GlyphTier { ascii, unicode }

/// How the surface displays inline raster images.
enum InlineImageSupport {
  /// No native pixel path: widgets paint glyph approximations (half-block
  /// art, braille) into cells themselves.
  none,

  /// The surface renders true pixels from image bytes placed over cell
  /// regions (a browser `<img>` overlay, a terminal escape protocol
  /// emitted by the presenter). Widgets emit placements; the PRESENTER
  /// renders them.
  placements,
}

/// Pointer fidelity the surface reports.
enum PointerPrecision {
  /// No pointer at all.
  none,

  /// Whole-cell positions — a terminal mouse.
  cell,

  /// Sub-cell positions are available at the input source (a browser
  /// mouse), even though hit-testing stays cell-space.
  subCell,
}

/// Backend-neutral description of what the presenting surface can do.
@immutable
final class SurfaceCapabilities {
  const SurfaceCapabilities({
    this.colorMode = ColorMode.truecolor,
    this.glyphTier = GlyphTier.unicode,
    this.images = InlineImageSupport.none,
    this.hyperlinks = false,
    this.pointer = PointerPrecision.cell,
  });

  final ColorMode colorMode;
  final GlyphTier glyphTier;
  final InlineImageSupport images;

  /// Real hyperlinks: OSC 8 on terminals, anchors on the web.
  final bool hyperlinks;

  final PointerPrecision pointer;

  SurfaceCapabilities copyWith({
    ColorMode? colorMode,
    GlyphTier? glyphTier,
    InlineImageSupport? images,
    bool? hyperlinks,
    PointerPrecision? pointer,
  }) {
    return SurfaceCapabilities(
      colorMode: colorMode ?? this.colorMode,
      glyphTier: glyphTier ?? this.glyphTier,
      images: images ?? this.images,
      hyperlinks: hyperlinks ?? this.hyperlinks,
      pointer: pointer ?? this.pointer,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SurfaceCapabilities &&
        other.colorMode == colorMode &&
        other.glyphTier == glyphTier &&
        other.images == images &&
        other.hyperlinks == hyperlinks &&
        other.pointer == pointer;
  }

  @override
  int get hashCode =>
      Object.hash(colorMode, glyphTier, images, hyperlinks, pointer);
}

/// Implemented by drivers whose surface capabilities come from somewhere
/// richer than the terminal-capability projection — a structured remote
/// driver reporting what its PEER (a browser) declared. runApp prefers
/// this over projecting [TerminalCapabilities] when present. Folds into
/// presenter negotiation (pipeline-program PR9).
abstract interface class SurfaceCapabilitiesProvider {
  SurfaceCapabilities get surfaceCapabilities;
}
