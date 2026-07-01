import 'package:fleury/fleury_core.dart';

/// Large-numeral display for clocks, timers, counters — the "calculator
/// face" look popularized by Textual's Digits widget. Each digit is drawn
/// as a 5-row glyph from block characters; `:` and ` ` are supported for
/// time-of-day strings.
///
/// ```dart
/// Digits('12:34', color: theme.colorScheme.primary)
/// ```
///
/// Throws if [text] contains a character outside `[0-9:.\- ]`.
class Digits extends StatelessWidget {
  const Digits(
    this.text, {
    super.key,
    this.style,
    this.color,
    this.offGlyph,
    this.semanticLabel = 'Digits',
  });

  final String text;
  final CellStyle? style;
  final Color? color;

  /// When set, "off" segments are painted with this dim glyph (e.g. `·` or
  /// `░`) for the two-tone calculator / flip-clock look, and so the digit
  /// shape reads on bright backgrounds. Default null leaves them blank.
  final String? offGlyph;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved =
        style ?? CellStyle(foreground: color ?? theme.colorScheme.primary);
    return Semantics(
      role: SemanticRole.text,
      label: semanticLabel,
      value: text,
      child: _RawDigits(text: text, style: resolved, offGlyph: offGlyph),
    );
  }
}

class _RawDigits extends LeafRenderObjectWidget {
  const _RawDigits({
    required this.text,
    required this.style,
    required this.offGlyph,
  });

  final String text;
  final CellStyle style;
  final String? offGlyph;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDigits(text: text, style: style, offGlyph: offGlyph);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDigits renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..offGlyph = offGlyph;
  }
}

/// Render object behind [Digits]. See its docs.
class RenderDigits extends RenderObject {
  RenderDigits({
    required String text,
    required CellStyle style,
    required String? offGlyph,
  }) : _text = text,
       _style = style,
       _offGlyph = offGlyph;

  String? _offGlyph;
  set offGlyph(String? v) {
    if (_offGlyph == v) return;
    _offGlyph = v;
    markNeedsPaintOnly();
  }

  String _text;
  set text(String v) {
    if (_text == v) return;
    final layoutChanged = _digitsWidth(_text) != _digitsWidth(v);
    _text = v;
    _cachedGlyphs = null;
    if (layoutChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaintOnly();
    }
  }

  CellStyle _style;
  set style(CellStyle v) {
    if (_style == v) return;
    _style = v;
    markNeedsPaintOnly();
  }

  // Each glyph is exactly _rows tall; widths vary. Patterns use '█' for an
  // "on" cell and ' ' for "off". Layout joins glyphs with a single-cell gap.
  static const _rows = 5;
  static const _gap = 1;
  static const _glyphs = <String, List<String>>{
    '0': ['███', '█ █', '█ █', '█ █', '███'],
    '1': [' █ ', '██ ', ' █ ', ' █ ', '███'],
    '2': ['███', '  █', '███', '█  ', '███'],
    '3': ['███', '  █', '███', '  █', '███'],
    '4': ['█ █', '█ █', '███', '  █', '  █'],
    '5': ['███', '█  ', '███', '  █', '███'],
    '6': ['███', '█  ', '███', '█ █', '███'],
    '7': ['███', '  █', '  █', '  █', '  █'],
    '8': ['███', '█ █', '███', '█ █', '███'],
    '9': ['███', '█ █', '███', '  █', '███'],
    ':': [' ', '█', ' ', '█', ' '],
    '.': [' ', ' ', ' ', ' ', '█'],
    '-': ['   ', '   ', '███', '   ', '   '],
    ' ': ['  ', '  ', '  ', '  ', '  '],
  };

  static int _digitsWidth(String text) {
    var width = 0;
    for (var i = 0; i < text.length; i += 1) {
      final glyph = _glyphs[text[i]];
      if (glyph == null) return -1;
      width += glyph[0].length;
      if (i > 0) width += _gap;
    }
    return width;
  }

  List<List<String>>? _cachedGlyphs;
  int _cachedWidth = 0;

  void _prepare() {
    if (_cachedGlyphs != null) return;
    final glyphs = <List<String>>[];
    var w = 0;
    for (var i = 0; i < _text.length; i++) {
      final ch = _text[i];
      final g = _glyphs[ch];
      if (g == null) {
        throw ArgumentError.value(
          _text,
          'text',
          'Digits supports only characters in "0-9:.- ".',
        );
      }
      glyphs.add(g);
      w += g[0].length;
      if (i > 0) w += _gap;
    }
    _cachedGlyphs = glyphs;
    _cachedWidth = w;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    _cachedGlyphs = null;
    _prepare();
    return constraints.constrain(CellSize(_cachedWidth, _rows));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) {
    _prepare();
    return _cachedWidth;
  }

  @override
  int computeMaxIntrinsicHeight(int? width) => _rows;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.cols == 0 || size.rows == 0) return;
    _prepare();
    final glyphs = _cachedGlyphs!;
    final maxCol = offset.col + size.cols;
    final maxRow = offset.row + size.rows;

    var col = offset.col;
    for (var gi = 0; gi < glyphs.length; gi++) {
      if (gi > 0) col += _gap;
      final glyph = glyphs[gi];
      final glyphW = glyph[0].length;
      for (var r = 0; r < _rows; r++) {
        final destRow = offset.row + r;
        if (destRow >= maxRow) break;
        for (var c = 0; c < glyphW; c++) {
          final destCol = col + c;
          if (destCol >= maxCol) break;
          if (glyph[r][c] != ' ') {
            buffer.writeGrapheme(
              CellOffset(destCol, destRow),
              '█',
              style: _style,
            );
          } else if (_offGlyph != null) {
            buffer.writeGrapheme(
              CellOffset(destCol, destRow),
              _offGlyph!,
              style: const CellStyle(dim: true),
            );
          }
        }
      }
      col += glyphW;
    }
  }
}
