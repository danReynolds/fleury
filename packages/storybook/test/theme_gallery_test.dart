import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/src/theme_gallery.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('ThemeGallery', () {
    testWidgets('renders every built-in palette with sample content', (
      tester,
    ) {
      tester.pumpWidget(const ThemeGallery());

      final output = tester.renderToString(
        size: const CellSize(74, 80),
        emptyMark: ' ',
      );

      // Every built-in theme is present by name...
      for (final named in ThemePalettes.all) {
        expect(output, contains(named.name), reason: 'missing ${named.name}');
      }
      // ...with the role swatches and sample content beside each.
      expect(output, contains('primary'));
      expect(output, contains('The quick brown fox'));
      expect(output, contains('✓ success'));
    });
  });
}
