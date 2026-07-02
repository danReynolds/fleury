import '../foundation/geometry.dart';
import '../rendering/surface_capabilities.dart';
import 'framework.dart';

/// Ambient information about the rendering surface: its [size] in cells
/// and the backend-neutral [capabilities] it reports. A terminal, a DOM
/// grid, and a served session all describe themselves through the same
/// vocabulary — terminal-only concerns (escape protocols, multiplexer
/// passthrough) are presenter concerns and never appear here.
final class MediaQueryData {
  const MediaQueryData({
    required this.size,
    this.capabilities = const SurfaceCapabilities(),
  });

  /// The surface viewport size in cells.
  final CellSize size;

  /// What the presenting surface can do.
  final SurfaceCapabilities capabilities;

  /// The surface's color fidelity — convenience for the common read.
  ColorMode get colorMode => capabilities.colorMode;

  /// The surface/font glyph repertoire — convenience for the common read.
  GlyphTier get glyphTier => capabilities.glyphTier;

  MediaQueryData copyWith({
    CellSize? size,
    SurfaceCapabilities? capabilities,
  }) => MediaQueryData(
    size: size ?? this.size,
    capabilities: capabilities ?? this.capabilities,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaQueryData &&
      other.size == size &&
      other.capabilities == capabilities;

  @override
  int get hashCode => Object.hash(size, capabilities);

  @override
  String toString() =>
      'MediaQueryData(size: $size, colorMode: ${colorMode.name}, '
      'glyphTier: ${glyphTier.name}, images: ${capabilities.images.name})';
}

/// Exposes the surface's [MediaQueryData] to its subtree, updated when the
/// surface resizes. Read it with `MediaQuery.sizeOf(context)` — the
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
        'No MediaQuery in scope. It is installed by runApp; in tests the '
        'FleuryTester provides one.',
      );
    }
    return data;
  }

  static MediaQueryData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaQuery>()?.data;

  /// The surface size in cells — the common case. Prefer this over
  /// [of] so a widget only depends on the size.
  static CellSize sizeOf(BuildContext context) => of(context).size;

  static CellSize? maybeSizeOf(BuildContext context) => maybeOf(context)?.size;

  /// The surface's capability set. Returns the neutral defaults when
  /// there is no MediaQuery in scope.
  static SurfaceCapabilities capabilitiesOf(BuildContext context) =>
      maybeOf(context)?.capabilities ?? const SurfaceCapabilities();

  /// The detected color fidelity. Returns [ColorMode.truecolor] when
  /// there is no MediaQuery in scope (the safe default for tests +
  /// the common terminal).
  static ColorMode colorModeOf(BuildContext context) =>
      maybeOf(context)?.colorMode ?? ColorMode.truecolor;

  /// The detected glyph repertoire. Returns [GlyphTier.unicode] when there is
  /// no MediaQuery in scope (the common test + modern-terminal default).
  static GlyphTier glyphTierOf(BuildContext context) =>
      maybeOf(context)?.glyphTier ?? GlyphTier.unicode;

  /// How the surface renders inline raster images. Returns
  /// [InlineImageSupport.none] when there's no MediaQuery — the
  /// glyph-fallback path works everywhere.
  static InlineImageSupport imagesOf(BuildContext context) =>
      maybeOf(context)?.capabilities.images ?? InlineImageSupport.none;

  @override
  bool updateShouldNotify(MediaQuery oldWidget) => data != oldWidget.data;
}
