import 'package:fleury_peer_nocterm_sb2_text_editing/text_editing_app.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isEmpty;

void main() {
  test('Nocterm SB.2 fixture exercises editing adapters', () async {
    await testNocterm('SB.2 Nocterm text editing fixture', (tester) async {
      final fixture = Sb2TextEditingFixture.generate(textChars: 2048);
      await tester.pumpComponent(Sb2TextEditingApp(fixture: fixture));
      final state = tester.findState<Sb2TextEditingState>();

      await tester.enterText(' --verbose');
      expect(state.composer.text, contains('--verbose'));

      state.focusEditor();
      state.moveEditorCursorToEnd();
      await tester.pump();
      for (var i = 0; i < 4; i += 1) {
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.arrowLeft,
            modifiers: ModifierKeys(shift: true),
          ),
        );
      }
      await tester.enterText(fixture.selectionReplacement);
      expect(state.editor.text, contains(fixture.selectionReplacement));

      await tester.sendKeyEvent(
        const KeyboardEvent(
          logicalKey: LogicalKey.keyZ,
          modifiers: ModifierKeys(ctrl: true),
        ),
      );
      expect(state.editor.text, isNot(contains(fixture.selectionReplacement)));

      await tester.sendKeyEvent(
        const KeyboardEvent(
          logicalKey: LogicalKey.keyY,
          modifiers: ModifierKeys(ctrl: true),
        ),
      );
      expect(state.editor.text, contains(fixture.selectionReplacement));

      ClipboardManager.copy(fixture.pasteText);
      await tester.sendKeyEvent(
        const KeyboardEvent(
          logicalKey: LogicalKey.keyV,
          modifiers: ModifierKeys(ctrl: true),
        ),
      );
      expect(state.editor.text, contains(fixture.pasteMarker));

      state.focusComposer();
      state.setComposerText('git che');
      await tester.pump();
      await tester.sendTab();
      expect(state.composer.text, 'git checkout');
      expect(state.completionAccepted, isTrue);

      state.setComposerText(fixture.historyDraft);
      await tester.pump();
      await tester.sendArrowUp();
      expect(state.composer.text, fixture.historyEntries.last);
      await tester.sendArrowDown();
      expect(state.composer.text, fixture.historyDraft);

      state.focusSecret();
      await tester.pump();
      expect(tester.terminalState.containsText(fixture.secretText), isFalse);
    });
  });
}
