import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

const _showcaseSize = CellSize(108, 34);

CellStyle _styleAt(FleuryTester tester, String text) {
  final buffer = tester.render(size: _showcaseSize);
  for (var row = 0; row < buffer.size.rows; row++) {
    final line = StringBuffer();
    for (var col = 0; col < buffer.size.cols; col++) {
      line.write(buffer.atColRow(col, row).grapheme ?? ' ');
    }
    final col = line.toString().indexOf(text);
    if (col >= 0) return buffer.atColRow(col, row).style;
  }
  throw StateError('Could not find "$text" in the rendered showcase.');
}

void main() {
  testWidgets('theme studio compares presets and exposes a custom editor', (
    tester,
  ) async {
    tester.viewportSize = _showcaseSize;
    tester.pumpWidget(const ThemingShowcaseApp());

    String rendered() =>
        tester.renderToString(size: _showcaseSize, emptyMark: ' ');

    expect(rendered(), contains('THEME STUDIO'));
    expect(rendered(), contains('Nord'));
    expect(rendered(), contains('SEMANTIC ROLES'));
    expect(rendered(), contains('LIVE WIDGET GALLERY'));
    expect(rendered(), contains('api-gateway'));
    expect(rendered(), contains('Production'));
    expect(rendered(), isNot(contains('EnvironmentProduction')));
    expect(rendered(), matches(RegExp(r'Environment\s+Production')));
    expect(rendered(), contains('Deployment'));
    expect(rendered(), contains('42%'));
    expect(rendered(), contains('Deploy'));
    expect(rendered(), contains('Unavailable'));

    tester.sendKey(const KeyEvent(KeyCode.enter));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(rendered(), contains('rendered by Dracula'));
    tester.sendKey(const KeyEvent(KeyCode.escape));
    expect(rendered(), contains('rendered by Nord'));

    await tester.button('Theme').setValue('Custom');

    expect(rendered(), contains('CUSTOM THEME'));
    expect(rendered(), contains('Dark'));
    expect(rendered(), contains('Border'));
    expect(rendered(), contains('Rounded'));
    expect(rendered(), contains('Theme colors'));
    expect(rendered(), contains('Role'));
    expect(rendered(), contains('Primary'));
    expect(rendered(), contains('Primary color'));
    expect(rendered(), contains('ANSI palette'));
    expect(rendered(), contains('Headings, selected values, and'));
    expect(rendered(), contains('primary actions.'));
    expect(rendered(), contains('Reset custom theme'));

    await tester.button('Border').setValue('Double-line');
    expect(rendered(), contains('╔'));
    expect(rendered(), contains('═'));
    expect(rendered(), contains('Double-line border'));

    expect(
      tester.target(role: SemanticRole.list, label: 'Primary color'),
      hasCount(1),
    );

    await tester
        .target(role: SemanticRole.radio, label: 'Primary: ANSI 7 (#E5E5E5)')
        .select();
    expect(_styleAt(tester, 'Form controls').foreground, const AnsiColor(7));
    expect(
      tester.target(role: SemanticRole.list, label: 'Primary color'),
      hasValue('Primary: ANSI 7 (#E5E5E5)'),
    );

    await tester.button('Palette role').setValue('Error');
    expect(rendered(), contains('Error color'));
    expect(
      tester.target(role: SemanticRole.list, label: 'Error color'),
      hasCount(1),
    );

    await tester.button('Reset custom theme').press();
    expect(
      tester.target(role: SemanticRole.list, label: 'Error color'),
      hasValue('Error: ANSI 9 (#FF0000)'),
    );

    await tester.field('Service name').fill('');
    expect(rendered(), contains('Service name is required.'));
    expect(
      tester.field('Service name').snapshot.validationError,
      'Service name is required.',
    );
  });
}
