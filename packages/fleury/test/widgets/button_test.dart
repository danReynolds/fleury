// Basic actions require only fleury_core, including on a browser surface.
import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'core button has styled spaces, semantics and keyboard activation',
    (tester) {
      var presses = 0;
      tester.pumpWidget(
        Button(label: 'New key', autofocus: true, onPressed: () => presses++),
      );
      final buffer = tester.render(size: const CellSize(14, 1));
      for (var col = 0; col < 11; col++) {
        expect(buffer.atColRow(col, 0).style.inverse, isTrue);
      }
      tester.press(.enter);
      tester.press(.space);
      expect(presses, 2);
      expect(
        tester.semantics().single(role: SemanticRole.button).label,
        'New key',
      );
    },
  );

  testWidgets('Tab traverses core field and button in both directions', (
    tester,
  ) {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            TextInput(focusNode: field, autofocus: true),
            Button(label: 'Save', focusNode: button, onPressed: () {}),
          ],
        ),
      ),
    );
    expect(field.hasFocus, isTrue);
    tester.press(.tab);
    expect(button.hasFocus, isTrue);
    tester.press(.shift.tab);
    expect(field.hasFocus, isTrue);
  });
}
