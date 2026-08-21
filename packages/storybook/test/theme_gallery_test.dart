import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/src/theme_gallery.dart';
import 'package:fleury_themes/fleury_themes.dart';
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
  for (final kind in <MouseEventKind>[MouseEventKind.down, MouseEventKind.up]) {
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
      expect(output, contains(fleuryThemes.first.name));
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

    testWidgets('every themeable surface is demonstrated and named', (tester) {
      // The styleguide's contract: a theme author can see the whole surface
      // they own. If a ColorScheme role or ThemeData style field is added
      // without a demo, this fails — which is the point.
      tester.pumpWidget(const ThemeGallery());
      final output = tester.renderToString(
        size: const CellSize(84, 60),
        emptyMark: ' ',
      );

      for (final section in [
        'IN CONTEXT',
        'COLOUR ROLES',
        'TEXT STYLES',
        'CONTROLS',
      ]) {
        expect(output, contains(section), reason: 'missing section: $section');
      }
      // Every ColorScheme role, by name.
      for (final role in [
        'primary',
        'focus',
        'success',
        'warning',
        'error',
        'info',
        'foreground',
        'background',
        'surface',
      ]) {
        expect(output, contains(role), reason: 'undemoed colour role: $role');
      }
      // Every ThemeData text style, named after the field that produced it.
      for (final field in [
        'textStyle',
        'mutedStyle',
        'selectionStyle',
        'focusedStyle',
        'errorStyle',
        'interactionStyle',
      ]) {
        expect(output, contains(field), reason: 'undemoed style: $field');
      }
      expect(
        fleuryThemes.every((theme) => theme.data.interactionStyle == null),
        isTrue,
        reason: 'bundled themes currently inherit widget state defaults',
      );
      expect(output, contains('interactionStyle · unset (widget defaults)'));
      // The border style and the two panel focus states are called out, so
      // the chrome reads as a demonstrated state rather than an accident.
      expect(output, contains('borderStyle'));
      expect(output, contains('active'));
      expect(output, contains('at rest'));
      // Brightness is visible — it drives the surface fallback.
      expect(output, contains(fleuryThemes.first.data.brightness.name));
    });

    testWidgets('plain custom control styles are labelled truthfully', (
      tester,
    ) {
      tester.pumpWidget(
        const ThemeGallery(
          themes: [
            NamedTheme(
              'Custom',
              ThemeData(interactionStyle: CellStyle(foreground: Colors.cyan)),
            ),
          ],
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(84, 60),
        emptyMark: ' ',
      );
      expect(output, contains('interactionStyle · ThemeData.interactionStyle'));
      expect(output, isNot(contains('states · ThemeData.interactionStyle')));
    });

    testWidgets('the sample wears the selected palette', (tester) {
      tester.pumpWidget(const ThemeGallery());
      final first = fleuryThemes.first.data.colorScheme;
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
      final themes = fleuryThemes;
      final second = themes[1];

      // Open the switcher, then move the highlight one down.
      _click(tester, _find(tester, themes.first.name, size)!);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // highlight #2

      expect(
        _cellsColored(tester, second.data.colorScheme.primary, size),
        greaterThan(0),
        reason:
            'the highlighted palette should paint the sample immediately, '
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
