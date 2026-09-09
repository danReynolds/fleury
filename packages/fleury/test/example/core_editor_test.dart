import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../../example/core_editor.dart';
import '../support/harness.dart';

void main() {
  testWidgets('search recovers from empty results and arrows transfer focus', (
    tester,
  ) {
    tester.pumpWidget(const CoreEditor());
    tester.type('missing');
    expect(tester.renderToString(), contains('No matches'));
    tester.press(.home);
    tester.press(.shift.end);
    tester.press(.backspace);
    tester.press(.down);
    expect(
      tester
          .semantics()
          .single(label: 'Search', role: SemanticRole.textField)
          .focused,
      isFalse,
    );
    tester.press(.up);
    expect(
      tester
          .semantics()
          .single(label: 'Search', role: SemanticRole.textField)
          .focused,
      isTrue,
    );
    tester.press(.down);
    tester.press(.enter);
    expect(
      tester
          .semantics()
          .single(label: 'Value', role: SemanticRole.textField)
          .focused,
      isTrue,
    );
    tester.press(.home);
    tester.press(.shift.end);
    tester.paste('Updated');
    tester.press(.ctrl.s);
    expect(tester.renderToString(), contains('Saved'));
    tester.press(.down);
    tester.press(.enter);
    expect(
      tester
          .semantics()
          .single(label: 'Value', role: SemanticRole.textField)
          .value,
      'Updated',
    );
  });

  testWidgets('compact confirmation starts on Cancel and preserves the draft', (
    tester,
  ) async {
    tester.pumpWidget(const CoreEditor());
    tester.press(.down);
    tester.press(.enter);
    tester.press(.home);
    tester.press(.shift.end);
    tester.type('draft');
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Delete…',
    );
    expect(
      tester
          .semantics()
          .single(label: 'Cancel', role: SemanticRole.button)
          .focused,
      isTrue,
    );
    final lines = tester
        .renderToString(size: const CellSize(80, 28), emptyMark: ' ')
        .split('\n');
    expect(lines.where((line) => line.trim().isNotEmpty).length, lessThan(10));
    tester.press(.escape);
    expect(
      tester
          .semantics()
          .single(label: 'Value', role: SemanticRole.textField)
          .value,
      'draft',
    );
  });
}
