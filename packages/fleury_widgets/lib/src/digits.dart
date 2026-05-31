import 'package:fleury/fleury.dart';

/// Large-numeral display for clocks, timers, counters — the "calculator
/// face" look popularized by Textual's Digits widget. Each digit is drawn
/// as a 5-row glyph from block characters; `:` and ` ` are supported for
/// time-of-day strings.
///
/// ```dart
/// Digits('12:34', color: theme.colorScheme.primary)
/// ```
///
/// Throws if [text] contains a character outside `[0-9: ]`.
class Digits extends StatelessWidget {
  const Digits(this.text, {super.key, this.style, this.color});

  final String text;
  final CellStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved =
        style ?? CellStyle(foreground: color ?? theme.colorScheme.primary);
    return _RawDigits(text: text, style: resolved);
  }
}

class _RawDigits extends LeafRenderObjectWidget {
  const _RawDigits({required this.text, required this.style});

  final String text;
  final CellStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDigits(text: text, style: style);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDigits renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style;
  }
}

/// Render object behind [Digits]. See its docs.
class RenderDigits extends RenderObject {
  RenderDigits({required String text, required CellStyle style})
    : _text = text,
      _style = style;

  String _text;
  set text(String v) {
    _text = v;
    markNeedsPaint();
  }

  CellStyle _style;
  set style(CellStyle v) {
    _style = v;
    markNeedsPaint();
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
    ' ': ['  ', '  ', '  ', '  ', '  '],
  };

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
          'Digits supports only characters in "0-9: ".',
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
          }
        }
      }
      col += glyphW;
    }
  }
}
