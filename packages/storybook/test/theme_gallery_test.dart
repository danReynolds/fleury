import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/src/theme_gallery.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

/// Cells painted in [color], as a cheap proxy for "the sample is wearing this
/// palette" — the mock app's text does not change between themes, only its
/// colours do.
int _cellsColored(FleuryTester tester, Color color, CellSize size) {
  final buffer = tester.render(size: size);
  var count = 0;
  for (var r = 0; r < buffer.size.rows; r++) {
    for (var c = 0; c < buffer.size.cols; c++) {
      final style = buffer.atColRow(c, r).style;
      if (style.foreground == color || style.background == color) count++;
    }
  }
  return count;
}

/// First screen position of [needle], for aiming a click.
({int col, int row})? _find(FleuryTester tester, String needle, CellSize size) {
  final buffer = tester.render(size: size);
  for (var r = 0; r < buffer.size.rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < buffer.size.cols; c++) {
      sb.write(buffer.atColRow(c, r).grapheme ?? ' ');
    }
    final idx = sb.toString().indexOf(needle);
    if (idx >= 0) return (col: idx, row: r);
  }
  return null;
}

/// Click at a screen cell (press + release), the way a user opens the picker.
void _click(FleuryTester tester, ({int col, int row}) at) {
  for (final kind in <MouseEventKind>[
    MouseEventKind.down,
    MouseEventKind.up,
  ]) {
    tester.sendMouse(
      MouseEvent(
        kind: kind,
        button: MouseButton.left,
        col: at.col,
        row: at.row,
      ),
    );
  }
}

void main() {
  const size = CellSize(84, 34);

  group('ThemeGallery', () {
    testWidgets('renders a themed mock app with a palette switcher', (tester) {
      tester.pumpWidget(const ThemeGallery());

      final output = tester.renderToString(size: size, emptyMark: ' ');

      // The dropdown shows the initially-selected palette...
      expect(output, contains(ThemePalettes.all.first.name));
      // ...and the mock app renders under it: both panes, the services table,
      // a button, and the palette legend.
      expect(output, contains('Deploy Console'));
      expect(output, contains('Activity'));
      expect(output, contains('api-gateway'));
      expect(output, contains('Deploy'));
      expect(output, contains('primary'));
      // The ✓ status glyph is a text-presentation dingbat (width 1); it renders
      // without desyncing the row now that the width resolver classifies it.
      expect(output, contains('✓ running'));
    });

    testWidgets('the sample wears the selected palette', (tester) {
      tester.pumpWidget(const ThemeGallery());
      final first = ThemePalettes.all.first.data.colorScheme;
      expect(
        _cellsColored(tester, first.primary, size),
        greaterThan(0),
        reason: 'the initial palette should paint the sample',
      );
    });

    testWidgets('arrowing the dropdown live-previews without committing', (
      tester,
    ) {
      tester.pumpWidget(const ThemeGallery());
      final themes = ThemePalettes.all;
      final second = themes[1];

      // Open the switcher, then move the highlight one down.
      _click(tester, _find(tester, themes.first.name, size)!);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // highlight #2

      expect(
        _cellsColored(tester, second.data.colorScheme.primary, size),
        greaterThan(0),
        reason: 'the highlighted palette should paint the sample immediately, '
            'before any Enter',
      );

      // Esc abandons the preview; the sample goes back to the applied palette.
      tester.sendKey(const KeyEvent(KeyCode.escape));
      expect(
        _cellsColored(tester, themes.first.data.colorScheme.primary, size),
        greaterThan(0),
        reason: 'dismissing restores the applied palette',
      );
    });
  });
}
