import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/cell_buffer.dart'
    show paintMeasuredGrapheme;
import 'package:test/test.dart';

void main() {
  test('measured placement matches policy-driven writes, cells and damage', () {
    const resolver = DefaultWidthResolver();
    const styles = [
      CellStyle.none,
      CellStyle(background: AnsiColor(4), inverse: true),
      CellStyle.interactive(
        base: CellStyle(foreground: AnsiColor(6)),
        focused: CellStyle(bold: true),
      ),
    ];
    for (final policy in [CellWidthPolicy.spec, CellWidthPolicy.cjk]) {
      for (final grapheme in ['', '\u0301', 'a', '界', '…', '👩‍💻']) {
        for (final style in styles) {
          for (var row = -1; row <= 2; row++) {
            for (var col = -1; col <= 6; col++) {
              CellBuffer populated() => CellBuffer(const CellSize(6, 2))
                ..writeText(CellOffset.zero, '界漢X')
                ..writeText(const CellOffset(0, 1), 'a界bc')
                ..resetDamageTracking();
              final actual = populated();
              final expected = populated();
              final advanced = paintMeasuredGrapheme(
                actual,
                col,
                row,
                grapheme,
                resolver.widthOfGrapheme(grapheme, policy),
                style,
              );
              expect(
                advanced,
                expected.writeGrapheme(
                  CellOffset(col, row),
                  grapheme,
                  policy: policy,
                  style: style,
                ),
              );
              expect(actual.damageBounds, expected.damageBounds);
              for (var r = 0; r < 2; r++) {
                for (var c = 0; c < 6; c++) {
                  expect(
                    actual.atColRow(c, r),
                    expected.atColRow(c, r),
                    reason: '$grapheme at ($col, $row), cell ($c, $r)',
                  );
                }
              }
            }
          }
        }
      }
    }
  });

  test('paint reuses layout line widths and measures each glyph once', () {
    final resolver = _CountingWidthResolver();
    final text = RenderText(text: 'a界b', widthResolver: resolver);
    final buffer = CellBuffer(const CellSize(8, 3));
    for (final content in ['a界b', '界\nx', 'abc def ghi', '─\n…']) {
      text.text = content;
      text.layout(const CellConstraints(maxCols: 4));
      resolver.reset();
      text.paint(buffer, CellOffset.zero);
      final calls = resolver.graphemeCalls;
      expect(calls, greaterThan(0));
      expect(resolver.textCalls, 0, reason: 'line widths belong to layout');
      resolver.reset();
      text.paint(buffer, CellOffset.zero);
      expect(resolver.graphemeCalls, calls);
      expect(resolver.textCalls, 0);
    }
    text
      ..text = 'a界b'
      ..layout(const CellConstraints(maxCols: 8));
    resolver.reset();
    text.paint(buffer, CellOffset.zero);
    expect(resolver.graphemeCalls, 3, reason: 'placement must not remeasure');
  });

  test('retained widths follow text, wrap, policy and alignment changes', () {
    final retained = RenderText(text: 'first');
    for (final content in ['a界b', 'ab cd ef', '─\n…', '', 'last']) {
      for (final policy in [
        TextPresentationPolicy.spec,
        const TextPresentationPolicy(widths: CellWidthPolicy.cjk),
      ]) {
        for (final wrap in [true, false]) {
          for (final align in TextAlign.values) {
            retained
              ..text = content
              ..textPolicy = policy
              ..softWrap = wrap
              ..textAlign = align
              ..maxLines = 2
              ..overflow = TextOverflow.ellipsis;
            final fresh = RenderText(
              text: content,
              textPolicy: policy,
              softWrap: wrap,
              textAlign: align,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
            for (final cols in [3, 8, 2]) {
              final constraints = CellConstraints.tight(CellSize(cols, 2));
              expect(retained.layout(constraints), fresh.layout(constraints));
              final actual = CellBuffer(const CellSize(8, 3));
              final expected = CellBuffer(actual.size);
              retained.paint(actual, const CellOffset(-1, 1));
              fresh.paint(expected, const CellOffset(-1, 1));
              for (var row = 0; row < 3; row++) {
                for (var col = 0; col < 8; col++) {
                  expect(
                    actual.atColRow(col, row),
                    expected.atColRow(col, row),
                  );
                }
              }
            }
          }
        }
      }
    }
  });
}

final class _CountingWidthResolver implements WidthResolver {
  var textCalls = 0;
  var graphemeCalls = 0;

  void reset() {
    textCalls = 0;
    graphemeCalls = 0;
  }

  @override
  int widthOfText(String text, CellWidthPolicy policy) {
    textCalls++;
    return const DefaultWidthResolver().widthOfText(text, policy);
  }

  @override
  int widthOfGrapheme(String grapheme, CellWidthPolicy policy) {
    graphemeCalls++;
    return const DefaultWidthResolver().widthOfGrapheme(grapheme, policy);
  }
}
