import '../foundation/geometry.dart';
import '../terminal/capabilities.dart';
import 'framework.dart';

/// Ambient information about the rendering surface — for a terminal, its
/// [size] in cells and the [colorMode] it supports. Lean by design;
/// more fields can join later behind aspect-specific accessors.
final class MediaQueryData {
  const MediaQueryData({
    required this.size,
    this.colorMode = ColorMode.truecolor,
    this.glyphTier = GlyphTier.unicode,
    this.imageProtocol = ImageProtocol.halfBlock,
    this.tmuxPassthrough = false,
  });

  /// The terminal viewport size in cells.
  final CellSize size;

  /// The terminal's detected color fidelity. Widgets that pre-quantize
  /// (image rendering with dithering, color-aware glyph picking) need
  /// this; widgets that just emit `RgbColor` and trust the renderer
  /// cascade can ignore it.
  final ColorMode colorMode;

  /// The terminal/font glyph repertoire. Widgets and primitives that draw
  /// charts, borders, and ornaments use this to choose Unicode or ASCII
  /// representations without changing semantic state.
  final GlyphTier glyphTier;

  /// The richest image-rendering protocol the terminal supports.
  /// Image widgets pick the highest-fidelity path available.
  final ImageProtocol imageProtocol;

  /// True when we're running under a multiplexer (tmux, GNU screen)
  /// that swallows DCS/APC by default. Image widgets re-wrap their
  /// protocol payloads in the multiplexer's passthrough envelope so
  /// the host terminal still receives them.
  final bool tmuxPassthrough;

  MediaQueryData copyWith({
    CellSize? size,
    ColorMode? colorMode,
    GlyphTier? glyphTier,
    ImageProtocol? imageProtocol,
    bool? tmuxPassthrough,
  }) => MediaQueryData(
    size: size ?? this.size,
    colorMode: colorMode ?? this.colorMode,
    glyphTier: glyphTier ?? this.glyphTier,
    imageProtocol: imageProtocol ?? this.imageProtocol,
    tmuxPassthrough: tmuxPassthrough ?? this.tmuxPassthrough,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaQueryData &&
      other.size == size &&
      other.colorMode == colorMode &&
      other.glyphTier == glyphTier &&
      other.imageProtocol == imageProtocol &&
      other.tmuxPassthrough == tmuxPassthrough;

  @override
  int get hashCode =>
      Object.hash(size, colorMode, glyphTier, imageProtocol, tmuxPassthrough);

  @override
  String toString() =>
      'MediaQueryData(size: $size, colorMode: ${colorMode.name}, '
      'glyphTier: ${glyphTier.name}, '
      'imageProtocol: ${imageProtocol.name}, '
      'tmuxPassthrough: $tmuxPassthrough)';
}

/// Exposes the surface's [MediaQueryData] to its subtree, updated when the
/// terminal resizes. Read it with `MediaQuery.sizeOf(context)` — the
/// preferred accessor: it stays correct if the data grows new fields
/// (where reading the whole object would over-rebuild, Flutter's
/// well-known `MediaQuery.of` footgun).
class MediaQuery extends InheritedWidget {
  const MediaQuery({super.key, required this.data, required super.child});

  final MediaQueryData data;

  /// The full data in scope. Throws if there is no [MediaQuery] ancestor.
  static MediaQueryData of(BuildContext context) {
    final data = maybeOf(context);
    if (data == null) {
      throw StateError(
        'No MediaQuery in scope. It is installed by runTui; in tests the '
        'FleuryTester provides one.',
      );
    }
    return data;
  }

  static MediaQueryData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaQuery>()?.data;

  /// The terminal size in scope — the common case. Prefer this over
  /// [of] so a widget only depends on the size.
  static CellSize sizeOf(BuildContext context) => of(context).size;

  static CellSize? maybeSizeOf(BuildContext context) => maybeOf(context)?.size;

  /// The detected color fidelity. Returns [ColorMode.truecolor] when
  /// there is no MediaQuery in scope (the safe default for tests +
  /// the common terminal).
  static ColorMode colorModeOf(BuildContext context) =>
      maybeOf(context)?.colorMode ?? ColorMode.truecolor;

  /// The detected glyph repertoire. Returns [GlyphTier.unicode] when there is
  /// no MediaQuery in scope (the common test + modern-terminal default).
  static GlyphTier glyphTierOf(BuildContext context) =>
      maybeOf(context)?.glyphTier ?? GlyphTier.unicode;

  /// The detected image protocol. Returns [ImageProtocol.halfBlock]
  /// when there's no MediaQuery — the universal-fallback path.
  static ImageProtocol imageProtocolOf(BuildContext context) =>
      maybeOf(context)?.imageProtocol ?? ImageProtocol.halfBlock;

  /// Whether protocol payloads need to be wrapped for a multiplexer.
  /// Defaults to false (no MediaQuery in scope, e.g. tests).
  static bool tmuxPassthroughOf(BuildContext context) =>
      maybeOf(context)?.tmuxPassthrough ?? false;

  @override
  bool updateShouldNotify(MediaQuery oldWidget) => data != oldWidget.data;
}
