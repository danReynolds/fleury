import 'package:meta/meta.dart';

/// A state used internally while resolving a value from [CellStyle.state].
///
/// Widgets use only the states that make sense for their surface. For example,
/// a button never becomes [selected], while a checkbox uses [selected] for its
/// checked value. Unsupported states are simply never emitted.
enum CellStyleState { hovered, focused, selected, disabled, invalid }

const List<CellStyleState> _cellStyleStatePaintOrder = [
  CellStyleState.selected,
  CellStyleState.hovered,
  CellStyleState.focused,
  CellStyleState.invalid,
];

CellStyle _plainCellStyle(CellStyle style) {
  var result = style;
  while (result is _StatefulCellStyle) {
    result = result.base;
  }
  return result;
}

/// Internal bridge for renderers that must store only concrete cell paint.
CellStyle plainCellStyle(CellStyle style) => _plainCellStyle(style);

/// Whether [style] contains unresolved control-state entries.
bool hasCellStyleStates(CellStyle style) => style is _StatefulCellStyle;

/// Resolves [cascade] from lowest to highest priority.
///
/// Base styles merge in order. For each active state, the highest-priority
/// non-null patch wins as a unit and is then merged over the base. An explicit
/// [CellStyle.none] therefore suppresses a lower-priority state cue. Disabled
/// is exclusive of transient/value states.
CellStyle resolveCellStyle({
  required Iterable<CellStyle?> cascade,
  Set<CellStyleState> states = const {},
}) {
  final layers = [for (final style in cascade) ?style];
  var result = CellStyle.none;
  for (final layer in layers) {
    result = result.merge(_plainCellStyle(layer));
  }

  final active = states.contains(CellStyleState.disabled)
      ? const [CellStyleState.disabled]
      : _cellStyleStatePaintOrder.where(states.contains);
  for (final state in active) {
    CellStyle? patch;
    for (final layer in layers) {
      if (layer is _StatefulCellStyle) {
        patch = layer._styleFor(state) ?? patch;
      }
    }
    if (patch != null) {
      result = result.merge(_plainCellStyle(patch));
    }
  }
  return result;
}

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
    Color? foreground,
    Color? background,
    bool? bold,
    bool? dim,
    bool? italic,
    bool? underline,
    bool? inverse,
    bool? strikethrough,
    String? linkUri,
  }) : _foreground = foreground,
       _background = background,
       _bold = bold,
       _dim = dim,
       _italic = italic,
       _underline = underline,
       _inverse = inverse,
       _strikethrough = strikethrough,
       _linkUri = linkUri;

  /// A cell style whose paint varies with the control's current state.
  ///
  /// [base] is also the fallback when this value is used by a non-control API
  /// such as `Text(style:)`. A null state entry inherits the corresponding
  /// theme/widget default; [CellStyle.none] explicitly suppresses it.
  const factory CellStyle.state({
    CellStyle base,
    CellStyle? hovered,
    CellStyle? focused,
    CellStyle? selected,
    CellStyle? disabled,
    CellStyle? invalid,
  }) = _StatefulCellStyle._;

  final Color? _foreground;
  final Color? _background;
  final bool? _bold;
  final bool? _dim;
  final bool? _italic;
  final bool? _underline;
  final bool? _inverse;
  final bool? _strikethrough;

  /// OSC 8 hyperlink target for this run, or null. Emitted by the ANSI
  /// renderer when the surface supports hyperlinks; carried on the wire for
  /// the browser (Stage 2). Set only by trusted widget code — never from
  /// untrusted output, which the sanitizer strips before it reaches a cell.
  ///
  /// Unlike the bool attributes this is a plain null-or-value field (there is
  /// no "explicitly off"): absence is null, presence is the URI. It is a
  /// *non-visual* attribute — the SGR encoders never read it and `ESC[0m` does
  /// not close it — so the renderer reasons about it separately from
  /// [sameVisualStyleAs] / [isVisuallyEmpty]. It still participates in
  /// [operator ==] and [hashCode], which is REQUIRED: the diff renderer and the
  /// wire style-dedupe key on style equality, and merging two cells that differ
  /// only by their link would silently drop the link.
  final String? _linkUri;

  Color? get foreground => _foreground;
  Color? get background => _background;
  bool get bold => boldOrNull ?? false;
  bool get dim => dimOrNull ?? false;
  bool get italic => italicOrNull ?? false;
  bool get underline => underlineOrNull ?? false;

  /// Whether inverse video swaps the effective foreground and background.
  ///
  /// Terminal renderers emit the standard SGR reverse-video attribute; other
  /// renderers reproduce the same visual exchange.
  bool get inverse => inverseOrNull ?? false;
  bool get strikethrough => strikethroughOrNull ?? false;

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
  String? get linkUri => _linkUri;

  /// No paint overrides.
  ///
  /// As a state entry in [CellStyle.state], this deliberately suppresses an
  /// inherited cue for that state.
  static const CellStyle none = CellStyle();

  CellStyle copyWith({
    Color? foreground,
    Color? background,
    bool? bold,
    bool? dim,
    bool? italic,
    bool? underline,
    bool? inverse,
    bool? strikethrough,
    String? linkUri,
  }) {
    return CellStyle(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      bold: bold ?? boldOrNull,
      dim: dim ?? dimOrNull,
      italic: italic ?? italicOrNull,
      underline: underline ?? underlineOrNull,
      inverse: inverse ?? inverseOrNull,
      strikethrough: strikethrough ?? strikethroughOrNull,
      linkUri: linkUri ?? this.linkUri,
    );
  }

  /// Returns a new style with [other]'s *set* fields layered on top of
  /// this one. Colors and each attribute are taken from [other] when it
  /// sets them (on or off) and inherited from this otherwise — so an
  /// override can both add and remove attributes.
  CellStyle merge(CellStyle other) {
    if (other is _StatefulCellStyle) {
      return other._withBase(merge(other.base));
    }
    return CellStyle(
      foreground: other.foreground ?? foreground,
      background: other.background ?? background,
      bold: other.boldOrNull ?? boldOrNull,
      dim: other.dimOrNull ?? dimOrNull,
      italic: other.italicOrNull ?? italicOrNull,
      underline: other.underlineOrNull ?? underlineOrNull,
      inverse: other.inverseOrNull ?? inverseOrNull,
      strikethrough: other.strikethroughOrNull ?? strikethroughOrNull,
      linkUri: other.linkUri ?? linkUri,
    );
  }

  @override
  bool operator ==(Object other) =>
      // Fast-path the equal-style hot path: a run of linked cells shares one
      // CellStyle instance, and the diff renderer / wire dedupe compare styles
      // constantly. This resolves most in-run comparisons before any field is
      // read, offsetting the extra `linkUri` compare below.
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is CellStyle &&
          other.foreground == foreground &&
          other.background == background &&
          other.boldOrNull == boldOrNull &&
          other.dimOrNull == dimOrNull &&
          other.italicOrNull == italicOrNull &&
          other.underlineOrNull == underlineOrNull &&
          other.inverseOrNull == inverseOrNull &&
          other.strikethroughOrNull == strikethroughOrNull &&
          // Trailing: cheapest to reach only after the visual fields match, and
          // REQUIRED so link-differing cells don't merge (see [linkUri]).
          other.linkUri == linkUri;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    foreground,
    background,
    boldOrNull,
    dimOrNull,
    italicOrNull,
    underlineOrNull,
    inverseOrNull,
    strikethroughOrNull,
    linkUri,
  );

  /// Whether this and [other] render identically, IGNORING [linkUri]. The link
  /// is a non-visual OSC 8 concern the ANSI renderer emits separately (and
  /// `ESC[0m` does not close), so the renderer compares visual style here to
  /// drive SGR — a link-only change must not trigger a style reset, and with
  /// hyperlinks disabled the link must not affect output at all. For a
  /// link-free style this is exactly [operator ==].
  bool sameVisualStyleAs(CellStyle other) =>
      identical(this, other) ||
      (foreground == other.foreground &&
          background == other.background &&
          boldOrNull == other.boldOrNull &&
          dimOrNull == other.dimOrNull &&
          italicOrNull == other.italicOrNull &&
          underlineOrNull == other.underlineOrNull &&
          inverseOrNull == other.inverseOrNull &&
          strikethroughOrNull == other.strikethroughOrNull);

  /// Whether every *visual* attribute is unset (so the style emits no SGR),
  /// IGNORING [linkUri]. For a link-free style this matches `== CellStyle.none`;
  /// a link-only style is visually empty (it emits an OSC 8 link but no SGR).
  ///
  /// Defined in terms of [sameVisualStyleAs] against the const [none] singleton
  /// (no per-call allocation) so the visual field list lives in exactly one
  /// place — a future visual attribute can't be forgotten here.
  bool get isVisuallyEmpty => sameVisualStyleAs(none);

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
        '${flags.isEmpty ? '' : ', ${flags.join(',')}'}'
        '${linkUri == null ? '' : ', link=$linkUri'})';
  }
}

/// The immutable value created by [CellStyle.state].
///
/// It remains a [CellStyle] so existing `style:` call sites stay lightweight.
/// Its inherited paint fields mirror [base], providing a deterministic
/// fallback in APIs that do not resolve control state.
@immutable
final class _StatefulCellStyle extends CellStyle {
  const _StatefulCellStyle._({
    this.base = CellStyle.none,
    this.hovered,
    this.focused,
    this.selected,
    this.disabled,
    this.invalid,
  }) : assert(base is! _StatefulCellStyle, 'base must be a plain CellStyle'),
       super();

  final CellStyle base;
  final CellStyle? hovered;
  final CellStyle? focused;
  final CellStyle? selected;
  final CellStyle? disabled;
  final CellStyle? invalid;

  @override
  Color? get foreground => base.foreground;

  @override
  Color? get background => base.background;

  @override
  bool? get boldOrNull => base.boldOrNull;

  @override
  bool? get dimOrNull => base.dimOrNull;

  @override
  bool? get italicOrNull => base.italicOrNull;

  @override
  bool? get underlineOrNull => base.underlineOrNull;

  @override
  bool? get inverseOrNull => base.inverseOrNull;

  @override
  bool? get strikethroughOrNull => base.strikethroughOrNull;

  @override
  String? get linkUri => base.linkUri;

  CellStyle? _styleFor(CellStyleState state) => switch (state) {
    CellStyleState.hovered => hovered,
    CellStyleState.focused => focused,
    CellStyleState.selected => selected,
    CellStyleState.disabled => disabled,
    CellStyleState.invalid => invalid,
  };

  _StatefulCellStyle _withBase(CellStyle nextBase) => _StatefulCellStyle._(
    base: nextBase,
    hovered: hovered,
    focused: focused,
    selected: selected,
    disabled: disabled,
    invalid: invalid,
  );

  @override
  _StatefulCellStyle copyWith({
    Color? foreground,
    Color? background,
    bool? bold,
    bool? dim,
    bool? italic,
    bool? underline,
    bool? inverse,
    bool? strikethrough,
    String? linkUri,
  }) => _withBase(
    base.copyWith(
      foreground: foreground,
      background: background,
      bold: bold,
      dim: dim,
      italic: italic,
      underline: underline,
      inverse: inverse,
      strikethrough: strikethrough,
      linkUri: linkUri,
    ),
  );

  @override
  _StatefulCellStyle merge(CellStyle other) {
    if (other is _StatefulCellStyle) {
      return _StatefulCellStyle._(
        base: base.merge(other.base),
        hovered: other.hovered ?? hovered,
        focused: other.focused ?? focused,
        selected: other.selected ?? selected,
        disabled: other.disabled ?? disabled,
        invalid: other.invalid ?? invalid,
      );
    }
    return _withBase(base.merge(other));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StatefulCellStyle &&
          other.base == base &&
          other.hovered == hovered &&
          other.focused == focused &&
          other.selected == selected &&
          other.disabled == disabled &&
          other.invalid == invalid;

  @override
  int get hashCode => Object.hash(
    _StatefulCellStyle,
    base,
    hovered,
    focused,
    selected,
    disabled,
    invalid,
  );

  @override
  String toString() =>
      'CellStyle.state(base: $base, hovered: $hovered, focused: $focused, '
      'selected: $selected, disabled: $disabled, invalid: $invalid)';
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
      style = CellStyle.none;

  const Cell.leading({
    required String this.grapheme,
    this.style = CellStyle.none,
  }) : role = CellRole.leading;

  const Cell.continuation({this.style = CellStyle.none})
    : grapheme = null,
      role = CellRole.continuation;

  /// A cell inside an inline-image placement's rectangle. Carries no
  /// grapheme and no style — the overlay's pixels own the region.
  const Cell.overlay()
    : grapheme = null,
      role = CellRole.overlay,
      style = CellStyle.none;

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
