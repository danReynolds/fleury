import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<String> _rows(FleuryTester tester, int cols, int rows) => tester
    .renderToString(size: CellSize(cols, rows), emptyMark: ' ')
    .split('\n');

void main() {
  group('Digits', () {
    testWidgets("renders '12:34' as a 5-row glyph block", (tester) {
      tester.pumpWidget(
        const SizedBox(width: 17, height: 5, child: Digits('12:34')),
      );
      final out = _rows(tester, 17, 5);
      // 5 rows, glyphs laid out side-by-side with single-cell gaps.
      expect(out[0], ' █  ███   ███ █ █');
      expect(out[1], '██    █ █   █ █ █');
      expect(out[2], ' █  ███   ███ ███');
      expect(out[3], ' █  █   █   █   █');
      expect(out[4], '███ ███   ███   █');
    });

    testWidgets('uses the explicit color', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 3,
          height: 5,
          child: Digits('8', color: AnsiColor(2)),
        ),
      );
      final cell = tester.render(size: const CellSize(3, 5)).atColRow(0, 0);
      expect(cell.style.foreground, const AnsiColor(2));
    });

    testWidgets('throws on unsupported characters', (tester) {
      tester.pumpWidget(
        const SizedBox(width: 5, height: 5, child: Digits('abc')),
      );
      expect(
        () => tester.render(size: const CellSize(5, 5)),
        throwsArgumentError,
      );
    });

    testWidgets('exposes the underlying text semantically', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 17,
          height: 5,
          child: Digits('12:34', semanticLabel: 'Clock'),
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.text,
        label: 'Clock',
        value: '12:34',
      );
      expect(node.value, '12:34');

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.text,
        label: 'Clock',
        value: '12:34',
      );
      expect(fallback.value, '12:34');
    });
  });
}
