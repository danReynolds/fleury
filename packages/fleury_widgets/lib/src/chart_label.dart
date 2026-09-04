import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_internal.dart' show projectText;

/// A single-line chart label, measured and painted with the same surface policy.
/// Plot symbols use a one-cell fallback; labels retain their Unicode text.
class ChartLabel {
  ChartLabel(String text, TextPresentationPolicy policy)
    : this._(
        projectText(
          sanitizeForDisplay(text.replaceAll(_lineBreaks, ' ')),
          policy: policy,
        ).displayText,
        policy.widths,
      );

  ChartLabel._(this.text, this.policy);

  final String text;
  final CellWidthPolicy policy;
  static const _resolver = DefaultWidthResolver();
  static final _lineBreaks = RegExp(r'[\r\n]');

  int get width => _resolver.widthOfText(text, policy);

  ChartLabel clip(int columns) {
    var used = 0;
    var end = 0;
    for (final grapheme in text.characters) {
      final width = _resolver.widthOfGrapheme(grapheme, policy);
      if (used + width > columns) break;
      used += width;
      end += grapheme.length;
    }
    return ChartLabel._(text.substring(0, end), policy);
  }

  void paint(CellBuffer buffer, CellOffset offset, CellStyle style) {
    if (offset.row < 0 || offset.row >= buffer.size.rows) return;
    var col = offset.col;
    for (final grapheme in text.characters) {
      final width = _resolver.widthOfGrapheme(grapheme, policy);
      if (col >= buffer.size.cols) break;
      if (col >= 0 && width > 0) {
        buffer.writeGrapheme(
          CellOffset(col, offset.row),
          grapheme,
          style: style,
          policy: policy,
        );
      }
      col += width;
    }
  }
}
