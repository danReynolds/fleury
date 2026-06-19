import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:image/image.dart' as img;

/// Per-cell symbol palette the half-block painter uses to encode the
/// source. Trade more glyph diversity for sharper edges and better
/// effective resolution on color-poor terminals.
enum ImageGlyph {
  /// Classic two-pixel-per-cell rendering with `▀`. One fg color per
  /// row, one bg color per row — the safest, most font-portable
  /// choice. Matches what every TUI image library shipped first.
  halfBlock,

  /// Four-pixel-per-cell rendering across the 16 Unicode block
  /// quadrant glyphs (`▘▝▖▗▙▟▛▜▀▄▌▐▞▚█` + space). For each cell we
  /// pick the two-color split + glyph whose pattern best approximates
  /// the 2×2 source neighborhood — chafa's strategy. Roughly doubles
  /// effective horizontal resolution at the cost of needing all 16
  /// block glyphs from the active font (universally present in
  /// modern monospace fonts).
  quarterBlock,

  /// Six-pixel-per-cell rendering across the 64 Unicode sextant
  /// glyphs (U+1FB00..U+1FB3B + space, `▌`, `▐`, `█`). For each cell
  /// we sample a 2-wide × 3-tall sub-grid and pick the best 2-color
  /// pattern — chafa's `--symbols sextant` mode. ~50% more effective
  /// resolution than quarterBlock; needs the Unicode 13 "Symbols for
  /// Legacy Computing" block in the active font (modern fonts ship
  /// with it; older ones won't render the glyphs).
  sextant,

  /// Eight-pixel-per-cell rendering across the 256 Unicode braille
  /// glyphs (U+2800..U+28FF). Each cell encodes a 2-wide × 4-tall
  /// sub-grid via the 8 braille dots — densest practical sub-cell
  /// resolution we can address with widely-supported Unicode. Lower
  /// per-cell fidelity than sextant for photo-like content (only
  /// monochrome dots, no two-color split) but the canonical choice
  /// for line art, sparklines, and waveform displays — chafa's
  /// `--symbols braille`. Single fg color per cell.
  braille,
}

/// How an [Image] sizes itself within its allotted cell area.
enum ImageFit {
  /// Scale uniformly to fit inside the box, preserving aspect ratio.
  /// Letterboxes / pillarboxes the residual.
  contain,

  /// Scale uniformly to fill the box, preserving aspect ratio. Crops
  /// the parts that don't fit.
  cover,

  /// Stretch independently on each axis to fill the box. Distorts.
  fill,

  /// Render at intrinsic pixel size, centered (clipped if it overflows).
  none,
}

/// Source for an [Image] widget. Holds the decoded pixel data.
///
/// Decoding happens synchronously when the source is constructed
/// — fine for bundled assets and config-driven previews; not for
/// HTTP/large-PNG cases (decode upstream and pass via
/// [ImageSource.decoded] instead).
abstract class ImageSource {
  /// Decoded pixel data. Implementations cache.
  img.Image decode();

  /// Backed by an in-memory byte buffer (PNG / JPEG / BMP / TIFF /
  /// GIF — whatever `package:image` recognises).
  factory ImageSource.bytes(Uint8List bytes) = _BytesSource;

  /// Backed by a file on disk. Read synchronously at construction.
  ///
  /// Decoded images are cached cross-instance keyed by absolute path,
  /// so mounting the same `logo.png` in N widgets decodes once. Call
  /// [evictFile] to drop the cache for a path that has changed on
  /// disk; [evictAll] clears everything.
  factory ImageSource.file(String path) = _FileSource;

  /// An already-decoded image (e.g. produced by `img.decodePng`).
  /// Use this when the caller manages decoding (HTTP, large files,
  /// transformations).
  factory ImageSource.decoded(img.Image image) = _DecodedSource;

  /// Drop the cached decode for [path]. Call after writing to the file
  /// to force the next [decode] to re-read from disk.
  static void evictFile(String path) {
    _FileSource._cache.remove(File(path).absolute.path);
  }

  /// Drop every cached file decode. Useful in long-running sessions
  /// where assets get hot-swapped underneath.
  static void evictAll() {
    _FileSource._cache.clear();
  }
}

class _BytesSource implements ImageSource {
  _BytesSource(this._bytes);
  final Uint8List _bytes;
  img.Image? _cached;
  @override
  img.Image decode() => _cached ??=
      img.decodeImage(_bytes) ??
      (throw ArgumentError('ImageSource.bytes: could not decode'));
}

class _FileSource implements ImageSource {
  _FileSource(this._path);
  final String _path;

  /// Cross-instance decode cache. Keyed by absolute path so two
  /// `_FileSource('logo.png')` instances in different parts of the
  /// tree share the same decoded image. Holds strong references —
  /// the typical use case (bundled assets) is a finite set of files;
  /// callers with elastic working sets should drive eviction via
  /// [ImageSource.evictAll].
  static final Map<String, img.Image> _cache = {};

  @override
  img.Image decode() {
    final key = File(_path).absolute.path;
    final hit = _cache[key];
    if (hit != null) return hit;
    final bytes = File(_path).readAsBytesSync();
    final decoded =
        img.decodeImage(bytes) ??
        (throw ArgumentError('ImageSource.file: could not decode $_path'));
    _cache[key] = decoded;
    return decoded;
  }
}

class _DecodedSource implements ImageSource {
  _DecodedSource(this._image);
  final img.Image _image;
  @override
  img.Image decode() => _image;
}

/// Renders a raster image into the terminal as half-block ANSI art.
///
/// Each terminal cell holds two vertical "pixels": the top half is
/// drawn via the foreground of `▀`, the bottom half via its
/// background. With a truecolor terminal that's 24-bit color per
/// half-cell — full-fidelity image rendering for charts, logos,
/// previews, screenshots. On lesser terminals, [AnsiRenderer]'s color
/// cascade downsamples to 256 / 16 / none automatically.
///
/// ```dart
/// Image.file('logo.png')                      // most common
/// Image.bytes(bytes, fit: ImageFit.cover)
/// Image.decoded(decoded, glyph: ImageGlyph.sextant)
/// Image(source: ImageSource.bytes(buf))       // long form, still works
/// ```
///
/// Decoding is synchronous and cached on the [ImageSource]; the
/// widget itself is cheap to rebuild. For HTTP or other async
/// sources, decode upstream and pass via [ImageSource.decoded].
///
/// Future protocol upgrades (Kitty graphics, Sixel) will layer on
/// top transparently — terminals that support them will get true
/// pixel fidelity; everyone else continues to see the half-block
/// render this widget produces today.
class Image extends StatefulWidget {
  const Image({
    super.key,
    required this.source,
    this.fit = ImageFit.contain,
    this.glyph = ImageGlyph.halfBlock,
    this.backgroundColor,
    this.semanticLabel,
  });

  /// Shorthand for `Image(source: ImageSource.file(path))` — the
  /// common path for asset-style usage. Mirrors Flutter's
  /// `Image.file(File(path))`.
  Image.file(
    String path, {
    super.key,
    this.fit = ImageFit.contain,
    this.glyph = ImageGlyph.halfBlock,
    this.backgroundColor,
    this.semanticLabel,
  }) : source = ImageSource.file(path);

  /// Shorthand for `Image(source: ImageSource.bytes(bytes))`.
  Image.bytes(
    Uint8List bytes, {
    super.key,
    this.fit = ImageFit.contain,
    this.glyph = ImageGlyph.halfBlock,
    this.backgroundColor,
    this.semanticLabel,
  }) : source = ImageSource.bytes(bytes);

  /// Shorthand for `Image(source: ImageSource.decoded(decoded))` —
  /// pass an already-decoded `package:image` Image (e.g. from an HTTP
  /// fetch, generated programmatically, or transformed).
  Image.decoded(
    img.Image decoded, {
    super.key,
    this.fit = ImageFit.contain,
    this.glyph = ImageGlyph.halfBlock,
    this.backgroundColor,
    this.semanticLabel,
  }) : source = ImageSource.decoded(decoded);

  final ImageSource source;
  final ImageFit fit;

  /// Symbol palette for the ANSI-art fallback. [ImageGlyph.halfBlock]
  /// is the conservative default; [ImageGlyph.quarterBlock] roughly
  /// doubles horizontal resolution at the cost of more font-glyph
  /// reliance. Ignored when the active terminal supports a native
  /// image protocol (Kitty/iTerm2) — that path is already pixel-
  /// perfect and ignores the palette.
  final ImageGlyph glyph;

  /// If non-null, semitransparent pixels (0 < α < 255) are alpha-
  /// composited against this color: `out = α · src + (1−α) · bg`.
  /// Fully-transparent pixels are also flattened to [backgroundColor].
  ///
  /// When null, transparent pixels render as empty cells (showing the
  /// terminal's own background) and semitransparent pixels are
  /// weighted by their α in the area average — readable but doesn't
  /// match what designers expect from a compositor. Provide
  /// [backgroundColor] (typically the surrounding container's color)
  /// when transparent PNGs need crisp edges against a known surface.
  final Color? backgroundColor;

  /// Semantic label exposed to tests, inspectors, and future adapters.
  ///
  /// Leave null for decorative images. Capability and fallback state is still
  /// exposed so diagnostics can explain how the image rendered.
  final String? semanticLabel;

  @override
  State<Image> createState() => _ImageState();
}

class _ImageState extends State<Image> with SingleTickerProviderStateMixin {
  // The multi-frame source. For static images this has a single
  // entry; for animated GIFs / APNG / animated WebP this carries
  // every frame plus its per-frame duration.
  late img.Image _source;
  int _frameIndex = 0;

  // Cumulative time the current frame has been on screen, and the
  // last ticker timestamp we saw. We compute deltas so the loop
  // honors actual wall-clock spacing rather than ticker cadence
  // (a fast 60Hz ticker on a 100ms-per-frame GIF would over-advance
  // without this).
  int _accumulatedMs = 0;
  int _lastTickMs = 0;
  Ticker? _animationTicker;

  // GIFs that declare 0ms-per-frame (technically valid; classic
  // browsers interpret it as "as fast as possible") are clamped to a
  // sensible floor so we don't burn CPU.
  static const _minFrameMs = 20;
  static const _defaultFrameMs = 100;

  @override
  void initState() {
    super.initState();
    _source = widget.source.decode();
    _frameIndex = 0;
    _maybeStartAnimation();
  }

  void _maybeStartAnimation() {
    if (!_source.hasAnimation || _source.numFrames <= 1) return;
    _animationTicker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final nowMs = elapsed.inMilliseconds;
    final delta = nowMs - _lastTickMs;
    _lastTickMs = nowMs;
    if (delta <= 0) return;
    _accumulatedMs += delta;

    // Drain the accumulator by however many frame intervals it
    // covers. Drops frames cleanly if the host stalled for several
    // intervals — the animation jumps forward instead of replaying
    // missed frames.
    var changed = false;
    var dur = _durationOf(_frameIndex);
    while (_accumulatedMs >= dur) {
      _accumulatedMs -= dur;
      _frameIndex = (_frameIndex + 1) % _source.numFrames;
      dur = _durationOf(_frameIndex);
      changed = true;
    }
    if (changed) setState(() {});
  }

  int _durationOf(int index) {
    final raw = _source.frames[index].frameDuration;
    if (raw <= 0) return _defaultFrameMs;
    if (raw < _minFrameMs) return _minFrameMs;
    return raw;
  }

  @override
  void didUpdateWidget(Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source)) {
      _source = widget.source.decode();
      _frameIndex = 0;
      _accumulatedMs = 0;
      _lastTickMs = 0;
      _animationTicker?.dispose();
      _animationTicker = null;
      _maybeStartAnimation();
    }
  }

  @override
  void dispose() {
    _animationTicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorMode = MediaQuery.colorModeOf(context);
    final protocol = MediaQuery.imageProtocolOf(context);
    final tmuxPassthrough = MediaQuery.tmuxPassthroughOf(context);
    final capabilityResolution = resolveCapabilityRequirement(
      CapabilityRequirement(
        feature: TerminalFeature.inlineImages,
        level: CapabilityLevel.preferred,
        reason: 'Render image widgets with native terminal pixels.',
        fallback: CapabilityFallback(label: '${widget.glyph.name} glyph image'),
      ),
      TerminalCapabilities(
        colorMode: colorMode,
        imageProtocol: protocol,
        tmuxPassthrough: tmuxPassthrough,
      ),
    );
    final semanticState = capabilityResolution
        .toSemanticState()
        .merge(<String, Object?>{
          'imageProtocol': protocol.name,
          'imageGlyph': widget.glyph.name,
          'colorMode': colorMode.name,
          'tmuxPassthrough': tmuxPassthrough,
          'frameIndex': _frameIndex,
          'frameCount': _source.frames.length,
        });

    return Semantics(
      role: SemanticRole.image,
      label: widget.semanticLabel,
      value: protocol.name,
      state: semanticState,
      child: _RawImage(
        decoded: _source.frames[_frameIndex],
        fit: widget.fit,
        glyph: widget.glyph,
        colorMode: colorMode,
        protocol: protocol,
        tmuxPassthrough: tmuxPassthrough,
        backgroundColor: widget.backgroundColor,
      ),
    );
  }
}

class _RawImage extends LeafRenderObjectWidget {
  const _RawImage({
    required this.decoded,
    required this.fit,
    required this.glyph,
    required this.colorMode,
    required this.protocol,
    required this.tmuxPassthrough,
    required this.backgroundColor,
  });

  final img.Image decoded;
  final ImageFit fit;
  final ImageGlyph glyph;
  final ColorMode colorMode;
  final ImageProtocol protocol;
  final bool tmuxPassthrough;
  final Color? backgroundColor;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderImage(
    decoded: decoded,
    fit: fit,
    glyph: glyph,
    colorMode: colorMode,
    protocol: protocol,
    tmuxPassthrough: tmuxPassthrough,
    backgroundColor: backgroundColor,
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderImage r) {
    r
      ..decoded = decoded
      ..fit = fit
      ..glyph = glyph
      ..colorMode = colorMode
      ..protocol = protocol
      ..tmuxPassthrough = tmuxPassthrough
      ..backgroundColor = backgroundColor;
  }
}

/// Render object behind [Image].
class RenderImage extends RenderObject {
  RenderImage({
    required img.Image decoded,
    required ImageFit fit,
    required ImageGlyph glyph,
    required ColorMode colorMode,
    required ImageProtocol protocol,
    bool tmuxPassthrough = false,
    Color? backgroundColor,
  }) : _decoded = decoded,
       _fit = fit,
       _glyph = glyph,
       _colorMode = colorMode,
       _protocol = protocol,
       _tmuxPassthrough = tmuxPassthrough,
       _backgroundColor = backgroundColor;

  img.Image _decoded;
  set decoded(img.Image v) {
    if (identical(_decoded, v)) return;
    _decoded = v;
    _encodedPng = null;
    _encodedId = null;
    _fitCropPng = null;
    _fitCropKey = null;
    markNeedsLayout();
  }

  // Cached PNG encode of [_decoded] and its content-hash id, recomputed only
  // when the decoded image changes. The native-protocol (kitty/iTerm2) and
  // browser paint paths run on every frame the tree repaints; without this they
  // would re-encode (zlib) and re-hash the same pixels each frame.
  Uint8List? _encodedPng;
  String? _encodedId;

  Uint8List get _png => _encodedPng ??= img.encodePng(_decoded);
  String get _pngId => _encodedId ??= CellBuffer.hashImageBytes(_png);

  ImageFit _fit;
  set fit(ImageFit v) {
    if (_fit == v) return;
    _fit = v;
    markNeedsPaintOnly();
  }

  ImageGlyph _glyph;
  set glyph(ImageGlyph v) {
    if (_glyph == v) return;
    _glyph = v;
    markNeedsPaintOnly();
  }

  ColorMode _colorMode;
  set colorMode(ColorMode v) {
    if (_colorMode == v) return;
    _colorMode = v;
    markNeedsPaintOnly();
  }

  ImageProtocol _protocol;
  set protocol(ImageProtocol v) {
    if (_protocol == v) return;
    _protocol = v;
    markNeedsPaintOnly();
  }

  bool _tmuxPassthrough;
  set tmuxPassthrough(bool v) {
    if (_tmuxPassthrough == v) return;
    _tmuxPassthrough = v;
    markNeedsPaintOnly();
  }

  Color? _backgroundColor;
  set backgroundColor(Color? v) {
    if (_backgroundColor == v) return;
    _backgroundColor = v;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Intrinsic size: 1 cell per (1 pixel × 2 pixels) at native scale —
    // halfBlock cells are 2 pixels tall. Most consumers will bound us
    // with a SizedBox; if unbounded we fall back to a sensible default.
    final natW = _decoded.width;
    final natH = (_decoded.height / 2).ceil();
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : natW;
    final rows = constraints.hasBoundedHeight ? constraints.maxRows! : natH;
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final cols = size.cols;
    final rows = size.rows;
    if (cols == 0 || rows == 0) return;

    // Native protocol path takes over completely when supported — the
    // terminal paints the pixels itself, no per-cell half-block math.
    if (_protocol == ImageProtocol.kitty) {
      _paintKitty(buffer, offset, cols, rows);
      return;
    }
    if (_protocol == ImageProtocol.iterm2) {
      _paintIterm2(buffer, offset, cols, rows);
      return;
    }
    if (_protocol == ImageProtocol.sixel) {
      _paintSixel(buffer, offset, cols, rows);
      return;
    }
    if (_protocol == ImageProtocol.browser) {
      _paintBrowser(buffer, offset, cols, rows);
      return;
    }

    if (_glyph == ImageGlyph.quarterBlock) {
      _paintQuarterBlock(buffer, offset, cols, rows);
      return;
    }
    if (_glyph == ImageGlyph.sextant) {
      _paintSextant(buffer, offset, cols, rows);
      return;
    }
    if (_glyph == ImageGlyph.braille) {
      _paintBraille(buffer, offset, cols, rows);
      return;
    }

    final srcW = _decoded.width;
    final srcH = _decoded.height;
    final tgtW = cols;
    final tgtH = rows * 2;

    final (sampleX, sampleY) = _sampleMappers(srcW, srcH, tgtW, tgtH, _fit);

    // Pass 1: sample every half-pixel at full RGB into a flat buffer.
    // Indexed (y * tgtW + x); null means "fully transparent / no
    // intersection with the source." Storing the row of resolved colors
    // up front lets the dithering pass distribute quantization error
    // forward to as-yet-unwritten pixels.
    final sampled = List<(double, double, double)?>.filled(tgtW * tgtH, null);
    for (var py = 0; py < tgtH; py++) {
      for (var px = 0; px < tgtW; px++) {
        final rgb = _samplePixel(sampleX, sampleY, px, py, srcW, srcH);
        sampled[py * tgtW + px] = rgb == null
            ? null
            : (rgb.$1.toDouble(), rgb.$2.toDouble(), rgb.$3.toDouble());
      }
    }

    // Pass 2: quantize → emit. Floyd-Steinberg only kicks in for
    // indexed / ansi16 modes (truecolor and none pass through; the
    // first has no quantization to do, the second drops color anyway).
    final dither =
        _colorMode == ColorMode.indexed256 || _colorMode == ColorMode.ansi16;

    for (var py = 0; py < tgtH; py++) {
      final ry = py >> 1;
      final isTopHalf = (py & 1) == 0;
      for (var px = 0; px < tgtW; px++) {
        final idx = py * tgtW + px;
        final rgb = sampled[idx];
        if (rgb == null) continue;

        // Pick the quantized color and the error to distribute.
        final (qr, qg, qb, er, eg, eb) = _quantize(rgb, _colorMode);
        if (dither) {
          // Floyd-Steinberg error distribution:
          //   right       (px+1, py)   : 7/16
          //   below-left  (px-1, py+1) : 3/16
          //   below       (px,   py+1) : 5/16
          //   below-right (px+1, py+1) : 1/16
          void add(int p, double r, double g, double b) {
            final t = sampled[p];
            if (t == null) return;
            sampled[p] = (t.$1 + r, t.$2 + g, t.$3 + b);
          }

          if (px + 1 < tgtW) {
            add(idx + 1, er * 7 / 16, eg * 7 / 16, eb * 7 / 16);
          }
          if (py + 1 < tgtH) {
            final below = idx + tgtW;
            if (px - 1 >= 0) {
              add(below - 1, er * 3 / 16, eg * 3 / 16, eb * 3 / 16);
            }
            add(below, er * 5 / 16, eg * 5 / 16, eb * 5 / 16);
            if (px + 1 < tgtW) {
              add(below + 1, er * 1 / 16, eg * 1 / 16, eb * 1 / 16);
            }
          }
        }

        // Write the quantized color into the half-cell. We accumulate
        // per cell: the top half writes the foreground first, the
        // bottom half merges its color into the existing style as
        // background.
        final tgtCol = offset.col + px;
        final tgtRow = offset.row + ry;
        if (tgtCol < 0 ||
            tgtCol >= buffer.size.cols ||
            tgtRow < 0 ||
            tgtRow >= buffer.size.rows) {
          continue;
        }

        final color = _packColor(qr, qg, qb, _colorMode);
        final existing = buffer.atColRow(tgtCol, tgtRow).style;
        final newStyle = isTopHalf
            ? existing.merge(CellStyle(foreground: color))
            : existing.merge(CellStyle(background: color));
        buffer.writeGrapheme(CellOffset(tgtCol, tgtRow), '▀', style: newStyle);
      }
    }
  }

  /// Quantizes a continuous RGB sample (potentially with FS-accumulated
  /// error pushing components outside 0..255) into the target color
  /// mode's nearest representable color. Returns the quantized integer
  /// RGB plus the residual error (signed) for downstream distribution.
  ///
  /// For [ColorMode.truecolor] and [ColorMode.none] this is the identity
  /// (clamped) — no quantization step, no error to distribute.
  (int, int, int, double, double, double) _quantize(
    (double, double, double) sample,
    ColorMode mode,
  ) {
    final r = sample.$1.clamp(0.0, 255.0);
    final g = sample.$2.clamp(0.0, 255.0);
    final b = sample.$3.clamp(0.0, 255.0);
    switch (mode) {
      case ColorMode.truecolor:
      case ColorMode.none:
        return (r.round(), g.round(), b.round(), 0, 0, 0);
      case ColorMode.indexed256:
        // 6×6×6 cube + grays. We pick the nearest cube level
        // (0, 95, 135, 175, 215, 255) per channel — close enough to
        // the xterm-256 spec for dithering purposes.
        const levels = [0, 95, 135, 175, 215, 255];
        int near(double v) {
          var bestI = 0;
          var bestD = (v - levels[0]).abs();
          for (var i = 1; i < levels.length; i++) {
            final d = (v - levels[i]).abs();
            if (d < bestD) {
              bestD = d;
              bestI = i;
            }
          }
          return levels[bestI];
        }
        final qr = near(r);
        final qg = near(g);
        final qb = near(b);
        return (qr, qg, qb, r - qr, g - qg, b - qb);
      case ColorMode.ansi16:
        // Snap to the 8 standard colors + their bright variants —
        // sourced from the same table xterm uses. Smaller palette
        // means much larger errors, which is exactly where dithering
        // earns its keep.
        const ansi = [
          [0, 0, 0],
          [205, 0, 0],
          [0, 205, 0],
          [205, 205, 0],
          [0, 0, 238],
          [205, 0, 205],
          [0, 205, 205],
          [229, 229, 229],
          [127, 127, 127],
          [255, 0, 0],
          [0, 255, 0],
          [255, 255, 0],
          [92, 92, 255],
          [255, 0, 255],
          [0, 255, 255],
          [255, 255, 255],
        ];
        var bestI = 0;
        var bestD = double.infinity;
        for (var i = 0; i < ansi.length; i++) {
          final dr = r - ansi[i][0];
          final dg = g - ansi[i][1];
          final db = b - ansi[i][2];
          final d = dr * dr + dg * dg + db * db;
          if (d < bestD) {
            bestD = d;
            bestI = i;
          }
        }
        final qr = ansi[bestI][0];
        final qg = ansi[bestI][1];
        final qb = ansi[bestI][2];
        return (qr, qg, qb, r - qr, g - qg, b - qb);
    }
  }

  /// Wraps the quantized RGB triple in the right `Color` subclass for
  /// the mode, so the renderer doesn't re-quantize.
  Color? _packColor(int r, int g, int b, ColorMode mode) {
    switch (mode) {
      case ColorMode.none:
        return null; // strips color entirely
      case ColorMode.truecolor:
        return RgbColor(r, g, b);
      case ColorMode.indexed256:
        // Re-derive the 6-cube index from the quantized levels.
        const levels = [0, 95, 135, 175, 215, 255];
        int idx(int v) {
          for (var i = 0; i < levels.length; i++) {
            if (v == levels[i]) return i;
          }
          return 0;
        }
        return IndexedColor(16 + 36 * idx(r) + 6 * idx(g) + idx(b));
      case ColorMode.ansi16:
        // Lookup back into the same table the quantizer used.
        const ansi = [
          [0, 0, 0],
          [205, 0, 0],
          [0, 205, 0],
          [205, 205, 0],
          [0, 0, 238],
          [205, 0, 205],
          [0, 205, 205],
          [229, 229, 229],
          [127, 127, 127],
          [255, 0, 0],
          [0, 255, 0],
          [255, 255, 0],
          [92, 92, 255],
          [255, 0, 255],
          [0, 255, 255],
          [255, 255, 255],
        ];
        for (var i = 0; i < ansi.length; i++) {
          if (ansi[i][0] == r && ansi[i][1] == g && ansi[i][2] == b) {
            return AnsiColor(i);
          }
        }
        return AnsiColor(0);
    }
  }

  /// Returns mappers from target coordinates (cell columns, half-cell
  /// vertical pixels) into UNCLAMPED source pixel space. The sampler
  /// computes the source rect covered by each target half-pixel and
  /// clips to source bounds — pixels outside the source area are
  /// excluded from the average, rather than treated as transparent.
  (double Function(int), double Function(int)) _sampleMappers(
    int srcW,
    int srcH,
    int tgtW,
    int tgtH,
    ImageFit fit,
  ) {
    switch (fit) {
      case ImageFit.fill:
        return ((rx) => rx * srcW / tgtW, (py) => py * srcH / tgtH);
      case ImageFit.contain:
        final scale = (tgtW / srcW < tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
        final dispW = srcW * scale;
        final dispH = srcH * scale;
        final ox = (tgtW - dispW) / 2;
        final oy = (tgtH - dispH) / 2;
        return ((rx) => (rx - ox) / scale, (py) => (py - oy) / scale);
      case ImageFit.cover:
        final scale = (tgtW / srcW > tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
        final dispW = srcW * scale;
        final dispH = srcH * scale;
        final ox = (tgtW - dispW) / 2;
        final oy = (tgtH - dispH) / 2;
        return ((rx) => (rx - ox) / scale, (py) => (py - oy) / scale);
      case ImageFit.none:
        final ox = (tgtW - srcW) / 2;
        final oy = (tgtH - srcH) / 2;
        return ((rx) => (rx - ox).toDouble(), (py) => (py - oy).toDouble());
    }
  }

  /// The cell sub-rectangle the source occupies inside a [cols]×[rows] box under
  /// [fit] — `col`/`row` relative to the box top-left, `cols`/`rows` its size —
  /// plus the source-pixel crop (`cropX/Y/W/H`) to transmit. Mirrors
  /// [_sampleMappers]' contain/cover/none math against the conventional 1×2 cell
  /// pixel aspect, so the kitty/iTerm2 paths letterbox or crop exactly like the
  /// glyph tiers and the browser (CSS `object-fit`). `fill` is the whole box and
  /// whole source (the historical behaviour). When the box already matches the
  /// source aspect, `contain` degenerates to the full box.
  static _FitRect _resolveFit(
      int srcW, int srcH, int cols, int rows, ImageFit fit) {
    int centerOffset(int outer, int inner) =>
        ((outer - inner) / 2).round().clamp(0, outer - inner);
    switch (fit) {
      case ImageFit.fill:
        return _FitRect(0, 0, cols, rows, 0, 0, srcW, srcH);
      case ImageFit.contain:
        final tgtW = cols.toDouble();
        final tgtH = (rows * 2).toDouble();
        final scale = (tgtW / srcW < tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
        final dCols = (srcW * scale).round().clamp(1, cols);
        final dRows = (srcH * scale / 2).round().clamp(1, rows);
        return _FitRect(centerOffset(cols, dCols), centerOffset(rows, dRows),
            dCols, dRows, 0, 0, srcW, srcH);
      case ImageFit.cover:
        final tgtW = cols.toDouble();
        final tgtH = (rows * 2).toDouble();
        final scale = (tgtW / srcW > tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
        final cropW = (tgtW / scale).round().clamp(1, srcW);
        final cropH = (tgtH / scale).round().clamp(1, srcH);
        return _FitRect(0, 0, cols, rows, centerOffset(srcW, cropW),
            centerOffset(srcH, cropH), cropW, cropH);
      case ImageFit.none:
        // Native resolution, centered: 1 source px = 1 column, 2 px = 1 row.
        final cropW = srcW <= cols ? srcW : cols;
        final cropH = srcH <= rows * 2 ? srcH : rows * 2;
        final dCols = cropW.clamp(1, cols);
        final dRows = (cropH / 2).round().clamp(1, rows);
        return _FitRect(centerOffset(cols, dCols), centerOffset(rows, dRows),
            dCols, dRows, centerOffset(srcW, cropW), centerOffset(srcH, cropH),
            cropW, cropH);
    }
  }

  // Single-entry cache of the cropped+encoded PNG for cover/none fits (contain
  // and fill reuse the full-image [_png]). Keyed by the crop rect, invalidated
  // when the decoded image changes.
  Uint8List? _fitCropPng;
  String? _fitCropKey;

  /// PNG bytes for [f]'s crop: the full-image [_png] when the crop is the whole
  /// source (fill/contain), else a cached encode of the cropped region.
  Uint8List _fitPng(_FitRect f) {
    if (f.cropX == 0 &&
        f.cropY == 0 &&
        f.cropW == _decoded.width &&
        f.cropH == _decoded.height) {
      return _png;
    }
    final key = '${f.cropX},${f.cropY},${f.cropW},${f.cropH}';
    if (_fitCropKey == key && _fitCropPng != null) return _fitCropPng!;
    final cropped = img.copyCrop(
      _decoded,
      x: f.cropX,
      y: f.cropY,
      width: f.cropW,
      height: f.cropH,
    );
    final png = img.encodePng(cropped);
    _fitCropPng = png;
    _fitCropKey = key;
    return png;
  }

  /// Emits the image via the Kitty graphics protocol — terminal renders
  /// actual pixels, not half-blocks. Encodes the source as PNG (Kitty's
  /// best-supported format; format `f=100`), base64-wraps the payload,
  /// chunks at 4 KiB (Kitty requires `m=1` for not-last and `m=0` for
  /// final, with each chunk in its own `ESC_G…ESC\` envelope), and
  /// constrains the displayed region to our allotted cell box via
  /// `c=<cols>,r=<rows>` so the terminal scales to fit.
  ///
  /// Action `a=T` ("transmit and display now") tells Kitty to put the
  /// image at the current cursor position. The renderer positions the
  /// cursor at the cell anchor before emitting these bytes.
  void _paintKitty(CellBuffer buffer, CellOffset offset, int cols, int rows) {
    // Resolve the fit: contain letterboxes into a centered sub-rect, cover/none
    // crop, fill takes the whole box — matching the glyph + browser surfaces.
    final f = _resolveFit(_decoded.width, _decoded.height, cols, rows, _fit);
    // Encode (cached across repaints) — Kitty's RGBA path (`f=32`) has fewer
    // well-tested decoders across terminals than PNG (`f=100`).
    final png = _fitPng(f);
    final b64 = base64.encode(png);
    const chunkSize = 4096;
    final out = StringBuffer();
    var pos = 0;
    var first = true;
    while (pos < b64.length) {
      final end = (pos + chunkSize < b64.length) ? pos + chunkSize : b64.length;
      final isLast = end == b64.length;
      out.write('\x1B_G');
      if (first) {
        // First chunk carries the parameters; subsequent ones only
        // carry `m=` (continuation flag).
        out.write('f=100,a=T,c=${f.cols},r=${f.rows},m=${isLast ? 0 : 1};');
        first = false;
      } else {
        out.write('m=${isLast ? 0 : 1};');
      }
      out.write(b64.substring(pos, end));
      out.write('\x1B\\');
      pos = end;
    }
    _writeProtocolRegion(buffer, CellOffset(offset.col + f.col, offset.row + f.row),
        out.toString(), f.cols, f.rows);
  }

  /// Emits the image for the browser "serve" surface. The PNG bytes go into the
  /// buffer's inline-image table (keyed by content hash) via [CellBuffer.writeImage];
  /// the cell grid only carries the lightweight id. The serve codec ships the
  /// bytes once and the DOM client renders an `<img>` overlay — true pixels,
  /// like a native terminal image protocol, without bloating the cell wire.
  void _paintBrowser(CellBuffer buffer, CellOffset offset, int cols, int rows) {
    // Reuse the cached PNG + id so a static image isn't re-encoded or re-hashed
    // on every repaint (writeImageWithId skips the per-paint content hash).
    buffer.writeImageWithId(
      offset,
      _pngId,
      _png,
      width: cols,
      height: rows,
      fit: _inlineFit(_fit),
    );
  }

  /// Maps the widget-level [ImageFit] onto the wire-level [InlineImageFit] the
  /// serve client turns into a CSS `object-fit`. Exhaustive, so adding an
  /// [ImageFit] mode fails to compile here until it's mapped — keeping the two
  /// enums in lockstep.
  static InlineImageFit _inlineFit(ImageFit fit) => switch (fit) {
    ImageFit.contain => InlineImageFit.contain,
    ImageFit.cover => InlineImageFit.cover,
    ImageFit.fill => InlineImageFit.fill,
    ImageFit.none => InlineImageFit.none,
  };

  /// Paints the image at quarter-block density: 2×2 sub-pixels per
  /// cell instead of half-block's 1×2. For each cell we sample the
  /// four quadrants of the source, then search the 16 possible
  /// two-color-split patterns for the one whose A/B cluster averages
  /// minimize sum-of-squared error against the samples. The chosen
  /// pattern picks one of 16 Unicode block-element glyphs
  /// (`▘▝▖▗▙▟▛▜▀▄▌▐▞▚█` + space); fg = A cluster mean, bg = B cluster
  /// mean.
  ///
  /// On uniform cells the algorithm naturally degenerates to `█`
  /// (all-A) so flat regions cost no extra fidelity vs. half-block.
  /// On stripey / diagonal / textured regions it picks half-block
  /// (`▀`/`▄`/`▌`/`▐`) or one of the L-shaped tri-quadrant glyphs —
  /// roughly chafa's quarter-block algorithm, the canonical
  /// state-of-the-art for ANSI-art image fidelity.
  ///
  /// Quantization for indexed / ansi16 modes runs on the cluster
  /// means (one per side) rather than per sub-pixel, so a cell never
  /// shows more than two distinct quantized colors regardless of
  /// source complexity.
  void _paintQuarterBlock(
    CellBuffer buffer,
    CellOffset offset,
    int cols,
    int rows,
  ) {
    final srcW = _decoded.width;
    final srcH = _decoded.height;
    final tgtW = cols * 2;
    final tgtH = rows * 2;
    final (sampleX, sampleY) = _sampleMappers(srcW, srcH, tgtW, tgtH, _fit);

    // Bit layout: TL=8, TR=4, BL=2, BR=1. Index = pattern.
    const glyphs = [
      ' ',
      '▗',
      '▖',
      '▄',
      '▝',
      '▐',
      '▞',
      '▟',
      '▘',
      '▚',
      '▌',
      '▙',
      '▀',
      '▜',
      '▛',
      '█',
    ];

    for (var ry = 0; ry < rows; ry++) {
      for (var rx = 0; rx < cols; rx++) {
        final tgtCol = offset.col + rx;
        final tgtRow = offset.row + ry;
        if (tgtCol < 0 ||
            tgtCol >= buffer.size.cols ||
            tgtRow < 0 ||
            tgtRow >= buffer.size.rows) {
          continue;
        }

        // Sample the four sub-pixels covering this cell.
        final px = rx * 2;
        final py = ry * 2;
        final tl = _samplePixel(sampleX, sampleY, px, py, srcW, srcH);
        final tr = _samplePixel(sampleX, sampleY, px + 1, py, srcW, srcH);
        final bl = _samplePixel(sampleX, sampleY, px, py + 1, srcW, srcH);
        final br = _samplePixel(sampleX, sampleY, px + 1, py + 1, srcW, srcH);

        final samples = <(int, int, int)?>[tl, tr, bl, br];
        var nonNull = 0;
        for (final s in samples) {
          if (s != null) nonNull++;
        }
        if (nonNull == 0) continue; // fully transparent → empty cell

        // Search all 16 patterns for the lowest cluster-error fit.
        // Per pattern: pixels where bit is 1 belong to cluster A
        // (foreground), bit 0 → B (background). Compute cluster
        // means over the non-null samples, then SSE of every sample
        // against its assigned cluster center.
        var bestPattern = 0xF;
        var bestErr = double.infinity;
        var bestAr = 0.0, bestAg = 0.0, bestAb = 0.0;
        var bestBr = 0.0, bestBg = 0.0, bestBb = 0.0;

        for (var pattern = 0; pattern <= 15; pattern++) {
          var aR = 0.0, aG = 0.0, aB = 0.0, aN = 0;
          var bR = 0.0, bG = 0.0, bB = 0.0, bN = 0;
          for (var i = 0; i < 4; i++) {
            final s = samples[i];
            if (s == null) continue;
            final isA = ((pattern >> (3 - i)) & 1) == 1;
            if (isA) {
              aR += s.$1;
              aG += s.$2;
              aB += s.$3;
              aN++;
            } else {
              bR += s.$1;
              bG += s.$2;
              bB += s.$3;
              bN++;
            }
          }
          // A side with no members borrows the other side's mean —
          // gives the right thing for all-foreground / all-background
          // degenerate patterns on uniform cells.
          double aMr, aMg, aMb, bMr, bMg, bMb;
          if (aN == 0) {
            aMr = bR / bN;
            aMg = bG / bN;
            aMb = bB / bN;
            bMr = aMr;
            bMg = aMg;
            bMb = aMb;
          } else if (bN == 0) {
            bMr = aR / aN;
            bMg = aG / aN;
            bMb = aB / aN;
            aMr = bMr;
            aMg = bMg;
            aMb = bMb;
          } else {
            aMr = aR / aN;
            aMg = aG / aN;
            aMb = aB / aN;
            bMr = bR / bN;
            bMg = bG / bN;
            bMb = bB / bN;
          }

          var err = 0.0;
          for (var i = 0; i < 4; i++) {
            final s = samples[i];
            if (s == null) continue;
            final isA = ((pattern >> (3 - i)) & 1) == 1;
            final dr = s.$1 - (isA ? aMr : bMr);
            final dg = s.$2 - (isA ? aMg : bMg);
            final db = s.$3 - (isA ? aMb : bMb);
            err += dr * dr + dg * dg + db * db;
          }
          // `<=` so when two patterns tie on error (e.g. ▀ and ▄ for
          // a top-half stripe are mathematically equivalent splits),
          // the later iteration with TL in the foreground wins —
          // matches the convention that "more fg" / TL-set patterns
          // are the canonical representation.
          if (err <= bestErr) {
            bestErr = err;
            bestPattern = pattern;
            bestAr = aMr;
            bestAg = aMg;
            bestAb = aMb;
            bestBr = bMr;
            bestBg = bMg;
            bestBb = bMb;
          }
        }

        final glyph = glyphs[bestPattern];

        // Quantize each cluster mean to the active color mode. We
        // discard the FS error here — quarter-block already encodes
        // most of the spatial detail through pattern choice, so
        // per-cluster dithering would muddy more than it helps.
        final (qAr, qAg, qAb, _, _, _) = _quantize((
          bestAr,
          bestAg,
          bestAb,
        ), _colorMode);
        final (qBr, qBg, qBb, _, _, _) = _quantize((
          bestBr,
          bestBg,
          bestBb,
        ), _colorMode);
        final fg = _packColor(qAr, qAg, qAb, _colorMode);
        final bg = _packColor(qBr, qBg, qBb, _colorMode);

        buffer.writeGrapheme(
          CellOffset(tgtCol, tgtRow),
          glyph,
          style: CellStyle(foreground: fg, background: bg),
        );
      }
    }
  }

  /// Paints at sextant density: 2 cols × 3 rows of sub-pixels per cell
  /// (vs quarterBlock's 2×2). For each cell we sample the 6 sub-pixels,
  /// search all 64 two-color partitions for the lowest cluster-error
  /// fit, then emit the matching Unicode 13 sextant glyph + fg/bg.
  ///
  /// Bit layout (LSB = top-left, matches the Unicode "BLOCK SEXTANT-N"
  /// naming):
  ///   bit 0 = top-left      bit 1 = top-right
  ///   bit 2 = middle-left   bit 3 = middle-right
  ///   bit 4 = bottom-left   bit 5 = bottom-right
  void _paintSextant(CellBuffer buffer, CellOffset offset, int cols, int rows) {
    final srcW = _decoded.width;
    final srcH = _decoded.height;
    final tgtW = cols * 2;
    final tgtH = rows * 3;
    final (sampleX, sampleY) = _sampleMappers(srcW, srcH, tgtW, tgtH, _fit);

    for (var ry = 0; ry < rows; ry++) {
      for (var rx = 0; rx < cols; rx++) {
        final tgtCol = offset.col + rx;
        final tgtRow = offset.row + ry;
        if (tgtCol < 0 ||
            tgtCol >= buffer.size.cols ||
            tgtRow < 0 ||
            tgtRow >= buffer.size.rows) {
          continue;
        }

        final px = rx * 2;
        final py = ry * 3;
        // Order matches the bit numbering above: TL, TR, ML, MR, BL, BR.
        final samples = <(int, int, int)?>[
          _samplePixel(sampleX, sampleY, px, py, srcW, srcH),
          _samplePixel(sampleX, sampleY, px + 1, py, srcW, srcH),
          _samplePixel(sampleX, sampleY, px, py + 1, srcW, srcH),
          _samplePixel(sampleX, sampleY, px + 1, py + 1, srcW, srcH),
          _samplePixel(sampleX, sampleY, px, py + 2, srcW, srcH),
          _samplePixel(sampleX, sampleY, px + 1, py + 2, srcW, srcH),
        ];
        var nonNull = 0;
        for (final s in samples) {
          if (s != null) nonNull++;
        }
        if (nonNull == 0) continue;

        var bestPattern = 0x3F;
        var bestErr = double.infinity;
        var bestAr = 0.0, bestAg = 0.0, bestAb = 0.0;
        var bestBr = 0.0, bestBg = 0.0, bestBb = 0.0;

        for (var pattern = 0; pattern <= 63; pattern++) {
          var aR = 0.0, aG = 0.0, aB = 0.0, aN = 0;
          var bR = 0.0, bG = 0.0, bB = 0.0, bN = 0;
          for (var i = 0; i < 6; i++) {
            final s = samples[i];
            if (s == null) continue;
            final isA = ((pattern >> i) & 1) == 1;
            if (isA) {
              aR += s.$1;
              aG += s.$2;
              aB += s.$3;
              aN++;
            } else {
              bR += s.$1;
              bG += s.$2;
              bB += s.$3;
              bN++;
            }
          }
          double aMr, aMg, aMb, bMr, bMg, bMb;
          if (aN == 0) {
            aMr = bR / bN;
            aMg = bG / bN;
            aMb = bB / bN;
            bMr = aMr;
            bMg = aMg;
            bMb = aMb;
          } else if (bN == 0) {
            bMr = aR / aN;
            bMg = aG / aN;
            bMb = aB / aN;
            aMr = bMr;
            aMg = bMg;
            aMb = bMb;
          } else {
            aMr = aR / aN;
            aMg = aG / aN;
            aMb = aB / aN;
            bMr = bR / bN;
            bMg = bG / bN;
            bMb = bB / bN;
          }

          var err = 0.0;
          for (var i = 0; i < 6; i++) {
            final s = samples[i];
            if (s == null) continue;
            final isA = ((pattern >> i) & 1) == 1;
            final dr = s.$1 - (isA ? aMr : bMr);
            final dg = s.$2 - (isA ? aMg : bMg);
            final db = s.$3 - (isA ? aMb : bMb);
            err += dr * dr + dg * dg + db * db;
          }
          if (err < bestErr) {
            bestErr = err;
            bestPattern = pattern;
            bestAr = aMr;
            bestAg = aMg;
            bestAb = aMb;
            bestBr = bMr;
            bestBg = bMg;
            bestBb = bMb;
          }
        }

        final glyph = _sextantGlyph(bestPattern);
        final (qAr, qAg, qAb, _, _, _) = _quantize((
          bestAr,
          bestAg,
          bestAb,
        ), _colorMode);
        final (qBr, qBg, qBb, _, _, _) = _quantize((
          bestBr,
          bestBg,
          bestBb,
        ), _colorMode);
        final fg = _packColor(qAr, qAg, qAb, _colorMode);
        final bg = _packColor(qBr, qBg, qBb, _colorMode);

        buffer.writeGrapheme(
          CellOffset(tgtCol, tgtRow),
          glyph,
          style: CellStyle(foreground: fg, background: bg),
        );
      }
    }
  }

  /// Unicode 13 (Symbols for Legacy Computing) reserves 60 codepoints
  /// for sextants — patterns 1..62 minus the four already-existing
  /// patterns 21 (left half), 42 (right half), and 0/63 (space/full).
  /// Returns the glyph for any 6-bit pattern.
  String _sextantGlyph(int pattern) {
    if (pattern == 0) return ' ';
    if (pattern == 21) return '▌'; // ▌ LEFT HALF BLOCK
    if (pattern == 42) return '▐'; // ▐ RIGHT HALF BLOCK
    if (pattern == 63) return '█'; // █ FULL BLOCK
    // The remaining 60 patterns map sequentially into U+1FB00..U+1FB3B,
    // skipping the four codepoints above in source numbering. So we
    // subtract 1 for the missing pattern 0, and another 1 each as we
    // pass 21 and 42.
    var offset = pattern - 1;
    if (pattern > 21) offset -= 1;
    if (pattern > 42) offset -= 1;
    return String.fromCharCode(0x1FB00 + offset);
  }

  /// Paints at braille density: 2 cols × 4 rows of sub-pixels per cell
  /// via the 8 braille dots. Unlike quarter/sextant we don't search
  /// for a best-fit pattern — braille glyphs are monochrome (no two-
  /// color split inside a single cell), so each sub-pixel is just
  /// "lit" or "unlit" by a luminance threshold. The cell's foreground
  /// gets the *average* color of the lit sub-pixels; the background
  /// stays the surface default.
  ///
  /// Dot bit layout per Unicode 6429 (braille block U+2800..U+28FF):
  ///   col 0          col 1
  ///   row 0: bit 0   bit 3
  ///   row 1: bit 1   bit 4
  ///   row 2: bit 2   bit 5
  ///   row 3: bit 6   bit 7
  /// Codepoint = U+2800 + pattern.
  void _paintBraille(CellBuffer buffer, CellOffset offset, int cols, int rows) {
    final srcW = _decoded.width;
    final srcH = _decoded.height;
    final tgtW = cols * 2;
    final tgtH = rows * 4;
    final (sampleX, sampleY) = _sampleMappers(srcW, srcH, tgtW, tgtH, _fit);

    // Bit index per (col-in-cell, row-in-cell): the layout above.
    const bitIndex = <List<int>>[
      [0, 1, 2, 6], // col 0
      [3, 4, 5, 7], // col 1
    ];

    for (var ry = 0; ry < rows; ry++) {
      for (var rx = 0; rx < cols; rx++) {
        final tgtCol = offset.col + rx;
        final tgtRow = offset.row + ry;
        if (tgtCol < 0 ||
            tgtCol >= buffer.size.cols ||
            tgtRow < 0 ||
            tgtRow >= buffer.size.rows) {
          continue;
        }
        final px = rx * 2;
        final py = ry * 4;

        var pattern = 0;
        var rSum = 0, gSum = 0, bSum = 0, lit = 0;
        for (var dx = 0; dx < 2; dx++) {
          for (var dy = 0; dy < 4; dy++) {
            final s = _samplePixel(
              sampleX,
              sampleY,
              px + dx,
              py + dy,
              srcW,
              srcH,
            );
            if (s == null) continue;
            // "Is this pixel meaningfully drawn?" The right question for
            // line-art / sparkline use, which is what braille is for.
            // Luma weighting would treat saturated red (luma 76) as dark,
            // wrong for visible-on-black drawings. Max-channel ≥ 64
            // catches any non-near-black pixel as lit.
            final maxChannel = s.$1 > s.$2
                ? (s.$1 > s.$3 ? s.$1 : s.$3)
                : (s.$2 > s.$3 ? s.$2 : s.$3);
            if (maxChannel >= 64) {
              pattern |= 1 << bitIndex[dx][dy];
              rSum += s.$1;
              gSum += s.$2;
              bSum += s.$3;
              lit++;
            }
          }
        }
        if (pattern == 0) continue; // every sub-pixel dark → leave empty
        final glyph = String.fromCharCode(0x2800 + pattern);
        final (qr, qg, qb, _, _, _) = _quantize((
          rSum / lit,
          gSum / lit,
          bSum / lit,
        ), _colorMode);
        final fg = _packColor(qr, qg, qb, _colorMode);
        buffer.writeGrapheme(
          CellOffset(tgtCol, tgtRow),
          glyph,
          style: CellStyle(foreground: fg),
        );
      }
    }
  }

  /// Emits the image via the DEC Sixel protocol — terminal renders
  /// actual pixels. Targets a default cell-pixel grid of 10×20
  /// (a sensible average across modern terminal cell sizes; the
  /// terminal scales the emitted image to its real cell dimensions
  /// since the raster attributes carry our chosen pixel extents).
  /// A future refinement will probe `CSI 14 t` for the active
  /// terminal's pixel-per-cell dimensions and adapt the encoding
  /// resolution accordingly.
  ///
  /// Pipeline:
  ///   1. Resize the source to (cols·10, rows·20) — `fit: fill`
  ///      semantics by default. `fit: contain` / `cover` are honored
  ///      by letterboxing or cropping via a sample-and-stamp pass
  ///      onto a black canvas.
  ///   2. Run a Neural-net quantizer for 128 palette colors.
  ///   3. Encode 6-pixel-tall bands with per-color column masks,
  ///      RLE-compressing runs of identical sixel bytes.
  void _paintSixel(CellBuffer buffer, CellOffset offset, int cols, int rows) {
    const cellPxW = 10;
    const cellPxH = 20;
    final tgtW = cols * cellPxW;
    final tgtH = rows * cellPxH;

    // Build the target pixel buffer with the user's chosen fit.
    final resized = _resizeForSixel(tgtW, tgtH);

    // Quantize to a 128-color palette. 128 is a good middle ground:
    // enough fidelity for photos / logos, small enough that the
    // palette emission stays compact (~16 bytes per color).
    final quantizer = img.NeuralQuantizer(resized, numberOfColors: 128);
    final indexed = quantizer.getIndexImage(resized);
    final palette = quantizer.palette;

    final sixel = _encodeSixel(indexed, palette, tgtW, tgtH);
    _writeProtocolRegion(buffer, offset, sixel, cols, rows);
  }

  /// Builds the pixel canvas to feed the Sixel quantizer. Honors
  /// `_fit` so contain / cover behave like their cell-grid
  /// counterparts. `none` centers the source at its native resolution
  /// (which may exceed the target on large source images — clipping
  /// is fine, the rest is just black canvas).
  img.Image _resizeForSixel(int tgtW, int tgtH) {
    final srcW = _decoded.width;
    final srcH = _decoded.height;

    // Pick a (dispW, dispH, ox, oy) window into the target where the
    // source pixels actually land. Pixels outside that window stay
    // at the canvas default (zero / black).
    int dispW, dispH, ox, oy;
    switch (_fit) {
      case ImageFit.fill:
        return img.copyResize(
          _decoded,
          width: tgtW,
          height: tgtH,
          interpolation: img.Interpolation.linear,
        );
      case ImageFit.contain:
        final scale = (tgtW / srcW < tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
        dispW = (srcW * scale).round().clamp(1, tgtW);
        dispH = (srcH * scale).round().clamp(1, tgtH);
        ox = (tgtW - dispW) ~/ 2;
        oy = (tgtH - dispH) ~/ 2;
      case ImageFit.cover:
        final scale = (tgtW / srcW > tgtH / srcH) ? tgtW / srcW : tgtH / srcH;
        dispW = (srcW * scale).round();
        dispH = (srcH * scale).round();
        ox = (tgtW - dispW) ~/ 2;
        oy = (tgtH - dispH) ~/ 2;
      case ImageFit.none:
        dispW = srcW;
        dispH = srcH;
        ox = (tgtW - dispW) ~/ 2;
        oy = (tgtH - dispH) ~/ 2;
    }

    final scaled = img.copyResize(
      _decoded,
      width: dispW,
      height: dispH,
      interpolation: img.Interpolation.linear,
    );
    final canvas = img.Image(width: tgtW, height: tgtH, numChannels: 3);
    final bg = _backgroundColor?.toRgb();
    if (bg != null) {
      img.fill(canvas, color: img.ColorRgb8(bg.r, bg.g, bg.b));
    }
    img.compositeImage(canvas, scaled, dstX: ox, dstY: oy);
    return canvas;
  }

  /// Encodes a single-channel indexed image into a Sixel byte stream.
  /// Caller is responsible for already having sized [indexed] to the
  /// final on-screen pixel dimensions; the encoder just translates
  /// pixels → DCS bytes.
  String _encodeSixel(
    img.Image indexed,
    img.Palette palette,
    int width,
    int height,
  ) {
    final buf = StringBuffer();
    // DCS introducer. `q` is the Sixel control. No parameters means
    // the terminal applies its default aspect / background settings.
    buf.write('\x1BPq');
    // Raster attributes: pan/pad of 1:1 (square pixels), Ph/Pv =
    // emitted image extent. Terminals use this to scale into cell
    // space.
    buf.write('"1;1;$width;$height');

    // Palette definitions: `# Pc ; 2 ; R ; G ; B` per color, 0..100.
    final numColors = palette.numColors;
    for (var i = 0; i < numColors; i++) {
      final r = (palette.getRed(i) * 100 / 255).round().clamp(0, 100);
      final g = (palette.getGreen(i) * 100 / 255).round().clamp(0, 100);
      final b = (palette.getBlue(i) * 100 / 255).round().clamp(0, 100);
      buf.write('#$i;2;$r;$g;$b');
    }

    // Per 6-row band: for each palette color appearing in the band,
    // emit a color-select then a per-column 6-bit mask. Sort colors
    // for deterministic output (the wire bytes are visible in tests).
    for (var bandY = 0; bandY < height; bandY += 6) {
      final bandH = (height - bandY < 6) ? height - bandY : 6;

      final colorsInBand = <int>{};
      for (var y = bandY; y < bandY + bandH; y++) {
        for (var x = 0; x < width; x++) {
          colorsInBand.add(indexed.getPixel(x, y).r.toInt());
        }
      }
      final sorted = colorsInBand.toList()..sort();

      var first = true;
      for (final color in sorted) {
        // Carriage return resets to column 0 within the same band so
        // subsequent colors overlay onto the same pixel row group.
        if (!first) buf.write(r'$');
        first = false;
        buf.write('#$color');

        // Build the column sequence as sixel bytes, RLE-compressing
        // runs of identical bytes via `!Pn X`. `!Pn X` consumes
        // 2 + len(Pn) chars; runs of 4+ save bytes.
        var prevByte = -1;
        var runLen = 0;

        void flushRun() {
          if (runLen == 0) return;
          if (runLen >= 4) {
            buf.write('!$runLen');
            buf.writeCharCode(prevByte);
          } else {
            for (var i = 0; i < runLen; i++) {
              buf.writeCharCode(prevByte);
            }
          }
          runLen = 0;
        }

        for (var x = 0; x < width; x++) {
          var mask = 0;
          for (var by = 0; by < bandH; by++) {
            final y = bandY + by;
            if (indexed.getPixel(x, y).r.toInt() == color) {
              mask |= (1 << by);
            }
          }
          final byte = 0x3F + mask; // sixel byte is in '?'..'~' range
          if (byte == prevByte) {
            runLen++;
          } else {
            flushRun();
            prevByte = byte;
            runLen = 1;
          }
        }
        flushRun();
      }

      // Advance to next 6-row band (no `-` after the final band — the
      // terminator handles end-of-image).
      if (bandY + 6 < height) buf.write('-');
    }

    // ST terminator.
    buf.write('\x1B\\');
    return buf.toString();
  }

  /// Emits the image via iTerm2's inline-image protocol — terminal
  /// renders actual pixels via an OSC 1337 escape carrying a base64
  /// PNG payload. `inline=1` makes it display rather than download;
  /// `width`/`height` in cell units constrain the displayed size to
  /// our allotted box; `preserveAspectRatio=0` lets us own the fit
  /// math (we already laid out for the right shape, the terminal
  /// shouldn't second-guess us).
  ///
  /// Unlike Kitty there's no chunking — the entire payload rides in
  /// one OSC sequence terminated by BEL.
  void _paintIterm2(CellBuffer buffer, CellOffset offset, int cols, int rows) {
    // Resolve the fit into a sub-rect + crop (see _paintKitty); the sub-rect is
    // aspect-correct, so preserveAspectRatio=0 fills it without distortion.
    final f = _resolveFit(_decoded.width, _decoded.height, cols, rows, _fit);
    final png = _fitPng(f);
    final b64 = base64.encode(png);
    final out =
        '\x1B]1337;File=inline=1;size=${png.length};'
        'width=${f.cols};height=${f.rows};preserveAspectRatio=0:$b64\x07';
    _writeProtocolRegion(buffer, CellOffset(offset.col + f.col, offset.row + f.row),
        out, f.cols, f.rows);
  }

  /// Hand off a fully-assembled protocol payload to the cell buffer,
  /// applying the tmux/screen passthrough envelope first when the
  /// surface needs it. tmux drops unknown DCS / APC sequences by
  /// default; the envelope re-emits them via `ESC P tmux ; payload
  /// ESC \\`, where every embedded `ESC` is doubled. Modern tmux 3.3+
  /// users can opt out by setting `allow-passthrough on` and ignoring
  /// this branch entirely — until they do, this is the only way to
  /// land Kitty / Sixel / iTerm2 bytes in the host terminal.
  void _writeProtocolRegion(
    CellBuffer buffer,
    CellOffset offset,
    String payload,
    int cols,
    int rows,
  ) {
    final bytes = _tmuxPassthrough ? _wrapForTmux(payload) : payload;
    buffer.writeProtocol(offset, bytes, width: cols, height: rows);
  }

  /// Wrap [payload] in tmux's passthrough envelope. Every embedded
  /// `ESC` is doubled so tmux's own DCS parser doesn't terminate on
  /// the payload's internal ST.
  String _wrapForTmux(String payload) {
    final doubled = payload.replaceAll('\x1B', '\x1B\x1B');
    return '\x1BPtmux;$doubled\x1B\\';
  }

  /// Samples the source rect covered by a single half-pixel at
  /// (rx, py)..(rx+1, py+1). For downscale (rect covers > 1 source
  /// pixel) averages all source pixels in the rect; for upscale
  /// (rect smaller than 1 source pixel) nearest-neighbors the center.
  /// Returns null if the rect has zero intersection with the source.
  (int, int, int)? _samplePixel(
    double Function(int) xMap,
    double Function(int) yMap,
    int rx,
    int py,
    int srcW,
    int srcH,
  ) {
    // Source rect this half-pixel covers — may extend outside the
    // source for letterboxed/offset fits.
    final sx0 = xMap(rx);
    final sx1 = xMap(rx + 1);
    final sy0 = yMap(py);
    final sy1 = yMap(py + 1);

    // Clip to source bounds. ceil() on the right edge — half-open
    // interval [ix0, ix1) — so a rect that JUST touches a source pixel
    // includes it.
    final ix0 = sx0.clamp(0.0, srcW.toDouble()).floor();
    final iy0 = sy0.clamp(0.0, srcH.toDouble()).floor();
    final ix1Raw = sx1.clamp(0.0, srcW.toDouble());
    final iy1Raw = sy1.clamp(0.0, srcH.toDouble());
    final ix1 = ix1Raw.ceil();
    final iy1 = iy1Raw.ceil();

    if (ix0 >= ix1 || iy0 >= iy1) return null; // zero intersection

    // Area-weighted average over the clipped source rect. We weight
    // each source pixel by the fraction of it that actually overlaps
    // the target half-pixel — without this an off-edge pixel that's
    // only 10%-covered contributes equally to the average as one fully
    // inside the rect, biasing colors at letterbox / cover edges.
    //
    // Alpha contributes to the weight too: a 50%-transparent pixel
    // contributes 50% as much as an opaque pixel of the same area.
    // Without this, alpha-edged sprites bleed unweighted color into
    // their soft margins instead of softening toward the background.
    var rSum = 0.0, gSum = 0.0, bSum = 0.0;
    var opaqueWeight = 0.0; // Σ(area · α/255) — coverage scaled by alpha
    var areaWeight = 0.0; // Σ(area)         — pure geometric overlap
    for (var y = iy0; y < iy1; y++) {
      final yLo = y > sy0 ? y.toDouble() : sy0;
      final yHi = (y + 1) < sy1 ? (y + 1).toDouble() : sy1;
      final wy = yHi - yLo;
      if (wy <= 0) continue;
      for (var x = ix0; x < ix1; x++) {
        final xLo = x > sx0 ? x.toDouble() : sx0;
        final xHi = (x + 1) < sx1 ? (x + 1).toDouble() : sx1;
        final wx = xHi - xLo;
        if (wx <= 0) continue;
        final p = _decoded.getPixel(x, y);
        final area = wx * wy;
        areaWeight += area;
        if (p.a == 0) continue;
        final w = area * (p.a / 255.0);
        rSum += p.r * w;
        gSum += p.g * w;
        bSum += p.b * w;
        opaqueWeight += w;
      }
    }
    if (areaWeight == 0) return null;

    final bg = _backgroundColor;
    if (bg == null) {
      // No compositing target — preserve v1 behavior: fully-transparent
      // samples drop out (returns null → empty cell), semitransparent
      // samples take the alpha-weighted mean of just the opaque
      // contribution. Acceptable when the surrounding cells are also
      // empty (no visible bleed).
      if (opaqueWeight == 0) return null;
      return (
        (rSum / opaqueWeight).round().clamp(0, 255),
        (gSum / opaqueWeight).round().clamp(0, 255),
        (bSum / opaqueWeight).round().clamp(0, 255),
      );
    }

    // Composite against the caller-supplied background:
    //   out = α·src + (1−α)·bg
    // where α is the area-weighted average alpha and src is the
    // alpha-pre-weighted average color. Falls back to all-bg when the
    // rect is fully transparent.
    final bgRgb = bg.toRgb();
    final alpha = opaqueWeight / areaWeight; // 0..1
    double srcR;
    double srcG;
    double srcB;
    if (opaqueWeight == 0) {
      srcR = bgRgb.r.toDouble();
      srcG = bgRgb.g.toDouble();
      srcB = bgRgb.b.toDouble();
    } else {
      srcR = rSum / opaqueWeight;
      srcG = gSum / opaqueWeight;
      srcB = bSum / opaqueWeight;
    }
    return (
      (alpha * srcR + (1 - alpha) * bgRgb.r).round().clamp(0, 255),
      (alpha * srcG + (1 - alpha) * bgRgb.g).round().clamp(0, 255),
      (alpha * srcB + (1 - alpha) * bgRgb.b).round().clamp(0, 255),
    );
  }
}

/// Destination cell rectangle (relative to the image box) plus the source-pixel
/// crop that a protocol paint path transmits, as resolved by
/// [RenderImage._resolveFit] for a given [ImageFit].
class _FitRect {
  const _FitRect(
    this.col,
    this.row,
    this.cols,
    this.rows,
    this.cropX,
    this.cropY,
    this.cropW,
    this.cropH,
  );

  final int col;
  final int row;
  final int cols;
  final int rows;
  final int cropX;
  final int cropY;
  final int cropW;
  final int cropH;
}
