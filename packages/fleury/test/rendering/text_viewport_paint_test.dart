import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
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

  test('viewport paint equals a crop of full paint, including selection', () {
    const content = 'first a漢\n─ wide 👩‍💻 text\n\nlast e\u0301 characters';
    for (final policy in [
      TextPresentationPolicy.spec,
      const TextPresentationPolicy(widths: CellWidthPolicy.cjk),
    ]) {
      for (final wrap in [true, false]) {
        for (final align in TextAlign.values) {
          for (final overflow in TextOverflow.values) {
            for (final maxLines in <int?>[null, 2]) {
              final render = RenderText(
                text: content,
                textPolicy: policy,
                softWrap: wrap,
                textAlign: align,
                overflow: overflow,
                maxLines: maxLines,
                style: const CellStyle(foreground: AnsiColor(3)),
              )..layout(const CellConstraints(maxCols: 8));
              for (final selected in [false, true]) {
                final full = CellBuffer(const CellSize(8, 40));
                const screen = CellOffset(10, 20);
                render.paint(full, CellOffset.zero, screenOffset: screen);
                if (selected) {
                  render.dispatchSelectionEvent(
                    const SelectionEdgeUpdateEvent(
                      globalPosition: CellOffset(11, 21),
                      isStart: true,
                    ),
                  );
                  render.dispatchSelectionEvent(
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
                    render.cellBounds,
                    CellRect(offset: screen, size: render.size),
                  );
                  expect(
                    render.visibleBounds,
                    render.cellBounds!.intersect(clip),
                  );
                }
                render.dispatchSelectionEvent(const SelectionClearEvent());
              }
            }
          }
        }
      }
    }
  });
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
