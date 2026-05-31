import 'package:meta/meta.dart';

import 'cell.dart';

/// Visual style for a [BoxBorder].
///
/// - [single] — light single-line box drawing (`┌─┐│└─┘`).
/// - [double] — heavy double-line box drawing (`╔═╗║╚═╝`).
/// - [rounded] — single-line edges with rounded corners
///   (`╭─╮│╰─╯`).
/// - [ascii] — ASCII fallback (`+-+|+-+`) for terminals that don't
///   render box-drawing graphemes.
enum BorderStyle { single, double, rounded, ascii }

/// A four-sided border drawn around a box.
///
/// v0 always draws all four sides with the same [style] and
/// [cellStyle]. Per-side enables and per-side styles can be added
/// later if a real use case shows up.
@immutable
final class BoxBorder {
  const BoxBorder({
    this.style = BorderStyle.single,
    this.cellStyle = CellStyle.empty,
  });

  /// Box-drawing variant.
  final BorderStyle style;

  /// Cell style applied to the border glyphs (color, bold, etc.).
  final CellStyle cellStyle;

  @override
  bool operator ==(Object other) =>
      other is BoxBorder &&
      other.style == style &&
      other.cellStyle == cellStyle;

  @override
  int get hashCode => Object.hash(style, cellStyle);
}

/// The six glyphs needed to draw a four-sided box.
@immutable
class BorderGlyphs {
  const BorderGlyphs({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.horizontal,
    required this.vertical,
  });

  final String topLeft;
  final String topRight;
  final String bottomLeft;
  final String bottomRight;
  final String horizontal;
  final String vertical;

  static BorderGlyphs forStyle(BorderStyle style) {
    return switch (style) {
      BorderStyle.single => _single,
      BorderStyle.double => _double,
      BorderStyle.rounded => _rounded,
      BorderStyle.ascii => _ascii,
    };
  }

  static const BorderGlyphs _single = BorderGlyphs(
    topLeft: '┌',
    topRight: '┐',
    bottomLeft: '└',
    bottomRight: '┘',
    horizontal: '─',
    vertical: '│',
  );
  static const BorderGlyphs _double = BorderGlyphs(
    topLeft: '╔',
    topRight: '╗',
    bottomLeft: '╚',
    bottomRight: '╝',
    horizontal: '═',
    vertical: '║',
  );
  static const BorderGlyphs _rounded = BorderGlyphs(
    topLeft: '╭',
    topRight: '╮',
    bottomLeft: '╰',
    bottomRight: '╯',
    horizontal: '─',
    vertical: '│',
  );
  static const BorderGlyphs _ascii = BorderGlyphs(
    topLeft: '+',
    topRight: '+',
    bottomLeft: '+',
    bottomRight: '+',
    horizontal: '-',
    vertical: '|',
  );
}
