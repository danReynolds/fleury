import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;
import 'package:test/test.dart';

void main() {
  for (final rich in [false, true]) {
    test(
      'resized unwrapped text matches fresh layout and selection, rich=$rich',
      () {
        RenderObject create(
          String source,
          TextPresentationPolicy policy,
          bool wrap,
          int? maxLines,
        ) => rich
            ? RenderRichText(
                span: TextSpan(text: source),
                base: CellStyle.none,
                textPolicy: policy,
                softWrap: wrap,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              )
            : RenderText(
                text: source,
                textPolicy: policy,
                softWrap: wrap,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              );
        final retained = create(
          'initial',
          TextPresentationPolicy.spec,
          false,
          null,
        );
        for (final source in ['a界\nb 👩‍💻\n\nlongest line here', '', '─\n…']) {
          for (final policy in [
            TextPresentationPolicy.spec,
            const TextPresentationPolicy(widths: CellWidthPolicy.cjk),
            const TextPresentationPolicy(lowering: ClusterLowering.split),
          ]) {
            for (final wrap in [true, false]) {
              for (final maxLines in [null, 2, 1]) {
                if (retained is RenderText) {
                  retained
                    ..text = source
                    ..textPolicy = policy
                    ..softWrap = wrap
                    ..maxLines = maxLines;
                } else {
                  (retained as RenderRichText)
                    ..setSpan(TextSpan(text: source), CellStyle.none)
                    ..textPolicy = policy
                    ..softWrap = wrap
                    ..maxLines = maxLines;
                }
                final selectable = retained as Selectable;
                for (final bounds in [
                  const CellConstraints(maxCols: 3),
                  const CellConstraints(),
                  const CellConstraints(maxCols: 0),
                  const CellConstraints(minCols: 8, maxRows: 1),
                  const CellConstraints(maxCols: 1, maxRows: 0),
                  const CellConstraints(maxCols: 12),
                ]) {
                  final fresh = create(source, policy, wrap, maxLines);
                  expect(retained.layout(bounds), fresh.layout(bounds));
                  final freshSelectable = fresh as Selectable;
                  final actual = CellBuffer(const CellSize(16, 6));
                  final expected = CellBuffer(actual.size);
                  void paint() {
                    actual.clear();
                    expected.clear();
                    retained.paint(actual, const CellOffset(1, 1));
                    fresh.paint(expected, const CellOffset(1, 1));
                  }

                  selectable.dispatchSelectionEvent(
                    const SelectionClearEvent(),
                  );
                  paint();
                  for (final event in [
                    const SelectionEdgeUpdateEvent(
                      globalPosition: CellOffset(2, 1),
                      isStart: true,
                    ),
                    const SelectionEdgeUpdateEvent(
                      globalPosition: CellOffset(6, 3),
                      isStart: false,
                    ),
                  ]) {
                    selectable.dispatchSelectionEvent(event);
                    freshSelectable.dispatchSelectionEvent(event);
                  }
                  // Keep the pointer selection across a second resize, so line
                  // identity must refresh its relation to the new screen bounds.
                  const narrow = CellConstraints(maxCols: 2, maxRows: 2);
                  fresh.markNeedsLayout();
                  expect(retained.layout(narrow), fresh.layout(narrow));
                  paint();
                  expect(
                    selectable.getSelectedContent()?.plainText,
                    freshSelectable.getSelectedContent()?.plainText,
                  );
                  for (var row = 0; row < 6; row++) {
                    for (var col = 0; col < 16; col++) {
                      expect(
                        actual.atColRow(col, row),
                        expected.atColRow(col, row),
                      );
                    }
                  }
                  const all = SelectionGranularEvent(
                    granularity: SelectionGranularity.all,
                  );
                  selectable.dispatchSelectionEvent(all);
                  freshSelectable.dispatchSelectionEvent(all);
                  expect(
                    selectable.getSelectedContent()?.plainText,
                    freshSelectable.getSelectedContent()?.plainText,
                  );
                }
              }
            }
          }
        }
      },
    );
  }
}
