import 'package:meta/meta.dart';

/// A terminal color expressed in one of three palettes.
///
/// The renderer chooses the closest representable color based on the
/// detected terminal capabilities (truecolor → indexed → 16-color).
@immutable
sealed class Color {
  const Color();

  /// Resolves this color to concrete RGB using the standard xterm palette
  /// (so [AnsiColor]/[IndexedColor] can be lightened, darkened, or mixed).
  RgbColor toRgb();
}

/// xterm's default 16-color palette as RGB. The shared reference for both
/// color matching (downsampling) and [Color.toRgb].
const List<List<int>> ansiPalette16 = [
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

/// The six per-channel levels of the 6×6×6 color cube (256-color indices
/// 16–231).
const List<int> cube256Levels = [0, 95, 135, 175, 215, 255];

/// One of the sixteen standard ANSI colors (0–15).
final class AnsiColor extends Color {
  const AnsiColor(this.index)
    : assert(index >= 0 && index < 16, 'AnsiColor index must be 0..15');

  final int index;

  @override
  RgbColor toRgb() {
    final c = ansiPalette16[index];
    return RgbColor(c[0], c[1], c[2]);
  }

  @override
  bool operator ==(Object other) => other is AnsiColor && other.index == index;
  @override
  int get hashCode => Object.hash(AnsiColor, index);
  @override
  String toString() => 'AnsiColor($index)';
}

/// A 256-color palette entry (0–255).
final class IndexedColor extends Color {
  const IndexedColor(this.index)
    : assert(index >= 0 && index < 256, 'IndexedColor index must be 0..255');

  final int index;

  @override
  RgbColor toRgb() {
    if (index < 16) {
      final c = ansiPalette16[index];
      return RgbColor(c[0], c[1], c[2]);
    }
    if (index < 232) {
      final n = index - 16;
      return RgbColor(
        cube256Levels[n ~/ 36],
        cube256Levels[(n ~/ 6) % 6],
        cube256Levels[n % 6],
      );
    }
    final v = 8 + 10 * (index - 232);
    return RgbColor(v, v, v);
  }

  @override
  bool operator ==(Object other) =>
      other is IndexedColor && other.index == index;
  @override
  int get hashCode => Object.hash(IndexedColor, index);
  @override
  String toString() => 'IndexedColor($index)';
}

/// A 24-bit RGB color.
final class RgbColor extends Color {
  const RgbColor(this.r, this.g, this.b)
    : assert(r >= 0 && r < 256, 'r must be 0..255'),
      assert(g >= 0 && g < 256, 'g must be 0..255'),
      assert(b >= 0 && b < 256, 'b must be 0..255');

  final int r;
  final int g;
  final int b;

  @override
  RgbColor toRgb() => this;

  /// Blends toward [other] by [t] (0 = unchanged, 1 = fully [other]).
  RgbColor mix(RgbColor other, double t) {
    final c = t.clamp(0.0, 1.0);
    int ch(int a, int b) => (a + (b - a) * c).round().clamp(0, 255);
    return RgbColor(ch(r, other.r), ch(g, other.g), ch(b, other.b));
  }

  /// Mixes toward white by [amount]. Predictable (linear), unlike a
  /// perceptual tonal remap — the hue is preserved.
  RgbColor lighten([double amount = 0.1]) =>
      mix(const RgbColor(255, 255, 255), amount);

  /// Mixes toward black by [amount].
  RgbColor darken([double amount = 0.1]) =>
      mix(const RgbColor(0, 0, 0), amount);

  @override
  bool operator ==(Object other) =>
      other is RgbColor && other.r == r && other.g == g && other.b == b;
  @override
  int get hashCode => Object.hash(RgbColor, r, g, b);
  @override
  String toString() => 'RgbColor($r, $g, $b)';
}

/// Named color constants, in the spirit of Flutter's `Colors` — saves you
/// from typing `RgbColor(220, 20, 60)` for "crimson." Two flavours:
///
///   - The eight standard ANSI names ([Colors.black], [Colors.red], …)
///     return [AnsiColor] entries. They respect the user's terminal
///     palette and downsample cleanly. Use these for *semantic* roles
///     (success, warning, dim text); the user's theme decides what they
///     look like.
///
///   - The handful of CSS-style aliases ([Colors.white], [Colors.gray],
///     [Colors.crimson], …) return [RgbColor] for cases where you want a
///     specific shade. Quantized down on 16/256-color terminals via the
///     usual cascade.
///
/// Want a one-off? `RgbColor(r, g, b)` still works — this class is for
/// the everyday case.
final class Colors {
  Colors._();

  // ---- The 8 standard ANSI colors (palette-aware) ------------------------
  static const Color black = AnsiColor(0);
  static const Color red = AnsiColor(1);
  static const Color green = AnsiColor(2);
  static const Color yellow = AnsiColor(3);
  static const Color blue = AnsiColor(4);
  static const Color magenta = AnsiColor(5);
  static const Color cyan = AnsiColor(6);
  static const Color white = AnsiColor(7);

  // ---- 8 bright ANSI variants -------------------------------------------
  static const Color brightBlack = AnsiColor(8);
  static const Color brightRed = AnsiColor(9);
  static const Color brightGreen = AnsiColor(10);
  static const Color brightYellow = AnsiColor(11);
  static const Color brightBlue = AnsiColor(12);
  static const Color brightMagenta = AnsiColor(13);
  static const Color brightCyan = AnsiColor(14);
  static const Color brightWhite = AnsiColor(15);

  /// Alias for [brightBlack] — every terminal renders bright-black as
  /// some shade of gray. The more readable name.
  static const Color gray = AnsiColor(8);

  /// British spelling — both spellings are common in source code.
  static const Color grey = AnsiColor(8);

  // ---- True-color named constants ---------------------------------------
  // Picked for usefulness, not exhaustiveness. Adds the colors people
  // actually reach for in app code: backgrounds, accents, status tints.

  /// Pure white at 24-bit truecolor (255, 255, 255). Distinct from
  /// [white] (which is the user's terminal "white," typically 192 or
  /// 240 depending on theme).
  static const Color pureWhite = RgbColor(255, 255, 255);
  static const Color pureBlack = RgbColor(0, 0, 0);

  // Material-inspired shades for accents.
  static const Color crimson = RgbColor(220, 20, 60);
  static const Color orange = RgbColor(255, 140, 0);
  static const Color amber = RgbColor(255, 191, 0);
  static const Color lime = RgbColor(50, 205, 50);
  static const Color teal = RgbColor(0, 180, 180);

  /// Cool spring-green accent (46, 230, 166) — the framework's default
  /// [ColorScheme.primary]. A high-legibility "terminal cyber" green that
  /// reads clearly on dark backgrounds and downsamples cleanly on 256/16-
  /// color terminals.
  static const Color mint = RgbColor(0x2E, 0xE6, 0xA6);
  static const Color azure = RgbColor(70, 130, 220);
  static const Color violet = RgbColor(138, 90, 220);
  static const Color pink = RgbColor(255, 105, 180);
  static const Color slate = RgbColor(112, 128, 144);
}

/// Visual attributes applied to a [Cell] in addition to its grapheme.
///
/// Each attribute is internally tri-state: unset (null), on, or
/// explicitly off. The public getters collapse that to a plain bool
/// (unset reads as off), so a resolved cell style is simple to consume.
/// The distinction only matters in [merge]: passing `bold: false` lets a
/// child style turn *off* an attribute it inherited, rather than only
/// being able to add to it.
@immutable
final class CellStyle {
  const CellStyle({
    this.foreground,
    this.background,
    bool? bold,
    bool? dim,
    bool? italic,
    bool? underline,
    bool? inverse,
    bool? strikethrough,
  }) : _bold = bold,
       _dim = dim,
       _italic = italic,
       _underline = underline,
       _inverse = inverse,
       _strikethrough = strikethrough;

  final Color? foreground;
  final Color? background;
  final bool? _bold;
  final bool? _dim;
  final bool? _italic;
  final bool? _underline;
  final bool? _inverse;
  final bool? _strikethrough;

  bool get bold => _bold ?? false;
  bool get dim => _dim ?? false;
  bool get italic => _italic ?? false;
  bool get underline => _underline ?? false;
  bool get inverse => _inverse ?? false;
  bool get strikethrough => _strikethrough ?? false;

  /// Raw tri-state attributes (null = unset, distinct from false). The
  /// resolved getters above collapse null to false for rendering; these
  /// preserve the distinction for exact serialization and inspection,
  /// since [operator ==] compares the raw fields.
  bool? get boldOrNull => _bold;
  bool? get dimOrNull => _dim;
  bool? get italicOrNull => _italic;
  bool? get underlineOrNull => _underline;
  bool? get inverseOrNull => _inverse;
  bool? get strikethroughOrNull => _strikethrough;

  static const CellStyle empty = CellStyle();

  CellStyle copyWith({
    Color? foreground,
    Color? background,
    bool? bold,
    bool? dim,
    bool? italic,
    bool? underline,
    bool? inverse,
    bool? strikethrough,
  }) {
    return CellStyle(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      bold: bold ?? _bold,
      dim: dim ?? _dim,
      italic: italic ?? _italic,
      underline: underline ?? _underline,
      inverse: inverse ?? _inverse,
      strikethrough: strikethrough ?? _strikethrough,
    );
  }

  /// Returns a new style with [other]'s *set* fields layered on top of
  /// this one. Colors and each attribute are taken from [other] when it
  /// sets them (on or off) and inherited from this otherwise — so an
  /// override can both add and remove attributes.
  CellStyle merge(CellStyle other) {
    return CellStyle(
      foreground: other.foreground ?? foreground,
      background: other.background ?? background,
      bold: other._bold ?? _bold,
      dim: other._dim ?? _dim,
      italic: other._italic ?? _italic,
      underline: other._underline ?? _underline,
      inverse: other._inverse ?? _inverse,
      strikethrough: other._strikethrough ?? _strikethrough,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CellStyle &&
      other.foreground == foreground &&
      other.background == background &&
      other._bold == _bold &&
      other._dim == _dim &&
      other._italic == _italic &&
      other._underline == _underline &&
      other._inverse == _inverse &&
      other._strikethrough == _strikethrough;

  @override
  int get hashCode => Object.hash(
    foreground,
    background,
    _bold,
    _dim,
    _italic,
    _underline,
    _inverse,
    _strikethrough,
  );

  @override
  String toString() {
    final flags = <String>[
      if (bold) 'bold',
      if (dim) 'dim',
      if (italic) 'italic',
      if (underline) 'underline',
      if (inverse) 'inverse',
      if (strikethrough) 'strikethrough',
    ];
    return 'CellStyle('
        'fg=$foreground, bg=$background'
        '${flags.isEmpty ? '' : ', ${flags.join(',')}'})';
  }
}

/// How a [Cell] participates in a (possibly wide) grapheme.
///
/// `empty` cells have no glyph. `leading` cells own the grapheme and may
/// occupy one or two columns. `continuation` cells fill the second column
/// of a wide grapheme; their `grapheme` is always null.
enum CellRole {
  empty,
  leading,
  continuation,

  /// A cell whose visual is owned by an out-of-band overlay — an inline
  /// image placement recorded on the buffer ([CellBuffer.imagePlacements])
  /// and rendered by the PRESENTER (a terminal graphics protocol, a DOM
  /// `<img>`), never by cell content. Escape bytes never ride in a cell;
  /// presenters read the placement list instead.
  ///
  /// The renderer paints no glyph for these cells, but it DOES clear the
  /// cell to a blank when it transitions from content to overlay — so
  /// stale text can't survive in an image's letterbox bars (which the
  /// image encoder leaves unpainted). An overlay cell that was already
  /// blank (or overlay) the previous frame emits nothing, so an unchanging
  /// image costs zero bytes.
  overlay,
}

/// One terminal cell: the smallest addressable unit in the cell grid.
@immutable
final class Cell {
  const Cell.empty()
    : grapheme = null,
      role = CellRole.empty,
      style = CellStyle.empty;

  const Cell.leading({
    required String this.grapheme,
    this.style = CellStyle.empty,
  }) : role = CellRole.leading;

  const Cell.continuation({this.style = CellStyle.empty})
    : grapheme = null,
      role = CellRole.continuation;

  /// A cell inside an inline-image placement's rectangle. Carries no
  /// grapheme and no style — the overlay's pixels own the region.
  const Cell.overlay()
    : grapheme = null,
      role = CellRole.overlay,
      style = CellStyle.empty;

  /// The grapheme owned by this cell. Always null on `empty`,
  /// `continuation`, and `overlay` cells.
  final String? grapheme;

  /// This cell's role in its (possibly wide) grapheme.
  final CellRole role;

  /// Visual style applied to the cell. Always empty for `overlay`
  /// cells — the overlay's pixels carry their own coloring.
  final CellStyle style;

  @override
  bool operator ==(Object other) =>
      other is Cell &&
      other.grapheme == grapheme &&
      other.role == role &&
      other.style == style;

  @override
  int get hashCode => Object.hash(grapheme, role, style);

  @override
  String toString() {
    switch (role) {
      case CellRole.empty:
        return 'Cell.empty';
      case CellRole.continuation:
        return 'Cell.continuation';
      case CellRole.leading:
        return 'Cell.leading("$grapheme")';
      case CellRole.overlay:
        return 'Cell.overlay';
    }
  }
}
