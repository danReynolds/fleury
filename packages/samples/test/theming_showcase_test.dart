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

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Theme',
      payload: 'Custom',
    );
    tester.pump();

    expect(rendered(), contains('CUSTOM THEME'));
    expect(rendered(), contains('Dark'));
    expect(rendered(), contains('Border'));
    expect(rendered(), contains('Rounded'));
    expect(rendered(), contains('Palette'));
    expect(rendered(), contains('Role'));
    expect(rendered(), contains('Accent'));
    expect(rendered(), contains('Accent color'));
    expect(rendered(), contains('Headings, selection, and primary'));
    expect(rendered(), contains('Reset custom theme'));

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Border',
      payload: 'Double-line',
    );
    tester.pump();
    expect(rendered(), contains('╔'));
    expect(rendered(), contains('═'));
    expect(rendered(), contains('Double-line border'));

    expect(
      tester.semantics().single(role: SemanticRole.list, label: 'Accent color'),
      isNotNull,
    );

    await tester.invokeSemanticAction(
      SemanticAction.select,
      role: SemanticRole.radio,
      label: 'Accent option 8',
    );
    tester.pump();
    expect(_styleAt(tester, 'Form controls').foreground, const AnsiColor(7));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.list, label: 'Accent color')
          .value,
      'Accent option 8',
    );

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Palette role',
      payload: 'Error',
    );
    tester.pump();
    expect(rendered(), contains('Error color'));
    expect(
      tester.semantics().single(role: SemanticRole.list, label: 'Error color'),
      isNotNull,
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Reset custom theme',
    );
    tester.pump();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.list, label: 'Error color')
          .value,
      'Error option 10',
    );

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.textField,
      label: 'Service name',
      payload: '',
    );
    tester.pump();
    expect(rendered(), contains('Service name is required.'));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Service name')
          .validationError,
      'Service name is required.',
    );
  });
}
