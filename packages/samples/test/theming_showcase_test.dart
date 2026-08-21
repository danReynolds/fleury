import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('theme studio compares presets and exposes a custom editor', (
    tester,
  ) async {
    tester.pumpWidget(const ThemingShowcaseApp());

    String rendered() =>
        tester.renderToString(size: const CellSize(108, 34), emptyMark: ' ');

    expect(rendered(), contains('THEME STUDIO'));
    expect(rendered(), contains('Nord'));
    expect(rendered(), contains('SEMANTIC ROLES'));
    expect(rendered(), contains('LIVE WIDGET GALLERY'));
    expect(rendered(), contains('api-gateway'));
    expect(rendered(), contains('Production'));
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
    expect(rendered(), contains('rounded'));
    expect(rendered(), contains('Accent'));
    expect(rendered(), contains('Focus'));
    expect(rendered(), contains('Success'));
    expect(rendered(), contains('Warning'));
    expect(rendered(), contains('Error'));
    expect(rendered(), contains('Info'));
    expect(rendered(), contains('Reset custom theme'));

    expect(
      tester.semantics().single(role: SemanticRole.list, label: 'Accent color'),
      isNotNull,
    );
    expect(
      tester.semantics().single(role: SemanticRole.list, label: 'Error color'),
      isNotNull,
    );

    await tester.invokeSemanticAction(
      SemanticAction.select,
      role: SemanticRole.radio,
      label: 'Accent option 8',
    );
    tester.pump();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.list, label: 'Accent color')
          .value,
      'Accent option 8',
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
          .single(role: SemanticRole.list, label: 'Accent color')
          .value,
      'Accent option 7',
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
