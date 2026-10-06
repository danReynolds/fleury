import 'package:fleury/fleury.dart';
import 'package:fleury_doc_examples/testing/draft_editor.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  // #docregion command-test
  testWidgets('saves the draft by its command ID', (tester) async {
    String? saved;
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (text) async => saved = text),
      ),
    );
    await tester.field('Draft').fill('Ready for review.');

    final result = await tester.invokeCommand(const CommandId('editor.save'));
    expect(result.completed, isTrue);
    expect(saved, 'Ready for review.');

    final again = await tester.invokeCommand(const CommandId('editor.save'));
    expect(again.status, CommandInvocationStatus.disabled);
  });
  // #enddocregion command-test

  // #docregion shortcut-test
  testWidgets('saves the draft with Ctrl+S', (tester) async {
    String? saved;
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (text) async => saved = text),
      ),
    );
    final editor = tester.target(type: DraftEditor);
    expect(editor.field('Draft'), isFocused);
    tester.type(' Ready for review.');
    tester.press(KeySequence.ctrl.s);
    await tester.settle();

    expect(saved, 'Ship the testing guide. Ready for review.');
    expect(tester.exists(text('All changes saved')), isTrue);
    expect(editor.button('Save'), isDisabled);
  });
  // #enddocregion shortcut-test
}
