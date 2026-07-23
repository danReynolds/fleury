import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/src/theme_gallery.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('ThemeGallery', () {
    testWidgets('renders a themed sample with a palette switcher', (tester) {
      tester.pumpWidget(const ThemeGallery());

      final output = tester.renderToString(
        size: const CellSize(74, 30),
        emptyMark: ' ',
      );

      // The dropdown shows the initially-selected palette...
      expect(output, contains(ThemePalettes.all.first.name));
      // ...and the sample UI renders under it: title, a role swatch, a button,
      // and a status line.
      expect(output, contains('Deploy Console'));
      expect(output, contains('primary'));
      expect(output, contains('Deploy'));
      expect(output, contains('success'));
    });
  });
}
