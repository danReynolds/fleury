import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;
import 'package:test/test.dart';

void main() {
  for (final rich in [false, true]) {
    test('highlight cells share immutable styles, rich=$rich', () {
      const base = CellStyle(foreground: AnsiColor(3), inverse: false);
      final RenderObject render = rich
          ? RenderRichText(
              span: const TextSpan(text: 'ab漢\ncd字'),
              base: base,
            )
          : RenderText(text: 'ab漢\ncd字', style: base);
      render.layout(const CellConstraints(maxCols: 8));
      final buffer = CellBuffer(const CellSize(8, 2));
      render.paint(buffer, CellOffset.zero);
      (render as Selectable).dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      buffer.clear();
      render.paint(buffer, CellOffset.zero);
      for (var row = 0; row < 2; row++) {
        final style = buffer.atColRow(0, row).style;
        expect(style, const CellStyle(foreground: AnsiColor(3), inverse: true));
        for (var col = 1; col < 4; col++) {
          expect(identical(buffer.atColRow(col, row).style, style), isTrue);
        }
      }
      expect(
        base.inverse,
        isFalse,
        reason: 'highlighting must not mutate source styles',
      );
    });

    test('selection range resolves once per paint, rich=$rich', () {
      var reads = 0;
      final content = List.filled(1000, 'a漢b').join('\n');
      final RenderObject render = rich
          ? _RangeCountingRichText(content, () => reads++)
          : _RangeCountingText(content, () => reads++);
      render.layout(const CellConstraints(maxCols: 10));
      final selectable = render as Selectable;
      final buffer = CellBuffer(const CellSize(10, 3));
      render.paint(buffer, const CellOffset(0, -400));
      selectable.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      reads = 0;
      buffer.clear();
      render.paint(buffer, const CellOffset(0, -400));
      expect(reads, 1);
      expect(buffer.atColRow(0, 0).style.inverse, isTrue);
      expect(buffer.atColRow(2, 2).style.inverse, isTrue);
      expect(selectable.getSelectedContent()?.plainText, content);

      selectable.dispatchSelectionEvent(const SelectionClearEvent());
      reads = 0;
      buffer.clear();
      render.paint(buffer, const CellOffset(0, -400));
      expect(reads, 1);
      expect(buffer.atColRow(0, 0).style.inverse, isFalse);
    });
  }
  test('paint measures only rows intersecting the buffer', () {
    final resolver = _CountingResolver();
    final render = RenderText(
      text: List.filled(1000, 'a漢👩‍💻').join('\n'),
      widthResolver: resolver,
    )..layout(const CellConstraints(maxCols: 20));
    for (final row in [0, -400, -997]) {
      resolver.calls = 0;
      render.paint(CellBuffer(const CellSize(20, 3)), CellOffset(0, row));
      expect(
        resolver.calls,
        9,
        reason: 'three graphemes on three visible rows',
      );
    }
    for (final row in [3, -1000]) {
      resolver.calls = 0;
      render.paint(
        CellBuffer(const CellSize(20, 3)),
        CellOffset(0, row),
        screenOffset: const CellOffset(10, 20),
        clipRect: CellRect.fromLTWH(10, 20, 20, 3),
      );
      expect(resolver.calls, 0);
      expect(
        render.cellBounds,
        CellRect.fromLTWH(10, 20, render.size.cols, 1000),
        reason: 'hidden paint must still register full selection geometry',
      );
    }
  });

  for (final rich in [false, true]) {
    test('viewport paint equals full-paint crop with selection, rich=$rich', () {
      const content = 'first a漢\n─ wide 👩‍💻 text\n\nlast e\u0301 characters';
      for (final policy in [
        TextPresentationPolicy.spec,
        const TextPresentationPolicy(widths: CellWidthPolicy.cjk),
      ]) {
        for (final wrap in [true, false]) {
          for (final align in rich ? [TextAlign.left] : TextAlign.values) {
            for (final overflow in TextOverflow.values) {
              for (final maxLines in <int?>[null, 2]) {
                final RenderObject render = rich
                    ? RenderRichText(
                        span: const TextSpan(
                          text: 'first a漢\n',
                          children: [
                            TextSpan(
                              text: '─ wide 👩‍💻 text\n\n',
                              style: CellStyle(bold: true),
                            ),
                            TextSpan(
                              text: 'last e\u0301 characters',
                              style: CellStyle(inverse: false),
                            ),
                          ],
                        ),
                        base: const CellStyle(foreground: AnsiColor(3)),
                        textPolicy: policy,
                        softWrap: wrap,
                        overflow: overflow,
                        maxLines: maxLines,
                      )
                    : RenderText(
                        text: content,
                        textPolicy: policy,
                        softWrap: wrap,
                        textAlign: align,
                        overflow: overflow,
                        maxLines: maxLines,
                        style: const CellStyle(foreground: AnsiColor(3)),
                      );
                render.layout(const CellConstraints(maxCols: 8));
                final selectable = render as Selectable;
                for (final selected in [false, true]) {
                  final full = CellBuffer(const CellSize(8, 40));
                  const screen = CellOffset(10, 20);
                  render.paint(full, CellOffset.zero, screenOffset: screen);
                  if (selected) {
                    selectable.dispatchSelectionEvent(
                      const SelectionEdgeUpdateEvent(
                        globalPosition: CellOffset(11, 21),
                        isStart: true,
                      ),
                    );
                    selectable.dispatchSelectionEvent(
                      const SelectionEdgeUpdateEvent(
                        globalPosition: CellOffset(13, 23),
                        isStart: false,
                      ),
                    );
                    full.clear();
                    render.paint(full, CellOffset.zero, screenOffset: screen);
                  }
                  for (var top = -2; top <= render.size.rows + 1; top++) {
                    final actual = CellBuffer(const CellSize(8, 2));
                    // Buffer and screen coordinates intentionally differ: a
                    // scroll scratch must not use the screen clip as its grid.
                    final clip = CellRect.fromLTWH(10, 20 + top, 8, 2);
                    render.paint(
                      actual,
                      CellOffset(0, -top),
                      screenOffset: screen,
                      clipRect: clip,
                    );
                    for (var row = 0; row < 2; row++) {
                      for (var col = 0; col < 8; col++) {
                        final sourceRow = top + row;
                        final expected = sourceRow < 0 || sourceRow >= 40
                            ? const Cell.empty()
                            : full.atColRow(col, sourceRow);
                        expect(
                          actual.atColRow(col, row),
                          expected,
                          reason:
                              '$policy wrap=$wrap align=$align $overflow '
                              'maxLines=$maxLines selected=$selected '
                              'top=$top cell=($col,$row)',
                        );
                      }
                    }
                    expect(
                      selectable.cellBounds,
                      CellRect(offset: screen, size: render.size),
                    );
                    expect(
                      selectable.visibleBounds,
                      selectable.cellBounds!.intersect(clip),
                    );
                  }
                  selectable.dispatchSelectionEvent(
                    const SelectionClearEvent(),
                  );
                }
              }
            }
          }
        }
      }
    });
  }
}

final class _CountingResolver implements WidthResolver {
  var calls = 0;
  @override
  int widthOfGrapheme(String grapheme, CellWidthPolicy policy) {
    calls++;
    return const DefaultWidthResolver().widthOfGrapheme(grapheme, policy);
  }

  @override
  int widthOfText(String text, CellWidthPolicy policy) =>
      const DefaultWidthResolver().widthOfText(text, policy);
}

class _RangeCountingText extends RenderText {
  _RangeCountingText(String text, this.onRead) : super(text: text);
  final void Function() onRead;
  @override
  ({int start, int end})? getSelectionRange() {
    onRead();
    return super.getSelectionRange();
  }
}

class _RangeCountingRichText extends RenderRichText {
  _RangeCountingRichText(String text, this.onRead)
    : super(
        span: TextSpan(text: text),
        base: CellStyle.none,
      );
  final void Function() onRead;
  @override
  ({int start, int end})? getSelectionRange() {
    onRead();
    return super.getSelectionRange();
  }
}
